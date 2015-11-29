package Logger;

use strict;
use warnings;

use Scalar::Util qw( reftype );
use Devel::StackTrace;

use Time::HiRes;

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
		my ($class, $prefix, $auth_cli, $packet_id) = @_;

		my $self = bless {
			prefix => $prefix,
			msg_info => '',
		}, $class;

		$self->{msg_info} .= " [cli=$auth_cli]"
			if $auth_cli;

		$self->{msg_info} .= " [id=$packet_id]"
			if defined $packet_id;

		return $self;
	}

	sub real_warn {
		my ($self, $type, $prefix, $msg) = @_;
		return unless defined($prefix);

		unless (defined $msg) {
			$self->err("Uninitialized message came from " . Devel::StackTrace->new->as_string);
			return;
		}

		warn sprintf "%s [$type] [$prefix]$self->{msg_info} $msg\n", scalar localtime;
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
			real_warn $self, "Logger", "Invalid message came: " . Dumper $msg;
			return;
		}

		return $prefix, $msg;
	}

	sub trace {
		my $self = shift;
		return if $LOG_LVL < 5;
		$self->real_warn("T", $self->prepare(@_));
	}

	sub debug {
		my $self = shift;
		return if $LOG_LVL < 4;
		$self->real_warn("D", $self->prepare(@_));
	}

	sub info {
		my $self = shift;
		return if $LOG_LVL < 3;
		$self->real_warn("I", $self->prepare(@_));
	}

	sub warn {
		my $self = shift;
		return if $LOG_LVL < 2;
		$self->real_warn("W", $self->prepare(@_));
	}

	sub err {
		my $self = shift;
		return if $LOG_LVL < 1;
		$self->real_warn("E", $self->prepare(@_));
	}
}

1;
