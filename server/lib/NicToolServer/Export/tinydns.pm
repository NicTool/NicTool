package NicToolServer::Export::tinydns;
# ABSTRACT: export NicTool DNS data to tinydns (part of djbdns)

use strict;
use warnings;

use Cwd;
use Data::Dumper;
use File::Copy;
use Params::Validate qw/ :all /;
use Time::TAI64 qw/ unixtai64 /;

# maybe TODO: append DB ids (but why?)

sub new {
    my $class = shift;

    my $self = bless {
        nte => shift,
        FH  => undef,
    },
    $class;

    warn "oops, a NicToolServer::Export object wasn't provided!" 
        if ! $self->{nte};
    return $self;
}

sub get_export_file {
    my $self = shift;
    my $dir = shift || $self->{nte}->get_export_dir or return;

    # reuse the same file handle for every zone.
    return $self->{FH} if $self->{FH};

    # not opened yet, move old file aside
    my $filename = $dir . '/data';
    if ( -e $filename ) {
        move( $filename, "$filename.orig" );
    };

    open my $FH, '>', $filename
        or die $self->{nte}->elog("failed to open $filename");

    $self->{FH} = $FH;
    return $FH;
};

sub postflight {
    my $self = shift;

    # compile data to data.cdb
    $self->compile_cdb or return;

    # rsync file into place
    $self->rsync_cdb or return;

    return 1;
}

sub compile_cdb {
    my $self = shift;

    # compile data -> data.cdb
    my $export_dir = $self->{nte}{export_dir};

    if ( ! -e "$export_dir/Makefile" ) {
        my $address = $self->{nte}{ns_ref}{address} || '127.0.0.1';
        my $datadir = $self->{nte}{ns_ref}{datadir} || getcwd . '/data-all';
        $datadir =~ s/\/$//;  # strip off any trailing /
        open my $M, '>', "$export_dir/Makefile";
        print $M <<MAKE
# compiles data.cdb using the tinydns-data program.
# make sure the path to tinydns-data is correct
# test this target by running 'make data.cdb' in this directory
data.cdb: data
\t/usr/local/bin/tinydns-data

# copies the data file to the remote host. The address is the nameservers IP
# as defined in the NicTool database. Adjust it if necessary. Add additional
# rsync lines to copy to additional hosts.
remote: data.cdb
\trsync -az data.cdb tinydns\@$address:$datadir/data.cdb

# If the DNS server is running locally and rsync is not necessary, trick
# the export process into thinking it worked by setting the 'remote' make
# target to any system command that will succeed. An example is provided.
# test by running the 'make remote' target and make sure it succeeds:
#   make test && echo "it worked"
noremote: data.cdb
\ttest 1
MAKE
;
        close $M;
    };
    chdir $export_dir;
    my $before = time;
    system ('make data.cdb') == 0
        or die $self->{nte}->elog("unable to compile cdb: $?");
    my $elapsed = time - $before;
    my $message = "compiled";
    $message .= ( $elapsed > 5 ) ? " ($elapsed secs)" : '';
    $self->{nte}->elog($message);
    return 1;
};

sub rsync_cdb {
    my $self = shift;

    my $dir = $self->{nte}{export_dir};

    return 1 if ! defined $self->{nte}{ns_ref}{address};  # no rsync
    #warn Dumper($self->{nte});

    if ( -e "$dir/Makefile" && ! `grep remote $dir/Makefile` ) {
        my $address = $self->{nte}{ns_ref}{address} || '127.0.0.1';
        my $datadir = $self->{nte}{ns_ref}{datadir} || getcwd . '/data-all';
        $datadir =~ s/\/$//;  # strip off any trailing /
        open my $M, '>>', "$dir/Makefile";
        print $M <<MAKE
# copies the data file to the remote host. The address is the nameservers IP
# as defined in the NicTool database. Adjust it if necessary. Add additional
# rsync lines to copy to additional hosts.
remote: data.cdb
\trsync -az data.cdb tinydns\@$address:$datadir/data.cdb
MAKE
;
        close $M;
    };

    my $before = time;
    system ('make remote') == 0
        or die $self->{nte}->elog("unable to rsync cdb: $?");
    my $elapsed = time - $before;
    my $message = "copied";
    $message .= " ($elapsed secs)" if $elapsed > 5;
    $self->{nte}->elog($message);
    return 1;
};

sub zr_a {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF }, } );

    my $r = $p{record};

    #warn Data::Dumper::Dumper($r);

    return '+'                            # special char
        . $self->qualify( $r->{name} )    # fqdn
        . ':' . $r->{address}             # ip
        . ':' . $r->{ttl}                 # ttl
        . ':' . $r->{timestamp}           # timestamp
        . ':' . $r->{location}            # location
        . "\n";
}

sub zr_cname {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

    #warn Data::Dumper::Dumper($r);

    return 'C'                                     # special char
        . $self->qualify( $r->{name} )             # fqdn
        . ':' . $self->qualify( $r->{address} )    # p   (host/domain name)
        . ':' . $r->{ttl}                          # ttl
        . ':' . $r->{timestamp}                    # timestamp
        . ':' . $r->{location}                     # lo
        . "\n";
}

sub zr_mx {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

    return '@'                                     # special char
        . $self->qualify( $r->{name} )             # fqdn
        . ':'                                      # ip
        . ':' . $self->qualify( $r->{address} )    # x
        . ':' . $r->{weight}                       # distance
        . ':' . $r->{ttl}                          # ttl
        . ':' . $r->{timestamp}                    # timestamp
        . ':' . $r->{location}                     # lo
        . "\n";
}

sub zr_txt {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

    #warn Data::Dumper::Dumper($r);

    return "'"                                     # special char '
        . $self->qualify( $r->{name} )             # fqdn
        . ':' . $self->escape( $r->{address} )     # s
        . ':' . $r->{ttl}                          # ttl
        . ':' . $r->{timestamp}                    # timestamp
        . ':' . $r->{location}                     # lo
        . "\n";
}

sub zr_ns {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

    #warn Data::Dumper::Dumper($r);

    return '&'                                     # special char
        . $self->qualify( $r->{name} )             # fqdn
        . ':'                                      # ip
        . ':' . $self->qualify( $r->{address} )    # x (hostname)
        . ':' . $r->{ttl}                          # ttl
        . ':' . $r->{timestamp}                    # timestamp
        . ':' . $r->{location}                     # lo
        . "\n";
}

sub zr_ptr {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

    #warn Data::Dumper::Dumper($r);

    return '^'                                     # special char
        . $self->qualify( $r->{name} )             # fqdn
        . ':' . $r->{address}                      # p
        . ':' . $r->{ttl}                          # ttl
        . ':' . $r->{timestamp}                    # timestamp
        . ':' . $r->{location}                     # lo
        . "\n";
}

sub zr_soa {
    my $self = shift;
    my %p = validate( @_, { zone => { type => HASHREF } } );

    my $z = $p{zone};

    return 'Z' . "$z->{zone}"     # fqdn
        . ":$z->{nsname}"         # mname
        . ":$z->{mailaddr}"       # rname
        . ":$z->{serial}"         # serial
        . ":$z->{refresh}"        # refresh
        . ":$z->{retry}"          # retry
        . ":$z->{expire}"         # expire
        . ":$z->{minimum}"        # min
        . ":$z->{ttl}"            # ttl
        . ":$z->{timestamp}"      # timestamp
        . ":$z->{location}"       # location
        . "\n";
}

sub zr_spf {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

    #warn Data::Dumper::Dumper($r);

    return ":"                                    # special char
        . $self->qualify( $r->{name} )            # fqdn
        . '99'                                    # n
        . ':' . $self->escape( $r->{address} )    # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
}

sub zr_srv {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

    #warn Data::Dumper::Dumper($r);

    # :fqdn:n:rdata:ttl:timestamp:lo (Generic record)
    my $priority = escapeNumber( $self->{nte}->is_ip_port( $r->{priority} ) );
    my $weight   = escapeNumber( $self->{nte}->is_ip_port( $r->{weight} ) );
    my $port     = escapeNumber( $self->{nte}->is_ip_port( $r->{other} ) );

# SRV
# :sip.tcp.example.com:33:\000\001\000\002\023\304\003pbx\007example\003com\000

    my $target = "";
    my @chunks = split /\./, $self->qualify( $r->{address} );
    foreach my $chunk (@chunks) {
        $target .= characterCount($chunk) . $chunk;
    }

    return ':'                                      # special char (generic)
        . escape( $self->qualify( $r->{name} ) )    # fqdn
        . ':33'                                     # n
        . ':' . $priority . $weight . $port . $target . "\\000"    # rdata
        . ':' . $r->{ttl}                                          # ttl
        . ':' . $r->{timestamp}                                    # timestamp
        . ':' . $r->{location}                                     # lo
        . "\n";
}

sub zr_aaaa {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

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

    return ':'                            # generic record format
        . $self->qualify( $r->{name} )    # fqdn
        . ':28'                           # n
        . ':' . "$a$b$c$d$e$f$g$h"        # rdata
        . ':' . $r->{ttl}                 # ttl
        . ':' . $r->{timestamp}           # timestamp
        . ':' . $r->{location}            # location
        . "\n";
}

sub qualify {
    my ( $self, $record, $zone ) = @_;
    return $record if $record =~ /\.$/;    # record already ends in .
    $zone ||= $self->{nte}{zone_name} or return $record;
    return $record if $record =~ /$zone$/;    # ends in zone, just no .
    return "$record.$zone"                    # append missing zone name
}

sub format_timestamp {
    my ($self, $ts) = @_;
    return '' if ! $ts;
    #warn "timestamp: $ts\n";
    return substr unixtai64( $ts ), 1;
};

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
}

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

__END__


