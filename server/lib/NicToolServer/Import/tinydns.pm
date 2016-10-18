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
        Time::HiRes::sleep 0.1;      # go slow enough we can read

        my $first = substr($record, 0, 1);
        my $record = substr($record, 1 );
        chomp $record;

        if ( $first eq 'Z' ) {          #  SOA        =>  Z fqdn:mname:rname:ser:ref:ret:exp:min:ttl:time:lo
            $self->zr_soa($record);
        }
        elsif ( $first eq '.' ) {       #  'SOA,NS,A' =>  . fqdn : ip : x:ttl:timestamp:lo
            $self->zr_soa($record);
            $self->zr_ns($record);
            my ( $fqdn, $ip, $ttl, $timestamp, $location ) = split(':', $record);
            $self->zr_a($record) if $ip;
        }
        elsif ( $first eq '=' ) {       #  'A,PTR'    =>  = fqdn : ip : ttl:timestamp:lo
            $self->zr_a($record);
            my ($fqdn, $addr, $ttl, $ts, $loc) = split(':', $record);
            if ('*.' eq substr $fqdn, 0, 2) {  # a wildcard A record is not a valid PTR name
                $fqdn = substr $fqdn, 2;       # strip *. prefix
            }
            $self->zr_ptr(join(':', $self->ip_to_ptr($addr), $fqdn, $ttl || '', $ts || '', $loc || ''));
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
    return 1;
};

sub zr_a {
    my $self = shift;
    my $r = shift or die;

    print "A  : $r\n";
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

    print "CNAME: $r\n";
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

    print "MX : $r\n";
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

    print "TXT: $r\n";
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

    print "NS : $r\n";
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

    print "PTR: $r\n";
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

    print "SOA: $r\n";
    my ( $zone, $mname, $rname, $serial, $refresh, $retry, $expire, $min, $ttl, $timestamp, $location )
        = split(':', $r);

    my $zid = $self->nt_get_zone_id( zone => $zone );
    if ( $zid ) {
        print "zid: $zid\n";
        return $zid;
    };

    $self->nt_create_zone(
        zone        => $zone,
        description => '',
        defined $rname   ? ( contact => $rname )   : (),  # only include
        defined $ttl     ? ( ttl     => $ttl )     : (),  # these values
        defined $refresh ? ( refresh => $refresh ) : (),  # when defined
        defined $retry   ? ( retry   => $retry )   : (),
        defined $expire  ? ( expire  => $expire )  : (),
        defined $min     ? ( minimum => $min )     : (),
        defined $timestamp ? ( timestamp => $timestamp ) : (),
        defined $location  ? ( location  => $location  ) : (),
    );
}

sub zr_generic {
    my ($self, $r) = @_;
    $r or die;
    print "Generic : $r\n";
    my ( $fqdn, $n, $rdata, $ttl, $timestamp, $location ) = split ':', $r;
    return $self->zr_spf(  $r ) if $n == 99;
    return $self->zr_aaaa( $r ) if $n == 28;
    return $self->zr_srv( $r )  if $n == 33;
    if ($n == 16) {
        $r =~ s/:16:\\[\d]{3,}/:/;
        return $self->zr_txt( $r );
    };
    die "oops, no generic support for record type $n in $fqdn\n";
}

sub zr_spf {
    my $self = shift;
    my $r = shift or die;

    print "SPF : $r\n";
    my ( $fqdn, $n, $rdata, $ttl, $timestamp, $location ) = split(':', $r);

    my ($zone_id, $host) = $self->get_zone_id( $fqdn );

    $rdata = $self->unescape_octal( $rdata );

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

    print "AAAA : $r\n";
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

sub zr_srv {
    my ($self, $r) = @_;
    $r or die "missing record";

    print "SRV : $r\n";
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
    # convert escaped hex back to hex chars, like in an AAAA
    $str =~ s/(\\)([0-9]{3})/sprintf('%02x',oct($2))/eg;
    return join(':', unpack("(a4)*", $str));
};

1;
