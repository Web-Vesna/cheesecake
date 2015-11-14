#!/usr/bin/perl

use strict;
use warnings;

# parse given args
use Getopt::Long;
use Pod::Usage;
use FindBin;

use lib $FindBin::Bin;

my %console_args = (
	# default console arguments
);

GetOptions(
	'config=s'	=> \$console_args{config},
	'log_level=i'	=> \$console_args{log_lvl},
	'telnet'	=> \$console_args{use_telnet},
	'help'		=> \$console_args{help},
	'man'		=> \$console_args{man},
);

my $readme_file = $FindBin::Bin . '/../README.pod';
unless (-f $readme_file) {
	die "README file not found ($readme_file)!\n";
}

pod2usage(
	-exitval	=> 1,
	-input		=> $readme_file,
	-verbose	=> 0, # only SYNOPSIS will be printed
) if $console_args{help};

pod2usage(
	-exitval	=> 1,
	-input		=> $readme_file,
	-verbose	=> 2, # full README will be printed
) if $console_args{man};

die "Config file path is required\n"
	unless $console_args{config};

die "Can't open config file ($console_args{config}) for reading: $!\n"
	unless -r $console_args{config};

use Logger qw( set_log_lvl );
if ($console_args{log_lvl}) {
	set_log_lvl($console_args{log_lvl});
}

use CakeConfig qw( read_config );
read_config($console_args{config});

use CakeProto qw( telnet_mode );
telnet_mode($console_args{use_telnet});

use MainLoop qw( main_loop );
main_loop;

1;
