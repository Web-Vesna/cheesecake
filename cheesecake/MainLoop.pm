package MainLoop;

use strict;
use warnings;

use CakeConfig;

use base qw( Exporter );

our @EXPORT = qw(
	main_loop
);

sub main_loop {
	use Data::Dumper;
	warn Dumper config();
}

1;
