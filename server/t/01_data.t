# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01+ Copyright 2011 The Network People, Inc.
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

use strict;

use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use Test::More tests => 39;
use Test::Output;
use Data::Dumper;


BEGIN {
    use_ok( 'DBIx::Simple' );
    use_ok( 'NicTool' );
    use_ok( 'NicToolServer' );
    use_ok( 'NicToolServer::Zone' );
};

my $nts = NicToolServer->new();
$NicToolServer::dsn = Config('dsn');
$NicToolServer::db_user = Config('db_user');
$NicToolServer::db_pass = Config('db_pass');

my $dbh = NicToolServer->dbh();
ok( $dbh, 'dbh handle' );
#warn Data::Dumper::Dumper($dbh);
#isa_ok( $dbih, 'DBI::db' );

$nts = NicToolServer->new(undef,undef,$dbh);
#warn Data::Dumper::Dumper($nts);

# test exec_query
my $dbix = $nts->dbix();
ok( $dbix, "DBIx::Simple handle");

my $r = $nts->exec_query( "SELECT email FROM nt_user WHERE deleted=0" );
ok( scalar @$r, "select users: ".scalar @$r );
#warn Data::Dumper::Dumper($r->[0]);

# clean up after previous tests
$nts->exec_query( "DELETE FROM nt_zone WHERE zone='testing.com'" );

stderr_like { $nts->exec_query( "SELECT testfake FROM nt_user" ) } qr/Unknown column/, 'invalid select';

my $zid = $nts->exec_query( "INSERT INTO nt_zone SET zone='testing.com', nt_group_id=1, deleted=1");
ok( $zid, "Insert zone ID $zid" );
#warn Data::Dumper::Dumper($r);

$r = $nts->exec_query( "UPDATE nt_zone SET description='delete me' WHERE nt_zone_id=?", $zid);
ok( $r, "Update zone $zid description" );

stderr_like { $nts->exec_query( "UPDATE nt_zone SET fake='delete me' WHERE nt_zone_id=?", $zid ) } qr/Unknown column/, 'invalid update';

$r = $nts->exec_query( "DELETE FROM nt_zone WHERE nt_zone_id=?", $zid);
ok( $r, "Delete zone $zid");

stderr_like { $nts->exec_query(
  "INSERT INTO nt_zone SET fake='testing.com',deleted=1"
) } qr/Unknown column/, 'insert zone fail';

stderr_like { $nts->exec_query(
  "DELETE FROM nt_fake WHERE nt_zone_id=?", $r
) } qr/doesn't exist/, 'Delete zone fail';

# is_subgroup
ok( ! $nts->is_subgroup(1,1), 'is_subgroup');

# valid_ttl
foreach ( qw/ -299 -2592001 -2 -1 2147483648 oops / ) {
    ok( ! $nts->valid_ttl( $_ ), "valid_ttl: $_");
};

# valid_ip_address
foreach ( qw/ 1.0.0.0 1.2.3.4 5.6.7.8 255.255.255.254 / ) {
    my $ip = $nts->valid_ip_address( $_ );
    ok( $ip, "valid_ip_address: $_ -> $ip");
};

foreach ( qw/ 0.0.0.0 0.0.0.1 255.255.255.255 / ) {
    my $ip = $nts->valid_ip_address( $_ );
    ok( ! $ip, "valid_ip_address: $_ -> $ip");
};

# serial number tests
my $zone = NicToolServer::Zone->new(undef,undef,$dbh );
my @datestr = localtime(time);
my $year  = $datestr[5] + 1900;
my $month = sprintf( "%02d", $datestr[4] + 1 );
my $day   = sprintf( "%02d", $datestr[3] );

my %serials = (
    1 => 2,
    2 => 3,
    4294967294 => 4294967295,
    4294967295 => 1,
    4500000000 => 1,
    2011010100 => $year . $month . $day . '00',
    $year.$month.$day.'00' => $year . $month . $day . '01',
);

foreach my $k ( sort keys %serials ) {
    my $r = $zone->bump_serial( 1, $k );
    ok( $r == $serials{$k}, "bump_serial, $k -> $serials{$k} ($r)");
};

$r = $zone->bump_serial( 'new' );
ok( $r == $year.$month.$day.'00', "bump_serial, 'new'");


foreach my $opt ( qw/ db_version session_timeout default_group / ) {
    ok( $nts->get_option($opt), "get_option, $opt");
}

#$r = $nts->is_subgroup(1,320);
#ok( $r, "is_subgroup ($r)");

#my $dbix = DBIx::Simple->connect( $nts->{dbh} );
#my $query = "SELECT nt_nameserver_id FROM nt_zone_nameserver WHERE nt_zone_id=?";
#my @nsids = $dbix->query( $query, 25 )->flat;
#warn Dumper(\@nsids);

#use NicToolServer::Zone;
#my $ntz = NicToolServer::Zone->new();
#$ntz->{dbh} = $dbh;
#$ntz->{dbix} = $dbix;
#$r = NicToolServer::Zone::pack_nameservers( undef, { nt_zone_id=>25 } );
#warn Dumper($r);

diag( "Testing NicToolServer $NicToolServer::VERSION, Perl $], $^X" );



