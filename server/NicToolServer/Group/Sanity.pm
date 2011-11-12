package NicToolServer::Group::Sanity;

#
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

use strict;

@NicToolServer::Group::Sanity::ISA = qw(NicToolServer::Group);

sub new_group {
    my ( $self, $data ) = @_;

    $self->push_sanity_error( 'nt_group_id',
        'Cannot add group to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{'nt_group_id'} );

    if ( $data->{'name'} =~ /([^a-zA-Z0-9 \-\_\'\.\@])/ ) {
        $self->{'errors'}->{'name'} = 1;
        push(
            @{ $self->{'error_messages'} },
            "Group name contains an invalid character - \"$1\". Only A-Z, 0-9, ', _, ., -, and [spaces] are allowed."
        );
    }

    unless ( length( $data->{'name'} ) > 2 ) {
        $self->{'errors'}->{'name'} = 1;
        push(
            @{ $self->{'error_messages'} },
            'Group name must be at least 3 characters.'
        );
    }

    unless ( lc( $data->{'name'} ) =~ /^[a-z0-9]/ ) {
        $self->{'errors'}->{'name'} = 1;
        push(
            @{ $self->{'error_messages'} },
            'Group name must start with a letter or number. (A-Z, 0-9)'
        );
    }

    if ( $self->group_exists($data) ) {
        $self->{'errors'}->{'name'} = 1;
        push(
            @{ $self->{'error_messages'} },
            'Group name is already taken at this level.'
        );
    }

    return $self->throw_sanity_error if ( $self->{'errors'} );
    $self->SUPER::new_group($data);
}

sub edit_group {
    my ( $self, $data ) = @_;

    my $dataobj = $self->get_group($data);
    return $dataobj if $self->is_error_response($dataobj);

    $self->push_sanity_error( 'nt_group_id',
        'Cannot edit group in a deleted group!' )
        if $self->check_object_deleted( 'group',
        $dataobj->{'parent_group_id'} );

    $self->push_sanity_error( 'nt_group_id', 'Cannot edit a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{'nt_group_id'} );

    if ( exists $data->{'name'}
        && $data->{'name'} =~ /([^a-zA-Z0-9 \-\_\'\.\@])/ )
    {
        $self->{'errors'}->{'name'} = 1;
        push(
            @{ $self->{'error_messages'} },
            "Group name contains an invalid character - \"$1\". Only A-Z, 0-9, ', _, ., -, and [spaces] are allowed."
        );
    }

    if ( exists $data->{'name'} && length( $data->{'name'} ) < 3 ) {
        $self->{'errors'}->{'name'} = 1;
        push(
            @{ $self->{'error_messages'} },
            'Group name must be at least 3 characters.'
        );
    }

    if ( exists $data->{'name'} && lc( $data->{'name'} ) =~ /^[^a-z0-9]/ ) {
        $self->{'errors'}->{'name'} = 1;
        push(
            @{ $self->{'error_messages'} },
            'Group name must start with a letter or number. (A-Z, 0-9)'
        );
    }

    if ( $self->group_exists_edit($data) ) {
        $self->{'errors'}->{'name'} = 1;
        push(
            @{ $self->{'error_messages'} },
            'Group name is already taken at this level.'
        );
    }

    return $self->throw_sanity_error if ( $self->{'errors'} );
    $self->SUPER::edit_group($data);
}

sub get_group_subgroups {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(group sub_groups parent_group_id) );
    return $self->throw_sanity_error if ( $self->{'errors'} );
    return $self->SUPER::get_group_subgroups($data);
}

sub get_global_application_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(timestamp user action object title description) );
    return $self->throw_sanity_error if ( $self->{'errors'} );
    return $self->SUPER::get_global_application_log($data);
}

sub group_exists {
    my ( $self, $data ) = @_;

    my $sql
        = "SELECT * FROM nt_group WHERE deleted=0 AND parent_group_id = ? AND name = ?";
    my $groups
        = $self->exec_query( $sql, [ $data->{nt_group_id}, $data->{name} ] );

    return ref $groups->[0] ? 1 : 0;
}

sub group_exists_edit {
    my ( $self, $data ) = @_;

    my $sql
        = "SELECT * FROM nt_group INNER JOIN nt_group as g "
        . "ON nt_group.parent_group_id=g.parent_group_id "
        . "AND nt_group.nt_group_id != g.nt_group_id "
        . "WHERE nt_group.deleted=0 AND g.nt_group_id = ?"
        . "AND nt_group.name = ?";
    my $groups = $self->exec_query( $sql,
        [ $data->{nt_group_id}, $data->{'name'} ] );
    return ref $groups->[0] ? 1 : 0;
}

1;
