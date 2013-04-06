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
use Time::Local;
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
        $r->{timestamp} = $self->to_tai64($r->{timestamp});
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
    return 'Z'. $z->{zone}           # fqdn
        . ':' . $z->{nsname}         # mname
        . ':' . $z->{mailaddr}       # rname
        . ':' . $z->{serial}         # serial
        . ':' . $z->{refresh}        # refresh
        . ':' . $z->{retry}          # retry
        . ':' . $z->{expire}         # expire
        . ':' . $z->{minimum}        # min
        . ':' . $z->{ttl}            # ttl
        . ':' . $z->{timestamp}      # timestamp
        . ':' . $z->{location}       # location
        . "\n";
}

sub zr_generic {
    my ($self, $rrid, $r, $rdata) = @_;
    return ':'                             # special char (none = generic)
        . $self->qualify( $r->{name} )     # fqdn
        . ':' . $rrid                      # n
        . ':' . $rdata                     # rdata
        . ':' . $r->{ttl}                  # ttl
        . ':' . $r->{timestamp}            # timestamp
        . ':' . $r->{location}             # lo
        . "\n";
};

sub zr_spf {
    my $self = shift;
    my $r = shift or die;

# assistance from djbdnsRecordBuilder
    my $rdata = $self->characterCount( $r->{address} )
              . $self->escape( $r->{address} );

    return $self->zr_generic( 99, $r, $rdata );
}

sub zr_srv {
    my $self = shift;
    my $r = shift or die;

    # SRV - https://www.ietf.org/rfc/rfc2782.txt
    # format of SRV record derived from djbdnsRecordBuilder

    my $rdata = escape_rdata( pack "nnn",
        $self->{nte}->is_ip_port( $r->{priority} ),   # Priority, 16 bit (n)
        $self->{nte}->is_ip_port( $r->{weight} ),     # Weight,   16 bit (n)
        $self->{nte}->is_ip_port( $r->{other} ),      # Port,     16 bit (n)
    );

    $rdata .= $self->pack_domain_name( $r->{address} ); # Target, domain name

    return $self->zr_generic( 33, $r, $rdata );
}

sub zr_aaaa {
    my $self = shift;
    my $r = shift or die;

    my $aaaa = $self->expand_aaaa( $r->{address} );

    # convert from AAAA (possibly compressed) notation (8 groups of 4 hex
    # digits) to 16 escaped octals
    my $rdata = sprintf '\%03lo' x 16,    # output num as escaped octal
            map { hex $_             }    # convert hex string to number
            map { unpack '(a2)*', $_ }    # split each quad into 2 hex digits
            split /:/, $aaaa;             # split hex quads

    $self->aaaa_to_ptr( $aaaa ) if 1 == 0; # TODO: add option to enable

    return $self->zr_generic( 28, $r, $rdata );
};

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

    my $rdata = escape_rdata( pack 'C4N3', 0,
                         precsize_valton($size),
                         precsize_valton($horiz_pre),
                         precsize_valton($vert_pre),
                         $latitude, $longitude, $altitude
                    );

    return $self->zr_generic( 29, $r, $rdata );
}

sub zr_naptr {
    my $self = shift;
    my $r = shift or die;

# from djbdnsRecordBuilder
# :example.com:35:\000\012\000\144\001u\007E2U+sip\036!^.*$!sip\072info@example.com.br!\000:300
#                 |-order-|-pref--|flag|-services-|---------------regexp---------------|re-|

    my ($flag, $services, $regexp, $replace) = split /__/, $r->{address};

    my $rdata = $self->escapeNumber( $r->{'weight'} )    # order
              . $self->escapeNumber( $r->{'priority'} )  # pref
              . $self->characterCount( $flag )     . $flag
              . $self->characterCount( $services ) . $self->escape( $services )
              . $self->characterCount( $regexp )   . $self->escape( $regexp );

    if ( $replace ne '' ) {
        $rdata .= $self->characterCount( $replace ) . $self->escape( $replace );
    };
    $rdata .= '\000:';

    return $self->zr_generic( 35, $r, $rdata );
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

    return $self->zr_generic( 44, $r, $rdata );
};

sub zr_dnskey {
    my $self = shift;
    my $r = shift or die;

    # DNSKEY: http://www.ietf.org/rfc/rfc4034.txt

    my $public_key = decode_base64( $r->{address} ) or do {
        $self->{nte}->elog("failed to base 64 decode $r->{name} DNSKEY in $r->{zone}");
        return '';
    };

    my $rdata = escape_rdata( pack "nCCa*",
        $r->{weight},             # flags:     2 octets
        $r->{priority},           # protocol:  1 octet
        $r->{other},              # algorithm: 1 octet
        $public_key               # public key
        );

    return $self->zr_generic( 48, $r, $rdata );
};

sub zr_rrsig {
    my $self = shift;
    my $r = shift or die;

    # RRSIG: http://www.ietf.org/rfc/rfc4034.txt
    my ($type, $algorithm, $label_count, $orig_ttl, $sig_exp, undef, $sig_inc,
        $key_tag, $signers_name, $signature) = split /\s+/, $r->{address}, 10;

    $type = $self->{nte}->get_rr_id( $type ); # convert from RR name to ID

    $signature =~ s/\s+//g; chop $signature;  # remove spaces and trailing )
    $signature = decode_base64( $signature );

    $sig_exp = $self->datestamp_to_int( $sig_exp );
    $sig_inc = $self->datestamp_to_int( $sig_inc );

    my $rdata = escape_rdata( pack("nCCNNNn",
        $type,                              # Type Covered   2 octet
        $algorithm,                         # Algorithm      1 octet
        $label_count,                       # Labels         1 octet
        $orig_ttl,                          # Original TTL   4 octet
        $sig_exp,                           # Signature Expiration  4 octet
        $sig_inc,                           # Signature Inception   4 octet
        $key_tag,                           # Key Tag        2 octet
    ) );

    $rdata .= $self->pack_domain_name( $signers_name ); # Signer's Name
    $rdata .= escape_rdata( pack "a*", $signature );    # Signature

    return $self->zr_generic( 46, $r, $rdata );
};

sub zr_nsec {
    my $self = shift;
    my $r = shift or die;

    # NSEC: http://www.ietf.org/rfc/rfc4034.txt

    my $rdata = $self->pack_domain_name( $r->{address} ); # Next Domain Name

    # Type Bit Maps Field = ( Window Block # | Bitmap Length | Bitmap )+

    # build RR id lookup table from list of RR types
    my %rec_ids;
    foreach my $label ( split /\s+/, $r->{description} ) {
        $label =~ s/[\(\)]//g;  # remove ( and )
        $rec_ids{ $self->{nte}->get_rr_id( $label ) } = $label;
    };

    my ($highest_rr_id) = (sort keys %rec_ids)[-1];  # find the highest ID

    my $highest_window = int( $highest_rr_id / 256 );
       $highest_window += ( $highest_rr_id % 256 == 0 ? 0 : 1 );

    foreach my $window ( 0 .. $highest_window ) {
        my $base = $window * 256;
        next unless grep { $_ >= $base && $_ < $base + 256 } %rec_ids;
        my $highest_in_this_window = $highest_rr_id - $base;

        my $bm_octets = int( $highest_in_this_window / 8 );
           $bm_octets += $highest_in_this_window % 8 == 0 ? 0 : 1;

        $rdata .= sprintf('\%03lo' x 2, $window, $bm_octets);

        foreach my $octet ( 0 .. $bm_octets - 1 ) {
            my $start = $octet * 8;
            my $bitstring = join '',
                map { defined $rec_ids{ $_ } ? 1 : 0 }
                $start .. $start+7;
            $rdata .= sprintf '\%03lo', oct('0b'.$bitstring);
        };
    };

    return $self->zr_generic( 47, $r, $rdata );
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

    return $self->zr_generic( 50, $r, $rdata );
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

    return $self->zr_generic( 51, $r, $rdata );
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

    return $self->zr_generic( 43, $r, $rdata );
};

sub aaaa_to_ptr {
    my ( $self, $r ) = @_;
    my $aaaa = $self->expand_aaaa( $r->{address} );
    my @nibbles = reverse map { split //, $_ } split /:/, $aaaa;
    return $self->zr_ptr( {
            name       => join('.', @nibbles) . '.ip6.arpa.',
            address    => $r->{name},
            ttl        => $r->{ttl},
            timestamp  => $r->{timestamp},
            location   => $r->{location},
        });
};

sub datestamp_to_int {
    my ($self, $ds) = @_;

    # serial arrives in YYYYMMDDHHmmSS UTC format (14 digits): RFC 4034, 3.2
    return timegm(
        substr($ds, 12, 2),       # seconds
        substr($ds, 10, 2),       # minutes
        substr($ds,  8, 2),       # hour
        substr($ds,  6, 2),       # day
        substr($ds,  4, 2) -1,    # month
        substr($ds,  0, 4)        # year
    );
};

sub escape_rdata {
    my $line = pop @_;
    my $out;
    foreach ( split //, $line ) {
        if ( $_ =~ /[^A-Za-z0-9\-\.]/ ) {
            $out .= sprintf '\%03lo', ord $_;
        }
        else {
            $out .= $_;
        }
    }
    return $out;
}

sub expand_aaaa {
    my ( $self, $aaaa ) = @_;

# from djbdnsRecordBuilder, contributed by Matija Nalis
    my $colons = $aaaa =~ tr/:/:/;             # count the colons
    if ($colons < 7) {
        $aaaa =~ s/::/':' x (9-$colons)/e;     # restore compressed colons
    };

# restore any compressed leading zeros
    $aaaa = join ':', map { sprintf '%04s', $_ } split /:/, $aaaa;
    return $aaaa;
};

sub pack_domain_name {
    my ($self, $name) = @_;

    my $r;
    foreach my $label ( split /\./, $self->qualify( $name ) ) {
        $r .= escape_rdata( pack( 'CA*', length( $label ), $label ) );
    };
    $r.= '\000';   # end of field
    return $r;
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

sub to_tai64 {
    my ($self, $ts) = @_;
    return '' if ! $ts;
    return substr unixtai64( $ts ), 1;
};

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

