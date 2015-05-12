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
my $log         = 0;
%main::qcache           = ();
$main::nt_nameserver_id = 1;

#avoid CNAME loops
%main::seenrecid = ();
chomp($line);

unless ( $line eq "HELO\t1" ) {
    print "FAIL\n";
    print STDERR "Recevied '$line'\n";

    #<<>;;
    exit;
}
print "OK\tNicTool Backend firing up\n";    # print our banner

my $dsn = "DBI:mysql:database=nictool;host=127.0.0.1";
my $dbh = DBI->connect( $dsn, 'nictool', 'lootcin205' )
    or die "LOG\tUnable to connect to database: $!\nFAIL\n";

print "LOG\tPID $$\n" if $log;

while (<>) {

    #	print STDERR "$$ Received: $_";
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
            print "LOG\tPowerDNS sent unparseable line: "
                . join( ":", @arr ) . "\n";
            print "FAIL\n";
            next;
        }
        elsif ($cache) {
            @res = @{ $cache->{response} };
        }
        elsif ($qtype eq "A"
            || $qtype eq 'MX'
            || $qtype eq 'PTR'
            || $qtype eq 'CNAME' )
        {
            @res = &get_records(@arr);
            $main::qcache{ $qname . ":" . $qtype }
                = +{ response => [@res], expire => $default_ttl + time };
        }
        elsif ( $qtype eq 'NS' ) {
            @res = &get_ns(@arr);
            $main::qcache{ $qname . ":" . $qtype }
                = +{ response => [@res], expire => $default_ttl + time };
        }
        elsif ( $qtype eq 'SOA' ) {
            @res = &get_soa(@arr);
            $main::qcache{ $qname . ":" . $qtype }
                = +{ response => [@res], expire => $default_ttl + time };
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
   LEFT JOIN nt_zone_record r ON z.nt_zone_id=r.nt_zone_id 
   LEFT JOIN resource_record_type t ON r.type_id=t.id
    WHERE z.nt_zone_id=$zoneid 
      AND z.deleted=0
      AND r.deleted=0 
];

    print STDERR "\t" . $sql . "\n" if $warnsql;
    my $sth = $dbh->prepare($sql);
    my @result;
    if ( $sth->execute ) {
        my @rows;
        while ( $t = $sth->fetchrow_hashref ) {
            push @result,
                [
                "DATA",
                $t->{name} =~ /\.$/
                ? $t->{name}
                : $t->{name} . "." . $t->{zone},
                'IN',
                $t->{type},
                $t->{ttl},
                ( $use_zone_id ? $t->{'nt_zone_id'} : 1 ),
                $t->{address}
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
            zone => join( ".", @zs ),
            record => $t ? $t : $qname . "."
            };

        # get *.zone
        push @order,
            +{
            zone   => join( ".",        @zs ),
            record => "*." . join( ".", @zs ) . "."
            }
            if @order > 1;

        $t = $t ? $t . "." . shift @zs : shift @zs;

    }

    my $sql = "
 SELECT z.nt_zone_id, z.zone, t.name AS type, 
        r.name, r.ttl, r.address, r.weight, r.priority, r.other,
        r.nt_zone_record_id
   FROM nt_zone z
   LEFT JOIN nt_zone_record r ON z.nt_zone_id=r.nt_zone_id
   LEFT JOIN resource_record_type t ON r.type_id=t.id
   LEFT JOIN nt_zone_nameserver ns ON ns.nt_zone_id=z.nt_zone_id
     WHERE ( " 
        . join( " OR ",
            map {
                  " z.zone = " . $dbh->quote( $_->{'zone'} )
                . " AND r.name = " . $dbh->quote( $_->{'record'} )
                } @order
            )
        . " ) 
         AND ( t.name = '$qtype' OR t.name ='CNAME' ) 
         AND ns.nt_nameserver_id=$main::nt_nameserver_id
         AND z.deleted=0
         AND r.deleted=0 ";

    print STDERR "\t" . $sql . "\n" if $warnsql;
    my $sth = $dbh->prepare($sql);
    my @result;
    if ( $sth->execute ) {
        my @rows;
        while ( $t = $sth->fetchrow_hashref ) {
            print Dumper($t) if $warnsql;
            $t->{address} =~ s/\.$//;
            push @result,
                [
                "DATA", $qname, $qclass, $t->{type}, $t->{ttl},
                ( $use_zone_id ? $t->{'nt_zone_id'} : 1 ),
                $t->{address}
                ];
            push @rows, $t;
            $main::seenrecid{ $t->{'nt_zone_record_id'} } = 1;
            if ( $t->{type} eq 'CNAME'
                && !exists $main::seenrecid{ $t->{'nt_zone_record_id'} } )
            {
                $t->{address} =~ s/\.$//;
                push @result,
                    &get_records( $type, $t->{address}, $qclass, $qtype, $id,
                    $ip );
            }
        }

    }
    return @result;
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
    LEFT JOIN nt_zone_nameserver zns ON z.nt_zone_id=zns.nt_zone_id
    LEFT JOIN nt_nameserver ns ON zns.nt_nameserver_id=ns.nt_nameserver_id
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
                "DATA", $qname, $qclass, $qtype, $t->{ttl},
                $use_zone_id ? $t->{'nt_zone_id'} : 1,
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
LEFT JOIN nt_zone_nameserver zns ON z.nt_zone_id=zns.nt_zone_id
LEFT JOIN nt_nameserver ns ON zns.`nt_nameserver_id`=ns.`nt_nameserver_id`
 WHERE z.zone = " . $dbh->quote($qname)
." AND z.deleted=0
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
            "DATA",  $qname,
            $qclass, $qtype,
            $t->{ttl}, $use_zone_id ? $t->{'nt_zone_id'} : 1,
            $t->{name},   $t->{mailaddr},
            $t->{serial}, $t->{refresh},
            $t->{retry},  $t->{expire},
            $t->{ttl}
            ];

    }

    return @result;
}

$dbh->disconnect;

print "LOG\tExitting...$$\n";
