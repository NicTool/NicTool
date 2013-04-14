package NicToolServer::Import::BIND;
# ABSTRACT: import BIND zone files into NicTool

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

use Net::DNS::Zone::Parser;

sub get_import_file {
    my $self = shift;
    my $filename = shift || '/etc/namedb/named.conf';

    return $self->{FH} if defined $self->{FH};

    open my $FH, '<', $filename
        or die "failed to open '$filename'";

    $self->{FH} = $FH;
    return $FH;
};

sub import_records {
    my $self = shift;

    my $p = NicToolServer::Import::BIND::Conf_Parser->new;
    foreach ( qw/ nt group_id nameservers / ) {
        $p->{$_} = $self->{$_};
    };
    #print "loaded parser\n";
    $p->parse_fh( $self->{FH} );
    #print "done parsing\n";
};

sub import_zone {
    my ($self, $zone, $file) = @_;
    print "zone: $zone \tfrom\t$file\n";

    my $parser = Net::DNS::Zone::Parser->new;
    $parser->read($file,
        {   ORIGIN    => $zone,
            CREATE_RR => 1,
            STRIP_SEC => 1,
        }
    ) and die "unable to read/parse $file\n";

    my $RRs=$parser->get_array();
    foreach my $rr ( @$RRs ) {
        my $method = 'zr_' . lc $rr->type;
        $self->$method( $rr );
#        Time::HiRes::sleep 0.1;
    };
};

sub zr_soa {
    my ($self, $rr) = @_;

    my $zid = $self->nt_get_zone_id( zone => $rr->name );
    if ( $zid ) {
        print "zid: $zid\n";
        return $zid;
    };

    $self->nt_create_zone(
            zone        => $rr->name,
            description => '',
            contact     => $rr->rname . '.',
            ttl         => $rr->ttl,
            refresh     => $rr->refresh,
            retry       => $rr->retry,
            expire      => $rr->expire,
            minimum     => $rr->minimum,
            );
};

sub zr_ns {
    my ($self, $rr) = @_;

    # automatically generated in NicTool
    return;
};

sub zr_a {
    my $self = shift;
    my $rr = shift or die;

    print "A : " . $rr->name . "\t" . $rr->address . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'A',
        name    => $host,
        address => $rr->address,
        ttl     => $rr->ttl,
    );
};

sub zr_mx {
    my $self = shift;
    my $rr = shift or die;

    print "MX : " . $rr->name . "\t" . $rr->exchange . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'MX',
        name    => $host,
        address => $self->fully_qualify( $rr->exchange ),
        weight  => $rr->preference,
        ttl     => $rr->ttl,
    );
}

sub zr_txt {
    my $self = shift;
    my $rr = shift or die;

    print "TXT : " . $rr->name . "\t" . $rr->txtdata . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'TXT',
        name    => $host,
        address => $rr->txtdata || '',
        ttl     => $rr->ttl,
    );
}

sub zr_cname {
    my $self = shift;
    my $rr = shift or die;

    print "CNAME : ".$rr->name."\t".$rr->cname."\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'CNAME',
        name    => $host,
        address => $self->fully_qualify( $rr->cname ),
        ttl     => $rr->ttl,
    );
}

sub zr_spf {
    my $self = shift;
    my $rr = shift or die;

    print "SPF : " . $rr->name . "\t" . $rr->txtdata . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'SPF',
        name    => $host,
        address => $rr->txtdata,
        ttl     => $rr->ttl,
    );
}

sub zr_aaaa {
    my $self = shift;
    my $rr = shift or die;

    print "AAAA : " . $rr->name . "\t" . $rr->address . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'AAAA',
        name    => $host,
        address => $rr->address,
        ttl     => $rr->ttl,
    );
};

sub zr_srv {
    my $self = shift;
    my $rr = shift or die;

    print "SRV : " . $rr->name . "\t" . $rr->target . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'SRV',
        name    => $host,
        address => $self->fully_qualify( $rr->target ),
        weight  => $rr->weight,
        priority=> $rr->priority,
        other   => $rr->port,
        ttl     => $rr->ttl,
    );
}

sub zr_loc {
    my $self = shift;
    my $rr = shift or die;

    print "LOC : " . $rr->name . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'LOC',
        name    => $host,
        address => join(' ', $rr->latitude, $rr->longitude, $rr->altitude, $rr->size, $rr->hp, $rr->vp ),
        ttl     => $rr->ttl,
    );
}

sub zr_dname {
    my $self = shift;
    my $rr = shift or die;

    print "DNAME : ".$rr->name."\t".$rr->target."\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'CNAME',
        name    => $host,
        address => $self->fully_qualify( $rr->target ),
        ttl     => $rr->ttl,
    );
}

sub zr_sshfp { 
    my $self = shift;
    my $rr = shift or die;

    print "SSHFP : " . $rr->name . "\t" . $rr->fp . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'SSHFP',
        name    => $host,
        address => $rr->fp,
        weight  => $rr->algorithm,
        priority=> $rr->fptype,
        ttl     => $rr->ttl,
    );
};

sub zr_naptr { 
    my $self = shift;
    my $rr = shift or die;

    print "NAPTR : " . $rr->name . "\t" . $rr->service . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'NAPTR',
        name    => $host,
        address => join(' ', $rr->flags, $rr->service, $rr->regexp),
        weight  => $rr->order,
        priority=> $rr->preference,
        ttl     => $rr->ttl,
    );
};

sub zr_ptr {
    my $self = shift;
    my $rr = shift or die;

    print "PTR : " . $rr->name . "\t" . $rr->ptrdname . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'PTR',
        name    => $host,
        address => $self->fully_qualify( $rr->ptrdname ),
        ttl     => $rr->ttl,
    );
};

sub zr_ipseckey { 
    my $self = shift;
    my $rr = shift or die;

    print "IPSECKEY : " . $rr->name . "\t" . $rr->gateway . "\n";
    my ($zone_id, $host) = $self->get_zone_id( $rr->name );

    $self->nt_create_record(
        zone_id => $zone_id,
        type    => 'IPSECKEY',
        name    => $host,
        address => $rr->gateway,
        weight  => $rr->precedence,
        priority=> $rr->gatetype,
        other   => $rr->algorithm,
        ttl     => $rr->ttl,
        description => $rr->key,
    );
};


sub zr_ds { };
sub zr_dnskey { };
sub zr_nsec { };
sub zr_nsec3 { };
sub zr_nsec3param { };
sub zr_rrsig { };
#    die Data::Dumper::Dumper($rr);

1;

package NicToolServer::Import::BIND::Conf_Parser;

use BIND::Conf_Parser;
use vars qw(@ISA);
@ISA = qw(NicToolServer::Import::BIND NicToolServer::Import::Base BIND::Conf_Parser);

sub handle_zone {
    my($self, $name, $class, $type, $options) = @_;
    $self->import_zone( $name, $options->{file} );
};

1;
