package CakeProcessor::MethodAbout;

use strict;
use warnings;

use base qw( CakeProcessor::MethodCheck );

use Data::Dumper::OneLine;

require Logger;
my $logger = Logger->new("AboutMethod");

sub process {
	my $self = shift;

	$logger->trace("Processing started");
	$self->memc->get($self->{session_id}, sub {
		my $value = shift;

		$logger->trace("Response from memc: '" . ($value // 'undef') . "'");
		$self->packet_invalid("not exists")
			unless $value;

		$self->packet_valid($value);
	});
}

1;
