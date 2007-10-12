package Test::Weaken;

use vars qw(@ISA @EXPORT_OK $VERSION);
require Exporter;

@ISA       = qw(Exporter);
@EXPORT_OK = qw(poof);
$VERSION = '0.001_002';
$VERSION   = eval $VERSION;

# This is alpha software, not at present suitable for any purpose
# except reading and experimentation

use warnings;
use strict;

use Scalar::Util qw(refaddr reftype isweak weaken);

# Test is destructive, except in case of failure
sub poof {
    my $closure = shift;
    my $strong_ref = $closure->();

    # reverse hash -- maps strong ref address back to a reference to the reference
    my $reverse = {};

    # the current working set -- initialize to our first ref
    my $workset = [ \$strong_ref ];

    # an array of strong references to the weak references
    my $weak = [];

    # need to work with refs to a weak ref, because copying a weak ref (sigh) strengthens it
    WORKSET: while (@$workset) {
        my $follow = [];
        REF: for my $rr (@$workset)
        {
             my $type = reftype $$rr;
             next REF unless defined $type;
             if (isweak $$rr)
             {
                  push(@$weak, $rr);
                  next REF;
             }
             if ($type eq "ARRAY" or $type eq "HASH" or $type eq "REF") {
                  if (defined $reverse->{refaddr $$rr}) {
                       next REF;
                  }
                  $reverse->{refaddr $$rr} = $rr;
                  if ($type eq "ARRAY") {
                      ELEMENT: for my $ix (0 .. $#$$rr) {
                          next ELEMENT unless exists $$rr->[$ix];
                          if (defined $$rr->[$ix]) {
                              push(@$follow, \ ($$rr->[$ix]) );
                          } else {
                              # array entry exists but is undef
                              # set it to a number so it doesn't fool us later
                              $$rr->[$ix] = 42;
                          }
                      }
                      next REF;
                  }
                  if ($type eq "HASH") {
                      for my $ix (keys %$$rr) {
                          if (defined $$rr->{$ix}) {
                              push(@$follow, \ ($$rr->{$ix}) );
                          } else {
                              # hash entry exists but is undef
                              # set it to a number so it doesn't fool us later
                              $$rr->{$ix} = 42;
                          }
                      }
                      next REF;
                  }
                  if ($type eq "REF") {
                      push(@$follow, \$$$rr );
                  }
             }
        }
        $workset = $follow;
    }

    my $strong = [];
    my $ix = 0;
    for my $ref (values %$reverse) {
      weaken($strong->[$ix++] = $ref);
    }

    my $weak_count = @$weak;
    my $strong_count = @$strong;

    weaken($strong_ref);
    $reverse = undef;
    $workset = undef;

    # The below will the weak references will be strengthened through copying,
    # but it no longer matters
    my @unfreed_strong = map { $$_ } grep { defined $$_ } @$strong;
    my @unfreed_weak = map { $$_ } grep { defined $$_ } @$weak;

    return wantarray ? ($weak_count, $strong_count, \@unfreed_weak, \@unfreed_strong) :
        (@unfreed_weak + @unfreed_strong);
}

1;

=head1 NAME

Test::Weaken - Test for leaks after weakening of circular references

=head1 VERSION

Alpha Version

This is alpha software, not at present suitable for any purpose
except reading and experimentation.  Among other issues, this
documentation is still very inadequate.

=head1 SYNOPSIS

Frees an object and checks that the memory was freed.
This module is intended for use in test scripts,
to check that the programmer's strategy for weakening
circular references does 
indeed work as expected.

    use Test::Weaken;

    my $freed_ok = Test::Weaken::poof(
        sub {
	   my $obj1 = new Module::Test_me1;
	   my $obj2 = new Module::Test_me2;
	   [ $obj1, $obj2 ];
	}
    );

=cut

=head1 FUNCTION

=head2 poof

sub poof {
}

C<poof> is named in order to emphasize that the test is destructive.  C<poof> takes a subroutine reference
as its only argument.  The subroutine should return a reference to an object.
C<poof> frees that object, then checks each reference to ensure it has been released.
In scalar context, it returns a true value if the memory was properly released, false otherwise.

In array context, C<poof> returns a list containing the references counts from the original object and
arrays with references to the references not freed.
Specifically, in an array context, C<poof> returns a list with four elements:
first, the starting count of weak references;
second, the starting count of strong references;
third, a reference to an array containing references to the unfreed weak references;
fourth, a reference to an array containing references to the unfreed strong references.

=cut

=head1 AUTHOR

Jeffrey Kegler

=head1 BUGS

Please report any bugs or feature requests to
C<bug-test-weaken at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test-Weaken>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Test::Weaken

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Test-Weaken>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Test-Weaken>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Test-Weaken>

=item * Search CPAN

L<http://search.cpan.org/dist/Test-Weaken>

=back

=head1 LIMITATIONS

Potential users will want to compare C<Test::Memory::Cycle>
and C<Devel::Cycle>, which examine existing structures non-destructively.
C<Devel::Leak> also covers similar ground, although it requires Perl
to be compiled with
C<-DDEBUGGING> in order to work.

This module does not look inside code references.  Devel::Cycle does so
if PadWalker is present, and I may enhance this module to do likewise.

This module assumes the object returned from the subroutine is
self-contained, that is, that there are no references to outside memory.
If there are, bad things will happen.
Most seriously, to distinguish C<undef>'s in the
original data from those which result from freeing of memory, C<Test::Weaken>
overwrites them with the number 42.
Less, the results reported by C<Test::Weaken> will include the outside
memory, probably not be what you wanted.

=head1 ACKNOWLEDGEMENTS

Thanks to jettero, Juerd and perrin of 
Perlmonks for their advice.
Thanks also to Lincoln Stein (developer of C<Devel::Cycle>)
for test cases and other ideas.

=head1 COPYRIGHT & LICENSE

Copyright 2007 Jeffrey Kegler, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Test::Weaken

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
=head1 NAME
