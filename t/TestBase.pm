package TestBase;

use strict;
use warnings;
use Cwd qw( abs_path );

use base qw( Exporter );

use lib qw( ../cheesecake ../client CheeseCake );

our @EXPORT = qw(
	cfg_name
);

my $path = abs_path($0);
$path =~ s#/[^/]*$##;

sub cfg_name { "$path/../config" };

1;
