use strict;

# use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicToolServer::Import::Base;
# use NicTool;
use Test;

BEGIN { plan tests => 25 }


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
die "Couldn't log in" unless noerrok( $user->result );
die "Couldn't log in" unless ok( $user->nt_user_session );

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

sub doit {

    ####################
    # setup            #
    ####################

    #make a new group
    $res = $user->get_group->new_group( name => 'test_reverse' );
    die "Couldn't create test group"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');


    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

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
    die "couldn't make test zone $rzone"
        unless noerrok($res)
            and ok( $res->get('nt_zone_id') => qr/^\d+$/ );
    $zid1 = $res->get('nt_zone_id');

    ####################
    # get test zone    #
    ####################

    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    die "Couldn't get test zone $zid1 : " . errtext($zone1)
        unless noerrok($zone1)
            and ok( $zone1->id, $zid1 );
    for (
        qw(zone serial ttl description mailaddr refresh retry expire minimum))
    {
        ok( $zone1->get($_) => $z1{$_} );
    }


    $res = $group1->get_group_zones;
    noerrok($res);
    ok( ref $res   => 'NicTool::List' );
    ok( $res->size => 1 );


    my (@r) = $base->get_zone_id($rzone);
    warn @r;
    ok($r[0]);
}

sub del {

    ####################
    # cleanup support objects
    ####################

    if ( defined $zid1 ) {
        $res = $user->delete_zones( zone_list => $zid1 );
        unless ( noerrok($res) ) {
            warn Data::Dumper::Dumper($res);
        }
    }
    else {
        ok( 1, 0, "Couldn't delete test zone 1" );
    }

    if ( defined $gid1 ) {
        $res = $user->delete_group( nt_group_id => $gid1 );
        noerrok($res);
    }
}

