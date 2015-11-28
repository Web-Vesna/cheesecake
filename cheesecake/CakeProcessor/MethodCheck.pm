package CakeProcessor::MethodCheck;

use strict;
use warnings;

use base qw( CakeProcessor::BaseMethod );

use Data::Dumper::OneLine;

require Logger;
my $logger = Logger->new("CheckMethod");

sub check_args {
	my ($self, $args) = @_;

	my $err = "";
	unless ($args && @$args) {
		$err = "no arguments";
	} elsif (scalar @$args != 1) {
		$err = "too many argumets: 1 expected";
	} elsif (ref $args->[0]) {
		$err = "invalid argument: '" . Dumper($args->[0]) . "'. String is expected";
	} else {
		$logger->trace("Validation complete successfully");
		$self->{session_id} = $args->[0];
		return 1;
	}

	$logger->info("Validation failed: $err");
	return $self->packet_invalid($err);
}

sub process {
	my $self = shift;

	$logger->trace("Processing started");
	$self->memc->get($self->{session_id}, sub {
		my $value = shift;

		$logger->trace("Response from memc: '" . ($value // 'undef') . "'");
		return $self->packet_invalid("not exists")
			unless $value;

		$self->packet_valid;
	});
}

1;
