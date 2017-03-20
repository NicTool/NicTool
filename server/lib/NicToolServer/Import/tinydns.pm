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
use Time::HiRes;
use Time::TAI64 qw/ unixtai64 /;

sub get_import_file {
    my $self = shift;
    my $filename = shift || 'data';

    open my $FH, '<', $filename
        or die "failed to open '$filename'";

    return $self->{FH} = $FH;
};

sub import_records {
    my ($self, $file) = @_;
    $self->get_import_file( $file || 'data' ) or return;

    # tinydns-data format: http://cr.yp.to/djbdns/tinydns-data.html

    my $fh = $self->{FH};
    while ( defined ( my $record = <$fh> ) ) {
        next if $record =~ /^#/;     # comment
        next if $record =~ /^\s+$/;  # blank line
        next if $record =~ /^\-/;    # IGNORE: - fqdn : ip : ttl:timestamp:lo
        Time::HiRes::sleep 0.1;      # go slow enough a human can read

        my $first = substr($record, 0, 1);
        my $record = substr($record, 1 );
        chomp $record;

        my @err; # Collect errors from nt_create_{zone,record}

        if ( $first eq 'Z' ) {          #  SOA        =>  Z fqdn:mname:rname:ser:ref:ret:exp:min:ttl:time:lo
            push @err, $self->zr_soa($record);
        }
        elsif ( $first eq '.' ) {       #  'SOA,NS,A' =>  . fqdn : ip : x:ttl:timestamp:lo
            push @err, $self->zr_soa($record);
            push @err, $self->zr_ns($record);
            my ( $fqdn, $ip, $ttl, $timestamp, $location ) = split(':', $record);
            push @err, $self->zr_a($record) if $ip;
        }
        elsif ( $first eq '=' ) {       #  'A,PTR'    =>  = fqdn : ip : ttl:timestamp:lo
            push @err, $self->zr_a($record);
            my ($fqdn, $addr, $ttl, $ts, $loc) = split(':', $record);
            if ('*.' eq substr $fqdn, 0, 2) {  # a wildcard A record is not a valid PTR name
                $fqdn = substr $fqdn, 2;       # strip *. prefix
            }
            push @err, $self->zr_ptr(join(':', $self->ip_to_ptr($addr), $fqdn, $ttl || '', $ts || '', $loc || ''));
        }
        elsif ( $first eq '&' ) {       #  NS         =>  & fqdn : ip : x:ttl:timestamp:lo
            push @err, $self->zr_ns($record);
        }
        elsif ( $first eq '^' ) {       #  PTR        =>  ^ fqdn :  p : ttl:timestamp:lo
            push @err, $self->zr_ptr($record);
        }
        elsif ( $first eq '+' ) {       #  A          =>  + fqdn : ip : ttl:timestamp:lo
            push @err, $self->zr_a($record);
        }
        elsif ( $first eq 'C' ) {       #  CNAME      =>  C fqdn :  p : ttl:timestamp:lo
            push @err, $self->zr_cname($record);
        }
        elsif ( $first eq '@' ) {       #  MX         =>  @ fqdn : ip : x:dist:ttl:timestamp:lo
            push @err, $self->zr_mx($record);
        }
        elsif ( $first eq '\'' ) {      #  TXT        =>  ' fqdn :  s : ttl:timestamp:lo
            push @err, $self->zr_txt($record);
        }
        elsif ( $first eq ':' ) {       #  GENERIC    =>  : fqdn : n  : rdata:ttl:timestamp:lo
            push @err, $self->zr_generic($record);
        }
        elsif ( $first eq '3') {        #  AAAA       =>  3 fqdn : ip : x:ttl:timestamp:lo
            push @err, $self->zr_aaaa6($record);
        }
        elsif ( $first eq '6') {        # 'AAAA,PTR'  =>  6 fqdn : ip : x:ttl:timestamp:lo
            push @err, $self->zr_aaaa6($record);
            my ($fqdn, $addr, $ttl, $ts, $loc) = split(':', $record);
            if ('*.' eq substr $fqdn, 0, 2) {  # a wildcard AAAA record is not a valid PTR name
                $fqdn = substr $fqdn, 2;       # strip *. prefix
            }
            push @err, $self->zr_ptr(join(':', $self->ip6_to_ptr($addr),
                $fqdn, $ttl || '', $ts || '', $loc || ''));
        }
        else { # Emit a local error (not from nt_create_* on the server) if record type unknown
            $first = sprintf '\%03o', ord($first) # Escape unprintable ascii
                if $first =~ /^[\x00-\x20\x7F-\xFF]$/;
            push @err, {
                error_code => 501,
                error_desc => "Unknown TinyDNS record type '$first'",
                error_msg  => $record };
        };

        map { # Report any errors returned from nt_create_{zone,record}
            if (ref $_ && $_->{error_code} != 200) {
                printf "ERROR   : %s: %s ( %s )\n",
                    $_->{error_code}, $_->{error_desc}, $_->{error_msg};
            }
        } @err;

    };

    print "done\n";
    return 1;
};

sub zr_a {
    my $self = shift;
    my $r = shift or die;

    print "A       : $r\n";
    my ( $fqdn, $ip, $ttl, $timestamp, $location ) = split(':', $r);

    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'A',
        name    => $host,
        address => $ip,
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_cname {
    my $self = shift;
    my $r = shift or die;

    print "CNAME   : $r\n";
    my ( $fqdn, $addr, $ttl, $timestamp, $location ) = split(':', $r);

    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'CNAME',
        name    => $host,
        address => $self->fully_qualify( $addr ),
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_mx {
    my $self = shift;
    my $r = shift or die;

    print "MX      : $r\n";
    my ( $fqdn, $ip, $addr, $distance, $ttl, $timestamp, $location ) = split(':', $r);

    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'MX',
        name    => $host,
        address => $self->fully_qualify( $addr ),
        weight  => $distance || 0,
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_txt {
    my $self = shift;
    my $r = shift or die;

    print "TXT     : $r\n";
    my ( $fqdn, $addr, $ttl, $timestamp, $location ) = split(':', $r);

    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'TXT',
        name    => $host,
        address => $self->unescape_octal($addr),
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_ns {
    my $self = shift;
    my $r = shift or die;

    print "NS      : $r\n";
    my ( $fqdn, $ip, $addr, $ttl, $timestamp, $location ) = split(':', $r);

    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'NS',
        name    => $host,
        address => $self->fully_qualify( $addr ),
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_ptr {
    my $self = shift;
    my $r = shift or die;

    print "PTR     : $r\n";
    my ( $fqdn, $addr, $ttl, $timestamp, $location ) = split(':', $r);
    my ($zone_id, $host);
    eval { ($zone_id, $host) = $self->get_zone_id( $fqdn ) };

    if (!$zone_id) {
        my @bits = split /\./, $fqdn;
        shift @bits;
        $self->nt_create_zone(
            zone        => join('.', @bits),
            description => '',
        );
        ($zone_id, $host) = $self->get_zone_id( $fqdn );
    }

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'PTR',
        name    => $host,
        address => $self->fully_qualify( $addr ),
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_soa {
    my $self = shift;
    my $r = shift or die;

    print "SOA     : $r\n";
    my ( $zone, $mname, $rname, $serial, $refresh, $retry, $expire, $min, $ttl, $timestamp, $location )
        = split(':', $r);

    # TinyDNS auto-appends the trailing dot if missing
    $mname .= '.' if '.' ne substr($mname, -1, 1);
    $rname .= '.' if '.' ne substr($rname, -1, 1);

    my $zid = $self->nt_get_zone_id( zone => $zone );
    if ( $zid ) {
        print "zid: $zid\n";
        return $zid;
    };

    $self->nt_create_zone(
        zone        => $zone,
        description => '',
        defined $rname   ? ( contact => $rname )   : (),  # only include
        defined $ttl     ? ( ttl     => $ttl )     : (),  # when set
        refresh     => $refresh ||   16384,
        retry       => $retry   ||    2048,
        expire      => $expire  || 1048576,
        minimum     => $min     ||    2560,
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_generic {
    my ($self, $r) = @_;
    $r or die;
    print "Generic : $r\n";
    my ( $fqdn, $n, $rdata, $ttl, $timestamp, $location ) = split ':', $r;
    return $self->zr_spf(  $r )    if $n == 99;
    return $self->zr_aaaa( $r )    if $n == 28;
    return $self->zr_srv( $r )     if $n == 33;
    return $self->zr_gen_txt( $r ) if $n == 16;
    die "oops, no generic support for record type $n in $fqdn\n";
}

sub zr_gen_txt {
    my $self = shift;
    my $r = shift or die;

    print "TXT     : $r\n";
    my ( $fqdn, $n, $rdata, $ttl, $timestamp, $location ) = split(':', $r);

    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $rdata = $self->unpack_txt( $rdata );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'TXT',
        name    => $host,
        address => $rdata,
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_spf {
    my $self = shift;
    my $r = shift or die;

    print "SPF     : $r\n";
    my ( $fqdn, $n, $rdata, $ttl, $timestamp, $location ) = split(':', $r);

    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    # DNS RRtype 99 (SPF) and RRtype 16 (TXT) uses the same rdata format.
    # TinyDNS gen type :16: and :99: records are identical, except for the type.
    $rdata = $self->unpack_txt( $rdata );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'SPF',
        name    => $host,
        address => $rdata,
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_aaaa {
    my $self = shift;
    my $r = shift or die;

    print "AAAA    : $r\n";
    my ($fqdn, $n, $rdata, $ttl, $timestamp, $location) = split(':', $r);
    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $rdata = $self->unescape_packed_hex( $rdata );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'AAAA',
        name    => $host,
        address => $rdata,
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_aaaa6 {
    my $self = shift;
    my $r = shift or die;

    my ($fqdn, $rdata, $ttl, $timestamp, $location) = split(':', $r);
    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    # rdata is a string of hex characters
    $rdata = join ':', unpack "(a4)*", $rdata;

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'AAAA',
        name    => $host,
        address => $rdata,
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_srv {
    my ($self, $r) = @_;
    $r or die "missing record";

    print "SRV     : $r\n";
    my ($fqdn, $n, $rdata, $ttl, $timestamp, $location) = split ':', $r;
    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $rdata = $self->unescape_octal($rdata);
    my ($priority, $weight, $port) = unpack('n3', $rdata);
    my $target = $self->unpack_domain( $rdata, 6 );

    $self->nt_create_record(
        zone_id  => $zone_id,
        type     => 'SRV',
        name     => $host,
        address  => $self->fully_qualify( $target ),
        weight   => $weight,
        priority => $priority,
        other    => $port,
        defined $ttl       ? ( ttl       => $ttl       ) : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub ip_to_ptr {
    my ($self, $ip) = @_;
    return '' if ! $ip;
    return join '.', reverse(split /\./, $ip), 'in-addr.arpa.';
}

sub ip6_to_ptr {
    my ($self, $ip) = @_;
    return '' if ! $ip;
    return join '.', reverse(split //, $ip), 'ip6.arpa.';
}

sub unpack_domain {
    my ($self, $string, $index) = @_;

    $index ||= 0;
    my @labels;
    while ( $index < length $string ) {
        my $header = unpack "\@$index C", $string;
        return join('.', @labels) if !$header;
        if ( $header <= 63 ) {
            push @labels, substr $string, ++$index, $header;
            $index += $header;
        }
    }
    die "domain name unpack failed\n";
}

sub unpack_txt {
    my $self = shift;
    my $rdata = shift or die;

    # Gen type 16 (TXT) rdata contains one or more strings of
    # between 1 and 127 (or maybe up to 255) bytes (inclusive,
    # after unescape), each preceeded by a length byte.
    #
    # Any byte (length and string bytes) *can* be octal escaped,
    # but doesn't *have* to be if it's printable ascii (except
    # colon ':' and backslash '\', which must always be escaped).
    #
    # Note: Long TXT records in the ' (quote) TXT record syntax variant
    # (which doesn't contain length fields) will be split into segments
    # of only 127 bytes max by tinydns-data when generating data.cdb.
    # Some parts of TinyDNS thus uses a max length of 127 bytes,
    # so to play it safe, use 127 as the upper limit ... although
    # tests have shown that TinyDNS *can* handle gen type 16 TXT
    # records with strings up to the full DNS limit of 255 bytes.
    # YMMV though - you have been warned ...

    # Unescape everything (length and string bytes), then
    # build the TXT string one element (1-255 bytes) at a time
    my $raw = $self->unescape_octal( $rdata );
    $rdata = ''; # Reset for string build
    while (length $raw) {
        my $len = ord(substr($raw,0,1,'')); # Length byte
        die "Zero length element in TXT rdata ?\n" unless $len;
        $rdata .= substr($raw,0,$len,''); # String (1..255 bytes)
    }

    return $rdata;
}

sub unescape_octal {
    my ($self, $str) = @_;
    $str or die "missing string";
    # convert octal escapes to ascii
    $str =~ s/(\\)([0-9]{3})/chr(oct($2))/eg;
    return $str;
};

sub unescape_packed_hex {
    my ($self, $str) = @_;
    $str or die "missing string";

    # https://tools.ietf.org/html/rfc3596#section-2.2
    #    A 128 bit IPv6 address is encoded in the data portion of an AAAA
    #    resource record in network byte order (high-order byte first).

    # convert any octals to ASCII, then unpack to hex chars
    $str = unpack 'H*', $self->unescape_octal($str);

    # insert : after each 4 char set
    return join(':', unpack("(a4)*", $str));
};

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Import::tinydns - import tinydns data into NicTool

=head1 VERSION

version 2.34

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abe Shelton

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
