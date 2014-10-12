package DNS;

use strict;
use warnings;

our $VERSION = '0.76';

use Data::Dumper;
use English qw( -no_match_vars );
use Net::DNS;
use Params::Validate qw(:all);

use lib 'lib';

sub new {
    my $class = shift;

    my %p = validate(
        @_,
        {   'proj' => { type => OBJECT },
            'log'  => { type => OBJECT, optional => 1 },
        }
    );

    my $self = {
        'proj'      => $p{proj},
        logger      => $p{'log'} || $p{proj},
        nt          => undef,
        ns_ips      => undef,
        resolver    => undef,
    };
    bless( $self, $class );

    return $self;
}

sub nt_connect {
    my $self = shift;

    return $self->{nt} if $self->{nt};    # session already cached

    eval { require NicTool; };

    if ($EVAL_ERROR) {
        die "Could not load NicTool.pm. Are the NicTool client libraries
            installed? They can be found in NicToolServer/sys/client in
            the NicToolServer distribution.";
    }

    if ( !$self->{proj}{config}{NicTool} ) {
        die "[NicTool] config section missing from proj.conf\n";
    }

    my $cfg = $self->{proj}{config}{NicTool};
    my $nt = NicTool->new(
        server_host => $cfg->{host},
        server_port => $cfg->{port} || 8082,
        protocol    => $cfg->{protocol},
    );

    my $r = $nt->login( username => $cfg->{user}, password => $cfg->{pass} );

    if ( $nt->is_error($r) ) {
        die "error logging in to nictool: $r->{store}{error_msg}\n";
    }

    #warn Data::Dumper::Dumper( $nt ); # ->{user}{store} );
    #warn "\tlogin successful (session " . $nt->{nt_user_session} . ")";
    return $self->{nt} = $nt;
}

sub nt_create_record {
    my $self = shift;

    my %p = validate(
        @_,
        {   'zone_id'     => { type => SCALAR },
            'name'        => { type => SCALAR },
            'address'     => { type => SCALAR },
            'type'        => { type => SCALAR },
            'ttl'         => { type => SCALAR, optional => 1, },
            'weight'      => { type => SCALAR, optional => 1, },
            'other'       => { type => SCALAR, optional => 1, },
            'priority'    => { type => SCALAR, optional => 1, },
            'description' => { type => SCALAR, optional => 1, },
        }
    );

    my $nt = $self->nt_connect();

    my %request = (
        nt_zone_id => $p{zone_id},
        name       => $p{name},
        address    => $p{address},
        type       => $p{type},
    );

    $request{ttl}         = $p{ttl}         if $p{ttl};
    $request{weight}      = $p{weight}      if defined $p{weight};
    $request{priority}    = $p{priority}    if defined $p{priority};
    $request{other}       = $p{other}       if defined $p{other};
    $request{description} = $p{description} if $p{description};

    # create it
    my $r = $nt->new_zone_record(%request);

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    my $record_id = $r->{store}{nt_zone_record_id} || 1;
    return $record_id;
}

sub nt_create_zone {
    my $self = shift;

    my %p = validate(
        @_,
        {   'zone'     => { type => SCALAR },
            'group_id' => { type => SCALAR, optional => 1, default => 1 },
            'description' => { type => SCALAR },
            'contact' => { type => SCALAR, optional => 1 },
            'ttl'     => { type => SCALAR, optional => 1, default => 86400 },
            'refresh' => { type => SCALAR, optional => 1, default => 16384 },
            'retry'   => { type => SCALAR, optional => 1, default => 2048 },
            'expire' => { type => SCALAR, optional => 1, default => 1048576 },
            'minimum' => { type => SCALAR, optional => 1, default => 2560 },
            'nameservers' =>
                { type => SCALAR, optional => 1, default => [ 3, 4 ] },
            'template' => { type => SCALAR, optional => 1, },
            'ip'       => { type => SCALAR, optional => 1, },
            'mailip'   => { type => SCALAR, optional => 1, },
            'logger'   => { type => OBJECT, optional => 1 },
        }
    );

    my $nt = $self->nt_connect();
    my $logger = $p{logger} || $self->{logger};

    my $nameservers = $p{nameservers};
    my $config      = $self->{proj}{config};
    if ( !$nameservers && $config ) {
        $nameservers
            = scalar $config->{NicTool}{nameserver}
            ? [ $config->{NicTool}{nameserver} ]
            : $config->{NicTool}{nameserver};
    }
    $nameservers = join( ',', @{$nameservers} );

    my $r = $nt->new_zone(
        nt_zone_id  => undef,
        nt_group_id => $p{group_id},
        zone        => $p{zone},
        ttl         => $p{ttl},
        serial      => undef,
        description => $p{description},
        nameservers => $nameservers,
        mailaddr    => $p{contact} || 'hostmaster.' . $p{zone},
        refresh     => $p{refresh},
        retry       => $p{retry},
        expire      => $p{expire},
        minimum     => $p{minimum},
    );

    if ( $r->{store}{error_code} != 200 ) {
        my $err = "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
        $logger->log( $err, severity => 3 );
        return;
    }

    my $zone_id = $r->{store}{nt_zone_id};
    $logger->log("created zone $p{zone} ( $zone_id ) ");
    return $zone_id;
}

sub nt_delete_record {

    my $self = shift;

    my %p = validate( @_, { 'record_id' => { type => SCALAR } } );

    my $nt        = $self->nt_connect();
    my $record_id = $p{record_id};
    my $r
        = $self->{nt}->delete_zone_record( nt_zone_record_id => $record_id );

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    return "deleted record id: $record_id";
}

sub nt_delete_zone {
    my $self = shift;

    my %p = validate( @_, { 'zone_id' => { type => SCALAR } } );

    my $nt      = $self->nt_connect();
    my $zone_id = $p{zone_id};

    # NT API description for delete_zones method
    # zone_list: string. A list of zone id's separated by commas.

    my $r = $self->{nt}->delete_zones( zone_list => $zone_id );

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    return "deleted zone id: $zone_id";
}

sub nt_error {
    my $self = shift;
    my $err  = shift;

    my ($nictool_err) = $err =~ /\((.*)\) at/;
    $nictool_err ||= $err;
    if ($nictool_err) {
        $self->{logger}->log( $nictool_err, severity => 2 );
        return;
    }
    return 1;
}

sub nt_get_reverse {
    my ( $self, $ip ) = @_;

    #    warn "IP $ip\n";

    my @octets = split( '\.', $ip );
    my $zone = "$octets[2].$octets[1].$octets[0].in-addr.arpa";

    #    warn "reverse zone: $zone\n";

    my $id = $self->nt_get_zones( zone => $zone );
    return if !$id;

    #    warn "found $zone with id: $id\n";

    my $recs = $self->nt_get_zone_records(
        zone_id => $id,
        name    => $octets[3],
        type    => 'PTR',
        debug   => 0,
    );
    return if !$recs;

    return $recs;
}

sub nt_get_reverses {

    my $self = shift;
    my $ips  = shift;

    my @r;
    foreach my $ip (@$ips) {

        if ( !$self->{proj}->is_valid_ip($ip) ) {
            warn "invalid ip ($ip)";
            next;
        }

        my $r = $self->nt_get_reverse($ip);

        $r->{ip} = $ip;
        push @r, $r;
    }
    return \@r;
}

sub nt_get_zones {
    my $self = shift;
    my %p = validate(
        @_,
        {   'zone'  => { type => SCALAR },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
        }
    );

    my $nt = $self->nt_connect();
    my $r = $nt->get_group_zones(
        nt_group_id       => $nt->{user}{store}{nt_group_id},
        include_subgroups => 1,
        Search            => 1,
        '1_field'         => 'zone',
        '1_option'        => 'equals',
        '1_value'         => $p{zone},
    );

    #warn Data::Dumper::Dumper($r);

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    if ( !$r->{store}{zones}[0]{store}{nt_zone_id} ) {
        warn "\tzone $p{zone} not found!";
        return;
    }

    my $zone_id = $r->{store}{zones}[0]{store}{nt_zone_id};
    return $zone_id;
}

sub nt_get_zones_by_client_id {

    my $self = shift;

    my %p = validate(
        @_,
        {   'client_id' => { type => SCALAR },
            'zone'      => { type => SCALAR, optional => 1 },
            'sort'      => { type => SCALAR, optional => 1 },
            'fatal'     => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'     => { type => BOOLEAN, optional => 1, default => 1 },
        }
    );

    my $nt = $self->nt_connect();

    my %request = (
        nt_group_id       => $nt->{user}{store}{nt_group_id},
        include_subgroups => 1,
        limit             => 255,
        Search            => 1,
        '1_field'         => 'description',
        '1_option'        => 'equals',
        '1_value'         => $p{client_id},
    );

    if ( $p{zone} ) {
        $request{'2_field'}     = 'zone';
        $request{'2_option'}    = 'equals';
        $request{'2_value'}     = $p{zone};
        $request{'2_inclusive'} = 'And';
    }

    if ( $p{'sort'} ) {
        $request{'Sort'}        = 1;
        $request{'1_sortfield'} = 'zone';
        $request{'1_sortmod'}   = 'Ascending';
    }

    my $r = $nt->get_group_zones(%request);

    #warn Data::Dumper::Dumper($r);

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    my @zones;

    # map zone names to their ids
    foreach my $zone ( @{ $r->{store}{zones} } ) {
        push @zones,
            {
            name => $zone->{store}{zone},
            id   => $zone->{store}{nt_zone_id},
            };
    }

    return \@zones;
}

sub nt_get_zone_info {
    my $self = shift;
    my %p    = validate(
        @_,
        {   'zone_id' => { type => SCALAR },
            'name'    => { type => SCALAR, optional => 1 },
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => 1 },
        }
    );

    #warn "getting info for zone id $p{zone_id}\n";

    my $nt = $self->nt_connect();
    my $r = $nt->get_zone( nt_zone_id => $p{zone_id} );
    return $r->{store};
}

sub nt_get_zone_records {
    my $self = shift;

    my %p = validate(
        @_,
        {   'zone_id' => { type => SCALAR },
            'name'    => { type => SCALAR, optional => 1 },
            'type'    => { type => SCALAR, optional => 1 },
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => 1 },
        }
    );

    #warn "\tgetting zone records for zone id $p{zone_id}\n" if $p{debug};

    my $nt = $self->nt_connect();

    my %request = (
        'nt_zone_id' => $p{zone_id},
        'Search'     => 1,
        limit        => 255,
    );

    if ( $p{name} ) {
        $request{'1_field'}  = 'name';
        $request{'1_option'} = 'equals';
        $request{'1_value'}  = $p{name};
    }

    if ( $p{type} ) {
        $request{'2_inclusive'} = 'And';
        $request{'2_field'}     = 'type';
        $request{'2_option'}    = 'equals';
        $request{'2_value'}     = $p{type};
    }

    my $r = $nt->get_zone_records(%request);
    return if !$r->{store}{records};

    #warn Dumper ( $r->{store}{records}[0]{store} ) if $p{debug};

    if ( $p{debug} ) {

        for ( my $i = 0; $i < scalar( @{ $r->{store}{records} } ); $i++ ) {
            print "$i\n";
            next if !defined $r->{store}{records}[$i]{store};
            printf "%35s  %5s  %35s\n", $r->{store}{records}[$i]{store}{name},
                $r->{store}{records}[$i]{store}{type},
                $r->{store}{records}[$i]{store}{address};
        }

        #warn "get_zone_records: returning $r->{store}{records}\n";
    }

    if ( $p{name} ) {
        if ( $r->{store}{records}[1]{store} ) {
            warn "yikes, more than one record matched?!\n";
        }
        return $r->{store}{records}[0]{store};
    }

    my @records;
    foreach ( @{ $r->{store}{records} } ) {
        push @records, $_->{store};
    }
    return \@records;
}

sub nt_set_zone_record {
    my $self = shift;

    my %p = validate(
        @_,
        {   'zone_id'     => { type => SCALAR },
            'name'        => { type => SCALAR },
            'address'     => { type => SCALAR },
            'ttl'         => { type => SCALAR },
            'type'        => { type => SCALAR },
            'description' => { type => SCALAR, optional => 1 },
            'fatal'       => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'       => { type => BOOLEAN, optional => 1, default => 1 },
        }
    );

    # see if the zone record exists
    my $r = $self->nt_get_zone_records(
        zone_id => $p{zone_id},
        name    => $p{name},
        type    => $p{type},
        debug   => 0,
    );

    my $rec_id
        = defined $r->{nt_zone_record_id} ? $r->{nt_zone_record_id} : undef;

    #warn "rec_id: " . Dumper ($rec_id);

    my %request = (
        nt_zone_record_id => $rec_id,
        nt_zone_id        => $p{zone_id},
        ttl               => $p{ttl},
        type              => $p{type},
        name              => $p{name},
        address           => $p{address},
        description       => $p{description} || '',
    );

    if ($rec_id) {
        $r = $self->{nt}->edit_zone_record(%request);    # if exists, update
    }
    else {
        $r = $self->{nt}->new_zone_record(%request);     # otherwise, create
    }

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    return 1;
}

sub nt_update_record {

    my $self = shift;

    my %p = validate(
        @_,
        {   'zone_id'     => { type => SCALAR },
            'record_id'   => { type => SCALAR },
            'name'        => { type => SCALAR },
            'address'     => { type => SCALAR },
            'type'        => { type => SCALAR },
            'ttl'         => { type => SCALAR, optional => 1 },
            'weight'      => { type => SCALAR, optional => 1 },
            'priority'    => { type => SCALAR, optional => 1 },
            'other'       => { type => SCALAR, optional => 1 },
            'description' => { type => SCALAR, optional => 1 },
        }
    );

    my $nt = $self->nt_connect();

    my %request = (
        nt_zone_record_id => $p{record_id},
        nt_zone_id        => $p{zone_id},
        'name'            => $p{name},
        'address'         => $p{address},
        'type'            => $p{type},
    );

    $request{ttl}         = $p{ttl}         if $p{ttl};
    $request{weight}      = $p{weight}      if defined $p{weight};
    $request{priority}    = $p{priority}    if defined $p{priority};
    $request{other}       = $p{other}       if defined $p{other};
    $request{description} = $p{description} if $p{description};

    my $r = $self->{nt}->edit_zone_record(%request);

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    return 1;
}

sub get_a_records {
    my $self = shift;

    my %p = validate( @_, { 'host' => { type => SCALAR } } );

    my @ips;

    # resolve host to its IP
    my $resolver = $self->get_resolver();
    my $dns_q = $resolver->query( $p{host}, 'A' );

    if ( !$dns_q ) {
        $self->{logger}
            ->log( "DNS query for $p{host} A records failed", severity => 2 );
        return;
    }

    foreach my $rr ( $dns_q->answer ) {
        next if $rr->type ne 'A';
        my $ip = $rr->address;
        next if !$ip;
        push @ips, $ip;
    }
    return \@ips;
}

sub get_ns_records {
    my $self = shift;

    my %p = validate( @_, { 'zone' => { type => SCALAR } } );

    my $resolver = $self->get_resolver();

    my $dns_q;
    if ( $p{zone} =~ /\./ ) {
        $dns_q = $resolver->query( $p{zone}, 'NS' );
    }
    else {

    # this method must be used for TLD queries. TLD queries fail with NXDOMAIN
    # using the standard method above .
        $dns_q = $resolver->send( $p{zone}, 'NS' );
    }

    if ( !$dns_q ) {

   #        $self->{logger}
   #            ->log( "NS record query for $p{zone} failed", severity => 2 );
        warn "NS record query for '$p{zone}' failed: "
            . $resolver->errorstring;
        return;
    }

    my @records;
    foreach my $rr ( $dns_q->answer ) {
        next if $rr->type ne 'NS';
        my $ns = $rr->nsdname;
        next if !$ns;
        push @records, $ns;
    }
    return \@records;
}

sub get_resolver {
    my $self = shift;
    return $self->{resolver} if $self->{resolver};

    my $resolver = Net::DNS::Resolver->new();
    if ( !$resolver ) {
        $self->{logger}
            ->log( "Unable to get a DNS resolver object.", severity => 2 );
        warn "unable to get DNS resolver\n";
        return;
    }
    $self->{resolver} = $resolver;
    return $resolver;
}

sub get_proj_ns_ips {
    my $self = shift;

    return $self->{ns_ips} if $self->{ns_ips};

    my $ns_recs = $self->get_ns_records( zone => 'dnscloud.com' );

    my %ips;

    # resolve each NS to its IP
    foreach (@$ns_recs) {
        my $ips = $self->get_a_records( host => $_ );
        foreach (@$ips) { $ips{$_} = 1 }
    }

    $self->{ns_ips} = \%ips;
    return \%ips;
}

sub has_my_ns_records {
    my $self = shift;
    my %p = validate( @_, { 'zone' => { type => SCALAR } } );

    my $domain   = $p{zone};
    my $logger   = $self->{logger};
    my $resolver = $self->get_resolver();

    my $proj_ns_ips = $self->get_proj_ns_ips();

    my $their_ns_records = $self->get_ns_records( zone => $domain );
    if ( !$their_ns_records || scalar @$their_ns_records < 1 ) {
        $logger->log( "The DNS zone $domain has no NS records.",
            severity => 2 );
        return;
    }

    my $matches = 0;
    foreach my $host (@$their_ns_records) {
        my $ips = $self->get_a_records( host => $host );
        foreach my $ip (@$ips) {
            $matches++ if $proj_ns_ips->{$ip};
        }
    }

    if ( !$matches ) {
        $logger->log(
            "The DNS zone $domain has NS records that point to other DNS servers.",
            severity => 3
        );
        return;
    }
    return 1;
}

sub reset_rdns {
    my $self = shift;
    my %p = validate( @_, { ip => { type => SCALAR } } );

    my $ip = $self->{proj}->is_valid_ip( $p{ip} ) or die "invalid IP '$p{ip}'\n";
    my @octets = split /\./, $ip;

    $self->{logger}->log( "setting DNS to defaults for $ip", severity => 1 );

    # update PTR record for 4.3.2.1.in-addr.arpa
    my $r_zone = "$octets[2].$octets[1].$octets[0].in-addr.arpa";
    my $zone_id = $self->nt_get_zones( zone => $r_zone );
    if ( !$zone_id ) {
        $self->nt_create_zone(
            zone        => $r_zone,
            group_id    => 3,
            description => 'added by Spry::DNS:reset_rdns',
        );
        $zone_id = $self->nt_get_zones( zone => $r_zone );
        if ( !$zone_id ) {
            $self->{logger}
                ->log( "unable to create zone $r_zone", severity => 3 );
            return;
        }
        $self->{logger}->log( "zone $r_zone created", severity => 1 );
    }

    eval {
        $self->nt_set_zone_record(
            zone_id => $zone_id,
            name    => $octets[3],
            address => "$octets[3].$r_zone.",
            ttl     => 3600,
            type    => 'PTR',
        );
    };
    if ($EVAL_ERROR) {
        $self->nt_error($EVAL_ERROR);    # reports any error
        return;
    }

    # update A record for 4.3.2.1.in-addr.arpa
    eval {
        $self->nt_set_zone_record(
            zone_id => $zone_id,
            name    => $octets[3],
            address => $ip,
            ttl     => 3600,
            type    => 'A',
        );
    };
    if ($EVAL_ERROR) {
        $self->nt_error($EVAL_ERROR);    # reports any error
        return;
    }
    return 1;
}

sub resolve_ip_to_hostname {

    my $self = shift;

    my %p = validate( @_, { 'ip' => { type => SCALAR, }, } );

    my $ip = $p{ip};

    #print "node: $ip";
    my $resolver = Net::DNS::Resolver->new();
    my $dns_q = $resolver->query( $ip, 'PTR' );
    foreach my $rr ( $dns_q->answer ) {
        my $fqdn = $rr->ptrdname;
        if ($fqdn) {

            #print " resolves to hostname: $fqdn";
            my ($node_c) = split( /\./, $fqdn );

            #print " ($node_c)\n";
            return $node_c;
        }
    }
    die "unable to resolve $ip to a hostname\n";
}


1;
