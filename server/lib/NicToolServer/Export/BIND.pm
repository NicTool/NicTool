package NicToolServer::Export::BIND;
# ABSTRACT: exporting DNS data to authoritative DNS servers

use strict;
use warnings;

use Cwd;
use Data::Dumper;
use File::Copy;
use Params::Validate qw/ :all /;

sub new {
    my $class = shift;

    my $self = bless {
        nte => shift,
    },
    $class;

    warn "oops, a NicToolServer::Export object wasn't provided!" 
        if ! $self->{nte};
    return $self;
}

sub get_export_file {
    my $self = shift;
    my $dir = shift || $self->{nte}->get_export_dir or return;
    my $zone = shift or die $self->{nte}->elog("missing zone");

    my $file = "$dir/$zone";
    open my $FH, '>', $file
        or die $self->{nte}->elog("unable to open $file");
    return $FH;
};

sub postflight {
    my $self = shift;

# TODO: 
#   write out a named.conf file
#   validate it?
#   restarted named

    return 1;
}

sub zr_a {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF }, } );

    my $r = $p{record};
# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	A	$r->{address}\n";
}

sub zr_cname {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );
    my $r = $p{record};

# name  ttl  class   rr     canonical name
    return "$r->{name}	$r->{ttl}	CNAME	$r->{address}\n";
}

sub zr_mx {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};
#name           ttl  class   rr  pref name
    return "$r->{name}	$r->{ttl}	MX	$r->{weight}	$r->{address}\n";
}

sub zr_txt {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};
# name  ttl  class   rr     text
    return "$r->{name}	$r->{ttl}	TXT	\"$r->{address}\"\n";
}

sub zr_ns {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};
# name  ttl  class  type  type-specific-data
    return "$r->{name}.	$r->{ttl}	NS	$r->{address}\n";
}

sub zr_ptr {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};
# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	PTR	$r->{address}\n";
}

sub zr_soa {
    my $self = shift;
    my %p = validate( @_, { zone => { type => HASHREF } } );

    my $z = $p{zone};

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
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};
# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	SPF	$r->{address}\n";
}

sub zr_srv {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

    my $priority = $self->{nte}->is_ip_port( $r->{priority} );
    my $weight   = $self->{nte}->is_ip_port( $r->{weight} );
    my $port     = $self->{nte}->is_ip_port( $r->{other} );

# srvce.prot.name  ttl  class   rr  pri  weight port target
    return "$r->{name}	$r->{ttl}	SRV	$priority	$weight	$port	$r->{address}\n";
}

sub zr_aaaa {
    my $self = shift;
    my %p = validate( @_, { record => { type => HASHREF } } );

    my $r = $p{record};

# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	AAAA	$r->{address}\n";
}

sub format_timestamp {
    my ($self, $ts) = @_;
    return $ts;
};


1;

__END__


