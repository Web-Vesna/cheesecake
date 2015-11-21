package Logger;

use strict;
use warnings;

use Scalar::Util qw( reftype );

use base qw( Exporter );

our @EXPORT = qw(
	log_lvl
	set_log_lvl
);
our @EXPORT_OK = @EXPORT;

{
	our $LOG_LVL = 2;
	sub set_log_lvl {
		$LOG_LVL = shift // 2;
	}

	sub log_lvl {
		return [qw(
			err
			warn
			info
			debug
			trace
		)]->[$LOG_LVL - 1];
	}

	sub new {
		my ($class, $prefix) = @_;

		return bless {
			prefix => $prefix,
		}, $class;
	}

	sub real_warn {
		my ($type, $prefix, $msg) = @_;
		return unless defined($prefix);

		warn sprintf "%s [$type] [$prefix] $msg\n", scalar localtime;
	}

	sub prepare {
		my ($self, $msg) = @_;
		my $prefix = "unknown";
		if (reftype $self ne 'HASH') {
			$msg = $self;
		} else {
			$prefix = $self->{prefix};
		}

		if (defined reftype $msg) {
			use Data::Dumper;
			real_warn "Logger", "Invalid message came: " . Dumper $msg;
			return;
		}

		return $prefix, $msg;
	}

	sub trace {
		return if $LOG_LVL < 5;
		real_warn "T", prepare @_;
	}

	sub debug {
		return if $LOG_LVL < 4;
		real_warn "D", prepare @_;
	}

	sub info {
		return if $LOG_LVL < 3;
		real_warn "I", prepare @_;
	}

	sub warn {
		return if $LOG_LVL < 2;
		real_warn "W", prepare @_;
	}

	sub err {
		return if $LOG_LVL < 1;
		real_warn "E", prepare @_;
	}
}

1;
