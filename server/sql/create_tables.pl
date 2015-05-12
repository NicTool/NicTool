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
use Crypt::KeyDerivation;
use DBI;
use English;
$|++;
my $test_run = $ARGV[0] eq '-test';

my ($dbh, $db_host) = get_dbh();

print "
#########################################################################
              NicTool DSN (database connection settings)
#########################################################################
";
my $db  = answer("the NicTool database name", 'nictool');
die "Sorry\n" if $db =~/^mysql$/i;

my $db_user = answer("the NicTool database user", 'nictool');
my $db_pass = get_password("the DB user $db_user");

print "\n
#########################################################################
        NicTool admin user (http://root\@$db_host/)
#########################################################################
";
my $nt_root_email;
while(!$nt_root_email){
    $nt_root_email = answer("the NicTool 'root' users email address", $nt_root_email);
}
my $clear_pass = get_password("the NicTool user 'root'");
my $salt = _get_salt(16);
my $pass_hash = unpack("H*", Crypt::KeyDerivation::pbkdf2($clear_pass, $salt, 5000, 'SHA512'));

print qq{\n
Beginning table creation.
If any of the information you entered is incorrect, press Control-C now!
-------------------------
DATABASE DSN:  mysql://$db_user:******\@$db_host/$db
host: $db_host
db  : $db
user: $db_user
   *** the DSN info must match the settings in nictoolserver.conf! ***

NICTOOL LOGIN: https://$db_host/index.cgi
user :  root
salt :  $salt
pass :  encrypted as: $pass_hash
email:  $nt_root_email
-------------------------
Otherwise, hit return to continue...
};
my $read = <STDIN>;

exit if $test_run;

# Create database and initial privileges
$dbh->do("DROP DATABASE IF EXISTS $db");
$dbh->do("CREATE DATABASE $db");
$dbh->do("GRANT ALL PRIVILEGES ON $db.* TO $db_user\@$db_host IDENTIFIED BY '$db_pass'");
$dbh->do("USE $db");

my @sql_files = get_sql_files();
foreach my $sql (@sql_files) {
    open (my $fh, '<', $sql) or die "failed to open $sql for read: $!";
    print "\nopened $sql\n";
    my $q_string = join(' ', grep {/^[^#]/} grep {/[\S]/} <$fh>);
    foreach my $q (split(';', $q_string)) { # split string into queries
        next if $q !~ /[\S]/;               # skip blank entries
        print "$q;";                        # show the query
        $dbh->do( $q ) or die $DBI::errstr; # run it!
    };
    close $fh;
    print "\n";
}

$dbh->do("
INSERT INTO $db.nt_user(nt_group_id, first_name, last_name, username, password, pass_salt, email)
VALUES (1, 'Root', 'User', 'root', '$pass_hash', '$salt', '$nt_root_email')");
$dbh->do("
INSERT INTO $db.nt_user_log(nt_group_id, nt_user_id, action, timestamp,
  modified_user_id, first_name, last_name, username, password, email)
VALUES (1,1,'added', UNIX_TIMESTAMP(), 0, 'Root', 'User', 'root', '$pass_hash', '$nt_root_email')");
$dbh->do("
INSERT INTO $db.nt_user_global_log(nt_user_id, timestamp, action, object,
  object_id, log_entry_id, title, description)
VALUES (1,UNIX_TIMESTAMP(),'added', 'user', 1, 1, 'root', 'user creation')"
);

$dbh->disconnect;
print "\n";

sub get_dbh {
    print "
#########################################################################
             Administrator DSN (database connection settings)
#########################################################################\n";
    my $db_host = answer("database hostname", '127.0.0.1');

    system "stty -echo";
    my $db_root_pw = answer("mysql root password");
    system "stty echo";
    print "\n";

    return if $test_run;
    my $dbh = DBI->connect("dbi:mysql:host=$db_host", "root", $db_root_pw, {
            ChopBlanks => 1,
        })
        or die $DBI::errstr;

    return ($dbh, $db_host);
}

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

sub get_password {
    my ($question) = @_;

    my ($answer, $response, $response2);
    while(!$answer){
        system "stty -echo";
        $response = answer("a new password for $question");
        system "stty echo";

        system "stty -echo";
        $response2 = answer("\nPlease verify password: ");
        system "stty echo";
        $answer = $response if $response and ($response eq $response2);
        if (!$answer) {
            print "\nPasswords didn't match!\n";
        };
    }
    return $answer;
};

sub get_sql_files {
    my @r;
    opendir(DIR, '.') || die "unable to open dir: $!\n";
    foreach my $file (sort readdir(DIR)) {
        next if /^\./;
        next if -d "./$file";
        next if $file !~ /\.sql$/;
        push @r, $file;
    };
    close DIR;
    if (scalar @r < 8) {
        die "didn't find *.sql files. Are you running this in the sql dir?\n";
    };
    return @r;
};

sub _get_salt {
    my $self = shift;
    my $length = shift || 16;
    my $chars = join('', map chr, 40..126); # ASCII 40-126
    my $salt;
    for ( 0..($length-1) ) {
        $salt .= substr($chars, rand((length $chars) - 1),1);
    };
    return $salt;
}
