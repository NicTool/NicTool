package NicToolServer::Zone::Sanity;

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

@NicToolServer::Zone::Sanity::ISA = qw(NicToolServer::Zone);

sub new_zone {
    my ( $self, $data ) = @_;

    my $user = $data->{'user'};

    $self->push_sanity_error( 'nt_group_id',
        'Cannot add zone to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{'nt_group_id'} );

    if ( $data->{'zone'} =~ /([^\/a-zA-Z0-9\-\.])/ ) {
        $self->{'errors'}->{'zone'} = 1;
        push(
            @{ $self->{'error_messages'} },
            "invalid character in zone -- $1"
        );
    }
    if ( $data->{'zone'} !~ /in-addr.arpa$/i && $data->{'zone'} =~ /\// ) {
        $self->{'errors'}->{'zone'} = 1;
        push(
            @{ $self->{'error_messages'} },
            "invalid character in zone '/'. Not allowed in non reverse-lookup zones"
        );
    }

    if ( $data->{'zone'} =~ /(.+?)\.$/ ) {    # always remove trailing dot
        $data->{'zone'} = $1;
    }

    if ( $data->{'zone'} =~ /in-addr.arpa$/ ) {

# TODO - any in-addr.arpa reverse DNS zone checks go here.
# might want to warn users if they try to make a PTR that points to an IP address rather
# than a name, but that would require "soft warnings."
# As of 10/12/01, I can't think of anything else we specifically need to for, WRT PTRs. --aai
    }

    if ( $data->{'zone'} !~ /.+\..+$/ ) {
        $self->{'errors'}->{'zone'} = 1;
        push(
            @{ $self->{'error_messages'} },
            "Zone must be a valid domain name -- something.something"
        );
    }

    # check if zone exists
    if ( $self->zone_exists( $data->{'zone'}, 0 ) ) {
        $self->{'errors'}->{'zone'} = 1;
        push( @{ $self->{'error_messages'} }, 'Zone is already taken' );
    }

    #check subdomains

    # sub-domain checks .. kinda nasty, but I think it has to be.
    my $z = $data->{'zone'};
    $z =~ tr/A-Z/a-z/;
    my @zparts = split( /\./, $z );
    if ( $z =~ /[a-z0-9\-\/]+\.[a-z0-9\-\/]+$/ )
    {    # zone must have a least one dot
        my $zstr = pop(@zparts);
        my @zonestocheck;
        while ( my $x = pop(@zparts) ) {
            $zstr = $x . "." . $zstr;
            push( @zonestocheck, $zstr );
        }
        foreach my $orig_zone (@zonestocheck) {
            if ( my $zref = $self->zone_exists( $orig_zone, 0 ) ) {

#use new permission-system to check for 'read' access to the zone...XXX 'read' access correct?
                my @error = $self->check_permission( 'nt_zone_id',
                    $zref->{'nt_zone_id'}, 'read', 'ZONE' );
                if ( defined $error[0] ) {
                    $self->{'errors'}->{'zone'} = 1;
                    push(
                        @{ $self->{'error_messages'} },
                        "Sub-domain creation not allowed: Access to zone $orig_zone denied: $error[1]"
                    );
                }
                if ($self->record_exists_within_zone(
                        $zref->{'nt_zone_id'}, $z
                    )
                    )
                {
                    $self->{'errors'}->{'zone'} = 1;
                    push(
                        @{ $self->{'error_messages'} },
                        "A record within $orig_zone named $z already exists. Delete or rename the record and then you can add $z as a sub-domain.\n"
                    );
                }

                # TODO - warn user that they're creating a sub-domain..
            }
        }
    }

    # check the zone's the TTL
    if ( !$data->{'ttl'} ) {
        $data->{'ttl'} = 86400;
    }
    if ( $data->{'ttl'} < 300 || $data->{'ttl'} > 2592000 ) {
        $self->{'errors'}->{'ttl'} = 1;
        push(
            @{ $self->{'error_messages'} },
            "Invalid TTL -- ttl must be >= 300 and <= 2,592,000"
        );
    }

    return $self->throw_sanity_error if ( $self->{'errors'} );
    $self->SUPER::new_zone($data);
}

sub edit_zone {
    my ( $self, $data ) = @_;

    my $user = $data->{'user'};

  #$self->push_sanity_error('nt_group_id','Cannot edit zone in deleted group')
  #if $self->check_object_deleted('group',$data->{'nt_group_id'});

    $self->push_sanity_error( 'nt_zone_id', 'Cannot edit deleted zone!' )
        if $self->check_object_deleted( 'zone', $data->{'nt_zone_id'} )
            and $data->{'deleted'} ne '0';

    my $dataobj = $self->get_zone($data);
    return $dataobj if $self->is_error_response($dataobj);

    $self->push_sanity_error( 'nt_zone_id',
        'Cannot edit zone in a deleted group!' )
        if $self->check_object_deleted( 'group', $dataobj->{'nt_group_id'} );

    # check the zone's the TTL
    if ( defined( $data->{'ttl'} )
        && ( $data->{'ttl'} < 300 || $data->{'ttl'} > 2592000 ) )
    {
        $self->{'errors'}->{'ttl'} = 1;
        push(
            @{ $self->{'error_messages'} },
            "Invalid TTL -- ttl must be >= 300 and <= 2,592,000"
        );
    }
    my $zone = $self->find_zone( $data->{'nt_zone_id'} );

    if (    $data->{'deleted'} eq '0'
        and $self->zone_exists( $zone->{'zone'}, $zone->{'nt_zone_id'} ) )
    {
        $self->{'errors'}->{'deleted'} = 1;
        push(
            @{ $self->{'error_messages'} },
            "Can't undelete the zone '$zone->{'zone'}' because another zone called '$zone->{'zone'}' now exists"
        );
    }

    return $self->throw_sanity_error if ( $self->{'errors'} );
    $self->SUPER::edit_zone($data);
}

sub move_zones {
    my ( $self, $data ) = @_;

    $self->push_sanity_error( 'nt_group_id',
        'Cannot move zones to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{'nt_group_id'} );

    if ( my @deld
        = grep { $self->check_object_deleted( 'zone', $_ ) }
        split( /,/, $data->{'zone_list'} ) )
    {
        $self->push_sanity_error( 'nt_zone_id',
            'Cannot move deleted zones: ' . join( ",", @deld ) );
    }

    return $self->throw_sanity_error if ( $self->{'errors'} );

    return $self->SUPER::move_zones($data);
}

sub get_zone_record_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(action user timestamp name description type address weight) );
    return $self->throw_sanity_error if ( $self->{'errors'} );
    return $self->SUPER::get_zone_record_log($data);
}

sub get_group_zones_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(action user timestamp zone description ttl group_name) );
    return $self->throw_sanity_error if ( $self->{'errors'} );
    return $self->SUPER::get_group_zones_log($data);
}

sub get_group_zones {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(zone group_name description queries_successful queries_norecord records)
    );
    return $self->throw_sanity_error if ( $self->{'errors'} );
    return $self->SUPER::get_group_zones($data);
}

sub get_zone_records {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(name description type address weight queries) );
    return $self->throw_sanity_error if ( $self->{'errors'} );
    return $self->SUPER::get_zone_records($data);
}

sub get_group_zone_query_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(timestamp nameserver zone query qtype flag ip port) );
    return $self->throw_sanity_error if ( $self->{'errors'} );
    return $self->SUPER::get_group_zone_query_log($data);
}

sub record_exists_within_zone {
    my ( $self, $zid, $name ) = @_;

    my $base_name = $name;
    $base_name =~ s/\..*$//;
    $name .= "." unless ( $name =~ /\.$/ );
    my $sql = "SELECT * FROM nt_zone_record WHERE deleted = '0'
        AND nt_zone_id = ? AND ( name = ? OR name = ? )";
    my $zrs = $self->exec_query( $sql, [ $zid, $name, $base_name ] ); 
    return ref $zrs->[0] ? 1 : 0;
}


1;
