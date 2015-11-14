package MemcClient;

use strict;
use warnings;

use AnyEvent::Memcached;

use CakeConfig qw( service );

# TODO: PROCESS MEMCACHED ERRORS !!!

require Logger;

my %connections;

sub new {
	my ($class, $service_name) = @_;

	my $self = bless {
		keys_in_process => {},
		keys_queue => [],

		delete_in_process => {},
		delete_queue => [],
	}, $class;

	unless ($connections{$service_name}) {
		$self->establish_connection($service_name);
	}

	$self->{conn} = $connections{$service_name};

	return $self;
}

sub establish_connection {
	my ($self, $service_name) = @_;

	my ($host, $port, $prefix, $exptime) = @{service($service_name)}{qw( memc_host memc_port memc_prefix session_expire_time )};

	my $memc = AnyEvent::Memcached->new(
		servers => [ "$host:$port" ],
		namespace => "$prefix:_sid:",
	);

	my $memc2 = AnyEvent::Memcached->new(
		servers => [ "$host:$port" ],
		namespace => "$prefix:_uid:",
	);

	my $logger = Logger->new("MemcachedClient");
	$connections{$service_name} = {
		sid_memc => $memc,
		uid_memc => $memc2,
		exptime => $exptime,
		logger => $logger,
	};
}

sub get {
	my ($self, $key, $cb) = @_;
	return $self->{conn}{sid_memc}->get($key, cb => $cb);
}

sub _process_queue {
	my ($self, $set_queue, $delete_queue) = @_;

	# at first we should close old sessions and only then open new
	for (@$delete_queue) {
		$self->delete(@$_);
	}

	for (@$set_queue) {
		$self->set(@$_);
	}
}

sub set {
	my ($self, $sid, $uid, $value, $cb) = @_;

	if ($self->{delete_in_process}{$uid}) {
		# ignore authentifications of users whose sessions we trying to close
		$cb->();
		return;
	}

	my $in_process = $self->{keys_in_process}; # to remove race-conditions
	if ($in_process->{$uid}) {
		shift;
		push @{$self->{keys_queue}}, \@_;
		return;
	}

	$in_process->{$uid} = 2;
	my $do_process = sub {
		# should be called just 2 times per uid
		if (--$in_process->{$uid} == 0) {
			my @queue = ($self->{keys_queue}, $self->{delete_queue};
			$self->{keys_queue} = [];
			$self->{delete_queue} = [];
			$self->_process_queue(@queue);
		}
	};

	$self->{conn}{sid_memc}->set(
		$sid => $value,
		expire => $self->{conn}{exptime},
		cb => sub {
			$cb->(@_);
			$do_process->();
		},
	);
	$self->{conn}{uid_memc}->get($uid, cb => sub {
		my ($val, $err) = @_;

		if ($err) {
			$self->{conn}{logger}->err("Can't get uid info: $uid: $@");
			$val = undef;
		}

		$val //= [];
		push @$val, $sid;

		$self->{conn}{uid_memc}->set(
			$uid => $val,
			cb => $do_process,
		);
	});
}

sub delete_by_sid {
	my ($self, $key, $cb) = @_;
	return $self->{conn}{sid_memc}->delete($key, cb => $cb // sub {});
}

sub delete_by_uid {
	my ($self, $uid) = @_;

	if ($self->{keys_in_process}{$uid}) {
		# close new sessions, who start to authorize before sessions close
		shift;
		push @{$self->{delete_queue}}, \@_;
		return;
	}

	# ignore authentifications of users whose sessions we trying to close
	$self->{delete_in_process}{$uid} = 1;
	$self->{conn}{uid_memc}->get($uid, cb => sub {
		my ($val, $err) = @_;

		if ($err) {
			$self->{conn}{logger}->err("Can't get uid info: $uid: $@");
			return;
		}

		for (@$val) {
			$self->{conn}{sid_memc}->delete($_, noreply => 1);
		}

		$self->{conn}{uid_memc}->delete($uid, noreply => 1);
		$self->{delete_in_process}{$uid} = 0;
	});
}

1;
