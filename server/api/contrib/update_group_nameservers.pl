#!/usr/bin/perl

# Script to update the nameservers within subgroups to use all the nameservers
# defined within that group.
#
# v 1.0  2011.11.28 - mps
#
# By Matt Simerson <matt@tnpi.net>
# Copyright 2011 by The Network People, Inc.

use Data::Dumper;
use lib 'lib';
use NicTool;

my $user = new NicTool(
    data_protocol => 'soap',
    server_host   => '127.0.0.1',       # you may need to edit these
    server_port   => '8082',
);
$user->login( 
    username => ask("your nictool username"),
    password => ask("your nictool password",1),
);
die $user->error_msg if $user->is_error;
print "\n";

$user->verify_session;
die $user->error_msg if $user->is_error;

my $group_id = 5;

#get a list of subgroups within subgroup 5
my $sublist = $user->get_group->get_group_subgroups( nt_group_id => $group_id );
die $sublist->error_msg if $sublist->is_error;
if ( $sublist->size == 0 ) {
    print "no subgroups found in group ID $group_id";
    exit;
};

foreach my $group_ref ( $sublist->list ) {

    my $sub_gid = $group_ref->get('nt_group_id');
    defined $sub_gid or die $group_ref->error_msg;
    print "gid: $sub_gid\n";

    # get a list of the nameservers in the subgroup
    my $nslist = $user->get_group->get_group_nameservers(nt_group_id => $sub_gid );
    die $nslist->error_msg if $nslist->is_error;

    # concatenate the nameserver IDs into a string. ex: 1,3,5
    my @nsids = map { $_->get('nt_nameserver_id') } $nslist->list;
    if ( scalar @nsids == 0 ) {
        print "no nameservers inside group $sub_gid. Skipping NS update\n";
        next;
    };
    my $ns_string = join(',', @nsids );
    print "\tnss: $ns_string\n";

    # get a list of zones in the subgroup
    my $zonelist = $user->get_group->get_group_zones(nt_group_id => $sub_gid );
    die $zonelist->error_msg if $zonelist->is_error;
    
    # update the nameservers for each zone
    foreach my $zone_ref ( $zonelist->list ) {
        $zone_ref->edit_zone( 
             nt_zone_id  => $zone_ref->get('nt_zone_id'), 
             nameservers => $ns_string,
        );
        if ( $zone_ref->is_error ) {
            warn $zone_ref->error_msg;
            warn $zone_ref->error_desc;
        }
        else {
            print "\tzid: ".$zone_ref->get('nt_zone_id')." ok.\n";
        };
    };
};

$user->logout;

exit 1;

sub ask {
    my $question = shift;
    my $pass     = shift;
    my $response;

PROMPT:
    print "Please enter $question";
    print ": ";
    system "stty -echo" if $pass;
    $response = <STDIN>;
    system "stty echo" if $pass;
    chomp $response;

    return $response if length $response  > 0; # they typed something, return it
    return '';                             # return empty handed
}

