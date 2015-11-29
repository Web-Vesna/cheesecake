package CakeProcessor::MethodLogin;

use strict;
use warnings;

use base qw( CakeProcessor::BaseMethod );

use Data::Dumper::OneLine;
use Digest::MD5 qw( md5_hex );

sub check_args {
	my ($self, $args) = @_;

	my $err = "";
	unless ($args && @$args) {
		$err = "no arguments";
	} elsif (scalar @$args != 1) {
		$err = "too many argumets: 1 expected";
	} elsif (!ref($args->[0]) || ref($args->[0]) ne 'HASH') {
		$err = "invalid argument: '" . Dumper($args->[0]) . "'. Object is expected";
	} elsif (!$args->[0]{login} || !$args->[0]{password}) {
		$err = "invalid argument: '" . Dumper($args->[0]) . "'. login and password is expected";
	} else {
		$self->logger->trace("Validation complete successfully");
		$self->{credentials} = $args->[0];
		return 1;
	}

	$self->logger->info("Validation failed: $err");

	return $self->packet_invalid($err);
}

sub process {
	my $self = shift;

	my $login = $self->{credentials}{$self->dbi->extra_col('login')};
	$self->logger->trace("Trying to login: '$login'");
	$self->dbi->check_pass(@{$self->{credentials}}{qw( login password )}, sub {
		my ($response, $err) = @_;
		if ($err) {
			$self->logger->info("login failed for '$login': '$err'");
			return $self->packet_invalid("internal error: $err");
		} else {
			$self->logger->trace("login request successfull: '$login'");
			if ($response && @$response == 1) {
				$self->create_session($response->[0], sub {
					$self->packet_valid(shift);
				});
			} else {
				return $self->packet_invalid("invalid login or password");
			}
		}
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
