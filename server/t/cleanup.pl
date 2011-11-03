#!/usr/bin/perl
#
# Recursively delete a list of Groups and all of it's objects + groups.
# usage: cleanup.pl <group_id> [...]
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under 
# the terms of the Affero General Public License as published by Affero, 
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT 
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#

use lib '../client';
use lib 't';
use TestConfig;

@ARGV or die "cleanup <group_id> [...]\n";

use NicTool;

$nt = new NicTool(
    server_host => Config('server_host'),
    server_port => Config('server_port')
);

$nt->login( username => Config('username'), password => Config('password') );
$nt->result->die_if_err;
print "Logged in as " . Config('username') . "...\n";
$tab = 0;
foreach $gid (@ARGV) {
    del_group($gid);
}

sub del_group {

    my $gid = shift;
    $x = ' ' x $tab;
    $group = $nt->get_group( nt_group_id => $gid );
    $group->die_if_err
      || print "${x}Deleting group " . $group->get('name') . " ID $gid\n";
    if ( $group->get('deleted') ) {
        print "${x}Group is already deleted!\n";
        return;
    }

    print "${x}Checking users...\n";
    $users = $group->get_group_users;

    if ( !$users->warn_if_err && $users->size ) {
        print $x. $users->size . " users found. Deleting users...";
        @uids = map { $_->id } $users->list;
        $nt->delete_users( user_list => \@uids );
        $nt->result->warn_if_err || print "Ok\n";
    }

    print "${x}Checking zones...\n";
    $zones = $group->get_group_zones;

    if ( !$zones->warn_if_err && $zones->size ) {
        print $x. $zones->size . " zones found. Deleting zones...";
        @zids = map { $_->id } $zones->list;
        $nt->delete_zones( zone_list => \@zids );
        $nt->result->warn_if_err || print "Ok\n";
    }

    print "${x}Checking subgroups...\n";
    $groups = $group->get_group_subgroups;

    if ( !$groups->warn_if_err && $groups->size ) {
        print $x. $groups->size . " subgroups found. Deleting subgroups...\n";
        foreach ( $groups->list ) {
            $tab++;
            del_group( $_->id );
            $tab--;
        }
    }

    print "${x}Deleting group $gid...";
    $res = $group->delete;
    $res->warn_if_err || print "Finished.\n";

}
