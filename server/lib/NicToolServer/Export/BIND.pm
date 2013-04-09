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
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my $fh = $self->get_export_file( 'named.conf.nictool', $dir );
    foreach my $zone ( @{$self->{zone_list}} ) {
        my $tmpl = $self->get_template($dir, $zone);
        if ( $tmpl ) {
            print $fh $tmpl;
            next;
        };

        print $fh qq[zone "$zone"\t IN { type master; file "$datadir/$zone"; };\n];
    };
    close $fh;

    return 1 if ! $self->{nte}{postflight_extra};

    $self->write_makefile() or return;
    $self->compile() or return;
    $self->rsync()   or return;
    $self->restart() or return;

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

sub compile {
    my $self = shift;

    my $dir = $self->{nte}{export_dir};

    $self->{nte}->set_status("compile");
    my $before = time;
    system ('make compile') == 0 or do {
        $self->{nte}->set_status("last: FAILED compile: $?");
        $self->{nte}->elog("unable to compile: $?");
        return;
    };
    my $elapsed = time - $before;
    my $message = "compiled";
    $message .= " ($elapsed secs)" if $elapsed > 5;
    $self->{nte}->elog($message);
    return 1;
};

sub restart {
    my $self = shift;

    return 1 if ! defined $self->{nte}{ns_ref}{address};

    my $before = time;
    $self->{nte}->set_status("remote restart");
    system ('make restart') == 0 or do {
        $self->{nte}->set_status("last: FAILED restart: $?");
        $self->{nte}->elog("unable to restart: $?");
        return;
    };
    my $elapsed = time - $before;
    my $message = "restarted";
    $message .= " ($elapsed secs)" if $elapsed > 5;
    $self->{nte}->elog($message);
    return 1;
};

sub rsync {
    my $self = shift;

    my $dir = $self->{nte}{export_dir};

    return 1 if ! defined $self->{nte}{ns_ref}{address};  # no rsync

    $self->{nte}->set_status("remote rsync");
    my $before = time;
    system ('make remote') == 0 or do {
        $self->{nte}->set_status("last: FAILED rsync: $?");
        $self->{nte}->elog("unable to rsync: $?");
        return;
    };
    my $elapsed = time - $before;
    my $message = "copied";
    $message .= " ($elapsed secs)" if $elapsed > 5;
    $self->{nte}->elog($message);
    return 1;
};

sub write_makefile {
    my $self = shift;

    return 1 if -e 'Makefile';   # already exists

    my $address = $self->{nte}{ns_ref}{address} || '127.0.0.1';
    my $datadir = $self->{nte}{ns_ref}{datadir} || getcwd . '/data-all';
    $datadir =~ s/\/$//;  # strip off any trailing /
    my $exportdir = $self->{nte}->get_export_dir or die "no export dir!";
    open my $M, '>', 'Makefile' or do {
        warn "unable to open ./Makefile: $!\n";
        return;
    };
    print $M <<MAKE
# After a successful export, 3 make targets are run: compile, remote, restart
# Each target can do anything you'd like. Examples are shown for several BIND
# compatible NS daemons. Remove comments (#) to activate the ones you wish.

################################
#########  BIND 9  #############
################################
# note that all 3 phases do nothing by default. It is expected that you are
# using BINDs zone transfers. With these options, can also use rsync instead.

compile: $exportdir/named.conf.nictool
\ttest 1

remote: $exportdir/named.conf.nictool
\t#rsync -az $exportdir/ bind\@$address:$datadir/
\ttest 1

restart: $exportdir/named.conf.nictool
\t#ssh bind\@$address rndc reload
\ttest 1

################################
#########    NSD   #############
################################
# Note: you will need to configure zonesdir in nsd.conf to point to this
# export directory. Make sure the export directory reflected below is correct
# then uncomment each of the targets.

#compile: $exportdir/named.conf.nictool
#\tnsdc rebuild
#
#remote: /var/db/nsd/nsd.db
#\trsync -az /var/db/nsd/nsd.db nsd\@$address:/var/db/nsd/
#
#restart: nsd.db
#\tssh nsd\@$address nsdc reload

################################
#########  PowerDNS  ###########
################################

#compile: $exportdir/named.conf.nictool
#\ttest 1
#
#remote: $exportdir/named.conf.nictool
#\trsync -az $exportdir/ powerdns\@$address:$datadir/
#
#restart: $exportdir/named.conf.nictool
#\tssh powerdns\@$address pdns_control cycle
MAKE
;
    close $M;
    return 1;
};

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

# BIND will croak if the length of the text record is longer than 255
    if ( length $r->{address} > 255 ) {
        $r->{address} = join( "\" \"", unpack("(a255)*", $r->{address} ) );
    };
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

    # empty mailaddr makes BIND angry, set a default
    $z->{mailaddr} ||= 'hostmaster.' . $z->{zone} . '.';
    if ( '.' ne substr( $z->{mailaddr}, -1, 1) ) {   # not fully qualified
        $z->{mailaddr} = $self->{nte}->qualify( $z->{mailaddr} ); # append domain
        $z->{mailaddr} .= '.';     # append trailing dot
    };

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
# https://www.ietf.org/rfc/rfc3403.txt

    my $order = $self->{nte}->is_ip_port( $r->{weight}   );
    my $pref  = $self->{nte}->is_ip_port( $r->{priority} );
    my ($flags, $service, $regexp, $replace) = split /__/, $r->{address};
    $regexp =~ s/\\/\\\\/g;  # escape any \ characters

# Domain TTL Class Type Order Preference Flags Service Regexp Replacement
    return qq[$r->{name} $r->{ttl}   IN  NAPTR   $order  $pref   "$flags"  "$service"    "$regexp" $replace\n];
}

sub zr_dname {
    my ($self, $r) = @_;

# name  ttl  class   rr     target
    return "$r->{name}	$r->{ttl}	IN  DNAME	$r->{address}\n";
}

sub zr_sshfp {
    my ($self, $r) = @_;
    my $algo   = $r->{weight};     #  1=RSA,   2=DSS,     3=ECDSA
    my $type   = $r->{priority};   #  1=SHA-1, 2=SHA-256
    return "$r->{name} $r->{ttl}     IN  SSHFP   $algo $type $r->{address}\n";
}

sub zr_ipseckey {
    my ($self, $r) = @_;

    my $precedence = $r->{weight};
    my $gw_type    = $r->{priority};
    my $algorithm  = $r->{other};
    my $gateway    = $r->{address};
    my $public_key = $r->{description};

    return "$r->{name}	$r->{ttl}	IN  IPSECKEY	( $precedence $gw_type $algorithm $gateway $public_key )\n";
};

sub zr_dnskey {
    my ($self, $r) = @_;

    my $flags    = $r->{weight};
    my $protocol = $r->{priority};  # always 3, RFC 4034
    my $algorithm = $r->{other};
    # 1=RSA/MD5, 2=Diffie-Hellman, 3=DSA/SHA-1, 4=Elliptic Curve, 5=RSA/SHA-1

    return "$r->{name}	$r->{ttl}	IN  DNSKEY	$flags $protocol $algorithm $r->{address}\n";
}

sub zr_ds {
    my ($self, $r) = @_;

    my $key_tag     = $r->{weight};
    my $algorithm   = $r->{priority}; # same as DNSKEY algo -^
    my $digest_type = $r->{other};    # 1=SHA-1 (RFC 4034), 2=SHA-256 (RFC 4509)

    return "$r->{name}	$r->{ttl}	IN  DS	$key_tag $algorithm $digest_type $r->{address}\n";
}

sub zr_rrsig {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  RRSIG $r->{address}\n";
}

sub zr_nsec {
    my ($self, $r) = @_;
    $r->{description} =~ s/[\(\)]//g;
    return "$r->{name}	$r->{ttl}	IN  NSEC $r->{address} ( $r->{description} )\n";
}

sub zr_nsec3 {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  NSEC3 $r->{address}\n";
}

sub zr_nsec3param {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  NSEC3PARAM $r->{address}\n";
}


1;

__END__

=head1 NAME

NicToolServer::Export::BIND

=head1 SYNOPSIS

Export DNS information from NicTool as BIND zone files. These exports are also suitable for use with any BIND compatible authoritative name servers like PowerDNS, NSD, and Knot DNS.

=head1 named.conf.local

This class will export a named.conf.nictool file with all the NicTool zones assigned to that NicTool BIND nameserver. It is expected that this file will be included into a named.conf file via an include entry like this:

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
