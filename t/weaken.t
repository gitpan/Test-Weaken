#!perl

use strict;
use warnings;

use Test::More tests => 6;
use Test::Weaken;
use Scalar::Util qw(weaken);
use Data::Dumper qw(Dumper);
$Data::Dumper::Maxdepth = 2;

BEGIN {
	use_ok( 'Test::Weaken' );
}

sub brief_result {
   my $text = "total: weak=" . (shift) . "; ";
   $text .= "strong=" . (shift) . "; ";
   $text .= "unfreed: weak=" . scalar @{(shift)} . "; ";
   $text .= "strong=" . scalar @{(shift)};
}

my $result = Test::Weaken::poof(
        sub {
            my $a = [];
            weaken(my $b = []);
        }
    );
cmp_ok($result, "==", 0, "Simple weak ref");

is(
    brief_result(Test::Weaken::poof( sub { my $a = 42; my $b = \$a; $a = \$b; })),
    "total: weak=0; strong=2; unfreed: weak=0; strong=2",
    "Bad Less Simple Cycle"
);

is( brief_result ( Test::Weaken::poof(
    sub { my $a; weaken(my $b = \$a); $a = \$b; $b; } ) ),
    "total: weak=1; strong=2; unfreed: weak=0; strong=0",
    "Fixed simple cycle"
);

is( brief_result( Test::Weaken::poof(
    sub { my $a; my $b = [ \$a ]; my $c = { k1 => \$b }; $a = \$c; [ $a, $b, $c ] } ) ),
    "total: weak=0; strong=6; unfreed: weak=0; strong=2",
    "Bad Complicated Cycle"
);

is( brief_result( Test::Weaken::poof(
    sub { my $a = 42; my $b = [ \$a ]; my $c = { k1 => \$b }; weaken($a = \$c); [ $a, $b, $c ] } ) ),
    "total: weak=1; strong=6; unfreed: weak=0; strong=0",
    "Fixed Complicated Cycle"
);

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
