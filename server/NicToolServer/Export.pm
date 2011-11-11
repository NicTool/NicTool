package NicToolServer::Export;

use strict;
use warnings;

use Data::Dumper;
use Params::Validate  qw/ :all /;

#
# Methods for writing exports of DNS data from NicTool
#
# this class will support the creation of nt_export_djb.pl, nt_export_bind.pl,
# and ease the creation of export scripts for other DNS servers.

# nt_nameserver_export
#   nt_nameserver_id
#   timestamp
#   status
#   timestamp_last_success
#   

sub new {
    die "please pass in a NicToolServer object" if ref $_[1] ne 'NicToolServer';
    bless {
        'dbix_r' => undef,
        'dbix_w' => undef,
        'nsid'   => $_[2],
        'server' => $_[1],
    },
    $_[0];
};

sub export {
    my $self = shift;
    my %p = validate(@_, { ns_id => { type => SCALAR } } );

    $self->get_active_nameservers();
    my $zones = $self->get_ns_zones( %p );

    foreach my $z ( @$zones ) {
        print $self->zr_soa( %p, zone=>$z );
        print $self->zr_ns ( %p, zone=>$z );
        my $records = $self->get_zone_records( zone => $z );
        $self->zr_dispatch( %p, zone=>$z, records=>$records );
    };
    $self->elog( "exported" );
    return 1;
};

sub get_last_ns_export {
    my $self = shift;
    my %p = validate(@_, {
            ns_id     => { type => SCALAR },
            success   => { type => BOOLEAN, optional => 1 },
            partial   => { type => BOOLEAN, optional => 1 },
        });

    my @args = $p{ns_id};
    my $query = "SELECT nt_nameserver_export_log_id AS id, 
        date_start, date_end, message
      FROM nt_nameserver_export_log
        WHERE nt_nameserver_id=?";

    foreach my $f ( qw/ success partial / ) {
        if ( defined $p{$f} ) {
            $query .= " AND $f=?";
            push @args, $p{$f};
        };
    };

    $query .= " ORDER BY date_start DESC LIMIT 1";

    my $logs = $self->{server}->exec_query( $query, \@args );
    return $logs->[0];
};

sub get_dbh {
    my ($self, $dsn) = @_;

    $self->{dbh} = $self->{server}->dbh($dsn);
# get database handles (r/w and r/o) used by the export processes
#
# if a r/o handle is provided, use it for reading zone data. This is useful
# for sites with replicated mysql servers and a local db slave.
#
# The write handle is used for all other purposes. If a specific DSN 
# is provided in the nt_nameserver table, use it. Else use the settings in
# nictoolserver.conf.
#
# 
 
};

sub get_ns_id {
    my $self = shift;
    my %p = validate(@_,
        {
            id   => { type => SCALAR, optional => 1 },
            name => { type => SCALAR, optional => 1 },
            ip   => { type => SCALAR, optional => 1 },
        }
    );

    die "An id, ip, or name must be passed to get_ns_id\n"
        if ( ! $p{id} && ! $p{name} && ! $p{id} );

    my @q_args;
    my $query = "SELECT nt_nameserver_id AS id FROM nt_nameserver 
        WHERE deleted=0";

    if ( defined $p{id} ) {
        $query .= " AND nt_nameserver_id=?";
        push @q_args, $p{id};
    };
    if ( defined $p{ip} ) {
        $query .= " AND address=?";
        push @q_args, $p{ip};
    };
    if ( defined $p{name} ) {
        $query .= " AND name=?";
        push @q_args, $p{name};
    };

    my $nameservers = $self->{server}->exec_query($query, \@q_args);
    return $nameservers->[0]->{id};
};

sub get_ns_zones {
    my $self = shift;
    my %p = validate(@_, {
            ns_id         => { type => SCALAR },
            last_modified => { type => SCALAR, optional => 1 },
        },
    );

    my $sql = "SELECT nt_zone_id, zone, mailaddr, serial, refresh, retry, expire, minimum, ttl, 
        ns0, ns1, ns2, ns3, ns4, ns5, ns6, ns7, ns8, ns9, last_modified
FROM nt_zone 
    WHERE deleted=0";

    my @ns_ids;
    if ( $p{ns_id} != 0 ) {
        for ( 0 .. 9 ) { push @ns_ids, $p{ns_id} };
        $sql .= " AND (ns0 = ? OR ns1 = ? OR ns2 = ? OR ns3 = ? OR ns4 = ? OR ns5 = ? 
            OR  ns6 = ? OR ns7 = ? OR ns8 = ? OR ns9 = ?) ";
    };
    $sql .= " LIMIT 10";

    my $r = $self->{server}->exec_query( $sql, \@ns_ids );
    $self->elog( "retrieved ".scalar @$r." zones");
    return $r;
};

sub get_log_id {
    my $self = shift;
    my %p = validate(@_, { 
            success => { type => BOOLEAN, optional => 1 },
            partial => { type => BOOLEAN, optional => 1 },
        } );
    return $self->{log_id} if defined $self->{log_id};
    my $message = "started";
    my $query = "INSERT INTO nt_nameserver_export_log 
        SET nt_nameserver_id=?, date_start=CURRENT_TIMESTAMP(), message=?";

    my @args = ( $self->{nsid}, $message );
    foreach ( qw/ success partial / ) {
        if ( defined $p{$_} ) {
            $query .= ",$_=?";
            push @args, $p{$_};
        };
    };

    $self->{log_id} = $self->{server}->exec_query( $query, \@args );
    return $self->{log_id};
};

sub get_zone_ns_ids {
    my $self = shift;
    my $zone = shift or die "missing zone";
    ref $zone or die "invalid zone object";

    my @ns_ids;
    for ( 0..9 ) { 
        next if ! $zone->{"ns$_"};
        my $this_nsid = $zone->{"ns$_"};
        push @ns_ids, $this_nsid if $self->{active_ns_ids}{$this_nsid};
    };

    #warn Dumper(\@ns_ids);
    return \@ns_ids;
};

sub get_zone_records {
    my $self = shift;
    my %p = validate(@_, { zone => { type => HASHREF } } );

    my $zid = $p{zone}->{nt_zone_id};
    my $query = "SELECT name,ttl,description,type,address,weight,priority,other
        FROM nt_zone_record
         WHERE deleted=0 AND nt_zone_id=?";

    return $self->{server}->exec_query( $query, $zid );
};

sub get_active_nameservers {
    my $self = shift;
    return $self->{active_ns} if defined $self->{active_ns};

    my $query = "SELECT * FROM nt_nameserver WHERE deleted=0";
    $self->{active_ns} = $self->{server}->exec_query( $query );  # populated

    foreach my $r ( @{ $self->{active_ns} } ) {
        $self->{active_ns_ids}{$r->{nt_nameserver_id}} = $r;

        # tinydns can autogenerate serial numbers based on data file
        # timestamp. Make sure it's enabled for everyone else.
        $r->{export_serials}++ if $r->{export_format} ne 'djb';
    };
    #warn Dumper( $self->{active_ns} );
    return $self->{active_ns};
};

sub elog {
    my $self = shift;
    my $message = shift;
    my %p = validate(@_, { 
            success => { type => BOOLEAN, optional => 1 },
            partial => { type => BOOLEAN, optional => 1 },
        } );
    my $logid = $self->get_log_id();
    my $query = "UPDATE nt_nameserver_export_log 
    SET message=CONCAT_WS(', ',message,?)";

    my @args = $message;
    foreach ( qw/ success partial / ) {
        if ( defined $p{$_} ) {
            $query .= ",$_=?";
            push @args, $p{$_};
        };
    };

    push @args, $self->{nsid}, $logid;
    $query .= "WHERE nt_nameserver_id=? AND nt_nameserver_export_log_id=?";
    $self->{server}->exec_query( $query, \@args ); 
};

sub zr_soa {
    my $self = shift;
    my %p = validate(@_, { 
            ns_id => { type => SCALAR },
            zone  => { type => HASHREF },
        } );

    my $ns_ref = $self->{active_ns_ids}{$p{ns_id}};
    my $format = $ns_ref->{export_format};  # djb, bind, etc...
    my $method = "zr_${format}_soa";
    my $r = $self->$method(%p);     # format record for nameserver type
    return $r;
};

sub zr_ns {
    my $self = shift;
    my %p = validate(@_, { 
            ns_id => { type => SCALAR },
            zone  => { type => HASHREF },
        } );

    my $this_ns = $self->{active_ns_ids}{$p{ns_id}};

    my $zone = $p{zone};

    my @selected_ns;
    for my $i ( 0..9 ) {
        push @selected_ns, $zone->{'ns'.$i} if $zone->{'ns'.$i};
    };

    my $format = $this_ns->{export_format};

    my $r;
    foreach my $nsid ( @selected_ns ) {
        my $method = 'zr_' . $format . '_ns';

        $r .= $self->$method( 
            record => {
                name    => $zone->{zone},
                address => $self->qualify($self->{active_ns_ids}{$nsid}{name}, $zone->{zone}),
                ttl     => $self->{active_ns_ids}{$nsid}{ttl},
                location=> $this_ns->{location} || '',
            },
        );
    };
    return $r;
};

sub zr_dispatch {
    my $self = shift;
    my %p = validate(@_, { 
            ns_id  => { type => SCALAR },
            zone   => { type => HASHREF },
            records =>{ type => ARRAYREF },
        } );

    my $this_ns = $self->{active_ns_ids}{$p{ns_id}};
    my $format = $this_ns->{export_format};
    $self->{zone_name} = $p{zone}{zone}; # for reference by ->qualify

    foreach my $r ( @{ $p{records} } ) {
        my $type = lc( $r->{type} );
        my $method = "zr_${format}_${type}";
        $r->{location} ||= '';
        print $self->$method( record=>$r);
    };
};

sub zr_djb_a {
    my $self = shift;
    my %p = validate(@_, { 
            record => { type => HASHREF },
        } );

    my $r = $p{record};
    #warn Data::Dumper::Dumper($r);

    return '+'                           # special char
        .  $self->qualify( $r->{name} ) # fqdn
        . ':' . $r->{address}            # ip
        . ':' . $r->{ttl}                # ttl
        . ':'                            # timestamp
        . ':' . $r->{location}           # location
        . "\n";
};

sub zr_djb_cname {
    my $self = shift;
    my %p = validate(@_, { record => { type => HASHREF } } );

    my $r = $p{record};
    #warn Data::Dumper::Dumper($r);

    return 'C'                                  # special char
        .       $self->qualify( $r->{name} )    # fqdn
        . ':' . $self->qualify( $r->{address} ) # p   (host/domain name)
        . ':' . $r->{ttl}                       # ttl
        . ':'                                   # timestamp
        . ':' . $r->{location}                  # lo
        . "\n";
};

sub zr_djb_mx {
    my $self = shift;
    my %p = validate(@_, { record => { type => HASHREF } } );

    my $r = $p{record};

    return '@'                                   # special char
        .       $self->qualify( $r->{name} )     # fqdn
        . ':'                                    # ip
        . ':' . $self->qualify( $r->{address} )  # x
        . ':' . $r->{weight}                     # distance
        . ':' . $r->{ttl}                        # ttl
        . ':'                                    # timestamp
        . ':' . $r->{location}                   # lo
        . "\n";
};

sub zr_djb_txt {
    my $self = shift;
    my %p = validate(@_, { record => { type => HASHREF } } );

    my $r = $p{record};
    #warn Data::Dumper::Dumper($r);

    return "'"                                  # special char '
        .       $self->qualify( $r->{name} )    # fqdn
        . ':' . $self->escape( $r->{address} )  # s
        . ':' . $r->{ttl}                       # ttl
        . ':'                                   # timestamp
        . ':' . $r->{location}                  # lo
        . "\n";
};

sub zr_djb_ns {
    my $self = shift;
    my %p = validate(@_, { record => { type => HASHREF } } );

    my $r = $p{record};
    #warn Data::Dumper::Dumper($r);

    return '&'                                   # special char
        .       $self->qualify( $r->{name} )     # fqdn
        . ':'                                    # ip
        . ':' . $self->qualify( $r->{address} )  # x (hostname)
        . ':' . $r->{ttl}                        # ttl
        . ':'                                    # timestamp
        . ':' . $r->{location}                   # lo
        . "\n";
};

sub zr_djb_ptr {
    my $self = shift;
    my %p = validate(@_, { record => { type => HASHREF } } );

    my $r = $p{record};
    #warn Data::Dumper::Dumper($r);

    return '^'                                   # special char
        .       $self->qualify( $r->{name} )     # fqdn
        . ':' .                 $r->{address}    # p
        . ':' . $r->{ttl}                        # ttl
        . ':'                                    # timestamp
        . ':' . $r->{location}                   # lo
        . "\n";
};

sub zr_djb_soa {
    my $self = shift;
    my %p = validate(@_, { 
            ns_id => { type => SCALAR },
            zone  => { type => HASHREF },
        } );

    my $z = $p{zone};

    my $ns_ids = $self->get_zone_ns_ids( $z );
    my $primary_ns = $self->{active_ns_ids}{ $ns_ids->[0] }{name};
    my $serial = $self->{active_ns_ids}{ $p{ns_id} }{export_serials} ? $z->{serial} : '';
    my $location = $z->{location} || 'ex';

    return 'Z'
        . ":$z->{zone}"      # fqdn
        . ":$primary_ns"     # mname
        . ":$z->{mailaddr}"  # rname
        . ":$serial"         # serial
        . ":$z->{refresh}"   # refresh
        . ":$z->{retry}"     # retry
        . ":$z->{expire}"    # expire
        . ":$z->{minimum}"   # min
        . ":$z->{ttl}"       # ttl
        . ":"                # timestamp
        . ":$location"       # location
        . "\n";
# maybe TODO: append DB ids (why?)
};

sub zr_djb_spf {
    my $self = shift;
    my %p = validate(@_, { record => { type => HASHREF } } );

    my $r = $p{record};
    #warn Data::Dumper::Dumper($r);

    return ":"                                  # special char
        .       $self->qualify( $r->{name} )    # fqdn
        . '99'                                  # n
        . ':' . $self->escape( $r->{address} )  # rdata
        . ':' . $r->{ttl}                       # ttl
        . ':'                                   # timestamp
        . ':' . $r->{location}                  # lo
        . "\n";
};

sub zr_djb_srv {
    my $self = shift;
    my %p = validate(@_, { record => { type => HASHREF } } );

    my $r = $p{record};
    #warn Data::Dumper::Dumper($r);

    # :fqdn:n:rdata:ttl:timestamp:lo (Generic record)
    my $priority = escapeNumber( $self->is_ip_port( $r->{priority} ) );
    my $weight   = escapeNumber( $self->is_ip_port( $r->{weight}   ) );
    my $port     = escapeNumber( $self->is_ip_port( $r->{other}    ) );

# SRV
# :sip.tcp.example.com:33:\000\001\000\002\023\304\003pbx\007example\003com\000
    
    my $target = "";
    my @chunks = split /\./, $self->qualify( $r->{address} );
    foreach my $chunk (@chunks) {
        $target .= characterCount($chunk) . $chunk;
    }

    return ':'                                   # special char (generic)
        . escape( $self->qualify( $r->{name} ) ) # fqdn
        . ':33'                                  # n
        . ':' . $priority . $weight . $port . $target . "\\000" # rdata
        . ':' . $r->{ttl}                        # ttl
        . ':'                                    # timestamp
        . ':' . $r->{location}                   # lo
        . "\n";
};

sub zr_djb_aaaa {
    my $self = shift;
    my %p = validate(@_, { record => { type => HASHREF } } );

    my $r = $p{record};
    
# :fqdn:n:rdata:ttl:timestamp:lo (generic record format)
# ffff:1234:5678:9abc:def0:1234:0:0
# :example.com:28:\377\377\022\064\126\170\232\274\336\360\022\064\000\000\000\000
    
    my ( $a, $b, $c, $d, $e, $f, $g, $h ) = split /:/, $r->{address};
    if ( !defined $h ) {
        die "Didn't get a valid-looking IPv6 address\n";
    }   
    
    $a = escapeHex( sprintf "%04s", $a ); 
    $b = escapeHex( sprintf "%04s", $b );
    $c = escapeHex( sprintf "%04s", $c );
    $d = escapeHex( sprintf "%04s", $d );
    $e = escapeHex( sprintf "%04s", $e );
    $f = escapeHex( sprintf "%04s", $f );
    $g = escapeHex( sprintf "%04s", $g );
    $h = escapeHex( sprintf "%04s", $h );
    
    return ':'                           # generic record format
        . $self->qualify( $r->{name} )   # fqdn
        . ':28'                          # n
        . ':' . "$a$b$c$d$e$f$g$h"       # rdata
        . ':' . $r->{ttl}                # ttl
        . ':'                            # timestamp
        . ':'                            # location
        . "\n";
}       

sub is_ip_port {
    my ($self, $port) = @_;

    return $port if ( $port >= 0 && $port <= 65535 );
    warn "value not within IP port range: 0 - 65535";
    return 0;
};

sub qualify {
    my ($self, $record, $zone) = @_;
    return $record if $record =~ /\.$/;    # record already ends in .
    $zone ||= $self->{zone_name} or return $record;
    return $record if $record =~ /$zone$/; # ends in zone, just no .
    return "$record.$zone" # append missing zone name 
}


# 4 following subs based on http://www.anders.com/projects/sysadmin/djbdnsRecordBuilder/
sub escape {
    my $line = pop @_;
    my $out;

    foreach my $char ( split //, $line ) {
        if ( $char =~ /[\r\n\t: \\\/]/ ) {
            $out .= sprintf "\\%.3lo", ord $char;
        }
        else {
            $out .= $char;
        }
    }
    return $out;
};

sub escapeHex {
    # takes a 4 character hex value and converts it to two escaped numbers
    my $line = pop @_;
    my @chars = split //, $line;

    my $out = sprintf "\\%.3lo", hex "$chars[0]$chars[1]";
    $out .= sprintf "\\%.3lo", hex "$chars[2]$chars[3]";
    
    return $out;
}

sub escapeNumber {
    my $number     = pop @_;
    my $highNumber = 0;

    if ( $number - 256 >= 0 ) {
        $highNumber = int( $number / 256 );
        $number = $number - ( $highNumber * 256 );
    }
    my $out = sprintf "\\%.3lo", $highNumber;
    $out .= sprintf "\\%.3lo", $number;

    return $out;
}

sub characterCount {
    my $line  = pop @_;
    my @chars = split //, $line;
    my $count = @chars;
    return ( sprintf "\\%.3lo", $count );
}


#  A          =>  + fqdn : ip : ttl:timestamp:lo
#  CNAME      =>  C fqdn :  p : ttl:timestamp:lo
#  MX         =>  @ fqdn : ip : x:dist:ttl:timestamp:lo
#  TXT        =>  ' fqdn :  s : ttl:timestamp:lo
#  NS         =>  & fqdn : ip : x:ttl:timestamp:lo
#  PTR        =>  ^ fqdn :  p : ttl:timestamp:lo
#  SOA        =>  Z fqdn:mname:rname:ser:ref:ret:exp:min:ttl:time:lo
#  'A,PTR'    =>  = fqdn : ip : ttl:timestamp:lo
#  'SOA,NS,A' =>  . fqdn : ip : x:ttl:timestamp:lo
#  GENERIC    =>  : fqdn : n  : rdata:ttl:timestamp:lo
#  IGNORE     =>  - fqdn : ip : ttl:timestamp:lo

1;
