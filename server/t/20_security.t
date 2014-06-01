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

=head1 DESCRIPTION

Other security related interaction tests.  This script
checks that no delegation of Zones or Zone Records can
be made such that the delegate has more access to the
delegated object than the delegator.  

Also test that a user in a group cannot access any objects
that have not been delegated to his group and that are not
in his group or a subgroup.  Nameserver objects are an
exception: they can be read by anybody.

=cut

use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test;

BEGIN { plan tests => 291 }

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

%dpermmap = (
    perm_write               => 'delegate_write',
    perm_delete              => 'delegate_delete',
    perm_delegate            => 'delegate_delegate',
    zone_perm_add_records    => 'delegate_add_records',
    zone_perm_delete_records => 'delegate_delete_records',
);

#full delegation permissions for zone
%dpermsnone = (
    perm_write               => 0,
    perm_delete              => 0,
    perm_delegate            => 0,
    zone_perm_add_records    => 0,
    zone_perm_delete_records => 0,

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

&start;

eval {&delegation};
warn $@ if $@;

eval {&security};
warn $@ if $@;

&del;

=head1 Runup to tests

=over

=cut

sub start {

=item login as root

=cut

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

=item make a new group  (GROUP1)

    GROUP1 has all permissions set to 0.

=cut

    $res = $user->new_group( name => 'test_delete_me1', %permsnone );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

=item make a new user in GROUP1  (USER1)

    USER1 inherits permissions from GROUP1.

=cut

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

}

=back

=cut

=head1 Test delegation permissions

No one should be able to delegate objects with more permissions
than they themselves have. Nor should they be able to 
edit existing delegations and change any permission which they
do not have.

Zones:

=over

=item perm_write

    0 unless user has "zone_write" permission

=item zone_perm_add_records

    0 unless user has "zonerecord_create" permission

=item zone_perm_delete_records

    0 unless user has "zonerecord_delete" permission


=back

Records:

=over

=item perm_write

    0 unless user has "zonerecord_write" permission

=back

BEGIN delegation permissions tests:

=over

=cut

sub delegation {

=item make new zone (ZONE1)

=cut

    $res = $user->new_zone(
        nt_group_id => $gid1,
        zone        => 'highlevel.com',
        serial      => 0,
        ttl         => 86400,
        description => "delegation security test delete me",
        mailaddr    => "root.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    noerrok($res);
    $zid1 = $res->get('nt_zone_id');

=item new record in zone (RECORD1)

=cut

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

=item new subgroup in GROUP1 (GROUP2)
    
GROUP2 has full permissions.

=cut

    $res = $group1->new_group( name => 'testsubgroup', %permsfull );
    die "Couldn't create test subgroup"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid2 = $res->get('nt_group_id');

    $subg = $user->get_group( nt_group_id => $gid2 );
    die "Couldn't get test subgroup"
        unless noerrok($subg)
            and ok( $subg->id, $gid2 );

=item new user in GROUP2 (USER2)

USER2 inherits permissions from GROUP2. 

=cut

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

=item log in as USER1

=cut

    $tuser = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );

    $tuser->login(
        username => 'testuser1@test_delete_me1',
        password => 'testpass'
    );
    die "couldn't log in as test user 1" unless noerrok( $tuser->result );

=item log in as USER2

=cut

    $tuser2 = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );

    $tuser2->login(
        username => 'testuser2@testsubgroup',
        password => 'testpass2'
    );
    die "couldn't log in as test user 2" unless noerrok( $tuser2->result );

    #verify perms are all 0

    foreach ( keys %permsnone ) {
        ok( $tuser->get($_), $permsnone{$_}, "user has no $_ perms" );
    }

=item for GROUP1 set zone_delegate and zonerecord_delegate to true

(USER1 inherits)

=cut

    noerrok(
        $user->edit_group(
            nt_group_id => $gid1,
            %permsnone,
            zone_delegate       => 1,
            zonerecord_delegate => 1
        )
    );

    noerrok( $tuser->refresh );

    #verify delegation permissions
    foreach (qw(zone_delegate zonerecord_delegate)) {
        ok( $tuser->get($_), 1, "user can delegate $_" );
    }

=back

Test Zones:

=over

=cut

=item USER1 delegates ZONE1 to GROUP2 with perm_write=1

=cut

    %dp = %dpermsnone;
    $dp{'perm_write'} = 1;

    noerrok(
        $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dp,
        )
    );

=item  USER2 checks permissions on delegated ZONE1

perm_write should be 0

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);

    #warn Data::Dumper::Dumper($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            0, "shouldn't have delegate $_ access" );
    }

=item (remove delegation of ZONE1 to GROUP2)

=cut

    noerrok(
        $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=item USER1 delegates ZONE1 to GROUP2 with zone_perm_add_records=1

=cut

    %dp = %dpermsnone;
    $dp{'zone_perm_add_records'} = 1;
    noerrok(
        $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dp,
        )
    );

=item USER2 checks permissions on delegated ZONE1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            0, "shouldn't have delegate $_ access" );
    }

=item USER1 removes delegation of ZONE1 to GROUP2

=cut

    noerrok(
        $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=item USER1 delegatews ZONE1 to GROUP2 with zone_perm_delete_records=1

=cut

    %dp = %dpermsnone;
    $dp{'zone_perm_delete_records'} = 1;
    noerrok(
        $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dpermsnone,
            zone_perm_delete_records => 1
        )
    );

=item USER2 checks permissions on delegated zone

(all perms should be 0)

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            0, "shouldn't have delegate $_ access" );
    }

=item USER1 removes delegation ZONE1 -> GROUP2

=cut

    noerrok(
        $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=item USER1 changes GROUP1 set zone_write=1

=cut

    noerrok(
        $user->edit_group(
            nt_group_id => $gid1,
            zone_write  => 1,
        )
    );

=item USER1 delegates ZONE1 to GROUP2 with perm_write=1

=cut

    %dp = %dpermsnone;
    $dp{'perm_write'} = 1;
    noerrok(
        $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dp,
        )
    );

=item USER2 checks permissions on delegated zone

(all perms should be 0 except perm_write should be 1)

=cut

    %dp               = %dpermsnone;
    $dp{'perm_write'} = 1;
    $res              = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dp ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "$_ access should be '$dp{$_}'" );
    }

=item USER1 removes delegation ZONE1 -> GROUP2

=cut

    noerrok(
        $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=item USER1 changes GROUP1 set zonerecord_create=1

=cut

    noerrok(
        $user->edit_group(
            nt_group_id       => $gid1,
            zonerecord_create => 1,
        )
    );

=item USER1 delegates ZONE1 to GROUP2 with zone_perm_add_records=1

=cut

    %dp = %dpermsnone;
    $dp{'zone_perm_add_records'} = 1;
    noerrok(
        $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dp,
        )
    );

=item USER2 checks permissions on delegated zone

(all perms should be 0 except zone_perm_add_records should be 1)

=cut

    %dp                          = %dpermsnone;
    $dp{'zone_perm_add_records'} = 1;
    $res                         = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dp ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "$_ access should be '$dp{$_}'" );
    }

=item USER1 removes delegation ZONE1 -> GROUP2

=cut

    noerrok(
        $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=item USER1 changes GROUP1 set zonerecord_delete=1

=cut

    noerrok(
        $user->edit_group(
            nt_group_id       => $gid1,
            zonerecord_delete => 1,
        )
    );

=item USER1 delegates ZONE1 to GROUP2 with zone_perm_delete_records=1

=cut

    %dp = %dpermsnone;
    $dp{'zone_perm_delete_records'} = 1;
    noerrok(
        $tuser->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dp,
        )
    );

=item USER2 checks permissions on delegated zone

(all perms should be 0 except zone_perm_add_records should be 1)

=cut

    %dp = %dpermsnone;
    $dp{'zone_perm_delete_records'} = 1;
    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dp ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "$_ access should be '$dp{$_}'" );
    }

=item USER1 removes delegation ZONE1 -> GROUP2

=cut

    noerrok(
        $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=back

Test Zone Records:

=over

=cut

=item USER1 delegates RECORD1 to GROUP2 with perm_write=1

=cut

    %dp = %dpermsnone;
    $dp{'perm_write'} = 1;
    noerrok(
        $tuser->delegate_zone_records(
            zonerecord_list => $zrid1,
            nt_group_id     => $gid2,
            %dp,
        )
    );

=item USER2 checks permissions on delegated RECORD1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach (qw(perm_write perm_delete perm_delegate)) {
        ok( $res->get( $dpermmap{$_} ),
            0, "shouldn't have delegate $_ access" );
    }

=item USER1 removes delegation RECORD1 -> GROUP2

=cut

    noerrok(
        $tuser->delete_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2
            )

    );

=item USER1 changes GROUP1 set zonerecord_write=1

=cut

    noerrok(
        $user->edit_group(
            nt_group_id      => $gid1,
            zonerecord_write => 1,
        )
    );

=item USER1 delegates RECORD1 to GROUP2 with perm_write=1

=cut

    %dp = %dpermsnone;
    $dp{'perm_write'} = 1;
    noerrok(
        $tuser->delegate_zone_records(
            zonerecord_list => $zrid1,
            nt_group_id     => $gid2,
            %dp,
        )
    );

=item USER2 checks permissions on delegated RECORD1

(all perms should be 0 except delegate_write should be 1)

=cut

    %dp = %dpermsnone;
    $dp{'perm_write'} = 1;
    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach (qw(perm_write perm_delete perm_delegate)) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "$_ access should be $dp{$_}" );
    }

=item USER1 removes delegation RECORD1 -> GROUP2

=cut

    noerrok(
        $tuser->delete_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2
            )

    );

=back

Test editting of delegations for permissions violations:

=over

=cut

=item root changes GROUP1 set perms to none, allow delegation of Zone and Zonerecords

=cut

    noerrok(
        $user->edit_group(
            nt_group_id => $gid1,
            %permsnone,
            zone_delegate       => 1,
            zonerecord_delegate => 1,
        )
    );

=item root delegates ZONE1 to GROUP2 with perm_write=1

=cut

    %dp = %dpermsnone;
    $dp{'perm_write'} = 1;

    noerrok(
        $user->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dp,
        )
    );

=item  USER2 checks permissions on delegated ZONE1

perm_write should be 0

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);

    #warn Data::Dumper::Dumper($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "shouldn't have delegate $_ access" );
    }

=item USER1 edits delegation, tries to set perm_write to 0

=cut

    noerrok(
        $tuser->edit_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2,
            perm_write  => 0,
            )

    );

=item  USER2 checks permissions on delegated ZONE1

perm_write should be 0

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);

    #warn Data::Dumper::Dumper($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "shouldn't have delegate $_ access" );
    }

=item root changes GROUP1 set zone_write=1

=cut

    noerrok(
        $user->edit_group(
            nt_group_id => $gid1,
            zone_write  => 1,
        )
    );

=item USER1 edits delegation, tries to set perm_write to 0

=cut

    noerrok(
        $tuser->edit_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2,
            perm_write  => 0,
            )

    );

=item  USER2 checks permissions on delegated ZONE1

perm_write should be 0

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);

    #warn Data::Dumper::Dumper($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            0, "shouldn't have delegate $_ access" );
    }

=item root removes delegation of ZONE1 to GROUP2

=cut

    noerrok(
        $user->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=item root delegates ZONE1 to GROUP2 with zone_perm_add_records=1

=cut

    %dp = %dpermsnone;
    $dp{'zone_perm_add_records'} = 1;
    noerrok(
        $user->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dp,
        )
    );

=item USER2 checks permissions on delegated ZONE1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "shouldn't have delegate $_ access" );
    }

=item USER1 edits delegation, tries to set zone_perm_add_records to 0

=cut

    noerrok(
        $tuser->edit_zone_delegation(
            nt_zone_id            => $zid1,
            nt_group_id           => $gid2,
            zone_perm_add_records => 0,
            )

    );

=item USER2 checks permissions on delegated ZONE1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "shouldn't have delegate $_ access" );
    }

=item root changes GROUP1 set zonerecord_create=1

=cut

    noerrok(
        $user->edit_group(
            nt_group_id       => $gid1,
            zonerecord_create => 1,
        )
    );

=item USER1 edits delegation, tries to set zone_perm_add_records to 0

=cut

    noerrok(
        $tuser->edit_zone_delegation(
            nt_zone_id            => $zid1,
            nt_group_id           => $gid2,
            zone_perm_add_records => 0,
            )

    );

=item USER2 checks permissions on delegated ZONE1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            0, "shouldn't have delegate $_ access" );
    }

=item USER1 removes delegation of ZONE1 to GROUP2

=cut

    noerrok(
        $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=item root delegates ZONE1 to GROUP2 with zone_perm_delete_records=1

=cut

    %dp = %dpermsnone;
    $dp{'zone_perm_delete_records'} = 1;
    noerrok(
        $user->delegate_zones(
            zone_list   => $zid1,
            nt_group_id => $gid2,
            %dpermsnone,
            zone_perm_delete_records => 1
        )
    );

=item USER2 checks permissions on delegated zone

(all perms should be 0)

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "shouldn't have delegate $_ access" );
    }

=item USER1 edits delegation, tries to set zone_perm_delete_records to 0

=cut

    noerrok(
        $tuser->edit_zone_delegation(
            nt_zone_id               => $zid1,
            nt_group_id              => $gid2,
            zone_perm_delete_records => 0,
            )

    );

=item USER2 checks permissions on delegated ZONE1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "shouldn't have delegate $_ access" );
    }

=item root changes GROUP1 set zonerecord_delete=1

=cut

    noerrok(
        $user->edit_group(
            nt_group_id       => $gid1,
            zonerecord_delete => 1,
        )
    );

=item USER1 edits delegation, tries to set zone_perm_delete_records to 0

=cut

    noerrok(
        $tuser->edit_zone_delegation(
            nt_zone_id               => $zid1,
            nt_group_id              => $gid2,
            zone_perm_delete_records => 0,
            )

    );

=item USER2 checks permissions on delegated ZONE1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone( nt_zone_id => $zid1 );
    noerrok($res);
    foreach ( keys %dpermsnone ) {
        ok( $res->get( $dpermmap{$_} ),
            0, "shouldn't have delegate $_ access" );
    }

=item USER1 removes delegation ZONE1 -> GROUP2

=cut

    noerrok(
        $tuser->delete_zone_delegation(
            nt_zone_id  => $zid1,
            nt_group_id => $gid2
            )

    );

=back

Test editting of Zone Records:

=over

=item root changes GROUP1 set perms to none, allow delegation of Zone and Zonerecords

=cut

    noerrok(
        $user->edit_group(
            nt_group_id => $gid1,
            %permsnone,
            zone_delegate       => 1,
            zonerecord_delegate => 1,
        )
    );

=cut

=item root delegates RECORD1 to GROUP2 with perm_write=1

=cut

    %dp = %dpermsnone;
    $dp{'perm_write'} = 1;
    noerrok(
        $user->delegate_zone_records(
            zonerecord_list => $zrid1,
            nt_group_id     => $gid2,
            %dp,
        )
    );

=item USER2 checks permissions on delegated RECORD1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach (qw(perm_write perm_delete perm_delegate)) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "shouldn't have delegate $_ access" );
    }

=item USER1 edits delegation, tries to set perm_write to 0

=cut

    noerrok(
        $tuser->edit_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2,
            perm_write        => 0,
            )

    );

=item USER2 checks permissions on delegated RECORD1

(all perms should be 0,except perm_write should be 1)

=cut

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach (qw(perm_write perm_delete perm_delegate)) {
        ok( $res->get( $dpermmap{$_} ),
            $dp{$_}, "shouldn't have delegate $_ access" );
    }

=item root changes GROUP1 set zonerecord_write=1

=cut

    noerrok(
        $user->edit_group(
            nt_group_id      => $gid1,
            zonerecord_write => 1,
        )
    );

=item USER1 edits delegation, tries to set perm_write to 0

=cut

    noerrok(
        $tuser->edit_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2,
            perm_write        => 0,
            )

    );

=item USER2 checks permissions on delegated RECORD1

(all perms should be 0)

=cut

    $res = $tuser2->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res);
    foreach (qw(perm_write perm_delete perm_delegate)) {
        ok( $res->get( $dpermmap{$_} ),
            0, "shouldn't have delegate $_ access" );
    }

=item USER1 removes delegation RECORD1 -> GROUP2

=cut

    noerrok(
        $tuser->delete_zone_record_delegation(
            nt_zone_record_id => $zrid1,
            nt_group_id       => $gid2
            )

    );

=back

END Delegation permissions tests.

Cleanup:

=over

=cut

=item Delete RECORD1

=cut

    noerrok( $user->delete_zone_record( nt_zone_record_id => $zrid1 ) );

=item Delete ZONE1

=cut

    noerrok( $user->delete_zones( zone_list => $zid1 ) );

=item Delete USER2

=cut

    noerrok( $user->delete_users( user_list => $uid2 ) );

=item Delete GROUP2

=cut

    noerrok( $user->delete_group( nt_group_id => $gid2 ) );

}

=head1 security tests

Test integrity of access model.  

=over

=item 

Users should not be able to 
modify/read/move/delete objects higher than their own group.

=item 

Users should not be able to 
modify/read/move/delete objects at a peer level to their own group

=item

Users should not be able to 
modify/read/move/delete objects at a lower level than their own group
if the objects are not inside a subgroup of their own group.

=item

Users should not be able to modify their own group settings.

=back

BEGIN tests:

Test access above user's group:

=over

=cut

sub security {

=item edit GROUP1 for full permissions

=cut

    noerrok( $group1->edit_group(%permsfull) );

=item root creates zone ZONE1

=cut

    $res = $user->new_zone(
        zone        => 'highlevel.com',
        serial      => 0,
        ttl         => 86400,
        description => "security test delete me",
        mailaddr    => "root.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    noerrok($res);
    $zid1 = $res->get('nt_zone_id');

=item new record in zone (RECORD1)

=cut

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

=item root makes a new group  (GROUP2)

=cut

    $res = $user->new_group( name => 'test_delete_me2', %permsfull );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid2 = $res->get('nt_group_id');

    $group2 = $user->get_group( nt_group_id => $gid2 );
    die "Couldn't get test group1"
        unless noerrok($group2)
            and ok( $group2->id, $gid2 );

=item root makes a new user in top level group (USER2)

=cut

    $res = $user->new_user(
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
    $uid2 = $res->get('nt_user_id');

=item root makes a new nameserver in top level group (NAMESERVER1)

=cut

    $res = $user->new_nameserver(
        name          => 'ns2.somewhere.com.',
        address       => '1.2.3.5',
        export_format => 'djbdns',
        ttl           => 86401
    );
    die "couldn't make test nameserver"
        unless noerrok($res)
            and ok( $res->get('nt_nameserver_id') => qr/^\d+$/ );
    $nsid1 = $res->get('nt_nameserver_id');

=item USER1 logs in

=cut

    $tuser = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );

    $tuser->login(
        username => 'testuser1@test_delete_me1',
        password => 'testpass'
    );
    die "couldn't log in as test user 1" unless noerrok( $tuser->result );

=item USER1 tries to create new objects in top level group

=over

=item Zone

=cut

    $res = $tuser->new_zone(
        nt_group_id => $user->get('nt_group_id'),
        zone        => 'atahigherlevel.test',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "root.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item User

=cut

    $res = $tuser->new_user(
        nt_group_id               => $user->get('nt_group_id'),
        first_name                => 'test',
        last_name                 => '1',
        email                     => 'test@blah.blah',
        username                  => 'highertestuser',
        password                  => 'testpass',
        password2                 => 'testpass',
        inherit_group_permissions => 1,
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item Group

=cut

    $res = $tuser->new_group(
        nt_group_id => $user->get('nt_group_id'),
        name        => 'HIGH LEVEL TEST delete me',
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item Nameserver

=cut

    $res = $tuser->new_nameserver(
        nt_group_id   => $user->get('nt_group_id'),
        name          => 'ns2.somewhere.test.',
        address       => '4.4.4.4',
        export_format => 'djbdns',
        ttl           => 86404
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item Record (inside ZONE1)

=cut

    $res = $tuser->new_zone_record(
        nt_zone_id  => $zid1,
        name        => 'TEST',
        ttl         => 86400,
        description => 'HIGH LEVEL TEST delete me',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=back

=cut

=item USER1 tries to modify objects in the top level group

=over

=item ZONE1

=cut

    $res = $tuser->edit_zone(
        nt_zone_id  => $zid1,
        description => 'HIGH LEVEL TEST 2 delete me',
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item USER2

=cut

    $res = $tuser->edit_user(
        nt_user_id => $uid2,
        first_name => 'TESTTEST',
        last_name  => 'DELETEME',
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item GROUP2

=cut

    $res = $tuser->edit_group(
        nt_group_id => $gid2,
        name        => 'HIGH LEVEL TEST',
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item root group

=cut

    $res = $tuser->edit_group(
        nt_group_id => $user->get('nt_group_id'),
        name        => 'HIGH LEVEL TEST',
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item NAMESERVER1

=cut

    $res = $tuser->edit_nameserver(
        nt_nameserver_id => $nsid1,
        description      => 'HIGH LEVEL TEST 2 delete me',
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item RECORD1

=cut

    $res = $tuser->edit_zone_record(
        nt_zone_record_id => $zrid1,
        description       => 'HIGH LEVEL TEST 2 delete me',
    );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=back

=item User tries to delete objects in higher level group

=over

=item ZONE1

=cut

    $res = $tuser->delete_zones( zone_list => $zid1, );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item USER2

=cut

    $res = $tuser->delete_users( user_list => $uid2, );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item GROUP2

=cut

    $res = $tuser->delete_group( nt_group_id => $gid2, );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item root group

=cut

    $res = $tuser->delete_group( nt_group_id => $user->get('nt_group_id'), );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item NAMESERVER1

=cut

    $res = $tuser->delete_nameserver( nt_nameserver_id => $nsid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item RECORD1

=cut

    $res = $tuser->delete_zone_record( nt_zone_record_id => $zrid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=back

=item USER1 tries to read objects in the top level group

=over

=item ZONE1

=cut

    $res = $tuser->get_zone( nt_zone_id => $zid1, );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item USER2

=cut

    $res = $tuser->get_user( nt_user_id => $uid2, );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item GROUP2

=cut

    $res = $tuser->get_group( nt_group_id => $gid2, );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item root group

=cut

    $res = $tuser->get_group( nt_group_id => $user->get('nt_group_id'), );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item NAMESERVER1 (access allowed,all nameservers read accessible)

=cut

    $res = $tuser->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($res);

=item RECORD1

=cut

    $res = $tuser->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=back

=item User tries to add objects to peer level group

=over

=item Zone

=cut

    $res = $tuser->new_zone(
        nt_group_id => $gid2,
        zone        => 'atahigherlevel.test',
        serial      => 0,
        ttl         => 86400,
        description => "test delete me",
        mailaddr    => "root.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item User

=cut

    $res = $tuser->new_user(
        nt_group_id               => $gid2,
        first_name                => 'test',
        last_name                 => '1',
        email                     => 'test@blah.blah',
        username                  => 'highertestuser',
        password                  => 'testpass',
        password2                 => 'testpass',
        inherit_group_permissions => 1,
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item Group

=cut

    $res = $tuser->new_group(
        nt_group_id => $gid2,
        name        => 'HIGH LEVEL TEST delete me',
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=item Nameserver

=cut

    $res = $tuser->new_nameserver(
        nt_group_id   => $gid2,
        name          => 'ns2.somewhere.test.',
        address       => '4.4.4.4',
        export_format => 'djbdns',
        ttl           => 86404
    );

    noerrok( $res, 404 );
    ok( $res->error_msg,  qr/No Access Allowed to that object/ );
    ok( $res->error_desc, qr/Access Permission denied/ );

=back 

=item User logs out

=cut

    $tuser->logout;

=item root deletes USER2

=cut

    noerrok( $user->delete_users( user_list => $uid2 ) );

=item root deletes GROUP2

=cut

    noerrok( $user->delete_group( nt_group_id => $gid2 ) );

=item root deletes NAMESERVER1

=cut

    noerrok( $user->delete_nameserver( nt_nameserver_id => $nsid1 ) );

=item root deletes RECORD1

=cut

    noerrok( $user->delete_zone_record( nt_zone_record_id => $zrid1 ) );

=item root deletes ZONE1

=cut

    noerrok( $user->delete_zones( zone_list => $zid1 ) );

=item END security tests

=back

=cut

}

=head1 Cleanup

Clean up test objects:

=over

=cut

sub del {

=item Delete USER1

=cut

    noerrok( $user->delete_users( user_list => $uid1 ) );

=item Delete GROUP1

=cut

    noerrok( $group1->delete );
}
