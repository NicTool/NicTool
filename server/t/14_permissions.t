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

 x permissons setting
 x permissons inheritance
 x test object creation permissions
 x test object modification permissions
 x test object deletion permissions
 x cannot change/create group/user with more perms than you have
 x cannot take away perms from group/user that you don't have
 x test usable_nameservers.  users always inherit from group

=cut

use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test;

BEGIN { plan tests => 4593 }

&start;
eval {&test_perms};
warn $@ if $@;
eval {&test_create};
warn $@ if $@;
eval {&test_modify};
warn $@ if $@;
eval {&test_delete};
warn $@ if $@;
eval {&test_bounds};
warn $@ if $@;
eval {&test_usable_nameservers};
warn $@ if $@;
eval {&del};
warn $@ if $@;

sub start {
    $user = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );
    die "Couldn't create NicTool Object" unless ok( ref $user, 'NicTool' );

    $user->login(
        username => Config('username'),
        password => Config('password'),
    );
    die "Couldn't log in" unless noerrok( $user->result );
    die "Couldn't log in" unless ok( $user->nt_user_session );

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
        first_name                => 'test',
        last_name                 => '1',
        email                     => 'test@blah.blah',
        username                  => 'testuser1',
        password                  => 'testpass',
        password2                 => 'testpass',
        inherit_group_permissions => 1,
    );
    die "Couldn't create test user"
        unless noerrok($res);
    $uid1 = $res->get('nt_user_id');

    #login as test user
    $tuser = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );
    ok( ref $tuser => 'NicTool' );

    $tuser->login(
        username => 'testuser1@test_delete_me1',
        password => 'testpass',
    );
    ok( $tuser->result );

    %perms = (
        group_write  => 0,
        group_create => 0,
        group_delete => 0,

        zone_write    => 0,
        zone_create   => 0,
        zone_delegate => 0,
        zone_delete   => 0,

        zonerecord_write    => 0,
        zonerecord_create   => 0,
        zonerecord_delegate => 0,
        zonerecord_delete   => 0,

        user_write  => 0,
        user_create => 0,
        user_delete => 0,

        nameserver_write  => 0,
        nameserver_create => 0,
        nameserver_delete => 0,

    );
}

sub test_perms {
####################
    # basic perms stuff
####################

    #check group perms

    $res = $group1->edit_group(%perms);
    noerrok($res);

    noerrok( $group1->refresh ) or die "Couldn't get test group $gid1";

    foreach ( keys %perms ) {
        ok( $group1->get($_), $perms{$_} );
    }

    #set and unset each permission for group. check inheritance
    foreach ( keys %perms ) {

        #set perm to TRUE
        $perms{$_} = 1;

        $res = $group1->edit_group( $_ => 1 );
        noerrok($res);

        noerrok( $group1->refresh )
            or die "Couldn't refresh test group $gid1";

        foreach $k ( keys %perms ) {
            ok( $group1->get($k), $perms{$k},
                "perm $_ set to 1: $k incorrect" );
        }

        noerrok( $tuser->refresh ) or die "Couldn't refresh test user $uid1";

        foreach $k ( keys %perms ) {
            ok( $tuser->get($k), $perms{$k},
                "perm $_ set to 1: $k incorrect" );
        }

        #set perm to FALSE
        $perms{$_} = 0;

        $res = $group1->edit_group( $_ => 0 );
        noerrok($res);

        noerrok( $group1->refresh )
            or die "Couldn't refresh test group $gid1";

        foreach $k ( keys %perms ) {
            ok( $group1->get($k), $perms{$k},
                "perm $_ set to 0: $k incorrect" );
        }

        noerrok( $tuser->refresh ) or die "Couldn't refresh test user $uid1";

        foreach $k ( keys %perms ) {
            ok( $tuser->get($k), $perms{$k},
                "perm $_ set to 0: $k incorrect" );
        }

    }

    #set and unset each permission for user
    foreach $p ( keys %perms ) {

        #set perm to TRUE
        $perms{$p} = 1;

        $res = $user->edit_user(
            nt_user_id                => $uid1,
            $p                        => 1,
            inherit_group_permissions => 0
        );
        noerrok($res);

        noerrok( $group1->refresh )
            or die "Couldn't refresh test group $gid1";

        foreach $k ( keys %perms ) {
            ok( $group1->get($k), 0, "user perm $p set to 1: $k incorrect" );
        }

        noerrok( $tuser->refresh ) or die "Couldn't refresh test user $uid1";

        foreach $k ( keys %perms ) {
            ok( $tuser->get($k), $perms{$k},
                "user perm $p set to 1: $k incorrect" );
        }

        #set perm to FALSE
        $perms{$p} = 0;

        $res = $user->edit_user( nt_user_id => $uid1, $p => 0 );
        noerrok($res);

        noerrok( $group1->refresh )
            or die "Couldn't refresh test group $gid1";

        foreach $k ( keys %perms ) {
            ok( $group1->get($k), 0, "user perm $p set to 0: $k incorrect" );
        }

        noerrok( $tuser->refresh ) or die "Couldn't refresh test user $uid1";

        foreach $k ( keys %perms ) {
            ok( $tuser->get($k), $perms{$k},
                "user perm $p set to 0: $k incorrect" );
        }
    }

    #make user inherit perms again
    $res = $user->edit_user(
        nt_user_id                => $uid1,
        inherit_group_permissions => 1
    );
    noerrok($res) or die "Couldn't modify test user perms";

    # check inheritance again
    foreach ( keys %perms ) {

        #set perm to TRUE
        $perms{$_} = 1;

        $res = $group1->edit_group( $_ => 1 );
        noerrok($res);

        noerrok( $group1->refresh )
            or die "Couldn't refresh test group $gid1";

        foreach $k ( keys %perms ) {
            ok( $group1->get($k), $perms{$k}, "perm $_ set to 1" );
        }

        noerrok( $tuser->refresh ) or die "Couldn't refresh test user $uid1";

        foreach $k ( keys %perms ) {
            ok( $tuser->get($k), $perms{$k}, "perm $_ set to 1" );
        }

        #set perm to FALSE
        $perms{$_} = 0;

        $res = $group1->edit_group( $_ => 0 );
        noerrok($res);

        noerrok( $group1->refresh )
            or die "Couldn't refresh test group $gid1";

        foreach $k ( keys %perms ) {
            ok( $group1->get($k), $perms{$k}, "perm $_ set to 0" );
        }

        noerrok( $tuser->refresh ) or die "Couldn't refresh test user $uid1";

        foreach $k ( keys %perms ) {
            ok( $tuser->get($k), $perms{$k}, "perm $_ set to 0" );
        }

    }

}

sub test_create {
####################
    # no create permissions
####################

    #try to create

    #zone

    $res = $tuser->new_zone(
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

    noerrok( $res, 404, "create zone" );
    ok( $res->error_msg, qr/Not allowed to create new zone/ );

    # let user create zones

    $res = $group1->edit_group( zone_create => 1, );
    noerrok($res);

    #create zone

    $res = $tuser->new_zone(
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
    $zid = $res->get('nt_zone_id');
    ok( $zid, qr/^\d+$/ );

    $res = $user->delete_zones( zone_list => $zid );
    noerrok($res) or die "Couldn't delete test zone ID $zid !";

    # don't let user create zones

    $res = $group1->edit_group( zone_create => 0, );
    noerrok($res);

    #user

    $res = $tuser->new_user(
        first_name => 'test',
        last_name  => '1',
        email      => 'test@blah.blah',
        username   => 'testuser2',
        password   => 'testpass',
        password2  => 'testpass',
    );

    noerrok( $res, 404, "create user" );
    ok( $res->error_msg, qr/Not allowed to create new user/ );

    #let user create users

    $res = $group1->edit_group( user_create => 1, );
    noerrok($res);

    #create test user

    $res = $tuser->new_user(
        first_name => 'test',
        last_name  => '1',
        email      => 'test@blah.blah',
        username   => 'testuser2',
        password   => 'testpass',
        password2  => 'testpass',
    );

    noerrok($res);
    $uid = $res->get('nt_user_id');
    ok( $uid, qr/^\d+$/ );

    #delete user

    $res = $user->delete_users( user_list => $uid );
    noerrok($res) or die "Couldn't delete test user ID $uid !";

    #don't let user create users

    $res = $group1->edit_group( user_create => 0, );
    noerrok($res);

    #nameserver

    $res = $tuser->new_nameserver(
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'bind',
        ttl           => 86400
    );

    noerrok( $res, 404, "create nameserver" );
    ok( $res->error_msg, qr/Not allowed to create new nameserver/ );

    #let user create nameservers

    $res = $group1->edit_group( nameserver_create => 1, );
    noerrok($res);

    #create nameserver

    $res = $tuser->new_nameserver(
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'bind',
        ttl           => 86400
    );

    noerrok($res);
    $nsid = $res->get('nt_nameserver_id');
    ok( $nsid, qr/^\d+$/ );

    $res = $user->delete_nameserver( nt_nameserver_id => $nsid );
    noerrok($res) or die "Couldn't delete test nameserver ID $nsid !";

    #don't let user create nameservers

    $res = $group1->edit_group( nameserver_create => 0, );
    noerrok($res);

    #group
    $res = $tuser->new_group( name => "test_delete_me 2" );

    noerrok( $res, 404, "Create group" );
    ok( $res->error_msg, qr/Not allowed to create new group/ );

    #let user create groups

    $res = $group1->edit_group( group_create => 1, );
    noerrok($res);

    $res = $tuser->new_group( name => "test_delete_me 2" );

    noerrok($res);
    $gid = $res->get('nt_group_id');
    ok( $gid, qr/^\d+$/ );

    $res = $user->delete_group( nt_group_id => $gid );
    noerrok($res) or die "Couldn't delete test group ID $gid !";

    #don't let user create groups

    $res = $group1->edit_group( group_create => 0, );
    noerrok($res);

####################
    # allow user to create zones, but no records
####################

    $res = $group1->edit_group( zone_create => 1, );
    noerrok($res);

####################
    # test user tries to create records
####################

    $res = $tuser->new_zone(
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

    $res = $tuser->new_zone_record(
        nt_zone_id  => $zid1,
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );

    noerrok( $res, 404, "create record" );
    ok( $res->error_msg, qr/Not allowed to create new zonerecord/ );

    $res = $group1->edit_group( zonerecord_create => 1, );
    noerrok($res);

    #now create record

    $res = $tuser->new_zone_record(
        nt_zone_id  => $zid1,
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );

    noerrok($res);
    $zrid = $res->get('nt_zone_record_id');
    ok( $zrid, qr/^\d+$/ );

    $res = $user->delete_zone_record( nt_zone_record_id => $zrid );
    noerrok($res) or die "Couldn't delete test zone record ID $zrid !";

    $res = $user->delete_zones( zone_list => $zid1 );
    noerrok($res) or die "Couldn't delete test zone ID $zid1 !";

}

sub test_modify {
####################
    # test user tries to modify objects
####################

    %perms = (
        %perms,
        zone_create       => 1,
        user_create       => 1,
        group_create      => 1,
        zonerecord_create => 1,
        nameserver_create => 1,
    );

    $res = $group1->edit_group(%perms);

    ####################
    # test zone_write
    ####################

    %zoneorig = (
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

    $res = $tuser->new_zone(%zoneorig);
    noerrok($res);
    $zid1 = $res->get('nt_zone_id');

    #warn "zone id is $zid1";

    #try to edit
    %zone = (
        serial      => '1',
        ttl         => '86401',
        description => 'please delete me',
        mailaddr    => 'hostmaster.test.com',
        refresh     => 11,
        retry       => 21,
        expire      => 31,
        minimum     => 41,
    );
    $res = $tuser->edit_zone( nt_zone_id => $zid1, %zone );
    noerrok( $res, 404, 'edit zone' );
    ok( $res->error_msg,
        qr/You have no 'write' permission for zone objects/ );

    $zone = $tuser->get_zone( nt_zone_id => $zid1 );
    noerrok($zone);

    foreach ( keys %zoneorig ) {
        ok( $zone->get($_), $zoneorig{$_} );
    }

    # set perms correctly

    %perms = ( %perms, zone_write => 1, );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    # try to edit again

    $res = $tuser->edit_zone( nt_zone_id => $zid1, %zone );
    noerrok($res);

    $zone = $tuser->get_zone( nt_zone_id => $zid1 );
    noerrok($zone);

    foreach ( keys %zone ) {
        if ( $_ eq 'serial' ) {
            ok( $zone->get($_), ++$zone{$_} );
            next;
        }
        ok( $zone->get($_), $zone{$_} );
    }

    # delete zone

    $res = $user->delete_zones( zone_list => [$zone] );
    noerrok($res);

    ####################
    # test group_write
    ####################

    #create

    %group = (
        name         => "test_delete_me 2",
        group_write  => 0,
        group_create => 0,
        group_delete => 0,

        zone_write    => 0,
        zone_create   => 0,
        zone_delegate => 0,
        zone_delete   => 0,

        zonerecord_write    => 0,
        zonerecord_create   => 0,
        zonerecord_delegate => 0,
        zonerecord_delete   => 0,

        user_write  => 0,
        user_create => 0,
        user_delete => 0,

        nameserver_write  => 0,
        nameserver_create => 0,
        nameserver_delete => 0,
    );

    $res = $tuser->new_group(%group);

    noerrok($res);
    $gid = $res->get('nt_group_id');

    #try to edit

    $res = $tuser->edit_group(
        nt_group_id       => $gid,
        name              => "please delete me 2",
        group_create      => 1,
        zone_create       => 1,
        zonerecord_create => 1,
        user_create       => 1,
        nameserver_create => 1,
    );

    noerrok( $res, 404, 'edit group' );
    ok( $res->error_msg,
        qr/You have no 'write' permission for group objects/ );

    $group = $tuser->get_group( nt_group_id => $gid );
    noerrok($group);
    foreach ( keys %group ) {
        ok( $group->get($_), $group{$_}, 'settings should not have changed' );
    }

    #set group_write
    %perms = ( %perms, group_write => 1, );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    #try to edit again

    $res = $tuser->edit_group(
        nt_group_id       => $gid,
        name              => "please delete me 2",
        group_create      => 1,
        zone_create       => 1,
        zonerecord_create => 1,
        user_create       => 1,
        nameserver_create => 1,
    );
    ok($res);
    %group = (
        %group,
        name              => "please delete me 2",
        group_create      => 1,
        zone_create       => 1,
        zonerecord_create => 1,
        user_create       => 1,
        nameserver_create => 1,
    );

    $group = $tuser->get_group( nt_group_id => $gid );
    noerrok($group);
    foreach ( keys %group ) {
        ok( $group->get($_), $group{$_}, 'changed group settings' );
    }

    #delete group
    $res = $user->delete_group( nt_group_id => $group );
    noerrok($res);

    ####################
    # test user_write
    ####################

    %usert = (
        first_name => 'testo',
        last_name  => 'chango',
        username   => 'testpermuser',
        email      => 'test@test.com',
    );

    $res = $tuser->new_user(
        password  => 'testpass',
        password2 => 'testpass',
        %usert
    );
    noerrok($res);
    $uid = $res->get('nt_user_id');

    #edit user
    $res = $tuser->edit_user(
        nt_user_id => $uid,
        username   => 'test2permuser',
        first_name => 'Testo',
        last_name  => 'Chango',
        email      => 'test2@test2.com',
    );
    noerrok( $res, 404, "no user_write perm" );
    ok( $res->error_msg,
        qr/You have no 'write' permission for user objects/ );

    $usert = $tuser->get_user( nt_user_id => $uid );
    noerrok($usert);
    foreach ( keys %usert ) {
        ok( $usert->get($_), $usert{$_}, "no user settings should change" );
    }

    #set user_perm to 1
    %perms = ( %perms, user_write => 1 );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    #edit again
    %usert = (
        %usert,
        username   => 'test2permuser',
        first_name => 'Testo',
        last_name  => 'Chango',
        email      => 'test2@test2.com',
    );
    $res = $tuser->edit_user( nt_user_id => $uid, %usert );
    noerrok($res);

    $usert = $tuser->get_user( nt_user_id => $uid );
    noerrok($usert);

    foreach ( keys %usert ) {
        ok( $usert->get($_), $usert{$_}, "user settings should change" );
    }

    #delete user
    #$user->config(debug_request=>1);
    $res = $user->delete_users( user_list => $usert );
    noerrok($res);

    ####################
    # test zonerecord_write
    ####################

    #make zone
    $res = $tuser->new_zone(%zoneorig);
    noerrok($res);
    $zid = $res->get('nt_zone_id');

    #make record
    %record = (
        nt_zone_id  => $zid,
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );
    $res = $tuser->new_zone_record(%record);
    noerrok($res);
    $zrid = $res->get('nt_zone_record_id');

    #try to edit
    $res = $tuser->edit_zone_record(
        nt_zone_record_id => $zrid,
        name              => 'b',
        ttl               => 86401,
        description       => 'record changed',
        type              => 'MX',
        address           => 'mx.somewhere.com.',
        weight            => 1,
    );

    noerrok( $res, 404, "no zonerecord_write perms" );
    ok( $res->error_msg,
        qr/You have no 'write' permission for zonerecord objects/ );

    $zr = $tuser->get_zone_record( nt_zone_record_id => $zrid );
    noerrok($zr);

    foreach ( keys %record ) {
        ok( $zr->get($_), $record{$_}, "no settings should change" );
    }

    #set zonerecord_write to 1

    %perms = ( %perms, zonerecord_write => 1 );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    #edit again
    %record = (
        %record,
        name        => 'b',
        ttl         => 86401,
        description => 'record changed',
        type        => 'MX',
        address     => 'mx.somewhere.com.',
        weight      => 1,
    );
    $res = $tuser->edit_zone_record(
        nt_zone_record_id => $zrid,
        %record,
    );
    noerrok($res);

    $zr = $tuser->get_zone_record( nt_zone_record_id => $zrid );
    noerrok($zr);

    foreach ( keys %record ) {
        ok( $zr->get($_), $record{$_}, "no settings should change" );
    }

    #delete record
    $res = $user->delete_zone_record( nt_zone_record_id => $zrid );
    noerrok($res);

    #delete zone
    $res = $user->delete_zones( zone_list => $zid );
    noerrok($res);

    ####################
    # test nameserver_write
    ####################
    %ns = (
        name          => 'ns.somewhere.com.',
        description   => 'blah blah blah',
        address       => '1.2.3.4',
        export_format => 'djbdns',
    );
    $res = $tuser->new_nameserver(%ns);

    noerrok($res);
    $nsid = $res->get('nt_nameserver_id');

    #try to edit nameserver
    $res = $tuser->edit_nameserver(
        nt_nameserver_id => $nsid,
        name             => 'ns2.somewhere.com.',
        description      => 'new nameserver addr',
        address          => '1.2.3.5',
        export_format    => 'bind',
    );

    noerrok( $res, 404, "no nameserver_write perms" );
    ok( $res->error_msg,
        qr/You have no 'write' permission for nameserver objects/ );

    #check that ns didn't change

    $ns = $tuser->get_nameserver( nt_nameserver_id => $nsid );
    noerrok($ns);

    foreach ( keys %ns ) {
        ok( $ns->get($_), $ns{$_}, "test nameserver: $_ should be $ns{$_}" );
    }

    #set nameserver_write perm to 1
    %perms = ( %perms, nameserver_write => 1 );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    %ns = (
        %ns,
        name          => 'ns2.somewhere.com.',
        description   => 'new nameserver addr',
        address       => '1.2.3.5',
        export_format => 'bind',
    );

    $res = $tuser->edit_nameserver(
        nt_nameserver_id => $nsid,
        %ns,
    );

    noerrok($res);

    $ns = $tuser->get_nameserver( nt_nameserver_id => $nsid );
    noerrok($ns);

    foreach ( keys %ns ) {
        ok( $ns->get($_), $ns{$_},
            "modified test nameserver: $_ should be $ns{$_}" );
    }

    #delete nameserver

    $res = $user->delete_nameserver( nt_nameserver_id => $nsid );
    noerrok($res);

    ####################
    # test self_write
    ####################

    #try to modify self.
    %self = (
        first_name => 'tester',
        last_name  => '234',
        email      => 'testchange@blah.blah',
        username   => 'testuser1changed',
    );

    $res = $tuser->edit_user(%self);

    noerrok( $res, 404, "no self_write perms" );
    ok( $res->error_msg, qr/Not allowed to modify self/ );

    #check self hasn't changed
    $u = $tuser->get_user;
    noerrok($u);
    foreach ( keys %self ) {
        ok( $u->get($_), $tuser->get($_), "$_ shouldn't change for self" );
    }

    #allow self_write

    %perms = ( %perms, self_write => 1 );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    #modify self again

    $res = $tuser->edit_user(%self);
    noerrok($res);

    #check self has changed
    $u = $tuser->get_user;
    noerrok($u);
    foreach ( keys %self ) {
        ok( $u->get($_), $self{$_}, "$_ should change for self" );
    }

}

sub test_delete {
####################
    # test user tries to delete objects
####################

    %perms = (
        %perms,
        zone_create       => 1,
        user_create       => 1,
        group_create      => 1,
        zonerecord_create => 1,
        nameserver_create => 1,
        zone_delete       => 0,
        user_delete       => 0,
        group_delete      => 0,
        zonerecord_delete => 0,
        nameserver_delete => 0,
    );

    $res = $group1->edit_group(%perms);

    ####################
    # test zone_delete
    ####################

    %zoneorig = (
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

    $res = $tuser->new_zone(%zoneorig);
    noerrok($res);
    $zid1 = $res->get('nt_zone_id');

    #warn "zone id is $zid1";

    #try to delete
    $res = $tuser->delete_zones( zone_list => $zid1 );
    noerrok( $res, 404, 'delete zone' );
    ok( $res->error_msg,
        qr/You have no 'delete' permission for zone objects/ );

    $zone = $tuser->get_zone( nt_zone_id => $zid1 );
    noerrok($zone);
    ok( $zone->get('deleted'), 0, "zone should not be deleted" );

    # set perms correctly

    %perms = ( %perms, zone_delete => 1, );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    # try to edit again

    $res = $tuser->delete_zones( zone_list => $zid1 );
    noerrok($res);

    $zone = $tuser->get_zone( nt_zone_id => $zid1 );
    noerrok($zone);

    ok( $zone->get('deleted'), 1, "zone should not be deleted" );

    # delete zone

    if ( !$zone->is_deleted ) {
        $user->delete_zones( zone_list => $zid1 );
    }

    ####################
    # test group_delete
    ####################

    #create

    %group = (
        name         => "test_delete_me 2",
        group_write  => 0,
        group_create => 0,
        group_delete => 0,

        zone_write    => 0,
        zone_create   => 0,
        zone_delegate => 0,
        zone_delete   => 0,

        zonerecord_write    => 0,
        zonerecord_create   => 0,
        zonerecord_delegate => 0,
        zonerecord_delete   => 0,

        user_write  => 0,
        user_create => 0,
        user_delete => 0,

        nameserver_write  => 0,
        nameserver_create => 0,
        nameserver_delete => 0,
    );

    $res = $tuser->new_group(%group);

    noerrok($res);
    $gid = $res->get('nt_group_id');

    #try to delete

    $res = $tuser->delete_group( nt_group_id => $gid );

    noerrok( $res, 404, 'delete group' );
    ok( $res->error_msg,
        qr/You have no 'delete' permission for group objects/ );

    $group = $tuser->get_group( nt_group_id => $gid );
    noerrok($group);
    ok( $group->get('deleted') => 0, "group should not be deleted" );

    #set group_delete
    %perms = ( %perms, group_delete => 1, );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    #try to delete again

    $res = $tuser->delete_group( nt_group_id => $gid );
    ok($res);

    $group = $tuser->get_group( nt_group_id => $gid );
    noerrok($group);
    ok( $group->get('deleted') => 1, "group should be deleted" );

    if ( !$group->is_deleted ) {
        $user->delete_group( nt_group_id => $gid );
    }

    ####################
    # test user_delete
    ####################

    %usert = (
        first_name => 'testo',
        last_name  => 'chango',
        username   => 'testpermuser',
        email      => 'test@test.com',
    );

    $res = $tuser->new_user(
        password  => 'testpass',
        password2 => 'testpass',
        %usert
    );
    noerrok($res);
    $uid = $res->get('nt_user_id');

    #delete user
    $res = $tuser->delete_users( user_list => $uid );
    noerrok( $res, 404, "no user_delete perm" );
    ok( $res->error_msg,
        qr/You have no 'delete' permission for user objects/ );

    $usert = $tuser->get_user( nt_user_id => $uid );
    noerrok($usert);
    ok( $usert->is_deleted, 0, "user should not be deleted" );

    #set user_delete to 1
    %perms = ( %perms, user_delete => 1 );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    #delete again
    $res = $tuser->delete_users( user_list => $uid );
    noerrok($res);

    $usert = $tuser->get_user( nt_user_id => $uid );
    noerrok($usert);

    ok( $usert->is_deleted, 1, "user should be deleted" );

    if ( !$usert->is_deleted ) {
        $user->delete_users( user_list => $uid );
    }

    ####################
    # test zonerecord_delete
    ####################
    %zoneorig = (
        zone        => 'test.com',
        serial      => 0,
        ttl         => '86400',
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );

    #make zone
    $res = $tuser->new_zone(%zoneorig);
    noerrok($res);
    $zid = $res->get('nt_zone_id');

    #make record
    %record = (
        nt_zone_id  => $zid,
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );
    $res = $tuser->new_zone_record(%record);
    noerrok($res);
    $zrid = $res->get('nt_zone_record_id');

    #try to delete
    $res = $tuser->delete_zone_record( nt_zone_record_id => $zrid );

    noerrok( $res, 404, "no zonerecord_delete perms" );
    ok( $res->error_msg,
        qr/You have no 'delete' permission for zonerecord objects/ );

    $zr = $tuser->get_zone_record( nt_zone_record_id => $zrid );
    noerrok($zr);

    ok( $zr->is_deleted, 0, "record should not be deleted" );

    #set zonerecord_delete to 1

    %perms = ( %perms, zonerecord_delete => 1 );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    #delete again
    $res = $tuser->delete_zone_record( nt_zone_record_id => $zrid );
    noerrok($res);

    $zr = $tuser->get_zone_record( nt_zone_record_id => $zrid );
    noerrok($zr);

    ok( $zr->is_deleted, 1, "record should be deleted" );

    if ( !$zr->is_deleted ) {

        #delete record
        $res = $user->delete_zone_record( nt_zone_record_id => $zrid );
    }

    #delete zone
    $res = $user->delete_zones( zone_list => $zid );
    noerrok($res);

    ####################
    # test nameserver_delete
    ####################
    %ns = (
        name          => 'ns.somewhere.com.',
        description   => 'blah blah blah',
        address       => '1.2.3.4',
        export_format => 'djbdns',
    );
    $res = $tuser->new_nameserver(%ns);

    noerrok($res);
    $nsid = $res->get('nt_nameserver_id');

    #try to delete nameserver
    $res = $tuser->delete_nameserver( nt_nameserver_id => $nsid );

    noerrok( $res, 404, "no nameserver_delete perms" );
    ok( $res->error_msg,
        qr/You have no 'delete' permission for nameserver objects/ );

    #check that ns didn't change

    $ns = $tuser->get_nameserver( nt_nameserver_id => $nsid );
    noerrok($ns);
    ok( $ns->is_deleted, 0, "nameserver should not be deleted" );

    #set nameserver_write perm to 1
    %perms = ( %perms, nameserver_delete => 1 );
    $res = $group1->edit_group(%perms);
    noerrok($res);

    #delete again
    $res = $tuser->delete_nameserver( nt_nameserver_id => $nsid );
    noerrok($res);

    $ns = $tuser->get_nameserver( nt_nameserver_id => $nsid );
    noerrok($ns);

    ok( $ns->is_deleted, 1, "nameserver should be deleted" );

    #delete nameserver

    if ( !$ns->is_deleted ) {
        $res = $user->delete_nameserver( nt_nameserver_id => $nsid );
    }

    ####################
    # can never delete self
    ####################

    $res = $tuser->delete_users( user_list => $tuser->user->id );

    noerrok( $res, 404, "no delete self" );
    ok( $res->error_msg, qr/Not allowed to delete self/ );

}

sub test_bounds {

####################
    # a user cannot create or modify a group or user
    # such that the group or user has more action permissions
    # than the creating user.
    # Test this for creating and modifying groups and users.
    # for each permission setting A
    #   change user's perms to full EXCEPT A
    #   user creates group with A
    #   check group NOT A
    #   change group perms to full
    #   user modifies group for NOT A
    #   check group has A
    #   modify group for NOT A
    #   user modifies group for A
    #   check group NOT A
    #
    #   same for new user
    #
####################

    %group = ( name => "test delete me 1" );
    %user = (
        first_name                => 'delete',
        last_name                 => 'me',
        username                  => 'deleteme',
        email                     => 'blah@blog.ug',
        password                  => 'testing123',
        password2                 => 'testing123',
        inherit_group_permissions => 0,

    );
    @perms = qw(
        group_write
        group_create
        group_delete

        zone_write
        zone_create
        zone_delegate
        zone_delete

        zonerecord_write
        zonerecord_create
        zonerecord_delegate
        zonerecord_delete

        user_write
        user_create
        user_delete

        nameserver_write
        nameserver_create
        nameserver_delete
    );

    %trueperms = map { $_ => 1 } @perms;

    $res = $user->edit_user(
        nt_user_id                => $uid1,
        inherit_group_permissions => 1
    );
    noerrok($res);

    foreach $perm (@perms) {

        #modify user so they cannot do $perm
        $res = $group1->edit_group( %trueperms, $perm => 0 );
        noerrok($res);

        if ( $perm ne 'group_create' ) {

            #create group with $perm
            $res = $tuser->new_group( %group, %trueperms, $perm => 1 );
            noerrok($res);
            die "Can't create test group" unless !$res->is_error;
            $gid = $res->get('nt_group_id');

        }
        else {

            #root creates group without $perm
            $res = $user->new_group(
                nt_group_id => $tuser->user->get('nt_group_id'),
                %group, %trueperms, $perm => 0
            );
            noerrok($res);
            die "Can't create test group" unless !$res->is_error;
            $gid = $res->get('nt_group_id');
        }

        #group should not have $perm
        $group = $user->get_group( nt_group_id => $gid );
        noerrok($group);
        ok( $group->get($perm), 0, "create group with $perm" );

        ## set $perm to true for test group
        $res = $user->edit_group( nt_group_id => $gid, $perm => 1 );
        noerrok($res);

        $group = $user->get_group( nt_group_id => $gid );
        noerrok($group);
        ok( $group->get($perm), 1, "create group with $perm" );

        if ( $perm ne 'group_write' ) {

            #test user try to set $perm to 0
            $res = $tuser->edit_group( nt_group_id => $gid, $perm => 0 );
            noerrok($res);

            $group = $user->get_group( nt_group_id => $gid );
            noerrok($group);
            ok( $group->get($perm), 1, "create group with $perm" );

            ## set $perm to false for test group
            $res = $user->edit_group( nt_group_id => $gid, $perm => 0 );
            noerrok($res);

            $group = $user->get_group( nt_group_id => $gid );
            noerrok($group);
            ok( $group->get($perm), 0, "create group with $perm" );

            #test user try to set $perm to 1
            $res = $tuser->edit_group( nt_group_id => $gid, $perm => 1 );
            noerrok($res);

            $group = $user->get_group( nt_group_id => $gid );
            noerrok($group);
            ok( $group->get($perm), 0, "create group with $perm" );

        }

        #delete group
        $res = $user->delete_group( nt_group_id => $gid );
        noerrok($res);
        die "couldn't delete test group ($gid)" if $res->is_error;

        #same tests for user objects

        if ( $perm ne 'user_create' ) {

            #create user with $perm
            $res = $tuser->new_user( %user, %trueperms, $perm => 1 );
            noerrok($res);
            $uid = $res->get('nt_user_id');
        }
        else {

            #root creates user without $perm
            $res = $user->new_user(
                nt_group_id => $tuser->user->get('nt_group_id'),
                %user, %trueperms, $perm => 0
            );
            noerrok($res);
            $uid = $res->get('nt_user_id');
        }

        #user should not have $perm
        $u = $user->get_user( nt_user_id => $uid );
        noerrok($u);
        ok( $u->get($perm), 0, "create user with $perm" );

        ## set $perm to true for test user
        $res = $user->edit_user( nt_user_id => $uid, $perm => 1 );
        noerrok($res);

        $u = $user->get_user( nt_user_id => $uid );
        noerrok($u);
        ok( $u->get($perm), 1, "create user with $perm" );

        if ( $perm ne 'user_write' ) {

            #test user try to set $perm to 0
            $res = $tuser->edit_user( nt_user_id => $uid, $perm => 0 );
            noerrok($res);

            $u = $user->get_user( nt_user_id => $uid );
            noerrok($u);
            ok( $u->get($perm), 1, "modify user with $perm" );

            ## set $perm to false for test user
            $res = $user->edit_user( nt_user_id => $uid, $perm => 0 );
            noerrok($res);

            $u = $user->get_user( nt_user_id => $uid );
            noerrok($u);
            ok( $u->get($perm), 0, "modify user with $perm" );

            #test user try to set $perm to 1
            $res = $tuser->edit_user( nt_user_id => $uid, $perm => 1 );
            noerrok($res);

            $u = $user->get_user( nt_user_id => $uid );
            noerrok($u);
            ok( $u->get($perm), 0, "modify user with $perm" );

        }

        #delete user
        $res = $user->delete_users( user_list => $uid );
        noerrok($res);
        die "couldn't delete test user ($uid)" if $res->is_error;
    }
}

sub test_usable_nameservers {

    #empty usable nameservers
    $res = $group1->edit_group( usable_nameservers => [] );
    noerrok($res);

    $group1->refresh;
    noerrok( $user->result );

    ok( $group1->get('usable_ns'), '', "no usable nameservers" );

    #check user

    $tuser->user->refresh;
    noerrok( $tuser->result );

    ok( $tuser->get('usable_ns'), '', "no usable nameservers" );

    #set usable_nameservers for group
    $res = $group1->edit_group( usable_nameservers => [ 1, 2 ] );
    noerrok($res);

    $group1->refresh;
    noerrok( $user->result );

    ok( $group1->get('usable_ns'), '1,2', "modified usable nameservers" );

    #check user

    $tuser->user->refresh;
    noerrok( $tuser->result );

    ok( $group1->get('usable_ns'), '1,2', "modified usable nameservers" );

    #attempt to modify for user

    $res = $user->edit_user(
        nt_user_id                => $uid1,
        inherit_group_permissions => 0,
        usable_nameservers        => [1]
    );
    noerrok($res);

    #check again

    $tuser->user->refresh;
    noerrok( $tuser->result );

    ok( $tuser->get('usable_ns'), '1,2', "modified usable nameservers" );

    #modify group settings again
    #empty usable nameservers
    $res = $group1->edit_group( usable_nameservers => '' );
    noerrok($res);

    $group1->refresh;
    noerrok( $user->result );

    ok( $group1->get('usable_ns'), '', "no usable nameservers" );

    #check user

    $tuser->user->refresh;
    noerrok( $tuser->result );

    ok( $tuser->get('usable_ns'), '', "no usable nameservers" );
}

sub del {
####################
    # cleanup
####################

    $tuser->logout;

    $res = $user->delete_users( user_list => $uid1 );
    noerrok($res);
    $res = $group1->delete;
    noerrok($res);
    $user->logout;
}
