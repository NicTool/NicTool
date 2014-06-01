# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
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

=head1 PLAN

 Test interaction between different objects in the system

 1. Deleting a Group which still contains child objects
   A. Zones
   B. User
   C. Group

 2. Deleting a Nameserver which still has zones attached

 3. Add and Modify Records to a deleted Zone

 4. Delegation of deleted objects and to deleted groups

 5. Moving yourself, changing permissions for yourself, deleting yourself.

=cut

use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test;

BEGIN { plan tests => 200 }

$user = new NicTool(
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
die "Couldn't log in" unless noerrok( $user->result );
die "Couldn't log in" unless ok( $user->nt_user_session );

eval {&groups_with_children};
warn $@ if $@;
eval {&nameserver_with_zones};
warn $@ if $@;
eval {&deleted_zones};
warn $@ if $@;
eval {&deleted_records};
warn $@ if $@;
eval {&deleted_users};
warn $@ if $@;
eval {&deleted_nameservers};
warn $@ if $@;
eval {&deleted_groups};
warn $@ if $@;
eval {&deleted_objects_delegation};
warn $@ if $@;
eval {&self};
warn $@ if $@;

sub groups_with_children {

    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    #
    # delete group with remaining children
    #

    #
    # zone
    #
    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    if ( noerrok($res) ) {
        $zid = $res->get('nt_zone_id');
        $res = $group1->delete;
        noerrok( $res, 600, 'has zone' );
        ok( $res->get('error_msg') =>
                qr/You can't delete this group until you delete all of its zones/
        );
        ok( $res->get('error_desc') => qr/Failure/ );

        if ( $res->error_code eq 600 ) {
            $res = $user->delete_zones( zone_list => $zid );
            noerrok($res);
            $res = $group1->delete;
            noerrok($res);
        }
        else {
            ok( 0, 1, "Group was already deleted incorrectly" );
            ok( 0, 1, "Not deleting zone $zid" );
        }
    }
    else {
        warn "Couldn't create test zone";
        for ( 1 .. 6 ) { ok(0) }
    }

    #
    # user
    #

    #make a new group
    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_user(
        first_name => 'test',
        last_name  => '1',
        email      => 'test@blah.blah',
        username   => 'testuser1',
        password   => 'testpass',
        password2  => 'testpass'
    );
    if ( noerrok($res) ) {
        $uid = $res->get('nt_user_id');
        $res = $group1->delete;
        noerrok( $res, 600, 'has user' );
        ok( $res->get('error_msg') =>
                qr/You can't delete this group until you delete all of its users/
        );
        ok( $res->get('error_desc') => qr/Failure/ );

        if ( $res->error_code eq 600 ) {
            $res = $user->delete_users( user_list => $uid );
            noerrok($res);
            $res = $group1->delete;
            noerrok($res);
        }
        else {
            ok( 0, 1, "Group was already deleted incorrectly" );
            ok( 0, 1, "Not deleting user $uid" );
        }
    }
    else {
        warn "Couldn't create test user";
        for ( 1 .. 6 ) { ok(0) }
    }

    #
    # group
    #

    #make a new group
    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_group( name => 'sub_test1' );
    if ( noerrok($res) ) {
        $gid = $res->get('nt_group_id');
        $res = $group1->delete;
        noerrok( $res, 600, 'has group' );
        ok( $res->get('error_msg') =>
                qr/You can't delete this group until you delete all of its sub-groups/
        );
        ok( $res->get('error_desc') => qr/Failure/ );

        if ( $res->error_code eq 600 ) {
            $res = $user->delete_group( nt_group_id => $gid );
            noerrok($res);
            $res = $group1->delete;
            noerrok($res);
        }
        else {
            ok( 0, 1, "Group was already deleted incorrectly" );
            ok( 0, 1, "Not deleting group $gid" );
        }
    }
    else {
        warn "Couldn't create test group";
        for ( 1 .. 6 ) { ok(0) }
    }
}

sub nameserver_with_zones {

    #
    # delete nameservers with attached zones
    #

    #
    # zones
    #

    #make a new group
    $res = $user->new_group( name => 'test_delete_me1' );
    noerrok($res);
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    noerrok($group1);
    ok( $group1->id, $gid1 );

    #make new nameserver
    $res = $user->new_nameserver(
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'bind',
        ttl           => 86400
    );
    noerrok($res);
    $nsid = $res->get('nt_nameserver_id');

    #make new zone
    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
        nameservers => $nsid
    );
    noerrok($res);
    $zid1 = $res->get('nt_zone_id');

    #make new zone
    $res = $group1->new_zone(
        zone        => 'test2.com',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
        nameservers => $nsid
    );
    noerrok($res);
    $zid2 = $res->get('nt_zone_id');

    #try to delete nameserver (should fail)
    $res = $user->delete_nameserver( nt_nameserver_id => $nsid );
    noerrok( $res, 600, 'nameserver has zones' );
    ok( $res->get('error_msg') =>
            qr/You can't delete this nameserver until you delete all of its zones/
    );
    ok( $res->get('error_desc') => qr/Failure/ );

    #delete a zone
    $res = $user->delete_zones( zone_list => $zid1 );
    noerrok($res);

    #try to delete nameserver (should still fail)
    $res = $user->delete_nameserver( nt_nameserver_id => $nsid );
    noerrok( $res, 600, 'nameserver has zones' );
    ok( $res->get('error_msg') =>
            qr/You can't delete this nameserver until you delete all of its zones/
    );
    ok( $res->get('error_desc') => qr/Failure/ );

    #delete last zone
    $res = $user->delete_zones( zone_list => $zid2 );
    noerrok($res);

    #try to delete nameserver (should succeed)
    $res = $user->delete_nameserver( nt_nameserver_id => $nsid );
    noerrok($res);

    #delete group
    noerrok( $group1->delete );

}

sub deleted_zones {

    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    noerrok($res);
    $zid1 = $res->get('nt_zone_id');

    $res = $user->new_zone_record(
        nt_zone_id => $zid1,
        name       => 'a',
        type       => 'A',
        address    => '1.2.3.4',
        ttl        => 86400,
    );
    noerrok($res);
    $zrid1 = $res->get('nt_zone_record_id');

    $res = $user->delete_zones( zone_list => $zid1 );
    noerrok($res);

    #try to modify the record

    $res = $user->edit_zone_record(
        nt_zone_record_id => $zrid1,
        name              => 'b',
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,
        qr/Cannot create\/edit records in a deleted zone\./ );
    ok( $res->error_desc, qr/Sanity error/ );

    #try to create a new record

    $res = $user->new_zone_record(
        nt_zone_id => $zid1,
        name       => 'b',
        type       => 'A',
        address    => '1.2.3.4',
        ttl        => 86400,
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,
        qr/Cannot create\/edit records in a deleted zone\./ );
    ok( $res->error_desc, qr/Sanity error/ );

    #try to modify deleted zone
    $res = $user->edit_zone(
        nt_zone_id  => $zid1,
        description => 'this zone is deleted!!',
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot edit deleted zone!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #delete group
    noerrok( $group1->delete );

}

sub deleted_records {

    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    noerrok($res);
    $zid1 = $res->get('nt_zone_id');

    $res = $user->new_zone_record(
        nt_zone_id => $zid1,
        name       => 'a',
        type       => 'A',
        address    => '1.2.3.4',
        ttl        => 86400,
    );
    noerrok($res);
    $zrid1 = $res->get('nt_zone_record_id');

    $res = $user->delete_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);

    #try to modify the record

    $res = $user->edit_zone_record(
        nt_zone_record_id => $zrid1,
        name              => 'b',
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot edit deleted record!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    $res = $user->delete_zones( zone_list => $zid1 );
    noerrok($res);

    #delete group
    noerrok( $group1->delete );

}

sub deleted_users {

    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_user(
        first_name => 'test',
        last_name  => '1',
        email      => 'test@blah.blah',
        username   => 'testuser1',
        password   => 'testpass',
        password2  => 'testpass'
    );
    noerrok($res);
    $uid1 = $res->get('nt_user_id');

    $res = $user->delete_users( user_list => $uid1 );
    noerrok($res);

    #try to edit user
    $res = $user->edit_user(
        nt_user_id => $uid1,
        first_name => 'deleted',
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot edit deleted user!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #delete group
    noerrok( $group1->delete );
}

sub deleted_nameservers {

    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_nameserver(
        name          => 'ns2.somewhere.com.',
        address       => '1.2.3.5',
        export_format => 'djbdns',
        ttl           => 86401,
    );
    noerrok($res);
    $nsid1 = $res->get('nt_nameserver_id');

    $res = $user->delete_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($res);

    #try to edit user
    $res = $user->edit_nameserver(
        nt_nameserver_id => $nsid1,
        address          => '5.4.2.1',
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot edit deleted nameserver!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #delete group
    noerrok( $group1->delete );
}

sub deleted_groups {

    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_group( name => 'testsubgroup', );
    noerrok($res);
    $gid2 = $res->get('nt_group_id');

    $res = $user->get_group( nt_group_id => $gid2, );
    noerrok($res);
    ok( $res->get('deleted'), 0, "new group should not be deleted" );

    $res = $user->new_nameserver(
        nt_group_id   => $gid2,
        name          => 'ns2.somewhere.com.',
        address       => '1.2.3.5',
        export_format => 'djbdns',
        ttl           => 86401,
    );
    noerrok($res);
    $nsid1 = $res->get('nt_nameserver_id');

    #delete the group
    $res = $user->delete_group( nt_group_id => $gid2 );
    noerrok($res);

    $res = $user->get_group( nt_group_id => $gid2, );
    noerrok($res);
    ok( $res->get('deleted'), 1, "group should be deleted" );

    #try to edit group
    $res = $user->edit_group(
        nt_group_id => $gid2,
        name        => 'testsubgroup modified',
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot edit a deleted group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    $res = $user->edit_nameserver(
        nt_nameserver_id => $nsid1,
        name             => 'ns3.somewhere.com',
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot edit nameserver in a deleted group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    $res = $user->new_nameserver(
        nt_group_id   => $gid2,
        name          => 'ns3.somewhere.com.',
        address       => '1.2.3.5',
        export_format => 'djbdns',
        ttl           => 86401,
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot add nameserver to a deleted group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    $res = $user->new_group(
        nt_group_id => $gid2,
        name        => 'testsubgroup2',
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot add group to a deleted group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    $res = $user->new_user(
        nt_group_id => $gid2,
        first_name  => 'test',
        last_name   => '1',
        email       => 'test@blah.blah',
        username    => 'testuser1',
        password    => 'testpass',
        password2   => 'testpass'
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot add user to a deleted group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    $res = $user->new_zone(
        nt_group_id => $gid2,
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot add zone to a deleted group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #delete group
    noerrok( $group1->delete );
}

sub deleted_objects_delegation {

    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_group( name => 'testsubgroup', );
    noerrok($res);
    $gid2 = $res->get('nt_group_id');

    $res = $user->get_group( nt_group_id => $gid2, );
    noerrok($res);
    ok( $res->get('deleted'), 0, "new group should not be deleted" );

    #delete the group
    $res = $user->delete_group( nt_group_id => $gid2 );
    noerrok($res);

    $res = $user->get_group( nt_group_id => $gid2, );
    noerrok($res);
    ok( $res->get('deleted'), 1, "group sohuld be deleted" );

    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    noerrok($res);
    $zid1 = $res->get('nt_zone_id');

    $res = $user->new_zone_record(
        nt_zone_id => $zid1,
        name       => 'a',
        type       => 'A',
        address    => '1.2.3.4',
        ttl        => 86400,
    );
    noerrok($res);
    $zrid1 = $res->get('nt_zone_record_id');

    $res = $user->new_zone_record(
        nt_zone_id => $zid1,
        name       => 'b',
        type       => 'A',
        address    => '4.3.2.1',
        ttl        => 86400,
    );
    noerrok($res);
    $zrid2 = $res->get('nt_zone_record_id');

    #try to delegate zone to deleted group

    $res = $user->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        perm_write  => 1
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot delegate to a deleted group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #try to delegate record to deleted group

    $res = $user->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        perm_write      => 1
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot delegate to a deleted group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #now try delegating deleted objects to a group

    $res = $group1->new_group( name => 'testsubgroup', );
    noerrok($res);
    $gid2 = $res->get('nt_group_id');

    #delete zone record
    $res = $user->delete_zone_record( nt_zone_record_id => $zrid2 );
    noerrok($res);

    #try to delegate zonerecord to group
    $res = $user->delegate_zone_records(
        zonerecord_list => $zrid2,
        nt_group_id     => $gid2
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot delegate deleted objects!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #delete zone
    $res = $user->delete_zones( zone_list => $zid1 );
    noerrok($res);

    #try to delegate zone to group

    $res = $user->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot delegate deleted objects!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #clean up group
    noerrok( $user->delete_group( nt_group_id => $gid2 ) );

    #delete group
    noerrok( $group1->delete );
}

sub self {
    $res = $user->new_group(
        name        => 'test_delete_me1',
        self_write  => 1,
        zone_create => 0,
        zone_delete => 0,
        zone_write  => 0,
    );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    $res = $group1->new_group( name => 'testsubgroup', );
    noerrok($res);
    $gid2 = $res->get('nt_group_id');

    $res = $user->new_user(
        nt_group_id               => $gid1,
        first_name                => 'test',
        last_name                 => '1',
        email                     => 'test@blah.blah',
        username                  => 'testuser1',
        password                  => 'testpass',
        password2                 => 'testpass',
        inherit_group_permissions => 1,
    );
    noerrok($res);
    $uid2 = $res->get('nt_user_id');

    #log in as testuser

    $tuser = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );
    die "Couldn't create NicTool Object" unless ok( ref $tuser, 'NicTool' );

    $tuser->login(
        username => 'testuser1@test_delete_me1',
        password => 'testpass'
    );
    die "Couldn't log in" unless noerrok( $tuser->result );
    die "Couldn't log in" unless ok( $tuser->nt_user_session );

    #let test user try to move self

    $res = $tuser->move_users( user_list => $uid2, nt_group_id => $gid2 );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot move yourself to another group!/ );
    ok( $res->error_desc, qr/Sanity error/ );

    #try to change self permissions

    $tuser->user->refresh;
    foreach (qw(zone_write zone_create zone_delete)) {
        ok( $tuser->get($_), 0, "self edit $_ permissions" );
    }
    ok( $tuser->get('self_write'), 1, "self edit self_write permissions" );

    $res = $tuser->edit_user(
        nt_user_id                => $uid2,
        inherit_group_permissions => 0,
        zone_write                => 1,
        zone_create               => 1,
        zone_delete               => 1
    );
    noerrok($res);
    $tuser->user->refresh;
    foreach (qw(zone_write zone_create zone_delete)) {
        ok( $tuser->get($_), 0, "self edit $_ permissions" );
    }
    ok( $tuser->get('self_write'), 1, "self edit self_write permissions" );

    noerrok(
        $user->edit_user(
            nt_user_id  => $uid2,
            zone_write  => 1,
            zone_create => 1,
            zone_delete => 1,
            self_write  => 1
        )
    );

    $tuser->user->refresh;
    foreach (qw(zone_write zone_create zone_delete)) {
        ok( $tuser->get($_), 1, "root edit $_ permissions" );
    }
    ok( $tuser->get('self_write'), 1, "root edit self_write permissions" );

    $res = $tuser->edit_user(
        nt_user_id                => $uid2,
        inherit_group_permissions => 0,
        zone_write                => 0,
        zone_create               => 0,
        zone_delete               => 0
    );
    noerrok($res);
    $tuser->user->refresh;
    foreach (qw(zone_write zone_create zone_delete)) {
        ok( $tuser->get($_), 1, "self edit $_ permissions" );
    }
    ok( $tuser->get('self_write'), 1, "self edit self_write permissions" );

    $user1 = $user->get_user( nt_user_id => $uid2 );
    noerrok($user1);
    foreach (qw(zone_write zone_create zone_delete)) {
        ok( $user1->get($_), 1, "self edit $_ permissions" );
    }
    ok( $user1->get('self_write'), 1, "self edit self_write permissions" );

    #try to delete self
    $res = $tuser->delete_users( user_list => $uid2 );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/Not allowed to delete self/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #clean up user
    noerrok( $user->delete_users( user_list => $uid2 ) );

    #clean up group
    noerrok( $user->delete_group( nt_group_id => $gid2 ) );

    #delete group
    noerrok( $group1->delete );
}
