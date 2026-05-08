package NicToolServer::Nameserver::Sanity;

# ABSTRACT: sanity tests for nameservers

use strict;
use parent 'NicToolServer::Nameserver';

sub new_nameserver {
    my ( $self, $data ) = @_;

    if ( $self->check_object_deleted( 'group', $data->{nt_group_id} ) ) {
        $self->error( 'nt_group_id', 'Cannot add nameserver to a deleted group!' );
    }

    defined $data->{ttl} or $data->{ttl} = 86400;    # if unset, default

    $self->valid_ttl( $data->{ttl} );

    $self->_valid_chars( $data->{name} );
    $self->_valid_fqdn( $data->{name} );
    $self->_valid_nsname( $data->{name} );
    $self->_valid_export_type($data);

    if ( !$data->{address} ) {
        $self->error( 'address', "Invalid IP address" );
    }
    $self->_valid_ip_addresses($data);
    $self->_valid_export_paths($data);

    return $self->throw_sanity_error if $self->{errors};
    $self->SUPER::new_nameserver($data);
}

sub edit_nameserver {
    my ( $self, $data ) = @_;

    $self->error( 'nt_nameserver_id', 'Cannot edit deleted nameserver!' )
        if $self->check_object_deleted( 'nameserver', $data->{nt_nameserver_id} );

    my $dataobj = $self->get_nameserver($data);
    return $dataobj if $self->is_error_response($dataobj);

    $self->error( 'nt_nameserver_id', 'Cannot edit nameserver in a deleted group!' )
        if $self->check_object_deleted( 'group', $dataobj->{nt_group_id} );

    $self->valid_ttl( $data->{ttl} ) if defined $data->{ttl};

    if ( exists $data->{name} ) {
        $self->_valid_chars( $data->{name} );
        $self->_valid_fqdn( $data->{name} );
        $self->_valid_nsname( $data->{name} );
    }

    if ( $data->{export_format} || $data->{export_type_id} ) {
        $self->_valid_export_type($data);
    }

    $self->_valid_ip_addresses($data);
    $self->_valid_export_paths($data);

    return $self->throw_sanity_error if $self->{errors};
    $self->SUPER::edit_nameserver($data);
}

sub move_nameservers {
    my ( $self, $data ) = @_;

    # TODO TODO TODO - sanity
    #warn Dumper($data);

    $self->SUPER::move_nameservers($data);
}

sub get_group_nameservers {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(name description address address6 remote_login export_type_id status group_name) );

    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_group_nameservers($data);
}

sub _valid_export_paths {
    my ( $self, $data ) = @_;

    # datadir and logdir are interpolated into shell commands and Makefiles by
    # the Export modules. Forbid shell metacharacters and require an absolute,
    # well-formed path. Also reject `..` path components and `//` runs to
    # prevent traversal outside the intended export tree (rsync follows the
    # path verbatim, so `/srv/exports/../etc` would escape the export root).
    for my $field (qw(datadir logdir)) {
        next unless defined $data->{$field} && length $data->{$field};
        my $val = $data->{$field};
        if ( $val !~ m{^/[A-Za-z0-9_./-]*$} ) {
            $self->error( $field,
                "Invalid $field: must be an absolute path containing only "
                . "letters, digits, _ . / -" );
            next;
        }
        # Reject `..` as a whole path component; bare dots in filenames are fine.
        if ( grep { $_ eq '..' } split m{/}, $val ) {
            $self->error( $field,
                "Invalid $field: path traversal components ('..') are not allowed" );
        }
        if ( $val =~ m{//} ) {
            $self->error( $field,
                "Invalid $field: empty path components ('//') are not allowed" );
        }
    }

    # remote_login is interpolated into ssh/rsync targets ("user\@host"). Allow
    # only POSIX-portable username characters.
    if ( defined $data->{remote_login} && length $data->{remote_login} ) {
        if ( $data->{remote_login} !~ /^[A-Za-z_][A-Za-z0-9_-]{0,31}$/ ) {
            $self->error( 'remote_login',
                "Invalid remote_login: must match POSIX username "
                . "(letters, digits, underscore, dash; 1-32 chars)" );
        }
    }
}

sub _valid_ip_addresses {
    my ( $self, $data ) = @_;

    if ( $data->{address} ) {
        if ( !$self->valid_ip_address( $data->{address} ) ) {
            $self->error( 'address', "Invalid IP address - $data->{address}" );
        }
        if ( $data->{address} =~ /\.(0|255)$/ ) {
            $self->error( 'address', "Invalid IP address - $data->{address}" );
        }
    }

    if ( $data->{address6} && !$self->valid_ip_address( $data->{address6} ) ) {
        $self->error( 'address6', "Invalid IPv6 address - $data->{address6}" );
    }
}

sub _valid_chars {
    my ( $self, $name ) = @_;

    # check characters
    if ( $name =~ /([^a-zA-Z0-9\-\.])/ ) {
        $self->error( 'name',
            "Nameserver name contains an invalid character - \"$1\". Only A-Z, 0-9, . and - are allowed."
        );
        return 0;
    }

    return 1;
}

sub _valid_export_type {
    my ( $self, $data ) = @_;

    if ( !$self->{export_types} ) {
        $self->{export_types} = $self->get_nameserver_export_types( { type => 'ALL' } )->{types};
    }

    # request might arrive with export_format, or export_type_id
    my $type_id = $data->{export_type_id};
    if ( $data->{export_type_id} ) {
        my @r = grep { $_->{id} == $type_id } @{ $self->{export_types} };
        return $r[0] if $r[0];
    }

    if ( $data->{export_format} ) {
        my $type = $data->{export_format};
        my @r    = grep { $_->{name} eq $type } @{ $self->{export_types} };
        if ( $r[0] ) {
            $data->{export_type_id} = $r[0]->{id};
            return $r[0];
        }
    }

    $self->error( 'export_format', 'Invalid export format.' );
    return 0;
}

sub _valid_fqdn {
    my ( $self, $name ) = @_;

    return 1 if $name =~ /\.$/;

    # name is not absolute.
    $self->error( 'name',
        "Nameserver name must be a fully-qualified domain name with a dot at the end, such as ns1.example.com. (notice the dot after .com...)"
    );
    return 0;
}

sub _valid_nsname {
    my ( $self, $name ) = @_;

    my $has_err;

    # check that labels of the name are valid
    my @parts = split( /\./, $name );
    foreach my $address (@parts) {
        if ( $address !~ /[a-zA-Z0-9\-]+/ ) {
            $self->error( 'name', "Nameserver name must be a valid host." );
            $has_err++;
        }
        if ( $address =~ /^[\-]/ ) {    # can't start with a dash or a dot.
            $self->error( 'name', "Parts of a nameserver name cannot start with a dash." );
            $has_err++;
        }
    }
    return $has_err ? 0 : 1;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Nameserver::Sanity - sanity tests for nameservers

=head1 VERSION

version 2.40

=head1 SYNOPSIS

Validate that nameservers have required params, no invalid chars, etc.

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abraham Ingersoll

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abraham Ingersoll, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
