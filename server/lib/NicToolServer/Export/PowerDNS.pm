package NicToolServer::Export::PowerDNS;
# ABSTRACT: exporting DNS data to PowerDNS servers

=pod

A working PowerDNS pipe backend script is included in the NicToolServer 
distribution as bin/nt_powerdns.pl. It serves PowerDNS requests directly
from the data in the NicTool tables.

This module is primarily for documentation. It could be used to populate 
a set of PowerDNS tables in the native PowerDNS SQL schema. If it were 
used that way, each of the zr_ methods below would contain a query used 
to insert the records. Search the NicTool mailing list archives for 'PowerDNS'
for more info.

=cut

use strict;
use warnings;

use Cwd;
use File::Copy;
use Params::Validate qw/ :all /;

sub new {
    my $class = shift;

    my $self = bless {
        nte => shift,
        zone_list => [],
    },
    $class;

    warn "oops, a NicToolServer::Export object wasn't provided!" 
        if ! $self->{nte};
    return $self;
}

sub export_db {
    my $self = shift;

    foreach my $z ( @{ $self->{nte}->get_ns_zones() } ) {
        push @{$self->{zone_list}}, $z->{zone};
# ....
        $self->{nte}{zone_name} = $z->{zone};
#        print $fh $self->{nte}->zr_soa( $z );
#        print $fh $self->{nte}->zr_ns( $z );

        my $records = $self->get_records( $z->{nt_zone_id} );
        foreach my $r ( @$records ) {
            my $type   = lc( $r->{type} );
            my $method = "zr_${type}";
            $r->{location}  ||= '';
# each of the zone record methods below need to be altered to return whatever
# PowerDNS needs
#            print $fh $self->$method( $r );
        }

    }   
};

sub get_records {
    my $self = shift;
    my $zone_id = shift;

    my $sql = "SELECT r.name, r.ttl, r.description, t.name AS type, r.address, r.weight, 
    priority, other, location, UNIX_TIMESTAMP(timestamp) AS timestamp
        FROM nt_zone_record r
        LEFT JOIN resource_record_type t ON t.id=r.type_id
         WHERE r.deleted=0 AND r.nt_zone_id=?";

    return $self->{nte}->exec_query( $sql, $zone_id );
}

sub postflight {
    my $self = shift;

# TODO

    return 1;
}

sub zr_a {
    my ($self, $r) = @_;
}

sub zr_cname {
    my ($self, $r) = @_;
}

sub zr_mx {
    my ($self, $r) = @_;
}

sub zr_txt {
    my ($self, $r) = @_;
}

sub zr_ns {
    my ($self, $r) = @_;
}

sub zr_ptr {
    my ($self, $r) = @_;
}

sub zr_soa {
    my ($self, $z) = @_;
}

sub zr_spf {
    my ($self, $r) = @_;
}

sub zr_srv {
    my ($self, $r) = @_;
}

sub zr_aaaa {
    my ($self, $r) = @_;
}

sub zr_loc {
    my ($self, $r) = @_;
}


1;

__END__


