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

my $test_run = $ARGV[0] eq '-test';
# machine dependant variables
my $db_host = 'localhost';
my $db      = 'nictool';
my $db_user = 'nictool';
my $db_pass = 'lootcin205';
my $root_pw = '';
my $nt_root_pw= '';
my $nt_root_email='';

if(-f "$0.cache" && open (F,"$0.cache")){
	my $cache;
	{local $/;
	$cache = <F>;
	}	
	eval $cache;
	print "read cache: $cache\n";
	close(F);
}

print <<END;
This script will update an existing 1.06x database to version 2.00.
It will also grant access to the database for a user.  You should 
make sure this username and password are specified in 'nictoolserver.conf'.

Make a COPY of your database and then upgrade the COPY.

END

my $read;
print "Please enter database hostname [$db_host]: ";
$read = <STDIN>;
chomp $read;
$db_host=$read if $read;

print "Please enter database root password: ";
system "stty -echo";
$read = scalar(<STDIN>);
system "stty echo";
chomp $read;
$root_pw=$read if $read;

print "\nPlease enter the name for the NicTool database to be upgraded.
	You should make a COPY of your old data and upgrade the copy [$db]: ";
$read = <STDIN>;
chomp $read;
$db = $read if $read;
die "Sorry\n" if $db =~/^mysql$/i;

print "Please enter a username for NicTool's database user [$db_user]: ";
$read = <STDIN>;
chomp $read;
$db_user = $read if $read;


while(!$db_pass){
    my $newread;
    print "\nPlease enter a new password for NicTool's database user ($db_user): ";
    system "stty -echo";
    $read = <STDIN>;
    chomp $read;
    system "stty echo";

    print "\nPlease verify password: ";
    system "stty -echo";
    $newread = <STDIN>;
    chomp $newread;
    system "stty echo";
    $db_pass = $read if $read and $read eq $newread;
    print "\nPasswords didn't match!\n" unless $db_pass;
}

#print "ntrootpw: $nt_root_pw\ndb_pass: $db_pass\nroot_pw: $root_pw\ndb_host: $db_host\n";
#exit 1;

print qq{
Beginning table creation.
If any of the information you entered is incorrect, press Control-C now!
-------------------------
DB_HOSTNAME: $db_host
DB to upgrade: $db
DB_USER: $db_user
-------------------------
Otherwise, hit return to continue...
};
$read = <STDIN>;

if(open(F,">$0.cache")){
	print F "\$db_host='$db_host';\n";			
	print F "\$db='$db';\n";			
	print F "\$db_user='$db_user';\n";			
	close(F);
}

my $dbh;
if(!$test_run){
    $dbh = DBI->connect("dbi:mysql:host=$db_host", "root", $root_pw);

    print "Granting privleges to $db_user...\n";
    $dbh->do("GRANT ALL PRIVILEGES ON $db.* TO $db_user\@$db_host IDENTIFIED BY '$db_pass'");
    $dbh->disconnect;
}

print "Running update_v1_06.sql on database $db ...\n"; 
my $res;
my $cmd = "mysql -u $db_user -p$db_pass -h $db_host $db < update_v1_06.sql";
if(!$test_run){
	$res = system( $cmd ) and print "FAILED($res)\n";
	print "done.\n" if $res==0;
}else{
	print( $cmd ); 
	print "TEST\n";
}


