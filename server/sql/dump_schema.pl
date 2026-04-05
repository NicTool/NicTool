#!/usr/bin/perl

use strict;
use warnings;
use DBI;

# machine dependant variables
my $db_host = '127.0.0.1';
my $db      = 'nictool';
my $db_dsn  = "DBI:mysql:database=$db;host=$db_host";
my $db_user = 'nictool';
my $db_pass = $ENV{NICTOOL_DB_USER_PASSWORD} or die "Set NICTOOL_DB_USER_PASSWORD\n";
my $root_pw = '';

my $dbh = DBI->connect( $db_dsn, 'root', $root_pw );

my @tables = map { $_ =~ s/.*\.//; $_ } $dbh->tables();
foreach my $table (@tables) {
    my $cmd = "mysql -v -u $db_user -p$db_pass -h $db_host $db -e 'DESC $table'";

    #print "cmd: $cmd\n";
    system($cmd);
}

$dbh->disconnect;
