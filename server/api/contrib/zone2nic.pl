#!/usr/bin/perl -w

# =-=-=-=-=
# $Id: zone2nic,v 1.5 2006/04/08 01:12:22 monachus Exp $
#
# Script to load zones from axfr into NicTool
# Written by Adrian Goins <agoins@arces.net>
# Copyright 2006 by Arces Network, LLC
# =-=-=-=-=
# mps - 2011.11.13 - applied Pat Woo's patch: 
#   https://www.tnpi.net/support/forums/index.php/topic,632.0.html
#
# I should update this to use NicTool.pm instead of NicToolServerAPI.
# =-=-=-=-=

use strict;
use Net::DNS;
use Getopt::Long;
use NicToolServerAPI;
use Term::ReadKey;
use Data::Dumper;

use vars qw( $opts @zones $conf $servers );
use vars qw( $ntconf $nt $ntuser $resp $gid );

# *** Edit these to suit your environment.  If ntuser and ntpass are blank,
# *** it will ask for them at runtime.
$ntconf = { ntuser  =>  '',
            ntpass  =>  '',
            nthost  =>  '127.0.0.1',
            ntport  =>  8082,
            nt_transfer_protocol => 'http'
        };

# *** Stop editing now

$servers = "";
$| = 1;

my $result = GetOptions(
    'a|all' => \$opts->{a}, 
    'h|help' => \$opts->{h},
    'z|zone=s' => \$opts->{z},
    'f|file=s' => \$opts->{f},
    's|source=s' => \$opts->{s},
    'g|group=s' => \$opts->{g},
    'port=i' => \$opts->{port},
    'use-https' => \$opts->{secure},
    'destination=s' => \$opts->{destination},
    'user=s' => \$opts->{user});

if( $opts->{h} or ! ( $opts->{z} or $opts->{f} )) {
    &usage;
} elsif( $opts->{z} and $opts->{f} ) {
    print( "Only one of -z or -f is permitted.\n" );
    &usage;
}

$ntconf->{nthost} = $opts->{destination} if ( $opts->{destination});
$ntconf->{ntport} = $opts->{port} if ( $opts->{port});
$ntconf->{ntuser} = $opts->{user} if ( $opts->{user});
$ntconf->{nt_transfer_protocol} = 'https' if ( $opts->{secure});

# Get login information if not present
&getUser if( $ntconf->{ntuser} eq "" );
&getPass if( $ntconf->{ntpass} eq "" );

unless( $ntconf->{nthost} and $ntconf->{ntport} ) {
    print( "NicTool server and port not defined - please edit zone2nic before running.\n" );
    &usage;
}

# Set up the NicTool object
$nt = new NicToolServerAPI;
$NicToolServerAPI::server_host = $ntconf->{nthost};
$NicToolServerAPI::server_port = $ntconf->{ntport};
$NicToolServerAPI::transfer_protocol = $ntconf->{nt_transfer_protocol};
$NicToolServerAPI::data_protocol = "soap";

# Get a NicTool user object
$ntuser = $nt->send_request( 
        action   => "login",
        username => $ntconf->{ntuser},
        password => $ntconf->{ntpass},
    );

if( $ntuser->{error_code} ) {
    print( "Unable to log in: " . $ntuser->{error_code} . " " . $ntuser->{error_msg} . "\n" );
    exit 1;
} else {
    print( "Logged in as " . $ntuser->{first_name} . " " . $ntuser->{last_name} . "\n" );
}

# Get group data if we have it specifeid
if( $opts->{g} ) {
    $resp = $nt->send_request( 
        action => "get_group_subgroups",
        nt_user_session => $ntuser->{nt_user_session},
        nt_group_id => ( $ntuser->{nt_group_id} ),
        include_subgroups   => 1,
        search_value        => $opts->{g},
        quick_search        => 1,
    );

    if( @{$resp->{groups}} == 0 ) {
        warn( "*** Group " . $opts->{g} . " not found.\n\n" );
        exit 1;
    } elsif( @{$resp->{groups}} > 1 ) {
        warn( "*** Group parameter too vague - found more than one match.\n" );
        warn( "*** Please resubmit query.\n\n" );
        exit 1;
    } else {
        # There should be only one
        print( "Binding to group " . $resp->{groups}->[0]->{name} . "\n" );
        $gid = $resp->{groups}->[0]->{nt_group_id};
    }
} else {
    $gid = $ntuser->{nt_group_id};
}


$resp = $nt->send_request( 
    action      => "get_usable_nameservers",
    nt_user_session => $ntuser->{nt_user_session},
    nt_group_id => ( $gid ),
);

if( @{$resp->{nameservers}} == 0 ) {
    # No nameservers
    warn( "*** You don't have any nameservers defined in NicTool.\n" );
    warn( "*** Please define nameservers first.\n\n" );
    exit 1;
}

foreach( @{$resp->{nameservers}} ) {
    # Don't add the default nameservers
    next if( $_->{name} =~ /nictool.com/ );

    if( $opts->{a} ) {
        $servers .= $_->{nt_nameserver_id};
    } else {
        print( "Bind to " . $_->{name} . "? [y] " );
        ReadMode( 'cbreak' );
        my $yn = ReadKey(0);
        chomp( $yn );
        ReadMode( 'normal' );
        print( "$yn\n" );
        if( $yn eq "" or $yn =~ /^[Yy]/) {
            $servers .= $_->{nt_nameserver_id};
        } else {
            print( "Skipping " . $_->{name} . "\n" );
        }
    }
    $servers .= "," if( $servers ne "" and $servers !~ /,$/ );
}

if( $servers eq "" ) {
    # If we're here, it means that nameservers exist, but that they 
    # have 'nictool.com' in their definition.  These are probably
    # the default nameservers and should be removed.
    warn( "*** You appear to only have the default NicTool nameservers.\n" );
    warn( "*** Please remove these and add your own nameservers first.\n\n" );
    exit 1;
}

# Create the list of zones to operate on
push( @zones, $opts->{z} ) if( $opts->{z} );
&readZones if( $opts->{f} );

# Do something with our zones
foreach my $zone ( @zones ) {
    my @ns;
    my $records = 0;
    my $dns = Net::DNS::Resolver->new;

    # Standardize on no trailing dot
    $zone =~ s/\.$//;

    # If we don't have a server to query provided on the command
    # line - go get the nameserver list for the zone
    if( $opts->{s} ) {
        push( @ns, $opts->{s} );
    } else {
        my $packet = $dns->query( $zone, 'NS' );
        my @rr = $packet->answer;
        foreach my $rr ( @rr ) {
            push( @ns, $rr->nsdname );
        }
    }

    $dns = Net::DNS::Resolver->new( 
        nameservers => \@ns,
    );

    # Do the transfer
    my @zoneinfo = $dns->axfr( $zone );

    if( @zoneinfo ) {
        # Get the SOA
        my $soa = ($dns->query( $zone, "SOA" )->answer)[0];
        my $zoneid;

        # Start doing the work
        print( "Importing $zone:\n" );

        # See if this zone already exists
        $resp = $nt->send_request( 
            action              => "get_group_zones",
            nt_user_session     => $ntuser->{nt_user_session},
            nt_group_id         => ( $gid ),
            include_subgroups   => 1,
            Search              => 1,
            '1_field'           => "zone",
            '1_option'          => "equals",
            '1_value'           => $zone
        );

        if( &checkResponse( $resp )) {
            # Zone might exist - search always returns OK
            if( $resp->{total} == 1 ) {
                print( "\tZone $zone exists - deleting.\n" );
                $resp = $nt->send_request(
                    action          => "delete_zones",
                    nt_user_session => $ntuser->{nt_user_session},
                    zone_list       => $resp->{zones}->[0]->{nt_zone_id},
                );

                if( &checkResponse( $resp )) {
                    print( "\tZone $zone deleted.\n" );
                } else {
                    warn( "\t*** Failed to delete zone $zone: " . $resp->{error_desc} . " : " . $resp->{error_msg} . "\n" );
                    warn( "\t*** Skipping to next zone.\n" );
                    next;
                }
            } 

        } else {
            # Something was wrong with the search
            warn( "\t*** Failed searching for zone $zone: " . $resp->{error_desc} . " : " . $resp->{error_msg} . "\n" );
        }

        # Add it up!
        $resp = $nt->send_request(
            action          => "new_zone",
            nt_user_session => $ntuser->{nt_user_session},
            nt_zone_id      => undef,
            zone            => $zone,
            nt_group_id     => $gid,
            ttl             => ( $soa->ttl < 300 ? 300 : $soa->ttl ),
            serial          => $soa->serial,
            nameservers     => $servers,
            mailaddr        => $soa->rname,
            refresh         => $soa->refresh,
            retry           => $soa->retry,
            expire          => $soa->expire,
            minimum         => $soa->minimum,
        );

        if( !&checkResponse( $resp )) {
            warn( "\t*** Failed to create $zone: " . $resp->{error_desc} . " : " . $resp->{error_msg} . "\n" );
            next;
        } else {
            $zoneid = $resp->{nt_zone_id};
            print( "\tZone created: $zoneid\n" );
        }

        # Go on to add records to the new zone
        foreach my $rr ( @zoneinfo ) {

            # Sanitize the TTL so NicTool doesn't freak out
            if( $rr->ttl < 300 ) {
                print( "\t*** Raising TTL on " . $rr->name . " from " . $rr->ttl . " to 300\n" );
            }

            # Turn name from fqdn back to hostname
            my $name = $rr->name;
            $name =~ s/\.?$zone\.?//;
            $name = '@' if( $name eq "" );

            if( $rr->type eq "A" || $rr->type eq "AAAA" ) {
                $resp = $nt->send_request(
                    action              => "new_zone_record",
                    nt_user_session     => $ntuser->{nt_user_session},
                    nt_zone_id          => $zoneid,
                    nt_zone_record_id   => undef,
                    name                => $name,
                    ttl                 => ( $rr->ttl < 300 ? 300 : $rr->ttl ),
                    type                => $rr->type,
                    address             => $rr->address,
                );
            } elsif( $rr->type eq "NS" ) {
                # Nameservers for the default domain are added
                # by NicTool - don't add them here.
                next if( $name eq '@' );

                $resp = $nt->send_request(
                    action              => "new_zone_record",
                    nt_user_session     => $ntuser->{nt_user_session},
                    nt_zone_id          => $zoneid,
                    nt_zone_record_id   => undef,
                    name                => $name,
                    ttl                 => ( $rr->ttl < 300 ? 300 : $rr->ttl ),
                    type                => $rr->type,
                    address             => $rr->nsdname . ".",
                );
            } elsif( $rr->type eq "CNAME" ) {
                $resp = $nt->send_request(
                    action              => "new_zone_record",
                    nt_user_session     => $ntuser->{nt_user_session},
                    nt_zone_id          => $zoneid,
                    nt_zone_record_id   => undef,
                    name                => $name,
                    ttl                 => ( $rr->ttl < 300 ? 300 : $rr->ttl ),
                    type                => $rr->type,
                    address             => $rr->cname . ".",
                );
            } elsif( $rr->type eq "TXT" ) {
                $resp = $nt->send_request(
                    action              => "new_zone_record",
                    nt_user_session     => $ntuser->{nt_user_session},
                    nt_zone_id          => $zoneid,
                    nt_zone_record_id   => undef,
                    name                => $name,
                    ttl                 => ( $rr->ttl < 300 ? 300 : $rr->ttl ),
                    type                => $rr->type,
                    address             => join( " ", $rr->char_str_list()),
                );
            } elsif( $rr->type eq "MX" ) {
                $resp = $nt->send_request(
                    action              => "new_zone_record",
                    nt_user_session     => $ntuser->{nt_user_session},
                    nt_zone_id          => $zoneid,
                    nt_zone_record_id   => undef,
                    name                => $name,
                    ttl                 => ( $rr->ttl < 300 ? 300 : $rr->ttl ),
                    type                => $rr->type,
                    address             => $rr->exchange . ".",
                    weight              => $rr->preference,
                );
            } elsif( $rr->type eq "PTR" ) {
                $resp = $nt->send_request(
                    action              => "new_zone_record",
                    nt_user_session     => $ntuser->{nt_user_session},
                    nt_zone_id          => $zoneid,
                    nt_zone_record_id   => undef,
                    name                => $name,
                    ttl                 => ( $rr->ttl < 300 ? 300 : $rr->ttl ),
                    type                => $rr->type,
                    address             => $rr->ptrdname . ".",
                );
            }

            if( !&checkResponse( $resp )) {
                warn( "\t*** Failed to add record " . $rr->name . ": " . $resp->{error_desc} . " : " . $resp->{error_msg} . "\n" );
            } else {
                $records++;
            }
        }
        print( "Zone $zone complete: $records added.\n\n" );
    } else {
        print( "\t*** Transfer of $zone failed: " . $dns->errorstring . "\n" );
    }
}

sub usage {
    print( "Usage:  zone2nic { -z zone | -f file | -h } [ -s server ] [ -a ] [ -g group ]\n" );
    print( "\t-z, --zone :\t\tName of zone to import\n" );
    print( "\t-h, --help :\t\tDisplay this help\n" );
    print( "\t-f, --file :\t\tFile with zones, one per line\n" );
    print( "\t-s, --source :\t\tNameserver to query - pulls from zone if missing.\n" );
    print( "\t-a, --all :\t\tBind to all NicTool nameservers\n" );
    print( "\t-g, --group :\t\tGroup to insert zones into\n" );
    print( "\t--destination :\tNictool server\n" );
    print( "\t--port :\t\tNictool server port\n" );
    print( "\t--user :\t\t\tNictool user\n" );
    print( "\t--use-https :\tUse https towards Nictool server\n" );
    print( "\n" );
    exit 1;
}

sub readZones {
    my $file = $opts->{f};

    unless( -f $file ) {
        print( STDERR "ERROR:  Can't read $file!\n" );
        &usage;
    }

    open( IN, $file ) || die( "Can't open $file: $!\n" );
    while( my $line = <IN> ) {
        chomp( $line );
        $line =~ s/\s+$//;  # Strip trailing whitespace
        next if( $line =~ /^#/ );
        next if( $line =~ /^$/ );
        push( @zones, $line );
    }
    close( IN );
}

sub getUser {
    print( "NicTool Username: " );
    my $user = ReadLine(0);
    chomp $user;
    if( $user eq "" ) {
        print( "Exiting.\n" );
        exit 1;
    } else {
        $ntconf->{ntuser} = $user;
    }
}

sub getPass {
    print( "NicTool Password: " );
    ReadMode( 'noecho' );
    my $pass = ReadLine(0);
    chomp( $pass );
    ReadMode( 'normal' );
    print( "\n" );
    $ntconf->{ntpass} = $pass;
}

sub checkResponse {
    my $resp = shift;

    if( $resp->{error_msg} ne "OK" ) {
        warn( $resp->{error_code} . " - " . $resp->{error_desc} . ": " . $resp->{error_msg} . "\n" );
        return 0;
    }

    return 1;
}

