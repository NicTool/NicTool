package NicTool::DBObject;
use strict;
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


=head1 NAME

NicTool::DBObject - Abstract class representing an object in the 
NicTool system. Subclass of B<NicTool::Result>

=head1 SUMMARY

Subclasses of this class represent objects in the NicTool system 
with knowledge 
about what API functions pertain to them, and what parameters to
include automatically in those function calls.  They also know of a 
parameter to
name their ID number. Instances have an ID number.

=head1 METHODS

=over

=cut

use Carp;

use lib 'lib';
use NicTool::Result;

our @ISA = 'NicTool::Result';

=item _api

This abstract method should be overridden by a subclass. It returns a 
hashref containing information about API functions known to the 
subclass.

=cut

sub _api {
    die "This method needs to be overridden in a subclass";
}

=item _id_name

This abstract method should be overridden by a sublcass.  It returns 
the name of the parameter containing the ID of this type of object.

=cut

sub _id_name {
    die "This method needs to be overridden in a subclass";
}

=item id

Returns the ID of this object.

=cut

sub id {
    return $_[0]->get( $_[0]->_id_name );
}

=item result

Returns the result of the last API function call.

=cut

sub result {
    return $_[0]->{nt}->result;
}

=item nt_user_session

Returns the session string for the session.

=cut

sub nt_user_session {
    return $_[0]->{nt}->nt_user_session;
}

sub _api_call {
    my $self   = shift;
    my $method = shift;
    if ( $self->_api->{$method} ) {
        return 1;
    }
    else {
        return '';
    }
}

sub _call {
    my $self   = shift;
    my $method = shift;
    my %data   = @_;
    if ( $self->is_error ) {
        confess "Attempting to call method $method on an error result";
    }
    if ( $self->_api->{$method}->{sully} ) {
        $self->{nt}->_cache_sully_object($self);
    }
    if ( $self->_api->{$method}->{includeid} ) {
        $data{ $self->_id_name } = $self->id
            unless exists $data{ $self->_id_name };
    }
    foreach ( @{ $self->_api->{$method}->{include} } ) {
        $data{$_} = $self->get($_) unless exists $data{$_};
    }
    foreach ( keys %{ $self->_api->{$method}->{includeas} } ) {
        $data{$_} = $self->get( $self->_api->{$method}->{includeas}->{$_} )
            unless exists $data{$_};
    }
    my $apimethod = $self->_api->{$method}->{function} || $method;

    #check cache for object
    my $obj;
    if ( $self->{nt}->_should_cache->{$method} ) {
        $obj = $self->{nt}->_cache_get(
            NicTool::API->result_type($apimethod),
            $data{ $self->{nt}->_should_cache->{$method} }
        );
        return $obj if $obj;
    }
    $obj = $self->{nt}->_dispatch( $apimethod, %data );
    if ( $self->{nt}->_should_cache->{$method} ) {
        $self->{nt}->_cache_object($obj) if !$obj->is_error;
    }
    return $obj;
}

=item refresh

Causes the object to refresh its data from the server by calling  
the appropriate API function.

=cut

sub refresh {
    my $self = shift;
    my $obj  = $self->_get_self;
    return $obj if $obj->is_error;
    $self->{store} = $obj->{store};
    $obj = undef;
    return $self;
}

=item delete

Calls appropriate function to delete the object from the NicTool Server.

=cut

sub delete {
    my $self = shift;
    my $res  = $self->_delete_self;
    return $res;
}

=item is_deleted

Returns the value of the 'deleted' property.  (equivalent to calling 
$obj->get('deleted');

=cut

sub is_deleted {
    my $self = shift;
    return $self->get('deleted');
}

=item FUNCTION(PARAMS)

See specific subclasses of this class for which API functions can be
called directly through this object.

=cut

sub AUTOLOAD {
    my ($self) = shift;
    return if $NicTool::DBObject::AUTOLOAD =~ /DESTROY/;
    $NicTool::DBObject::AUTOLOAD =~ s/.*:://;
    if ( $self->_api_call($NicTool::DBObject::AUTOLOAD) ) {
        return $self->_call( $NicTool::DBObject::AUTOLOAD, @_ );
    }
    if ( $NicTool::DBObject::AUTOLOAD =~ /can_([^:]+)$/ ) {
        return $self->get($1);
    }

    #warn "Can't call $NicTool::DBObject::AUTOLOAD : ".(caller);
    return;
}

=pod

=back

=head1 SUPERCLASS

=over

=item *

L<NicTool::Result>

=back

=head1 KNOWN SUBCLASSES

=over

=item *

L<NicTool::Group>

=item *

L<NicTool::User>

=item *

L<NicTool::Zone>

=item *

L<NicTool::Record>

=item *

L<NicTool::Nameserver>

=back

=cut

1;
