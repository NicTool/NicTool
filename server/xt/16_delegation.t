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

 x test delegation API calls
 x create zone + record(s)
 x create sub group
 x try delegation without delgation perms
 x try delegation with perms
 x log in to sub group and verify delegation perms correct
 x zones - redelegation, deletion, modification, record add, record del
         - no inappropriate access to "pseudo" delegated records
 x records - modify, delete, redelegate
          - no inappropriate access to "pseudo" delegated zones

=cut

use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test;

BEGIN { plan tests => 779 }

#no group permissions
%permsnone = (
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

#full group permissions
%permsfull = (
    group_write  => 1,
    group_create => 1,
    group_delete => 1,

    zone_write    => 1,
    zone_create   => 1,
    zone_delegate => 1,
    zone_delete   => 1,

    zonerecord_write    => 1,
    zonerecord_create   => 1,
    zonerecord_delegate => 1,
    zonerecord_delete   => 1,

    user_write  => 1,
    user_create => 1,
    user_delete => 1,

    nameserver_write  => 1,
    nameserver_create => 1,
    nameserver_delete => 1,

);

#full delegation permissions for zone
%dpermsfull = (
    perm_write               => 1,
    perm_delete              => 1,
    perm_delegate            => 1,
    zone_perm_add_records    => 1,
    zone_perm_delete_records => 1,

    #zone_perm_modify_zone=>1,
    #zone_perm_modify_mailaddr=>1,
    #zone_perm_modify_desc=>1,
    #zone_perm_modify_minimum=>1,
    #zone_perm_modify_serial=>1,
    #zone_perm_modify_refresh=>1,
    #zone_perm_modify_retry=>1,
    #zone_perm_modify_expire=>1,
    #zone_perm_modify_ttl=>1,
    #zone_perm_modify_nameservers=>1,
);

#no delegation permissions for zone
%dpermsnone = (
    perm_write               => 0,
    perm_delete              => 0,
    perm_delegate            => 0,
    zone_perm_add_records    => 0,
    zone_perm_delete_records => 0,

    #zone_perm_modify_zone=>0,
    #zone_perm_modify_mailaddr=>0,
    #zone_perm_modify_desc=>0,
    #zone_perm_modify_minimum=>0,
    #zone_perm_modify_serial=>0,
    #zone_perm_modify_refresh=>0,
    #zone_perm_modify_retry=>0,
    #zone_perm_modify_expire=>0,
    #zone_perm_modify_ttl=>0,
    #zone_perm_modify_nameservers=>0,
);

#full delegation permissions for zone records
%dzrpermsfull = (
    perm_write    => 1,
    perm_delete   => 1,
    perm_delegate => 1,

    #zonerecord_perm_modify_name=>1,
    #zonerecord_perm_modify_type=>1,
    #zonerecord_perm_modify_addr=>1,
    #zonerecord_perm_modify_weight=>1,
    #zonerecord_perm_modify_ttl=>1,
    #zonerecord_perm_modify_desc=>1,
);

%dpermmap = (
    perm_write               => 'delegate_write',
    perm_delete              => 'delegate_delete',
    perm_delegate            => 'delegate_delegate',
    zone_perm_add_records    => 'delegate_add_records',
    zone_perm_delete_records => 'delegate_delete_records',
);

&start;

eval {&test_api_funcs};
eval {&test_zones};
eval {&test_zone_records};
warn $@ if $@;
&del;

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
        password => Config('password')
    );
    die "Couldn't log in" unless noerrok( $user->result );
    die "Couldn't log in" unless ok( $user->nt_user_session );

    #make a new group
    $res = $user->new_group( name => 'test_delete_me1', %permsfull );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    # new user in group
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

    #make new zone
    $res = $user->new_zone(
        zone        => 'highlevel.com',
        serial      => 0,
        ttl         => 86400,
        description => "delegation test delete me",
        mailaddr    => "root.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    noerrok($res);
    $zid0 = $res->get('nt_zone_id');

    #new record in zone

    $res = $user->new_zone_record(
        nt_zone_id  => $zid0,
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );
    noerrok($res);
    $zrid0 = $res->get('nt_zone_record_id');

    #subgroup
    $res = $group1->new_group( name => 'testsubgroup', %permsfull );
    die "Couldn't create test subgroup"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid2 = $res->get('nt_group_id');

    $subg = $user->get_group( nt_group_id => $gid2 );
    die "Couldn't get test subgroup"
        unless noerrok($subg)
            and ok( $subg->id, $gid2 );

    $res = $subg->new_user(
        first_name                => 'test2',
        last_name                 => '2',
        email                     => 'test2@blah.blah',
        username                  => 'testuser2',
        password                  => 'testpass2',
        password2                 => 'testpass2',
        inherit_group_permissions => 1,
    );
    die "Couldn't create test user"
        unless noerrok($res);
    $uid2 = $res->get('nt_user_id');

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
        password => 'testpass'
    );
    ok( $tuser->result );

    # another subgroup

    $res = $group1->new_group( name => 'testsubgroup2', %permsfull );
    die "Couldn't create test subgroup2"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid3 = $res->get('nt_group_id');

    #create test zones

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

    $res = $group1->new_zone(
        zone        => 'test2.com',
        serial      => 0,
        ttl         => 86401,
        description => "test delete me also",
        mailaddr    => "other.somewhere.com",
        refresh     => 11,
        retry       => 21,
        expire      => 31,
        minimum     => 41,
    );
    noerrok($res);
    $zid2 = $res->get('nt_zone_id');

    #create 2 test records

    $res = $user->new_zone_record(
        nt_zone_id  => $zid1,
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );
    noerrok($res);
    $zrid1 = $res->get('nt_zone_record_id');

    $res = $user->new_zone_record(
        nt_zone_id  => $zid1,
        name        => 'b',
        ttl         => 86400,
        description => 'record 2',
        type        => 'CNAME',
        address     => 'a.test.com.',
        weight      => 0
    );
    noerrok($res);
    $zrid2 = $res->get('nt_zone_record_id');

} ## end sub start

sub test_api_funcs {

####################
    # test each API function
####################

    ####################
    #delegate_zones
    ####################

    #zone list missing
    $res = $tuser->delegate_zones(
        zone_list   => '',
        nt_group_id => $gid2,
        %dpermsfull,
    );
    noerrok( $res, 301, "no zones" );
    ok( $res->get('error_msg')  => 'zone_list' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #zone list invalid
    $res = $tuser->delegate_zones(
        zone_list   => 'abc',
        nt_group_id => $gid2,
        %dpermsfull,
    );
    noerrok( $res, 302, "zone invalid" );
    ok( $res->get('error_msg')  => 'zone_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #zone list not valid
    $res = $tuser->delegate_zones(
        zone_list   => 0,
        nt_group_id => $gid2,
        %dpermsfull,
    );
    noerrok( $res, 302, "zones invalid" );
    ok( $res->get('error_msg')  => 'zone_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #group id missing
    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => '',
        %dpermsfull,
    );
    noerrok( $res, 301, "no group" );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #group id invalid
    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => 'abc',
        %dpermsfull,
    );
    noerrok( $res, 302, "group id invalid" );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #group id invalid
    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => 0,
        %dpermsfull,
    );
    noerrok( $res, 302, "group id invalid" );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #try true delegation

    %perms = %dpermsfull;

    foreach $p ( keys %dpermsfull ) {

        #test no perms for each permission
        $perms{$p} = 0;
        $res = $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %perms,
        );
        noerrok($res);

        $del = $tuser->get_zone_delegates( nt_zone_id => $zid1 );
        noerrok($del);
        ok( $del->size, 1, "only one delegate" );
        $res = $del->next;
        ok( $res->get('nt_group_id') => $gid2 );

        #verify
        foreach ( keys %dpermmap ) {
            ok( $res->get($_), $perms{ $dpermmap{$_} },
                "delegation perm $_" );
        }

        #remove delegation

        $res = $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
        );
        noerrok($res);

    } ## end foreach $p ( keys %dpermsfull...

    #try true delegation

    foreach $p ( keys %dpermsfull ) {

        #test no perms for each permission
        $perms{$p} = 1;
        $res = $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %perms,
        );
        noerrok($res);

        $del = $tuser->get_zone_delegates( nt_zone_id => $zid1 );
        noerrok($del);
        ok( $del->size, 1, "only one delegate" );
        $res = $del->next;
        ok( $res->get('nt_group_id') => $gid2 );

        #verify
        foreach ( keys %dpermmap ) {
            ok( $res->get($_), $perms{ $dpermmap{$_} },
                "delegation perm $_" );
        }

        #remove delegation

        $res = $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
        );
        noerrok($res);

    } ## end foreach $p ( keys %dpermsfull...

    #try to delegate to own group

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid1,
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot delegate to your own group./ );
    ok( $res->error_desc, qr/Sanity error/ );

    #try to delegate to higher group

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => 1,
    );
    noerrok( $res, 404 );
    ok( $res->error_msg, qr/No Access Allowed to that object \(GROUP : 1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #try to delegate a zone you have no access to

    $res = $tuser->delegate_zones(
        zone_list   => $zid0,
        nt_group_id => $gid2,
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONE : $zid0\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    ####################
    #delegate_zone_records
    ####################

    #zone_record list missing
    $res = $tuser->delegate_zone_records(
        zonerecord_list => '',
        nt_group_id     => $gid2,
        %dpermsfull,
    );
    noerrok( $res, 301, "no zones" );
    ok( $res->get('error_msg')  => 'zonerecord_list' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #zone list invalid
    $res = $tuser->delegate_zone_records(
        zonerecord_list => 'abc',
        nt_group_id     => $gid2,
        %dpermsfull,
    );
    noerrok( $res, 302, "zone invalid" );
    ok( $res->get('error_msg')  => 'zonerecord_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #zone list not valid
    $res = $tuser->delegate_zone_records(
        zonerecord_list => 0,
        nt_group_id     => $gid2,
        %dpermsfull,
    );
    noerrok( $res, 302, "zones invalid" );
    ok( $res->get('error_msg')  => 'zonerecord_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #group id missing
    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => '',
        %dpermsfull,
    );
    noerrok( $res, 301, "no group" );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #group id invalid
    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => 'abc',
        %dpermsfull,
    );
    noerrok( $res, 302, "group id invalid" );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #group id invalid
    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => 0,
        %dpermsfull,
    );
    noerrok( $res, 302, "group id invalid" );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #try true delegation

    %perms = %dpermsfull;

    foreach $p ( keys %dpermsfull ) {

        #test no perms for each permission
        $perms{$p} = 0;
        $res = $tuser->delegate_zone_records(
            zonerecord_list => $zrid1,
            nt_group_id     => $gid2,
            %perms,
        );
        noerrok($res);

        $del = $tuser->get_zone_record_delegates(
            nt_zone_record_id => $zrid1 );
        noerrok($del);
        ok( $del->size, 1, "only one delegate" );
        $res = $del->next;
        ok( $res->get('nt_group_id') => $gid2 );

        #verify
        foreach ( keys %dpermmap ) {
            ok( $res->get($_), $perms{ $dpermmap{$_} },
                "delegation perm $_" );
        }

        #remove delegation

        $res = $tuser->delete_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2
        );
        noerrok($res);

    } ## end foreach $p ( keys %dpermsfull...

    #try true delegation

    foreach $p ( keys %dpermsfull ) {

        #test no perms for each permission
        $perms{$p} = 1;
        $res = $tuser->delegate_zone_records(
            zonerecord_list => $zrid1,
            nt_group_id     => $gid2,
            %perms,
        );
        noerrok($res);

        $del = $tuser->get_zone_record_delegates(
            nt_zone_record_id => $zrid1 );
        noerrok($del);
        ok( $del->size, 1, "only one delegate" );
        $res = $del->next;
        ok( $res->get('nt_group_id') => $gid2 );

        #verify
        foreach ( keys %dpermmap ) {
            ok( $res->get($_), $perms{ $dpermmap{$_} },
                "delegation perm $_" );
        }

        #remove delegation

        $res = $tuser->delete_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2
        );
        noerrok($res);

    } ## end foreach $p ( keys %dpermsfull...

    #try to delegate to own group

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid1,
    );
    noerrok( $res, 300 );
    ok( $res->error_msg,  qr/Cannot delegate to your own group./ );
    ok( $res->error_desc, qr/Sanity error/ );

    #try to delegate to higher group

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => 1,
    );
    noerrok( $res, 404 );
    ok( $res->error_msg, qr/No Access Allowed to that object \(GROUP : 1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #try to delegate a zone record you have no access to

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid0,
        nt_group_id     => $gid2,
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONERECORD : $zrid0\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    ####################
    #edit_zone_delegation
    ####################

    #try true delegation

    %perms = %dpermsfull;

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %perms,
    );
    noerrok($res);

    #no group id
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => '',
        %perms,
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #group id invalid
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => 'abc',
        %perms,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #group id invalid
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => 0,
        %perms,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #no zone_list
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => '',
        nt_group_id => $gid2,
        %perms,
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #zone_list invalid
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => 'abc',
        nt_group_id => $gid2,
        %perms,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #zone_list invalid
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => 0,
        nt_group_id => $gid2,
        %perms,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    foreach $p ( keys %dpermsfull ) {

        #test no perms for each permission
        $perms{$p} = 0;
        $res = $tuser->edit_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2,
            %perms,
        );
        noerrok($res);

        $del = $tuser->get_zone_delegates( nt_zone_id => $zid1 );
        noerrok($del);
        ok( $del->size, 1, "only one delegate" );
        $res = $del->next;
        ok( $res->get('nt_group_id') => $gid2 );

        #verify
        foreach ( keys %dpermmap ) {
            ok( $res->get($_), $perms{ $dpermmap{$_} },
                "delegation perm $_" );
        }

    } ## end foreach $p ( keys %dpermsfull...

    #remove delegation

    $res = $tuser->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    noerrok($res);

    ####################
    #edit_zone_record_delegation
    ####################

    #try true delegation

    %perms = %dpermsfull;

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        %perms,
    );
    noerrok($res);

    #no group id
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => '',
        %perms,
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #group id invalid
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => 'abc',
        %perms,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #group id invalid
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => 0,
        %perms,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #no zonerecord_list
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => '',
        nt_group_id       => $gid2,
        %perms,
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #zonerecord_list invalid
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => 'abc',
        nt_group_id       => $gid2,
        %perms,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #zonerecord_list invalid
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => 0,
        nt_group_id       => $gid2,
        %perms,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    foreach $p ( keys %dpermsfull ) {

        #test no perms for each permission
        $perms{$p} = 0;
        $res = $tuser->edit_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2,
            %perms,
        );
        noerrok($res);

        $del = $tuser->get_zone_record_delegates(
            nt_zone_record_id => $zrid1 );
        noerrok($del);
        ok( $del->size, 1, "only one delegate" );
        $res = $del->next;
        ok( $res->get('nt_group_id') => $gid2 );

        #verify
        foreach ( keys %dpermmap ) {
            ok( $res->get($_), $perms{ $dpermmap{$_} },
                "delegation perm $_" );
        }

    } ## end foreach $p ( keys %dpermsfull...

    #remove delegation

    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok($res);

    ####################
    #delete_zone_delegation
    ####################

    #try true delegation

    %perms = %dpermsfull;

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1, );
    noerrok($res);
    ok( $res->size, 1 );
    $res = $res->next;
    ok( $res->get('nt_group_id') => $gid2 );

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 1 );
    $res = $res->next;
    ok( $res->get('nt_group_id') => $gid1 );    #group of the zone
    ok( $res->get('nt_zone_id')  => $zid1 );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => '',
        nt_zone_id  => $zid1,
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => 'abc',
        nt_zone_id  => $zid1,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => 0,
        nt_zone_id  => $zid1,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => '',
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => 'abc',
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => 0,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #really delete it
    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => $zid1,
    );
    noerrok($res);

    #verify

    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1, );
    noerrok($res);
    ok( $res->size, 0 );

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 0 );

    ####################
    #delete_zone_record_delegation
    ####################

    #try true delegation

    %perms = %dpermsfull;

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1, );
    noerrok($res);
    ok( $res->size, 1 );
    $res = $res->next;
    ok( $res->get('nt_group_id') => $gid2 );

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 1 );
    $res = $res->next;
    ok( $res->get('nt_group_id') => $gid1 );    #group of the zone
    ok( $res->get('nt_zone_id')  => $zid1 );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => '',
        nt_zone_id  => $zid1,
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => 'abc',
        nt_zone_id  => $zid1,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => 0,
        nt_zone_id  => $zid1,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => '',
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => 'abc',
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => 0,
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #really delete it
    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => $zid1,
    );
    noerrok($res);

    #verify

    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1, );
    noerrok($res);
    ok( $res->size, 0 );

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 0 );

    ####################
    # get_delegated_zones
    ####################

    %perms = %dpermsfull;

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_delegated_zones( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $tuser->get_delegated_zones( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->get_delegated_zones( nt_group_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 1 );
    $z = $res->next;
    ok( $z->get('nt_zone_id'), $zid1 );
    foreach ( keys %perms ) {
        ok( $z->get( $dpermmap{$_} ), $perms{$_} );
    }

    $res = $tuser->delegate_zones(
        zone_list   => $zid2,
        nt_group_id => $gid2,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 2 );
    $saw1 = 0;
    $saw2 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->get('nt_zone_id') == $zid1;
        $saw2 = 1 if $z->get('nt_zone_id') == $zid2;
        foreach ( keys %perms ) {
            ok( $z->get( $dpermmap{$_} ), $perms{$_} );
        }
    } ## end for ( $z = $res->next )
    ok($saw1);
    ok($saw2);

    #remove delegation of first zone
    $res = $tuser->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    noerrok($res);

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 1 );
    $z = $res->next;
    ok( $z->get('nt_zone_id'), $zid2 );
    foreach ( keys %perms ) {
        ok( $z->get( $dpermmap{$_} ), $perms{$_} );
    }

    #remove delegation of second zone
    $res = $tuser->delete_zone_delegation(
        nt_zone_id  => $zid2,
        nt_group_id => $gid2
    );
    noerrok($res);

    ####################
    # get_delegated_zone_records
    ####################

    %perms = %dpermsfull;

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_delegated_zone_records( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $tuser->get_delegated_zone_records( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->get_delegated_zone_records( nt_group_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->get_delegated_zone_records( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 1 );

    #use Data::Dumper;
    #warn Dumper $res;
    #print "sleeping for 30 seconds...\n";
    #sleep 40;

    $z = $res->next;
    ok( $z->get('nt_zone_record_id'), $zrid1 );
    foreach ( keys %perms ) {
        ok( $z->get( $dpermmap{$_} ), $perms{$_} );
    }

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid2,
        nt_group_id     => $gid2,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_delegated_zone_records( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 2 );
    $saw1 = 0;
    $saw2 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->get('nt_zone_record_id') == $zrid1;
        $saw2 = 1 if $z->get('nt_zone_record_id') == $zrid2;
        foreach ( keys %perms ) {
            ok( $z->get( $dpermmap{$_} ), $perms{$_} );
        }
    } ## end for ( $z = $res->next )
    ok($saw1);
    ok($saw2);

    #remove delegation of first zone
    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok($res);

    $res = $tuser->get_delegated_zone_records( nt_group_id => $gid2 );
    noerrok($res);
    ok( $res->size, 1 );
    $z = $res->next;
    ok( $z->get('nt_zone_record_id'), $zrid2 );
    foreach ( keys %perms ) {
        ok( $z->get( $dpermmap{$_} ), $perms{$_} );
    }

    #remove delegation of second zone
    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid2,
        nt_group_id       => $gid2
    );
    noerrok($res);

    ####################
    #get_zone_delegates
    ####################

    %perms = %dpermsfull;

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_zone_delegates( nt_zone_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $tuser->get_zone_delegates( nt_zone_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->get_zone_delegates( nt_zone_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->size, 1 );
    $z = $res->next;
    ok( $z->get('nt_group_id'), $gid2 );
    foreach ( keys %perms ) {
        ok( $z->get( $dpermmap{$_} ), $perms{$_} );
    }

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid3,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->size, 2 );
    $saw1 = 0;
    $saw2 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->get('nt_group_id') == $gid2;
        $saw2 = 1 if $z->get('nt_group_id') == $gid3;
        foreach ( keys %perms ) {
            ok( $z->get( $dpermmap{$_} ), $perms{$_} );
        }
    } ## end for ( $z = $res->next )
    ok($saw1);
    ok($saw2);

    #remove delegation to first group
    $res = $tuser->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    noerrok($res);

    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->size, 1 );
    $z = $res->next;
    ok( $z->get('nt_group_id'), $gid3 );
    foreach ( keys %perms ) {
        ok( $z->get( $dpermmap{$_} ), $perms{$_} );
    }

    #remove delegation to second group
    $res = $tuser->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid3
    );
    noerrok($res);

    ####################
    #get_zone_record_delegates
    ####################

    %perms = %dpermsfull;

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_zone_record_delegates( nt_zone_record_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $tuser->get_zone_record_delegates( nt_zone_record_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->get_zone_record_delegates( nt_zone_record_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->size, 1 );
    $z = $res->next;
    ok( $z->get('nt_group_id'), $gid2 );
    foreach ( keys %perms ) {
        ok( $z->get( $dpermmap{$_} ), $perms{$_} );
    }

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid3,
        %perms,
    );
    noerrok($res);

    $res = $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->size, 2 );
    $saw1 = 0;
    $saw2 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->get('nt_group_id') == $gid2;
        $saw2 = 1 if $z->get('nt_group_id') == $gid3;
        foreach ( keys %perms ) {
            ok( $z->get( $dpermmap{$_} ), $perms{$_} );
        }
    } ## end for ( $z = $res->next )
    ok( $saw1, 1, "Should see $gid2 in list of delegates for record" );
    ok( $saw2, 1, "Should see $gid3 in list of delegates for record" );

    #remove delegation to first group
    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok($res);

    $res = $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->size, 1 );
    $z = $res->next;
    ok( $z->get('nt_group_id'), $gid3 );
    foreach ( keys %perms ) {
        ok( $z->get( $dpermmap{$_} ), $perms{$_} );
    }

    #remove delegation to second group
    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid3
    );
    noerrok($res);
} ## end sub test_api_funcs

=head1 test_zones

Tests delegation of zones to sub groups

=over

=item user can't delegate without perms

=item user can delegate with perms

=item subgroup has no access before delegation 

=item subgroup has limited access after delegation

=over

=item write

=item remove delegation

=item re-delegate

=item add records

=item delete records
    
=back

=item subgroup has limited access after delegation modification

=item subgroup has no access after delegation deletion

=back

=cut

sub test_zones {

    #login testuser2
    my $tuser2 = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port'),
    );
    die "Couldn't create NicTool Object" unless ok( ref $tuser2, 'NicTool' );

    $tuser2->login(
        username => 'testuser2@testsubgroup',
        password => 'testpass2',
    );
    die "Couldn't log in" unless noerrok( $tuser2->result );
    die "Couldn't log in" unless ok( $tuser2->nt_user_session );

    #should have no access to zid1

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONE : $zid1\)/, "get_zone, $zid1" );
    ok( $res->error_desc, qr/Access Permission denied/, "get_zone, $zid1" );

    $res  = $tuser2->get_group_zones;
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zid1;
    }
    ok( !$saw1 );

    #disallow delegation by test user 1

    $res = $group1->edit_group(%permsnone);
    noerrok($res);

    $tuser->refresh;
    noerrok( $tuser->result );
    ok( $tuser->can_zone_delegate, 0 );

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %dpermsnone,
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for zone objects/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #again check no access to zone from test user 2

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONE : $zid1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res  = $tuser2->get_group_zones;
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zid1;
    }
    ok( !$saw1 );

    #allow test user 1 to delegate and full zone/record permissions

    $res = $group1->edit_group(
        %permsnone,
        zone_delegate     => 1,
        zone_write        => 1,
        zonerecord_create => 1,
        zonerecord_delete => 1,
        zonerecord_write  => 1
    );
    noerrok($res);

    $tuser->refresh;
    noerrok( $tuser->result );
    ok( $tuser->can_zone_delegate, 1 );

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %dpermsnone,
    );
    noerrok($res);

    #see if access is available to test user 2

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->id, $zid1 );

    %z1 = (
        zone => 'test.com',

        #serial      => ,
        ttl         => '86400',
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    foreach ( keys %z1 ) {
        ok( $res->get($_), $z1{$_}, "delegated zone access value $_" );
    }

    foreach ( keys %dpermsfull ) {
        ok( $res->get( $dpermmap{$_} ), 0,
            "access perms for delegated zone" );
    }

    $res  = $tuser2->get_group_zones;
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zid1;
    }
    ok($saw1);

    #check each access permission type

    #perm_write

    %newz = (
        serial      => 2,
        ttl         => 86401,
        description => 'modified description',
        mailaddr    => 'nobody.nowhere.com',
        refresh     => 21,
        retry       => 31,
        expire      => 41,
        minimum     => 51,
    );

    $res = $tuser2->edit_zone( nt_zone_id => $zid1, %newz );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'write' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %z1 ) {
        ok( $res->get($_), $z1{$_}, "un-modified delegated zone perm $_" );
    }

    #change to allow write
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2,
        %dpermsnone, perm_write => 1
    );
    noerrok($res);

    #try write access again

    $res = $tuser2->edit_zone( nt_zone_id => $zid1, %newz );
    noerrok($res);

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %newz ) {
        ok( $res->get($_), $newz{$_}, "modified delegated zone" );
    }

    #reset to previous values
    $res = $user->edit_zone( nt_zone_id => $zid1, %z1 );
    noerrok($res);

    #perm_delegate

    #make test group
    $res = $user->new_group(
        nt_group_id => $gid2,
        name        => "testsubsubgroup",
    );
    noerrok($res);
    $tgid = $res->get('nt_group_id');

    $res = $tuser2->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $tgid,
        %dpermsnone
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #change perms to allow delegation

    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2,
        %dpermsnone, perm_delegate => 1
    );
    noerrok($res);

    $res = $tuser2->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $tgid,
        %dpermsnone
    );
    noerrok($res);

    $res = $user->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $tgid
    );
    noerrok($res);

    $res = $user->delete_group( nt_group_id => $tgid );
    noerrok($res);

    #perm_delete

    $res = $tuser2->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #change perms to allow removal of delegation
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2,
        %dpermsnone, perm_delete => 1
    );
    noerrok($res);

    $res = $tuser2->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    noerrok($res);

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONE : $zid1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res  = $tuser2->get_group_zones;
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zid1;
    }
    ok( !$saw1 );

    ##delegate again
    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %dpermsnone,
    );
    noerrok($res);
    ##

    #zone_perm_add_records
    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->size, 2 );

    $res = $tuser2->new_zone_record(
        nt_zone_id  => $zid1,
        name        => '@',
        ttl         => 86400,
        description => 'record 3',
        type        => 'MX',
        address     => 'mail.otherzone.com.',
        weight      => 1,
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/Not allowed to add records to the delegated zone./ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #change perms to allow adding sub records
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2,
        %dpermsnone, zone_perm_add_records => 1
    );
    noerrok($res);

    $res = $tuser2->new_zone_record(
        nt_zone_id  => $zid1,
        name        => '@',
        ttl         => 86400,
        description => 'record 3',
        type        => 'MX',
        address     => 'mail.otherzone.com.',
        weight      => 1,
    );
    noerrok($res);
    $zrid3 = $res->get('nt_zone_record_id');

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->size, 3 );
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zrid3;
    }
    ok($saw1);

    $res = $user->delete_zone_record( nt_zone_record_id => $zrid3 );
    noerrok($res);

    #zone_perm_delete_records

    $res = $user->new_zone_record(
        nt_zone_id  => $zid1,
        name        => '@',
        ttl         => 86400,
        description => 'record 3',
        type        => 'MX',
        address     => 'mail.otherzone.com.',
        weight      => 1,

    );
    noerrok($res);
    $zrid3 = $res->get('nt_zone_record_id');

    #try to delete record from delegated zone

    $res = $tuser2->delete_zone_record( nt_zone_record_id => $zrid3 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delete' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->size, 3 );
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zrid3;
    }
    ok($saw1);

    #change perms
    $res = $tuser->edit_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2,
        %dpermsnone, zone_perm_delete_records => 1
    );
    noerrok($res);

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);

    #print Data::Dumper::Dumper($res);

    $res = $tuser2->delete_zone_record( nt_zone_record_id => $zrid3 );
    noerrok($res);

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->size, 2 );
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zrid3;
    }
    ok( !$saw1 );

    #clean up

    $res = $user->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2,
    );
    noerrok($res);

    $tuser2->logout;
}

=head1 test_zone_records

Tests delegation of Zone Records to sub groups

=over

=item user can't delegate without perms

=item user can delegate with perms

=item subgroup has no access before delegation 

=item subgroup has limited access after delegation

=over

=item write

=item remove delegation

=item re-delegate

=back

=item subgroup has limited access after delegation modification

=item subgroup has no access after delegation deletion

=back

=cut

sub test_zone_records {

    #login testuser2
    my $tuser2 = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );
    die "Couldn't create NicTool Object" unless ok( ref $tuser2, 'NicTool' );

    $tuser2->login(
        username => 'testuser2@testsubgroup',
        password => 'testpass2',
    );
    die "Couldn't log in" unless noerrok( $tuser2->result );
    die "Couldn't log in" unless ok( $tuser2->nt_user_session );

    #should have no access to zrid1

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONERECORD : $zrid1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONE : $zid1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #disallow delegation by test user 1

    $res = $group1->edit_group(%permsnone);
    noerrok($res);

    $tuser->refresh;
    noerrok( $tuser->result );
    ok( $tuser->can_zonerecord_delegate, 0 );

    #try to delegate
    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        %dpermsnone,
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for zonerecord objects/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #again check no access to zone record from test user 2

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONERECORD : $zrid1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONE : $zid1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #allow test user 1 to delegate and edit records

    $res = $group1->edit_group(
        %permsnone,
        zonerecord_write    => 1,
        zonerecord_delegate => 1
    );
    noerrok($res);

    $tuser->refresh;
    noerrok( $tuser->result );
    ok( $tuser->can_zonerecord_delegate, 1 );

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        %dpermsnone,
    );
    noerrok($res);

    #see if access is available to test user 2

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->id, $zrid1 );

    %zr1 = (
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );
    foreach ( keys %zr1 ) {
        ok( $res->get($_), $zr1{$_},
            "delegated zone record access value $_" );
    }

    foreach ( keys %dzrpermsfull ) {
        ok( $res->get( $dpermmap{$_} ),
            0, "access perm $_ for delegated zone" );
    }

    $res  = $tuser2->get_group_zones;
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zid1;
    }
    ok($saw1);

    #check pseudo access to zone

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->get('pseudo'), 1,
        "should have pseudo delegate access to zone" );
    ok( $res->get('deleted'), 0, "zone is not deleted" );
    foreach ( keys %dpermsfull ) {
        ok( $res->get( $dpermmap{$_} ),
            0, "access perms for pseudo-delegated zone" );
    }
    foreach ( keys %z1 ) {
        ok( $res->get($_), $z1{$_}, "settings of pseudo delegated zone" );
    }

 #check that user can only see and access the delegated record inside the zone

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    ok( $res->size, 1 );
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zrid1;
    }
    ok($saw1);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid2 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONERECORD : $zrid2\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #check each access permission type

    #perm_write

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->get('delegate_write'), 0, "has no write access" );

    %newzr = (
        name        => 'd',
        ttl         => 86404,
        description => 'record 4',
        type        => 'A',
        address     => '192.168.1.4',
        weight      => 4
    );

    $res = $tuser2->edit_zone_record( nt_zone_record_id => $zrid1, %newzr );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'write' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach ( keys %zr1 ) {
        ok( $res->get($_), $zr1{$_},
            "un-modified delegated zone record perm $_" );
    }

    #check write perms for pseudo delegated zone perm_write

    %newz = (
        serial      => 2,
        ttl         => 86401,
        description => 'modified description',
        mailaddr    => 'nobody.nowhere.com',
        refresh     => 21,
        retry       => 31,
        expire      => 41,
        minimum     => 51,
    );

    $res = $tuser2->edit_zone( nt_zone_id => $zid1, %newz );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'write' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %z1 ) {
        ok( $res->get($_), $z1{$_},
            "un-modified pseudo delegated zone perm $_" );
    }

    #change to allow write
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2,
        %dpermsnone, perm_write => 1
    );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->can_delegate_write, 1, "has write access" );

    #try write access again

    $res = $tuser2->edit_zone_record( nt_zone_record_id => $zrid1, %newzr );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach ( keys %newzr ) {
        ok( $res->get($_), $newzr{$_}, "modified delegated zone record" );
    }

    #still no write access to zone
    $res = $tuser2->edit_zone( nt_zone_id => $zid1, %newz );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'write' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %z1 ) {
        ok( $res->get($_), $z1{$_},
            "un-modified pseudo delegated zone perm $_" );
    }

    #perm_delegate

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->can_delegate_delegate, 0, "has no delegate access" );

    #make test group
    $res = $user->new_group(
        nt_group_id => $gid2,
        name        => "testsubsubgroup",
    );
    noerrok($res);
    $tgid = $res->get('nt_group_id');

    $res = $tuser2->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $tgid,
        %dpermsnone
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #try to delegate pseudo-delegated zone

    $res = $tuser2->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $tgid,
        %dpermsnone
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #change perms to allow delegation

    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2,
        %dpermsnone, perm_delegate => 1
    );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->can_delegate_delegate, 1, "has delegate access" );

    $res = $tuser2->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $tgid,
        %dpermsnone
    );
    noerrok($res);

    $res = $user->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $tgid
    );
    noerrok($res);

    #try to delegate pseudo-delegated zone

    $res = $tuser2->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $tgid,
        %dpermsnone
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $user->delete_group( nt_group_id => $tgid );
    noerrok($res);

    #perm_delete

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->can_delegate_delete, 0, "has no delete access" );

    $res = $tuser2->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/You have no 'delegate' permission for the delegated object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    #change perms to allow removal of delegation
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2,
        %dpermsnone, perm_delete => 1
    );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    ok( $res->can_delegate_delete, 1, "has delete access" );

    $res = $tuser2->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONERECORD : $zrid1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,
        qr/No Access Allowed to that object \(ZONE : $zid1\)/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

    $res  = $tuser2->get_group_zones;
    $saw1 = 0;
    while ( $z = $res->next ) {
        $saw1 = 1 if $z->id eq $zid1;
    }
    ok( !$saw1 );

    #cleanup

    $tuser2->logout;
}

sub del {
    ####################
    # cleanup
    ####################

    $tuser->logout;

    $res = $user->delete_users( user_list => [ $uid1, $uid2 ] );
    noerrok($res);
    $res = $subg->delete;
    noerrok($res);
    $res = $user->delete_group( nt_group_id => $gid3 );
    noerrok($res);

    $res = $user->delete_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    $res = $user->delete_zone_record( nt_zone_record_id => $zrid2 );
    noerrok($res);

    $res = $user->delete_zones( zone_list => [ $zid1, $zid2 ] );
    noerrok($res);

    $res = $group1->delete;
    noerrok($res);

    $res = $user->delete_zones( zone_list => $zid0 );
    noerrok($res);

    $user->logout;
} ## end sub del

