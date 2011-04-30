#!/usr/bin/perl

use strict;
use DBI;

# machine dependant variables
my $db_host = 'localhost';
my $db      = 'nictool';
my $db_user = 'nictool';
my $db_pass = 'lootcin205';
my $root_pw = '';

my $dbh = DBI->connect("dbi:mysql:database=nictool;host=$db_host", "root", $root_pw);

# Create database and initial priveleges
#$dbh->do("DROP DATABASE IF EXISTS $db");
#$dbh->do("CREATE DATABASE $db");
#$dbh->do("GRANT ALL PRIVILEGES ON $db.* TO $db_user\@$db_host IDENTIFIED BY '$db_pass'");

#$dbh->disconnect;

my @tables;
@tables = map { $_ =~ s/.*\.//; $_ } $dbh->tables();
foreach my $sql (@tables) {
    system("mysql -v -u $db_user -p$db_pass -h $db_host $db -e \"" . &view_command($sql) . "\"" ); 
}

sub view_command {
	my $table = shift;
	return "desc $table;\n";
}

close(DIR);
$dbh->disconnect;
