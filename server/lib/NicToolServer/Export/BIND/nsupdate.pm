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

sub postflight {
    my $self = shift;
    my $dir = shift || $self->{nte}->get_export_dir or return;

    my $nsupdate = "";

    build_nsupdate( $self, $dir );

    # Uncomment out the following to automatically load the nsupdate
    # Export to the DNS server via nsupdate
    #$nsupdate = `nsupdate < $dir/nsupdate.log 2<&1`;

    # Uncomment this if you would like to do nsupdate with a keyfile
    # For more info go to https://github.com/msimerson/NicTool/wiki/Export-to-BIND-nsupdate
    #my $keyfile = "/etc/Knsupdate.+157+44682.key";
    #$nsupdate = `nsupdate -k $keyfile < $dir/nsupdate.log 2<&1`;

    if ( $nsupdate =~ m/BADKEY/ )
    {
        $self->{nte}->set_status("last: FAILED, reason: BADKEY");
        $self->{nte}->elog("nsupdate FAILED, reason: BADKEY", success=>0);
        exit 0;
    }  
    elsif ( $nsupdate =~ m/could\snot\sread\skey\*file\s\not\sfound/ )
    {
        $self->{nte}->set_status("last: FAILED, reason: Keyfile not found");
        $self->{nte}->elog("nsupdate FAILED, reason: Keyfile not found", success=>0);
        exit 0;
    }  
    elsif ( $nsupdate =~ m/REFUSED/ )
    {
        $self->{nte}->set_status("last: FAILED, reason: REFUSED");
        $self->{nte}->elog("nsupdate FAILED, reason: REFUSED", success=>0);
        exit 0;
    } 
    elsif ( $nsupdate =~ m/NOTZONE/ || $nsupdate =~ m/enclosing\szone/ ) 
    {
        $self->{nte}->set_status("last: FAILED, reason: NOTZONE");
        $self->{nte}->elog("nsupdate FAILED, reason: NOTZONE", success=>0);
        exit 0;
    } 
    elsif ( $nsupdate =~ m/Communication\swith.*failed/ || $nsupdate =~ m/timed\sout/ || $nsupdate =~ m/could\snot\stalk/ ) 
    {
        $self->{nte}->set_status("last: FAILED, reason: TIMEOUT");
        $self->{nte}->elog("nsupdate FAILED, reason: TIMEOUT", success=>0);
        exit 0;
    } 
    elsif ( $nsupdate =~ m/NOTAUTH/ )
    {
        $self->{nte}->set_status("last: FAILED, reason: NOTAUTH");
        $self->{nte}->elog("nsupdate FAILED, reason: NOTAUTH", success=>0);
        exit 0;
    }
    
    return 1;
}

sub build_nsupdate {
    my ( $self, $dir ) = @_;

    my @results = get_log( $self, $dir );
    my $ns = "";

    # open the nsupdate log file
    open FILE, "+>", "$dir/nsupdate.log" or die $!;

    foreach my $record (@results) {
        my @zone_records = get_zone_record( $self, $record->{object_id} );
        my $r            = $zone_records[0];
        my $mode         = "add";

        # check if its a delete action
        if ( $record->{description} =~ m/deleted\srecord/ ) {
            $mode = "delete";
        }

        # check if its a modify on name or address
        # TODO - confirm nsupdate removal with full details doesnt remove any round robin entries with the same name but a different IP
        if ( $record->{description} =~ m/changed\sname\sfrom\s\'((\w|\.|\:|\-)*)\'\s/ )
        {

            # Found a changed DNS name - pull delete name from desc
            my $old_name = $1;

            # Deref the $r hash and copy it, then create a new reference for use here
            my %old_hash = %{$r};
            my $old      = \%old_hash;

            # Overwrite the original name in the hashref with the replacement older name to delete
            $old->{name} = $old_name;

            # check if the IP has changed as well
            # If it hasnt, just use the address from given details in record that is already there
            # Make sure if its a TXT file to accept other characters we might not otherwise have allowed
            if ( $record->{description} =~ m/changed\saddress\sfrom\s\'((\w|\:|\.|\-)*)\'\s/ || ($record->{description} =~ m/changed\saddress\sfrom\s\'(.*)\'\s/ && $r->{"type"} eq "TXT"))
            {

                #Found a changed address as well, pull old address to delete from desc
                $old->{address} = $1;
            }

            # If the current name server doesnt match last time, set a new server in the nsupdate file
            if ( $ns !~ m/$self->{nte}->{ns_ref}->{name}/i ) {
                print FILE $self->zr_soa( $self, $old );
            }
            $mode = "delete";
            my $method = 'zr_' . lc $old->{type};
            $old->{location} ||= '';
            print FILE $self->$method( $old, $mode );
            print FILE "send\n";

            $mode = "add";
        }
        elsif ( $record->{description} =~ m/changed\saddress\sfrom\s\'((\w|\:|\.|\-)*)\'\s/ || ($record->{description} =~ m/changed\saddress\sfrom\s\'(.*)\'\s/ && $r->{"type"} eq "TXT"))
        {

            # Just found an IP change - need to remove the old IP entry
            my $old_ip = $1;

            # Deref the $r hash and copy it, then create a new reference for use here
            my %old_hash = %{$r};
            my $old      = \%old_hash;

            $old->{address} = $old_ip;

            # If the current name server doesnt match last time, set a new server in the nsupdate file
            if ( $ns !~ m/$self->{nte}->{ns_ref}->{name}/i ) {
                print FILE $self->zr_soa( $self, $old );
            }

            $mode = "delete";
            my $method = 'zr_' . lc $old->{type};
            $old->{location} ||= '';
            print FILE $self->$method( $old, $mode );
            print FILE "send\n";

            $mode = "add";
        }
        elsif ( $record->{description} =~ m/changed\stimestamp/ ) {

            # on just a timestamp change - dont bother generating any entries
            next;
        }

# Now that we are done (potentially) cleaning up old changes, lets move onto the main change
# If the current name server doesnt match last time, set a new server in the nsupdate file
        if ( $ns !~ m/$self->{nte}->{ns_ref}->{name}/i ) {
            print FILE $self->zr_soa( $self, $r );
        }
        my $method = 'zr_' . lc $r->{type};
        $r->{location} ||= '';
        print FILE $self->$method( $r, $mode );
        print FILE "send\n";

        # load the current nameserver into ns for checking next loop
        $ns = $self->{nte}->{ns_ref}->{name};
    }

    close FILE or die $!;
}

sub get_log {
    my ( $self, $dir ) = @_;

    my $dbix_w = $self->{nte}->{dbix_w};
    my $ns_id = $self->{nte}->{ns_ref}->{nt_nameserver_id};
    my $time   = time - 300;

    my $sql = "SELECT * FROM nictool.nt_user_global_log WHERE timestamp > (SELECT UNIX_TIMESTAMP(date_start) FROM nt_nameserver_export_log WHERE success=1 AND nt_nameserver_id=$ns_id ORDER BY date_start DESC LIMIT 1) AND object IN ('zone','zone_record')";

    return $dbix_w->query($sql)->hashes;
}

sub get_zone_record {
    my ( $self, $id ) = @_;
    my $dbix_w = $self->{nte}->{dbix_w};
    my $time   = time - 1800;

    my $sql = "SELECT r.name, r.ttl, r.description, t.name AS type, r.address, r.weight,
    r.priority, r.other, r.location, z.zone
    from nt_zone_record r
    LEFT JOIN resource_record_type t ON t.id=r.type_id
    LEFT JOIN nt_zone z ON r.nt_zone_id=z.nt_zone_id
    where r.nt_zone_record_id = $id";

    return $dbix_w->query($sql)->hashes;
}

sub get_changed_zones {
    my ( $self, $dir ) = @_;
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my %has_changes;
    foreach my $zone ( $self->{nte}->zones_exported ) {
        my $tmpl = $self->get_template( $dir, $zone );
        if ($tmpl) {
            $has_changes{$zone} = $tmpl;
            next;
        }
        $has_changes{$zone}
            = qq[zone "$zone"\t IN { type master; file "$datadir/$zone"; };\n];
    }
    return \%has_changes;
}

sub zr_a {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    return
          "update $mode "
        . $r->{name}
        . (substr($r->{name}, -1, 1) eq '.' ? '' : '.' . $r->{zone})
        . " $r->{ttl} A $r->{address}\n";
}

sub zr_cname {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    return
          "update $mode "
        . $r->{name}
        . (substr($r->{name}, -1, 1) eq '.' ? '' : '.' . $r->{zone})
        . " $r->{ttl} CNAME $r->{address}\n";
}

sub zr_mx {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    return
          "update $mode "
        . $r->{name}
        . (substr($r->{name}, -1, 1) eq '.' ? '' : '.' . $r->{zone})
        . " $r->{ttl} MX $r->{weight} $r->{address}\n";
}

sub zr_txt {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    # BIND will croak if the length of the text record is longer than 255
    if ( length $r->{address} > 255 ) {
        $r->{address} = join( "\" \"", unpack( "(a255)*", $r->{address} ) );
    }

    # name  ttl  class   rr     text
    return
          "update $mode "
        . $r->{name}
        . (substr($r->{name}, -1, 1) eq '.' ? '' : '.' . $r->{zone})
        . " $r->{ttl} TXT \"$r->{address}\"\n";
}

sub zr_ns {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    my $name = $r->{name};
    $name .= '.' if '.' ne substr( $name, -1, 1 );

    return "update $mode $name"."$r->{zone} $r->{ttl} NS $r->{address}\n";
}

sub zr_ptr {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    return
          "update $mode "
        . $r->{name} . "."
        . $r->{zone}
        . " $r->{ttl} PTR $r->{address}\n";
}

sub zr_soa {
    my ( $self, $z ) = @_;

#no real "soa" for an nsupdate - so lets set the server we want to update to instead
    $z->{nsname} = $self->{nte}->{ns_ref}->{name}
        unless defined( $z->{nsname} );
    return "server $z->{nsname}\n";
}

sub zr_spf {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    # SPF record support was added in BIND v9.4.0

    # name  ttl  class  type  type-specific-data
    return
          "update $mode "
        . $r->{name}
        . (substr($r->{name}, -1, 1) eq '.' ? '' : '.' . $r->{zone})
        . " $r->{ttl} SPF \"$r->{address}\"\n";
}

sub zr_srv {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    my $priority = $self->{nte}->is_ip_port( $r->{priority} );
    my $weight   = $self->{nte}->is_ip_port( $r->{weight} );
    my $port     = $self->{nte}->is_ip_port( $r->{other} );

    # srvce.prot.name  ttl  class   rr  pri  weight port target
    return
          "update $mode "
        . $r->{name}
        . (substr($r->{name}, -1, 1) eq '.' ? '' : '.' . $r->{zone})
        . " $r->{ttl} SRV $priority $weight $port $r->{address}\n";
}

sub zr_aaaa {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{zone} = $self->{nte}->{zone_name} unless defined( $r->{zone} );

    # name  ttl  class  type  type-specific-data
    return
          "update $mode "
        . $r->{name}
        . (substr($r->{name}, -1, 1) eq '.' ? '' : '.' . $r->{zone})
        . " $r->{ttl} AAAA $r->{address}\n";
}

sub zr_loc {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    return "update $mode $r->{name} $r->{ttl} LOC $r->{address}\n";
}

sub zr_naptr {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);

    # http://www.ietf.org/rfc/rfc2915.txt
    # https://www.ietf.org/rfc/rfc3403.txt

    my $order = $self->{nte}->is_ip_port( $r->{weight} );
    my $pref  = $self->{nte}->is_ip_port( $r->{priority} );
    my ( $flags, $service, $regexp ) = split /" "/, $r->{address};
    $regexp =~ s/"//g;    # strip off leading "
    $flags  =~ s/"//g;    # strip off trailing "
    my $replace = $r->{description};
    $regexp =~ s/\\/\\\\/g;    # escape any \ characters

    # Domain TTL Class Type Order Preference Flags Service Regexp Replacement
    return
        qq[update $mode $r->{name} $r->{ttl} NAPTR $order $pref "$flags" "$service" "$regexp" $replace\n];
}

sub zr_dname {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);

    # name  ttl  class   rr     target
    return "update $mode $r->{name} $r->{ttl} DNAME $r->{address}\n";
}

sub zr_sshfp {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);

    my $algo = $r->{weight};      #  1=RSA,   2=DSS,     3=ECDSA
    my $type = $r->{priority};    #  1=SHA-1, 2=SHA-256
    return
        "update $mode $r->{name} $r->{ttl} SSHFP $algo $type $r->{address}\n";
}

sub zr_ipseckey {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);

    my $precedence = $r->{weight};
    my $gw_type    = $r->{priority};
    my $algorithm  = $r->{other};
    my $gateway    = $r->{address};
    my $public_key = $r->{description};

    return
        "update $mode $r->{name} $r->{ttl} IPSECKEY ( $precedence $gw_type $algorithm $gateway $public_key )\n";
}

sub zr_dnskey {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);

    my $flags     = $r->{weight};
    my $protocol  = $r->{priority};    # always 3, RFC 4034
    my $algorithm = $r->{other};

    # 1=RSA/MD5, 2=Diffie-Hellman, 3=DSA/SHA-1, 4=Elliptic Curve, 5=RSA/SHA-1

    return
        "update $mode $r->{name} $r->{ttl} DNSKEY $flags $protocol $algorithm $r->{address}\n";
}

sub zr_ds {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);

    my $key_tag   = $r->{weight};
    my $algorithm = $r->{priority};    # same as DNSKEY algo -^
    my $digest_type = $r->{other};  # 1=SHA-1 (RFC 4034), 2=SHA-256 (RFC 4509)

    return
        "update $mode $r->{name} $r->{ttl} DS $key_tag $algorithm $digest_type $r->{address}\n";
}

sub zr_rrsig {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);

    return "update $mode $r->{name} $r->{ttl} RRSIG $r->{address}\n";
}

sub zr_nsec {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    $r->{description} =~ s/[\(\)]//g;
    return "update $mode $r->{name} $r->{ttl} NSEC $r->{address} ( $r->{description} )\n";
}

sub zr_nsec3 {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    return "update $mode $r->{name} $r->{ttl} NSEC3 $r->{address}\n";
}

sub zr_nsec3param {
    my ( $self, $r, $mode ) = @_;
    $mode = "add" unless defined($mode);
    return "update $mode $r->{name} $r->{ttl} NSEC3PARAM $r->{address}\n";
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::BIND::nsupdate - exporting DNS data to authoritative DNS servers

=head1 VERSION

version 2.33

=head1 SYNOPSIS

Export DNS information from NicTool as BIND zone updates. These exports are suitable for any running DNS server that accepts nsupdate inserted entries.
The exports are done as both a full kickstart for each zone file, as well as a delta since the last run (nsupdate.log) which can be inserted each run to ensure zones are updated with the latest changes

=head1 NAME

NicToolServer::Export::BIND::nsupdate

=head1 nsupdate.log

This class will export a nsupdate.log file with only the changes that have occured since the last run. This file should be injected into the named server using nsupdate and is currently set up to not use a key (use IP restrictions to secure your dynamic updates)

A key secured method will be added at a later date.

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
