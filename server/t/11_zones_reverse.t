use strict;

# use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicToolServer::Import::Base;
# use NicTool;
use Test::More;


my $user = nt_api_connect();

my $base = new NicToolServer::Import::Base;
$base->nt_connect(
    Config('server_host'),
    Config('server_port'),
    Config('username'),
    Config('password'));

my $rzone = 'e.3.2.0.0.3.4.0.1.0.a.2.ip6.arpa';

#try to do the tests
eval {&doit};
warn $@ if $@;

#delete objects even if other tests bail
eval {&del};
warn $@ if $@;

my ($res, $gid1, $group1, %z1, $zid1, $zone1);

done_testing();
exit;

sub doit {

    ####################
    # setup            #
    ####################

    #make a new group
    $res = $user->get_group->new_group( name => 'test_reverse' );
    noerrok($res)
        && ok( $res->get('nt_group_id') => qr/^\d+$/ ) or
            die "Couldn't create test group";
    $gid1 = $res->get('nt_group_id');


    $group1 = $user->get_group( nt_group_id => $gid1 );
    noerrok($group1)
        && is( $group1->id, $gid1 ) or
            die "Couldn't get test group1";

    %z1 = (
        zone        => $rzone,
        serial      => 1,
        ttl         => 86402,
        nameservers => "",
        description => "test delete me",
        mailaddr    => "somebody.example.com",
        refresh     => 101,
        retry       => 201,
        expire      => 301,
        minimum     => 401,
    );
    $res = $group1->new_zone(%z1);
    noerrok($res)
        && ok( $res->get('nt_zone_id') => qr/^\d+$/ ) or
            die "couldn't make test zone $rzone";
    $zid1 = $res->get('nt_zone_id');

    ####################
    # get test zone    #
    ####################

    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    noerrok($zone1)
        && is( $zone1->id, $zid1 ) or
            die "Couldn't get test zone $zid1 : " . errtext($zone1);

    for (
        qw(zone serial ttl description mailaddr refresh retry expire minimum))
    {
        is( $zone1->get($_), $z1{$_} );
    }


    $res = $group1->get_group_zones;
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 1 );


    my (@r) = $base->get_zone_id($rzone);
    #warn @r;
    ok($r[0]);
}

sub del {

    ####################
    # cleanup support objects
    ####################

    if ( defined $zid1 ) {
        $res = $user->delete_zones( zone_list => $zid1 );
        noerrok($res) or warn Data::Dumper::Dumper($res);
    }
    else {
        is( 1, 0, "Couldn't delete test zone 1" );
    }

    if ( defined $gid1 ) {
        $res = $user->delete_group( nt_group_id => $gid1 );
        noerrok($res);
    }
}

