package NicToolServer::Group::Sanity;
# ABSTRACT: sanity tests for NicTool groups

use strict;

@NicToolServer::Group::Sanity::ISA = 'NicToolServer::Group';

sub new_group {
    my ( $self, $data ) = @_;

    $self->error( 'nt_group_id',
        'Cannot add group to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{nt_group_id} );

    if ( $data->{name} =~ /([^a-zA-Z0-9 \-\_\'\.\@])/ ) {
        $self->error('name',
            "Group name contains an invalid character - \"$1\". Only A-Z, 0-9, ', _, ., -, and [spaces] are allowed."
        );
    }

    unless ( length( $data->{name} ) > 2 ) {
        $self->error('name', 'Group name must be at least 3 characters.');
    }

    unless ( lc( $data->{name} ) =~ /^[a-z0-9]/ ) {
        $self->error('name',
            'Group name must start with a letter or number. (A-Z, 0-9)'
        );
    }

    if ( $self->group_exists($data) ) {
        $self->error('name',
            'Group name is already taken at this level.'
        );
    }

    return $self->throw_sanity_error if $self->{errors};
    $self->SUPER::new_group($data);
}

sub edit_group {
    my ( $self, $data ) = @_;

    my $dataobj = $self->get_group($data);
    return $dataobj if $self->is_error_response($dataobj);

    $self->error( 'nt_group_id',
        'Cannot edit group in a deleted group!' )
        if $self->check_object_deleted( 'group',
        $dataobj->{parent_group_id} );

    $self->error( 'nt_group_id', 'Cannot edit a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{nt_group_id} );

    if ( exists $data->{name}
        && $data->{name} =~ /([^a-zA-Z0-9 \-\_\'\.\@])/ )
    {
        $self->error('name',
            "Group name contains an invalid character - \"$1\". Only A-Z, 0-9, ', _, ., -, and [spaces] are allowed."
        );
    }

    if ( exists $data->{name} && length( $data->{name} ) < 3 ) {
        $self->error('name', 'Group name must be at least 3 characters.');
    }

    if ( exists $data->{name} && lc( $data->{name} ) =~ /^[^a-z0-9]/ ) {
        $self->error('name',
            'Group name must start with a letter or number. (A-Z, 0-9)'
        );
    }

    if ( $self->group_exists_edit($data) ) {
        $self->error('name', 'Group name is already taken at this level.');
    }

    return $self->throw_sanity_error if $self->{errors};
    $self->SUPER::edit_group($data);
}

sub get_group_subgroups {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(group sub_groups parent_group_id) );
    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_group_subgroups($data);
}

sub get_global_application_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(timestamp user action object title description) );
    return $self->throw_sanity_error if $self->{errors};
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
        [ $data->{nt_group_id}, $data->{name} ] );
    return ref $groups->[0] ? 1 : 0;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Group::Sanity - sanity tests for NicTool groups

=head1 VERSION

version 2.33

=head1 SYNOPSIS

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
