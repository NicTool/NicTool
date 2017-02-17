package NicTool::List;
###
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under
# the terms of the Affero General Public License as published by Affero,
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#
###



use strict;

use lib 'lib';
use NicTool;
use NicTool::Result;

our @ISA = 'NicTool::Result';
my $iterate = sub {
    my $self = shift;
    my $i    = $self->{iterator};
    $self->{iterator} = $i + 1 if $self->more;
    return $i;
};


sub new {
    my ( $pkg, $nt, $itype, $listparam, @rest ) = @_;
    my $self = $pkg->SUPER::new( $nt, @rest );
    $self->{type}       = 'List';
    $self->{list_param} = $listparam;
    $self->{iterator}   = 0;
    $self->{item_type}  = $itype;

    my @list;
    my $obj;
    if ( $self->get($listparam) ) {
        foreach ( @{ $self->get($listparam) } ) {
            $obj = $nt->_object_for_type( $itype, $_ );
            push @list, $obj;
        }
    }
    $self->set( $listparam, \@list );
    $self->{nt} = $nt;
    return bless $self, $pkg;
}


sub list_param {
    my $self = shift;
    return $self->{list_param};
}


sub item_type {
    my $self = shift;
    return $self->{item_type};
}


sub size {
    my $self = shift;
    return scalar @{ $self->get( $self->list_param ) };
}


sub more {
    my $self = shift;
    return ( $self->size gt 0 ) && ( $self->size gt( $self->{iterator} ) );
}


sub next {
    my $self = shift;
    local *NicTool::List::iterate = $iterate;
    if ( $self->more ) {

        #$self->{iterator} = $self->{iterator} + 1;
        return ${ $self->get( $self->list_param ) }[ $self->iterate ];
    }
    else {
        return '';
    }
}


sub reset {
    my $self = shift;
    $self->{iterator} = 0;
}


sub list {
    my $self = shift;
    return @{ $self->get( $self->list_param ) };
}


sub list_as_ref {
    my $self = shift;
    return $self->get( $self->list_param );
}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::List

=head1 VERSION

version 1.02

=head1 SYNOPSIS

    my $list = $nt->get_group_zones;

=head1 DESCRIPTION

The B<NicTool::List> class provides a simple interface to results of
NicTool API function calls which return lists of data representing
objects.
The following NicTool API calls return lists of a certain type of 
object:

=over

=item get_group_users

List of B<NicTool::Group>s

=item get_user_list

List of B<NicTool::User>s

=item get_group_groups

List of B<NicTool::Group>s

=item get_group_subgroups

List of B<NicTool::Group>s

=item get_group_zones

List of B<NicTool::Zone>s

=item get_zone_records

List of B<NicTool::Record>s

=item get_zone_list

List of B<NicTool::Zone>s

=item get_group_nameservers

List of B<NicTool::Nameserver>s

=item get_nameserver_list

List of B<NicTool::Nameserver>s

=item get_delegated_zones

List of B<NicTool::Zone>s

=item get_delegated_zone_records

List of B<NicTool::Record>s

=item get_zone_delegates

List of B<NicTool::Group>s

=item get_zone_record_delegates

List of B<NicTool::Group>s

=back

Each function call will return a B<NicTool::List> instance with a list
of B<NicTool::Result> subclasses.  B<NicTool::List> provides several
ways of accessing the list.  You can access it using the I<more>, and 
I<next> methods like an Iterator.  You can also access the list 
directly as an array (I<list>) or an array reference (I<list_as_ref>).

=head1 NAME

NicTool::List - A B<NicTool::Result> subclass representing a list of
NicTool objects.

=head1 METHODS

=over

=item new(ITEM_TYPE,LIST_PARAM,PARAMS...)

Creates a new B<NicTool::List> of items of type ITEM_TYPE.  The
parameter specified by LIST_PARAM should contain an array ref of hash
refs suitable for turning into NicTool objects.

=item list_param

Returns the name of the parameter which contains the list objects

=item item_type

Returns the 'type' of the objects in the list.  The class of the
objects can be determined by prepending "NicTool::" to the 'type'.

=item size

Returns the number of items in the list.

=item more

Returns a TRUE value if more items are available via the I<next> method.

=item next

Returns the next object in the list if I<more> is TRUE.

=item reset

Resets the Iterator interface.  After a call to I<reset>, a call to
I<more> will return true if the list is non-empty, and a call to
I<next> will return the first object in the list.

=item list

Returns an array of the objects in the list.

=item list_as_ref

Returns an array ref of the objects in the list.

=back

=head1 SEE ALSO

=over

=item *

L<NicTool::Result>

=item *

L<NicTool>

=back

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abe Shelton

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
