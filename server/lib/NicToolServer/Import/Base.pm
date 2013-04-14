package NicToolServer::Import::Base;
# ABSTRACT: base class for NicTool import classes

use strict;
use warnings;

use lib 'lib';

use Cwd;
use Data::Dumper;
use English;
use File::Copy;
use Params::Validate qw/ :all /;

sub new {
    my $class = shift;
    my $self = bless {
            nt_user     => undef,
            nt_pass     => undef,
            group_id    => undef,
            nameservers => undef,
        }, $class;
    return $self;
};

sub get_zone {
    my ($self, $fqdn) = @_;
    chop $fqdn if ( substr($fqdn,-1,1) eq '.' );  # remove trailing dot
    my @bits = split /\./, $fqdn;
    my $host = shift @bits;
    my $zone = join '.', @bits;
    #print "h: $host, z: $zone ($fqdn)\n";
    return ($host, $zone);
};

sub get_zone_id {
    my ($self, $fqdn) = @_;

    chop $fqdn if '.' eq substr $fqdn, -1, 1;
    $fqdn = lc $fqdn;

    # try going right:  host.example.com,  most specific first
    my $zone_id = $self->nt_get_zone_id( zone => $fqdn );
    if ( $zone_id ) {
        return ($zone_id, "$fqdn.");
    };

    my ($host, $zone) = $self->get_zone( lc $fqdn);
    if ( ! $zone ) {
        die "unable to work out zone from $fqdn\n";
    };

    # try:  host .. example.com
    $zone_id = $self->nt_get_zone_id( zone => $zone );
    if ( $zone_id ) {
        return ($zone_id, $host);
    };

    # try going left ( sub.dom .. example.com )
    my ($host2, $zone2) = $self->get_zone($zone);
    $zone_id = $self->nt_get_zone_id( zone => $zone2 );
    if ( $zone_id ) {
        return ($zone_id, "$host.$host2" );
    };

    # try more left ( sub.sub.dom .. example.com )
    my ($host3, $zone3) = $self->get_zone($zone2);
    $zone_id = $self->nt_get_zone_id( zone => $zone3 );
    if ( $zone_id ) {
        return ($zone_id, "$host.$host2.$host3" );
    };

    die "could not find zone for $fqdn\n";
};

sub nt_create_zone {
    my $self = shift;

    my %p = validate( @_, {
            'zone'     => { type => SCALAR },
            'group_id' => { type => SCALAR, optional => 1 },
            'description' => { type => SCALAR },
            'contact' => { type => SCALAR, optional => 1 },
            'ttl'     => { type => SCALAR, optional => 1, default => 86400 },
            'refresh' => { type => SCALAR, optional => 1, default => 16384 },
            'retry'   => { type => SCALAR, optional => 1, default => 2048 },
            'expire' => { type => SCALAR, optional => 1, default => 1048576 },
            'minimum' => { type => SCALAR, optional => 1, default => 2560 },
            'nameservers' => { type => ARRAYREF, optional => 1 },
            'template' => { type => SCALAR, optional => 1, },
            'ip'       => { type => SCALAR, optional => 1, },
            'mailip'   => { type => SCALAR, optional => 1, },
            'logger'   => { type => OBJECT, optional => 1 },
        }
    );

    print "creating zone $p{zone}\n";
    my $nt = $self->nt_connect();

    my $group_id = $p{group_id} || $self->group_id
        or die "group ID not set!\n";
    my $nameservers = $p{nameservers} || $self->nameservers 
        or die "nameservers unset!\n";
    $nameservers = join( ',', @{$nameservers} );

    my $r = $nt->new_zone(
        nt_zone_id  => undef,
        nt_group_id => $group_id,
        zone        => lc $p{zone},
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
    warn "created zone $p{zone} ( $zone_id )\n";
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
        name       => lc $p{name},
        address    => lc $p{address},
        type       => $p{type},
    );

    $self->record_exists( \%request ) and return;

    $request{ttl}         = $p{ttl}         if $p{ttl};
    $request{weight}      = $p{weight}      if defined $p{weight};
    $request{priority}    = $p{priority}    if defined $p{priority};
    $request{other}       = $p{other}       if defined $p{other};
    $request{description} = $p{description} if $p{description};

    print "adding record \n";
    my $nt = $self->nt_connect();
    my $r = $nt->new_zone_record(%request);  # submit to NicToolServer

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    my $record_id = $r->{store}{nt_zone_record_id} || 1;
    return $record_id;
}

sub nt_get_zone_id {
    my $self = shift;

    my %p = validate( @_,
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

    my %p = validate( @_,
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

    $nt_user ||= $self->{nt_user};
    $nt_pass ||= $self->{nt_pass};
    die "no credentials!\n" if ! $nt_pass;

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

sub record_exists {
    my ($self, $record) = @_;

    my $recs = $self->nt_get_zone_records(
        zone_id => $record->{nt_zone_id},
        name    => $record->{name},
        type    => $record->{type},
        address => $record->{address},
    );
    if ( scalar $recs ) {
        print "record exists\n"; # . Dumper($recs);
        return 1;
    };
    return 0;
};

sub nameservers {
    my ($self, $ns) = @_;
    return $self->{nameservers} if ! $ns;
    foreach my $nsid ( @$ns ) {
    };
    $self->{nameservers} = $ns;
    return $ns;
};

sub group_id {
    my ($self, $gid) = @_;
    return $self->{group_id} if ! $gid;
    $self->{group_id} = $gid;
    return $gid;
};

1;

