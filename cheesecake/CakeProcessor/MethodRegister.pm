package CakeProcessor::MethodRegister;

use strict;
use warnings;

use base qw( CakeProcessor::LoginMethod );

use Mail::RFC822::Address;

require Logger;
my $logger = Logger->new("RegisterMethod");

sub check_args {
	my ($self, $args) = @_;

	my $real_args;
	unless ($args && @$args) {
		$self->{err} = "no arguments";
	} elsif (scalar @$args != 1) {
		$self->{err} = "too many argumets: 1 expected";
	} elsif (!ref($args->[0]) || ref($args->[0]) ne 'HASH') {
		$self->{err} = "invalid argument: '" . Dumper($args->[0]) . "'. Object is expected";
	} elsif ((my $err, $real_args) = $self->validate_schema($args->[0])) {
		$self->{err} = "invalid schema: '" . Dumper($args->[0]) . "'. $err.";
	} else {
		$logger->trace("Validation complete successfully");
		$self->{user_info} = $real_args;
		return 1;
	}

	$logger->info("Validation failed: $self->{err}");

	return 0;
}

sub validate_schema {
	my ($self, $data) = @_;
	my $schema = $self->dbi->schema;

	my %expected_types = (
		int	=> sub { $_[0] !~ /\D/ },
		str	=> sub { 1 }, # everything matches
		email	=> sub { Mail::RFC822::Address::valid($_[0]) },
	);

	my %real_args;
	for (@$schema) {
		next if $_->{col_type} eq 'userid';

		return "'$_->{name}' field is required"
			if $_->{required} && !defined $data->{$_->{name}};

		my $v = $data->{$_->{name}};
		next unless defined $v; # not required field is not set

		return "flat $_->{type} is expected in '$_->{name}'"
			if ref $v;

		return "$_->{type} is expected in '$_->{name}'"
			unless $expected_types{$_->{type}}->($v);

		$real_args{$_->{name}} = $v;
	}

	if (my @redundant = grep { not defined $real_args{$_} } keys %$data) {
		return "redundant field found in request: '$redundant[0]'";
	}

	return (undef, \%real_args);
}

sub process_impl {
	my $self = shift;

	my $login = $self->{user_info}{$self->dbi->extra_col('login')};
	$logger->trace("Trying to register: '$login'");

	$self->dbi->insert(%{$self->{user_info}}, sub {
		my ($uid, $err) = @_;
		if ($err) {
			$self->{err} = $err;
			return $self->send;
		}

		# inserted user info can be different as requested.
		# Rerequest this info again
		$self->dbi->select(uid => $uid, sub {
			my ($response, $err) = @_;
			if ($err) {
				$self->{err} = $err;
				return $self->send;
			}

			$self->create_session($response, sub {
				return $self->send(shift, $uinfo); # session id && user info
			});
		});
	});
}

1;
