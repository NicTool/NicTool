package NicToolServer::Export::MaraDNS;
# ABSTRACT: exporting DNS data to MaraDNS servers

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
#           print $fh $self->$method( $r );
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

# Ahost.example.com.|7200|10.1.2.3
    return "A$r->{name}|$r->{ttl}|$r->{address}\n";
}

sub zr_cname {
    my ($self, $r) = @_;

# Calias.example.org.|3200|realname.example.org.
    return "C$r->{name}|$r->{ttl}|$r->{address}\n";
}

sub zr_mx {
    my ($self, $r) = @_;

# @example.com.|86400|10|mail.example.com.
    return "\@$r->{name}|$r->{ttl}|$r->{weight}|$r->{address}\n";
}

sub zr_txt {
    my ($self, $r) = @_;

# Texample.com.|86400|Example.com: Buy example products online
    return "T$r->{name}|$r->{ttl}|$r->{address}\n";
}

sub zr_ns {
    my ($self, $r) = @_;

# Nexample.com.|86400|ns.example.com.
    return "N$r->{name}.|$r->{ttl}|$r->{address}\n";
}

sub zr_ptr {
    my ($self, $r) = @_;

# P3.2.1.10.in-addr.arpa.|86400|ns.example.com.
    return "P$r->{name}|$r->{ttl}|$r->{address}\n";
}

sub zr_soa {
    my ($self, $z) = @_;

# Sexample.net.|86400|example.net.|hostmaster@example.net.|19771108|7200|3600|604800|1800
    return "S$z->{zone}.|$z->{ttl}|$z->{nsname}|$z->{mailaddr}|$z->{serial}|$z->{refresh}|$z->{retry}|$z->{expire}|$z->{minimum}\n";
}

sub zr_spf {
    my ($self, $r) = @_;

# Uexample.com|3600|40|\\010\\001\\002Kitchen sink data
    return "U$r->{name}|$r->{ttl}|99|$r->{address}\n";
}

sub zr_srv {
    my ($self, $r) = @_;

# srvce.prot.name  ttl  class   rr  pri  weight port target
# I suspect these can be completed by using a method just like in the tinydns
# export. Needs testing...
    return "";
}

sub zr_aaaa {
    my ($self, $r) = @_;

# TODO:
# I suspect these can be completed by using a method just like in the tinydns
# export. Needs testing...
    return "";
}

sub zr_loc {
    my ($self, $r) = @_;
# TODO:
    return "";
}


1;

__END__

MaraDNS RR formats defined here:
http://www.maradns.org/tutorial/man.csv1.html
