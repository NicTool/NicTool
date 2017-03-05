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

 create 2 groups for support
 create new users inside the groups
 test all the user related API calls
 delete the users
 delete the groups

=head1 TODO

 get_user_global_log
 search params on get_group_users,get_user_global_log

=cut

use strict;
use warnings;

use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test::More 'no_plan';

my $nt_obj = nt_api_connect();

my ($uid1, $uid2, $gid1, $gid2, $user1, $user2, $group1, $group2);
my (%username, %first_name, %last_name, %email);

eval {&do_the_tests};
warn $@ if $@;

#delete objects even if other tests bail
eval {&del};
warn $@ if $@;

done_testing();
exit;

sub do_the_tests {

    ####################
    # setup            #
    ####################

    test_new_group();
    test_new_user();
    test_get_user();
    test_edit_user();

    ####################
    # use data later   #
    ####################

    %username   = ( $uid1 => 'testuser1',       $uid2 => 'testuser2' );
    %first_name = ( $uid1 => 'name1',           $uid2 => 'name2' );
    %last_name  = ( $uid1 => '1name',           $uid2 => '2name' );
    %email      = ( $uid1 => 'test1@blah.blah', $uid2 => 'test2@blah.blah' );

    test_get_group_users();
    test_move_users();
    test_get_user_list();

    ####################
    # get_user_global_log
    ####################
    #       TODO       #
    ####################

    test_delete_users();
}

sub del {

    ####################
    # delete test users#
    ####################
    if ( defined $uid1 and defined $uid2 ) {

        #delete_users
        my $res = $nt_obj->delete_users( user_list => "$uid1,$uid2" );

        #verify
        noerrok($res);
        $res = $nt_obj->get_user( nt_user_id => $uid1 );
        noerrok($res);
        ok( $res->get('deleted') );
        $res = $nt_obj->get_user( nt_user_id => $uid2 );
        noerrok($res);
        ok( $res->get('deleted') );
    }

    ####################
    # delete support groups
    ####################
    if ( defined $gid1 and defined $gid2 ) {
        my $res = $nt_obj->delete_group( nt_group_id => $gid1 );
        noerrok($res);
        $res = $nt_obj->delete_group( nt_group_id => $gid2 );
        noerrok($res);
    }
}

sub test_new_group {

    # make a new group
    my $res = $nt_obj->get_group->new_group( name => 'test_delete_me1' );
    noerrok($res) && ok( $res->get('nt_group_id') =~ qr/^\d+$/ )
        or die "Couldn't create test group1";

    $gid1 = $res->get('nt_group_id');
    $group1 = $nt_obj->get_group( nt_group_id => $gid1 );
    noerrok($group1) && is( $group1->id, $gid1 )
        or die "Couldn't get test group1";

    # make a second group
    $res = $nt_obj->get_group->new_group( name => 'test_delete_me2' );
    noerrok($res) && ok( $res->get('nt_group_id') =~ qr/^\d+$/ )
        or die "Couldn't create test group2";
    $gid2 = $res->get('nt_group_id');
    $group2 = $nt_obj->get_group( nt_group_id => $gid2 );
    noerrok($group2) && is( $group2->id, $gid2 )
        or die "Couldn't get test group2";
}

sub test_new_user {

    #no password2
    my $res = $group1->new_user(
        username => 'blah',
        email    => 'blah@blah.com',
        password => 'something'
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'password2' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #no password
    $res = $group1->new_user(
        username  => 'blah',
        email     => 'blah@blah.com',
        password2 => 'something'
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'password' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #no username
    $res = $group1->new_user(
        email     => 'blah@blah.com',
        password  => 'something',
        password2 => 'something'
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'username' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #no email
    $res = $group1->new_user(
        username  => 'blah',
        password  => 'something',
        password2 => 'something'
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'email' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #no nt_group_id
    $res = $group1->new_user(
        nt_group_id => '',
        username    => 'blah',
        email       => 'blah@blah.com',
        password    => 'something',
        password2   => 'something'
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #nt_group_id not integer
    $res = $group1->new_user(
        nt_group_id => 'abc',
        username    => 'blah',
        email       => 'blah@blah.com',
        password    => 'something',
        password2   => 'something'
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #nt_group_id invalid id
    $res = $group1->new_user(
        nt_group_id => 0,
        username    => 'blah',
        email       => 'blah@blah.com',
        password    => 'something',
        password2   => 'something'
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #invalid email address
    $res = $group1->new_user(
        username  => 'blah',
        email     => 'blah.blah.com',
        password  => 'something',
        password2 => 'something'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg')  =~ qr/must be a valid email address/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    # username too small
    for (qw(b bl)) {
        $res = $group1->new_user(
            username  => $_,
            email     => 'blah@blah.com',
            password  => 'something',
            password2 => 'something'
        );
        noerrok( $res, 300 );
        ok( $res->get('error_msg') =~ qr/at least 3 characters/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
        }
    }

    for ( qw{~ ` ! @ $ % ^ & * ( ) + = [ ] \ / | ? > < " ' : ;},
        ',', '#', "\n", '{', '}' )
    {
        # username contains incorrect character
        $res = $group1->new_user(
            username  => 'bl${_}ah',
            email     => 'blah@blah.com',
            password  => 'something',
            password2 => 'something'
        );
        noerrok( $res, 300 );
        warn "character $_ should be invalid"
            unless $res->get('error_code') eq 300;
        ok( $res->get('error_msg') =~
                qr/Username contains an invalid character/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
        }
    }

    #password too small
    $res = $group1->new_user(
        username  => 'blah',
        email     => 'blah@blah.com',
        password  => '123',
        password2 => '123'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Password too short, must be 8-30 characters long./ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #mismatched passwords
    $res = $group1->new_user(
        username  => 'blah',
        email     => 'blah@blah.com',
        password  => 'something',
        password2 => 'somethingelse'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg')  =~ qr/Passwords must match/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    ####################
    # create test users#
    ####################

    #new_user 1
    $res = $group1->new_user(
        first_name => 'test',
        last_name  => '1',
        email      => 'test@blah.blah',
        username   => 'testuser1',
        password   => 'testpass',
        password2  => 'testpass'
    );
    noerrok($res) && ok( $res->get('nt_user_id') =~ qr/^\d+$/ )
        or die "couldn't make test user1";
    $uid1 = $res->get('nt_user_id');

    #new_user 2
    $res = $group1->new_user(
        first_name => 'test',
        last_name  => '2',
        email      => 'test@blah.blah',
        username   => 'testuser2',
        password   => 'testpass',
        password2  => 'testpass'
    );
    noerrok($res) && ok( $res->get('nt_user_id') =~ qr/^\d+$/ )
        or die "couldn't make test user2";
    $uid2 = $res->get('nt_user_id');


    ####################
    # tests for non unique username
    ####################

    #username already taken
    $res = $group1->new_user(
        username  => 'testuser1',
        email     => 'blah@blah.com',
        password  => 'something',
        password2 => 'something'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/is not unique. Please choose a different username/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }
}

sub test_get_user {

    #nt_user_id missing
    my $res = $nt_obj->get_user( nt_user_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_user_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    #nt_user_id not integer
    $res = $nt_obj->get_user( nt_user_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_user_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    #nt_user_id not valid id
    $res = $nt_obj->get_user( nt_user_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_user_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test users   #
    ####################

    #get_user 1
    $user1 = $nt_obj->get_user( nt_user_id => $uid1 );
    noerrok($user1) && is( $user1->id, $uid1 ) or die "Couldn't get test user1";
    is( $user1->get('username'), 'testuser1' );

    #get_user 2
    $user2 = $nt_obj->get_user( nt_user_id => $uid2 );
    noerrok($user2) && is( $user2->id, $uid2 ) or die "Couldn't get test user1";
    is( $user2->get('username'), 'testuser2' );
}

sub test_edit_user {

    ####################
    # edit_user        #
    ####################

    #no user id
    my $res = $user1->edit_user( nt_user_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_user_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    #user id not integer
    $res = $user1->edit_user( nt_user_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_user_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    #user id not valid id
    $res = $user1->edit_user( nt_user_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_user_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    #username too small
    $res = $user1->edit_user( username => 'bl' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Username must be at least 3 characters/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #username too small
    $res = $user1->edit_user( username => 'l' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Username must be at least 3 characters/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #username too small
    $res = $user1->edit_user( username => '' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Username must be at least 3 characters/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    for ( qw{~ ` ! @ $ % ^ & * ( ) + = [ ] \ / | ? > < " : ;},
        ',', '#', "\n", '{', '}' )
    {
        #username has invalid char
        $res = $user1->edit_user( username => "bl${_}ah" );
        noerrok( $res, 300 );
        $res->get('error_code') eq 300 or warn "character $_ should be invalid";
        ok( $res->get('error_msg') =~
                qr/Username contains an invalid character/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
    }

    #change password no old password
    $res = $user1->edit_user( password => 'another', password2 => 'another' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~ qr/Current password/, "edit_user, no previous" );
    ok( $res->get('error_desc') =~ qr/Sanity error/, "edit_user" );

    #change password bad old password
    $res = $user1->edit_user(
        password_current => 'wrong',
        password         => 'another',
        password2        => 'another'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~ qr/Current password/, "edit_user, wrong" );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #change password blank old password
    $res = $user1->edit_user(
        password_current => '',
        password         => 'another',
        password2        => 'another'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~ qr/Current password/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #change password too small
    $res = $user1->edit_user(
        password_current => 'something',
        password         => 'ano',
        password2        => 'ano'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~ qr/too short/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #change password mismatched
    $res = $user1->edit_user(
        password_current => 'something',
        password         => 'another',
        password2        => 'other'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg')  =~ qr/must match/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #username already taken
    $res = $user1->edit_user( username => 'testuser2' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/is not unique. Please choose a different username/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    ####################
    # edit test users  #
    ####################
    $res = $user1->edit_user(
        first_name => 'name1',
        last_name  => '1name',
        email      => 'test1@blah.blah'
    );
    noerrok($res);

    is( $res->get('nt_user_id'), $uid1 );

    $res = $nt_obj->get_user( 'nt_user_id' => $uid1 );
    noerrok($res);
    is( $res->get('first_name'), 'name1' );
    is( $res->get('last_name') , '1name' );
    is( $res->get('email')     , 'test1@blah.blah' );

    #edit_user 2
    $res = $user2->edit_user(
        first_name => 'name2',
        last_name  => '2name',
        email      => 'test2@blah.blah'
    );
    noerrok($res);
    is( $res->get('nt_user_id'), $uid2 );

    $res = $nt_obj->get_user( 'nt_user_id' => $uid2 );
    noerrok($res);
    is( $res->get('first_name'), 'name2' );
    is( $res->get('last_name') , '2name' );
    is( $res->get('email')     , 'test2@blah.blah' );

    # test changing of password
    my $tuser = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );
    is( ref $nt_obj, 'NicTool' ) or die "Couldn't create NicTool Object";

    $tuser->login(
        username => 'testuser2@test_delete_me1',
        password => 'testpass',
    );
    noerrok( $tuser->result );
    ok( $tuser->nt_user_session );

    noerrok( $tuser->logout );

    #edit_user 2
    $res = $user2->edit_user(
        username         => 'testuser2',
        current_password => 'testpass',
        password         => 'testpass2',
        password2        => 'testpass2'
    );
    noerrok($res);

    $tuser->login(
        username => 'testuser2@test_delete_me1',
        password => 'testpass2',
    );
    ok( !$tuser->result->is_error );
    ok( $tuser->nt_user_session );

    if ( ! $tuser->result->is_error ) {
        noerrok( $tuser->logout );
    };
}

sub test_get_group_users {

    #nt_group_id missing
    my $res = $group1->get_group_users( nt_group_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    #nt_group_id not integer
    $res = $group1->get_group_users( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    #nt_group_id not valid id
    $res = $group1->get_group_users( nt_group_id => 0 );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get from test group
    ####################

    $res = $group1->get_group_users;
    noerrok($res);
    is( ref $res, 'NicTool::List' );
    is( $res->size, 2 );
    if ( $res->size == 2 ) {
        my @u = $res->list;
        is( $u[0]->get('username')  , $username{ $u[0]->id } );
        is( $u[1]->get('username')  , $username{ $u[1]->id } );
        is( $u[0]->get('first_name'), $first_name{ $u[0]->id } );
        is( $u[1]->get('first_name'), $first_name{ $u[1]->id } );
        is( $u[0]->get('last_name') , $last_name{ $u[0]->id } );
        is( $u[1]->get('last_name') , $last_name{ $u[1]->id } );
        is( $u[0]->get('email')     , $email{ $u[0]->id } );
        is( $u[1]->get('email')     , $email{ $u[1]->id } );
    }
}

sub test_move_users {

    # missing user_list
    my $res = $group2->move_users( user_list => "" );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # user_list invalid
    $res = $group2->move_users( user_list => "abc,def" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # user_list invalid id
    $res = $group2->move_users( user_list => "0" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # nt_group_id missing
    $res = $group2->move_users( nt_group_id => '', user_list => "$uid1,$uid2" );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # nt_group_id not valid integer
    $res = $group2->move_users(
        nt_group_id => 'abc',
        user_list   => "$uid1,$uid2"
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # nt_group_id not valid
    $res = $group2->move_users( nt_group_id => 0,
        user_list => "$uid1,$uid2" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );


    $res = $group2->move_users( user_list => "$uid1,$uid2" );
    noerrok($res);

    $user1 = $nt_obj->get_user( nt_user_id => $uid1 );
    noerrok($user1);
    is( $user1->get('nt_group_id'), $gid2 );

    $user2 = $nt_obj->get_user( nt_user_id => $uid2 );
    noerrok($user2);
    is( $user2->get('nt_group_id'), $gid2 );

    $res = $group2->get_group_users;
    noerrok($res);
    is( ref $res, 'NicTool::List' );
    is( $res->size, 2 );
    if ( $res->size == 2 ) {
        my @u = $res->list;
        is( $u[0]->get('username')  , $username{ $u[0]->id } );
        is( $u[1]->get('username')  , $username{ $u[1]->id } );
        is( $u[0]->get('first_name'), $first_name{ $u[0]->id } );
        is( $u[1]->get('first_name'), $first_name{ $u[1]->id } );
        is( $u[0]->get('last_name') , $last_name{ $u[0]->id } );
        is( $u[1]->get('last_name') , $last_name{ $u[1]->id } );
        is( $u[0]->get('email')     , $email{ $u[0]->id } );
        is( $u[1]->get('email')     , $email{ $u[1]->id } );
    }
}

sub test_get_user_list {

    #user_list missing
    my $res = $nt_obj->get_user_list( user_list => "" );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    #user_list not integer
    $res = $nt_obj->get_user_list( user_list => "abc" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    #user_list not valid id
    $res = $nt_obj->get_user_list( user_list => "0" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test users   #
    ####################

    $res = $nt_obj->get_user_list( user_list => "$uid1,$uid2" );
    noerrok($res);
    is( ref $res, 'NicTool::List' );
    is( $res->size, 2 );
    if ( $res->size == 2 ) {
        my @u = $res->list;
        is( $u[0]->get('username')  , $username{ $u[0]->id } );
        is( $u[1]->get('username')  , $username{ $u[1]->id } );
        is( $u[0]->get('first_name'), $first_name{ $u[0]->id } );
        is( $u[1]->get('first_name'), $first_name{ $u[1]->id } );
        is( $u[0]->get('last_name') , $last_name{ $u[0]->id } );
        is( $u[1]->get('last_name') , $last_name{ $u[1]->id } );
        is( $u[0]->get('email')     , $email{ $u[0]->id } );
        is( $u[1]->get('email')     , $email{ $u[1]->id } );
    }

    #user 1
    $res = $nt_obj->get_user_list( user_list => "$uid1" );
    noerrok($res);
    is( ref $res, 'NicTool::List' );
    is( $res->size, 1 );
    if ( $res->size == 1 ) {
        my @u = $res->list;
        is( $u[0]->id, $uid1 );
        is( $u[0]->get('username')  , $username{$uid1} );
        is( $u[0]->get('first_name'), $first_name{$uid1} );
        is( $u[0]->get('last_name') , $last_name{$uid1} );
        is( $u[0]->get('email')     , $email{$uid1} );
    }

    #user 2
    $res = $nt_obj->get_user_list( user_list => "$uid2" );
    noerrok($res);
    is( ref $res, 'NicTool::List' );
    is( $res->size, 1 );
    if ( $res->size == 1 ) {
        my @u = $res->list;
        is( $u[0]->id, $uid2 );
        is( $u[0]->get('username')  , $username{$uid2} );
        is( $u[0]->get('first_name'), $first_name{$uid2} );
        is( $u[0]->get('last_name') , $last_name{$uid2} );
        is( $u[0]->get('email')     , $email{$uid2} );
    }
}

sub test_delete_users {

    # user list missing
    my $res = $nt_obj->delete_users( user_list => "" );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # user list not integer
    $res = $nt_obj->delete_users( user_list => "abc" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # user list invalid id
    $res = $nt_obj->delete_users( user_list => "0" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'user_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
}
