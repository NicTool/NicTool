#!/usr/bin/perl
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

use strict;

use DBI;
$NicToolServer::db_engine   = 'mysql';
$NicToolServer::db_host     = 'localhost';
$NicToolServer::db_port     = 3306;
$NicToolServer::db          = 'nictool_new';
$NicToolServer::db_user     = 'nictool';
$NicToolServer::db_pass     = 'lootcin205';

my $dbh = DBI->connect("DBI:$NicToolServer::db_engine:database=$NicToolServer::db;host=$NicToolServer::db_host", $NicToolServer::db_user, $NicToolServer::db_pass);

my $sth = $dbh->prepare("SELECT nt_group_id, name FROM nt_group ORDER BY nt_group_id");
$sth->execute();

while( my $row = $sth->fetch ) {
    &recurse_groups($row->[0], $row->[1], $row->[0], "\t", 1000);
}

sub recurse_groups {
    my $id = shift;
    my $name = shift;
    my $curr_id = shift;
    my $indent = shift;
    my $rank = shift;

    my $sth = $dbh->prepare("SELECT nt_group_id, name FROM nt_group WHERE parent_group_id = $curr_id");
    $sth->execute;

    while( my $row = $sth->fetch ) {
        print $indent . "adding $row->[0]:$row->[1] to $id:$name\n";
        $dbh->do("INSERT INTO nt_group_subgroups(nt_group_id, nt_subgroup_id, rank) VALUES($id, $row->[0], $rank)");
        &recurse_groups($id, $name, $row->[0], $indent . "\t", $rank - 1);
    }
    $sth->finish;
}

