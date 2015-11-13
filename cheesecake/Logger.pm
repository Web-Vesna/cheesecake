package Logger;

use strict;
use warnings;

use Scalar::Util qw( reftype );

use base qw( Exporter );

our @EXPORT = qw(
	new

	trace
	debug
	info
	warn
	err

	set_log_lvl
);

{
	our $LOG_LVL = 2;
	sub set_log_lvl {
		$LOG_LVL = shift // 2;
	}

	sub new {
		my ($class, $prefix) = @_;

		return bless {
			prefix => "$prefix: ",
		}, $class;
	}

	sub real_warn {
		my ($prefix, $msg) = @_;
		return unless defined($prefix);

		warn "$prefix$msg\n";
	}

	sub prepare {
		my ($self, $msg) = @_;
		my $prefix = "";
		if (reftype $self ne 'HASH') {
			$msg = $self;
		} else {
			$prefix = $self->{prefix};
		}

		if (defined reftype $msg) {
			use Data::Dumper;
			real_warn "Logger: ", "Invalid message came: " . Dumper $msg;
			return;
		}

		return $prefix, $msg;
	}

	sub trace {
		return if $LOG_LVL < 5;
		real_warn prepare @_;
	}

	sub debug {
		return if $LOG_LVL < 4;
		real_warn prepare @_;
	}

	sub info {
		return if $LOG_LVL < 3;
		real_warn prepare @_;
	}

	sub warn {
		return if $LOG_LVL < 2;
		real_warn prepare @_;
	}

	sub err {
		return if $LOG_LVL < 1;
		real_warn prepare @_;
	}
}

1;
