
use strict;
use warnings;
use English;
use Test::More tests => 2;

use Scalar::Util qw(weaken isweak);

BEGIN { use_ok('Test::Weaken') };

package Module::Test_me1; sub new { bless [], (shift); }
package Module::Test_me2; sub new { bless [], (shift); }

package main;

my $RS = undef;
my $code = `cat ../lib/Test/Weaken.pm`;
$code =~ s/.*^=head1\s*SYNOPSIS\s*$//xms;
$code =~ s/^=cut.*\z//xms;
$code =~ s/^\S[^\n]*$//xmsg;
eval $code;
if ($@) {
    fail("Synopsis code failed: $@");
} else {
    pass("Synopsis is good code");
}

