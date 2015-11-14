package CakeProcessor::MethodCheck;

use strict;
use warnings;

use base qw( CakeProcessor::BaseMethod );

use Data::Dumper::OneLine;

require Logger;
my $logger = Logger->new("CheckMethod");

sub check_args {
	my ($self, $args) = @_;

	unless ($args && @$args) {
		$self->{err} = "no arguments";
	} elsif (scalar @$args != 1) {
		$self->{err} = "too many argumets: 1 expected";
	} elsif (ref $args->[0]) {
		$self->{err} = "invalid argument: '" . Dumper($args->[0]) . "'. String is expected";
	} else {
		$logger->trace("Validation complete successfully");
		$self->{session_id} = $args->[0];
		return 1;
	}

	$logger->info("Validation failed: $self->{err}");

	return 0;
}

sub process_impl {
	my $self = shift;

	$logger->trace("Processing started");
	$self->memc->get($self->{session_id}, sub {
		my $value = shift;

		$logger->trace("Response from memc: '" . ($value // 'undef') . "'");
		$self->{err} = "not exists"
			unless $value;

		$self->send;
	});
}

1;
