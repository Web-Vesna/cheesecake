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
);

{
	my $logger = Logger->new("MainLoop");
	my @clients;

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

	sub mk_handle {
		my ($cli, $host, $port) = @_;

		my $proto = CakeProto->new(
			cb_close => sub {
				my ($hndl, $msg) = @_;
				$hndl->push_write($msg);
				$hndl->push_shutdown;
			},
			credentials => "$host:$port",
		);

		my $hndl = AnyEvent::Handle->new(
			fh => $cli,
			CakeProto::encode_mode(),

			on_error => sub {
				my ($hndl, $fatal, $msg) = @_;

				$logger->err("Error happens in $host:$port: $msg. Close connection.");
				$proto->bad_packet; # will destroy connection
			},

			on_eof => sub {
				my ($hndl) = @_;
				$logger->info("Closing connection with $host:$port");
				$hndl->destroy;
			},
		);
		$hndl->push_read($proto->on_read_event(auth => sub {
			my ($hndl, $packet) = @_;
			$logger->debug("auth packet came");
			$hndl->push_write($packet->response);
		}));

		return $hndl;
	}
}

1;
