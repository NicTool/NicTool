package NicToolServer::Export::BIND;
# ABSTRACT: exporting DNS data to authoritative DNS servers

use strict;
use warnings;

use lib 'lib';
use base 'NicToolServer::Export::Base';

use Cwd;
use File::Copy;
use Params::Validate qw/ :all /;

sub postflight {
    my $self = shift;

#   write out a named.conf file
    my $dir = shift || $self->{nte}->get_export_dir or return;
    my $fh = $self->get_export_file( 'named.conf.nictool', $dir );
    foreach my $zone ( @{$self->{zone_list}} ) {
        print $fh qq[
zone "$zone" { type master; file "$dir/$zone"; }; ];
    };
    close $fh;

# TODO: 
#   validate it?
#   restarted named

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
    return "$r->{name}	$r->{ttl}	SPF	\"$r->{address}\"\n";
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


