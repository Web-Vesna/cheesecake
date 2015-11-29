package CakeProcessor;

use strict;
use warnings;

use base qw( Exporter );
our @EXPORT = qw( process_function );

require Logger;

sub process_function {
	my ($func_name, $f_args, %args) = @_;

	my $method = _load_method($func_name, \%args);
	unless ($method) {
		$args{on_invalid}->("unknown function was called: $func_name");
	} else {
		$method->new($f_args, %args,
			on_valid => sub {
				return $args{on_valid}->(@_);
			},
			on_invalid => sub {
				my ($err) = @_;
				return $args{on_invalid}->($err);
			});
	}
}

sub _load_method {
	my $func_name = shift;
	my $args = shift;

	our %loaded = ();

	my $logger = Logger->new("CakeProcessor", $args->{auth_client}, $args->{packet_id});
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

1;
