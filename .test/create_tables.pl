#!/usr/bin/perl

use strict;
use Crypt::KeyDerivation;
use DBI;
use English;
$|++;

my $db_name    = 'nictool';
my $db_user    = 'nictool';
my $db_pass    = 'lootcin!mysql';
my $db_host    = 'localhost';
my $db_root_pw = $ENV{MYSQL_ROOT_PASSWORD} // 'root';

my $dbh = get_dbh();

my $nt_root_email = 'workflows@github.com';
my $salt          = _get_salt(16);
my $pass_hash     = unpack( "H*", Crypt::KeyDerivation::pbkdf2( $db_pass, $salt, 5000, 'SHA512' ) );

print qq{\n
Beginning table creation.
-------------------------
DATABASE DSN:  mysql://$db_user\@$db_host/$db_name
host: $db_host
db  : $db_name
user: $db_user
   *** the DSN info must match the settings in nictoolserver.conf! ***

NICTOOL LOGIN: https://$db_host/index.cgi
user :  nictest
salt :  $salt
pass :  encrypted as: $pass_hash
email:  $nt_root_email
-------------------------
};

# Create database and initial privileges
$dbh->do("DROP DATABASE IF EXISTS $db_name");
$dbh->do("CREATE DATABASE $db_name");

my %user_hosts = map { $_ => 1 } ( $db_host, '127.0.0.1', '::1' );

for my $host ( sort keys %user_hosts ) {
    my $db_user_host = "'$db_user'\@'$host'";
    $dbh->do("DROP USER IF EXISTS $db_user_host");

    my $created_user = eval {
        $dbh->do("CREATE USER $db_user_host IDENTIFIED WITH mysql_native_password BY '$db_pass'");
        1;
    };

    if ( !$created_user ) {
        $dbh->do("CREATE USER $db_user_host IDENTIFIED BY '$db_pass'");
    }

    $dbh->do("GRANT ALL PRIVILEGES ON $db_name.* TO $db_user_host");
}

$dbh->do("USE $db_name");

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

$dbh->do("INSERT INTO `nt_group` VALUES (2,1,'test_group', 0)");
$dbh->do(
    "INSERT INTO `nt_group_log` VALUES
    (2,1,1,'added',1487651312,2,1,'test_group')"
);
$dbh->do(
    "INSERT INTO `nt_group_subgroups` VALUES
    (1,2,1000);"
);
$dbh->do(
    "INSERT INTO `nt_perm` VALUES
   (2,2,NULL,NULL,NULL,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,'1,2,3',0);"
);
$dbh->do(
    "INSERT INTO `nt_user` VALUES
   (1,1,'Root','User','root','$pass_hash','$salt','$nt_root_email',NULL,0),
   (2,2,'TestFirst','TestLast','nictest','09afe1013ec0a14793df1317a8e5f28f5ee84cc9758f50a19cb6154857e07ffe',']]l7./*4,8]wvBbo','test\@example.com',NULL,0)"
);
$dbh->disconnect;
print "\n";

sub get_dbh {
    print "
#########################################################################
             Administrator DSN (database connection settings)
#########################################################################\n";

    my $dbh = DBI->connect(
        "dbi:mysql:host=$db_host",
        'root',
        $db_root_pw,
        {   mysql_ssl  => 1,
            ChopBlanks => 1,
        }
    ) or die $DBI::errstr;

    return $dbh;
}

sub get_sql_files {
    my @r;
    opendir( DIR, 'server/sql' ) || die "unable to open dir: $!\n";
    foreach my $file ( sort readdir(DIR) ) {
        next if /^\./;
        next if -d "server/sql/$file";
        next if $file !~ /\.sql$/;
        push @r, 'server/sql/' . $file;
    }
    close DIR;
    if ( scalar @r < 8 ) {
        die "didn't find *.sql files. Are you running this in the sql dir?\n";
    }
    return @r;
}

sub _get_salt {
    my $self   = shift;
    my $length = shift || 16;
    my $chars  = join( '', map chr, 40 .. 126 );    # ASCII 40-126
    my $salt;
    for ( 0 .. ( $length - 1 ) ) {
        $salt .= substr( $chars, rand( ( length $chars ) - 1 ), 1 );
    }
    return $salt;
}
