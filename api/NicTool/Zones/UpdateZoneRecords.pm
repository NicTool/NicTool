#!/usr/bin/perl

package NicTool::Zones::UpdateZoneRecords;

require Exporter;
@NicTool::Zones::UpdateZoneRecords::ISA     = qw(Exporter);
@NicTool::Zones::UpdateZoneRecords::EXPORT  = qw(update_zone_records);
$NicTool::Zones::UpdateZoneRecords::VERSION = 1.00;

# Zones::UpdateZoneRecords.pm by Matt Simerson <msimerson@interland.com>
#
# ChangeLog
#  10.03.2004 - Matt - Integrated with NicTool
#  02.17.2003 - Matt - Prototyped subroutine
#  05.09.2002 - Matt - Removed from zones.pl

use strict;

use lib "../../";
use NicTool;
use NicTool::Zones::Templates;

sub update_zone_records($$$$$$$$$;$) {
    my ($nt,    $rec,    $zid,   $zone,  $template,
        $newip, $mailip, $oldip, $debug, $last_octet
    ) = @_;

    my %zone_record;
    my $updated = "n";
    print "update_zone_records: $zid, $zone, $template, $last_octet\n"
        if ($debug);

    if ( $template ne "" ) {
        my $new = zone_record_template( $zid, $zone, $template, $last_octet,
            $newip, $mailip, $debug );

  # we'll get back an array of hashes: nt_zone_id, name, type, address, weight

        # next we'll iterate over each new record to create and check to see
        #  if there isn't an existing record to update first

        for ( my $i = 0; $i < scalar( @{$new} ); $i++ ) {
            for ( my $old = 0; $old < scalar( @{$rec} ); $old++ ) {
                if (   $rec->[$old]->{'type'} eq $new->[$i]->{'type'}
                    && $rec->[$old]->{'name'} eq $new->[$i]->{'name'} )
                {
                    print
                        "updating: $rec->[$old]->{'nt_zone_id'}, $rec->[$old]->{'name'}, $rec->[$old]->{'type'} from $rec->[$old]->{'address'} to $new->[$i]->{'address'}\n"
                        if ($debug);
                    %zone_record = (
                        nt_zone_record_id =>
                            $rec->[$old]->{'nt_zone_record_id'},
                        nt_zone_id  => $new->[$i]->{'nt_zone_id'},
                        name        => $new->[$i]->{'name'},
                        ttl         => "3600",
                        type        => $new->[$i]->{'type'},
                        address     => $new->[$i]->{'address'},
                        weight      => $new->[$i]->{'weight'},
                        description => $rec->[$old]->{'description'}
                    );
                    my $r = $nt->edit_zone_record(%zone_record);
                    if ( $r->{'error_code'} ne "200" ) {
                        print
                            "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
                    }
                    $updated = "y";
                    $old     = "100000";
                }
                else {
                    print
                        "No match: $new->[$i]->{'type'}, $new->[$i]->{'name'} !=  $rec->[$old]->{'type'}, $rec->[$old]->{'name'}\n"
                        if ($debug);
                    $updated = "n";
                }
            }
            if ( $updated ne "y" ) {
                %zone_record = (
                    nt_zone_id => $new->[$i]->{'nt_zone_id'},
                    name       => $new->[$i]->{'name'},
                    type       => $new->[$i]->{'type'},
                    address    => $new->[$i]->{'address'},
                    weight     => $new->[$i]->{'weight'}
                );
                print
                    "update_zone_record: $new->[$i]->{'name'}, $new->[$i]->{'type'}, $new->[$i]->{'address'}, $new->[$i]->{'weight'}\n"
                    if ($debug);
                my $r = $nt->new_zone_record(%zone_record);
                if ( $r->{'error_code'} ne "200" ) {
                    print
                        "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
                }
            }
        }

    }
    else {
        for ( my $i = 0; $i < scalar( @{$rec} ); $i++ ) {
            print
                "update_zone_records: $rec->[$i]->{'name'}, $rec->[$i]->{'type'}, $rec->[$i]->{'address'}\n"
                if ($debug);
            if ( $rec->[$i]->{'type'} eq "A" ) {
                if (   $rec->[$i]->{'name'} eq "mail"
                    && $rec->[$i]->{'address'} eq $oldip
                    && $mailip ne "" )
                {
                    &edit_zone_record(
                        $rec->[$i]->{'nt_zone_record_id'},
                        $zid,
                        $rec->[$i]->{'name'},
                        $mailip,
                        $rec->[$i]->{'type'},
                        $rec->[$i]->{'weight'}
                    );
                }
                elsif ( $rec->[$i]->{'address'} eq $oldip ) {
                    &edit_zone_record(
                        $rec->[$i]->{'nt_zone_record_id'},
                        $zid,
                        $rec->[$i]->{'name'},
                        $newip,
                        $rec->[$i]->{'type'},
                        $rec->[$i]->{'weight'}
                    );
                }
                else {
                    print
                        "didn't match record: $rec->[$i]->{'nt_zone_record_id'} on zone $zone. \n";
                }
            }
            elsif ( $rec->[$i]->{'type'} eq "MX" ) {
                if (   $rec->[$i]->{'name'} eq "$zone\."
                    && $rec->[$i]->{'address'} eq "mail.$zone\." )
                {
                    print "mx for $zone is ok\n";
                }
                elsif ($rec->[$i]->{'name'} eq "$zone\."
                    && $rec->[$i]->{'address'} eq $oldip )
                {
                    print
                        "WARNING: mx record must be a FQDN (see RFC 1035) - updated from $rec->[$i]->{'address'} to mail\.$zone\.\n";
                    &edit_zone_record(
                        $rec->[$i]->{'nt_zone_record_id'},
                        $zid,
                        $rec->[$i]->{'name'},
                        "mail\.$zone\.",
                        $rec->[$i]->{'type'},
                        $rec->[$i]->{'weight'}
                    );
                }
                else {
                    print "WARNING: mx for $zone is unverified\n";
                }
            }
        }
    }
}

1;
__END__

