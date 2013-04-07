#!/usr/bin/perl

use strict;
use warnings;

my $rsync = "rsync -av";
my $gitdir = '/usr/local/nictool/git';
my $ntdir  = '/usr/local/nictool';

if ( ! -d $gitdir ) {
    die "git dir not found. Did you check out the NicTool repo to $gitdir?\n
Try: git clone https://github.com/msimerson/NicTool.git $gitdir\n";
};


my $exclude = '--exclude nictoolclient.conf --exclude nictoolserver.conf --exclude test.cfg';
my $server = "$rsync $exclude $gitdir/server/ $ntdir/server/";
my $client = "$rsync $exclude $gitdir/client/ $ntdir/client/";

if ( ! -d "$ntdir/server" || ! -d "$ntdir/client" ) {
    die "This script can only update an existing NicTool install. Install
NicTool and/or edit this script to set ntdir.\n";
};

print "$server\n";
system $server;

print "$client\n";
system $client;

