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
use Getopt::Long qw/HelpMessage/;

$|++;

GetOptions(
    'test'                          => \my $test_run,
    'environment'                   => \my $environment,
    'db-type=s'                     => \my $db_type,
    'db-hostname=s'                 => \my $db_hostname,
    'db-root-password=s'            => \my $db_root_password,
    'nictool-db-name=s'             => \my $nictool_db_name,
    'nictool-db-user=s'             => \my $nictool_db_user,
    'nictool-db-user-password=s'    => \my $nictool_db_user_password,
    'nictool-root-email=s'          => \my $nictool_root_email,
    'nictool-root-password=s'       => \my $nictool_root_password,
    'help' => sub { HelpMessage(0) },
) or HelpMessage(1);

my ($dbh, $db_host, $db_type) = get_dbh();

print "
#########################################################################
              NicTool DSN (database connection settings)
#########################################################################
";

my $db = undef;

if ($environment) {
    $nictool_db_name = undef;
    die "NICTOOL_DB_NAME not set!!!\n" unless $ENV{NICTOOL_DB_NAME};
    $db = $ENV{NICTOOL_DB_NAME};
} elsif ($nictool_db_name) {
    $db = $nictool_db_name;
} else {
    $db  = answer("the NicTool database name", 'nictool');
}

die "Sorry\n" if $db =~/^mysql$/i;

my $db_user = undef;

if ($environment) {
    $nictool_db_user = undef;
    die "NICTOOL_DB_USER not set!!!\n" unless $ENV{NICTOOL_DB_USER};
    $db_user = $ENV{NICTOOL_DB_USER};
} elsif ($nictool_db_user) {
    $db_user = $nictool_db_user;
} else {
    $db_user = answer("the NicTool database user", 'nictool');
}

my $db_pass = undef;

if ($environment) {
    $nictool_db_user_password = undef;
    die "NICTOOL_DB_USER_PASSWORD not set!!!\n" unless $ENV{NICTOOL_DB_USER_PASSWORD};
    $db_pass = $ENV{NICTOOL_DB_USER_PASSWORD};
} elsif ($nictool_db_user_password) {
    $db_pass = $nictool_db_user_password;
} else {
    $db_pass = get_password("the DB user $db_user");
}

print "\n
#########################################################################
        NicTool admin user (http://root\@$db_host/)
#########################################################################
";
my $nt_root_email = undef;

if ($environment) {
    $nictool_root_email = undef;
    die "ROOT_USER_EMAIL not set!!!\n" unless $ENV{ROOT_USER_EMAIL};
    $nt_root_email = $ENV{ROOT_USER_EMAIL};
} elsif ($nictool_root_email) {
    $nt_root_email = $nictool_root_email;
} else {
    while(!$nt_root_email){
        $nt_root_email = answer("the NicTool 'root' users email address", $nt_root_email);
    }
}

my $clear_pass = undef;

if ($environment) {
    $nictool_root_password = undef;
    die "ROOT_USER_PASSWORD not set!!!\n" unless $ENV{ROOT_USER_PASSWORD};
    $clear_pass = $ENV{ROOT_USER_PASSWORD};
} elsif ($nictool_root_password) {
    $clear_pass = $nictool_root_password;
} else {
    $clear_pass = get_password("the NicTool user 'root'");
}

my $salt = _get_salt(16);
my $pass_hash = unpack("H*", Crypt::KeyDerivation::pbkdf2($clear_pass, $salt, 5000, 'SHA512'));

print qq{\n
Beginning table creation.
If any of the information you entered is incorrect, press Control-C now!
-------------------------
DATABASE DSN:  $db_type://$db_user:******\@$db_host/$db
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

# remote sessions will never be recognized as 'db_user'@'db_hostname' as MySQL does
# a reverse lookup of the initiating host's IP address and uses that as the 
# connection string, eg 'db_user'@'x.x.x.x'
if ($db_host eq 'localhost' || $db_host eq '127.0.0.1' || $db_host eq '::1') {
    $dbh->do("GRANT ALL PRIVILEGES ON $db.* TO $db_user\@$db_host IDENTIFIED BY '$db_pass'");
} else {
    $dbh->do("GRANT ALL PRIVILEGES ON $db.* TO $db_user\@'%' IDENTIFIED BY '$db_pass'");
}

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

    my $db_host = undef;

    if ($environment) {
        $db_type = undef;
        die "DB_TYPE not set!!!\n" unless $ENV{DB_TYPE};
        $db_type = $ENV{DB_TYPE};
    } elsif ($db_type) {
        $db_type = $db_type;
    } else {
        $db_type = answer("database type", 'mysql');
    }

    if ($environment) {
        $db_hostname = undef;
        die "DB_HOSTNAME not set!!!\n" unless $ENV{DB_HOSTNAME};
        $db_host = $ENV{DB_HOSTNAME};
    } elsif ($db_hostname) {
        $db_host = $db_hostname;
    } else {
        $db_host = answer("database hostname", '127.0.0.1');
    }

    my $db_root_pw = undef;

    if ($environment) {
        $db_root_password = undef;
        die "DB_ROOT_PASSWORD not set!!!\n" unless $ENV{DB_ROOT_PASSWORD};
        $db_root_pw = $ENV{DB_ROOT_PASSWORD};
    } elsif ($db_root_password) {
        $db_root_pw = $db_root_password;
    } else {
        system "stty -echo";
        $db_root_pw = answer("mysql root password");
        system "stty echo";
    }
    print "\n";

    return if $test_run;
    my $dbh = DBI->connect("dbi:$db_type:host=$db_host", "root", $db_root_pw, {
            ChopBlanks => 1,
        })
        or die $DBI::errstr;

    return ($dbh, $db_host, $db_type);
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
}

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
}

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

=head1 NAME

create_tables.pl - configure the NicTool database.

=head1 SYNOPSIS

  --help                        Displays this message. If called without any arguments, this script
                                will simply run interactively.

  --test                        Perform a test run.

  --environment                 Use environment variables to set up the database. These
                                are as follows: DB_TYPE, DB_HOSTNAME, DB_ROOT_PASSWORD,
                                NICTOOL_DB_NAME, NICTOOL_DB_USER, NICTOOL_DB_USER_PASSWORD,
                                ROOT_USER_EMAIL, ROOT_USER_PASSWORD. If this flag is
                                present, the remaining arguments below are ignored.

  --db-type                     The MySQL database type (mysql or MariaDB).
  --db-hostname                 The MySQL database hostname or IP address to connect to.
  --db-root-password            The MySQL root user password.
  --nictool-db-name             The name of the NicTool database. Defaults to 'nictool'.
  --nictool-db-user             The MySQL user of the NicTool database. Defaults to 'nictool'.
  --nictool-db-user-password    The password to use for the MySQL user of the NicTool database.
  --nictool-root-email          The e-mail address of the 'root' user of the NicTool web UI.
  --nictool-root-password       The password for the 'root' user of the NicTool web UI.

=head1 VERSION

2.33.2

=cut
