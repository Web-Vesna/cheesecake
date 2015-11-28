package CakeProcessor::BaseMethod;

use strict;
use warnings;

use base qw( Exporter );

use Data::Dumper::OneLine;

require Logger;
my $logger = Logger->new("BaseMethod");

sub new {
	my ($class, $processor_args, %args) = @_;

	$logger->trace("$class method invoked with args " . Dumper $processor_args);

	my $self = bless {
		memc		=> $args{memc},
		dbi		=> $args{dbi},
		on_valid	=> $args{on_valid},	# will be called if a packet is valid
		on_invalid	=> $args{on_invalid},	# will be called if a packet is invalid
	}, $class;

	my $response = $self->check_args($processor_args); # 0 -- args are invalid, 1 -- arge are valid, undef => args are in process

	return $self
		unless defined $response;

	$self->process
		if $response;

	return $self;
}

sub packet_valid {
	my $self = shift;
	$self->{on_valid}->(@_);
	return 1;
}

sub packet_invalid {
	my ($self, $err) = @_;
	$self->{on_invalid}->($err);
	return 0;
}

sub memc {
	return shift->{memc};
}

sub dbi {
	return shift->{dbi};
}

1;
