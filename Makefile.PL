#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

my $preop = q% perl -MPod::Man -e "Pod::Man->new(version => ${VERSION}, section => 3)->parse_from_file('README.pod', '${NAME}.l')" %;

WriteMakefile(
	NAME		=> 'CheeseCake',
	VERSION		=> '0.1',
	AUTHOR		=> 'Pavel Berezhnoy <pberejnoy2005@gmail.com>',
	LICENSE		=> 'GPL',
	PREREQ_PM	=> {
		'EV'			=> 0,
		'Errno'			=> 0,
		'FindBin'		=> 0,
		'CBOR::XS'		=> 0,
		'JSON::XS'		=> 0,
		'AnyEvent'		=> 0,
		'Pod::Usage'		=> 0,
		'Scalar::Util'		=> 0,
		'Getopt::Long'		=> 0,
		'AnyEvent::Handle'	=> 0,
		'AnyEvent::Memcached'	=> 0,
		'AnyEvent::Socket'	=> 0,
		'Data::Dumper::OneLine'	=> 0,
	},
	BUILD_REQUIRES	=> {
		'Pod::Man'		=> 0,
	},
	MAN3PODS	=> {
		'README.pod'		=> 'blib/man3/CheeseCake.l',
	},
	dist		=> {
		COMPRESS		=> 'gzip -9f',
		SUFFIX			=> 'gz',
		#PREOP			=> $preop,
	},
);
