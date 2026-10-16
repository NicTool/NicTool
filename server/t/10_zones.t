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

  create groups for support
  create new nameservers inside the group
  create test zones inside the group
  test all the zone related API calls
  delete the zones
  delete the nameservers
  delete the groups

=head1 TODO

 get_group_zones search stuff

=cut

use strict;
use warnings;

# use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test::More 'no_plan';

my $user = nt_api_connect();

my ( $group1, $group2, $gid1, $gid2, $nsid1, $nsid2, $zid1, $zid2, $res );
my ( $rzid1, $rzid2, %z1, %z2, $zone1, $zone2, $n1, $n2, $z, @z );

# try to do the tests
eval {&all_the_tests};
warn $@ if $@;

# delete objects even if other tests bail
eval {&test_cleanups};
warn $@ if $@;

sub all_the_tests {

    ####################
    # setup            #
    ####################

    $gid1 = new_id_ok( $user->get_group->new_group( name => 'test_delete_me1' ),
        'nt_group_id', "Couldn't create test group1" );
    $group1 =
        fetched_ok( $user->get_group( nt_group_id => $gid1 ), $gid1, "Couldn't get test group1" );

    $gid2 = new_id_ok( $user->get_group->new_group( name => 'test_delete_me2' ),
        'nt_group_id', "Couldn't create test group2" );
    $group2 =
        fetched_ok( $user->get_group( nt_group_id => $gid2 ), $gid2, "Couldn't get test group2" );

    #make test nameservers
    my $res = $group1->new_nameserver(
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'bind',
        ttl           => 86400
    );
    $nsid1 = new_id_ok( $res, 'nt_nameserver_id', "couldn't make test nameserver" );

    $res = $group1->new_nameserver(
        name          => 'ns2.somewhere.com.',
        address       => '1.2.3.5',
        export_format => 'djbdns',
        ttl           => 86401
    );
    $nsid2 = new_id_ok( $res, 'nt_nameserver_id', "couldn't make test nameserver" );

    test_new_zone();
    test_subdomain_conflicts();
    test_get_zone();
    test_get_zone_list();
    test_get_group_zones();
    test_edit_zone();
    test_move_zones();
    test_delete_zones();
}

sub test_cleanups {

    for (
        [ $zid1,  'delete_zones',      zone_list        => 'zone 1' ],
        [ $zid2,  'delete_zones',      zone_list        => 'zone 2' ],
        [ $rzid1, 'delete_zones',      zone_list        => 'reverse zone 1' ],
        [ $rzid2, 'delete_zones',      zone_list        => 'reverse zone 2' ],
        [ $nsid1, 'delete_nameserver', nt_nameserver_id => 'nameserver1' ],
        [ $nsid2, 'delete_nameserver', nt_nameserver_id => 'nameserver2' ],
        [ $gid1,  'delete_group',      nt_group_id      => 'group1' ],
        [ $gid2,  'delete_group',      nt_group_id      => 'group2' ],
        )
    {
        my ( $id, $call, $param, $label ) = @$_;
        next if !defined $id;
        my $res = $user->$call( $param => $id );
        noerrok($res) or do {
            warn "Couldn't delete test $label";
            diag( $call eq 'delete_group' ? $res : Data::Dumper::Dumper($res) );
        };
    }
}

sub delete_if_created {
    my ($res) = @_;
    return if $res->is_error;
    $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
    noerrok($res)
        or die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
}

sub zone_nameservers_seen {
    my ($zone) = @_;
    my %seen = map { $_->{'nt_nameserver_id'} => 1 } @{ $zone->get('nameservers') };
    return ( $seen{$nsid1} ? 1 : 0, $seen{$nsid2} ? 1 : 0 );
}

sub test_new_zone {

    bad_id_ok(
        'nameservers',
        sub {
            my $res = $group1->new_zone(
                zone        => 'test.com',
                serial      => 0,
                ttl         => '86400',
                nameservers => shift,
                description => "test delete me",
            );
            delete_if_created($res);
            return $res;
        },
        "abc,def",
        "0",
        "-1"
    );

    # zone missing
    my $res = $group1->new_zone(

        #zone       => 'test.com',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    param_error_ok( $res, 301, 'zone' );
    delete_if_created($res);

    ####################
    # make test zones  #
    ####################

    %z1 = (
        zone        => 'test.com',
        serial      => 0,
        ttl         => '86400',
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    $zid1 = new_id_ok( $group1->new_zone(%z1), 'nt_zone_id', "couldn't make test zone1" );

    %z2 = (
        zone        => 'anothertest.com',
        serial      => 1,
        ttl         => 86401,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me also",
        mailaddr    => "somebodyelse.somewhere.com",
        refresh     => 100,
        retry       => 200,
        expire      => 300,
        minimum     => 400,
    );
    $zid2 = new_id_ok( $group1->new_zone(%z2), 'nt_zone_id', "couldn't make test zone2" );

    ####################
    # try duplicate zone
    ####################

    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    sanity_error_ok( $res, qr/Zone is already taken/ );
    delete_if_created($res);

    # the same name in capitals, with the trailing dot, is the same zone
    $res = $group1->new_zone(
        zone        => 'TEST.com.',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~ qr/Zone is already taken/ );
    delete_if_created($res);

    # every trailing dot is stripped, so a repeat is the same zone
    $res = $group1->new_zone(
        zone        => 'DotTest.com..',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    noerrok($res) or die "couldn't make the trailing dots zone";
    my $dots_id = $res->get('nt_zone_id');
    is( $user->get_zone( nt_zone_id => $dots_id )->get('zone'), 'dottest.com' );
    $res = $group1->new_zone(
        zone        => 'DotTest.com..',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~ qr/Zone is already taken/ );
    delete_if_created($res);
    $res = $user->delete_zones( zone_list => $dots_id );
    noerrok($res) or die "Couldn't delete zone mistake $dots_id";

    # a new zone is stored lowercase
    $res = $group1->new_zone(
        zone        => 'MixedCase-Test.com',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    noerrok($res) or die "couldn't make the mixed case zone";
    my $mixed_id = $res->get('nt_zone_id');
    $res = $user->get_zone( nt_zone_id => $mixed_id );
    noerrok($res);
    is( $res->get('zone'), 'mixedcase-test.com' );
    $res = $user->delete_zones( zone_list => $mixed_id );
    noerrok($res) or die "Couldn't delete zone mistake $mixed_id";

    my %rz1 = (
        zone        => '3.2.1.in-addr.arpa',
        serial      => 1,
        ttl         => 86401,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me also",
        mailaddr    => "somebodyelse.somewhere.com",
        refresh     => 100,
        retry       => 200,
        expire      => 300,
        minimum     => 400,
    );
    $rzid1 =
        new_id_ok( $group1->new_zone(%rz1), 'nt_zone_id', "couldn't make test reverse zone 1" );

    my %rz2 = (
        zone        => '3.2.1.ip6.arpa',
        serial      => 1,
        ttl         => 86401,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me also",
        mailaddr    => "somebodyelse.somewhere.com",
        refresh     => 100,
        retry       => 200,
        expire      => 300,
        minimum     => 400,
    );
    $rzid2 =
        new_id_ok( $group1->new_zone(%rz2), 'nt_zone_id', "couldn't make test reverse zone 1" );
}

sub test_get_zone {

    bad_id_ok( 'nt_zone_id', sub { $user->get_zone( nt_zone_id => shift ) } );

    ####################
    # get test zones   #
    ####################

    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    fetched_ok( $zone1, $zid1, "Couldn't get test zone $zid1 : " . errtext($zone1) );

    for (qw(zone serial ttl description mailaddr refresh retry expire minimum)) {
        ok( $zone1->get($_) =~ $z1{$_} );
    }
    ok($_) for zone_nameservers_seen($zone1);

    $zone2 = $user->get_zone( nt_zone_id => $zid2 );
    fetched_ok( $zone2, $zid2, "Couldn't get test zone $zid2 : " . errtext($zone2) );

    for (qw(zone serial ttl description mailaddr refresh retry expire minimum)) {
        is( $zone2->get($_), $z2{$_} );
    }
    ok($_) for zone_nameservers_seen($zone2);
}

sub test_subdomain_conflicts {

    my $token            = 'issue309' . time() . $$ . int( rand(1000) );
    my $parent_zone_name = "$token.parent.test.com";

    my %parent_zone_data = (
        zone        => $parent_zone_name,
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "issue309 temporary parent zone",
        mailaddr    => "hostmaster.$parent_zone_name",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );

    my $res = $group1->new_zone(%parent_zone_data);
    noerrok($res)
        or die "Couldn't create temporary parent zone $parent_zone_name";
    my $parent_zone_id = $res->get('nt_zone_id');

    $res = $user->get_zone( nt_zone_id => $parent_zone_id );
    noerrok($res)
        or die "Couldn't load temporary parent zone for sub-domain tests";

    my $subzone = "$token.dev.$parent_zone_name";

    # A first-label record in the parent zone should not block a deeper sub-domain.
    $res = $res->new_zone_record(
        name    => $token,
        type    => 'A',
        address => '192.0.2.30',
        ttl     => 300,
    );
    noerrok($res) or die "Couldn't create test record $token";
    my $first_label_id = $res->get('nt_zone_record_id');

    my %subzone_data = (
        zone        => $subzone,
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "issue309 allow deeper sub-domain",
        mailaddr    => "hostmaster.$subzone",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );

    $res = $group1->new_zone(%subzone_data);
    noerrok($res) or die "Creating deeper sub-domain was incorrectly blocked";
    my $subzone_id = $res->get('nt_zone_id');

    $res = $user->delete_zones( zone_list => $subzone_id );
    noerrok($res) or die "Couldn't delete test sub-domain zone";

    $res = $user->delete_zone_record( nt_zone_record_id => $first_label_id );
    noerrok($res) or die "Couldn't delete first-label test record";

    # A matching relative record in the parent zone must still block creation.
    $res = $user->get_zone( nt_zone_id => $parent_zone_id );
    noerrok($res) or die "Couldn't reload parent zone for conflict test";

    $res = $res->new_zone_record(
        name    => "$token.dev",
        type    => 'A',
        address => '192.0.2.31',
        ttl     => 300,
    );
    noerrok($res) or die "Couldn't create blocking test record $token.dev";
    my $relative_label_id = $res->get('nt_zone_record_id');

    $res = $group1->new_zone(%subzone_data);
    noerrok( $res, 300 );
    like( $res->get('error_msg'), qr/already exists/ );

    $res = $user->delete_zone_record( nt_zone_record_id => $relative_label_id );
    noerrok($res) or die "Couldn't delete relative-label test record";

    $res = $user->delete_zones( zone_list => $parent_zone_id );
    noerrok($res) or die "Couldn't delete temporary parent zone";
}

sub test_get_zone_list {

    bad_id_ok( 'zone_list', sub { $user->get_zone_list( zone_list => shift ) } );

    ####################
    # get test zones   #
    ####################

    my $res = $user->get_zone_list( zone_list => [ $zid1, $zid2 ] );
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 2 );
    if ( $res->size >= 2 ) {
        @z  = $res->list;
        $n1 = -1;
        $n2 = -1;
        for ( 0 .. 1 ) {
            $n1 = $_ if $z[$_]->id eq $zid1;
        }
        for ( 0 .. 1 ) {
            $n2 = $_ if $z[$_]->id eq $zid2;
        }
        if ( $n1 > -1 ) {
            is( $z[$n1]->id, $zid1 );
            for (qw/zone serial ttl description mailaddr refresh retry expire minimum/) {
                is( $z[$n1]->get($_), $z1{$_} );
            }
        }

        if ( $n2 > -1 ) {
            is( $z[$n2]->id, $zid2 );
            for (qw/zone serial ttl description mailaddr refresh retry expire minimum/) {
                is( $z[$n2]->get($_), $z2{$_} );
            }
        }
    }
}

sub test_get_group_zones {

    bad_id_ok( 'nt_group_id', sub { $group1->get_group_zones( nt_group_id => shift ) } );

    ####################
    # get test zones   #
    ####################

    my $res = $group1->get_group_zones;
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 4 );
    my $saw1 = 0;
    my $saw2 = 0;
    if ( $res->size => 4 ) {
        for $z ( $res->list ) {
            if ( $z->id eq $zid1 ) {
                $saw1 = 1;
                is( $z->get('zone'),        $z1{zone} );
                is( $z->get('description'), $z1{description} );
                is( $z->get('nt_zone_id'),  $zid1 );
                is( $z->get('nt_group_id'), $gid1 );
                is( $z->get('group_name'),  'test_delete_me1' );
            }
            elsif ( $z->id eq $zid2 ) {
                $saw2 = 1;
                is( $z->get('zone'),        $z2{zone} );
                is( $z->get('description'), $z2{description} );
                is( $z->get('nt_zone_id'),  $zid2 );
                is( $z->get('nt_group_id'), $gid1 );
                is( $z->get('group_name'),  'test_delete_me1' );
            }
        }
    }
    if ( !$saw1 ) {
        for ( 1 .. 5 ) { is( 0, 1, "Didn't find test zone 1" ) }
    }
    if ( !$saw2 ) {
        for ( 1 .. 5 ) { is( 0, 1, "Didn't find test zone 2" ) }
    }
}

sub test_edit_zone {

    bad_id_ok( 'nt_zone_id', sub { $zone1->edit_zone( nt_zone_id => shift ) } );

    for (qw(-2 -1 -299 2147483648 abc)) {
        sanity_error_ok( $zone1->edit_zone( ttl => $_ ), qr/Invalid TTL/, "ttl $_" );
    }

    ####################
    # edit test zone   #
    ####################
    %z1 = (
        zone        => 'test.com',
        serial      => '2',
        ttl         => '86402',
        nameservers => "$nsid1",
        description => "delete me please",
        mailaddr    => "me.somewhere.com",
        refresh     => 12,
        retry       => 22,
        expire      => 32,
        minimum     => 42,
    );

    my $res = $zone1->edit_zone(%z1);
    noerrok($res);

    # listing every changed field outruns the log's 255 character description
    my $log = $user->get_user_global_log( limit => 255 );
    noerrok($log);
    my @edits = grep { $_->{object} eq 'zone' && $_->{object_id} == $zid1 && $_->{action} eq 'modified' }
        @{ $log->get('list') || [] };
    ok( @edits, 'the zone edit is in the global log' );

    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    fetched_ok( $zone1, $zid1, "Couldn't get test zone $zid1 : " . errtext($zone1) );

    for (qw/zone ttl description mailaddr refresh retry expire minimum/) {
        is( $zone1->get($_), $z1{$_} );
    }
    is( $zone1->get('serial'), '3' );
    my ( $saw1, $saw2 ) = zone_nameservers_seen($zone1);
    is( $saw1, 1, "should have seen Nameserver $nsid1" );
    is( $saw2, 0, "should NOT have seen Nameserver $nsid2" );

    #print Data::Dumper::Dumper($zone1->get('nameservers'));
}

sub test_move_zones {

    bad_id_ok( 'zone_list', sub { $group2->move_zones( zone_list => shift ) } );
    bad_id_ok( 'nt_group_id',
        sub { $group2->move_zones( nt_group_id => shift, zone_list => [ $zid1, $zid2 ] ) } );

    ####################
    # move test zones  #
    ####################

    my $res = $group2->move_zones( zone_list => [ $zid1, $zid2 ] );
    noerrok($res);

    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    noerrok($zone1);
    ok( $zone1->get('nt_group_id') =~ $gid2 );

    $zone2 = $user->get_zone( nt_zone_id => $zid2 );
    noerrok($zone2);
    ok( $zone2->get('nt_group_id') =~ $gid2 );
}

sub test_delete_zones {

    bad_id_ok( 'zone_list', sub { $user->delete_zones( zone_list => shift ) } );
}
