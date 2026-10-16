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
 test all the nameserver related API calls
 delete the nameservers
 delete the groups

=head1 TODO

 get_group_nameservers search stuff

=cut

use strict;
use warnings;

# use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test::More 'no_plan';

use DBI;
use NicToolServer::Nameserver::Sanity;

my ( $gid1, $gid2, $group1, $group2, $nsid1, $nsid2, $ns1, $ns2, $res );
my %ns;

my $user = nt_api_connect();

# try to do the tests
eval { object_tests(); };
warn $@ if $@;

# delete objects even if other tests bail
eval { cleanup(); };
warn $@ if $@;

done_testing();
exit;

sub object_tests {

    test_new_group();    # setup
    test_new_nameserver();
    test_get_nameserver();
    test_invalid_export_paths();
    test_get_nameserver_list();
    test_get_group_nameservers();
    test_move_nameserver();
    test_edit_nameserver();
    test_delete_nameserver();
}

sub cleanup {

    ####################
    # delete test nameservers
    ####################

    #$user->config(debug_request=>1,debug_response=>1);
    for ( [ $nsid1, 'nameserver1' ], [ $nsid2, 'nameserver2' ] ) {
        my ( $nsid, $label ) = @$_;
        if ( defined $nsid ) {
            my $res = $user->delete_nameserver( nt_nameserver_id => $nsid );
            noerrok($res) or diag Data::Dumper::Dumper($res);
        }
        else {
            is( 1, 0, "Couldn't delete test $label" );
        }
    }

    ####################
    # cleanup support groups
    ####################

    for ( [ $gid1, 'group1' ], [ $gid2, 'group2' ] ) {
        my ( $gid, $label ) = @$_;
        if ( defined $gid ) {
            noerrok( $user->delete_group( nt_group_id => $gid ) );
        }
        else {
            is( 1, 0, "Couldn't delete test $label" );
        }
    }
}

sub test_new_group {

    $gid1 = new_id_ok( $user->get_group->new_group( name => 'test_delete_me1' ),
        'nt_group_id', "Couldn't create test group1" );
    $group1 =
        fetched_ok( $user->get_group( nt_group_id => $gid1 ), $gid1, "Couldn't get test group1" );

    $gid2 = new_id_ok( $user->get_group->new_group( name => 'test_delete_me2' ),
        'nt_group_id', "Couldn't create test group2" );
    $group2 =
        fetched_ok( $user->get_group( nt_group_id => $gid2 ), $gid2, "Couldn't get test group2" );
}

sub test_new_nameserver {

    ####################
    # make test nameserver
    ####################

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
}

sub test_invalid_export_paths {

    for (
        [ datadir      => '/srv/exports/../etc',   qr/datadir.*traversal/ ],
        [ datadir      => '/srv//exports',         qr/datadir.*empty path/ ],
        [ datadir      => 'relative/path',         qr/datadir.*absolute/ ],
        [ datadir      => '/srv/exports;rm -rf /', qr/datadir/ ],
        [ logdir       => '/var/log/../etc',       qr/logdir.*traversal/ ],
        [ remote_login => 'user; rm -rf /',        qr/remote_login/ ],
        [ remote_login => '1baduser',              qr/remote_login/ ],
        )
    {
        my ( $field, $value, $error ) = @$_;
        my $res = $group1->new_nameserver(
            name          => 'badns1.somewhere.com.',
            address       => '1.2.3.99',
            export_format => 'bind',
            $field        => $value,
        );
        noerrok( $res, 300 );
        like( $res->get('error_msg'), $error );
    }

    # valid paths and remote_login pass
    my $res = $group1->new_nameserver(
        name          => 'goodns.somewhere.com.',
        address       => '1.2.3.98',
        export_format => 'bind',
        datadir       => '/srv/exports/zones',
        logdir        => '/var/log/nictool',
        remote_login  => 'nictool_export',
    );
    noerrok($res);
    if ( !$res->is_error ) {
        my $good_id = $res->get('nt_nameserver_id');
        $user->delete_nameserver( nt_nameserver_id => $good_id );
    }

    # edit_nameserver also rejects bad input
    $res = $ns1->edit_nameserver( datadir => '/srv/../etc' );
    noerrok( $res, 300 );
    like( $res->get('error_msg'), qr/datadir.*traversal/ );

    $res = $ns1->edit_nameserver( remote_login => 'user$(whoami)' );
    noerrok( $res, 300 );
    like( $res->get('error_msg'), qr/remote_login/ );
}

sub nameserver_is {
    my ( $ns, $nsid ) = @_;
    is( $ns->get($_), $ns{$nsid}{$_} ) for qw/ name address export_format ttl /;
}

# with @nsids, the listed rows are checked against those ids, in order
sub nameservers_listed_ok {
    my ( $res, $label, $size, @nsids ) = @_;
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, $size, $label );
    return if $res->size != $size;

    my @u   = $res->list;
    my @ids = @nsids ? @nsids : map { $_->id } @u;
    for my $field (qw/ name address export_format ttl /) {
        is( $u[$_]->get($field), $ns{ $ids[$_] }{$field} ) for 0 .. $#u;
    }
}

sub test_get_nameserver {

    bad_id_ok( 'nt_nameserver_id', sub { $user->get_nameserver( nt_nameserver_id => shift ) } );

    %ns = (
        $nsid1 => {
            name          => 'ns.somewhere.com.',
            address       => '1.2.3.4',
            export_format => 'bind',
            ttl           => '86400'
        },
        $nsid2 => {
            name          => 'ns2.somewhere.com.',
            address       => '1.2.3.5',
            export_format => 'djbdns',
            ttl           => '86401'
        },
    );

    ####################
    # get test nameserver
    ####################
    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    fetched_ok( $ns1, $nsid1, "Couldn't get test nameserver $nsid1 : " . errtext($ns1) );
    nameserver_is( $ns1, $nsid1 );

    $ns2 = $user->get_nameserver( nt_nameserver_id => $nsid2 );
    fetched_ok( $ns2, $nsid2, "Couldn't get test nameserver $nsid2 : " . errtext($ns2) );
    nameserver_is( $ns2, $nsid2 );
}

sub test_get_nameserver_list {

    bad_id_ok( 'nameserver_list', sub { $user->get_nameserver_list( nameserver_list => shift ) },
        '', 'abc', '0' );

    ####################
    # get test nameservers
    ####################
    nameservers_listed_ok( $user->get_nameserver_list( nameserver_list => "$nsid1,$nsid2" ),
        'nameserver_list incorrect size', 2 );
    nameservers_listed_ok(
        $user->get_nameserver_list( nameserver_list => "$nsid1" ),
        'nameserver_list incorrect size',
        1, $nsid1
    );
    nameservers_listed_ok(
        $user->get_nameserver_list( nameserver_list => "$nsid2" ),
        'nameserver_list incorrect size',
        1, $nsid2
    );
}

sub test_get_group_nameservers {

    bad_id_ok( 'nt_group_id', sub { $group2->get_group_nameservers( nt_group_id => shift ) } );

    ####################
    # get test nameservers
    ####################
    nameservers_listed_ok( $group1->get_group_nameservers, 'group_nameservers incorrect size', 2 );
}

sub test_move_nameserver {

    bad_id_ok( 'nameserver_list', sub { $group2->move_nameservers( nameserver_list => shift ) },
        '', 'abc', '0' );
    bad_id_ok(
        'nt_group_id',
        sub {
            $group2->move_nameservers( nt_group_id => shift, nameserver_list => "$nsid1,$nsid2" );
        }
    );

    ####################
    # move test nameservers
    ####################

    my $res = $group2->move_nameservers( nameserver_list => "$nsid1,$nsid2" );
    noerrok($res);

    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($ns1);
    is( $ns1->get('nt_group_id'), $gid2 );

    $ns2 = $user->get_nameserver( nt_nameserver_id => $nsid2 );
    noerrok($ns2);
    is( $ns2->get('nt_group_id'), $gid2 );

    nameservers_listed_ok( $group2->get_group_nameservers, 'group_nameservers incorrect size', 2 );
}

sub test_edit_nameserver {

    bad_id_ok( 'nt_nameserver_id', sub { $ns1->edit_nameserver( nt_nameserver_id => shift ) } );

    ####################
    # edit test nameserver
    ####################

    # the empty edit reads the nameserver back once more without changing it
    for my $edit (
        [ name    => 'ns3.somewhere.com.' ],
        [ address => '1.2.3.6' ],
        [],
        [ export_format => 'djbdns' ],
        [ ttl           => '86402' ],
        )
    {
        if (@$edit) {
            noerrok( $ns1->edit_nameserver(@$edit) );
            $ns{$nsid1}{ $edit->[0] } = $edit->[1];
        }
        $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
        noerrok($ns1);
        nameserver_is( $ns1, $nsid1 );
    }
}

sub test_delete_nameserver {

    bad_id_ok( 'nt_nameserver_id', sub { $user->delete_nameserver( nt_nameserver_id => shift ) } );
}
