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

my $dbh = DBI->connect( $db_dsn, $db_user, $db_pass,
    { RaiseError => 1, PrintError => 0 } );

my @tables = map { $_ =~ s/.*\.//r } $dbh->tables();
foreach my $table (@tables) {
    # Use DBI directly rather than spawning `mysql -p<pass>`, which would leak
    # the password via /proc/<pid>/cmdline and (if the password contained
    # shell metacharacters) allow command injection through system().
    print "DESC $table;\n";
    my $rows = $dbh->selectall_arrayref( "DESC $table", { Slice => {} } );
    for my $r (@$rows) {
        print join( "\t",
            map { defined $_ ? $_ : '' }
                @{$r}{qw(Field Type Null Key Default Extra)} ),
            "\n";
    }
    print "\n";
}

$dbh->disconnect;
