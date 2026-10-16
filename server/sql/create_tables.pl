#!/usr/bin/perl
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abraham Ingersoll & Greg Schueler
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
use Getopt::Long qw/HelpMessage/;

$|++;

GetOptions(
    'test'                       => \my $test_run,
    'environment'                => \my $environment,
    'db-engine=s'                => \my $db_engine,
    'db-hostname=s'              => \my $db_hostname,
    'db-root-password=s'         => \my $db_root_password,
    'nictool-db-name=s'          => \my $nictool_db_name,
    'nictool-db-user=s'          => \my $nictool_db_user,
    'nictool-db-user-password=s' => \my $nictool_db_user_password,
    'nictool-root-email=s'       => \my $nictool_root_email,
    'nictool-root-password=s'    => \my $nictool_root_password,
    'help'                       => sub { HelpMessage(0) },
) or HelpMessage(1);

my ( $dbh, $db_host, $db_engine ) = get_dbh();

print "
#########################################################################
              NicTool DSN (database connection settings)
#########################################################################
";

my $db = setting( 'NICTOOL_DB_NAME', $nictool_db_name,
    sub { answer( "the NicTool database name", 'nictool' ) } );

die "Sorry\n" if $db =~ /^mysql$/i;

# MySQL identifiers cannot be parameterized, so validate them strictly before
# interpolation into DDL below. Reject anything outside a safe charset.
sub _validate_ident {
    my ( $name, $what ) = @_;
    die "invalid $what: must match /^[A-Za-z0-9_]+\$/\n"
        unless defined $name && $name =~ /\A[A-Za-z0-9_]+\z/;
    return $name;
}
_validate_ident( $db, 'database name' );

my $db_user = setting( 'NICTOOL_DB_USER', $nictool_db_user,
    sub { answer( "the NicTool database user", 'nictool' ) } );

my $db_pass = setting( 'NICTOOL_DB_USER_PASSWORD', $nictool_db_user_password,
    sub { get_password("the DB user $db_user") } );

print "\n
#########################################################################
        NicTool admin user (http://root\@$db_host/)
#########################################################################
";

my $nt_root_email = setting(
    'ROOT_USER_EMAIL',
    $nictool_root_email,
    sub {
        my $email;
        $email = answer("the NicTool 'root' users email address") while !$email;
        return $email;
    }
);

my $clear_pass = setting( 'ROOT_USER_PASSWORD', $nictool_root_password,
    sub { get_password("the NicTool user 'root'") } );

my $salt      = _get_salt(16);
my $pass_hash = unpack( "H*", Crypt::KeyDerivation::pbkdf2( $clear_pass, $salt, 5000, 'SHA512' ) );

print qq{\n
Beginning table creation.
If any of the information you entered is incorrect, press Control-C now!
-------------------------
DATABASE DSN:  $db_engine://$db_user:******\@$db_host/$db
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
_validate_ident( $db_user, 'db user name' );

my $user_host =
    ( $db_host eq 'localhost' || $db_host eq '127.0.0.1' || $db_host eq '::1' ) ? $db_host : '%';
die "invalid host pattern: $user_host\n"
    unless $user_host =~ /\A[A-Za-z0-9_.:%-]+\z/;

# $db, $db_user, and $user_host have been validated against strict whitelists
# above. The password is escaped with $dbh->quote() rather than interpolated.
my $q_pass = $dbh->quote($db_pass);

$dbh->do("DROP DATABASE IF EXISTS $db");
$dbh->do("CREATE DATABASE $db");

# Create the NicTool database user. MySQL 8.0+ removed GRANT ... IDENTIFIED BY,
# so we CREATE USER first, then GRANT separately.
$dbh->do("DROP USER IF EXISTS '$db_user'\@'$user_host'");

# Try mysql_native_password first (MySQL 8.0+), fall back for MariaDB
my $created = $dbh->do(
    "CREATE USER '$db_user'\@'$user_host' IDENTIFIED WITH mysql_native_password BY $q_pass");
if ( !$created ) {
    $dbh->do("CREATE USER '$db_user'\@'$user_host' IDENTIFIED BY $q_pass");
}

$dbh->do("GRANT ALL PRIVILEGES ON $db.* TO '$db_user'\@'$user_host'");

$dbh->do("USE $db");

my @sql_files = get_sql_files();
foreach my $sql (@sql_files) {
    open( my $fh, '<', $sql ) or die "failed to open $sql for read: $!";
    print "\nopened $sql\n";
    my $q_string = join( ' ', grep {/^[^#]/} grep {/[\S]/} <$fh> );
    foreach my $q ( split( ';', $q_string ) ) {    # split string into queries
        next if $q !~ /[\S]/;                      # skip blank entries
        print "$q;";                               # show the query
        $dbh->do($q) or die $DBI::errstr;          # run it!
    }
    close $fh;
    print "\n";
}

# pass_salt is 16 random bytes drawn from ASCII 40-126, which includes '\'.
# Interpolating it into the SQL string lets MySQL/MariaDB swallow the backslash
# as the start of an escape sequence (\b, \=, \h, ...), which corrupts ~17% of
# salts on insert and silently locks the root account out at login.
# Bind every untrusted value, including $pass_hash and $nt_root_email.
$dbh->do(
    "INSERT INTO $db.nt_user
       (nt_group_id, first_name, last_name, username, password, pass_salt, email)
     VALUES (1, 'Root', 'User', 'root', ?, ?, ?)",
    undef, $pass_hash, $salt, $nt_root_email
);
$dbh->do(
    "INSERT INTO $db.nt_user_log
       (nt_group_id, nt_user_id, action, timestamp,
        modified_user_id, first_name, last_name, username, password, email)
     VALUES (1, 1, 'added', UNIX_TIMESTAMP(), 0, 'Root', 'User', 'root', ?, ?)",
    undef, $pass_hash, $nt_root_email
);
$dbh->do( "
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

    $db_engine = setting( 'DB_ENGINE', $db_engine, sub { answer( "database engine", 'mysql' ) } );
    my $db_host = setting( 'DB_HOSTNAME', $db_hostname,
        sub { answer( "database hostname", '127.0.0.1' ) } );
    my $db_root_pw = setting( 'DB_ROOT_PASSWORD', $db_root_password,
        sub { answer_secret("mysql root password") } );
    print "\n";

    return if $test_run;
    my %opts = ( ChopBlanks => 1 );
    $opts{ $db_engine eq 'MariaDB' ? 'mariadb_ssl' : 'mysql_ssl' } = 1 if $ENV{DB_SSL};
    my $dbh = DBI->connect( "dbi:$db_engine:host=$db_host", "root", $db_root_pw, \%opts )
        or die $DBI::errstr;

    return ( $dbh, $db_host, $db_engine );
}

# --environment takes every setting from the environment; otherwise a
# command line option wins over prompting
sub setting {
    my ( $env_name, $option, $prompt ) = @_;
    if ($environment) {
        die "$env_name not set!!!\n" unless $ENV{$env_name};
        return $ENV{$env_name};
    }
    return $option if $option;
    return $prompt->();
}

sub answer {
    my ( $question, $default ) = @_;
    die "question called incorrectly. RTFM. \n" if !$question;

    print "Please enter $question";
    print " [$default]" if $default;
    print ": ";

    my $response = <STDIN>;
    chomp $response;

    return $response if $response ne "";
    return $default  if $default;
    return "";
}

sub answer_secret {
    my ($question) = @_;
    system "stty -echo";
    my $response = answer($question);
    system "stty echo";
    return $response;
}

sub get_password {
    my ($question) = @_;

    while (1) {
        my $response  = answer_secret("a new password for $question");
        my $response2 = answer_secret("\nPlease verify password: ");
        return $response if $response && $response eq $response2;
        print "\nPasswords didn't match!\n";
    }
}

sub get_sql_files {
    my @r = sort grep { -f } glob '*.sql';
    die "didn't find *.sql files. Are you running this in the sql dir?\n" if @r < 8;
    return @r;
}

sub _get_salt {
    my $length = shift || 16;
    my $chars  = join( '', map chr, 40 .. 126 );    # ASCII 40-126
    my $salt;
    for ( 0 .. ( $length - 1 ) ) {
        $salt .= substr( $chars, rand( ( length $chars ) - 1 ), 1 );
    }
    return $salt;
}

=head1 NAME

create_tables.pl - configure the NicTool database.

=head1 SYNOPSIS

  --help                        Displays this message. If called without any arguments, this script
                                will simply run interactively.

  --test                        Perform a test run.

  --environment                 Use environment variables to set up the database. These
                                are as follows: DB_ENGINE, DB_HOSTNAME, DB_ROOT_PASSWORD,
                                NICTOOL_DB_NAME, NICTOOL_DB_USER, NICTOOL_DB_USER_PASSWORD,
                                ROOT_USER_EMAIL, ROOT_USER_PASSWORD. If this flag is
                                present, the remaining arguments below are ignored.

  --db-engine                   The MySQL database engine (mysql or MariaDB).
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
