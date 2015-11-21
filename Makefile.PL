#!/usr/bin/perl

use strict;
use warnings;

# ExtUtils::AutoInstall Bootstrap Code, version 7.
BEGIN{
	my $p = 'ExtUtils::AutoInstall';
	my $v = 0.45;
	$p->VERSION || 0 >= $v or
		+eval "use $p $v; 1" or
		+do {
			my $e = $ENV{PERL_EXTUTILS_AUTOINSTALL};
			(
				!defined($e) || $e !~ m/--(?:default|skip|testonly)/ and
				-t STDIN or
				eval "use ExtUtils::MakeMaker; WriteMakefile( PREREQ_PM => {'$p',$v} ); 1" and
				exit
			) and
			print "==> $p $v required. Install it from CPAN? [Y/n] " and
			<STDIN> !~ /^n/i and
			print "*** Installing $p\n" and
			do {
				if (eval '$>' and lc(`sudo -V`) =~ /version/) {
					system('sudo', $^X, "-MCPANPLUS","-e","CPANPLUS::install $p");
					eval "use $p $v; 1" || system('sudo', $^X, "-MCPAN", "-e", "CPAN::install $p");
				}
				eval {
					require CPANPLUS;CPANPLUS::install$p
				};
				eval "use $p $v; 1" or
				eval {
					require CPAN;
					CPAN::install $p
				};
				eval "use $p $v; 1" || die "*** Please manually install $p $v from cpan.org first...\n"
			}
		}
}

my %deps;
BEGIN {
	%deps = (
		'EV'			=> '',
		'Errno'			=> '',
		'FindBin'		=> '',
		'CBOR::XS'		=> '',
		'JSON::XS'		=> '',
		'AnyEvent'		=> '',
		'Pod::Man'		=> '',
		'Pod::Usage'		=> '',
		'Scalar::Util'		=> '',
		'Getopt::Long'		=> '',
		'AnyEvent::Handle'	=> '',
		'AnyEvent::Memcached'	=> '',
		'AnyEvent::Socket'	=> '',
		'Data::Dumper::OneLine'	=> '',
	);
}

use ExtUtils::AutoInstall (
	-core => [
		%deps,				# project deps
		'ExtUtils::MakeMaker'	=> '',	# build deps
	],
);

# install required modules while generating Makefile
# just a hack not to add a Module::Install module to the repo
ExtUtils::AutoInstall->install([], %deps);

use ExtUtils::MakeMaker;

WriteMakefile(
	NAME		=> 'CheeseCake',
	VERSION		=> '0.1',
	AUTHOR		=> 'Pavel Berezhnoy <pberejnoy2005@gmail.com>',
	LICENSE		=> 'GPL',
	MAN3PODS	=> {
		'README.pod'		=> 'blib/man3/CheeseCake.l',
	},
	dist		=> {
		COMPRESS		=> 'gzip -9f',
		SUFFIX			=> 'gz',
	},
	PREREQ_PM	=> { map { $_ => ($deps{$_} || 0) } keys %deps },
);
