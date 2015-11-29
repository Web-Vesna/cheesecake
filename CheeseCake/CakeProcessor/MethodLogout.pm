package CakeProcessor::MethodLogout;

use strict;
use warnings;

use base qw( CakeProcessor::BaseMethod );

use Data::Dumper::OneLine;

sub check_args {
	my ($self, $args) = @_;

	my $err = "";
	unless ($args && @$args) {
		$err = "no arguments";
	} elsif (scalar @$args < 1 || scalar @$args > 2) {
		$err = "invalid arguments count: 1 or 2 expected";
	} elsif (ref $args->[0]) {
		$err = "invalid argument: '" . Dumper($args->[0]) . "'. String is expected";
	} else {
		$self->logger->trace("Validation complete successfully");
		$self->{session_id} = $args->[0];
		$self->{close_all_sessions} = $args->[1] // 0;
		return 1;
	}

	$self->logger->info("Validation failed: $err");
	return $self->packet_invalid($err);
}

sub process {
	my $self = shift;

	$self->logger->trace("Trying to logout '$self->{session_id}' (force = " . $self->{close_all_sessions} . ")");
	if ($self->{close_all_sessions}) {
		$logger->trace("Trying to force logout of user with sid $self->{session_id}");
		$self->memc->get($self->{session_id}, sub {
			my $value = shift;
			unless ($value) {
				$self->logger->info("Got empty response in close_all_sessions request");
				return $self->packet_valid;
			}

			$self->logger->trace("Got uid for sid '$self->{session_id}': '$value->{uid}'");

			my $uid = $value->{uid};
			unless (defined $uid) {
				return $self->packet_valid;
			}

			$self->memc->delete_by_uid($uid, sub { $self->packet_valid });
		});
	} else {
		$self->memc->delete_by_sid($self->{session_id}, sub { $self->packet_valid });
	}
}

1;
