package NicToolServer::Export::tinydns;
# ABSTRACT: export NicTool DNS data to tinydns (part of djbdns)

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::Base';

use Cwd;
use File::Copy;
use MIME::Base32;
use MIME::Base64;
use Net::IP;
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

    $self->compile_cdb or return; # compile data to data.cdb
    $self->rsync_cdb or return;   # rsync file into place

    return 1;
}

sub compile_cdb {
    my $self = shift;

    # compile data -> data.cdb
    my $export_dir = $self->{nte}{export_dir};
    $self->write_makefile();

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
    my $remote_login = $self->{nte}{ns_ref}{remote_login} || 'tinydns';
    $datadir =~ s/\/$//;  # strip off any trailing /
    open my $M, '>>', "$export_dir/Makefile";
    print $M <<MAKE
# copies the data file to the remote host. The address is the nameservers IP
# as defined in the NicTool database. Adjust it if necessary. Add additional
# rsync lines to copy to additional hosts.
remote: data.cdb
\trsync -az data.cdb $remote_login\@$address:$datadir/data.cdb
MAKE
;
    close $M;
};

sub write_makefile {
    my $self = shift;
    my $export_dir = $self->{nte}{export_dir};
    return 1 if -e "$export_dir/Makefile";     # already exists
    my $address = $self->{nte}{ns_ref}{address} || '127.0.0.1';
    my $datadir = $self->{nte}{ns_ref}{datadir} || getcwd . '/data-all';
    my $remote_login = $self->{nte}{ns_ref}{remote_login} || 'tinydns';
    $datadir =~ s/\/$//;  # strip off any trailing /
    open my $M, '>', "$export_dir/Makefile";
    print $M <<MAKE
# See https://www.gnu.org/software/make/manual/make.html
#
# compiles data.cdb using the tinydns-data program.
# make sure the path to tinydns-data is correct
# test this target by running 'make data.cdb' in this directory
data.cdb: data
\t/usr/local/bin/tinydns-data

# copies the data file to the remote host. The address is the nameservers IP
# as defined in the NicTool database. Adjust it if necessary. Add additional
# rsync lines to copy to additional hosts. See the FAQ for details:
#    FAQ: https://github.com/msimerson/NicTool/wiki/FAQ
remote: data.cdb
\trsync -az data.cdb $remote_login\@$address:$datadir/data.cdb

# If the DNS server is running locally and rsync is not necessary, tell the
# export process the 'remote' make target succeeded. An example is provided.
# test by running the 'make remote' target and make sure it succeeds:
#
#  example useless entry
test:\n\techo "it worked"
MAKE
;
    close $M;
    return 1;
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
    $self->{nte}->set_copied(1);  # we copied
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
        my @args = $r;
        my $method = 'zr_' . lc $r->{type};
        if ('TYPE' eq substr(uc $r->{type}, 0, 4)) { # RFC 3597, Unknown type
            $method = 'zr_generic';
            @args = (substr($r->{type}, 4), $r, $self->octal_escape($r->{address}));
        }
        eval { print $fh $self->$method( @args ); };
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

    # 'You may use octal \nnn codes to include arbitrary bytes inside rdata'

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

    my $rdata = octal_escape( pack "nnn",
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

    # from AAAA notation (8 groups of 4 hex digits) to 16 escaped octals
    my $rdata = $self->pack_hex( join '', split /:/, $aaaa );

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

    my $rdata = octal_escape( pack 'C4N3', 0,
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

    # https://www.ietf.org/rfc/rfc3403.txt
# from djbdnsRecordBuilder
# :example.com:35:\000\012\000\144\001u\007E2U+sip\036!^.*$!sip\072info@example.com.br!\000:300
#                 |-order-|-pref--|flag|-services-|---------------regexp---------------|re-|

    my ($flag, $services, $regexp, $replace) = split /__/, $r->{address};

    my $rdata = $self->escapeNumber( $r->{'weight'} )    # order, 16-bit
           . $self->escapeNumber( $r->{'priority'} )     # pref,  16-bit
           . $self->characterCount( $flag )     . $flag  # Flags
           . $self->characterCount( $services ) . $self->escape( $services )
           . $self->characterCount( $regexp )   . $self->escape( $regexp );

    if ( $replace ne '' ) {
        $rdata .= $self->characterCount( $replace ) . $self->escape( $replace );
    };
    $rdata .= '\000';

    return $self->zr_generic( 35, $r, $rdata );
}

sub zr_dname {
    my $self = shift;
    my $r = shift or die;

    # https://tools.ietf.org/html/rfc6672
    # https://tools.ietf.org/html/rfc2672 (obsolete)
    my $rdata = $self->pack_domain_name( $self->qualify( $r->{address} ) );

    return $self->zr_generic( 39, $r, $rdata );
};

sub zr_sshfp {
    my $self = shift;
    my $r = shift or die;

# http://www.openssh.org/txt/rfc4255.txt
# http://tools.ietf.org/html/draft-os-ietf-sshfp-ecdsa-sha2-00

    my $algo = $r->{weight};    #  1 octet - 1=RSA, 2=DSA, 3=ECDSA
    my $type = $r->{priority};  #  1 octet - 1=SHA-1, 2=SHA-256
    my $fingerprint = $r->{address};  # in hex

    my $rdata = sprintf '\%03lo' x 2, $algo, $type;
    $rdata .= $self->pack_hex( $fingerprint );

    return $self->zr_generic( 44, $r, $rdata );
};

sub zr_ipseckey {
    my $self = shift;
    my $r = shift or die;

    # http://www.faqs.org/rfcs/rfc4025.html
# IN IPSECKEY ( precedence gateway-type algorithm gateway base64-public-key )

    my $rdata = $self->octal_escape( pack('CCC',
        $r->{weight},         # Precedence     1 octet
        $r->{priority},       # Gateway Type   1 octet, see Gateway
        $r->{other},          # Algorithm Type 1 octet, 0=none, 1-DSA, 2=RSA
    ));

    my $gw_type = $r->{priority};
    my $gateway = $r->{address};            # Gateway

    if ( $gw_type == 0 ) {
        $rdata .= sprintf('%03lo', '.');    #  0 - no gateway
    }
    elsif ( $gw_type == 1 ) {               #  1 - 32-bit(N) IPv4 address
        my $ip_as_int = new Net::IP ($gateway)->intip or do {
            warn "$r->{name} IPSECKEY gateway not an IPv4 address!\n";
            return;
        };
        $rdata .= $self->octal_escape( $ip_as_int );
    }
    elsif ( $gw_type == 2 ) {               # 2 - 128-bit, net order, IPv6
        my $ip_as_hex = new Net::IP ($gateway)->hexip or do {
            warn "$r->{name} IPSECKEY gateway not an IPv6 address!\n";
            return;
        };
        $rdata .= $self->pack_hex( $ip_as_hex );
    }
    elsif ( $gw_type == 3 ) {              #  3 - a wire encoded domain name
        $rdata .= $self->pack_domain_name( $gateway );
    };

    # Public Key     optional, base 64 encoded
    if ( $r->{description} ) {
        $rdata .= $self->octal_escape( decode_base64( $r->{description} ) );
    };

    return $self->zr_generic( 45, $r, $rdata );
};

sub zr_dnskey {
    my $self = shift;
    my $r = shift or die;

    # DNSKEY: http://www.ietf.org/rfc/rfc4034.txt

    my $public_key = decode_base64( $r->{address} ) or do {
        $self->{nte}->elog("failed to base 64 decode $r->{name} DNSKEY in $r->{zone}");
        return '';
    };

    my $rdata = octal_escape( pack "nCCa*",
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

    my $rdata = octal_escape( pack("nCCNNNn",
        $type,                              # Type Covered   2 octet
        $algorithm,                         # Algorithm      1 octet
        $label_count,                       # Labels         1 octet
        $orig_ttl,                          # Original TTL   4 octet
        $sig_exp,                           # Signature Expiration  4 octet
        $sig_inc,                           # Signature Inception   4 octet
        $key_tag,                           # Key Tag        2 octet
    ) );

    $rdata .= $self->pack_domain_name( $signers_name ); # Signer's Name
    $rdata .= octal_escape( pack "a*", $signature );    # Signature

    return $self->zr_generic( 46, $r, $rdata );
};

sub zr_nsec {
    my $self = shift;
    my $r = shift or die;

    # NSEC: http://www.ietf.org/rfc/rfc4034.txt

    my $rdata = $self->pack_domain_name( $r->{address} ); # Next Domain Name
    $rdata .= $self->pack_type_bitmap( $r->{description} );

    return $self->zr_generic( 47, $r, $rdata );
};

sub zr_nsec3 {
    my $self = shift;
    my $r = shift or die;

    # NSEC3: https://tools.ietf.org/html/rfc5155
# TTL should be same as zone SOA minimum: RFC 2308

# IN NSEC3 1 1 12 aabbccdd ( 2t7b4g4vsa5smi47k61mv5bv1a22bojr MX DNSKEY NS SOA NSEC3PARAM RRSIG )
    my @data = split /\s+/, $r->{address};
    @data = grep { $_ ne '(' && $_ ne ')' } @data; # make parens optional
    if ( '(' eq substr( $data[0], 0, 1) ) { $data[0] = substr $data[0], 1; };
    if ( ')' eq substr( $data[-1], -1, 1) ) { chop $data[-1]; };

    my ($hash_algo, $flags, $iters, $salt, $next_hash, @types ) = @data;

    my $rdata = $self->pack_nsec3_params( $hash_algo, $flags, $iters, $salt );
    $next_hash = $self->base32str_to_bin( $next_hash );

    $rdata .= octal_escape( pack 'Ca*',
        length( $next_hash),  # Hash Length      1 octet
        $next_hash            # Next Hashed Owner Name - unmodified binary hash value
    );

    my $bitmap_list = scalar @types ? join(' ', @types) : $r->{description};
    $rdata .= $self->pack_type_bitmap( $bitmap_list ); # Type Bit Maps

    return $self->zr_generic( 50, $r, $rdata );
};

sub zr_nsec3param {
    my $self = shift;
    my $r = shift or die;

    # NSEC3PARAM: https://tools.ietf.org/html/rfc5155
    my ($hash_algo, $flags, $iters, $salt) = split /\s+/, $r->{address};

#  RDATA mirrors the first four fields in the NSEC3
    my $rdata = $self->pack_nsec3_params( $hash_algo, $flags, $iters, $salt );

    return $self->zr_generic( 51, $r, $rdata );
};

sub zr_ds {
    my $self = shift;
    my $r = shift or die;

    # DS: http://www.ietf.org/rfc/rfc4034.txt
    my $rdata = octal_escape( pack("nCC",
        $r->{weight},             # Key Tag,     2 octets
        $r->{priority},           # Algorithm,   1 octet
        $r->{other},              # Digest Type, 1 octet (1=SHA-1, 2=SHA-256)
    ) );
    my $digest = $r->{address};   # Digest, in hex
    $digest =~ s/\s+//g;          # remove spaces

    # Digest is 20 octets for SHA-1, 32 for SHA-256
    $rdata .= $self->pack_hex( $digest );

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

    # In an RRSIG, serial arrives in YYYYMMDDHHmmSS UTC format (14 digits):
    # see RFC 4034, 3.2
    return timegm(
        substr($ds, 12, 2),       # seconds
        substr($ds, 10, 2),       # minutes
        substr($ds,  8, 2),       # hour
        substr($ds,  6, 2),       # day
        substr($ds,  4, 2) -1,    # month
        substr($ds,  0, 4)        # year
    );
};

sub octal_escape {
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

    # RFC 1035, 3.3 Standard RRs
    # The standard wire format for DNS names. (1 octet length + octets)
    my $r;
    foreach my $label ( split /\./, $self->qualify( $name ) ) {
        $r .= octal_escape( pack( 'C a*', length( $label ), $label ) );
    };
    $r.= '\000';   # terminating with a zero length label
    return $r;
};

sub pack_hex {
    my ($self, $string) = @_;

    my $r;
    foreach ( unpack "(a2)*", $string ) {  # nibble off 2 hex digits
        $r .= sprintf '\%03lo', hex $_;    # pack 'em into an escaped octal
    };
    return $r;
};

sub pack_nsec3_params {
    my ($self, $hash_algo, $flags, $iters, $salt ) = @_;

    if   ( $salt eq '-' ) { $salt = ''; }
    else                  { $salt = pack 'H*', $salt };  # to binary

    return octal_escape( pack 'CCnCa*',
        $hash_algo,           # Hash Algorithm   1 octet
        $flags,               # Flags            1 octet
        $iters,               # Iterations      16 bit ui,lf(n)
        length( $salt ),      # Salt Length      1 octet
        $salt,                # Salt             binary octets
    );
};

sub pack_type_bitmap {
    my ( $self, $rr_type_list ) = @_;

    # Type Bit Maps Field = ( Window Block # | Bitmap Length | Bitmap )+
    # Described in RFC 4034, used in NSEC and NSEC3 records

    # build RR id lookup table from list of RR types
    my %rec_ids;
    foreach my $label ( split /\s+/, $rr_type_list ) {
        $label =~ s/[\(\)]//g;  # remove ( and )
        $rec_ids{ $self->{nte}->get_rr_id( $label ) } = $label;
    };

    my ($highest_rr_id) = (sort { $a <=> $b} keys %rec_ids)[-1]; # find highest ID

    my $highest_window = int( $highest_rr_id / 256 );  # how many windows needed?
       $highest_window += ( $highest_rr_id % 256 == 0 ? 0 : 1 );

    my $bitmap;
    foreach my $window ( 0 .. $highest_window ) {
        my $base = $window * 256;
        next unless grep { $_ >= $base && $_ < $base + 256 } keys %rec_ids;

        my $highest_in_this_window = $highest_rr_id - $base;

        my $bm_octets = int( $highest_in_this_window / 8 );
           $bm_octets += $highest_in_this_window % 8 == 0 ? 0 : 1;

        $bitmap .= sprintf('\%03lo' x 2, $window, $bm_octets);

        foreach my $octet ( 0 .. $bm_octets - 1 ) {
            my $start = $octet * 8;
            my $bitstring = join '',
                map { defined $rec_ids{ $_ } ? 1 : 0 }
                $start .. $start+7;
            $bitmap .= sprintf '\%03lo', oct('0b'.$bitstring);
        };
    };
    return $bitmap;
};

sub qualify {
    my ($self, $record, $zone) = @_;
    return $record if substr($record,-1,1) eq '.';  # record ends in .
    $zone ||= $self->{nte}{zone_name} or return $record;

# substr is measurably faster than a regexp
    my $chars = length $zone;
    if ($zone eq substr($record,(-1*$chars),$chars)) {
        return $record;     # ends in $zone, no trailing .
    };

    return "$record.$zone"       # append missing zone name
}

sub to_tai64 {
    my ($self, $ts) = @_;
    return '' if ! $ts;
    return substr unixtai64( $ts ), 1;
};

sub base32str_to_bin {
    my ($self, $str) = @_;

    # RFC 5155 (NSEC3) suggests using Base32 with Extended Hex Alphabet as
    # described in RFC 4648).

    # Convert::Base32 implements Base32 per RACE 03 (ie, differently). First
    # clue? It dies on the NSEC3 RFC example with "non-Base32 characters"
    #return Convert::Base32::decode_base32( $str );

    # MIME::Base32 in 'RFC' mode implements RFC 3548, which is RFC 4648 minus
    # the 'base32 extended hex alphabet'. It won't suffice.

    # The MB fallback method is encode_09AV, which will work if we uc the
    # string first.
    return MIME::Base32::decode_base32hex( uc $str );
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
    return sprintf '\%03lo', length $_[-1];
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

1;

__END__

=head1 Instructions for Use

https://github.com/msimerson/NicTool/wiki/Export-to-tinydns

=head1 AUTHOR

Matt Simerson

=cut

