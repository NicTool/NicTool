package NicToolServer::Import::tinydns;
# ABSTRACT: import tinydns data into NicTool

use strict;
use warnings;

use lib 'lib';
#use base 'NicToolServer::Import::Base';

use Cwd;
use Data::Dumper;
use English;
use File::Copy;
use Params::Validate qw/ :all /;
use Time::TAI64 qw/ unixtai64 /;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
};

sub get_import_file {
    my $self = shift;
    my $filename = shift || 'data';

    return $self->{FH} if defined $self->{FH};

    open my $FH, '<', $filename
        or die "failed to open '$filename'";

    $self->{FH} = $FH;
    return $FH;
};

sub import_records {
    my $self = shift;
    $self->get_import_file( 'data' ) or return;

# tinydns-data format: http://cr.yp.to/djbdns/tinydns-data.html

    my $fh = $self->{FH};
    while ( defined ( my $record = <$fh> ) ) {
        next if $record =~ /^#/;     # comment
        next if $record =~ /^\s+$/;  # blank line
        next if $record =~ /^\-/;       #  IGNORE     =>  - fqdn : ip : ttl:timestamp:lo
        sleep 1;

        my $first = substr($record, 0, 1 );
        my $record = substr($record, 1 );
        chomp $record;

        if ( $first eq 'Z' ) {          #  SOA        =>  Z fqdn:mname:rname:ser:ref:ret:exp:min:ttl:time:lo
            $self->zr_soa($record);
        }
        elsif ( $first eq '.' ) {       #  'SOA,NS,A' =>  . fqdn : ip : x:ttl:timestamp:lo
            $self->zr_soa($record);
            $self->zr_ns($record);
            $self->zr_a($record);
        }
        elsif ( $first eq '=' ) {       #  'A,PTR'    =>  = fqdn : ip : ttl:timestamp:lo
            $self->zr_a($record);
            $self->zr_ptr($record);
        }
        elsif ( $first eq '&' ) {       #  NS         =>  & fqdn : ip : x:ttl:timestamp:lo
            $self->zr_ns($record);
        }
        elsif ( $first eq '^' ) {       #  PTR        =>  ^ fqdn :  p : ttl:timestamp:lo
            $self->zr_ptr($record);
        }
        elsif ( $first eq '+' ) {       #  A          =>  + fqdn : ip : ttl:timestamp:lo
            $self->zr_a($record);
        }
        elsif ( $first eq 'C' ) {       #  CNAME      =>  C fqdn :  p : ttl:timestamp:lo
            $self->zr_cname($record);
        }
        elsif ( $first eq '@' ) {       #  MX         =>  @ fqdn : ip : x:dist:ttl:timestamp:lo
            $self->zr_mx($record);
        }
        elsif ( $first eq '\'' ) {      #  TXT        =>  ' fqdn :  s : ttl:timestamp:lo
            $self->zr_txt($record);
        }
        elsif ( $first eq ':' ) {       #  GENERIC    =>  : fqdn : n  : rdata:ttl:timestamp:lo
            $self->zr_generic($record);
        };
    };

    print "done\n";
};

sub get_zone {
    my ($self, $fqdn) = @_;
    my @bits = split /\./, $fqdn;
    my $host = shift @bits;
    my $zone = join '.', @bits;
    print "h: $host, z: $zone ($fqdn)\n";
    return ($host, $zone);
};

sub zr_a {
    my $self = shift;
    my $r = shift or die;

    print "A  : $r\n";
    my ( $fqdn, $ip, $ttl, $timestamp, $location ) = split(':', $r);

    my ($host, $zone) = $self->get_zone($fqdn);
    if ( ! $zone ) {
        die "unable to work out zone from $fqdn\n";
    };
    my $zone_id = $self->nt_get_zone_id( zone => $zone );
    if ( ! $zone_id ) {
        $zone_id = $self->nt_get_zone_id( zone => $fqdn );
        $host = $fqdn;
        if ( ! $zone_id ) {
            warn "skipping, could not find zone: $zone\n";
            return;
        };
    };
    my $recs = $self->nt_get_zone_records(
        zone_id => $zone_id,
        name    => $host,
        type    => 'A',
        address => $ip,
    );
    if ( scalar $recs ) {
        print "record exists\n"; # . Dumper($recs);
        return;
    };

    print "adding record \n";
    my $rid = $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'A',
        name    => $host,
        address => $ip,
        ttl     => $ttl,
    );
}

sub zr_cname {
    my $self = shift;
    my $r = shift or die;

    print "CNA: $r\n";
    my ( $fqdn, $addr, $ttl, $timestamp, $location ) = split(':', $r);

    my ($host, $zone) = $self->get_zone($fqdn);
    if ( ! $zone ) {
        die "unable to work out zone from $fqdn\n";
    };
    my $zone_id = $self->nt_get_zone_id( zone => $zone );
    if ( ! $zone_id ) {
        $zone_id = $self->nt_get_zone_id( zone => $fqdn );
        $host = $fqdn;
        if ( ! $zone_id ) {
            warn "skipping, could not find zone: $zone\n";
            return;
        };
    };
    my $recs = $self->nt_get_zone_records(
        zone_id => $zone_id,
        name    => $host,
        type    => 'CNAME',
    );
    if ( scalar $recs ) {
        print "record exists\n"; # . Dumper($recs);
        return;
    };

    print "adding record \n";
    my $rid = $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'CNAME',
        name    => $host,
        address => $self->fully_qualify( $addr ),
        ttl     => $ttl,
    );
}

sub zr_mx {
    my $self = shift;
    my $r = shift or die;

    print "MX : $r\n";
    my ( $fqdn, $ip, $addr, $distance, $ttl, $timestamp, $location ) = split(':', $r);

    my ($host, $zone) = $self->get_zone($fqdn);
    if ( ! $zone ) {
        die "unable to work out zone from $fqdn\n";
    };
    my $zone_id = $self->nt_get_zone_id( zone => $zone );
    if ( ! $zone_id ) {
        $zone_id = $self->nt_get_zone_id( zone => $fqdn );
        $host = $fqdn;
        if ( ! $zone_id ) {
            warn "skipping, could not find zone: $zone\n";
            return;
        };
    };
    my $recs = $self->nt_get_zone_records(
        zone_id => $zone_id,
        type    => 'MX',
        name    => $host,
        address => $addr,
    );
    if ( scalar $recs ) {
        print "record exists\n"; # . Dumper($recs);
        return;
    };

    print "adding record \n";
    my $rid = $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'MX',
        name    => $host,
        address => $self->fully_qualify( $addr ),
        ttl     => $ttl,
        weight  => $distance,
    );
}

sub zr_txt {
    my $self = shift;
    my $r = shift or die;

    print "TXT: $r\n";
    my ( $fqdn, $addr, $ttl, $timestamp, $location ) = split(':', $r);

    my ($host, $zone) = $self->get_zone($fqdn);
    if ( ! $zone ) {
        die "unable to work out zone from $fqdn\n";
    };
    my $zone_id = $self->nt_get_zone_id( zone => $zone );
    if ( ! $zone_id ) {
        $zone_id = $self->nt_get_zone_id( zone => $fqdn );
        $host = $fqdn;
        if ( ! $zone_id ) {
            warn "skipping, could not find zone: $zone\n";
            return;
        };
    };
    my $recs = $self->nt_get_zone_records(
        zone_id => $zone_id,
        name    => $host,
        type    => 'TXT',
    );
    if ( scalar $recs ) {
        print "record exists\n"; # . Dumper($recs);
        return;
    };

    print "adding record \n";
    my $rid = $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'TXT',
        name    => $host,
        address => $addr,
        ttl     => $ttl,
    );
}

sub zr_ns {
    my $self = shift;
    my $r = shift or die;

    print "NS : $r\n";
    my ( $fqdn, $ip, $host, $ttl, $timestamp, $location ) = split(':', $r);
}

sub zr_ptr {
    my $self = shift;
    my $r = shift or die;

    print "PTR: $r\n";
    my ( $fqdn, $addr, $ttl, $timestamp, $location ) = split(':', $r);
    my ($host, $zone) = $self->get_zone($fqdn);
    if ( ! $zone ) {
        die "unable to work out zone from $fqdn\n";
    };
    my $zone_id = $self->nt_get_zone_id( zone => $zone );
    if ( ! $zone_id ) {
        warn "skipping, could not find zone: $zone\n";
        return;
    };
    my $recs = $self->nt_get_zone_records(
        zone_id => $zone_id,
        name    => $host,
        type    => 'PTR',
        address => $addr,
    );
    if ( scalar $recs ) {
        print "record exists\n"; # . Dumper($recs);
        return;
    };

    print "adding record \n";
    my $rid = $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'PTR',
        name    => $host,
        address => $self->fully_qualify( $addr ),
        ttl     => $ttl,
    );
}

sub zr_soa {
    my $self = shift;
    my $r = shift or die;

    print "SOA: $r\n";
    my ( $zone, $mname, $rname, $serial, $refresh, $retry, $expire, $min, $ttl, $timestamp, $location ) = split(':', $r);

    my $zid = $self->nt_get_zone_id( zone => $zone );
    if ( $zid ) {
        print "zid: $zid\n";
        return $zid;
    }
    else {
        print "creating zone $zone\n";
        $self->nt_create_zone(
            zone        => $zone,
            group_id    => 238,   # TODO: make this a CLI option
            nameservers => [ 3,4,5 ],
            description => '',
            contact     => $rname,
            ttl         => $ttl,
            refresh     => $refresh,
            retry       => $retry,
            expire      => $expire,
            minimum     => $min,
        );
    };
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
                { type => ARRAYREF, optional => 1, default => [ 3, 4 ] },
            'template' => { type => SCALAR, optional => 1, },
            'ip'       => { type => SCALAR, optional => 1, },
            'mailip'   => { type => SCALAR, optional => 1, },
            'logger'   => { type => OBJECT, optional => 1 },
        }
    );

    my $nt = $self->nt_connect();

    my $nameservers = $p{nameservers};
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
        warn "$r->{store}{error_desc} ( $r->{store}{error_msg} ), " . Dumper(\%p);
        return;
    }

    my $zone_id = $r->{store}{nt_zone_id};
    warn "created zone $p{zone} ( $zone_id ) ";
    return $zone_id;
};

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
    my $nt = $self->nt_connect();
    my $r = $nt->new_zone_record(%request);

    if ( $r->{store}{error_code} != 200 ) {
        warn "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
        return;
    }

    my $record_id = $r->{store}{nt_zone_record_id} || 1;
    return $record_id;
}

sub nt_get_zone_id {
    my $self = shift;

    my %p = validate(
        @_,
        {   'zone'  => { type => SCALAR },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
        }
    );

    #warn "getting zone $p{zone}";

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
        #warn "\tzone $p{zone} not found!";
        return;
    }

    my $zone_id = $r->{store}{zones}[0]{store}{nt_zone_id};
    return $zone_id;
}

sub nt_get_zone_records {
    my $self = shift;

    my %p = validate(
        @_,
        {   'zone_id' => { type => SCALAR },
            'name'    => { type => SCALAR, optional => 1 },
            'type'    => { type => SCALAR, optional => 1 },
            'address' => { type => SCALAR, optional => 1 },
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

    if ( $p{address} ) {
        $request{'3_inclusive'} = 'And';
        $request{'3_field'}     = 'address';
        $request{'3_option'}    = 'equals';
        $request{'3_value'}     = $p{address};
    };

    #warn Dumper(\%request);
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

sub nt_connect {
    my $self = shift;
    my ($nt_host, $nt_port, $nt_user, $nt_pass) = @_;

    return $self->{nt} if $self->{nt};

    eval { require NicTool; };

    if ($EVAL_ERROR) {
        die "Could not load NicTool.pm. Are the NicTool client libraries",
            " installed? They can be found in the api directory in ",
            " the NicToolServer distribution. See http://nictool.com/";
    }

    my $nt = NicTool->new(
            server_host => $nt_host || 'localhost',
            server_port => $nt_port || 8082,
#protocol    => 'xml_rpc',  # or soap
            );

    my $r = $nt->login( username => $nt_user, password => $nt_pass );

    if ( $nt->is_error($r) ) {
        die "error logging in to nictool: $r->{store}{error_msg}\n";
    }

    $self->{nt} = $nt;
    return $nt;
}

sub fully_qualify {
    my ($self, $host) = @_;
    return $host if substr($host, -1, 1) eq '.';
    return "$host.";
};

1;

