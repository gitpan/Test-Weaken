package Test::Weaken;

# This is beta software.  Be careful.  Note that Test::Weaken is
# primarily targeted to testing and debugging in any case, not to
# production environments.

use vars qw(@ISA @EXPORT_OK $VERSION);
require Exporter;

@ISA       = qw(Exporter);
@EXPORT_OK = qw(poof);
$VERSION   = '0.002001';
$VERSION   = eval $VERSION;

use warnings;
use strict;

use Carp;
use Scalar::Util qw(refaddr reftype isweak weaken);

=begin Implementation:

The basic strategy: get a list of all the references, attempt to
free the memory, and check the references.  If the memory is free,
they'll be undefined.

References to be tested are kept as references to references.  For
convenience, I will call these ref-refs.  They're necessary for
testing both weak and strong references.

If you copy a weak reference, the result is a strong reference.
There may be good reasons for it, but that behavior is a big problem
for this module.  Copying is difficult to avoid because a lot of
useful Perl constructs copy their arguments implicitly.  Creating
strong refs to the weak refs allows the code to avoid directly
manipulating the weak refs, ensuring they stay weak.

In dealing with strong references, I also need references to
references, but for a different reason.  In keeping the strong
references around to test that they go to undefined when released,
there's a Heisenberg paradox or, less pretentiously, a
chicken-and-egg situation.  As long as there is an unweakened
reference, the memory will not be freed.  The solution?  Create
references to the strong references, and before the test, weaken
the first layer of references.  The weak refs will allow their
strong refs to be freed, but the defined-ness of the strong refs
can still be tested via the weak refs.

=end

=cut

# See POD, below
sub poof {

    my $closure    = shift;
    my $type = reftype $closure;
    croak("poof() argument must be code ref") unless $type eq "CODE";

    my $base_ref = $closure->();
    $type = ref $base_ref;
    carp("poof() argument did not return a reference") unless $type;

    # reverse hash -- maps strong ref address back to a reference to the reference
    my $reverse = {};

    # the current working set -- initialize to our first ref
    my $workset = [ \$base_ref ];

    # an array of strong references to the weak references
    my $weak = [];
    my $strong = [];

    # Loop while there is work to do
    WORKSET: while (@$workset) {

        # The "follow-up" array, which holds those ref-refs to be 
        # be worked on in the next pass.
        my $follow = [];

        # For each ref-ref in the current workset
        REF: for my $rr (@$workset) {
            my $type = reftype $$rr;

            # If it's not a reference, nothing to do.
            next REF unless defined $type;

            # We push weak refs into a list, then we're done.
            # We don't follow them.
            if ( isweak $$rr) {
                push( @$weak, $rr );
                next REF;
            }

            # Put it into the list of strong refs
            push(@$strong, $rr);

            # If we've followed another ref to the same place before,
            # we're done
            if ( defined $reverse->{ refaddr $$rr } ) {
                next REF;
            }

            # If it's new, first add it to the hash
            $reverse->{ refaddr $$rr } = $rr;

            # Note that this implementation ignores refs to closures

            # If it's a reference to an array
            if ( $type eq "ARRAY" ) {

                # Index through its elements to avoid
                # copying any which are weak refs
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

        } # REF

        # Replace the current work list with the items we scheduled
        # for follow up
        $workset = $follow;

    }    # WORKSET

    # For the strong ref-refs, weaken the first reference so the array
    # of strong references does not affect the test
    for my $rr (@$strong) {
        weaken( $rr );
    }

    # Record the original counts of weak and strong references
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

Beta Version

This is beta software.  Be careful.  Note that Test::Weaken is
primarily targeted to testing and debugging in any case, not to
production environments.

=head1 SYNOPSIS

Frees an object and checks that the memory was freed.  This module
is intended for use in test scripts, to check that the programmer's
strategy for weakening circular references does indeed work as
expected.

    use Test::Weaken qw(poof);

    my $test = sub {
           my $obj1 = new Module::Test_me1;
           my $obj2 = new Module::Test_me2;
           [ $obj1, $obj2 ];
    };  

    my $freed_ok = Test::Weaken::poof( $test );

    my ($weak_count, $strong_count, $weak_unfreed, $strong_unfreed)
        = Test::Weaken::poof( $test );

    print scalar @$weak_unfreed,
        " of $weak_count weak references freed\n";
    print scalar @$strong_unfreed,
        " of $strong_count strong references freed\n";

    print "Weak unfreed references: ",
        join(" ", map { "".$_ } @$weak_unfreed), "\n";
    print "Strong unfreed references: ",
        join(" ", map { "".$_ } @$strong_unfreed), "\n";

C<Test::Weaken> is intended for testing and debugging, rather than use in production code.

=cut

=head1 EXPORT

By default, C<Test::Weaken> exports nothing.  Optionally, C<poof> may be exported.

=head1 FUNCTION

=head2 poof( CLOSURE )

C<poof> takes a subroutine reference as its only argument.  The
subroutine should construct the the object to be tested and return
a reference to it.  C<poof> frees that object, then checks every
reference in it to ensure that all references were released.  In
scalar context, it returns a true value if the memory was properly
released, false otherwise.

In array context, C<poof> returns counts of the references in the
original object and arrays with references to the references not
freed.  Specifically, in an array context, C<poof> returns a list
with four elements: first, the starting count of weak references;
second, the starting count of strong references; third, a reference
to an array containing references to the unfreed weak references;
fourth, a reference to an array containing references to the unfreed
strong references.

The name C<poof> was intended to warn the programmer that the test
is destructive.  I originally called the main subroutine C<destroy>,
but that choice seemed unfortunate because of similarities to
C<DESTROY>, a name reserved for object destructors.

C<poof>'s way of obtaining the reference to be tested may seem
roundabout.  In fact, the indirect method turns out to be easiest.
The reference to be tested must not have any strong references to
it from outside.  One way or another, some craft is required for
the calling environment to create and pass an object without holding
any reference to it.  Any mistake produces a false negative, one
which is quite difficult to distinguish from a real negative.  The
direct approach turns out to cost more trouble than it saves.

=cut

=head1 LIMITATIONS

This module does not look inside code references.

This module assumes the object returned from the subroutine is
self-contained, that is, that there are no references to
memory outside the object to be tested.
If there are, the results will be hard to interpret, because the
test assumes all referenced memory to should be freed.
Additionally, the unfreed memory will be altered.
To distinguish C<undef>'s in the original data from those which result
from freeing of memory, C<Test::Weaken> overwrites them with the
number 42.

=head1 AUTHOR

Jeffrey Kegler

=head1 BUGS

None known at present, but see B<LIMITATIONS>.

Please report any bugs or feature requests to C<bug-test-weaken at
rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test-Weaken>.  I
will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.

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

Potential users will want to compare C<Test::Memory::Cycle> and
C<Devel::Cycle>, which examine existing structures non-destructively.
C<Devel::Leak> also covers similar ground, although it requires
Perl to be compiled with C<-DDEBUGGING> in order to work.  Devel::Cycle
looks inside closures if PadWalker is present, a feature C<Test::Weaken>
does not have at present.

=head1 ACKNOWLEDGEMENTS

Thanks to jettero, Juerd and perrin of Perlmonks for their advice.
Thanks also to Lincoln Stein (developer of C<Devel::Cycle>) for
test cases and other ideas.

=head1 COPYRIGHT & LICENSE

Copyright 2007 Jeffrey Kegler, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;    # End of Test::Weaken

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
