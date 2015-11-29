package MainLoop;

use strict;
use warnings;

use EV;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use Errno;

use CakeProto;
use CakeConfig;
use Logger;

use base qw( Exporter );

our @EXPORT = qw(
	main_loop
	skip_auth
);

{
	my $logger = Logger->new("MainLoop");
	my @clients; # XXX: overflow is expected: FIXME

	my $auth_client = undef; # global auth client, should be setup from command line
	sub skip_auth {
		$auth_client = shift;
	}

	sub main_loop {
		die "Can't listen port " . config->{listen}{port} . " unless you are root\n"
			if config->{listen}{port} < 1024 && getpwuid($>) ne 'root';

		tcp_server config->{listen}{host}, config->{listen}{port}, sub {
			my ($client, $host, $port) = @_;
			unless ($client) {
				$logger->err("Unable to connect: $!\n");
				return;
			}

			$logger->info("Accepted client $host:$port");

			push @clients, mk_handle($client, $host, $port);
		};

		$logger->info("Server starts on " . join ":", @{config->{listen}}{qw( host port )});
		AnyEvent->condvar->recv;
	}

	sub create_proto {
		my ($host, $port, $auth_client) = @_;
		return CakeProto->new(
			cb_close => sub {
				my ($hndl, $msg) = @_;
				$hndl->push_write($msg);
				$hndl->destroy;
			},
			credentials => "$host:$port",
			auth_client => $auth_client,
		);
	}

	sub on_packet_read {
		my ($host, $port, $client) = @_;

		my $is_auth = !$auth_client && !defined $client;
		my $packet_type = $is_auth ? "Auth" : "Common";

		if (!$client && $auth_client) {
			$logger->info("Setting auth client as $auth_client (command line option)");
		}

		$logger->trace("Preparing read_packet event for $packet_type packet");
		my $__auth_cli = $client;
		return create_proto($host, $port, $client // $auth_client)->on_read_event(($is_auth ? 'auth' : undef) => sub {
			my ($hndl, $response, $auth_cli) = @_;
			$logger->debug("$packet_type packet came from $host, $port");

			my $need_close = 0;
			if ($is_auth) {
				if (!$auth_cli) {
					$logger->err("Auth client is not defined in auth response! Close connection");
					$need_close = 1;
				} else {
					$__auth_cli = $auth_cli;
					$logger->info("Setting auth client as $auth_cli");
				}
			}

			$hndl->push_write($response);
			if ($need_close) {
				$hndl->push_shutdown;
			} else {
				$hndl->push_read(on_packet_read($host, $port, $__auth_cli));
			}
		});
	}

	sub mk_handle {
		my ($cli, $host, $port) = @_;

		my $hndl = AnyEvent::Handle->new(
			fh => $cli,

			on_error => sub {
				my ($hndl, $fatal, $msg) = @_;

				$logger->err("Error happens in $host:$port: $msg. Close connection.");

				if ($fatal) {
					$hndl->destroy;
				} else {
					create_proto($host, $port)->bad_packet($hndl); # will destroy connection
				}
			},

			on_eof => sub {
				my ($hndl) = @_;
				$logger->info("Closing connection with $host:$port");
				$hndl->destroy;
			},
		);

		$hndl->push_read(on_packet_read($host, $port));

		return $hndl;
	}
}

1;
