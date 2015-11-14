package CakeProcessor::BaseMethod;

use strict;
use warnings;

use base qw( Exporter );

use Data::Dumper::OneLine;

require Logger;
my $logger = Logger->new("BaseMethod");

sub new {
	my ($class, $processor_args) = @_;

	$logger->trace("$class method invoked with args " . Dumper $processor_args);

	my $self = bless {}, $class;

	if ($self->check_args($processor_args)) { # method should be implemented in derived
		$self->{args} = $processor_args;
	} elsif ($self->valid) {
		# if we forget to set 'err' in derived
		$self->{err} = "args processing failed";
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
	$self->{response} = \@response;
	$self->{cb}->();
}

sub process {
	my ($self, $cb) = @_;

	$self->{cb} = $cb;
	$self->process_impl; # should be implemented in derived
}

sub response {
	my $self = shift;

	return @{$self->{response}};
}

1;
