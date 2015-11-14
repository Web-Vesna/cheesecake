package CakeProcessor;

use strict;
use warnings;

use base qw( Exporter );

use Logger;

my $logger = Logger->new("CakeProcessor");

sub new {
	my ($class, $func_name, $args) = @_;

	my $self = bless {}, $class;

	my $processor = _load_processor($func_name);
	unless ($processor) {
		$self->{err} = "unknown function was called: $func_name";
	} else {
		$self->{processor} = $processor->new($args);
		$self->{err} = $self->{processor}->errstr
			unless $self->{processor}->valid;
	}

	return $self;
}

sub _load_processor {
	my $func_name = shift;

	our %loaded = ();

	unless (exists $loaded{$func_name}) {
		my $package_name = "CakeProcessor::Method" . ucfirst($func_name);
		$logger->debug("Trying to load $package_name");

		eval("use $package_name");

		if ($@) {
			$logger->err("Unknown function called: $func_name ($package_name not found)");
			$package_name = undef;
		} else {
			$logger->debug("$package_name successfully loaded");
		}

		$loaded{$func_name} = $package_name;
	}

	return $loaded{$func_name};
}

sub valid {
	return not defined shift->{err};
}

sub process {
	my ($self, $cb) = @_;

	unless ($self->{processor}) {
		$logger->err("Processor not found in process()");
		$self->{err} = "processor not found";
		return;
	}

	# $cb will call response() method to get response data.
	# $cb should be called after all processings
	$self->{processor}->process($cb);
}

sub response {
	my $self = shift;

	unless ($self->{processor}) {
		$logger->err("Processor not found in response()");
		$self->{err} = "processor not found";
		return;
	}
	$self->{processor}->response;
}

sub errstr {
	return shift->{err} // "success";
}

1;
