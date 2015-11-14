package CakeProcessor::MethodCheck;

use strict;
use warnings;

use base qw( CakeProcessor::BaseMethod );

require Logger;
my $logger = Logger->new("CheckMethod");

sub check_args {
	my ($self, $args) = @_;

	return 1;
}

sub process_impl {
	my $self = shift;

	$logger->trace("Processing started");
	$self->send({ args => $self->args });
}

1;
