#!perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib $Bin;
use Sample;

my ($x, $y) = @ARGV;

print "--$x--\n";
print "--$y--\n";
print bar(), "\n";

eval <<EOT;
$x = 42
EOT

my $str = Sample::foo();


print "$x\n";

sub bar {
    my $foo = 42;
    $foo += 23;
    return $foo;
}

sleep 1;

$DB::single = 1;

my %x = (
    a => 1,
    b => 2,
    c => 3,
);

1;

