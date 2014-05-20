package NicToolServer::Export::BIND::nsupdate;
# ABSTRACT: exporting DNS data to authoritative DNS servers

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::Base';

use Cwd;
use IO::File;
use File::Copy;
use Params::Validate qw/ :all /;
use Data::Dumper;

sub postflight {
    my $self = shift;
    my $dir = shift || $self->{nte}->get_export_dir or return;

    build_nsupdate($self, $dir);

    #$self->update_named_include( $dir ) or return;
	if ( $self->{nte}->incremental ) {
		$self->export_latest($dir) or return;
	} else {
		$self->export_all($dir) or return;
	}
	
    return 1;
}

sub build_nsupdate {
    my ($self, $dir) = @_;

    my @results = get_log($self,$dir);

    # open the nsupdate log file
    open FILE, "+>", "$dir/nsupdate.log" or die $!;
    # print the server details for nsupdate
    #print FILE $self->zr_soa($self, get_zone_record($self,$results[0]->{object_id}[0]);

	foreach my $record (@results) {
    		my @zone_records = get_zone_record($self, $record->{object_id});
		my $r = $zone_records[0];
		my $mode = "add";

		# check if its a delete action
		if ($record->{description} =~ m/deleted\srecord/) {
			$mode = "delete";	
		}

          	my $method = 'zr_' . lc $r->{type};
            	$r->{location}  ||= '';
            	print FILE $self->$method($r, $mode);
        }

    close FILE or die $!;
}

sub get_log {
    my ($self, $dir) = @_;

    my $dbix_w = $self->{nte}->{dbix_w};
    my $time = time-300;

    my $sql = "select * from nt_user_global_log where timestamp > $time";

    return $dbix_w->query($sql)->hashes;
}

sub get_zone_record {
    my ($self, $id) = @_;
    my $dbix_w = $self->{nte}->{dbix_w};
    my $time = time-1800;

    my $sql = "select r.name, r.ttl, r.description, t.name AS type, r.address, r.weight,
    r.priority, r.other, r.location, z.zone
    from nt_zone_record r
    LEFT JOIN resource_record_type t ON t.id=r.type_id
    LEFT JOIN nt_zone z ON r.nt_zone_id=z.nt_zone_id
    where r.nt_zone_record_id = $id";

    return $dbix_w->query($sql)->hashes;
}

sub export_all {
    my ($self, $dir) = @_;
}

sub export_incremental {
    my ($self, $dir) = @_;

}
	

#---------- OLD methods below for reference -----------#

sub get_changed_zones {
    my ($self, $dir) = @_;
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my %has_changes;
    foreach my $zone ( @{$self->{zone_list}} ) {
        my $tmpl = $self->get_template($dir, $zone);
        if ( $tmpl ) {
            $has_changes{$zone} = $tmpl;
            next;
        };
        $has_changes{$zone} = qq[zone "$zone"\t IN { type master; file "$datadir/$zone"; };\n];
    };
    return \%has_changes;
};

sub zr_a {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

    return "update $mode ".$r->{name}.".".$r->{zone}." $r->{ttl} A $r->{address}\n";
}

sub zr_cname {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

    return "update $mode ".$r->{name}.".".$r->{zone}." $r->{ttl} CNAME $r->{address}\n";
}

sub zr_mx {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

    return "update $mode ".$r->{name}.".".$r->{zone}." $r->{ttl} MX $r->{weight} $r->{address}\n";
}

sub zr_txt {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

# BIND will croak if the length of the text record is longer than 255
    if ( length $r->{address} > 255 ) {
        $r->{address} = join( "\" \"", unpack("(a255)*", $r->{address} ) );
    };
# name  ttl  class   rr     text
    return "update $mode ".$r->{name}.".".$r->{zone}." $r->{ttl} TXT \"$r->{address}\"\n";
}

sub zr_ns {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

    my $name = $self->qualify( $r->{name} );
    $name .= '.' if '.' ne substr($name, -1, 1);

    return "update $mode $name $r->{ttl} NS $r->{address}\n";
}

sub zr_ptr {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

    return "update $mode ".$r->{name}.".".$r->{zone}." $r->{ttl} PTR $r->{address}\n";
}

sub zr_soa {
    my ($self, $z) = @_;
    #no real "soa" for an nsupdate - so lets set the server we want to update to instead
    return "server $z->{nsname}\n";
}

sub zr_spf {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

# SPF record support was added in BIND v9.4.0

# name  ttl  class  type  type-specific-data
    return "update $mode ".$r->{name}.".".$r->{zone}." $r->{ttl} SPF \"$r->{address}\"\n";
}

sub zr_srv {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

    my $priority = $self->{nte}->is_ip_port( $r->{priority} );
    my $weight   = $self->{nte}->is_ip_port( $r->{weight} );
    my $port     = $self->{nte}->is_ip_port( $r->{other} );

# srvce.prot.name  ttl  class   rr  pri  weight port target
    return "update $mode $r->{name} $r->{ttl} SRV $priority $weight $port $r->{address}\n";
}

sub zr_aaaa {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined($r->{zone});

# name  ttl  class  type  type-specific-data
    return "update $mode ".$r->{name}.".".$r->{zone}." $r->{ttl} AAAA $r->{address}\n";
}

sub zr_loc {
    my ($self, $r, $mode) = @_;
    $mode = "add" unless defined($mode);
    return "update $mode $r->{name} $r->{ttl} LOC $r->{address}\n";
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
