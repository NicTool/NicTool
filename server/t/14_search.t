
=head1 PLAN

 create a group, nameserver, zone and record
 sort and search each list call on every field the client offers for it
 delete the objects

=cut

use strict;
use warnings;

use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test::More 'no_plan';

my ( $gid, $group, $dgid, $nsid, $zid, $zone );

my $user = nt_api_connect();

eval { object_tests(); };
warn $@ if $@;

eval { cleanup(); };
warn $@ if $@;

done_testing();
exit;

sub object_tests {
    my $res = $user->get_group->new_group( name => 'test_delete_me_search' );
    noerrok($res) or die "Couldn't create test group";
    $gid   = $res->get('nt_group_id');
    $group = $user->get_group( nt_group_id => $gid );

    $res = $group->new_nameserver(
        name          => 'ns.search.example.com.',
        address       => '1.2.3.4',
        export_format => 'bind',
        ttl           => 86400
    );
    noerrok($res) or die "Couldn't create test nameserver";
    $nsid = $res->get('nt_nameserver_id');

    $res = $group->new_zone( zone => 'search-test.com', nameservers => $nsid, description => 'test delete me' );
    noerrok($res) or die "Couldn't create test zone";
    $zid  = $res->get('nt_zone_id');
    $zone = $user->get_zone( nt_zone_id => $zid );

    $res = $zone->new_zone_record( name => 'www', address => '1.2.3.4', type => 'A', ttl => 300 );
    noerrok($res) or die "Couldn't create test record";

    my $top = $user->get_group;

    # the columns each client page offers to sort and search on
    fields_ok( $top, 'get_group_subgroups', { start_group_id => $top->id, include_subgroups => 1 },
        qw/ group sub_groups / );
    fields_ok( $top, 'get_global_application_log', { include_subgroups => 1 },
        qw/ timestamp group_name user action object title description / );
    fields_ok( $user, 'get_user_global_log', {},
        qw/ timestamp action object title target description / );
    fields_ok( $top, 'get_group_users', { include_subgroups => 1 },
        qw/ group_name username first_name last_name email / );
    fields_ok( $group, 'get_group_users', {}, qw/ group_name username / );
    fields_ok( $top, 'get_group_nameservers', { include_subgroups => 1 },
        qw/ group_name name description address status / );
    fields_ok( $group, 'get_group_nameservers', {}, qw/ name description address status / );
    fields_ok( $top, 'get_group_zones', { include_subgroups => 1 }, qw/ zone group_name description / );
    fields_ok( $group, 'get_group_zones', {}, qw/ zone description / );
    fields_ok( $zone, 'get_zone_records', {},
        qw/ name type address ttl weight priority other description / );
    fields_ok( $zone, 'get_zone_record_log', {},
        qw/ timestamp user action name type address ttl weight description / );

    $res = $top->get_group_nameservers( include_subgroups => 1, quick_search => 1,
        search_value => 'ns.search.example.com.', exact_match => 1 );
    noerrok($res);
    is( $res->get('total'), 1, 'quick search finds the nameserver by name' );

    $res = $top->get_group_zones( include_subgroups => 1, Search => 1,
        '1_field' => 'group_name', '1_option' => 'equals', '1_value' => 'test_delete_me_search' );
    noerrok($res);
    is( $res->get('total'), 1, 'zones search on group_name finds the zone' );

    $res = $zone->get_zone_record_log( Search => 1,
        '1_field' => 'type', '1_option' => 'equals', '1_value' => 'A' );
    noerrok($res);
    ok( $res->get('total') >= 1, 'record log search on type finds the record' );

    $res = $user->get_group->new_group( name => 'test_delete_me_delegate' );
    noerrok($res) or die "Couldn't create delegate group";
    $dgid = $res->get('nt_group_id');
    noerrok( $user->delegate_zones( zone_list => $zid, nt_group_id => $dgid ) );

    $res = $user->get_user_global_log( Search => 1,
        '1_field' => 'target', '1_option' => 'equals', '1_value' => 'test_delete_me_delegate' );
    noerrok($res);
    ok( $res->get('total') >= 1, 'global log search on target finds the delegate group' );

    $res = $user->get_user_global_log( Search => 1,
        '1_field' => 'timestamp', '1_option' => '>', '1_value' => '2001-01-01' );
    noerrok($res);
    ok( $res->get('total') >= 1, 'global log search on a time range' );
}

sub fields_ok {
    my ( $obj, $method, $args, @fields ) = @_;
    for my $field (@fields) {
        my $res = $obj->$method( %$args, Sort => 1, '1_sortfield' => $field, '1_sortmod' => 'Ascending' );
        noerrok( $res, 200, "$method sort on $field" );

        $res = $obj->$method( %$args, Search => 1,
            '1_field' => $field, '1_option' => 'equals', '1_value' => '1' );
        noerrok( $res, 200, "$method search on $field" );
    }
}

sub cleanup {
    noerrok( $user->delete_zone_delegation( nt_zone_id => $zid, nt_group_id => $dgid ) )
        if defined $zid && defined $dgid;
    noerrok( $user->delete_zones( zone_list => $zid ) )             if defined $zid;
    noerrok( $user->delete_nameserver( nt_nameserver_id => $nsid ) ) if defined $nsid;
    noerrok( $user->delete_group( nt_group_id => $gid ) )           if defined $gid;
    noerrok( $user->delete_group( nt_group_id => $dgid ) )          if defined $dgid;
}
