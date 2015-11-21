package MemcClient;

use strict;
use warnings;

use AnyEvent::DBI::MySQL;

# TODO: PROCESS MYSQLD ERRORS !!!

require Logger;

my %connections;

sub new {
	my ($class, $service_name) = @_;

	my $self = bless {
		logger => Logger->new("MysqlClient ($service_name)"),
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

	$self->logger->info("Initialization of a service connection");
}

1;
