#!/usr/bin/perl
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

package NicTool::NTObject;

=head1 NAME

NicTool::NTObject - The base class for objects in the NicTool client framework.

=head1 SYNOPSIS

    my $obj = NicTool::NTObject->new(key=>'value',key2=>'value2');

=head1 DESCRIPTION

This is the base class for representing objects in the NicTool system.
It provides a mechanism for getting/setting/checking attributes, and contains some
meta-data for use by the B<NicTool> class.

=head1 METHODS

=over

=item new(PARAMS)

Creates a new object using the specified params as the attributes for the object.
If the first item in PARAMS is a hash ref, that hash ref is used as the attributes
hash instead, making it easy to use results of NicTool API calls which all return
a single hash ref.

=cut

sub new {
    my $group = shift;
    my @rest  = @_;
    my $self;
    if ( ref $rest[0] eq 'HASH' ) {
        $self = $rest[0];
    }
    else {
        $self = {@rest};
    }

    return bless { store => $self, type => undef, parent => undef }, $group;
}

=item type

Returns the type of the object.

=cut

sub type {
    return $_[0]->{type};
}

sub parent {
    return $_[0]->{parent};
}

=item get(KEY,...)

Returns the value of the attribute named KEY if only one KEY is 
specified.
If more than one key is specified, returns an array of all of the values
of the attributes in the same order.

=cut

sub get {
    my $self = shift;

    return $self->{store}->{ $_[0] } if scalar @_ == 1;

    if ( scalar @_ > 1 ) {
        my @r;
        foreach ( @_ ) { push @r, $self->{store}{$_}; };
        return @r;
    };

    my ( $package, $filename, $line ) = caller;
    warn "package $package at line $line called NTObject::get with invalid parameters!\n";
    return;
}

=item set(KEY=>VALUE,...)

Sets the value of each attribute KEY to the appropriate VALUE.

=cut

sub set {
    my $self = shift;
    while ( @_ gt 0 && @_ % 2 == 0 ) {
        unless ( defined $_[-1] && defined $_[-2] ) { pop @_; pop @_; next; }
        $self->{store}->{ $_[-2] } = $_[-1];
        pop @_;
        pop @_;
    }
}

=item has(KEY)

Returns a TRUE value if an attribute named KEY exists.

=cut

sub has {
    my $self = shift;
    return exists $self->{store}{ $_[0] };
}

sub sob {
    my $self = shift;
    foreach ( keys %{ $self->{store} } ) {
        print "$_ = " . Data::Dumper::Dumper( $self->get($_) );
    }

}

=pod

=back

=head1 KNOWN SUBCLASSES

L<NicTool::Result>

=cut

1;
