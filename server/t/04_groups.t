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

eval { &do_tests };
warn $@ if $@;

# delete objects even if other tests bail
eval { &delete_test_groups };
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

    if ( defined $gid3 ) {
        $res = $user->delete_group( nt_group_id => $gid3 );
        noerrok($res);
    }
    else {
        ok(0);
    }
    if ( defined $gid1 ) {
        $res = $user->delete_group( nt_group_id => $gid1 );
        noerrok($res);
    }
    else {
        ok(0);
    }
    if ( defined $gid2 ) {
        $res = $user->delete_group( nt_group_id => $gid2 );
        noerrok($res);
    }
    else {
        ok(0);
    }
}

sub test_group_new {

    #no name
    $res = $user->new_group;
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'name' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

    # nt_group_id empty
    $res = $user->new_group( name => 'test_delete_me1', nt_group_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

    # nt_group_id not integer
    $res = $user->new_group( name => 'test_delete_me1', nt_group_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

    # nt_group_id invalid
    $res = $user->new_group( name => 'test_delete_me1', nt_group_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

    for ( qw{~ ` ! $ % ^ & * ( ) + = [ ] \ / | ? > < " : ;},
        ',', '#', "\n", '{', '}' )
    {
        # invalid character in group name
        $res = $user->new_group( name => "test${_}delete" );
        noerrok( $res, 300 );
        if ($res->get('error_code') ne 300) {
            warn "character $_ should be invalid";
        }

        ok( $res->get('error_msg') =~
                qr/Group name contains an invalid character/, "new_group: $_");

        ok( $res->get('error_desc') =~ qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_group(nt_group_id => $res->get('nt_group_id') );
        }
    }

    for (qw(t te)) {

        # group name too small
        $res = $user->new_group( name => $_ );
        noerrok( $res, 300 );
        ok( $res->get('error_msg') =~
                qr/Group name must be at least 3 characters/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
        $res->is_error or do {
            $res = $user->delete_group(nt_group_id => $res->get('nt_group_id'));
        }
    }

    for ( ' test', qw(-test _test 'test .test @test) ) {

        # group name too small
        $res = $user->new_group( name => $_ );
        noerrok( $res, 300 );
        warn "name $_ should be invalid" if $res->get('error_code') ne 300;
        ok( $res->get('error_msg') =~
                qr/Group name must start with a letter or number/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_group(
                nt_group_id => $res->get('nt_group_id') );
        }
    }

    ####################
    # make test groups #
    ####################

    $res = $user->new_group( name => 'test_delete_me1' );
    noerrok($res) or die "Couldn't create test group1";
    ok( $res->get('nt_group_id') =~ qr/^\d+$/ )
        or die "Couldn't create test group1";
    $gid1 = $res->get('nt_group_id');

    $res = $user->new_group( name => 'test_delete_me2' );
    noerrok($res) or die "Couldn't create test group2";
    ok( $res->get('nt_group_id') => qr/^\d+$/ )
        or die "Couldn't create test group2";
    $gid2 = $res->get('nt_group_id');

    ####################
    # test duplicate name
    ####################

    $res = $user->new_group( name => 'test_delete_me1' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Group name is already taken at this level/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }
}

sub test_get_group {

    # nt_group_id empty
    $group1 = $user->get_group( nt_group_id => '' );
    noerrok( $group1, 301 );
    is( $group1->get('error_msg'), 'nt_group_id' );
    ok( $group1->get('error_desc') =~ qr/Required parameters missing/ );

    # nt_group_id not valid integer
    $group1 = $user->get_group( nt_group_id => 'abc' );
    noerrok( $group1, 302 );
    is( $group1->get('error_msg'), 'nt_group_id' );
    ok( $group1->get('error_desc') =~ qr/Some parameters were invalid/ );

    #no nt_group_id
    $group1 = $user->get_group( nt_group_id => 0 );      # not valid id
    noerrok( $group1, 302 );
    is( $group1->get('error_msg'), 'nt_group_id' );
    ok( $group1->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test group   #
    ####################

    $group1 = $user->get_group( nt_group_id => $gid1 );
    noerrok($group1) or die "Couldn't get test group1";
    is( $group1->id, $gid1 ) or die "Couldn't get test group1";
    is( $group1->get('name'), 'test_delete_me1' );
    is( $group1->get('parent_group_id'), $user->get('nt_group_id') );
}

sub test_group_get_fn {
    my $fn = "get_group_" . shift;

    # nt_group_id empty
    $res = $user->$fn( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # nt_group_id not integer
    $res = $user->$fn( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # nt_group_id invalid
    $res = $user->$fn( nt_group_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

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

    # nt_group_id empty
    $res = $user->get_group_branch( nt_group_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # nt_group_id not integer
    $res = $user->get_group_branch( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # nt_group_id not valid
    $res = $user->get_group_branch( nt_group_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get groups of user's group, should contain the 2 test groups
    ####################
    $res = $group1->get_group_branch;
    noerrok($res);
    is( ref $res, 'NicTool::List' );
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

    #no group id
    $res = $group1->edit_group( nt_group_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    #no group id
    $res = $group1->edit_group( nt_group_id => 'abc' );    #not an integer
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    #no group id
    $res = $group1->edit_group( nt_group_id => 0 );      #not valid id
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    for ( qw{~ ` ! $ % ^ & * ( ) + = [ ] \ / | ? > < " : ;},
        ',', '#', "\n", '{', '}' )
    {

        #invalid character in group name
        $res = $group1->edit_group( name => "test${_}delete" );
        noerrok( $res, 300 );
        warn "character $_ should be invalid" if $res->get('error_code') ne 300;
        ok( $res->get('error_msg') =~
                qr/Group name contains an invalid character/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
    }

    for (qw(t te)) {

        #group name too small
        $res = $group1->edit_group( name => $_ );
        noerrok( $res, 300 );
        ok( $res->get('error_msg') =~
                qr/Group name must be at least 3 characters/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
    }

    for ( ' test', qw(-test _test 'test .test @test) ) {

        #group name starts with incorrect char
        $res = $group1->edit_group( name => $_ );
        noerrok( $res, 300 );
        ok( $res->get('error_msg') =~
                qr/Group name must start with a letter or number/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
    }

    #group name already taken
    $res = $group1->edit_group( name => 'test_delete_me2' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Group name is already taken at this level/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    ####################
    # edit test group  #
    ####################

    $res = $group1->edit_group( name => 'test_delete_me_again' );
    noerrok($res);

    $g1 = $user->get_group( nt_group_id => $gid1 );
    noerrok($g1);
    is( $g1->get('name'), 'test_delete_me_again' );
    is( $g1->get('parent_group_id'), $user->get('nt_group_id') );
    is( $g1->id, $gid1 );
}

sub test_group_delete {

    # no group id
    $res = $user->delete_group( nt_group_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # group id not integer
    $res = $user->delete_group( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # group id invalid
    $res = $user->delete_group( nt_group_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # make new subgroup, try to delete parent group
    $res = $group1->new_group( name => 'test_delete_me3' );
    noerrok($res);
    $gid3 = $res->get('nt_group_id');

    $res = $group1->delete_group;
    noerrok( $res, 600 );
    ok( $res->get('error_msg'),
        qr/You can't delete this group until you delete all of its sub-groups/
    );
}
