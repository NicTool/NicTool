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

=head1 TODO

 get_global_application_log
 search params for get_group_subgroups,get_global_application_log

=cut

use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test::More 'no_plan';

my $user = nt_api_connect();

eval {&do_tests};
warn $@ if $@;

# delete objects even if other tests bail
eval {&delete_test_groups};
warn $@ if $@;

sub do_tests {

    test_group_new();    # create 2 groups
    test_get_group();
    test_group_get_fn('subgroups');
    test_group_get_fn('groups');
    test_group_get_branch();
    test_group_edit();
    test_group_delete();    # delete the test groups
}

sub delete_test_groups {

    for my $gid ( $gid3, $gid1, $gid2 ) {
        if ( defined $gid ) {
            $res = $user->delete_group( nt_group_id => $gid );
            noerrok($res);
        }
        else {
            ok(0);
        }
    }
}

sub test_group_new {

    bad_id_ok(
        'nt_group_id',
        sub {
            my $res = $user->new_group( name => 'test_delete_me1', nt_group_id => shift );
            $user->delete_group( nt_group_id => $res->get('nt_group_id') ) if !$res->is_error;
            return $res;
        }
    );

    ####################
    # make test groups #
    ####################

    $gid1 = new_id_ok( $user->new_group( name => 'test_delete_me1' ),
        'nt_group_id', "Couldn't create test group1" );

    $res = $user->new_group( name => 'test_delete_me2' );
    noerrok($res) or die "Couldn't create test group2";
    ok( $res->get('nt_group_id') => qr/^\d+$/ )
        or die "Couldn't create test group2";
    $gid2 = $res->get('nt_group_id');

    ####################
    # test duplicate name
    ####################

    $res = $user->new_group( name => 'test_delete_me1' );
    sanity_error_ok( $res, qr/Group name is already taken at this level/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }
}

sub test_get_group {

    bad_id_ok( 'nt_group_id', sub { $user->get_group( nt_group_id => shift ) } );

    ####################
    # get test group   #
    ####################

    $group1 =
        fetched_ok( $user->get_group( nt_group_id => $gid1 ), $gid1, "Couldn't get test group1" );
    is( $group1->get('name'),            'test_delete_me1' );
    is( $group1->get('parent_group_id'), $user->get('nt_group_id') );
}

sub test_group_get_fn {
    my $fn = "get_group_" . shift;

    # nt_group_id empty
    $res = $user->$fn( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    bad_id_ok( 'nt_group_id', sub { $user->$fn( nt_group_id => shift ) }, 'abc', 0 );

    ####################
    # get groups of user's group, should contain the 2 test groups
    ####################
    $res = $user->$fn;
    noerrok($res);
    is( ref $res, 'NicTool::List' );
    ok( $res->size >= 2 );
    $saw1 = 0;
    $saw2 = 0;
    if ( $res->size >= 2 ) {

        while ( my $g = $res->next ) {
            if ( $g->get('nt_group_id') eq $gid1 ) {
                $saw1 = 1;
            }
            if ( $g->get('nt_group_id') eq $gid2 ) {
                $saw2 = 1;
            }
        }
    }
    ok($saw1);
    ok($saw2);
}

sub test_group_get_branch {

    bad_id_ok( 'nt_group_id', sub { $user->get_group_branch( nt_group_id => shift ) } );

    ####################
    # get groups of user's group, should contain the 2 test groups
    ####################
    $res = $group1->get_group_branch;
    noerrok($res);
    is( ref $res,   'NicTool::List' );
    is( $res->size, 2 );
    $saw1 = 0;
    $saw2 = 0;
    if ( $res->size == 2 ) {
        $g = $res->next;
        if ( $g->get('nt_group_id') eq $user->get('nt_group_id') ) {
            $saw1 = 1;
        }
        $g = $res->next;
        if ( $g->get('nt_group_id') eq $gid1 ) {
            $saw2 = 1;
        }
    }
    ok($saw1);
    ok($saw2);
}

sub test_group_edit {

    bad_id_ok( 'nt_group_id', sub { $group1->edit_group( nt_group_id => shift ) } );

    #group name already taken
    $res = $group1->edit_group( name => 'test_delete_me2' );
    sanity_error_ok( $res, qr/Group name is already taken at this level/ );

    ####################
    # edit test group  #
    ####################

    $res = $group1->edit_group( name => 'test_delete_me_again' );
    noerrok($res);

    $g1 = $user->get_group( nt_group_id => $gid1 );
    noerrok($g1);
    is( $g1->get('name'),            'test_delete_me_again' );
    is( $g1->get('parent_group_id'), $user->get('nt_group_id') );
    is( $g1->id,                     $gid1 );
}

sub test_group_delete {

    bad_id_ok( 'nt_group_id', sub { $user->delete_group( nt_group_id => shift ) } );

    # make new subgroup, try to delete parent group
    $res = $group1->new_group( name => 'test_delete_me3' );
    noerrok($res);
    $gid3 = $res->get('nt_group_id');

    $res = $group1->delete_group;
    noerrok( $res, 600 );
    ok( $res->get('error_msg'),
        qr/You can't delete this group until you delete all of its sub-groups/ );
}
