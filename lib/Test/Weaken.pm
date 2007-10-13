package Test::Weaken;

# This is alpha software, not at present suitable for any purpose
# except reading and experimentation

use vars qw(@ISA @EXPORT_OK $VERSION);
require Exporter;

@ISA       = qw(Exporter);
@EXPORT_OK = qw(poof);
$VERSION   = '0.001_004';
$VERSION   = eval $VERSION;

use warnings;
use strict;

use Scalar::Util qw(refaddr reftype isweak weaken);

=begin Implementation:

The basic strategy: get a list of all the references, attempt to
free the memory, and check them.  If the memory is free, they'll
be undefined.

References to be tested are kept as references to references.  For
convenience, I will call these ref-refs.  They're necessary for both
testing both weak and strong references, but for different reasons.

In dealing with weak references, any copy strengthens it, which is
disastrous for the accuracy of this test.  Copying is difficult to
avoid because things a lot of useful Perl ops copy their arguments
implicitly.  Creating strong refs to the weak refs and not directly
manipulating the weak refs, keeps them weak.

In dealing with strong references, I also need references to
references, but for a different reason.  In keeping the strong
references around to test that they go to undefined when released,
there's a Heisenberg paradox (or a chicken-and-egg situation, for
the less pretentious).  As long as there is an unweakened reference,
the memory will not be freed.  The solution?  Create references to
the strong references, and before the test, weaken the first layer
of references.  The weak refs will allow their strong refs to be
freed, on one hand, but the undefined of the strong refs can still
be tested via the weak refs.

=end

=cut

# See POD, below
sub poof {
    my $closure    = shift;
    my $base_ref = $closure->();

    # reverse hash -- maps strong ref address back to a reference to the reference
    my $reverse = {};

    # the current working set -- initialize to our first ref
    my $workset = [ \$base_ref ];

    # an array of strong references to the weak references
    my $weak = [];

    # Loop while there is work to do
    WORKSET: while (@$workset) {

        # The "follow-up" array, which hold those ref-refs to be 
        # be worked on in the next pass.
        my $follow = [];

        # For each ref-ref in the current workset
        REF: for my $rr (@$workset) {
            my $type = reftype $$rr;

            # If for some reason it's not a reference,
            # (bad return from the argument subroutine?)
            # nothing to do.
            next REF unless defined $type;

            # We push weak refs into a list, then we're done.
            # We don't follow them.
            if ( isweak $$rr) {
                push( @$weak, $rr );
                next REF;
            }

            # We deal only with refs to arrays, hashes and refs
            # In particular, this implementation ignores refs to closures
            if ( $type eq "ARRAY" or $type eq "HASH" or $type eq "REF" ) {

                # If we've handled this ref before, we're done
                if ( defined $reverse->{ refaddr $$rr} ) {
                    next REF;
                }

                # If it's new, first add it to the hash
                $reverse->{ refaddr $$rr} = $rr;

                # If it's a reference to an array
                if ( $type eq "ARRAY" ) {

                    # Index through its elements to avoid copying any which are weak refs
                    ELEMENT: for my $ix ( 0 .. $#$$rr ) {

                        # Obviously, no need to deal with non-existent elements
                        next ELEMENT unless exists $$rr->[$ix];

                        # If it's defined, put it on the follow-up list
                        if ( defined $$rr->[$ix] ) {
                            push( @$follow, \( $$rr->[$ix] ) );
                        }
                        else {
                            # Not defined (but exists)
                            # Set it to a number so it doesn't fool us later
                            # when we check to see that it was freed
                            $$rr->[$ix] = 42;
                        }
                    }
                    next REF;
                }

                # If it's a reference to a hash
                if ( $type eq "HASH" ) {

                    # Iterate through the keys to avoid copying any values which are weak refs
                    for my $ix ( keys %$$rr ) {

                        # If it's defined, put it on the follow-up list
                        if ( defined $$rr->{$ix} ) {
                            push( @$follow, \( $$rr->{$ix} ) );
                        }
                        else {
                            # Hash entry exists but is undef
                            # Set it to a number so it doesn't fool us later
                            # when we check to see that it was freed
                            $$rr->{$ix} = 42;
                        }
                    }
                    next REF;
                }

                # If it's a reference to a reference,
                # put a reference to the reference to a reference (whew!)
                # on the follow up list
                if ( $type eq "REF" ) {
                    push( @$follow, \$$$rr );
                }

            }    # if (

        }    # REF

        # Replace the current work list with the items we scheduled
        # for follow up
        $workset = $follow;

    }    # WORKSET

    # We created a array of weak ref-refs above, now do the same for
    # the strong ref-refs, and weaken the first reference so the array
    # of strong references does not affect the test;
    my $strong = [];
    my $ix     = 0;
    for my $ref ( values %$reverse ) {
        weaken( $strong->[ $ix++ ] = $ref );
    }

    # Get the original counts for weak and strong references
    my $weak_count   = @$weak;
    my $strong_count = @$strong;

    # Now free everything.  Note the weaken of the base_ref --
    # it's necessary so that the counts work out right.
    $reverse = undef;
    $workset = undef;
    weaken($base_ref);

    # The implicit copy below will strengthen the weak references
    # but it no longer matters, since we have our data
    my @unfreed_strong = map {$$_} grep { defined $$_ } @$strong;
    my @unfreed_weak   = map {$$_} grep { defined $$_ } @$weak;

    # See the POD on the return values
    return
        wantarray
        ? ( $weak_count, $strong_count, \@unfreed_weak, \@unfreed_strong )
        : ( @unfreed_weak + @unfreed_strong );

} ## end sub poof

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

    use Test::Weaken qw(poof);

    my $test = sub {
           my $obj1 = new Module::Test_me1;
           my $obj2 = new Module::Test_me2;
           [ $obj1, $obj2 ];
    };  

    my $freed_ok = Test::Weaken::poof( $test );

    my ($weak_count, $strong_count, $weak_unfreed, $strong_unfreed)
        = Test::Weaken::poof( $test );

    print scalar @$weak_unfreed, " of $weak_count weak references freed\n";
    print scalar @$strong_unfreed, " of $strong_count strong references freed\n";

    print "Weak unfreed references: ", join(" ", map { "".$_ } @$weak_unfreed), "\n";
    print "Strong unfreed references: ", join(" ", map { "".$_ } @$strong_unfreed), "\n";

C<Test::Weaken> is intended for testing and debugging, rather than use in production code.

=cut

=head1 EXPORT

By default, C<Test::Weaken> exports nothing.  Optionally, C<poof> may be exported.

=head1 FUNCTION

=head2 poof

poof( CLOSURE )

C<poof> takes a subroutine reference as its only argument.
The subroutine should return a reference to the object to be tested.
To avoid false negatives, the subroutine should be anonymous.
C<poof> frees that object, then checks each reference to ensure it has been released.
In scalar context, it returns a true value if the memory was properly released, false otherwise.

In array context, C<poof> returns a list containing the references counts from the original object and
arrays with references to the references not freed.
Specifically, in an array context, C<poof> returns a list with four elements:
first, the starting count of weak references;
second, the starting count of strong references;
third, a reference to an array containing references to the unfreed weak references;
fourth, a reference to an array containing references to the unfreed strong references.

C<poof> is named in order to emphasize that the test is destructive.
Its way of accepting the reference to be tested --
requiring that its argument be a subroutine reference which returns the reference to be tested --
may seem roundabout.
In fact, it turned out to be easiest, because the reference to be tested must not have any strong
references to it from outside.
If there is an unnoticed, extra, strong reference, a false negative results.
Avoiding strong references from the calling environment turns out to be very tricky to do,
and when I tried to pass references directly,
I spent most of my time weeding out false negatives.
Having the argument be returned from a subroutine which goes out of existence the moment it
returns, turns out to be the easiest way to guarantee that the only strong references to that
argument are internal.

=cut

=head1 LIMITATIONS

This module does not look inside code references.

This module assumes the object returned from the subroutine is
self-contained, that is, that there are no references to outside memory.
If there are, bad things will happen.
Most seriously, to distinguish C<undef>'s in the
original data from those which result from freeing of memory, C<Test::Weaken>
overwrites them with the number 42.
Less, the results reported by C<Test::Weaken> will include the outside
memory, probably not be what you wanted.

=head1 AUTHOR

Jeffrey Kegler

=head1 BUGS

None known at present, but see B<LIMITATIONS>.

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

=head1 SEE ALSO

Potential users will want to compare C<Test::Memory::Cycle>
and C<Devel::Cycle>, which examine existing structures non-destructively.
C<Devel::Leak> also covers similar ground, although it requires Perl
to be compiled with
C<-DDEBUGGING> in order to work.
Devel::Cycle looks inside closures
if PadWalker is present, and I may enhance this module to do likewise.

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

1;    # End of Test::Weaken

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:

=head1 NAME
