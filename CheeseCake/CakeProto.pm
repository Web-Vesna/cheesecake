package CakeProto;

use strict;
use warnings;

use base qw( Exporter );

require Logger;
use JSON::XS;
use CBOR::XS;

our @EXPORT = qw(
	use_json
	encode_mode
);

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
		auth_client => undef,
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

		$pack_type->new(
			$data,
			auth_client => $self->{auth_client},
			on_success => sub {
				my ($response, $auth_cli) = @_;
				$sub->($hndl, _encode($response), $auth_cli);
			},
			on_error => sub {
				my ($response, $err) = @_;
				$logger->err("Invalid packet came from '$self->{credentials}': $err");
				$sub->($hndl, _encode($response));
			},
		);
	};
}

sub bad_packet {
	my ($self, $hndl) = @_;

	$logger->err("Invalid packet came from '$self->{credentials}'");

	my $packet = CakeProto::BadPacket->new;
	$self->{cb_close}($hndl, _encode($packet->response(error => 'bad packet')));
}

1;

package CakeProto::Packet;

use strict;
use warnings;

use Data::Dumper::OneLine;

sub new {
	my ($class, $packet, %args) = @_;

	my $self = bless {
		encode		=> $args{encode},
		auth_client	=> $args{auth_client},
		on_success	=> $args{on_success},
		on_error	=> $args{on_error},
		logger		=> Logger->new($class =~ /::(.*)/),
	}, $class;

	$self->parse_packet($packet);
	return $self;
}

sub packet_valid {
	my ($self, $data, $auth_cli) = @_;
	$self->{on_success}->($self->response(data => $data), $auth_cli);
}

sub packet_invalid {
	my ($self, $err) = @_;
	$self->{logger}->warn($err);
	$self->{on_error}->($self->response(error => $err), $err);
}

sub process {
	my ($self, $cb) = @_;
	return $cb->($self); # no processing by default
}

sub parse_packet {
	my ($self, $packet) = @_;

	$self->trace(request => $packet);

	return $self->packet_invalid("no data")
		unless $packet;

	return $self->packet_invalid("invalid packet type: array expected")
		unless ref $packet && ref $packet eq 'ARRAY';

	$self->{packet_id} = shift @$packet;
	$self->_parse_packet_impl($packet);
}

sub response {
	my ($self, $value_type, $value) = @_;

	my @resp = ( $self->{packet_id} );
	if ($value_type eq 'error') {
		push @resp, 0, $value;
	} elsif ($value_type eq 'data') {
 		push @resp, 1, @$value;
	} else {
		die "Invalid value type came: $value_type\n";
	}

	$self->trace(response => \@resp);

	return \@resp;
}

sub trace {
	my ($self, $type, $val) = @_;

	if (Logger::log_lvl eq 'trace') {
		$self->{logger}->trace(sprintf(({
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
use MemcClient;
use MysqlClient;

sub _parse_packet_impl {
	my ($self, $packet) = @_;

	my $func_name = shift @$packet;
	return $self->packet_invalid("function name is not specified")
		unless $func_name;

	die "Auth client is not set!\n"
		unless $self->{auth_client};

	CakeProcessor::process_function($func_name, $packet,
		memc		=> MemcClient->new($self->{auth_client}),
		dbi		=> MysqlClient->new($self->{auth_client}),
		on_valid	=> sub {
			$self->packet_valid(\@_);
		},
		on_invalid	=> sub {
			my ($err) = @_;
			$self->packet_invalid($err);
		}
	);
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
		return $self->packet_invalid("no such service");
	}

	unless (grep { $_ eq $client_secret } @{$service->{secrets}}) {
		$self->{logger}->warn("Unexpexted service secret requested: '$client_name', '$client_secret'");
		return $self->packet_invalid("no such service");
	}

	return $self->packet_valid([], $client_name);
}

1;

package CakeProto::BadPacket;

use strict;
use warnings;

use base qw( CakeProto::Packet );

sub parse_packet {}

1;
