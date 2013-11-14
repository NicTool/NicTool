#!/usr/bin/perl
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01+ Copyright 2004-2008 The Network People, Inc.
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
use English;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);

my $test_run = $ARGV[0] eq '-test';

# machine dependant variables
my $db_host    = 'localhost';
my $db         = 'nictool';
my $db_user    = 'nictool';
my $db_pass    = 'lootcin205';
my $db_root_pw = '';
my $nt_root_pw = '';
my $nt_root_email='';

print "
#########################################################################
               NicTool database connection settings  
######################################################################### \n";
$db_host = answer("database hostname", $db_host);

system "stty -echo";
$db_root_pw = answer("mysql root password");
system "stty echo";
print "\n";

$db = answer("a name for the NicTool database", $db);
die "Sorry\n" if $db =~/^mysql$/i;

$db_user = answer("a username for NicTool's database user", $db_user);

my ($response, $response2);
while(!$db_pass){
    system "stty -echo";
    $response = answer("a new password for NicTool's database user ($db_user)");
    system "stty echo";

    system "stty -echo";
    $response2 = answer("\nPlease verify password: ");
    system "stty echo";
    $db_pass = $response if $response and ($response eq $response2);
    print "\nPasswords didn't match!\n" unless $db_pass;
}

print "
#########################################################################
                 NicTool admin user (root) settings  
#########################################################################
";
while(!$nt_root_pw){
    system "stty -echo";
    $response = answer("a new root password for NicTool");
    system "stty echo";
    print "\n";

    system "stty -echo";
    $response2 = answer("a verify password");
    system "stty echo";
    $nt_root_pw = $response if $response and ($response eq $response2);
    print "\nPasswords didn't match!\n" unless $nt_root_pw;
}
$nt_root_pw = hmac_sha1_hex( $nt_root_pw, 'root' );
print "\n";

while(!$nt_root_email){
    $nt_root_email = answer("an email address for the root user of NicTool", $nt_root_email);
}

print qq{
Beginning table creation.
If any of the information you entered is incorrect, press Control-C now!
-------------------------
DATABASE DSN:  mysql://$db_user:******\@$db_host/$db
host: $db_host
db  : $db
user: $db_user
   *** the DSN info must match the settings in nictoolserver.conf! ***

NICTOOL LOGIN: http://localhost/index.cgi
user :  root
pass :  *******
email:  $nt_root_email
-------------------------
Otherwise, hit return to continue...
};
my $read = <STDIN>;

my $dbh;
if(!$test_run){
$dbh = DBI->connect("dbi:mysql:host=$db_host", "root", $db_root_pw);

# Create database and initial priveleges
$dbh->do("DROP DATABASE IF EXISTS $db");
$dbh->do("CREATE DATABASE $db");
$dbh->do("GRANT ALL PRIVILEGES ON $db.* TO $db_user\@$db_host IDENTIFIED BY '$db_pass'");

$dbh->disconnect;
}

opendir(DIR, "./") || warn "unable to open dir: $!\n";

my $sql;
my $res;
foreach( sort readdir(DIR) ) {
    next if /^\./;
    next if -d "./$_";
    next unless /\.sql$/;
    print "importing contents of $_ .. "; 
    if(!$test_run){
        $res = system("mysql -u $db_user -p$db_pass -h $db_host $db < $_"); 
        print "done.\n" unless $res ne 0;
        print "FAILED($res)\n" if $res ne 0;
    }else{
        print "TEST\n";
    }
}
close(DIR);

print "importing contents of temp.sql .. ";
my $temp =<<EO_TEMP;
INSERT INTO nt_user(nt_group_id, first_name, last_name, username, password, email) values (1, 'Root', 'User', 'root', '$nt_root_pw', '$nt_root_email');
INSERT INTO nt_user_log(nt_group_id, nt_user_id, action, timestamp, modified_user_id, first_name, last_name, username, password, email) values (1,1,'added', UNIX_TIMESTAMP(), 0, 'Root', 'User', 'root', '$nt_root_pw', '$nt_root_email');
INSERT INTO nt_user_global_log(nt_user_id, timestamp, action, object, object_id, log_entry_id, title, description) values (1,UNIX_TIMESTAMP(),'added', 'user', 1, 1, 'root', 'user creation');
EO_TEMP
open(TEMP,">temp.sql") || die "Unable to create file temp.sql: $!\n";
print TEMP $temp;
close(TEMP);
if(!$test_run){
    $res = system("mysql -u $db_user -p$db_pass -h $db_host $db < temp.sql");
    print "done.\n" unless $res ne 0;
    print "FAILED($res)\n" if $res ne 0;
}else{
    print "TEST\n";
}
unlink("temp.sql");

$dbh->disconnect if !$test_run;

sub answer {

    my ( $question, $default, $timeout) = @_;
            
    # this sub is useless without a question.
    unless ($question) {
        die "question called incorrectly. RTFM. \n";
    }

    print "Please enter $question";
    print " [$default]" if $default;
    print ": ";

    my ($response);

    if ($timeout) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timeout;
            $response = <STDIN>;
            alarm 0;
        };  
        if ($EVAL_ERROR) {
            ( $EVAL_ERROR eq "alarm\n" )
                ? print "timed out!\n"
                : warn;    # propagate unexpected errors
        }
    }
    else {
        $response = <STDIN>;
    }

    chomp $response;

    # if they typed something, return it
    return $response if ( $response ne "" );

    # otherwise, return the default if available
    return $default if $default;

    # and finally return empty handed
    return "";
}

