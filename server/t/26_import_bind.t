# NicTool v2.40 Copyright 2015-2026 The Network People, Inc.
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
my $bind   = nt_import_connect();

my $res = $nt_api->get_group->new_group( name => 'test_delete_group' );
noerrok($res) && ok( $res->get('nt_group_id') =~ qr/^\d+$/ )
    or die "Couldn't create test group";
my $gid1 = $res->get('nt_group_id');

my $group1 = $nt_api->get_group( nt_group_id => $gid1 );
noerrok($group1) && is( $group1->id, $gid1 )
    or die "Couldn't get test group1";

$bind->{group_id} = $group1;

eval { $bind->import_records('t/fixtures/named.conf'); 1 };
my $import_error = $@;
ok( !$import_error, 'initial import succeeds' ) or diag $import_error;

eval { $bind->import_records('t/fixtures/named.conf'); 1 };
$import_error = $@;
ok( !$import_error, 'rerun import succeeds with existing records' ) or diag $import_error;

my @nameserver_ids;
for my $number ( 1 .. 3 ) {
    $res = $group1->new_nameserver(
        name          => "ns$number.import-bind.test.",
        address       => "192.0.2.$number",
        export_format => 'bind',
        ttl           => 86400,
    );
    noerrok($res) && ok( $res->get('nt_nameserver_id') =~ qr/^\d+$/ )
        or die "Couldn't create test nameserver";
    push @nameserver_ids, $res->get('nt_nameserver_id');
}

my $parent_group = $nt_api->get_group;
$res = $parent_group->new_nameserver(
    name          => "ns4.import-bind.test.",
    address       => "192.0.2.4",
    export_format => 'bind',
    ttl           => 86400,
);
noerrok($res) && ok( $res->get('nt_nameserver_id') =~ qr/^\d+$/ )
    or die "Couldn't create the parent group nameserver";
push @nameserver_ids, $res->get('nt_nameserver_id');

eval { $bind->import_records('t/fixtures/import-bind.conf'); 1 };
$import_error = $@;
ok( !$import_error, 'group nameserver import succeeds' ) or diag $import_error;

eval { $bind->import_records('t/fixtures/import-bind.conf'); 1 };
$import_error = $@;
ok( !$import_error, 'group nameserver import rerun succeeds' ) or diag $import_error;

my %parent_ns = map { $_->get('name') => 1 }
    $nt_api->get_usable_nameservers( nt_group_id => $parent_group->id )->list;
ok( $parent_ns{'ns4.import-bind.test.'},
    'the lookup for a group finds that group\'s own nameserver' );
ok( !$parent_ns{'ns1.import-bind.test.'},
    'the lookup for a parent does not reach a child-only nameserver' );

my %child_ns = map { $_->get('name') => 1 }
    $nt_api->get_usable_nameservers( nt_group_id => $gid1 )->list;
ok( $child_ns{'ns1.import-bind.test.'}, 'the lookup for a child finds the child nameserver' );
ok( $child_ns{'ns4.import-bind.test.'}, 'the lookup climbs from the child to the parent nameserver' );

# usable_nameservers is the explicit grant a group gets for a nameserver it does
# not own. The group walk is ORed with it, so widening one must not drop it.
$res = $group1->edit_group( usable_nameservers => [ $nameserver_ids[3] ] );
noerrok($res);
my %granted_ns = map { $_->get('name') => 1 }
    $nt_api->get_usable_nameservers( nt_group_id => $gid1 )->list;
ok( $granted_ns{'ns4.import-bind.test.'}, 'a granted nameserver stays in the list' );

do_cleanup();

done_testing();
exit;

sub do_cleanup {
    foreach my $zone (qw/ 1.0.10.in-addr.arpa 138.80.85.in-addr.arpa example.com import-bind.test /) {
        my $r = $nt_api->get_group_zones(
            nt_group_id       => $group1,
            include_subgroups => 1,
            Search            => 1,
            '1_field'         => 'zone',
            '1_option'        => 'equals',
            '1_value'         => $zone,
        );
        isa_ok( $r, 'NicTool::Result' );
        for my $z ( $r->list ) {
            ok( $nt_api->delete_zones( zone_list => $z->id ), "delete_zones" );
        }
    }

    for my $nameserver_id (@nameserver_ids) {
        my $r = $nt_api->delete_nameserver(
            nt_nameserver_id => $nameserver_id,
        );
        noerrok($r);
    }

    my $r = $nt_api->delete_group( nt_group_id => $gid1 );
    noerrok($r);
}

sub nt_import_connect {
    my $bind = NicToolServer::Import::BIND->new();
    $bind->nt_connect( Config('server_host'), Config('server_port'),
        Config('username'), Config('password') );
    return $bind;
}
