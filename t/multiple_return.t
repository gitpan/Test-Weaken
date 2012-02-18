#!/usr/bin/perl -w

use strict;
use warnings;
use Test::Weaken;
use Test::More tests => 4;

my $global = [ 123 ];
{
  my $test = Test::Weaken::leaks(sub {
                                   my $local = [ 456 ];
                                   return ($global, $local);
                                 });
  my $unfreed_count = $test ? $test->unfreed_count() : 0;
  ok (defined $test, 'global/local multiple return -- leaks');
  is( $unfreed_count, 2, 'global/local multiple return -- count' );
}
{
  my $test = Test::Weaken::leaks(sub {
                                   my $local = [ 456 ];
                                   return ($local, $global);
                                 });
  ok (defined $test, 'local/global multiple return -- leaks');
  my $unfreed_count = $test ? $test->unfreed_count() : 0;
  is($unfreed_count, 2, 'local/global multiple return -- count');
}

exit 0;
