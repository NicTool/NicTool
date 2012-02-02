package NicToolServer::Export::PowerDNS;
# ABSTRACT: exporting DNS data to PowerDNS servers

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

# TODO: 

    return 1;
}

sub zr_a {
    my ($self, $r) = @_;

# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	A	$r->{address}\n";
}

sub zr_cname {
    my ($self, $r) = @_;

# name  ttl  class   rr     canonical name
    return "$r->{name}	$r->{ttl}	CNAME	$r->{address}\n";
}

sub zr_mx {
    my ($self, $r) = @_;

#name           ttl  class   rr  pref name
    return "$r->{name}	$r->{ttl}	MX	$r->{weight}	$r->{address}\n";
}

sub zr_txt {
    my ($self, $r) = @_;

# name  ttl  class   rr     text
    return "$r->{name}	$r->{ttl}	TXT	\"$r->{address}\"\n";
}

sub zr_ns {
    my ($self, $r) = @_;

# name  ttl  class  type  type-specific-data
    return "$r->{name}.	$r->{ttl}	NS	$r->{address}\n";
}

sub zr_ptr {
    my ($self, $r) = @_;

# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	PTR	$r->{address}\n";
}

sub zr_soa {
    my ($self, $z) = @_;

# name        ttl class rr    name-server email-addr  (sn ref ret ex min)
    return "$z->{zone}.		$z->{ttl}	IN	SOA	$z->{nsname}    $z->{mailaddr} (
					$z->{serial}    ; serial
					$z->{refresh}   ; refresh
					$z->{retry}     ; retry
					$z->{expire}    ; expiry
					$z->{minimum}   ; minimum
					)\n\n";
}

sub zr_spf {
    my ($self, $r) = @_;

# SPF record support was added in BIND v9.4.0

# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	SPF	$r->{address}\n";
}

sub zr_srv {
    my ($self, $r) = @_;

    my $priority = $self->{nte}->is_ip_port( $r->{priority} );
    my $weight   = $self->{nte}->is_ip_port( $r->{weight} );
    my $port     = $self->{nte}->is_ip_port( $r->{other} );

# srvce.prot.name  ttl  class   rr  pri  weight port target
    return "$r->{name}	$r->{ttl}	SRV	$priority	$weight	$port	$r->{address}\n";
}

sub zr_aaaa {
    my ($self, $r) = @_;

# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	AAAA	$r->{address}\n";
}

sub zr_loc {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	LOC	$r->{address}\n";
}


1;

__END__


