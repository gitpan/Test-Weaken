use strict;
use warnings;

use Test::More tests => 2;
use Scalar::Util qw(isweak weaken reftype);

BEGIN {
	use_ok( 'Test::Weaken' );
}


my ($wc, $sc, $wa, $sa) = Test::Weaken::poof(sub {
	my $a;
	my $b = [ \$a, 42];
	$a = [ \$b, 711];
	weaken($a->[2] = \$b);
	weaken($b->[2] = \$a);
	$a;
    }
);

my $text = "Starting counts: w=$wc  s=$sc\nUnfreed counts: w=" . scalar @$wa . "  s=" . scalar @$sa . "\n";

# names for the references, so checking the dump does not depend
# on the specific hex value of locations
my %name;
my %ref_number;

sub name {
    my $r = shift;
    my $name = $name{$r};
    return $name if defined $name;
    return "$r";
}

sub give_name {
    my $r = shift;
    return if defined $name{$r};
    my $type = reftype $r;
    my $prefix = "r";
    if ($type eq "REF") {
        $name{$r} = $prefix . $ref_number{$prefix}++;
	give_name($$r);
	return;
    }
    if ($type eq "ARRAY") {
	$prefix = "a";
        $name{$r} = $prefix . $ref_number{$prefix}++;
	return;
    }
}

STRONG: for (my $ix = 0; $ix <= $#$sa; $ix++) {
    give_name($sa->[$ix]);
}

for (my $ix = 0; $ix <= $#$sa; $ix++) {
    my $r = $sa->[$ix];
    $text .= "Unfreed strong ref $ix: " .
	name($r) . " => ";
    my $type = reftype $r;
    if ($type eq "REF") {
 	$text .=
	    "". name($$r) . " == " .
	    "[ ".
	    join(", ",
		map { my $t = reftype $_; (defined $t && $t eq "REF") ? name($_) : $_ }
		@$$r
	    ) .
	    " ]";
    } elsif ($type eq "ARRAY") {
 	$text .=
	    "[ ".
	    join(", ",
		map { my $t = reftype $_; (defined $t and $t eq "REF") ? name($_) : $_ }
		@$r
	    ) .
	    " ]";
    } else {
 	$text .= $type;
    }
    $text .= "\n";
}

for (my $ix = 0; $ix <= $#$wa; $ix++) {
    my $r = $wa->[$ix];
    $text .= "Unfreed weak   ref $ix:" .
	" ". name($r) . " => " .
	name($$r) . " == " .
	"[ ".
	join(", ",
	    map { my $t = reftype $_; (defined $t and $t eq "REF") ? name($_) : $_ }
	    @$$r)
	. " ]" .
	"\n";
}

is($text, <<'EOS', "Dump of unfreed arrays");
Starting counts: w=2  s=4
Unfreed counts: w=2  s=4
Unfreed strong ref 0: r0 => a0 == [ r1, 711, r1 ]
Unfreed strong ref 1: a1 => [ r0, 42, r0 ]
Unfreed strong ref 2: r1 => a1 == [ r0, 42, r0 ]
Unfreed strong ref 3: a0 => [ r1, 711, r1 ]
Unfreed weak   ref 0: r1 => a1 == [ r0, 42, r0 ]
Unfreed weak   ref 1: r0 => a0 == [ r1, 711, r1 ]
EOS
