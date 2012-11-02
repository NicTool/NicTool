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
    my $dir = shift || $self->{nte}->get_export_dir or return;
    my $fh = $self->get_export_file( 'named.conf.nictool', $dir );
    foreach my $zone ( @{$self->{zone_list}} ) {
        my $tmpl = $self->get_template($dir, $zone);
        if ( $tmpl ) {
            print $fh $tmpl;
            next;
        };

        print $fh qq[zone "$zone"\t IN { type master; file "$dir/$zone"; };\n];
    };
    close $fh;

# TODO: 
#   validate it?
#   restarted named

    return 1;
}

sub get_template {
    my ($self, $export_dir, $zone) = @_;

    return if ! $zone;
    my $tmpl_dir = "$export_dir/templates";
    return if ! -d $tmpl_dir;

    my $tmpl;
    foreach my $f ( $zone, 'default' ) {
        next if ! -f "$tmpl_dir/$f";
        $tmpl = "$tmpl_dir/$f";
        last;
    };    
    return if ! $tmpl;

    open my $FH, '<', $tmpl or do {
        warn "unable to open $tmpl\n";
        return;
    };
    my @lines = <$FH>;
    close $FH;

    foreach ( @lines ) { $_ =~ s/ZONE/$zone/g; };
    return join('', @lines); # stringify the array
}

sub zr_a {
    my ($self, $r) = @_;

# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	IN  A	$r->{address}\n";
}

sub zr_cname {
    my ($self, $r) = @_;

# name  ttl  class   rr     canonical name
    return "$r->{name}	$r->{ttl}	IN  CNAME	$r->{address}\n";
}

sub zr_mx {
    my ($self, $r) = @_;

#name           ttl  class   rr  pref name
    return "$r->{name}	$r->{ttl}	IN  MX	$r->{weight}	$r->{address}\n";
}

sub zr_txt {
    my ($self, $r) = @_;

# name  ttl  class   rr     text
    return "$r->{name}	$r->{ttl}	IN  TXT	\"$r->{address}\"\n";
}

sub zr_ns {
    my ($self, $r) = @_;

    my $name = $self->qualify( $r->{name} );
    $name .= '.' if '.' ne substr($name, -1, 1);

# name  ttl  class  type  type-specific-data
    return "$name	$r->{ttl}	IN	NS	$r->{address}\n";
}

sub zr_ptr {
    my ($self, $r) = @_;

# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	IN  PTR	$r->{address}\n";
}

sub zr_soa {
    my ($self, $z) = @_;

# name        ttl class rr    name-server email-addr  (sn ref ret ex min)
    return "
\$TTL    $z->{ttl};
\$ORIGIN $z->{zone}.
$z->{zone}.		IN	SOA	$z->{nsname}    $z->{mailaddr} (
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
    return "$r->{name}	$r->{ttl}	IN  SPF	\"$r->{address}\"\n";
}

sub zr_srv {
    my ($self, $r) = @_;

    my $priority = $self->{nte}->is_ip_port( $r->{priority} );
    my $weight   = $self->{nte}->is_ip_port( $r->{weight} );
    my $port     = $self->{nte}->is_ip_port( $r->{other} );

# srvce.prot.name  ttl  class   rr  pri  weight port target
    return "$r->{name}	$r->{ttl}	IN  SRV	$priority	$weight	$port	$r->{address}\n";
}

sub zr_aaaa {
    my ($self, $r) = @_;

# name  ttl  class  type  type-specific-data
    return "$r->{name}	$r->{ttl}	IN  AAAA	$r->{address}\n";
}

sub zr_loc {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  LOC	$r->{address}\n";
}

sub zr_naptr {
    my ($self, $r) = @_;

# http://www.ietf.org/rfc/rfc2915.txt

    my $order = $self->{nte}->is_ip_port( $r->{weight}   );
    my $pref  = $self->{nte}->is_ip_port( $r->{priority} );
    my ($flags, $service, $regexp, $replace) = split /__/, $r->{address};
    $regexp =~ s/\\/\\\\/g;  # escape any \ characters

# Domain TTL Class Type Order Preference Flags Service Regexp Replacement
    return qq[$r->{name} $r->{ttl}   IN  NAPTR   $order  $pref   "$flags"  "$service"    "$regexp" $replace\n];
}


1;

__END__

=head1 NAME

NicToolServer::Export::BIND

=head1 named.conf.local

This class will export a named.conf.nictool file with all the NicTool zones assigned to a NicTool BIND nameserver. It is expected that this file will be included into a named.conf file via an include entry like this:

 include "/etc/namedb/master/named.conf.nictool";


=head1 Templates

Paul Hamby contributed a patch to add support for zone templates. By default, a line such as this is added for each zone:

 zone "example.com"  IN { type master; file "/etc/namedb/master/example.com"; };

Templates provide a way to customize the additions that NicTool makes to named.conf.

Templates are configured by creating a 'templates' directory in the BIND export directory (as defined within the NicTool nameserver config). Populate the templates directory with a 'default' template, and/or templates that match specific zone names you wish to customize.

=head2 Example template

 zone "ZONE" {
    type master;
    file "/etc/namedb/master/ZONE";
    notify yes;
    also-notify {
        10.1.1.1;
    };
    allow-transfer {
        10.1.1.1;
    };
 };

Any instances of the keyword ZONE in a template are replaced by the zone name.

=cut
