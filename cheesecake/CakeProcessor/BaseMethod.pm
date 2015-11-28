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
	return $self->packet_invalid
		unless $response;
	return $self->packet_valid;
}

sub errstr {
	return shift->{err};
}

sub valid {
	return not defined shift->{err};
}

sub args {
	return shift->{args};
}

sub packet_valid {
	my $self = shift;
	$self->{on_valid}->($self);
	return $self;
}

sub packet_invalid {
	my $self = shift;
	$self->{on_invalid}->($self, $self->errstr);
	return $self;
}

sub send {
	my ($self, @response) = @_;
	if ($self->{err}) {
		$self->{on_err}->($self->{err});
	} else {
		$self->{response} = \@response;
		$self->{on_succ}->();
	}
}

sub process {
	my ($self, $on_succ, $on_err) = @_;

	$self->{on_succ} = $on_succ;
	$self->{on_err} = $on_err;
	$self->process_impl; # should be implemented in derived
}

sub response {
	my $self = shift;

	return @{$self->{response}};
}

sub memc {
	return shift->{memc};
}

sub dbi {
	return shift->{dbi};
}

1;
