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

	my $use_auth = 1;
	sub skip_auth {
		$use_auth = not shift;
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
		my ($host, $port) = @_;
		return CakeProto->new(
			cb_close => sub {
				my ($hndl, $msg) = @_;
				$hndl->push_write($msg);
				$hndl->destroy;
			},
			credentials => "$host:$port",
		);
	}

	sub on_packet_read {
		my ($host, $port, $type) = @_;
		my $packet_type = ucfirst($type // "common");

		$logger->trace("Preparing read_packet event for $packet_type packet");
		return create_proto($host, $port)->on_read_event($type => sub {
			my ($hndl, $packet) = @_;
			$logger->debug("$packet_type packet came from $host, $port");
			$hndl->push_write($packet->response);
			$hndl->push_read(on_packet_read($host, $port));
		});
	}

	sub mk_handle {
		my ($cli, $host, $port) = @_;

		my $hndl = AnyEvent::Handle->new(
			fh => $cli,
			CakeProto::encode_mode(), # not works ?

			on_error => sub {
				my ($hndl, $fatal, $msg) = @_;

				$logger->err("Error happens in $host:$port: $msg. Close connection.");
				create_proto($host, $port)->bad_packet($hndl); # will destroy connection
			},

			on_eof => sub {
				my ($hndl) = @_;
				$logger->info("Closing connection with $host:$port");
				$hndl->destroy;
			},
		);

		$hndl->push_read(on_packet_read($host, $port, ($use_auth ? 'auth' : undef)));

		return $hndl;
	}
}

1;
