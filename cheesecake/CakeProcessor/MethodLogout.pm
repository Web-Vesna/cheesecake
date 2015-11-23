package CakeProcessor::MethodLogout;

use strict;
use warnings;

use base qw( CakeProcessor::BaseMethod );

use Data::Dumper::OneLine;

require Logger;
my $logger = Logger->new("LogoutMethod");

sub check_args {
	my ($self, $args) = @_;

	unless ($args && @$args) {
		$self->{err} = "no arguments";
	} elsif (scalar @$args < 1 || scalar @$args > 2) {
		$self->{err} = "invalid arguments count: 1 or 2 expected";
	} elsif (ref $args->[0]) {
		$self->{err} = "invalid argument: '" . Dumper($args->[0]) . "'. String is expected";
	} else {
		$logger->trace("Validation complete successfully");
		$self->{session_id} = $args->[0];
		$self->{close_all_sessions} = $args->[1] // 0;
		return 1;
	}

	$logger->info("Validation failed: $self->{err}");

	return 0;
}

sub process_impl {
	my $self = shift;

	$logger->trace("Trying to logout '$self->{session_id}' (force = " . $self->{close_all_sessions} . ")");
	if ($self->{close_all_sessions}) {
		$logger->trace("Trying to force logout of user with sid $self->{session_id}");
		$self->memc->get($self->{session_id}, sub {
			my $value = shift;
			unless ($value) {
				$logger->info("Got empty response in close_all_sessions request");
				$self->send;
				return;
			}

			$logger->trace("Got uid for sid '$self->{session_id}': '$value->{uid}'");

			my $uid = $value->{uid};
			unless (defined $uid) {
				$self->send;
				return;
			}

			$self->memc->delete_by_uid($uid, sub { $self->send });
		});
	} else {
		$self->memc->delete_by_sid($self->{session_id}, sub { $self->send });
	}
}

1;
