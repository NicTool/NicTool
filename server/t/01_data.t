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

use lib 't';
use NicToolTest;
use Test::More 'no_plan';
use Test::Output;
use Data::Dumper;

BEGIN {
    use_ok( 'DBIx::Simple' );
    use_ok( 'NicTool' );
    use_ok( 'NicToolServer' );
    use_ok( 'NicToolServer::Zone' );
};

my $nts = get_nictoolserver_with_dbh();
my $r;

test_exec_select();
test_cleanups();

my $zid = test_exec_insert();

test_exec_update($zid);
test_exec_delete($zid);


# is_subgroup
ok( ! $nts->is_subgroup(1,1), 'is_subgroup, root');

valid_ttl();
valid_ip_address();
valid_serials();

foreach my $opt ( qw/ db_version session_timeout default_group / ) {
    ok( $nts->get_option($opt), "get_option, $opt");
}

diag( "Testing NicToolServer $NicToolServer::VERSION, Perl $], $^X" );

done_testing();
exit;

sub get_nictoolserver_with_dbh {

    my $nts = NicToolServer->new();

    $NicToolServer::dsn     = Config('dsn');
    $NicToolServer::db_user = Config('db_user');
    $NicToolServer::db_pass = Config('db_pass');

    my $dbh = NicToolServer->dbh();
    ok( $dbh, 'dbh handle' ) or diag Data::Dumper::Dumper($dbh);
    isa_ok( $dbh, 'DBI::db' );

    $nts = NicToolServer->new(undef, undef, $dbh) or
        warn Data::Dumper::Dumper($nts);

    return $nts;
}

sub test_exec_select {

    my $dbix = $nts->dbix();
    ok( $dbix, "DBIx::Simple handle");

    my $r = $nts->exec_query( "SELECT email FROM nt_user WHERE deleted=0" );
    ok( scalar @$r, "select users: " . scalar @$r ) or
        diag Data::Dumper::Dumper($r->[0]);


    stderr_like {
        $nts->exec_query( "SELECT testfake FROM nt_user" )
    }
    qr/Unknown column/, 'invalid select';
}

sub test_cleanups {

    # clean up after previous tests
    my $r = $nts->exec_query( "DELETE FROM nt_zone WHERE zone='testing.com'" );
    if ($r) {
        print "deleted $r records\n";
    }
}

sub test_exec_insert {

    my $zid = $nts->exec_query(
        "INSERT INTO nt_zone SET zone='testing.com', nt_group_id=1, deleted=1"
    );

    ok( $zid, "Insert zone ID $zid" )
        or diag Data::Dumper::Dumper($zid);


    stderr_like {
        $nts->exec_query("INSERT INTO nt_zone SET fake='testing.com',deleted=1")
    }
    qr/Unknown column/, 'insert zone fail';

    return $zid;
}

sub test_exec_update {
    my $zid = shift;

    my $r = $nts->exec_query(
        "UPDATE nt_zone SET description='delete me' WHERE nt_zone_id=?",
        $zid
    );
    ok( $r, "Update zone $zid description" );

    stderr_like {
        $nts->exec_query(
            "UPDATE nt_zone SET fake='delete me' WHERE nt_zone_id=?", $zid )
    }
    qr/Unknown column/, 'invalid update';
}

sub test_exec_delete {
    my $zid = shift;

    $r = $nts->exec_query( "DELETE FROM nt_zone WHERE nt_zone_id=?", $zid);
    ok( $r, "Delete zone $zid");

    stderr_like {
        $nts->exec_query("DELETE FROM nt_fake WHERE nt_zone_id=1")
    }
    qr/doesn't exist/, 'Delete zone fail';
}

sub valid_ttl {
    foreach ( qw/ 1 100 1000 2147483647 / ) {
        ok( $nts->valid_ttl( $_ ), "valid_ttl: $_");
    };

    foreach ( qw/ -299 -2592001 -2 -1 2147483648 oops / ) {
        ok( ! $nts->valid_ttl( $_ ), "invalid_ttl: $_");
    };
}

sub valid_ip_address {

    foreach ( qw/ 1.0.0.0 1.2.3.4 5.6.7.8 255.255.255.254 / ) {
        my $ip = $nts->valid_ip_address( $_ );
        ok( $ip, "valid_ip_address: $_ -> $ip");
    };

    foreach ( qw/ 0.0.0.0 0.0.0.1 255.255.255.255 / ) {
        my $ip = $nts->valid_ip_address( $_ );
        ok( ! $ip, "valid_ip_address: $_ -> $ip");
    };
}

sub valid_serials {
    my $zone = NicToolServer::Zone->new(undef, undef, NicToolServer->dbh());
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
}
