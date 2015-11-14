package MemcClient;

use strict;
use warnings;

use AnyEvent::Memcached;

use CakeConfig qw( service );

# TODO: PROCESS MEMCACHED ERRORS !!!

require Logger;
my $logger = Logger->new("MemcachedClient");

my %connections;

sub new {
	my ($class, $service_name) = @_;

	my $self = bless {}, $class;

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
		namespace => "$prefix:",
	);

	$connections{$service_name} = {
		memc => $memc,
		exptime => $exptime,
	};
}

sub get {
	my ($self, $key, $cb) = @_;
	return $self->{conn}{memc}->get($key, cb => $cb);
}

sub set {
	my ($self, $key, $value, $cb) = @_;
	return $self->{conn}{memc}->set(
		$key => $value,
		expire => $self->{conn}{exptime},
		cb => $cb // sub {}, # $cb->($rc, $err);
	);
}

sub delete {
	my ($self, $key, $cb) = @_;
	return $self->{conn}{memc}->delete($key, cb => $cb // sub {});
}

1;
