#!/usr/bin/perl -w
#
# PowerDNS Coprocess backend, based on provided sample
#
# (C) 2002 Dajoba, LLC
# (c) 2012 The Network People, Inc.
#
# Portions may be (C) Powerdns BV
#

use strict;
use DBI;
use Data::Dumper;

$| = 1;

my $line        = <>;
my $warnsql     = @ARGV;
my $use_zone_id = 1;
my $default_ttl = 20;
my $log         = 1;
%main::qcache           = ();
$main::nt_nameserver_id = 1;

#avoid CNAME loops
%main::seenrecid = ();
chomp($line);

unless ( $line =~ /^HELO\t(\d+)$/ && $1 >= 1 ) {
    print "FAIL\n";
    print STDERR "Recevied '$line'\n";

    #<<>;;
    exit;
}
print "OK\tNicTool Backend firing up\n";    # print our banner

my $db_name = $ENV{NT_PDNS_DB_NAME} // 'nictool';
my $db_host = $ENV{NT_PDNS_DB_HOST} // '127.0.0.1';
my $db_user = $ENV{NT_PDNS_DB_USER} // 'nictool';
my $db_pass = $ENV{NT_PDNS_DB_PASS} // 'lootcin!mysql';

my $dsn = "DBI:mysql:database=$db_name;host=$db_host;mysql_ssl=1";
my $dbh = DBI->connect( $dsn, $db_user, $db_pass )
    or die "LOG\tUnable to connect to database: $!\nFAIL\n";

print "LOG\tPID $$\n" if $log;

while (<>) {

    # print STDERR "$$ Received: $_";
    chomp();
    my @arr = split(/\t/);
    my @res;

    print "LOG\t$_\n" if $log;
    my ( $type, $qname, $qclass, $qtype, $id, $ip ) = split(/\t/);
    if ( $type eq 'Q' ) {
        my $cache = $main::qcache{ $qname . ":" . $qtype };
        my @res;
        if ( $cache and ( $cache->{expire} < time ) ) {
            delete $main::qcache{ $qname . ":" . $qtype };
            undef $cache;

            #print "LOG\tCLEARING cached data for $qname : $qtype\n";
        }
        elsif ($cache) {
            print "LOG\tUsing cached data for $qname : $qtype\n" if $log;
        }
        elsif ( !$cache ) {
            print "LOG\t***NOT Using cached data for $qname : $qtype\n"
                if $log;
        }
        if ( @arr < 6 ) {
            print "LOG\tPowerDNS sent unparseable line: " . join( ":", @arr ) . "\n";
            print "FAIL\n";
            next;
        }
        elsif ($cache) {
            @res = @{ $cache->{response} };
        }
        elsif ($qtype eq 'A'
            || $qtype eq 'AAAA'
            || $qtype eq 'MX'
            || $qtype eq 'PTR'
            || $qtype eq 'CNAME'
            || $qtype eq 'TXT'
            || $qtype eq 'SRV' )
        {
            @res = &get_records(@arr);
            $main::qcache{ $qname . ":" . $qtype } =
                +{ response => [@res], expire => $default_ttl + time };
        }
        elsif ( $qtype eq 'ANY' ) {
            # PDNS commonly asks ANY for lookups that were originally NS/A/etc.
            # Include both explicit RR data and nameserver table data.
            @res = ( &get_records(@arr), &get_ns(@arr) );
            @res = _uniq_rows(@res);
            $main::qcache{ $qname . ":" . $qtype } =
                +{ response => [@res], expire => $default_ttl + time };
        }
        elsif ( $qtype eq 'NS' ) {
            # Return zone apex NS from nt_zone_nameserver and any explicit NS RRs.
            # This helps modern PDNS clients that ask NS in multiple contexts.
            @res = ( &get_ns(@arr), &get_records(@arr) );
            @res = _uniq_rows(@res);
            $main::qcache{ $qname . ":" . $qtype } =
                +{ response => [@res], expire => $default_ttl + time };
        }
        elsif ( $qtype eq 'SOA' ) {
            @res = &get_soa(@arr);
            $main::qcache{ $qname . ":" . $qtype } =
                +{ response => [@res], expire => $default_ttl + time };
        }
        elsif ( $qtype eq "MBOXFW" ) {
        }
        for (@res) {
            print "LOG\t get $type: " . join( ":", @$_ ) . "\n" if $log;
            print join( "\t", @$_ ) . "\n";
        }

    }
    elsif ( $type eq "AXFR" ) {
        my @res = &get_axfr(@arr);
        for (@res) {
            print "LOG\t get axfr: " . join( ":", @$_ ) . "\n" if $log;
            print join( "\t", @$_ ) . "\n";
        }
    }
    elsif ( $type eq 'PING' ) {
    }

    #print join("\t", @res) if @res;
    #	print STDERR "$$ End of data\n";
    %main::seenrecid = ();
    print "END\n";
}

sub get_axfr {
    my ( $type, $zoneid ) = @_;
    my $t = '';

        my $sql = qq[
 SELECT z.nt_zone_id, z.zone, t.name AS type,
                r.name, r.ttl, r.address, r.weight, r.priority, r.other
 FROM nt_zone z
     INNER JOIN nt_zone_record r ON z.nt_zone_id=r.nt_zone_id
     LEFT JOIN resource_record_type t ON r.type_id=t.id
 WHERE z.nt_zone_id=?
     AND z.deleted=0
     AND r.deleted=0
];

    print STDERR "\t" . $sql . "\n" if $warnsql;
    my $sth = $dbh->prepare($sql);
    my @result;
        if ( $sth->execute($zoneid) ) {
        my @rows;
        while ( $t = $sth->fetchrow_hashref ) {
            my @content = rr_content_fields($t);
            push @result,
                [
                "DATA", $t->{name} =~ /\.$/
                ? $t->{name}
                : $t->{name} . "." . $t->{zone},
                'IN', $t->{type}, $t->{ttl}, ( $use_zone_id ? $t->{'nt_zone_id'} : 1 ),
                @content
                ];
            push @rows, $t;
        }

    }
    return @result;
}

sub get_records {
    my ( $type, $qname, $qclass, $qtype, $id, $ip ) = @_;
    my @zs;
    my @order;
    my $t = '';
    print "LOG\tcall get_records\n" if $log;
    @zs = split( /\./, $qname );
    for my $n ( 1 .. scalar(@zs) ) {
        push @order,
            +{
            zone   => join( ".", @zs ),
            record => $t ? $t : $qname . "."
            };

        # get *.zone
        push @order,
            +{
            zone   => join( ".", @zs ),
            record => "*." . join( ".", @zs ) . "."
            }
            if @order > 1;

        $t = $t ? $t . "." . shift @zs : shift @zs;

    }

    my %wanted_zones = map { $_->{zone} => 1 } @order;
    my @zone_names   = keys %wanted_zones;
    return () if !@zone_names;

    my $zone_name_placeholders = join( ',', ('?') x @zone_names );
    my $zone_lookup_sql        = "
 SELECT z.nt_zone_id, z.zone
   FROM nt_zone z
   INNER JOIN nt_zone_nameserver ns
           ON ns.nt_zone_id = z.nt_zone_id
          AND ns.nt_nameserver_id = ?
  WHERE z.deleted=0
    AND z.zone IN ($zone_name_placeholders)
";

    print STDERR "\t" . $zone_lookup_sql . "\n" if $warnsql;
    my $zsth = $dbh->prepare($zone_lookup_sql);
    my @zone_lookup_params = ( $main::nt_nameserver_id, @zone_names );
    return () if !$zsth->execute(@zone_lookup_params);

    my %zone_id_for;
    while ( my $z = $zsth->fetchrow_hashref ) {
        $zone_id_for{ $z->{zone} } = $z->{nt_zone_id};
    }

    my @zone_name_pairs;
    foreach my $entry (@order) {
        my $zid = $zone_id_for{ $entry->{zone} };
        next if !$zid;
        push @zone_name_pairs, [ $zid, $entry->{record} ];
    }
    return () if !@zone_name_pairs;

    my $pair_placeholders = join( ',', ('(?,?)') x @zone_name_pairs );
    my @pair_params       = map { @$_ } @zone_name_pairs;
    my @query_params      = (@pair_params);

    my $type_clause = '';
    if ( $qtype ne 'ANY' ) {
        $type_clause = " AND (t.name = ? OR t.name = 'CNAME') ";
        push @query_params, $qtype;
    }

    my $sql = "
 SELECT r.nt_zone_id, t.name AS type,
        r.name, r.ttl, r.address, r.weight, r.priority, r.other,
        r.nt_zone_record_id
   FROM nt_zone_record r
   INNER JOIN nt_zone z
           ON z.nt_zone_id = r.nt_zone_id
          AND z.deleted=0
   INNER JOIN nt_zone_nameserver ns
           ON ns.nt_zone_id = z.nt_zone_id
          AND ns.nt_nameserver_id = $main::nt_nameserver_id
   LEFT JOIN resource_record_type t ON r.type_id=t.id
  WHERE (r.nt_zone_id, r.name) IN ($pair_placeholders)
    AND r.deleted=0
    $type_clause
";

    print STDERR "\t" . $sql . "\n" if $warnsql;
    my $sth = $dbh->prepare($sql);
    my @result;
    if ( $sth->execute(@query_params) ) {
        my @rows;
        while ( $t = $sth->fetchrow_hashref ) {
            print Dumper($t) if $warnsql;
            my @content = rr_content_fields($t);
            push @result,
                [
                "DATA", $qname, $qclass, $t->{type}, $t->{ttl},
                ( $use_zone_id ? $t->{'nt_zone_id'} : 1 ),
                @content
                ];
            push @rows, $t;
            $main::seenrecid{ $t->{'nt_zone_record_id'} } = 1;
            if ( $t->{type} eq 'CNAME'
                && !exists $main::seenrecid{ $t->{'nt_zone_record_id'} } )
            {
                $t->{address} =~ s/\.$//;
                push @result, &get_records( $type, $t->{address}, $qclass, $qtype, $id, $ip );
            }
        }
    }
    return @result;
}

sub rr_content_fields {
    my ($rr) = @_;

    my $address = defined $rr->{address} ? $rr->{address} : '';
    $address =~ s/\.$//;

    if ( $rr->{type} eq 'MX' ) {
        my $pref = defined $rr->{weight} ? $rr->{weight} : 0;
        return ( $pref, $address );
    }

    if ( $rr->{type} eq 'SRV' ) {
        my $priority = defined $rr->{priority} ? $rr->{priority} : 0;
        my $weight   = defined $rr->{weight}   ? $rr->{weight}   : 0;
        my $port     = defined $rr->{other}    ? $rr->{other}    : 0;
        return ( $priority, join( ' ', $weight, $port, $address ) );
    }

    return ($address);
}

sub get_ns {
    my ( $type, $qname, $qclass, $qtype, $id, $ip ) = @_;
    my @zs;
    my @order;
    my $t = '';

        my $sql = "
  SELECT z.nt_zone_id,
         ns.ttl, ns.name, ns.address
  FROM nt_zone z
        INNER JOIN nt_zone_nameserver zns ON z.nt_zone_id=zns.nt_zone_id
        INNER JOIN nt_nameserver ns ON zns.nt_nameserver_id=ns.nt_nameserver_id
    WHERE z.zone = " . $dbh->quote($qname) . "
      AND z.deleted=0 
      AND ns.deleted=0 ";
    print STDERR "\t" . $sql . "\n" if $warnsql;
    my $sth = $dbh->prepare($sql);
    my @result;

    if ( $sth->execute ) {
        my @rows;
        while ( $t = $sth->fetchrow_hashref ) {
            push @result,
                [
                "DATA", $qname, $qclass, 'NS', $t->{ttl}, $use_zone_id ? $t->{'nt_zone_id'} : 1,
                $t->{name}
                ];
            push @rows, $t;
        }

    }

    return @result;

}

sub get_soa {
    my ( $type, $qname, $qclass, $qtype, $id, $ip ) = @_;
    my @zs;
    my @order;
    my $t = '';

        my $sql = "
SELECT ns.name, z.* 
  FROM nt_zone z
INNER JOIN nt_zone_nameserver zns ON z.nt_zone_id=zns.nt_zone_id
INNER JOIN nt_nameserver ns ON zns.`nt_nameserver_id`=ns.`nt_nameserver_id`
 WHERE z.zone = " . $dbh->quote($qname) . " AND z.deleted=0
   AND ns.deleted=0
 LIMIT 1";

    print STDERR "\t" . $sql . "\n" if $warnsql;
    my $sth = $dbh->prepare($sql);
    my @result;

    if ( $sth->execute ) {
        my @rows;
        $t = $sth->fetchrow_hashref;
        return unless $t;
        print Dumper($t) if $warnsql;
        $t->{mailaddr} =~ s/\./@/;
        push @result,
            [
            "DATA",       $qname,
            $qclass,      $qtype,
            $t->{ttl},    $use_zone_id ? $t->{'nt_zone_id'} : 1,
            $t->{name},   $t->{mailaddr},
            $t->{serial}, $t->{refresh},
            $t->{retry},  $t->{expire},
            $t->{ttl}
            ];
    }

    return @result;
}

sub _uniq_rows {
    my @rows = @_;
    my %seen;
    return grep { !$seen{ join( "\t", @$_ ) }++ } @rows;
}

$dbh->disconnect;

print "LOG\tExitting...$$\n";
