package NicToolServer::Import::tinydns;
# ABSTRACT: import tinydns data into NicTool

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Import::Base';

use Cwd;
use Data::Dumper;
use English;
use File::Copy;
use Params::Validate qw/ :all /;
use Time::TAI64 qw/ unixtai64 /;

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
    };
 
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
}

sub zr_generic {
    my $self = shift;
    die "oops, no generic support yet!\n";
    my $r = shift or die;
    print "Generic : $r\n";
    my ( $fqdn, $ip, $host, $ttl, $timestamp, $location ) = split(':', $r);
}


1;

