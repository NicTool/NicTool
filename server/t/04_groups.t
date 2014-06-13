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

 create 2 groups
 test all the group related API calls
 delete the groups

=head1 TODO

 get_global_application_log
 search params for get_group_subgroups,get_global_application_log

=cut


use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test;

BEGIN { plan tests => 325 }

my $user = new NicTool(
    server_host => Config('server_host'),
    server_port => Config('server_port')
);
die "Couldn't create NicTool Object" unless ok( ref $user, 'NicTool' );

$user->login(
    username => Config('username'),
    password => Config('password')
);
die "Couldn't log in" unless ok( !$user->result->is_error );
die "Couldn't log in" unless ok( $user->nt_user_session );

#try to do the tests
eval {&doit};
warn $@ if $@;

#delete objects even if other tests bail
eval {&del};
warn $@ if $@;

sub doit {

####################
    # new_group        #
####################

    ####################
    # parameters tests #
    ####################

    #no name
    $res = $user->new_group;
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'name' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

    #no nt_group_id
    $res = $user->new_group( name => 'test_delete_me1', nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

    #no nt_group_id
    $res = $user->new_group( name => 'test_delete_me1', nt_group_id => 'abc' )
        ;    # not integer
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

    #no nt_group_id
    $res = $user->new_group( name => 'test_delete_me1', nt_group_id => 0 )
        ;    #invalid id
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

    for ( qw{~ ` ! $ % ^ & * ( ) + = [ ] \ / | ? > < " : ;},
        ',', '#', "\n", '{', '}' )
    {

        #invalid character in group name
        $res = $user->new_group( name => "test${_}delete" );
        noerrok( $res, 300 );
        warn "character $_ should be invalid"
            unless $res->get('error_code') eq 300;
        ok( $res->get('error_msg') =>
                qr/Group name contains an invalid character/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_group(
                nt_group_id => $res->get('nt_group_id') );
        }
    }

    for (qw(t te)) {

        #group name too small
        $res = $user->new_group( name => $_ );
        noerrok( $res, 300 );
        ok( $res->get('error_msg') =>
                qr/Group name must be at least 3 characters/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_group(
                nt_group_id => $res->get('nt_group_id') );
        }
    }

    for ( ' test', qw(-test _test 'test .test @test) ) {

        #group name too small
        $res = $user->new_group( name => $_ );
        noerrok( $res, 300 );
        warn "name $_ should be invalid"
            unless $res->get('error_code') eq 300;
        ok( $res->get('error_msg') =>
                qr/Group name must start with a letter or number/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_group(
                nt_group_id => $res->get('nt_group_id') );
        }
    }

    ####################
    # make test groups #
    ####################

    $res = $user->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $res = $user->new_group( name => 'test_delete_me2' );
    die "Couldn't create test group2"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid2 = $res->get('nt_group_id');

    ####################
    # test duplicate name
    ####################

    $res = $user->new_group( name => 'test_delete_me1' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =>
            qr/Group name is already taken at this level/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $user->delete_group( nt_group_id => $res->get('nt_group_id') );
    }

####################
    # get_group        #
####################

    ####################
    # parameters tests #
    ####################

    #no nt_group_id
    $group1 = $user->get_group( nt_group_id => '' );
    noerrok( $group1, 301 );
    ok( $group1->get('error_msg')  => 'nt_group_id' );
    ok( $group1->get('error_desc') => qr/Required parameters missing/ );

    #no nt_group_id
    $group1 = $user->get_group( nt_group_id => 'abc' );    # not valid integer
    noerrok( $group1, 302 );
    ok( $group1->get('error_msg')  => 'nt_group_id' );
    ok( $group1->get('error_desc') => qr/Some parameters were invalid/ );

    #no nt_group_id
    $group1 = $user->get_group( nt_group_id => 0 );      # not valid id
    noerrok( $group1, 302 );
    ok( $group1->get('error_msg')  => 'nt_group_id' );
    ok( $group1->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # get test group   #
    ####################

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );
    ok( $group1->get('name')            => 'test_delete_me1' );
    ok( $group1->get('parent_group_id') => $user->get('nt_group_id') );

####################
    # get_group_subgroups
####################

    ####################
    # parameters tests #
    ####################
    #no nt_group_id
    $res = $user->get_group_subgroups( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #no nt_group_id
    $res = $user->get_group_subgroups( nt_group_id => 'abc' );   # not integer
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #no nt_group_id
    $res = $user->get_group_subgroups( nt_group_id => 0 );    # not valid id
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # get subgroups of user's group, should contain the 2 test groups
    ####################
    $res = $user->get_group_subgroups;
    noerrok($res);
    ok( ref $res => 'NicTool::List' );
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

####################
    # get_group_groups
####################

    ####################
    # parameters tests #
    ####################
    #no nt_group_id
    $res = $user->get_group_groups( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #no nt_group_id
    $res = $user->get_group_groups( nt_group_id => 'abc' );    #not integer
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #no nt_group_id
    $res = $user->get_group_groups( nt_group_id => 0 );      #not valid id
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # get groups of user's group, should contain the 2 test groups
    ####################
    $res = $user->get_group_groups;
    noerrok($res);
    ok( ref $res => 'NicTool::List' );
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

####################
    # get_group_branch
####################

    ####################
    # parameters tests #
    ####################
    #no nt_group_id
    $res = $user->get_group_branch( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #no nt_group_id
    $res = $user->get_group_branch( nt_group_id => 'abc' );    # not integer
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #no nt_group_id
    $res = $user->get_group_branch( nt_group_id => 0 );      # not valid id
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # get groups of user's group, should contain the 2 test groups
    ####################
    $res = $group1->get_group_branch;
    noerrok($res);
    ok( ref $res => 'NicTool::List' );
    ok( $res->size, 2 );
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

####################
    # edit_group       #
####################

    ####################
    # parameters tests #
    ####################

    #no group id
    $res = $group1->edit_group( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #no group id
    $res = $group1->edit_group( nt_group_id => 'abc' );    #not an integer
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #no group id
    $res = $group1->edit_group( nt_group_id => 0 );      #not valid id
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    for ( qw{~ ` ! $ % ^ & * ( ) + = [ ] \ / | ? > < " : ;},
        ',', '#', "\n", '{', '}' )
    {

        #invalid character in group name
        $res = $group1->edit_group( name => "test${_}delete" );
        noerrok( $res, 300 );
        warn "character $_ should be invalid"
            unless $res->get('error_code') eq 300;
        ok( $res->get('error_msg') =>
                qr/Group name contains an invalid character/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

    for (qw(t te)) {

        #group name too small
        $res = $group1->edit_group( name => $_ );
        noerrok( $res, 300 );
        ok( $res->get('error_msg') =>
                qr/Group name must be at least 3 characters/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

    for ( ' test', qw(-test _test 'test .test @test) ) {

        #group name starts with incorrect char
        $res = $group1->edit_group( name => $_ );
        noerrok( $res, 300 );
        ok( $res->get('error_msg') =>
                qr/Group name must start with a letter or number/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

    #group name already taken
    $res = $group1->edit_group( name => 'test_delete_me2' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =>
            qr/Group name is already taken at this level/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    ####################
    # edit test group  #
    ####################

    $res = $group1->edit_group( name => 'test_delete_me_again' );
    noerrok($res);

    $g1 = $user->get_group( nt_group_id => $gid1 );
    noerrok($g1);
    ok( $g1->get('name')            => 'test_delete_me_again' );
    ok( $g1->get('parent_group_id') => $user->get('nt_group_id') );
    ok( $g1->id, $gid1 );

####################
    # delete_group     #
####################

    ####################
    # parameters tests #
    ####################

    #no group id
    $res = $user->delete_group( nt_group_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    #no group id
    $res = $user->delete_group( nt_group_id => 'abc' );    #not integer
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #no group id
    $res = $user->delete_group( nt_group_id => 0 );      #invalid id
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_group_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #make new subgroup, try to delete parent group
    $res = $group1->new_group( name => 'test_delete_me3' );
    noerrok($res);
    $gid3 = $res->get('nt_group_id');

    $res = $group1->delete_group;
    noerrok( $res, 600 );
    ok( $res->get('error_msg'),
        qr/You can't delete this group until you delete all of its sub-groups/
    );

}

sub del {

    ####################
    # delete test groups
    ####################

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

