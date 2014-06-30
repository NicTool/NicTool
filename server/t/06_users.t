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
use Test;

BEGIN { plan tests => 408 }

my $nt_obj = new NicTool(
    cache_users  => 0,
    cache_groups => 0,
    server_host  => Config('server_host'),
    server_port  => Config('server_port')
);
die "Couldn't create NicTool Object" unless ok( ref $nt_obj, 'NicTool' );

$nt_obj->login(
    username => Config('username'),
    password => Config('password')
);
die "Couldn't log in" unless ok( !$nt_obj->result->is_error );
die "Couldn't log in" unless ok( $nt_obj->nt_user_session );

#try to do the tests
my ($uid1, $uid2, $gid1, $gid2);
eval {&doit};
warn $@ if $@;

#delete objects even if other tests bail
eval {&del};
warn $@ if $@;

sub doit {

    ####################
    # setup            #
    ####################

    #make a new group
    my $res = $nt_obj->get_group->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );

    $gid1   = $res->get('nt_group_id');
    my $group1 = $nt_obj->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    #make a new group
    $res = $nt_obj->get_group->new_group( name => 'test_delete_me2' );
    die "Couldn't create test group2"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid2   = $res->get('nt_group_id');
    my $group2 = $nt_obj->get_group( nt_group_id => $gid2 );
    die "Couldn't get test group2"
        unless noerrok($group2)
            and ok( $group2->id, $gid2 );

####################
    # new_user         #
####################

    ####################
    # parameters tests #
    ####################

    #no password2
    $res = $group1->new_user(
        username => 'blah',
        email    => 'blah@blah.com',
        password => 'something'
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'password2' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
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
    ok( $res->get('error_msg')  => 'password' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
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
    ok( $res->get('error_msg')  => 'username' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
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
    ok( $res->get('error_msg')  => 'email' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
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
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
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
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );
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
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );
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
    ok( $res->get('error_msg')  => qr/Email must be a valid email address/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

    #username too small
    for (qw(b bl)) {
        $res = $group1->new_user(
            username  => $_,
            email     => 'blah@blah.com',
            password  => 'something',
            password2 => 'something'
        );
        noerrok( $res, 300 );
        ok( $res->get('error_msg') =>
                qr/Username must be at least 3 characters/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
        }
    }

    for ( qw{~ ` ! @ $ % ^ & * ( ) + = [ ] \ / | ? > < " ' : ;},
        ',', '#', "\n", '{', '}' )
    {

        #username contains incorrect character
        $res = $group1->new_user(
            username  => 'bl${_}ah',
            email     => 'blah@blah.com',
            password  => 'something',
            password2 => 'something'
        );
        noerrok( $res, 300 );
        warn "character $_ should be invalid"
            unless $res->get('error_code') eq 300;
        ok( $res->get('error_msg') =>
                qr/Username contains an invalid character/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
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
    ok( $res->get('error_msg') =>
            qr/Password too short, must be 8-30 characters long./ );
    ok( $res->get('error_desc') => qr/Sanity error/ );
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
    ok( $res->get('error_msg')  => qr/Passwords must match/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );
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
    die "couldn't make test user1"
        unless noerrok($res)
            and ok( $res->get('nt_user_id') => qr/^\d+$/ );
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
    die "couldn't make test user2"
        unless noerrok($res)
            and ok( $res->get('nt_user_id') => qr/^\d+$/ );
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
    ok( $res->get('error_msg') =>
            qr/is not unique. Please choose a different username/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $nt_obj->delete_users( user_list => $res->get('nt_user_id') );
    }

####################
    # get_user         #
####################

    ####################
    # parameters tests #
    ####################

    #nt_user_id missing
    $res = $nt_obj->get_user( nt_user_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_user_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #nt_user_id not integer
    $res = $nt_obj->get_user( nt_user_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_user_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #nt_user_id not valid id
    $res = $nt_obj->get_user( nt_user_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_user_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # get test users   #
    ####################
    #get_user 1
    my $user1 = $nt_obj->get_user( nt_user_id => $uid1 );
    die "Couldn't get test user1"
        unless noerrok($user1)
            and ok( $user1->id, $uid1 );
    ok( $user1->get('username') => 'testuser1' );

    #get_user 2
    my $user2 = $nt_obj->get_user( nt_user_id => $uid2 );
    die "Couldn't get test user1"
        unless noerrok($user2)
            and ok( $user2->id, $uid2 );
    ok( $user2->get('username') => 'testuser2' );

####################
    # edit_user        #
####################

    ####################
    # parameters tests #
    ####################

    #no user id
    $res = $user1->edit_user( nt_user_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_user_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #user id not integer
    $res = $user1->edit_user( nt_user_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_user_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #user id not valid id
    $res = $user1->edit_user( nt_user_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_user_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #username too small
    $res = $user1->edit_user( username => 'bl' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =>
            qr/Username must be at least 3 characters/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    #username too small
    $res = $user1->edit_user( username => 'l' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =>
            qr/Username must be at least 3 characters/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    #username too small
    $res = $user1->edit_user( username => '' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =>
            qr/Username must be at least 3 characters/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    for ( qw{~ ` ! @ $ % ^ & * ( ) + = [ ] \ / | ? > < " : ;},
        ',', '#', "\n", '{', '}' )
    {

        #username has invalid char
        $res = $user1->edit_user( username => "bl${_}ah" );
        noerrok( $res, 300 );
        warn "character $_ should be invalid"
            unless $res->get('error_code') eq 300;
        ok( $res->get('error_msg') =>
                qr/Username contains an invalid character/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

    #change password no old password
    $res = $user1->edit_user( password => 'another', password2 => 'another' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') => qr/Current password/, "edit_user, no previous" );
    ok( $res->get('error_desc') => qr/Sanity error/, "edit_user" );

    #change password bad old password
    $res = $user1->edit_user(
        password_current => 'wrong',
        password         => 'another',
        password2        => 'another'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') => qr/Current password/, "edit_user, wrong" );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    #change password blank old password
    $res = $user1->edit_user(
        password_current => '',
        password         => 'another',
        password2        => 'another'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') => qr/Current password/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    #change password too small
    $res = $user1->edit_user(
        password_current => 'something',
        password         => 'ano',
        password2        => 'ano'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') => qr/too short/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    #change password mismatched
    $res = $user1->edit_user(
        password_current => 'something',
        password         => 'another',
        password2        => 'other'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg')  => qr/must match/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    #username already taken
    $res = $user1->edit_user( username => 'testuser2' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =>
            qr/is not unique. Please choose a different username/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    ####################
    # edit test users  #
    ####################
    $res = $user1->edit_user(
        first_name => 'name1',
        last_name  => '1name',
        email      => 'test1@blah.blah'
    );
    noerrok($res);

    ok( $res->get('nt_user_id') => $uid1 );

    $res = $nt_obj->get_user( 'nt_user_id' => $uid1 );
    noerrok($res);
    ok( $res->get('first_name') => 'name1' );
    ok( $res->get('last_name')  => '1name' );
    ok( $res->get('email')      => 'test1@blah.blah' );

    #edit_user 2
    $res = $user2->edit_user(
        first_name => 'name2',
        last_name  => '2name',
        email      => 'test2@blah.blah'
    );
    noerrok($res);
    ok( $res->get('nt_user_id') => $uid2 );

    $res = $nt_obj->get_user( 'nt_user_id' => $uid2 );
    noerrok($res);
    ok( $res->get('first_name') => 'name2' );
    ok( $res->get('last_name')  => '2name' );
    ok( $res->get('email')      => 'test2@blah.blah' );

    #test changing of password

    my $tuser = new NicTool(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => Config('server_host'),
        server_port  => Config('server_port')
    );
    die "Couldn't create NicTool Object" unless ok( ref $nt_obj, 'NicTool' );

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

    if ( ! $tuser->result->is_error ) {
        ok( $tuser->nt_user_session );
        noerrok( $tuser->logout );
    };


    ####################
    # use data later   #
    ####################

    my %username   = ( $uid1 => 'testuser1',       $uid2 => 'testuser2' );
    my %first_name = ( $uid1 => 'name1',           $uid2 => 'name2' );
    my %last_name  = ( $uid1 => '1name',           $uid2 => '2name' );
    my %email      = ( $uid1 => 'test1@blah.blah', $uid2 => 'test2@blah.blah' );

####################
    # get_group_users  #
####################

    ####################
    # parameters tests #
    ####################

    #nt_group_id missing
    $res = $group1->get_group_users( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #nt_group_id not integer
    $res = $group1->get_group_users( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #nt_group_id not valid id
    $res = $group1->get_group_users( nt_group_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # get from test group
    ####################

    $res = $group1->get_group_users;
    noerrok($res);
    ok( ref $res, 'NicTool::List' );
    ok( $res->size => 2 );
    if ( $res->size == 2 ) {
        my @u = $res->list;
        ok( $u[0]->get('username')   => $username{ $u[0]->id } );
        ok( $u[1]->get('username')   => $username{ $u[1]->id } );
        ok( $u[0]->get('first_name') => $first_name{ $u[0]->id } );
        ok( $u[1]->get('first_name') => $first_name{ $u[1]->id } );
        ok( $u[0]->get('last_name')  => $last_name{ $u[0]->id } );
        ok( $u[1]->get('last_name')  => $last_name{ $u[1]->id } );
        ok( $u[0]->get('email')      => $email{ $u[0]->id } );
        ok( $u[1]->get('email')      => $email{ $u[1]->id } );
    }
    else {
        for ( 1 .. 8 ) { ok(0) }
    }

####################
    # move_users       #
####################

    ####################
    # parameters test  #
    ####################

    #missing user_list
    $res = $group2->move_users( user_list => "" );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #user_list invalid
    $res = $group2->move_users( user_list => "abc,def" );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #user_list invalid id
    $res = $group2->move_users( user_list => "0" );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #nt_group_id missing
    $res = $group2->move_users( nt_group_id => '',
        user_list => "$uid1,$uid2" );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #nt_group_id not valid integer
    $res = $group2->move_users(
        nt_group_id => 'abc',
        user_list   => "$uid1,$uid2"
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #nt_group_id not valid
    $res = $group2->move_users( nt_group_id => 0,
        user_list => "$uid1,$uid2" );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # move test  users #
    ####################

    $res = $group2->move_users( user_list => "$uid1,$uid2" );

    noerrok($res);

    $user1 = $nt_obj->get_user( nt_user_id => $uid1 );
    noerrok($user1);
    ok( $user1->get('nt_group_id'), $gid2 );

    $user2 = $nt_obj->get_user( nt_user_id => $uid2 );
    noerrok($user2);
    ok( $user2->get('nt_group_id'), $gid2 );

    $res = $group2->get_group_users;
    noerrok($res);
    ok( ref $res, 'NicTool::List' );
    ok( $res->size => 2 );
    if ( $res->size == 2 ) {
        my @u = $res->list;
        ok( $u[0]->get('username')   => $username{ $u[0]->id } );
        ok( $u[1]->get('username')   => $username{ $u[1]->id } );
        ok( $u[0]->get('first_name') => $first_name{ $u[0]->id } );
        ok( $u[1]->get('first_name') => $first_name{ $u[1]->id } );
        ok( $u[0]->get('last_name')  => $last_name{ $u[0]->id } );
        ok( $u[1]->get('last_name')  => $last_name{ $u[1]->id } );
        ok( $u[0]->get('email')      => $email{ $u[0]->id } );
        ok( $u[1]->get('email')      => $email{ $u[1]->id } );
    }
    else {
        for ( 1 .. 8 ) { ok(0) }
    }

####################
    # get_user_list    #
####################

    ####################
    # parameters test  #
    ####################

    #user_list missing
    $res = $nt_obj->get_user_list( user_list => "" );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #user_list not integer
    $res = $nt_obj->get_user_list( user_list => "abc" );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #user_list not valid id
    $res = $nt_obj->get_user_list( user_list => "0" );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # get test users   #
    ####################

    $res = $nt_obj->get_user_list( user_list => "$uid1,$uid2" );
    noerrok($res);
    ok( ref $res, 'NicTool::List' );
    ok( $res->size => 2 );
    if ( $res->size == 2 ) {
        my @u = $res->list;
        ok( $u[0]->get('username')   => $username{ $u[0]->id } );
        ok( $u[1]->get('username')   => $username{ $u[1]->id } );
        ok( $u[0]->get('first_name') => $first_name{ $u[0]->id } );
        ok( $u[1]->get('first_name') => $first_name{ $u[1]->id } );
        ok( $u[0]->get('last_name')  => $last_name{ $u[0]->id } );
        ok( $u[1]->get('last_name')  => $last_name{ $u[1]->id } );
        ok( $u[0]->get('email')      => $email{ $u[0]->id } );
        ok( $u[1]->get('email')      => $email{ $u[1]->id } );
    }
    else {
        for ( 1 .. 8 ) { ok(0) }
    }

    #user 1
    $res = $nt_obj->get_user_list( user_list => "$uid1" );
    noerrok($res);
    ok( ref $res, 'NicTool::List' );
    ok( $res->size => 1 );
    if ( $res->size == 1 ) {
        my @u = $res->list;
        ok( $u[0]->id, $uid1 );
        ok( $u[0]->get('username')   => $username{$uid1} );
        ok( $u[0]->get('first_name') => $first_name{$uid1} );
        ok( $u[0]->get('last_name')  => $last_name{$uid1} );
        ok( $u[0]->get('email')      => $email{$uid1} );
    }
    else {
        for ( 1 .. 4 ) { ok(0) }
    }

    #user 2
    $res = $nt_obj->get_user_list( user_list => "$uid2" );
    noerrok($res);
    ok( ref $res, 'NicTool::List' );
    ok( $res->size => 1 );
    if ( $res->size == 1 ) {
        my @u = $res->list;
        ok( $u[0]->id, $uid2 );
        ok( $u[0]->get('username')   => $username{$uid2} );
        ok( $u[0]->get('first_name') => $first_name{$uid2} );
        ok( $u[0]->get('last_name')  => $last_name{$uid2} );
        ok( $u[0]->get('email')      => $email{$uid2} );
    }
    else {
        for ( 1 .. 4 ) { ok(0) }
    }

####################
    # get_user_global_log
####################
    #       TODO       #
####################

####################
    # delete_users     #
####################

    ####################
    # parameters test  #
    ####################

    #user list missing
    $res = $nt_obj->delete_users( user_list => "" );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #user list not integer
    $res = $nt_obj->delete_users( user_list => "abc" );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #user list invalid id
    $res = $nt_obj->delete_users( user_list => "0" );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'user_list' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

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
    else {
        for ( 1 .. 5 ) { ok(0) }
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
    else {
        for ( 1, 2 ) { ok(0) }
    }

}
