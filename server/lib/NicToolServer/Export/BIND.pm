package NicToolServer::Export::BIND;
# ABSTRACT: exporting DNS data to authoritative DNS servers

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::Base';

use Cwd;
use IO::File;
use File::Copy;
use Params::Validate qw/ :all /;

sub postflight {
    my $self = shift;
    my $dir = shift || $self->{nte}->get_export_dir or return;

    $self->update_named_include( $dir ) or return;

    return 1 if ! $self->{nte}{postflight_extra};

    $self->write_makefile() or return;
    $self->compile() or return;
    $self->rsync()   or return;
    $self->restart() or return;

    return 1;
}

sub update_named_include {
    my ($self, $dir) = @_;
    if ( $self->{nte}->incremental ) {
        return $self->update_named_include_incremental( $dir );
    };
    # full export, write a new include  file
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my $fh = $self->get_export_file( 'named.conf.nictool', $dir );
    foreach my $zone ( $self->{nte}->zones_exported ) {
        my $tmpl = $self->get_template($dir, $zone);
        if ( $tmpl ) {
            print $fh $tmpl;
            next;
        };

        print $fh qq[zone "$zone"\t IN { type master; file "$datadir/$zone"; };\n];
    };
    close $fh;
    return 1;
};

sub update_named_include_incremental {
    my ($self, $dir) = @_;

    # check that the zone that was modified since our last export is in the
    # include file, else append it.
    #
    # there's likely to be more lines in the include file than zones to append
    # build a lookup table of changed zones and pass through the file once
    my $to_add = $self->get_changed_zones( $dir );
    my $file   = "$dir/named.conf.nictool";

    my $in = IO::File->new($file, '<') or do {
            warn "unable to read $file\n";
            return;
        };

    my $out = IO::File->new("$file.tmp", '>') or do {
            warn "unable to append $file.tmp\n";
            return;
        };

    # zone "simerson.net"  IN { type master; file "/etc/namedb/nictool/simerson.net"; };
    while ( my $line = <$in> ) {
        my $zone = (split( /\"/, $line, 3))[1];
        if ( $to_add->{$zone} ) {
            delete $to_add->{$zone};   # exists, remove from add list
        };
        if ( ! $self->{nte}{zones_deleted}{$zone} ) {
            $out->print( $line );
        };
    };
    $in->close;

    foreach my $key ( keys %$to_add ) {
        $out->print( $to_add->{$key} );
    };
    $out->close;
    unlink $file;
    File::Copy::move("$file.tmp", $file);
    return 1;
};

sub get_changed_zones {
    my ($self, $dir) = @_;
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my %has_changes;
    foreach my $zone ( $self->{nte}->zones_exported ) {
        my $tmpl = $self->get_template($dir, $zone);
        if ( $tmpl ) {
            $has_changes{$zone} = $tmpl;
            next;
        };
        $has_changes{$zone} = qq[zone "$zone"\t IN { type master; file "$datadir/$zone"; };\n];
    };
    return \%has_changes;
};

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

    $self->{nte}->set_status("compile");
    my $exportdir = $self->{nte}->get_export_dir;
    my $before = time;
    system ("make -C $exportdir compile") == 0 or do {
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
    my $exportdir = $self->{nte}->get_export_dir;

    my $before = time;
    $self->{nte}->set_status("remote restart");
    system ("make -C $exportdir restart") == 0 or do {
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

    return 1 if ! defined $self->{nte}{ns_ref}{address};  # no rsync
    my $exportdir = $self->{nte}->get_export_dir;

    $self->{nte}->set_status("remote rsync");
    my $before = time;
    system ("make -C $exportdir remote") == 0 or do {
        $self->{nte}->set_status("last: FAILED rsync: $?");
        $self->{nte}->elog("unable to rsync: $?");
        return;
    };
    my $elapsed = time - $before;
    my $message = "copied";
    $message .= " ($elapsed secs)" if $elapsed > 5;
    $self->{nte}->set_copied(1);
    $self->{nte}->elog($message);
    return 1;
};

sub write_makefile {
    my $self = shift;

    my $exportdir = $self->{nte}->get_export_dir or do {
        warn "no export dir!";
        return;
    };
    return 1 if -e "$exportdir/Makefile";   # already exists

    my $address = $self->{nte}{ns_ref}{address} || '127.0.0.1';
    my $datadir = $self->{nte}{ns_ref}{datadir} || getcwd . '/data-all';
    my $remote_login = $self->{nte}{ns_ref}{remote_login} || 'bind';
    $datadir =~ s/\/$//;  # strip off any trailing /
    open my $M, '>', "$exportdir/Makefile" or do {
        warn "unable to open ./Makefile: $!\n";
        return;
    };
    print $M <<MAKE
# After a successful export, 3 make targets are run: compile, remote, restart
# Each target can do anything you'd like.
# See https://www.gnu.org/software/make/manual/make.html

################################
#########  BIND 9  #############
################################
# note that all 3 phases do nothing by default. It is expected that you are
# using BINDs zone transfers. With these options, can also use rsync instead.

compile: $exportdir/named.conf.nictool
\ttest 1

remote: $exportdir/named.conf.nictool
\t#rsync -az --delete $exportdir/ $remote_login\@$address:$datadir/
\ttest 1

restart: $exportdir/named.conf.nictool
\t#ssh $remote_login\@$address rndc reload
\ttest 1
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

    # fixup for quotes around DKIM in the DB (Luser error)
    $r->{address} =~ s/^"//g;   # strip off any leading quotes
    $r->{address} =~ s/"$//g;   # strip off any trailing quotes

    # BIND croaks when any string in the TXT RR address is longer than 255
    if ( length $r->{address} > 255 ) {
        $r->{address} = join( '" "', unpack("(a255)*", $r->{address} ) );
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
    my ($flags, $service, $regexp) = split /" "/, $r->{address};
    $regexp =~ s/"//g;  # strip off leading "
    $flags =~ s/"//g;   # strip off trailing "
    my $replace = $r->{description};
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

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::BIND - exporting DNS data to authoritative DNS servers

=head1 VERSION

version 2.33

=head1 SYNOPSIS

Export DNS information from NicTool as BIND zone files. These exports are also suitable for use with any BIND compatible authoritative name servers like PowerDNS, NSD, and Knot DNS.

=head1 NAME

NicToolServer::Export::BIND

=head1 named.conf.local

This class will export a named.conf.nictool file with all the NicTool zones assigned to that NicTool BIND nameserver. It is expected that this file will be included into a named.conf file via an include entry like this:

 include "/etc/namedb/master/named.conf.nictool";

=head1 Templates

See the L<https://github.com/msimerson/NicTool/wiki/Export-to-BIND|Export to BIND> page.

=head1 AUTHOR

Matt Simerson

Paul Hamby

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
