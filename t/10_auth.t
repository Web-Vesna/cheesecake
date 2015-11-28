#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use AnyEvent;

my %test = (
	valid		=> { ok => 1, data => [qw( test 3 )] },
	no_client	=> { ok => 0, data => [qw( test123 3 )] },
	no_key		=> { ok => 0, data => [qw( test 10 )] },
	no_connect	=> { ok => 0, no_connect => 1, host => '123.123.13.123', port => '1028', },
);

plan tests => scalar(keys %test) + 4;

require_ok('TestBase');
require_ok('CakeClient');
require_ok('CakeConfig');

CakeConfig::read_config(TestBase::cfg_name());
my $cfg = CakeConfig::config();

ok(defined $cfg, "Config read");

my $cv = AnyEvent->condvar;

my @__stuff;
for my $t (keys %test) {
	my $error_happen = 0;

	$cv->begin;
	my $cli = CakeClient->new(on_error => sub {
		if ($test{$t}{no_connect}) {
			ok(1, "$t: connecting to unknown service");
		} else {
			ok(!$test{$t}{ok}, "$t: Invalid connect");
		}
		$cv->end;
	});

	$cli->connect(
		host => $test{$t}{host} // $cfg->{listen}{host},
		port => $test{$t}{port} // $cfg->{listen}{port},
		client => $test{$t}{data}[0],
		client_key => $test{$t}{data}[1],
		cb => sub {
			ok($test{$t}{ok}, "$t: Success connect");
			$cv->end;
		});
	push @__stuff, $cli;
}



$cv->recv;
