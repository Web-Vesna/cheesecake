package MemcClient;

use strict;
use warnings;

use AnyEvent::Memcached;

use CakeConfig qw( service );

# TODO: PROCESS MEMCACHED ERRORS !!!

use Logger;

my %connections;

sub new {
	my ($class, $service_name, $packet_id) = @_;

	our %keys_in_process;
	our @keys_queue;
	our %delete_in_process;
	our @delete_queue;

	my $self = bless {
		keys_in_process		=> \%keys_in_process,
		keys_queue		=> \@keys_queue,
		delete_in_process	=> \%delete_in_process,
		delete_queue		=> \@delete_queue,

		logger => Logger->new("MemcachedClient", $service_name, $packet_id),
	}, $class;

	unless ($connections{$service_name}) {
		$self->establish_connection($service_name);
	}

	$self->{conn} = $connections{$service_name};

	return $self;
}

sub logger {
	return shift->{logger};
}

sub establish_connection {
	my ($self, $service_name) = @_;

	my ($host, $port, $prefix, $exptime) = @{service($service_name)}{qw( memc_host memc_port memc_prefix session_expire_time )};

	$self->logger->info("Initialization of a service connection");

	my $memc = AnyEvent::Memcached->new(
		servers => [ "$host:$port" ],
		namespace => "$prefix:_sid:",
	);

	my $memc2 = AnyEvent::Memcached->new(
		servers => [ "$host:$port" ],
		namespace => "$prefix:_uid:",
	);

	$connections{$service_name} = {
		sid_memc => $memc,
		uid_memc => $memc2,
		exptime => $exptime,
	};
}

sub get {
	my ($self, $key, $cb) = @_;
	return $self->{conn}{sid_memc}->get($key, cb => $cb);
}

sub _process_queue {
	my ($self, $set_queue, $delete_queue) = @_;

	$self->logger->info("Starting to process queued actions");

	# at first we should close old sessions and only then open new
	for (@$delete_queue) {
		$self->logger->info("Processing queued delete action for uid $_->[0]");
		$self->delete(@$_);
	}

	for (@$set_queue) {
		$self->logger->info("Processing queued set action for uid $_->[1]");
		$self->set(@$_);
	}

	$self->logger->info("Done processing queued actions");
}

sub set {
	my ($self, $sid, $uid, $value, $cb) = @_;

	if ($self->{delete_in_process}{$uid}) {
		# ignore authentifications of users whose sessions we trying to close
		$cb->();
		return;
	}

	my $in_process = ($self->{keys_in_process} //= {}); # to remove race-conditions

	$self->logger->trace("Setting $sid ($uid) into memc");
	if ($in_process->{$uid}) {
		shift;
		$self->logger->info("Queuing set action for uid $uid ($sid)");
		push @{$self->{keys_queue}}, \@_;
		return;
	}

	$in_process->{$uid} = 2;
	my $do_process = sub {
		# should be called just 2 times per uid
		if (--$in_process->{$uid} == 0) {
			$cb->(@_);

			my @queue = ($self->{keys_queue}, $self->{delete_queue});
			$self->{keys_queue} = [];
			$self->{delete_queue} = [];
			$self->_process_queue(@queue);
		}
	};

	$self->logger->trace("Setting $sid ($uid) into sid-memc");
	$self->{conn}{sid_memc}->set(
		$sid => $value,
		expire => $self->{conn}{exptime},
		cb => sub {
			$self->logger->trace("Done setting $sid into sid-memc");
			$do_process->(@_);
		},
	);

	$self->logger->trace("Setting $sid ($uid) into uid-memc");
	$self->{conn}{uid_memc}->get($uid, cb => sub {
		my ($val, $err) = @_;

		if ($err) {
			$self->logger->err("Can't get uid info: $uid: $@");
			$val = undef;
		}

		$self->logger->trace("Done requesting existed sessions from memc ($sid)");

		$val //= [];
		push @$val, $sid;

		$self->{conn}{uid_memc}->set(
			$uid => $val,
			cb => sub {
				$self->logger->trace("Done setting $sid($uid) into uid-memc");
				$do_process->(@_);
			},
		);
	});
}

sub delete_by_sid {
	my ($self, $key, $cb) = @_;
	return $self->{conn}{sid_memc}->delete($key, cb => $cb // sub {});
}

sub delete_by_uid {
	my ($self, $uid, $cb) = @_;

	if ($self->{keys_in_process}{$uid}) {
		# close new sessions, who start to authorize before sessions close
		shift;
		$self->logger->warn("Queuing delete action for uid $uid");
		push @{$self->{delete_queue}}, \@_;
		return;
	}

	# ignore authentifications of users whose sessions we trying to close
	$self->{delete_in_process}{$uid} = 1;
	$self->{conn}{uid_memc}->get($uid, cb => sub {
		my ($val, $err) = @_;

		if ($err) {
			$self->logger->err("Can't get uid info: $uid: $@");
			return;
		}

		for (@$val) {
			$self->logger->info("DELETING $_");
			$self->{conn}{sid_memc}->delete($_, cb => sub {}, no_reply => 1);
		}

		$self->{conn}{uid_memc}->delete($uid, cb => $cb // sub {});
		$self->{delete_in_process}{$uid} = 0;
	});
}

1;
