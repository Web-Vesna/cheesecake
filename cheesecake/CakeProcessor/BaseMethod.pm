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
		memc => $args{memc},
		dbi => $args{dbi},
	}, $class;

	unless ($self->check_args($processor_args)) { # method should be implemented in derived
		if ($self->valid) {
			# if we forget to set 'err' in derived
			$self->{err} = "args processing failed";
		}
	}

	return $self;
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

1;
