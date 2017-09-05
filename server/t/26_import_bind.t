# NicTool v2.34 Copyright 2015 The Network People, Inc.
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
use warnings;

use lib 't';
use lib 'lib';
use NicToolTest;
use Test::More 'no_plan';
use NicToolServer::Import::BIND;


my $nt_api = nt_api_connect();
my $bind = nt_import_connect();

my $res = $nt_api->get_group->new_group( name => 'test_delete_group' );
noerrok($res)
    && ok( $res->get('nt_group_id') =~ qr/^\d+$/ )
        or die "Couldn't create test group";
my $gid1 = $res->get('nt_group_id');


my $group1 = $nt_api->get_group( nt_group_id => $gid1 );
noerrok($group1)
    && is( $group1->id, $gid1 )
        or die "Couldn't get test group1";

$bind->{group_id} = $group1;

$bind->import_records('t/fixtures/named.conf');

do_cleanup();

done_testing();
exit;

sub do_cleanup {
    foreach my $zone (qw/ 1.0.10.in-addr.arpa 138.80.85.in-addr.arpa example.com /) {
        my $r = $nt_api->get_group_zones(
            nt_group_id       => $group1,
            include_subgroups => 1,
            Search            => 1,
            '1_field'         => 'zone',
            '1_option'        => 'equals',
            '1_value'         => $zone,
        );
        isa_ok($r, 'NicTool::Result');
        for my $z ( $r->list ) {
            ok( $nt_api->delete_zones( zone_list => $z->id ), "delete_zones" );
        }
    }

    my $r = $nt_api->delete_group( nt_group_id => $gid1 );
    noerrok($r);
}

sub nt_import_connect () {
    my $bind = NicToolServer::Import::BIND->new();
    $bind->nt_connect(
        Config('server_host'),
        Config('server_port'),
        Config('username'),
        Config('password')
        );
    return $bind;
}

