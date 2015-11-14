package CakeProto;

use strict;
use warnings;

use base qw( Exporter );

use Logger;
use JSON::XS;
use CBOR::XS;

our @EXPORT = qw(
	use_json
	encode_mode
);

{
	my $use_json = 0;
	sub use_json {
		$use_json = shift;
	}

	my $logger = Logger->new("Proto");
	my %encode_modes = (
		json => 'JSON::XS',
		cbor => 'CBOR::XS',
	);

	sub new {
		my $class = shift;
		my %args = (
			cb_close => undef,
			credentials => "unknown",
			@_,
		);

		$args{id} = int(rand 100000);
		$logger->trace("Creatigng proto $args{id}");

		return bless \%args, $class;
	}

	sub DESTROY {
		my $self = shift;
		$logger->trace("Destroying proto $self->{id}");
	}

	sub _encode_mode {
		return $use_json ? "json" : "cbor";
	}

	sub _encode_module {
		my $no_new = shift;
		my $pack = $encode_modes{_encode_mode()};

		return $pack
			if $no_new;
		return $pack->new;
	}

	sub encode_mode {
		my ($type, $mod) = (_encode_mode, _encode_module(1));
		$logger->debug("Using $mod module (use $type mode)");
		return $type, $mod->new;
	}

	sub _encode {
		return _encode_module->encode(shift);
	}

	sub on_read_event {
		my ($self, $type, $sub) = @_;
		if (ref $type && ref $type eq 'CODE') {
			$sub = $type;
			$type = undef;
		}

		my $pack_type = "CakeProto::CommonPacket";
		if ($type && $type eq 'auth') {
			$pack_type = "CakeProto::AuthPacket";
		} elsif (defined $type) {
			$logger->err("Unexpected packet type came: '$type'");
			die "Unexpected packet type from '$self->{credentials}': '$type'\n";
		}

		$logger->trace("Packet type is $pack_type");

		return _encode_mode, sub {
			my ($hndl, $data) = @_;

			$logger->trace("Packet came into on_read");

			my $packet = $pack_type->new(
				$data,
				encode => \&_encode,
			);
			if ($packet->valid) {
				return $packet->process($hndl, $sub);
			}

			$logger->err("Invalid packet came from '$self->{credentials}': " . $packet->errstr() . ". Close connection");
			$self->{cb_close}($hndl, $packet->response);
		};
	}

	sub bad_packet {
		my ($self, $hndl) = @_;

		$logger->err("Invalid packet came from '$self->{credentials}'");

		my $packet = CakeProto::BadPacket->new(undef, encode => \&_encode);
		$self->{cb_close}($hndl, $packet->response);
	}
}

1;

package CakeProto::Packet;

use strict;
use warnings;

use Data::Dumper::OneLine;

sub new {
	my ($class, $packet, %args) = @_;

	my $self = bless \%args, $class;

	$self->{logger} = Logger->new($class =~ /::(.*)/);
	$self->{packet} = $self->parse_packet($packet);

	return $self;
}

sub valid {
	return not defined shift->{err};
}

sub process {
	my ($self, $hndl, $cb) = @_;
	return $cb->($hndl, $self); # no processing by default
}

sub parse_packet {
	my ($self, $packet) = @_;

	$self->trace(request => $packet);

	unless ($packet) {
		$self->{err} = "no data";
		return;
	}

	unless (ref $packet && ref $packet eq 'ARRAY') {
		$self->{err} = "invalid packet type: array expected";
		return;
	}

	$self->{packet_id} = shift @$packet;
	return $self->_parse_packet_impl($packet);
}

sub errstr {
	return shift->{err} // "success";
}

sub response {
	my ($self) = @_;
	my @resp = ( $self->{packet_id} );
	if ($self->{err}) {
		push @resp, 0, $self->{err};
	} else {
 		push @resp, 1, $self->prepare_response;
	}
	$self->trace(response => \@resp);

	return $self->{encode}(\@resp);
}

sub logger {
	return shift->{logger};
}

sub trace {
	my ($self, $type, $val) = @_;

	if (Logger::log_lvl eq 'trace') {
		$self->logger->trace(sprintf(({
			request => "Request",
			response => "Response",
		}->{$type // ""} // "Unknown") . " packet: '%s'", Dumper $val));
	}
}

package CakeProto::CommonPacket;

use strict;
use warnings;

use base qw( CakeProto::Packet );

use CakeProcessor;

sub _parse_packet_impl {
	my ($self, $packet) = @_;

	my $func_name = shift @$packet;
	unless ($func_name) {
		$self->{err} = "function name is not specified";
		return;
	}

	$self->{processor} = CakeProcessor->new($func_name, $packet);
	unless ($self->{processor}->valid) {
		$self->{err} = $self->{processor}->errstr;
	}
}

sub prepare_response {
	my ($self, $args) = @_;
	return $self->{processor}->response;
}

sub process {
	my ($self, $hndl, $cb) = @_;
	$self->{processor}->process(sub {
		$cb->($hndl, $self);
	});
}

sub valid {
	my $self = shift;
	return !defined($self->{err}) && $self->{processor} && $self->{processor}->valid;
}

sub errstr {
	my $self = shift;
	return $self->{err} // ($self->{processor} && !$self->{processor}->valid) // "success";
}


1;

package CakeProto::AuthPacket;

use strict;
use warnings;

use base qw( CakeProto::Packet );

use CakeConfig qw( service );

sub _parse_packet_impl {
	my $self = shift;
	my $packet = shift;

	unless (scalar @$packet == 2) {
		$self->{err} = "invalid auth packet len: 3 items expected";
		return;
	}

	my ($client_name, $client_secret) = @$packet;
	my $service = service($client_name);

	unless ($service) {
		$self->{logger}->warn("Unexpected service requested: '$client_name'");
		$self->{err} = "no such service";
		return;
	}

	unless (grep { $_ eq $client_secret } @{$service->{secrets}}) {
		$self->{logger}->warn("Unexpexted service secret requested: '$client_name', '$client_secret'");
		$self->{err} = "no such service";
		return;
	}

	return {};
}

sub prepare_response {
	return (); # nothing in response
}

1;

package CakeProto::BadPacket;

use strict;
use warnings;

use base qw( CakeProto::Packet );

sub parse_packet {
	shift->{err} = "bad packet";
	return undef;
}

1;
