package CakeProcessor::MethodRegister;

use strict;
use warnings;

use base qw( CakeProcessor::MethodLogin );

use Mail::RFC822::Address;

sub check_args {
	my ($self, $args) = @_;

	my $real_args;
	my $err = "";
	unless ($args && @$args) {
		$err = "no arguments";
	} elsif (scalar @$args != 1) {
		$err = "too many argumets: 1 expected";
	} elsif (!ref($args->[0]) || ref($args->[0]) ne 'HASH') {
		$err = "invalid argument: '" . Dumper($args->[0]) . "'. Object is expected";
	} elsif ((my $err, $real_args) = $self->validate_schema($args->[0])) {
		$err = "invalid schema: '" . Dumper($args->[0]) . "'. $err.";
	} else {
		$self->logger->trace("Validation complete successfully. Check extra conditions");
		$self->check_extra_conditions($real_args);
		return undef;
	}

	$self->logger->info("Validation failed: $err");
	return $self->packet_invalid($err);
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

sub check_extra_conditions {
	my ($self, $data) = @_;

	# Extra conditions:
	#	* user with given unique fields is found (one by one)

	my $schema = $self->dbi->schema;
	my $reqs_sent = 0;
	my $failed = 0;

	for (@$schema) {
		# all required fields are already processed
		# => if fiels should be unique but not present means col is not required
		if ($_->{unique} && defined $data->{$_->{name}}) {
			++$reqs_sent;
			$self->dbi->check_unique($_->{name}, $data->{$_->{name}}, sub {
				return if $failed;

				my $err = shift;
				if ($err) {
					$failed = 1;
					return $self->packet_invalid($err);
				}

				unless (--$reqs_sent) {
					$self->{user_info} = $data;
					$self->process;
				}
			});
		}
	}
}

sub process {
	my $self = shift;

	my $login = $self->{user_info}{$self->dbi->extra_col('login')};
	$self->logger->trace("Trying to register: '$login'");

	$self->dbi->insert(%{$self->{user_info}}, sub {
		my ($uid, $err) = @_;
		if ($err) {
			return $self->packet_invalid($err);
		}

		# inserted user info can be different as requested.
		# Rerequest this info again
		$self->dbi->select(uid => $uid, sub {
			my ($response, $err) = @_;
			if ($err) {
				return $self->packet_invalid($err);
			}

			$self->create_session($response, sub {
				return $self->packet_valid(shift, $response); # session id && user info
			});
		});
	});
}

1;
