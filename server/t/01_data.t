##########
#
# NicTool v2.09 Copyright 2011 The Network People, Inc.
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
##########
use lib ".";
use lib "t";
use TestConfig;
use Test::More tests => 13;

BEGIN {
    use_ok( 'DBIx::Simple' );
    use_ok( 'NicTool' );
    use_ok( 'NicToolServer' );
};


my $nts = NicToolServer->new();
$NicToolServer::dsn = "DBI:mysql:database=nictool;host=localhost;port=3306";
$NicToolServer::db_user = 'nictool';
$NicToolServer::db_pass = 'lootcin205';

my $dbh = NicToolServer::dbh();
ok( $dbh, 'dbh handle' );
#warn Data::Dumper::Dumper($dbh);
#isa_ok( $dbih, 'DBI::db' );

$nts = NicToolServer->new(undef,undef,$dbh);
#warn Data::Dumper::Dumper($nts);

my $r = $nts->exec_query( "SELECT email FROM nt_user WHERE deleted='0'" );
ok( scalar @$r, "select users: ".scalar @$r );
#warn Data::Dumper::Dumper($r->[0]);

$r = $nts->exec_query( "SELECT emailf FROM nt_user" );
ok( ! $r, "invalid select" );


my $zid = $nts->exec_query( "INSERT INTO nt_zone SET zone='testing.com',deleted='1'");
ok( $zid, "Insert zone ID $zid" );
#warn Data::Dumper::Dumper($r);

$r = $nts->exec_query( "UPDATE nt_zone SET description='delete me' WHERE nt_zone_id=?", $zid);
ok( $r, "Update zone $zid description" );

$r = $nts->exec_query( "UPDATE nt_zone SET descriptionf='delete me' WHERE nt_zone_id=?", $zid);
ok( ! $r, "Update zone error" );

#exit;
$r = $nts->exec_query( "DELETE FROM nt_zone WHERE nt_zone_id=?", $zid);
ok( $r, "Delete zone $zid");


$r = $nts->exec_query( "INSERT INTO nt_zone SET zonef='testing.com',deleted='1'");
ok( ! $r, "Insert zone fail" );
#warn Data::Dumper::Dumper($r);

$r = $nts->exec_query( "DELETE FROM nt_zonef WHERE nt_zone_id=?", $r );
ok( ! $r, "Delete zone fail");


$r = $nts->is_subgroup(1,1);
ok( ! $r, "is_subgroup ($r)");

#$r = $nts->is_subgroup(1,320);
#ok( $r, "is_subgroup ($r)");

diag( "Testing NicToolServer $NicToolServer::VERSION, Perl $], $^X" );



