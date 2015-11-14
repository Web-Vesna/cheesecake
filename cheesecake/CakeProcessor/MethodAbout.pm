package CakeProcessor::MethodAbout;

use strict;
use warnings;

use base qw( CakeProcessor::MethodCheck );

use Data::Dumper::OneLine;

require Logger;
my $logger = Logger->new("AboutMethod");

sub process_impl {
	my $self = shift;

	$logger->trace("Processing started");
	$self->memc->get($self->{session_id}, sub {
		my $value = shift;

		$logger->trace("Response from memc: '" . ($value // 'undef') . "'");
		$self->{err} = "not exists"
			unless $value;

		$self->send($value);
	});
}

1;
