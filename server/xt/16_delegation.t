# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abraham Ingersoll & Greg Schueler
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

use strict;

# use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test::More 'no_plan';

my ( $tuser, $tuser2 );
my ( $gid1,  $gid2,  $gid3,  $group1, $subg, $zid0, $zid1, $zid2, $uid1, $uid2 );
my ( %z1,    $zrid0, $zrid1, $zrid2 );

# no group permissions
my %permsnone = (
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

# full group permissions
my %permsfull = (
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

# full delegation permissions for zone
my %dpermsfull = (
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

# no delegation permissions for zone
my %dpermsnone = (
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

# full delegation permissions for zone records
my %dzrpermsfull = (
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

my %dpermmap = (
    perm_write               => 'delegate_write',
    perm_delete              => 'delegate_delete',
    perm_delegate            => 'delegate_delegate',
    zone_perm_add_records    => 'delegate_add_records',
    zone_perm_delete_records => 'delegate_delete_records',
);

my %delegation_calls = (
    zone => {
        delegate  => 'delegate_zones',
        list      => 'zone_list',
        delegates => 'get_zone_delegates',
        remove    => 'delete_zone_delegation',
        id        => 'nt_zone_id',
    },
    zone_record => {
        delegate  => 'delegate_zone_records',
        list      => 'zonerecord_list',
        delegates => 'get_zone_record_delegates',
        remove    => 'delete_zone_record_delegation',
        id        => 'nt_zone_record_id',
    },
);

my $user = nt_api_connect();

&start;

eval {&test_api_funcs};
warn $@ if $@;
eval {&test_zones};
warn $@ if $@;
eval {&test_zone_records};
warn $@ if $@;
&cleanup;

done_testing();
exit;

sub start {

    #make a new group
    $gid1 = new_id_ok( $user->new_group( name => 'test_delete_me1', %permsfull ),
        'nt_group_id', "Couldn't create test group1" );
    $group1 =
        fetched_ok( $user->get_group( nt_group_id => $gid1 ), $gid1, "Couldn't get test group1" );

    # new user in group
    my $res = $group1->new_user(
        first_name                => 'test',
        last_name                 => '1',
        email                     => 'test@blah.blah',
        username                  => 'testuser1',
        password                  => 'testpass',
        password2                 => 'testpass',
        inherit_group_permissions => 1,
    );
    noerrok($res) or die "Couldn't create test user";
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
    $gid2 = new_id_ok( $group1->new_group( name => 'testsubgroup', %permsfull ),
        'nt_group_id', "Couldn't create test subgroup" );
    $subg =
        fetched_ok( $user->get_group( nt_group_id => $gid2 ), $gid2, "Couldn't get test subgroup" );

    $res = $subg->new_user(
        first_name                => 'test2',
        last_name                 => '2',
        email                     => 'test2@blah.blah',
        username                  => 'testuser2',
        password                  => 'testpass2',
        password2                 => 'testpass2',
        inherit_group_permissions => 1,
    );
    noerrok($res) or die "Couldn't create test user";
    $uid2 = $res->get('nt_user_id');

    #login as test user
    $tuser = nt_client( cache_zone => 0, cache_records => 0 );
    isa_ok( $tuser, 'NicTool' );

    $tuser->login(
        username => 'testuser1@test_delete_me1',
        password => 'testpass'
    );
    ok( $tuser->result );

    # another subgroup
    $gid3 = new_id_ok( $group1->new_group( name => 'testsubgroup2', %permsfull ),
        'nt_group_id', "Couldn't create test subgroup2" );

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
}

sub test_api_funcs {

    ####################
    #delegate_zones
    ####################

    my $res;
    for ( [ '', 301, "no zones" ], [ 'abc', 302, "zone invalid" ], [ 0, 302, "zones invalid" ] ) {
        my ( $list, $code, $name ) = @$_;
        $res = $tuser->delegate_zones(
            zone_list   => $list,
            nt_group_id => $gid2,
            %dpermsfull,
        );
        noerrok( $res, $code, $name );
        ok( $res->get('error_msg') =~ 'zone_list' );
        ok(
            $res->get('error_desc') =~ (
                $code == 301 ? qr/Required parameters missing/ : qr/Some parameters were invalid/
            )
        );
    }

    for (
        [ '',    301, "no group" ],
        [ 'abc', 302, "group id invalid" ],
        [ 0,     302, "group id invalid" ]
        )
    {
        my ( $gid, $code, $name ) = @$_;
        $res = $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid,
            %dpermsfull,
        );
        param_error_ok( $res, $code, 'nt_group_id', $name );
    }

    # try true delegation
    my %perms = %dpermsfull;
    delegation_toggled_ok( 'zone', $zid1, \%perms, 0 );
    delegation_toggled_ok( 'zone', $zid1, \%perms, 1 );

    #try to delegate to own group
    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid1,
    );
    noerrok( $res, 300 );
    ok( $res->error_msg  =~ qr/Cannot delegate to your own group./ );
    ok( $res->error_desc =~ qr/Sanity error/ );

    #try to delegate to higher group
    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => 1,
    );
    denied_ok( $res, qr/No Access Allowed to that object \(GROUP : 1\)/ );

    #try to delegate a zone you have no access to
    $res = $tuser->delegate_zones(
        zone_list   => $zid0,
        nt_group_id => $gid2,
    );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONE : $zid0\)/ );

    ####################
    #delegate_zone_records
    ####################

    for ( [ '', 301, "no zones" ], [ 'abc', 302, "zone invalid" ], [ 0, 302, "zones invalid" ] ) {
        my ( $list, $code, $name ) = @$_;
        $res = $tuser->delegate_zone_records(
            zonerecord_list => $list,
            nt_group_id     => $gid2,
            %dpermsfull,
        );
        param_error_ok( $res, $code, 'zonerecord_list', $name );
    }

    for (
        [ '',    301, "no group" ],
        [ 'abc', 302, "group id invalid" ],
        [ 0,     302, "group id invalid" ]
        )
    {
        my ( $gid, $code, $name ) = @$_;
        $res = $tuser->delegate_zone_records(
            zonerecord_list => $zrid1,
            nt_group_id     => $gid,
            %dpermsfull,
        );
        param_error_ok( $res, $code, 'nt_group_id', $name );
    }

    #try true delegation
    %perms = %dpermsfull;
    delegation_toggled_ok( 'zone_record', $zrid1, \%perms, 0 );
    delegation_toggled_ok( 'zone_record', $zrid1, \%perms, 1 );

    #try to delegate to own group
    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid1,
    );
    noerrok( $res, 300 );
    ok( $res->error_msg  =~ qr/Cannot delegate to your own group./ );
    ok( $res->error_desc =~ qr/Sanity error/ );

    #try to delegate to higher group
    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => 1,
    );
    denied_ok( $res, qr/No Access Allowed to that object \(GROUP : 1\)/ );

    #try to delegate a zone record you have no access to

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid0,
        nt_group_id     => $gid2,
    );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONERECORD : $zrid0\)/ );

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

    bad_id_ok( 'nt_group_id',
        sub { $tuser->edit_zone_delegation( nt_zone_id => $zid1, nt_group_id => shift, %perms ) } );
    bad_id_ok( 'nt_zone_id',
        sub { $tuser->edit_zone_delegation( nt_zone_id => shift, nt_group_id => $gid2, %perms ) } );

    foreach my $p ( keys %dpermsfull ) {

        #test no perms for each permission
        $perms{$p} = 0;
        $res = $tuser->edit_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2,
            %perms,
        );
        noerrok($res);
        only_delegate_ok( $tuser->get_zone_delegates( nt_zone_id => $zid1 ), \%perms );
    }

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

    bad_id_ok(
        'nt_group_id',
        sub {
            $tuser->edit_zone_record_delegation(
                nt_zone_record_id => $zrid1,
                nt_group_id       => shift,
                %perms
            );
        }
    );
    bad_id_ok(
        'nt_zone_record_id',
        sub {
            $tuser->edit_zone_record_delegation(
                nt_zone_record_id => shift,
                nt_group_id       => $gid2,
                %perms
            );
        }
    );

    foreach my $p ( keys %dpermsfull ) {

        #test no perms for each permission
        $perms{$p} = 0;
        $res = $tuser->edit_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2,
            %perms,
        );
        noerrok($res);
        only_delegate_ok( $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 ),
            \%perms );
    }

    #remove delegation
    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok($res);

    ####################
    #delete_zone_delegation
    ####################

    test_delete_zone_delegation();

    ####################
    #delete_zone_record_delegation
    ####################

    test_delete_zone_record_delegation();

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

    bad_id_ok( 'nt_group_id', sub { $tuser->get_delegated_zones( nt_group_id => shift ) } );

    delegation_listed_ok( $tuser->get_delegated_zones( nt_group_id => $gid2 ),
        'nt_zone_id', $zid1, \%perms );

    $res = $tuser->delegate_zones(
        zone_list   => $zid2,
        nt_group_id => $gid2,
        %perms,
    );
    noerrok($res);

    ok($_)
        for delegations_seen( $tuser->get_delegated_zones( nt_group_id => $gid2 ),
        'nt_zone_id', $zid1, $zid2, \%perms );

    #remove delegation of first zone
    $res = $tuser->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    noerrok($res);

    delegation_listed_ok( $tuser->get_delegated_zones( nt_group_id => $gid2 ),
        'nt_zone_id', $zid2, \%perms );

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

    bad_id_ok( 'nt_group_id', sub { $tuser->get_delegated_zone_records( nt_group_id => shift ) } );

    delegation_listed_ok( $tuser->get_delegated_zone_records( nt_group_id => $gid2 ),
        'nt_zone_record_id', $zrid1, \%perms );

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid2,
        nt_group_id     => $gid2,
        %perms,
    );
    noerrok($res);

    ok($_)
        for delegations_seen( $tuser->get_delegated_zone_records( nt_group_id => $gid2 ),
        'nt_zone_record_id', $zrid1, $zrid2, \%perms );

    #remove delegation of first zone
    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok($res);

    delegation_listed_ok( $tuser->get_delegated_zone_records( nt_group_id => $gid2 ),
        'nt_zone_record_id', $zrid2, \%perms );

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

    bad_id_ok( 'nt_zone_id', sub { $tuser->get_zone_delegates( nt_zone_id => shift ) } );

    delegation_listed_ok( $tuser->get_zone_delegates( nt_zone_id => $zid1 ),
        'nt_group_id', $gid2, \%perms );

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid3,
        %perms,
    );
    noerrok($res);

    ok($_)
        for delegations_seen( $tuser->get_zone_delegates( nt_zone_id => $zid1 ),
        'nt_group_id', $gid2, $gid3, \%perms );

    #remove delegation to first group
    $res = $tuser->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    noerrok($res);

    delegation_listed_ok( $tuser->get_zone_delegates( nt_zone_id => $zid1 ),
        'nt_group_id', $gid3, \%perms );

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

    bad_id_ok( 'nt_zone_record_id',
        sub { $tuser->get_zone_record_delegates( nt_zone_record_id => shift ) } );

    delegation_listed_ok( $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 ),
        'nt_group_id', $gid2, \%perms );

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid3,
        %perms,
    );
    noerrok($res);

    my ( $saw1, $saw2 ) =
        delegations_seen( $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 ),
        'nt_group_id', $gid2, $gid3, \%perms );
    is( $saw1, 1, "Should see $gid2 in list of delegates for record" );
    is( $saw2, 1, "Should see $gid3 in list of delegates for record" );

    #remove delegation to first group
    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok($res);

    delegation_listed_ok( $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 ),
        'nt_group_id', $gid3, \%perms );

    #remove delegation to second group
    $res = $tuser->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid3
    );
    noerrok($res);
}

sub test_delete_zone_delegation {

    #try true delegation
    my $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %dpermsfull,
    );
    noerrok($res);

    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1, );
    noerrok($res);
    is( $res->size, 1 );
    $res = $res->next;
    is( $res->get('nt_group_id'), $gid2 );

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    is( $res->size, 1 );
    $res = $res->next;
    is( $res->get('nt_group_id'), $gid1 );    #group of the zone
    is( $res->get('nt_zone_id'),  $zid1 );

    bad_id_ok( 'nt_group_id',
        sub { $tuser->delete_zone_delegation( nt_group_id => shift, nt_zone_id => $zid1 ) } );
    bad_id_ok( 'nt_zone_id',
        sub { $tuser->delete_zone_delegation( nt_group_id => $gid2, nt_zone_id => shift ) } );

    #really delete it
    $res = $tuser->delete_zone_delegation(
        nt_group_id => $gid2,
        nt_zone_id  => $zid1,
    );
    noerrok($res);

    #verify
    $res = $tuser->get_zone_delegates( nt_zone_id => $zid1, );
    noerrok($res);
    is( $res->size, 0 );

    $res = $tuser->get_delegated_zones( nt_group_id => $gid2 );
    noerrok($res);
    is( $res->size, 0 );
}

sub test_delete_zone_record_delegation {

    #try true delegation
    my $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        %dpermsfull,
    );
    noerrok($res);

    $res = $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 );
    noerrok($res);
    is( $res->size, 1 );
    $res = $res->next;
    is( $res->get('nt_group_id'), $gid2 );

    $res = $tuser->get_delegated_zone_records( nt_group_id => $gid2 );
    noerrok($res);
    is( $res->size, 1 );
    $res = $res->next;
    is( $res->get('nt_zone_record_id'), $zrid1 );

    bad_id_ok(
        'nt_group_id',
        sub {
            $tuser->delete_zone_record_delegation(
                nt_group_id       => shift,
                nt_zone_record_id => $zrid1
            );
        }
    );
    bad_id_ok(
        'nt_zone_record_id',
        sub {
            $tuser->delete_zone_record_delegation(
                nt_group_id       => $gid2,
                nt_zone_record_id => shift
            );
        }
    );

    #really delete it
    $res = $tuser->delete_zone_record_delegation(
        nt_group_id       => $gid2,
        nt_zone_record_id => $zrid1,
    );
    noerrok($res);

    #verify
    $res = $tuser->get_zone_record_delegates( nt_zone_record_id => $zrid1 );
    noerrok($res);
    is( $res->size, 0 );

    $res = $tuser->get_delegated_zone_records( nt_group_id => $gid2 );
    noerrok($res);
    is( $res->size, 0 );
}

# sets one more permission to $value per pass, delegating and removing the delegation each time
sub delegation_toggled_ok {
    my ( $kind, $oid, $perms, $value ) = @_;
    my $call = $delegation_calls{$kind};

    foreach my $p ( keys %dpermsfull ) {
        $perms->{$p} = $value;
        my $method = $call->{delegate};
        my $res    = $tuser->$method(
            $call->{list} => $oid,
            nt_group_id   => $gid2,
            %$perms,
        );
        noerrok($res);

        $method = $call->{delegates};
        only_delegate_ok( $tuser->$method( $call->{id} => $oid ), $perms );

        $method = $call->{remove};
        noerrok( $tuser->$method( $call->{id} => $oid, nt_group_id => $gid2 ) );
    }
}

sub only_delegate_ok {
    my ( $del, $perms ) = @_;
    noerrok($del);
    is( $del->size, 1, "only one delegate" );
    my $res = $del->next;
    is( $res->get('nt_group_id'), $gid2 );

    #verify
    foreach ( keys %dpermmap ) {
        is( $res->get( $dpermmap{$_} ), $perms->{$_}, "delegation perm $_" );
    }
}

sub delegation_listed_ok {
    my ( $res, $field, $id, $perms ) = @_;
    noerrok($res);
    is( $res->size, 1 );
    my $z = $res->next;
    is( $z->get($field), $id );
    foreach ( keys %$perms ) {
        is( $z->get( $dpermmap{$_} ), $perms->{$_} );
    }
}

sub delegations_seen {
    my ( $res, $field, $id1, $id2, $perms ) = @_;
    noerrok($res);
    is( $res->size, 2 );
    my $saw1 = 0;
    my $saw2 = 0;
    while ( my $z = $res->next ) {
        $saw1 = 1 if $z->get($field) == $id1;
        $saw2 = 1 if $z->get($field) == $id2;
        foreach ( keys %$perms ) {
            is( $z->get( $dpermmap{$_} ), $perms->{$_} );
        }
    }
    return ( $saw1, $saw2 );
}

sub denied_ok {
    my ( $res, $msg, $name ) = @_;
    noerrok( $res, 404 );
    ok( $res->error_msg  =~ $msg,                         $name );
    ok( $res->error_desc =~ qr/Access Permission denied/, $name );
}

sub has_id {
    my ( $list, $id ) = @_;
    while ( my $z = $list->next ) {
        return 1 if $z->id eq $id;
    }
    return 0;
}

sub tuser2_login {
    my $tuser2 = nt_client();
    isa_ok( $tuser2, 'NicTool' ) or die "Couldn't create NicTool Object";

    $tuser2->login(
        username => 'testuser2@testsubgroup',
        password => 'testpass2',
    );
    noerrok( $tuser2->result ) && ok( $tuser2->nt_user_session )
        or die "Couldn't log in";
    return $tuser2;
}

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

    # login testuser2
    my $tuser2 = tuser2_login();

    # should have no access to zid1
    my $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONE : $zid1\)/, "get_zone, $zid1" );

    $res = $tuser2->get_group_zones;
    ok( !has_id( $res, $zid1 ) );

    #disallow delegation by test user 1
    $res = $group1->edit_group(%permsnone);
    noerrok($res);

    $tuser->refresh;
    noerrok( $tuser->result );
    is( $tuser->can_zone_delegate, 0 );

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %dpermsnone,
    );
    denied_ok( $res, qr/You have no 'delegate' permission for zone objects/ );

    # again check no access to zone from test user 2
    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONE : $zid1\)/ );

    $res = $tuser2->get_group_zones;
    ok( !has_id( $res, $zid1 ) );

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
    is( $tuser->can_zone_delegate, 1 );

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %dpermsnone,
    );
    noerrok($res);

    #see if access is available to test user 2

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    is( $res->id, $zid1 );

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
        is( $res->get($_), $z1{$_}, "delegated zone access value $_" );
    }

    foreach ( keys %dpermsfull ) {
        is( $res->get( $dpermmap{$_} ), 0, "access perms for delegated zone" );
    }

    $res = $tuser2->get_group_zones;
    ok( has_id( $res, $zid1 ) );

    #check each access permission type

    #perm_write
    my %newz = (
        ttl         => 86401,
        description => 'modified description',
        mailaddr    => 'nobody.nowhere.com',
        refresh     => 21,
        retry       => 31,
        expire      => 41,
        minimum     => 51,
    );

    $res = $tuser2->edit_zone( nt_zone_id => $zid1, %newz );
    denied_ok( $res, qr/You have no 'write' permission for the delegated object/ );

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %z1 ) {
        is( $res->get($_), $z1{$_}, "un-modified delegated zone perm $_" );
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
        is( $res->get($_), $newz{$_}, "modified delegated zone" );
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
    my $tgid = $res->get('nt_group_id');

    $res = $tuser2->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $tgid,
        %dpermsnone
    );
    denied_ok( $res, qr/You have no 'delegate' permission for the delegated object/ );

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
    denied_ok( $res, qr/You have no 'delegate' permission for the delegated object/ );

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
    denied_ok( $res, qr/No Access Allowed to that object \(ZONE : $zid1\)/ );

    $res = $tuser2->get_group_zones;
    ok( !has_id( $res, $zid1 ) );

    #delegate again
    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %dpermsnone,
    );
    noerrok($res);

    # Regression test for issue #307:
    # when the same zone is delegated to multiple groups, permissions must be
    # evaluated for the requesting user's group, not the first delegation row.
    $res = $user->new_group(
        nt_group_id => $gid1,
        name        => "test-cross-delegation-group",
    );
    noerrok($res);
    my $cross_gid = $res->get('nt_group_id');

    # Make a permissive delegation for another group first.
    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $cross_gid,
        %dpermsfull,
    );
    noerrok($res);

    # Re-create the restrictive delegation for gid2 after the permissive one.
    $res = $tuser->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2,
    );
    noerrok($res);

    $res = $tuser->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $gid2,
        %dpermsnone,
    );
    noerrok($res);

    $res = $tuser2->edit_zone_record(
        nt_zone_record_id => $zrid1,
        name              => 'cross-deleg-test',
        ttl               => 86400,
        description       => 'record 1',
        type              => 'A',
        address           => '192.168.1.1',
        weight            => 0,
    );
    noerrok( $res, 404 );
    ok( $res->error_msg =~ qr/You have no 'write' permission for the delegated object/ );

    # Clean up the additional delegation/group used by this regression test.
    $res = $user->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $cross_gid,
    );
    noerrok($res);

    $res = $user->delete_group( nt_group_id => $cross_gid );
    noerrok($res);

    #zone_perm_add_records
    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    is( $res->size, 2 );

    $res = $tuser2->new_zone_record(
        nt_zone_id  => $zid1,
        name        => '@',
        ttl         => 86400,
        description => 'record 3',
        type        => 'MX',
        address     => 'mail.otherzone.com.',
        weight      => 1,
    );
    denied_ok( $res, qr/Not allowed to add records to the delegated zone./ );

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
    my $zrid3 = $res->get('nt_zone_record_id');

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    is( $res->size, 3 );
    ok( has_id( $res, $zrid3 ) );

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
    denied_ok( $res, qr/You have no 'delete' permission for the delegated object/ );

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    is( $res->size, 3 );
    ok( has_id( $res, $zrid3 ) );

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
    is( $res->size, 2 );
    ok( !has_id( $res, $zrid3 ) );

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
    my $tuser2 = tuser2_login();

    #should have no access to zrid1
    my $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONERECORD : $zrid1\)/ );

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONE : $zid1\)/ );

    #disallow delegation by test user 1

    $res = $group1->edit_group(%permsnone);
    noerrok($res);

    $tuser->refresh;
    noerrok( $tuser->result );
    is( $tuser->can_zonerecord_delegate, 0 );

    #try to delegate
    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        %dpermsnone,
    );
    denied_ok( $res, qr/You have no 'delegate' permission for zonerecord objects/ );

    #again check no access to zone record from test user 2

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONERECORD : $zrid1\)/ );

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONE : $zid1\)/ );

    #allow test user 1 to delegate and edit records
    $res = $group1->edit_group(
        %permsnone,
        zonerecord_write    => 1,
        zonerecord_delegate => 1
    );
    noerrok($res);

    $tuser->refresh;
    noerrok( $tuser->result );
    is( $tuser->can_zonerecord_delegate, 1 );

    $res = $tuser->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $gid2,
        %dpermsnone,
    );
    noerrok($res);

    #see if access is available to test user 2
    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    is( $res->id, $zrid1 );

    my %zr1 = (
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );
    foreach ( keys %zr1 ) {
        is( $res->get($_), $zr1{$_}, "delegated zone record access value $_" );
    }

    foreach ( keys %dzrpermsfull ) {
        is( $res->get( $dpermmap{$_} ), 0, "access perm $_ for delegated zone" );
    }

    $res = $tuser2->get_group_zones;
    ok( has_id( $res, $zid1 ) );

    #check pseudo access to zone

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    is( $res->get('pseudo'),  1, "should have pseudo delegate access to zone" );
    is( $res->get('deleted'), 0, "zone is not deleted" );
    foreach ( keys %dpermsfull ) {
        is( $res->get( $dpermmap{$_} ), 0, "access perms for pseudo-delegated zone" );
    }
    foreach ( keys %z1 ) {
        is( $res->get($_), $z1{$_}, "settings of pseudo delegated zone" );
    }

    #check that user can only see and access the delegated record inside the zone

    $res = $tuser2->get_zone_records( nt_zone_id => $zid1 );
    noerrok($res);
    is( $res->size, 1 );
    ok( has_id( $res, $zrid1 ) );

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid2 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONERECORD : $zrid2\)/ );

    #check each access permission type

    #perm_write
    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    is( $res->get('delegate_write'), 0, "has no write access" );

    my %newzr = (
        name        => 'd',
        ttl         => 86404,
        description => 'record 4',
        type        => 'A',
        address     => '192.168.1.4',
        weight      => 4
    );

    $res = $tuser2->edit_zone_record( nt_zone_record_id => $zrid1, %newzr );
    denied_ok( $res, qr/You have no 'write' permission for the delegated object/ );

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach ( keys %zr1 ) {
        is( $res->get($_), $zr1{$_}, "un-modified delegated zone record perm $_" );
    }

    #check write perms for pseudo delegated zone perm_write
    my %newz = (
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
    denied_ok( $res, qr/You have no 'write' permission for the delegated object/ );

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %z1 ) {
        is( $res->get($_), $z1{$_}, "un-modified pseudo delegated zone perm $_" );
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
    is( $res->can_delegate_write, 1, "has write access" );

    #try write access again
    $res = $tuser2->edit_zone_record( nt_zone_record_id => $zrid1, %newzr );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach ( keys %newzr ) {
        is( $res->get($_), $newzr{$_}, "modified delegated zone record" );
    }

    #still no write access to zone
    $res = $tuser2->edit_zone( nt_zone_id => $zid1, %newz );
    denied_ok( $res, qr/You have no 'write' permission for the delegated object/ );

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %z1 ) {
        is( $res->get($_), $z1{$_}, "un-modified pseudo delegated zone perm $_" );
    }

    #perm_delegate
    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    is( $res->can_delegate_delegate, 0, "has no delegate access" );

    #make test group
    $res = $user->new_group(
        nt_group_id => $gid2,
        name        => "testsubsubgroup",
    );
    noerrok($res);
    my $tgid = $res->get('nt_group_id');

    $res = $tuser2->delegate_zone_records(
        zonerecord_list => $zrid1,
        nt_group_id     => $tgid,
        %dpermsnone
    );
    denied_ok( $res, qr/You have no 'delegate' permission for the delegated object/ );

    #try to delegate pseudo-delegated zone
    $res = $tuser2->delegate_zones(
        zone_list   => $zid1,
        nt_group_id => $tgid,
        %dpermsnone
    );
    denied_ok( $res, qr/You have no 'delegate' permission for the delegated object/ );

    #change perms to allow delegation

    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2,
        %dpermsnone, perm_delegate => 1
    );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    is( $res->can_delegate_delegate, 1, "has delegate access" );

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
    denied_ok( $res, qr/You have no 'delegate' permission for the delegated object/ );

    $res = $user->delete_group( nt_group_id => $tgid );
    noerrok($res);

    #perm_delete

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    is( $res->can_delegate_delete, 0, "has no delete access" );

    $res = $tuser2->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    denied_ok( $res, qr/You have no 'delegate' permission for the delegated object/ );

    $res = $tuser2->delete_zone_delegation(
        nt_zone_id  => $zid1,
        nt_group_id => $gid2
    );
    denied_ok( $res, qr/You have no 'delegate' permission for the delegated object/ );

    #change perms to allow removal of delegation
    $res = $tuser->edit_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2,
        %dpermsnone,
        perm_delete => 1
    );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    is( $res->can_delegate_delete, 1, "has delete access" );

    $res = $tuser2->delete_zone_record_delegation(
        nt_zone_record_id => $zrid1,
        nt_group_id       => $gid2
    );
    noerrok($res);

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONERECORD : $zrid1\)/ );

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    denied_ok( $res, qr/No Access Allowed to that object \(ZONE : $zid1\)/ );

    $res = $tuser2->get_group_zones;
    ok( !has_id( $res, $zid1 ) );

    #cleanup
    $tuser2->logout;
}

sub cleanup {

    $tuser->logout;

    my $res = $user->delete_users( user_list => [ $uid1, $uid2 ] );
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
}
