#!/usr/bin/perl

use strict;
use warnings;

# ExtUtils::AutoInstall Bootstrap Code, version 7.
BEGIN {
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

my @deps;
BEGIN {
	@deps = (
		'FindBin'		=> '0',
		'Pod::Man'		=> '0',
		'Pod::Usage'		=> '0',
		'Getopt::Long'		=> '0',
		'List::Util'		=> '0',
		'Errno'			=> '0',
		'EV'			=> '0',
		'AnyEvent'		=> '0',
		'CBOR::XS'		=> '0',
		'JSON::XS'		=> '0',
		'DBD::mysql'		=> '0',
		'Digest::MD5'		=> '0',
		'Scalar::Util'		=> '0',
		'AnyEvent::Handle'	=> '0',
		'AnyEvent::Socket'	=> '0',
		'Devel::StackTrace'	=> '0',
		'AnyEvent::Memcached'	=> '0',
		'Data::Dumper::OneLine'	=> '0',
		'Mail::RFC822::Address'	=> '0',
	);
}

use ExtUtils::AutoInstall (
	-core => [
		@deps,				# project deps
		'ExtUtils::MakeMaker'	=> '',	# build deps
	],
);

# install required modules while generating Makefile
# just a hack not to add a Module::Install module to the repo
ExtUtils::AutoInstall->install([], @deps);

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
	PREREQ_PM	=> { @deps },
	BUILD_REQUIRES	=> {
		'AnyEvent'		=> '0',
		'Test::More'		=> '0',
		'Cwd'			=> '0',
	},
);
