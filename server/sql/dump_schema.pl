#!/usr/bin/perl

use strict;
use warnings;
use DBI;

# machine dependant variables
my $db_dsn  = "DBI:mysql:database=nictool;host=localhost";
my $db_user = 'nictool';
my $db_pass = 'lootcin205';
my $root_pw = '';

my $dbh = DBI->connect( $dsn, 'root', $root_pw);

my @tables = map { $_ =~ s/.*\.//; $_ } $dbh->tables();
foreach my $table (@tables) {
    my $cmd = "mysql -v -u $db_user -p$db_pass -h $db_host $db -e 'DESC $table'";
    #print "cmd: $cmd\n";
    system( $cmd ); 
}

$dbh->disconnect;
