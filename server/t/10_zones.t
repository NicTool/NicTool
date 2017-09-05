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

my ($group1, $group2, $gid1, $gid2, $nsid1, $nsid2, $zid1, $zid2);
my ($rzid1, $rzid2, %z1, %z2, $zone1, $zone2, $n1, $n2, $z, @z);

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

    #make a new group
    my $res = $user->get_group->new_group( name => 'test_delete_me1' );
    noerrok($res)
        && ok( $res->get('nt_group_id') =~ qr/^\d+$/ ) or
            die "Couldn't create test group1";
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    noerrok($group1)
        && is( $group1->id, $gid1 ) or
            die "Couldn't get test group1";

    # make a new group
    $res = $user->get_group->new_group( name => 'test_delete_me2' );
    noerrok($res)
        && ok( $res->get('nt_group_id') =~ qr/^\d+$/ ) or
            die "Couldn't create test group2";
    $gid2 = $res->get('nt_group_id');

    $group2 = $user->get_group( nt_group_id => $gid2 );
    noerrok($group2)
        && is( $group2->id, $gid2 ) or
            die "Couldn't get test group2";

    #make test nameservers
    $res = $group1->new_nameserver(
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'bind',
        ttl           => 86400
    );
    noerrok($res)
        && ok( $res->get('nt_nameserver_id') =~ qr/^\d+$/ ) or
            die "couldn't make test nameserver";
    $nsid1 = $res->get('nt_nameserver_id');

    $res = $group1->new_nameserver(
        name          => 'ns2.somewhere.com.',
        address       => '1.2.3.5',
        export_format => 'djbdns',
        ttl           => 86401
    );
    noerrok($res)
        && ok( $res->get('nt_nameserver_id') =~ qr/^\d+$/ ) or
            die "couldn't make test nameserver";
    $nsid2 = $res->get('nt_nameserver_id');

    test_new_zone();
    test_get_zone();
    test_get_zone_list();
    test_get_group_zones();
    test_edit_zone();
    test_move_zones();
    test_delete_zones();
}

sub test_cleanups {

    if ( defined $zid1 ) {
        my $res = $user->delete_zones( zone_list => $zid1 );
        noerrok($res) or do {
            warn "Couldn't delete test zone 1";
            diag Data::Dumper::Dumper($res);
        }
    }

    if ( defined $zid2 ) {
        my $res = $user->delete_zones( zone_list => $zid2 );
        noerrok($res) or do {
            warn "Couldn't delete test zone 2";
            diag Data::Dumper::Dumper($res);
        }
    }

    if ( defined $rzid1 ) {
        my $res = $user->delete_zones( zone_list => $rzid1 );
        noerrok($res) or do {
            warn "Couldn't delete test reverse zone 1";
            diag Data::Dumper::Dumper($res);
        }
    }

    if ( defined $rzid2 ) {
        my $res = $user->delete_zones( zone_list => $rzid2 );
        noerrok($res) or do {
            warn "Couldn't delete test reverse zone 2";
            diag Data::Dumper::Dumper($res);
        }
    }

    if ( defined $nsid1 ) {
        my $res = $user->delete_nameserver( nt_nameserver_id => $nsid1 );
        noerrok($res) or do {
            warn "Couldn't delete test nameserver1";
            diag Data::Dumper::Dumper($res);
        }
    }

    if ( defined $nsid2 ) {
        my $res = $user->delete_nameserver( nt_nameserver_id => $nsid2 );
        noerrok($res) or do {
            warn "Couldn't delete test nameserver2";
            diag Data::Dumper::Dumper($res);
        }
    }

    if ( defined $gid1 ) {
        my $res = $user->delete_group( nt_group_id => $gid1 );
        noerrok($res) or do {
            warn "Couldn't delete test group1";
            diag $res;
        }
    }

    if ( defined $gid2 ) {
        my $res = $user->delete_group( nt_group_id => $gid2 );
        noerrok($res) or do {
            warn "Couldn't delete test group2";
            diag $res;
        }
    }
}

sub test_new_zone {

    # nt_group_id missing
    my $res = $group1->new_zone(
        nt_group_id => '',
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
        noerrok($res) or
            die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
    }

    # nt_group_id not int
    $res = $group1->new_zone(
        nt_group_id => 'abc',
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
        die "Couldn't delete zone mistake " . $res->get('nt_zone_id')
            unless noerrok($res);
    }

    #nt_group_id not valid
    $res = $group1->new_zone(
        nt_group_id => 0,
        zone        => 'test.com',
        serial      => 0,
        ttl         => '86400',
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
        noerrok($res) or
            die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
    }

    # nameservers not int
    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => '86400',
        nameservers => "abc,def",
        description => "test delete me",
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nameservers' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
        noerrok($res) or
            die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
    }

    #nameservers not valid
    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => '86400',
        nameservers => "0",
        description => "test delete me",
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nameservers' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
        noerrok($res) or
            die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
    }

    #nameservers not valid
    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => '86400',
        nameservers => "-1",
        description => "test delete me",
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nameservers' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
        die "Couldn't delete zone mistake " . $res->get('nt_zone_id')
            unless noerrok($res);
    }

    # zone missing
    $res = $group1->new_zone(
        #zone       => 'test.com',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'zone' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
        noerrok($res) or
            die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
    }

    for ( qw{~ ` ! @ $ % ^ & * ( ) + = \ | ' " ; : < > / ?},
        ',', '#', "\n", ' ', qw({ }) )
    {
        # invalid character in zone
        $res = $group1->new_zone(
            zone        => "thisis${_}atest.com",
            serial      => 0,
            ttl         => 86400,
            nameservers => "$nsid1,$nsid2",
            description => "test delete me",
        );
        noerrok( $res, 300, "zone thisis${_}atest.com" );
        ok( $res->get('error_msg')  =~ qr/invalid character in zone/, "new_zone, thisis${_}atest.com" );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
            noerrok($res) or
                die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
        }
    }

    foreach my $ttl (qw(-42 -1 2147483648 grover)) {

        # invalid ttl
        $res = $group1->new_zone(
            zone        => "something.com",
            serial      => 0,
            ttl         => $ttl,
            nameservers => "$nsid1,$nsid2",
            description => "test delete me",
        );
        noerrok( $res, 300, "ttl $ttl" );
        ok( $res->get('error_msg')  =~ qr/Invalid TTL/, "invalid TTL: $ttl" );
        ok( $res->get('error_desc') =~ qr/Sanity error/, "invalid TTL: $ttl" );
        if ( !$res->is_error ) {
            $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
            noerrok($res) or
                die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
        }
    }

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
    $res = $group1->new_zone(%z1);
    noerrok($res)
        && ok( $res->get('nt_zone_id') =~ qr/^\d+$/ )
            or die "couldn't make test zone1";

    $zid1 = $res->get('nt_zone_id');

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
    $res = $group1->new_zone(%z2);
    noerrok($res)
        && ok( $res->get('nt_zone_id') =~ qr/^\d+$/ )
            or die "couldn't make test zone2";

    $zid2 = $res->get('nt_zone_id');

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
    noerrok( $res, 300 );
    ok( $res->get('error_msg')  =~ qr/Zone is already taken/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zones( zone_list => $res->get('nt_zone_id') );
        noerrok($res) or
            die "Couldn't delete zone mistake " . $res->get('nt_zone_id');
    }

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
    $res = $group1->new_zone(%rz1);
    noerrok($res)
        && ok( $res->get('nt_zone_id') =~ qr/^\d+$/ )
            or die "couldn't make test reverse zone 1";
    $rzid1 = $res->get('nt_zone_id');

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
    $res = $group1->new_zone(%rz2);
    noerrok($res)
        && ok( $res->get('nt_zone_id') =~ qr/^\d+$/ ) or
            die "couldn't make test reverse zone 1";

    $rzid2 = $res->get('nt_zone_id');
}

sub test_get_zone {

    my $res = $user->get_zone( nt_zone_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_zone_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $user->get_zone( nt_zone_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_zone_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $user->get_zone( nt_zone_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_zone_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test zones   #
    ####################

    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    noerrok($zone1)
        && is( $zone1->id, $zid1 ) or
            die "Couldn't get test zone $zid1 : " . errtext($zone1);

    for (
        qw(zone serial ttl description mailaddr refresh retry expire minimum))
    {
        ok( $zone1->get($_) =~ $z1{$_} );
    }
    my $saw1 = 0;
    my $saw2 = 0;
    foreach ( @{ $zone1->get('nameservers') } ) {
        if ( $_->{'nt_nameserver_id'} eq $nsid1 ) {
            $saw1 = 1;
        }
        elsif ( $_->{'nt_nameserver_id'} eq $nsid2 ) {
            $saw2 = 1;
        }
    }
    ok($saw1);
    ok($saw2);

    $zone2 = $user->get_zone( nt_zone_id => $zid2 );
    noerrok($zone2)
        && is( $zone2->id, $zid2 ) or
            die "Couldn't get test zone $zid2 : " . errtext($zone2);

    for (
        qw(zone serial ttl description mailaddr refresh retry expire minimum))
    {
        is( $zone2->get($_), $z2{$_} );
    }
    $saw1 = 0;
    $saw2 = 0;
    foreach ( @{ $zone2->get('nameservers') } ) {
        if ( $_->{'nt_nameserver_id'} eq $nsid1 ) {
            $saw1 = 1;
        }
        elsif ( $_->{'nt_nameserver_id'} eq $nsid2 ) {
            $saw2 = 1;
        }
    }
    ok($saw1);
    ok($saw2);
}

sub test_get_zone_list {

    my $res = $user->get_zone_list( zone_list => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $user->get_zone_list( zone_list => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $user->get_zone_list( zone_list => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test zones   #
    ####################

    $res = $user->get_zone_list( zone_list => [ $zid1, $zid2 ] );
    noerrok($res);
    isa_ok($res, 'NicTool::List' );
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
            for (
                qw/zone serial ttl description mailaddr refresh retry expire minimum/
                )
            {
                is( $z[$n1]->get($_), $z1{$_} );
            }
        }

        if ( $n2 > -1 ) {
            is( $z[$n2]->id, $zid2 );
            for (
                qw/zone serial ttl description mailaddr refresh retry expire minimum/
                )
            {
                is( $z[$n2]->get($_), $z2{$_} );
            }
        }
    }
}

sub test_get_group_zones {

    my $res = $group1->get_group_zones( nt_group_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $group1->get_group_zones( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $group1->get_group_zones( nt_group_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test zones   #
    ####################

    $res = $group1->get_group_zones;
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 4 );
    my $saw1 = 0;
    my $saw2 = 0;
    if ( $res->size => 4 ) {
        for $z ( $res->list ) {
            if ( $z->id eq $zid1 ) {
                $saw1 = 1;
                is( $z->get('zone')       , $z1{zone} );
                is( $z->get('description'), $z1{description} );
                is( $z->get('nt_zone_id') , $zid1 );
                is( $z->get('nt_group_id'), $gid1 );
                is( $z->get('group_name') , 'test_delete_me1' );
            }
            elsif ( $z->id eq $zid2 ) {
                $saw2 = 1;
                is( $z->get('zone')       , $z2{zone} );
                is( $z->get('description'), $z2{description} );
                is( $z->get('nt_zone_id') , $zid2 );
                is( $z->get('nt_group_id'), $gid1 );
                is( $z->get('group_name') , 'test_delete_me1' );
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

    my $res = $zone1->edit_zone( nt_zone_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_zone_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $zone1->edit_zone( nt_zone_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_zone_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $zone1->edit_zone( nt_zone_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_zone_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    for (qw(-2 -1 -299 2147483648 abc)) {
        $res = $zone1->edit_zone( ttl => $_ );
        noerrok( $res, 300, "ttl $_" );
        ok( $res->get('error_msg')  =~ qr/Invalid TTL/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
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

    $res = $zone1->edit_zone(%z1);
    noerrok($res);

    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    noerrok($zone1)
        && is( $zone1->id, $zid1 ) or
            die "Couldn't get test zone $zid1 : " . errtext($zone1);

    for ( qw/zone ttl description mailaddr refresh retry expire minimum/ ) {
        is( $zone1->get($_), $z1{$_} );
    }
    is( $zone1->get('serial'), '3' );
    my $saw1 = 0;
    my $saw2 = 0;
    foreach ( @{ $zone1->get('nameservers') } ) {
        if ( $_->{'nt_nameserver_id'} eq $nsid1 ) {
            $saw1 = 1;
        }
        elsif ( $_->{'nt_nameserver_id'} eq $nsid2 ) {
            $saw2 = 1;
        }
    }
    is( $saw1, 1, "should have seen Nameserver $nsid1" );
    is( $saw2, 0, "should NOT have seen Nameserver $nsid2" );

    #print Data::Dumper::Dumper($zone1->get('nameservers'));
}

sub test_move_zones {

    my $res = $group2->move_zones( zone_list => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $group2->move_zones( zone_list => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $group2->move_zones( zone_list => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $group2->move_zones(
        nt_group_id => '',
        zone_list   => [ $zid1, $zid2 ]
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $group2->move_zones(
        nt_group_id => 'abc',
        zone_list   => [ $zid1, $zid2 ]
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $group2->move_zones(
        nt_group_id => 0,
        zone_list   => [ $zid1, $zid2 ]
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # move test zones  #
    ####################

    $res = $group2->move_zones( zone_list => [ $zid1, $zid2 ] );
    noerrok($res);

    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    noerrok($zone1);
    ok( $zone1->get('nt_group_id') =~ $gid2 );

    $zone2 = $user->get_zone( nt_zone_id => $zid2 );
    noerrok($zone2);
    ok( $zone2->get('nt_group_id') =~ $gid2 );
}

sub test_delete_zones {

    my $res = $user->delete_zones( zone_list => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $user->delete_zones( zone_list => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $user->delete_zones( zone_list => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'zone_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
}
