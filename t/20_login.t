#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use AnyEvent;

use Cwd qw( abs_path );

my %tests = (
	valid		=> { ok => 1, login => 'test', pass => 'test' },
	invalid_login	=> { ok => 0, login => 'dsf', pass => 'test' },
	invalid_pass	=> { ok => 0, login => 'test', pass => '2q4' },
);

my $path = abs_path($0);
$path =~ s#/[^/]*$##;

sub cfg_name { "$path/../config" };

unshift @INC, "$path/../CheeseCake", "$path/../CheeseClient";

require_ok('CakeClient');
require_ok('CakeConfig');

CakeConfig::read_config(cfg_name());
my $cfg = CakeConfig::config();

ok(defined $cfg, "Config read");

my $cv = AnyEvent->condvar;

my @__stuff;

sub logout {
	my ($cv, $cli, $sid, $tname) = @_;

	warn "BEGIN";
	$cv->begin;
	$cli->req(func => 'logout', args => [ $sid ], cb => sub {
		my $data = shift;

		ok(ref($data) eq 'ARRAY', "$tname: logout array found");
		ok(@$data == 1, "$tname: logout array contains 1 element");
		ok($data->[0] == 1, "$tname: logout success");

		check($cv, $cli, $sid, "$tname: after logout", 0);

		$cv->end;
	});
}

sub check {
	my ($cv, $cli, $sid, $tname, $valid, $cb) = @_;

	$cv->begin;
	$cli->req(func => 'check', args => [ $sid ], cb => sub {
		my $data = shift;

		ok(ref($data) eq 'ARRAY', "$tname: check array found");
		ok(@$data == ($valid ? 1 : 2), "$tname: check array contains 1 element");
		ok($data->[0] == $valid, "$tname: check success");

		$cb->() if $cb;
		$cv->end;
	});
}

sub login_ok {
	my ($cv, $cli, $sid, $tname) = @_;

	my $reqs_in_process = 2;
	check($cv, $cli, $sid, $tname, 1, sub {
		unless (--$reqs_in_process) {
			logout($cv, $cli, $sid, $tname);
		}
	});

	$cv->begin;
	$cli->req(func => 'about', args => [ $sid ], cb => sub {
		my $data = shift;

		ok(ref($data) eq 'ARRAY', "$tname: about array found");
		ok(@$data == 2, "$tname: about array contains 2 elements");
		ok($data->[0] == 1, "$tname: about success");
		ok(ref($data->[1]) eq 'HASH', "$tname: hash is response");

		unless (--$reqs_in_process) {
			logout($cv, $cli, $sid, $tname);
		}

		$cv->end;
	});
}

sub on_connect {
	my ($cv, $tname, $cli) = @_;
	$cv->begin;

	$cli->req(func => "login", args => [{ login => $tests{$tname}{login}, password => $tests{$tname}{pass} }],
		cb => sub {
			my $data = shift;
			ok(ref($data) eq 'ARRAY', "$tname: array found");
			ok(@$data == 2, "$tname: array contains 2 elements");
			ok($data->[0] == $tests{$tname}{ok}, "$tname: Login complete ok");

			if ($tests{$tname}{ok}) {
				login_ok($cv, $cli, $data->[1], $tname);
			}

			$cv->end;
		});
}

for my $t (keys %tests) {
	$cv->begin;

	my $cli = CakeClient->new(on_error => sub {
		ok(0, "$t: error happen: $_[0]");
	});

	$cli->connect(
		host => $cfg->{listen}{host},
		port => $cfg->{listen}{port},
		client => 'test',
		client_key => '3',
		cb => sub {
			on_connect($cv, $t, $cli);
			$cv->end;
		});
	push @__stuff, $cli;
}

$cv->recv;

$cv = AnyEvent->condvar;
my @sids;
for my $try (0..10) {
	$cv->begin;
	my $cli = CakeClient->new(on_error => sub {
		ok(0, "Try $try: error happen: $_[0]");
	});

	$cli->connect(
		host => $cfg->{listen}{host},
		port => $cfg->{listen}{port},
		client => 'test',
		client_key => '3',
		cb => sub {
			$cv->begin;

			$cli->req(func => "login", args => [{ login => 'test', password => 'test' }],
				cb => sub {
					my $data = shift;
					ok(ref($data) eq 'ARRAY', "try $try: array found");
					ok(@$data == 2, "try $try: array contains 2 elements");

					$cv->end;
					push @sids, $data->[1];
				});

			$cv->end;
		});
	push @__stuff, $cli;
}

$cv->recv;

$cv = AnyEvent->condvar;
$cv->begin;
my $cli = shift @__stuff;
$cli->req(func => "logout", args => [ shift(@sids), 1 ], # force close
	cb => sub {
		my $data = shift;
		ok(ref($data) eq 'ARRAY', "Session force close: array found");
		ok(@$data == 2, "Session force close: array contains 1 elements");
		ok($data->[0] == 1, "Session force close: Login complete ok");

		check($cv, $cli, $_, "after force logout", 0)
			for @sids;
		$cv->end;
	});

$cv->recv;

done_testing;
