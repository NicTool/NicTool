#!/usr/bin/perl
#
# Creates the test user/group and generates test.cfg files for the test suite.
# Reads all credentials from environment variables.
#

use strict;
use warnings;
use Crypt::KeyDerivation;
use DBI;

my $db_engine = $ENV{DB_ENGINE}       || 'mysql';
my $db_host   = $ENV{DB_HOSTNAME}     || '127.0.0.1';
my $db_name   = $ENV{NICTOOL_DB_NAME} || 'nictool';
my $db_user   = $ENV{NICTOOL_DB_USER}          or die "Set NICTOOL_DB_USER\n";
my $db_pass   = $ENV{NICTOOL_DB_USER_PASSWORD} or die "Set NICTOOL_DB_USER_PASSWORD\n";

# Generate a random password for the test user
my $test_pass = _random_password(20);
my $salt      = _get_salt(16);
my $pass_hash = unpack( "H*", Crypt::KeyDerivation::pbkdf2( $test_pass, $salt, 5000, 'SHA512' ) );

my $dsn = "DBI:$db_engine:database=$db_name;host=$db_host;port=3306";
my $dbh = DBI->connect( $dsn, $db_user, $db_pass, { RaiseError => 1 } )
    or die "Cannot connect to $dsn: $DBI::errstr\n";

# Check if test group already exists
my ($group_exists) = $dbh->selectrow_array("SELECT COUNT(*) FROM nt_group WHERE nt_group_id = 2");

unless ($group_exists) {
    print "Creating test group and user...\n";
    $dbh->do("INSERT INTO nt_group VALUES (2,1,'test_group', 0)");
    $dbh->do("INSERT INTO nt_group_log VALUES (2,1,1,'added',UNIX_TIMESTAMP(),2,1,'test_group')");
    $dbh->do("INSERT INTO nt_group_subgroups VALUES (1,2,1000)");
    $dbh->do(
        "INSERT INTO nt_perm VALUES (2,2,NULL,NULL,NULL,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,'1,2,3',0)"
    );
}

# Check if test user already exists
my ($user_exists) =
    $dbh->selectrow_array("SELECT COUNT(*) FROM nt_user WHERE username = 'nictest'");

if ($user_exists) {
    $dbh->do( "UPDATE nt_user SET password = ?, pass_salt = ? WHERE username = 'nictest'",
        undef, $pass_hash, $salt );
    print "Updated test user 'nictest' password.\n";
}
else {
    $dbh->do(
        "INSERT INTO nt_user VALUES (2,2,'TestFirst','TestLast','nictest',?,?,'test\@example.com',NULL,0)",
        undef, $pass_hash, $salt
    );
    print "Created test user 'nictest'.\n";
}

$dbh->disconnect;

# Determine project root (two levels up from this script: dist/setup/ -> project root)
my $script_dir = $0;
$script_dir =~ s|/[^/]+$||;
my $project_root = "$script_dir/../..";

# Write server/t/test.cfg
write_test_cfg( "$project_root/server/t/test.cfg", <<EOF );
{

# this specifies the location of the NicTool api client lib
# if it is not installed. (you never ran 'make install' )
lib => 'api/lib',     # in the root dir
lib => '../api/lib',  # in the test dir

# change the following as needed
server_host   => 'localhost',
server_port   => 8082,
data_protocol => 'soap', # can be 'soap' or 'xml_rpc'
username      => 'nictest\@test_group',
password      => '$test_pass',

# for database tests. Set the same as in nictoolserver.conf
dsn     => '$dsn',
db_user => '$db_user',
db_pass => '$db_pass',

}
EOF

# Write server/api/t/test.cfg
write_test_cfg( "$project_root/server/api/t/test.cfg", <<EOF );
# edit the following values
{
server_host   => 'localhost',
server_port   => 8082,
data_protocol => 'soap', # can be 'soap' or 'xml_rpc'
username      => 'nictest\@test_group',
password      => '$test_pass',
}
# the username and password required is a nictool user, typically
# the one automatically created when you run ./create_tables.pl
EOF

print "Generated test.cfg files.\n";

sub write_test_cfg {
    my ( $path, $content ) = @_;
    open( my $fh, '>', $path ) or die "Cannot write $path: $!\n";
    print $fh $content;
    close $fh;
    print "  wrote $path\n";
}

sub _random_password {
    my $length = shift || 20;
    my @chars  = ( 'A' .. 'Z', 'a' .. 'z', '0' .. '9' );
    my $pass   = '';
    $pass .= $chars[ rand @chars ] for 1 .. $length;
    return $pass;
}

sub _get_salt {
    my $length = shift || 16;
    my $chars  = join( '', map chr, 40 .. 126 );
    my $salt   = '';
    $salt .= substr( $chars, rand( length($chars) - 1 ), 1 ) for 0 .. ( $length - 1 );
    return $salt;
}
