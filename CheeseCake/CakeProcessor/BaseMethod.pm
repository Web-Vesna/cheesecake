package CakeProcessor::BaseMethod;

use strict;
use warnings;

use base qw( Exporter );

use Data::Dumper::OneLine;

require Logger;

sub new {
	my ($class, $processor_args, %args) = @_;

	my $self = bless {
		memc		=> $args{memc},
		dbi		=> $args{dbi},
		auth_client	=> $args{auth_client},
		packet_id	=> $args{packet_id},
		class_name	=> $class,
		on_valid	=> $args{on_valid},	# will be called if a packet is valid
		on_invalid	=> $args{on_invalid},	# will be called if a packet is invalid
	}, $class;

	$self->logger->trace("$class method invoked with args " . Dumper $processor_args);

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

sub logger {
	my $self = shift;

	unless ($self->{logger}) {
		$self->{logger} =  Logger->new(@$self{qw( class_name auth_client packet_id )});
	}

	return $self->{logger};
}

1;
