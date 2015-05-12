#!/usr/bin/perl -w

# =-=-=-=-=
# $Id: addserver,v 1.2 2006/04/01 18:43:33 monachus Exp $
#
# Script to add server to a zone or group of zones
#
# Written by Adrian Goins <agoins@arces.net>
# Copyright 2006 by Arces Network, LLC
# =-=-=-=-=

use strict;
use Getopt::Std;
use NicToolServerAPI;
use Term::ReadKey;

use vars qw( $opts $sid @zones @zonenames );
use vars qw( $ntconf $nt $ntuser $resp );

# *** Edit these to suit your environment.  If ntuser and ntpass are blank,
# # *** it will ask for them at runtime.
$ntconf = { ntuser  => '', 
            ntpass  => '',
            nthost  => '127.0.0.1',
            ntport  => 8082,
          };

# *** Stop editing now

$| = 1;
$sid = "";

getopts( 'prahz:s:', \%{$opts} );

if( $opts->{h} ) {
    &usage;
} elsif( $opts->{a} and $opts->{z} ) {
    print( "Only one of -z or -a is permitted.\n" );
    &usage;
} elsif( ! $opts->{a} and ! $opts->{z} ) {
    &usage;
} elsif( ! $opts->{s} ) {
    &usage;
}

$opts->{s} .= "." if( $opts->{s} !~ /\.$/ );

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
$NicToolServerAPI::data_protocol = "soap";
$NicToolServerAPI::use_https_authentication = 0;

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

$resp = $nt->send_request( 
    action      => "get_group_nameservers",
    nt_user_session => $ntuser->{nt_user_session},
    nt_group_id => ( $ntuser->{nt_group_id} ),
    include_subgroups => 1,
);

if( $resp->{total} == 0 ) {
    # No nameservers
    warn( "*** You don't have any nameservers defined in NicTool.\n" );
    warn( "*** Please define nameservers first.\n\n" );
    exit 1;
}

foreach( @{$resp->{list}} ) {
    $sid = $_->{nt_nameserver_id} if( $opts->{s} eq $_->{name} );
}

if( $sid eq "" ) {
    warn( "*** Nameserver not found.\n" );
    exit 1;
}

# We have a nameserver - let's stick it on a zone

if( $opts->{f} ) {
    # Load whatever is in this file
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
        push( @zonenames, $line );
    }
    close( IN );
} else {
    push( @zonenames, $opts->{z} );
}

# Load all of the zones
$resp = $nt->send_request( 
    action  => "get_group_zones",
    nt_user_session => $ntuser->{nt_user_session},
    nt_group_id => ( $ntuser->{nt_group_id} ),
    include_subgroups => 1,
    limit => 1000,
);

if( &checkResponse( $resp )) {
    if( $resp->{total} > 0 ) {
        # We've got zones....
        foreach my $z ( @{$resp->{zones}} ) {
            if( $opts->{a} ) {
                push( @zones, $z );
            } else {
                foreach ( @zonenames ) {
                    push( @zones, $z ) if( $z->{zone} =~ /$_/ );
                }
            }
        }
    } else {
        warn( "*** No zones found.\n" );
    }
}

if( @zones == 0 ) {
    warn( "*** No zones found.\n" );
    exit 1;
}

foreach my $zone ( @zones ) {
    my @servers;
    my $serial;

    # Change the nameserver
    unless( $opts->{a} ) {
        # If we're not globally changing, bail if we're not
        # the zone we want (or a regex)
        my $regex = $opts->{z};
        $regex = "^" . $regex . "\$" unless( $opts->{p} );
        next unless( $zone->{zone} =~ /$regex/ );
    } 

    # Still here?  Change it up
    my $resp = $nt->send_request( 
        action  => "get_zone",
        nt_user_session => $ntuser->{nt_user_session},
        nt_zone_id => $zone->{nt_zone_id},
        nt_group_id => $zone->{nt_group_id},
    );

    if( &checkResponse( $resp )) {
        foreach my $ns ( @{$resp->{nameservers}} ) {
            push( @servers, $ns->{nt_nameserver_id} ) unless( $ns->{nt_nameserver_id} == $sid );
        }
        $serial = $resp->{serial};

    } else {
        warn( "*** Unable to load zone.\n" );
        exit 1;
    }

    push( @servers, $sid ) unless( $opts->{r} );

    $resp = $nt->send_request(
        action  => "edit_zone",
        nt_user_session => $ntuser->{nt_user_session},
        nt_zone_id => $zone->{nt_zone_id},
        nt_group_id => $zone->{nt_group_id},
        nameservers => join( ",", @servers ),
        serial => $serial + 1,
    );

    if( &checkResponse( $resp )) {
        print( "Zone " . $zone->{zone} . " changed.\n" );
    }
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

sub usage {
    print( "Usage:  addserver { -a | -z zone | -f file } [ -r ] [ -h ] -s server\n" );
    print( "\t-z : Name of zone to change\n" );
    print( "\t-a : Change all zones\n" );
    print( "\t-f : File with zones, one per line\n" );
    print( "\t-s : Nameserver to add\n" );
    print( "\t-p : -s is a regex\n" );
    print( "\t-r : Remove it instead of adding it\n" );
    print( "\t-h : Display this help\n" );
    print( "\n" );  
    exit 1;
}               

