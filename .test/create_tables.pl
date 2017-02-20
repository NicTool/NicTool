#!/usr/bin/perl

use strict;
use Crypt::KeyDerivation;
use DBI;
use English;
$|++;

my ($dbh, $db_host) = get_dbh();

my $db  = 'nictool';
my $db_user = 'nictool';
my $db_pass = 'lootcin!mysql';

my $nt_root_email = 'ci@travis-ci.com';
my $salt = _get_salt(16);
my $pass_hash = unpack("H*", Crypt::KeyDerivation::pbkdf2($db_pass, $salt, 5000, 'SHA512'));

print qq{\n
Beginning table creation.
-------------------------
DATABASE DSN:  mysql://nictool\@$db_host/$db
host: $db_host
db  : $db
user: nictool
   *** the DSN info must match the settings in nictoolserver.conf! ***

NICTOOL LOGIN: https://$db_host/index.cgi
user :  nictest
salt :  $salt
pass :  encrypted as: $pass_hash
email:  $nt_root_email
-------------------------
};

# Create database and initial privileges
$dbh->do("DROP DATABASE IF EXISTS $db");
$dbh->do("CREATE DATABASE $db");
$dbh->do("GRANT ALL PRIVILEGES ON $db.* TO nictool\@$db_host IDENTIFIED BY '$db_pass'");
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

$dbh->do("INSERT INTO `nt_group` (`nt_group_id`, `parent_group_id`, `name`)
VALUES (2,1,'test_group')");

$dbh->do("
INSERT INTO $db.nt_user(nt_group_id, first_name, last_name, username, password, pass_salt, email)
VALUES
    (1, 'Root', 'User', 'root', '$pass_hash', '$salt', '$nt_root_email'),
    (2, 'TestFirst','TestLast','nictest','7307552e39c9143bd5272f2610b610ed714d7d5e1fadd36e94fcb44d4a7fd65d','GdS=6WW1yTDsg`Nd','test\@example.com')
");
$dbh->do("
INSERT INTO `nt_perm` (`nt_perm_id`, `nt_group_id`, `nt_user_id`, `inherit_perm`, `perm_name`, `group_write`, `group_create`, `group_delete`, `zone_write`, `zone_create`, `zone_delegate`, `zone_delete`, `zonerecord_write`, `zonerecord_create`, `zonerecord_delegate`, `zonerecord_delete`, `user_write`, `user_create`, `user_delete`, `nameserver_write`, `nameserver_create`, `nameserver_delete`, `self_write`, `usable_ns`)
VALUES
    (2,2,NULL,NULL,NULL,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,'1,2,3');
");
$dbh->disconnect;
print "\n";

sub get_dbh {
    print "
#########################################################################
             Administrator DSN (database connection settings)
#########################################################################\n";
    my $db_host = 'localhost';
    my $db_root_pw = '';

    my $dbh = DBI->connect("dbi:mysql:host=$db_host", 'root', $db_root_pw, {
            ChopBlanks => 1,
        })
        or die $DBI::errstr;

    return ($dbh, $db_host);
}

sub get_sql_files {
    my @r;
    opendir(DIR, 'server/sql') || die "unable to open dir: $!\n";
    foreach my $file (sort readdir(DIR)) {
        next if /^\./;
        next if -d "server/sql/$file";
        next if $file !~ /\.sql$/;
        push @r, 'server/sql/' . $file;
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
