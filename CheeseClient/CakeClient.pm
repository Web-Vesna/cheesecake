package CakeClient;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Data::Dumper::OneLine;

use CBOR::XS;

sub new {
	my $class = shift;

	my %args = (
		nb		=> 1, # non-block by default
		on_error	=> sub {
			die shift . "\n";
		},
		@_,
	);
	return bless \%args, $class;
}

sub send {
	my ($self, $data, $cb) = @_;

	our %requests;

	my $req_id = int(rand 99999) * int(rand 75) + int(rand 654125);
	unshift @$data, $req_id;
	$requests{$req_id} = {
		req => $data,
		cb => $cb,
	};

	warn Dumper "SENDING REQUEST: " . Dumper($data);

	$self->{hndl}->push_write(cbor => $data);
	$self->{hndl}->push_read(cbor => sub {
		my (undef, $v) = @_;

		return $self->{on_error}->("Invalid response: " . Dumper($v))
			unless ref($v) && ref($v) eq 'ARRAY';

		my $req_id = shift @$v;
		my $req = delete $requests{$req_id}
			or return $self->{on_error}->("Request with id $req_id not found");

		$req->{cb}->($v)
			if $req->{cb};
	});
}

sub connect {
	my $self = shift;
	my %args = (
		host		=> 'localhost',
		port		=> 8000,
		client		=> 'test',
		client_key	=> '1',
		cb		=> undef,
		@_,
	);

	my $cv = AnyEvent->condvar;
	unless ($self->{nb}) {
		my $cb = $args{cb};
		$args{cb} = sub {
			$cb->(@_)
				if $cb;

			$cv->send;
		};
	}

	tcp_connect($args{host}, $args{port}, sub {
		my $fh = $_[0]
			or return $self->{on_error}->("Can't connect to $args{host}:$args{port}: $!");

		$self->{hndl} = AnyEvent::Handle->new(
			fh => $fh,
			on_error => sub {
				my ($hdl, $fatal, $msg) = @_;
				$self->{on_error}->($msg);
				$hdl->destroy
					if $fatal;
			});

		$self->auth(%args);
	});

	$cv->recv
		unless $self->{nb};
}

sub auth {
	my $self = shift;

	my %args = (
		client		=> 'test',
		client_key	=> '1',
		cb		=> undef,
		@_,
	);

	$self->send([ $args{client}, $args{client_key} ], sub {
		my $args = shift;
		return $self->{on_error}->($args->[1] // "auth failed")
			unless $args->[0];

		$args{cb}->()
			if $args{cb};
	});
}

sub req {
	my $self = shift;
	my %args = (
		cb	=> undef,
		func	=> undef,
		args	=> undef,
		@_,
	);

	my $response;
	my $cv = AnyEvent->condvar;
	unless ($self->{cb}) {
		my $cb = $args{cb};
		$args{cb} = sub {
			$cb->(@_)
				if $cb;
			$cv->send;
		};
	}

	$self->send([ $args{func}, @{$args{args}} ], $args{cb});

	$cv->recv
		unless $self->{nb};
}

1;
