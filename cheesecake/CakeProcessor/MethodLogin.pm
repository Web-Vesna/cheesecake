package CakeProcessor::MethodLogin;

use strict;
use warnings;

use base qw( CakeProcessor::BaseMethod );

use Data::Dumper::OneLine;
use Digest::MD5 qw( md5_hex );

require Logger;
my $logger = Logger->new("LoginMethod");

sub check_args {
	my ($self, $args) = @_;

	unless ($args && @$args) {
		$self->{err} = "no arguments";
	} elsif (scalar @$args != 1) {
		$self->{err} = "too many argumets: 1 expected";
	} elsif (!ref($args->[0]) || ref($args->[0]) ne 'HASH') {
		$self->{err} = "invalid argument: '" . Dumper($args->[0]) . "'. Object is expected";
	} elsif (!$args->[0]{login} || !$args->[0]{password}) {
		$self->{err} = "invalid argument: '" . Dumper($args->[0]) . "'. login and password is expected";
	} else {
		$logger->trace("Validation complete successfully");
		$self->{credentials} = $args->[0];
		return 1;
	}

	$logger->info("Validation failed: $self->{err}");

	return 0;
}

sub process_impl {
	my $self = shift;

	my $login = $self->{credentials}{$self->dbi->extra_col('login')};
	$logger->trace("Trying to login: '$login'");
	$self->dbi->check_pass(@{$self->{credentials}}{qw( login password )}, sub {
		my ($response, $err) = @_;
		if ($err) {
			$logger->info("login failed for '$login': '$err'");
			$self->{err} = "internal error: $err";
		} else {
			$logger->trace("login request successfull: '$login'");
			if ($response && @$response == 1) {
				$self->create_session($response->[0], sub {
					$self->send(shift);
				});
				return;
			}
			$self->{err} = "invalid login or password";
		}
		$self->send;
	});
}

sub create_sid {
	my ($self, $uinfo) = @_;
	my $data = join '', map { "$_$uinfo->{$_}" } keys %$uinfo;
	$data .= localtime;

	return md5_hex($data);
}

sub create_session {
	my ($self, $uinfo, $cb) = @_;

	my $sid = $self->create_sid($uinfo);
	$self->memc->set($sid, $uinfo->{uid}, $uinfo, sub {
		$cb->($sid);
	});
}

1;
