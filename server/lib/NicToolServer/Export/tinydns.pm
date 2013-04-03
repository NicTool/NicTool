package NicToolServer::Export::tinydns;
# ABSTRACT: export NicTool DNS data to tinydns (part of djbdns)

use strict;
use warnings;

use lib 'lib';
use base 'NicToolServer::Export::Base';

use Cwd;
use File::Copy;
use MIME::Base64;
use Params::Validate qw/ :all /;
use Time::TAI64 qw/ unixtai64 /;

# maybe TODO: append DB ids (but why?)

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

    $self->{nte}->set_copied(1);  # we intend to copy...
    $self->compile_cdb or return; # compile data to data.cdb
    $self->rsync_cdb or return;   # rsync file into place

    return 1;
}

sub compile_cdb {
    my $self = shift;

    # compile data -> data.cdb
    my $export_dir = $self->{nte}{export_dir};
    $self->write_makefile() if ! -e "$export_dir/Makefile";

    chdir $export_dir;
    my $before = time;
    $self->{nte}->set_status("compiling cdb");
    print "\n";
    system ('make data.cdb') == 0 or do {
        $self->{nte}->set_status("last: FAILED compiling cdb: $?");
        $self->{nte}->elog("unable to compile cdb: $?");
        return;
    };
    my $elapsed = time - $before;
    my $message = "compiled";
    $message .= " ($elapsed secs)" if $elapsed > 5;
    $self->{nte}->elog($message);
    return 1;
};

sub append_makefile {
    my $self = shift;
    my $export_dir = $self->{nte}{export_dir};
    my $address = $self->{nte}{ns_ref}{address} || '127.0.0.1';
    my $datadir = $self->{nte}{ns_ref}{datadir} || getcwd . '/data-all';
    $datadir =~ s/\/$//;  # strip off any trailing /
    open my $M, '>>', "$export_dir/Makefile";
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

sub write_makefile {
    my $self = shift;
    my $export_dir = $self->{nte}{export_dir};
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

sub rsync_cdb {
    my $self = shift;

    my $dir = $self->{nte}{export_dir};

    return 1 if ! defined $self->{nte}{ns_ref}{address};  # no rsync

    if ( -e "$dir/Makefile" && ! `grep remote $dir/Makefile` ) {
        $self->append_makefile();
    };

    $self->{nte}->set_status("remote rsync");
    my $before = time;
    print "\n";
    system ('make remote') == 0 or do {
        $self->{nte}->set_status("last: FAILED rsync: $?");
        $self->{nte}->elog("unable to rsync cdb: $?");
        return;
    };
    my $elapsed = time - $before;
    my $message = "copied";
    $message .= " ($elapsed secs)" if $elapsed > 5;
    $self->{nte}->elog($message);
    return 1;
};

sub export_db {
    my $self = shift;

    my $fh = $self->get_export_file() or return;

# the while loop fetches a row at at time. Grabbing them all in one pass is
# no faster. It takes 3 seconds to fetch 150,000 zones either way. The while
# loop uses 150MB less RAM.
    my @sql = $self->{nte}->get_ns_zones(query_result=>1);
    my $result = $self->{nte}{dbix_r}->query( @sql );
    $self->{nte}->elog( $result->rows . " zones" );
    while ( my $z = $result->hash ) {

        $self->{nte}{zone_name} = $z->{zone};
# print SOA & NS records
        print $fh $self->{nte}->zr_soa( $z );
        print $fh $self->{nte}->zr_ns( $z );
    }
    $result->finish;

# print all the rest
    @sql = $self->{nte}->get_ns_records(query_result=>1);
    $result = $self->{nte}{dbix_r}->query( @sql )
        or die $self->{nte}{dbix_r}->error;
    $self->{nte}->elog( $result->rows . " records" );
    while ( my $r = $result->hash ) {
        $self->{nte}{zone_name} = $r->{zone_name};
        $r->{location}  ||= '';
        $r->{timestamp} = $self->format_timestamp($r->{timestamp});
        my $method = 'zr_' . lc $r->{type};
        eval { print $fh $self->$method( $r ); };
        $self->{nte}->elog( $@ ) if $@;
    };
    $result->finish;

    close $fh;
};

sub zr_a {
    my $self = shift;
    my $r = shift or die;

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
    my $r = shift or die;

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
    my $r = shift or die;

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
    my $r = shift or die;

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
    my $r = shift or die;

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
    my $r = shift or die;

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
    my $z = shift or die;

# using sprintf versus concatenation takes the same amount of time.
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
    my $r = shift or die;

# assistance from djbdnsRecordBuilder
    return ':'                                    # special char (none = generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':99'                                   # n
        . ':' . $self->characterCount($r->{address})
              . $self->escape( $r->{address} )    # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
}

sub zr_srv {
    my $self = shift;
    my $r = shift or die;

    # :fqdn:n:rdata:ttl:timestamp:lo (Generic record)
    my $priority = escapeNumber( $self->{nte}->is_ip_port( $r->{priority} ) );
    my $weight   = escapeNumber( $self->{nte}->is_ip_port( $r->{weight} ) );
    my $port     = escapeNumber( $self->{nte}->is_ip_port( $r->{other} ) );

# SRV - from djbdnsRecordBuilder
# :sip.tcp.example.com:33:\000\001\000\002\023\304\003pbx\007example\003com\000

    my $target = "";
    my @chunks = split /\./, $self->qualify( $r->{address} );
    foreach my $chunk (@chunks) {
        $target .= characterCount($chunk) . $chunk;
    }

    return ':'                                      # special char (generic)
        . escape( $self->qualify( $r->{name} ) )    # fqdn
        . ':33'                                     # n
        . ':' . $priority . $weight . $port . $target . '\000'     # rdata
        . ':' . $r->{ttl}                                          # ttl
        . ':' . $r->{timestamp}                                    # timestamp
        . ':' . $r->{location}                                     # lo
        . "\n";
}

sub zr_aaaa {
    my $self = shift;
    my $r = shift or die;

# ffff:1234:5678:9abc:def0:1234:0:0
# :example.com:28:\377\377\022\064\126\170\232\274\336\360\022\064\000\000\000\000

# next 2 lines from djbdnsRecordBuilder, restores any compressed colons
    my $colons = $r->{address} =~ tr/:/:/;  # count the colons
    if ($colons < 7) { $r->{address} =~ s/::/':' x (9-$colons)/e; }

    # convert from AAAA compressed notation (8 groups of 4 hex digits) to
    # 16 escaped octals
    my $oct_ip = sprintf '\%03lo' x 16,   # output as escaped octal
            map { hex $_             }    # convert hex to binary
            map { unpack '(a2)*', $_ }    # split into 2 hex digit chunks
            map { sprintf '%04s', $_ }    # restore compressed leading zero(s)
            split /:/, $r->{address};     # split into hex groups

    return ':'                            # generic record format
        . $self->qualify( $r->{name} )    # fqdn
        . ':28'                           # n
        . ':' . $oct_ip                   # rdata
        . ':' . $r->{ttl}                 # ttl
        . ':' . $r->{timestamp}           # timestamp
        . ':' . $r->{location}            # location
        . "\n";
}

sub zr_loc {
    my $self = shift;
    my $r = shift or die;
    my $string = $r->{address};

    # lifted from Net::DNS::RR::LOC
    my ($alt, $size, $horiz_pre, $vert_pre, $latitude, $longitude, $altitude);
    if ($string &&
            $string =~ /^ (\d+) \s+     # deg lat
            (?:(\d+) \s+)?              # min lat
            (?:([\d.]+) \s+)?           # sec lat
            (N|S) \s+                   # hem lat
            (\d+) \s+                   # deg lon
            (?:(\d+) \s+)?              # min lon
            (?:([\d.]+) \s+)?           # sec lon
            (E|W) \s+                   # hem lon
            (-?[\d.]+) m?               # altitude
            (?:\s+ ([\d.]+) m?)?        # size
            (?:\s+ ([\d.]+) m?)?        # horiz precision
            (?:\s+ ([\d.]+) m?)?        # vert precision
            /ix) {

        my $version = 0;

        my ($latdeg, $latmin, $latsec, $lathem) = ($1, $2, $3, $4);
        my ($londeg, $lonmin, $lonsec, $lonhem) = ($5, $6, $7, $8);
           ($alt, $size, $horiz_pre, $vert_pre) = ($9, $10, $11, $12);

        $latmin    ||= 0;
        $latsec    ||= 0;
        $lathem    = uc($lathem);

        $lonmin    ||= 0;
        $lonsec    ||= 0;
        $lonhem    = uc($lonhem);

        $size      ||= 1;
        $horiz_pre ||= 10_000;
        $vert_pre  ||= 10;

        $size      = $size * 100;
        $horiz_pre = $horiz_pre * 100;
        $vert_pre  = $vert_pre * 100;
        $latitude  = dms2latlon($latdeg, $latmin, $latsec, $lathem);
        $longitude = dms2latlon($londeg, $lonmin, $lonsec, $lonhem);
        $altitude  = $alt * 100 + 100_000 * 100;
    }
    else {
        warn "Oops, invalid LOC data\n";
        return '';
    };

    my $rdata = pack('C4N3', 0,
                         precsize_valton($size),
                         precsize_valton($horiz_pre),
                         precsize_valton($vert_pre),
                         $latitude, $longitude, $altitude
                    );

    return ':'                                    # special char (none = generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':29'                                   # n
        . ':' . escape_rdata( $rdata )            # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
}

sub zr_naptr {
    my $self = shift;
    my $r = shift or die;

# from djbdnsRecordBuilder
# :example.com:35:\000\012\000\144\001u\007E2U+sip\036!^.*$!sip\072info@example.com.br!\000:300
#                 |-order-|-pref--|flag|-services-|---------------regexp---------------|re-|

    my ($flag, $services, $regexp, $replace) = split /__/, $r->{address};

    my $result = ':'                           # special char (none = generic)
        . $self->qualify( $r->{name} )         # fqdn
        . ":35:"                               # IANA RR ID
        . $self->escapeNumber( $r->{'weight'} ) # order
        . $self->escapeNumber( $r->{'priority'} )  # pref
        . $self->characterCount( $flag )     . $flag
        . $self->characterCount( $services ) . $self->escape( $services )
        . $self->characterCount( $regexp )   . $self->escape( $regexp );

    if ( $replace ne '' ) {
        $result .= $self->characterCount( $replace ) . $self->escape( $replace );
    };

    $result .= "\\000:";
    $result .= ':' . $r->{ttl};                # ttl
    $result .= ':' . $r->{timestamp};          # timestamp
    $result .= ':' . $r->{location};           # lo

    return $result . "\n";
}

sub zr_sshfp {
    my $self = shift;
    my $r = shift or die;

# http://www.openssh.org/txt/rfc4255.txt
# http://tools.ietf.org/html/draft-os-ietf-sshfp-ecdsa-sha2-00

    my $algo = $r->{weight};    #  1 octet - 1=RSA, 2=DSS, 3=ECDSA
    my $type = $r->{priority};  #  1 octet - 1=SHA-1, 2=SHA-256
    my $fingerprint = $r->{address};  # in hex

    my $rdata = sprintf '\%03lo' x 2, $algo, $type;
    foreach ( unpack "(a2)*", $fingerprint ) {
        $rdata .= sprintf '\%03lo', hex $_;
    };

    return ':'                                    # special char (generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':44'                                   # n
        . ':' . $rdata                            # rdata (algo.type.fp)
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
};

sub zr_dnskey {
    my $self = shift;
    my $r = shift or die;

    # DNSKEY: http://www.ietf.org/rfc/rfc4034.txt

    my $public_key = decode_base64( $r->{address} ) or do {
        $self->{nte}->elog("failed to base 64 decode $r->{name} DNSKEY in $r->{zone}");
        return '';
    };

    my $rdata = pack("nCCa*",
        $r->{weight},             # flags:     2 octets
        $r->{priority},           # protocol:  1 octet
        $r->{other},              # algorithm: 1 octet
        $public_key               # public key
        );

    return ':'                                    # special char (generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':48'                                   # n
        . ':' . escape_rdata( $rdata )            # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
};

sub zr_rrsig {
    my $self = shift;
    my $r = shift or die;

    # RRSIG: http://www.ietf.org/rfc/rfc4034.txt

# Type Covered   2 octet
# Algorithm      1 octet
# Labels         1 octet
# Original TTL   4 octet
# Signature Expiration  4 octet (32-bit ui) L
# Signature Inception   4 octet (32-bit ui) L
# Key Tag        2 octet  n
# Signer's Name
# Signature

    my $rdata = $r->{address};

    return ':'                                    # special char (generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':46'                                   # n
        . ':' . $rdata                            # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
};

sub zr_nsec {
    my $self = shift;
    my $r = shift or die;

    # NSEC: http://www.ietf.org/rfc/rfc4034.txt
# TTL should be same as zone SOA minimum: RFC 2308

    my $next = $r->{address};    # Next Domain Name
    my $tbm  = $r->{weight};     # Type Bit Maps
    # TBM: 256 window blocks, low order 8 bits of 16-bit RR type

    my $rdata;
    foreach my $label ( split /\./, $next ) {
    };

    return ':'                                    # special char (generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':47'                                   # n
        . ':' . $rdata                            # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
};

sub zr_nsec3 {
    my $self = shift;
    my $r = shift or die;

    # NSEC3: https://tools.ietf.org/html/rfc5155

    my $rdata = $r->{address};
    # Hash Algorithm   1 octet
    # Flags            1 octet
    # Iterations      16 bit ui,lf(n)
    # Salt Length      1 octet
    # Salt            binary octets, length varies -^ (0-N)
    # Hash Length      1 octet
    # Next Hashed Owner Name - unmodified binary hash value
    # Type Bit Maps

# TTL should be same as zone SOA minimum: RFC 2308

    return ':'                                    # special char (generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':50'                                   # n
        . ':' . $rdata                            # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
};

sub zr_nsec3param {
    my $self = shift;
    my $r = shift or die;

    # NSEC3: https://tools.ietf.org/html/rfc5155

    my $rdata = $r->{address};
    # Hash Algorithm   1 octet
    # Flag Fields      1 octet
    # Iterations      16 bit ui,lf(n)
    # Salt Length      1 octet
    # Salt            N binary octets (0-N)

# TTL should be same as zone SOA minimum: RFC 2308

    return ':'                                    # special char (generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':51'                                   # n
        . ':' . $rdata                            # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
};

sub zr_ds {
    my $self = shift;
    my $r = shift or die;

    # DS: http://www.ietf.org/rfc/rfc4034.txt
    my $rdata = escape_rdata( pack("nCC",
        $r->{weight},             # Key Tag,     2 octets
        $r->{priority},           # Algorithm,   1 octet
        $r->{other},              # Digest Type, 1 octet (1=SHA-1, 2=SHA-256)
    ) );
    my $digest = $r->{address};   # Digest, in hex
    $digest =~ s/\s+//g;          # remove spaces

    # Digest is 20 octets for SHA-1, 32 for SHA-256
    foreach ( unpack "(a2)*", $digest ) {     # nibble off 2 hex chars
        $rdata .= sprintf '\%03lo', hex $_;   # from hex to escaped octal
    };

    return ':'                                    # special char (generic)
        . $self->qualify( $r->{name} )            # fqdn
        . ':43'                                   # n
        . ':' . $rdata                            # rdata
        . ':' . $r->{ttl}                         # ttl
        . ':' . $r->{timestamp}                   # timestamp
        . ':' . $r->{location}                    # lo
        . "\n";
};

sub qualify {
    my $self = shift;
    my $record = shift;
    return $record if substr($record,-1,1) eq '.';  # record ends in .
    my $zone = shift || $self->{nte}{zone_name} or return $record;

# substr is measurably faster than the regexp
    #return $record if $record =~ /$zone$/;   # ends in zone, just no .
    return $record if $zone eq substr($record,(-1*length($zone)),length($zone));

    return "$record.$zone"       # append missing zone name
}

sub format_timestamp {
    my ($self, $ts) = @_;
    return '' if ! $ts;
    return substr unixtai64( $ts ), 1;
};

sub escape_rdata {
    my $line = pop @_;
    my $out;
    foreach ( split //, $line ) {
        if ( $_ =~ /[^A-Za-z0-9]/ ) {
            $out .= sprintf '\%03lo', ord $_;
        }
        else {
            $out .= $_;
        }
    }
    return $out;
}

# next 3 subs based on http://www.anders.com/projects/sysadmin/djbdnsRecordBuilder/
sub escape {
    my $line = pop @_;
    my $out;
    foreach ( split //, $line ) {
        $out .= $_ =~ /[^\r\n\t:\\\/]/ ? $_ : sprintf '\%03lo', ord $_;
    }
    return $out;
};

sub escapeNumber {
    my $number     = pop @_;
    my $highNumber = 0;

    if ( $number - 256 >= 0 ) {
        $highNumber = int( $number / 256 );
        $number = $number - ( $highNumber * 256 );
    }
    return sprintf '\%03lo' x 2, $highNumber, $number;
}

sub characterCount {
    return sprintf '\%03lo', scalar split //, pop @_;
}

# next 2 subs lifted from Net::DNS::RR::LOC
sub dms2latlon {
    my ($deg, $min, $sec, $hem) = @_;
    my $retval;

    my $conv_sec = 1000;
    my $conv_min = 60 * $conv_sec;
    my $conv_deg = 60 * $conv_min;

    $retval = ($deg * $conv_deg) + ($min * $conv_min) + ($sec * $conv_sec);
    $retval = -$retval if ($hem eq "S") || ($hem eq "W");
    $retval += 2**31;
    return $retval;
}

sub precsize_valton {
    my $val = shift;
    my $exponent = 0;
    while ($val >= 10) { $val /= 10; ++$exponent; }
    return (int($val) << 4) | ($exponent & 0x0f);
}

# tinydns-data format: http://cr.yp.to/djbdns/tinydns-data.html
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
#
# 'You may use octal \nnn codes to include arbitrary bytes inside rdata'
1;

__END__

=head1 Instructions for Use

https://github.com/msimerson/NicTool/wiki/Export-to-tinydns

=cut

