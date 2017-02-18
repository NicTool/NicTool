# NicTool v2.33 Copyright 2015 The Network People, Inc.
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

# use lib '.';
use lib 't';
use lib 'lib';
# use Data::Dumper;
use NicToolTest;
use Test;
use_ok('NicToolServer::Import::BIND');
# $Data::Dumper::Sortkeys=1;


BEGIN { plan tests => 2 }

my $nt_api = nt_api_connect();
my $bind = nt_import_connect();

ok($nt_api, 'new');
ok($bind, 'new');

my $res = $nt_api->get_group->new_group( name => 'test_delete_group' );
die "Couldn't create test group"
    unless noerrok($res)
        and ok( $res->get('nt_group_id') => qr/^\d+$/ );
my $gid1 = $res->get('nt_group_id');


my $group1 = $nt_api->get_group( nt_group_id => $gid1 );
die "Couldn't get test group1"
    unless noerrok($group1)
        and ok( $group1->id, $gid1 );

$bind->{group_id} = $group1;

$bind->import_records('t/fixtures/named.conf');

done_testing();

exit;


sub nt_api_connect () {
    my $user = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );
    die "Couldn't create NicTool Object" unless ok( ref $user, 'NicTool' );

    $user->login(
        username => Config('username'),
        password => Config('password')
    );

    return $user;
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

