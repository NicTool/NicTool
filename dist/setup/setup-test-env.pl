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
my $test_gid;

# Generate a random password for the test user
my $test_pass = _random_password(20);
my $salt      = _get_salt(16);
my $pass_hash = unpack( "H*", Crypt::KeyDerivation::pbkdf2( $test_pass, $salt, 5000, 'SHA512' ) );

my $dsn = "DBI:$db_engine:database=$db_name;host=$db_host;port=3306";
$dsn .= ";mysql_ssl=1" if $ENV{DB_SSL};
my %opts = ( RaiseError => 1 );
$opts{mysql_ssl} = 1 if $ENV{DB_SSL};
my $dbh = DBI->connect( $dsn, $db_user, $db_pass, \%opts )
    or die "Cannot connect to $dsn: $DBI::errstr\n";

# The ids are whatever the database hands out: a database with real data
# in it already has a group 2 and a user 2.
($test_gid) = $dbh->selectrow_array(
    "SELECT nt_group_id FROM nt_group WHERE parent_group_id = 1 AND name = 'test_group' AND deleted = 0"
);

unless ($test_gid) {
    print "Creating test group and user...\n";
    $dbh->do("INSERT INTO nt_group (parent_group_id, name, deleted) VALUES (1,'test_group', 0)");
    $test_gid = $dbh->last_insert_id( undef, undef, 'nt_group', 'nt_group_id' );
    $dbh->do(
        "INSERT INTO nt_group_log (nt_group_id, nt_user_id, action, timestamp, modified_group_id, parent_group_id, name)
         VALUES (?,1,'added',UNIX_TIMESTAMP(),?,1,'test_group')",
        undef, $test_gid, $test_gid
    );
}

# a test_group that was there already may be a plain group: give it what the tests need
my ($linked) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM nt_group_subgroups WHERE nt_group_id = 1 AND nt_subgroup_id = ?", undef, $test_gid );
$dbh->do( "INSERT INTO nt_group_subgroups VALUES (1,?,1000)", undef, $test_gid ) unless $linked;
my ($perm_exists) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM nt_perm WHERE nt_group_id = ? AND nt_user_id IS NULL AND deleted = 0",
    undef, $test_gid );
unless ($perm_exists) {
    $dbh->do(
        "INSERT INTO nt_perm (nt_group_id, nt_user_id, inherit_perm, perm_name,
            group_write, group_create, group_delete, zone_write, zone_create, zone_delegate, zone_delete,
            zonerecord_write, zonerecord_create, zonerecord_delegate, zonerecord_delete,
            user_write, user_create, user_delete, nameserver_write, nameserver_create, nameserver_delete,
            self_write, usable_ns, deleted)
         VALUES (?,NULL,NULL,NULL,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,'1,2,3',0)",
        undef, $test_gid
    );
}

# logins are user\@group, so only a nictest in the test group counts
my ($user_exists) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM nt_user WHERE username = 'nictest' AND nt_group_id = ? AND deleted = 0",
    undef, $test_gid );

if ($user_exists) {
    $dbh->do( "UPDATE nt_user SET password = ?, pass_salt = ? WHERE username = 'nictest' AND nt_group_id = ?",
        undef, $pass_hash, $salt, $test_gid );
    print "Updated test user 'nictest' password.\n";
}
else {
    $dbh->do(
        "INSERT INTO nt_user (nt_group_id, first_name, last_name, username, password, pass_salt, email, is_admin, deleted)
         VALUES (?,'TestFirst','TestLast','nictest',?,?,'test\@example.com',NULL,0)",
        undef, $test_gid, $pass_hash, $salt
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

# the REST bridge to the v3 API
write_test_cfg( "$project_root/server/t/test-rest.cfg", <<EOF );
{
server_host       => 'api',
server_port       => 3000,
transfer_protocol => 'http',
data_protocol     => 'rest',
username          => 'nictest\@test_group',
password          => '$test_pass',
test_gid          => $test_gid,
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
