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

my ($gid1, $gid2, $group1, $group2, $nsid1, $nsid2, $ns1, $ns2, @u);
my (%name, %address, %ttl, %export_format);

non_object_tests();

my $user = nt_api_connect();

# try to do the tests
eval { object_tests(); };
warn $@ if $@;

# delete objects even if other tests bail
eval { cleanup(); };
warn $@ if $@;

done_testing();
exit;

sub non_object_tests {

    my $dbh = DBI->connect( Config('dsn'), Config('db_user'), Config('db_pass') )
        or die "unable to connect to database: " . $DBI::errstr . "\n";

    my $sanity = NicToolServer::Nameserver::Sanity->new(undef, undef, $dbh);

    # _valid_nsname
    foreach my $bad ( qw/ -bad_ns bad.-domain / ) {
        my $res = $sanity->_valid_nsname( $bad );
        is( $res, 0 );
    };
    foreach my $good ( qw/ good-ns.tld a.b.c / ) {
        my $res = $sanity->_valid_nsname( $good );
        ok( $res );
    };

    # _valid_fqdn
    my $res = $sanity->_valid_fqdn( 'host' );
    is( $res, 0 );
    $res = $sanity->_valid_fqdn( 'host.tld.' );
    ok( $res );


    # _valid_chars
    foreach my $bad ( qw/ bad_ns über / ) {
        $res = $sanity->_valid_chars( $bad );
        is( $res, 0 );
    };
    foreach my $good ( qw/ host name valid-ns wooki.tld / ) {
        $res = $sanity->_valid_chars( $good );
        ok( $res );
    };


    # _valid_export_type, export_format
    foreach my $bad ( qw/ cryptic fuzzy yitizg / ) {
        $res = $sanity->_valid_export_type({ export_format => $bad });
        is( $res, 0 );
    };
    foreach my $good ( qw/ bind djbdns knot NSD maradns powerdns dynect / ) {
        $res = $sanity->_valid_export_type({ export_format => $good });
        ok( $res );
    };

    # _valid_export_type, export_type_id
    foreach my $good_id ( 1 .. 8 ) {
        $res = $sanity->_valid_export_type({ export_type_id => $good_id });
        ok( $res );
    }
    foreach my $bad_id ( -1, 1000 ) {
        $res = $sanity->_valid_export_type({ export_type_id => $bad_id });
        is( $res, 0 );
    }
};

sub object_tests {

    test_new_group();      # setup
    test_new_nameserver();
    test_get_nameserver();
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
    if ( defined $nsid1 ) {
        my $res = $user->delete_nameserver( nt_nameserver_id => $nsid1 );
        noerrok($res) or diag Data::Dumper::Dumper($res);
    }
    else {
        is( 1, 0, "Couldn't delete test nameserver1" );
    }
    if ( defined $nsid2 ) {
        my $res = $user->delete_nameserver( nt_nameserver_id => $nsid2 );
        noerrok($res) or diag Data::Dumper::Dumper($res);
    }
    else {
        is( 1, 0, "Couldn't delete test nameserver2" );
    }

    ####################
    # cleanup support groups
    ####################

    if ( defined $gid1 ) {
        my $res = $user->delete_group( nt_group_id => $gid1 );
        noerrok($res);
    }
    else {
        is( 1, 0, "Couldn't delete test group1" );
    }
    if ( defined $gid2 ) {
        my $res = $user->delete_group( nt_group_id => $gid2 );
        noerrok($res);
    }
    else {
        is( 1, 0, "Couldn't delete test group2" );
    }
}

sub test_new_group {

    #make a new group
    my $res = $user->get_group->new_group( name => 'test_delete_me1' );
    noerrok($res) &&
        ok( $res->get('nt_group_id') =~ qr/^\d+$/ )
            or die "Couldn't create test group1";
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    noerrok($group1) &&
        is( $group1->id, $gid1 )
            or die "Couldn't get test group1";

    #make a new group
    $res = $user->get_group->new_group( name => 'test_delete_me2' );
    noerrok($res) &&
        ok( $res->get('nt_group_id') =~ qr/^\d+$/ )
            or die "Couldn't create test group2";
    $gid2 = $res->get('nt_group_id');

    $group2 = $user->get_group( nt_group_id => $gid2 );
    noerrok($group2) &&
        is( $group2->id, $gid2 )
            or die "Couldn't get test group2";
}

sub test_new_nameserver {

    #no nt_group_id
    my $res = $group1->new_nameserver(
        nt_group_id   => '',
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'djbdns'
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    #no nt_group_id
    $res = $group1->new_nameserver(
        nt_group_id   => 'abc',                 #not integer
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'djbdns'
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    #no nt_group_id
    $res = $group1->new_nameserver(
        nt_group_id   => 0,                   #not valid id
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'djbdns'
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    # no name
    $res = $group1->new_nameserver(
        #name=>'ns.somewhere.com',
        address       => '1.2.3.4',
        export_format => 'djbdns'
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'name' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    for ( qw{~ ` ! @ $ % ^ & * ( ) _ + = \ | ' " ; : < > / ?},
        ',', '#', "\n", ' ', qw({ }) )
    {

        # name has invalid chars
        $res = $group1->new_nameserver(
            name          => 'a.b${_}d.com.',
            address       => '1.2.3.4',
            export_format => 'djbdns',
        );
        noerrok( $res, 300, "char $_" );
        ok( $res->get('error_msg') =~
                qr/Nameserver name contains an invalid character/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_nameserver(
                nt_nameserver_id => $res->get('nt_nameserver_id') );
        }
    }

    #name has parts that start with invalid chars
    $res = $group1->new_nameserver(
        name          => 'ns..somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'djbdns',
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg')  =~ qr/Nameserver name must be a valid host/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    #name has parts that start with invalid chars
    $res = $group1->new_nameserver(
        name          => 'ns.-something.com.',
        address       => '1.2.3.4',
        export_format => 'djbdns'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Parts of a nameserver name cannot start with a dash/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    #name not fully qualified
    $res = $group1->new_nameserver(
        name          => 'ns.abc.com',
        address       => '1.2.3.4',
        export_format => 'djbdns'
    );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Nameserver name must be a fully-qualified domain name with a dot at the end/
    );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    #no address
    $res = $group1->new_nameserver(
        #address      => '1.2.3.4',
        name          => 'ns.somewhere.com.',
        export_format => 'djbdns'
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'address' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    for (qw/
        1.x.2.3 .1.2.3 0.0.0.0 1234.1.2.3 256.2.3.4
        24.56.22.0 1.-.2.3 1.2.3 1.2 1 1.2.3. -1.2.3.4
        /,
        '1. .3.4', '1.2,3.4', '1.,.3.4')
    {
        #address invalid
        $res = $group1->new_nameserver(
            address       => $_,
            name          => 'ns.somewhere.com.',
            export_format => 'djbdns'
        );
        noerrok( $res, 300, "address $_" );
        ok( $res->get('error_msg')  =~ qr/Invalid IP address/, "address $_" );
        ok( $res->get('error_desc') =~ qr/Sanity error/,       "address $_" );
        if ( !$res->is_error ) {
            $res = $user->delete_nameserver(
                nt_nameserver_id => $res->get('nt_nameserver_id') );
        }
    }

    #no export_format
    $res = $group1->new_nameserver(
        name         => 'ns.somewhere.com.',
        address      => '1.2.3.4',
       #export_format=>'djbdns',
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'export_format' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_nameserver(
            nt_nameserver_id => $res->get('nt_nameserver_id') );
    }

    for ( qw/ bin djbs DJB BIND NT / ) {

        #invalid export_format
        $res = $group1->new_nameserver(
            name          => 'ns.somewhere.com.',
            address       => '1.2.3.4',
            export_format => $_,
        );
        noerrok( $res, 300, "export_format $_" );
        ok( $res->get('error_msg')  =~ qr/Invalid export format/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_nameserver(
                nt_nameserver_id => $res->get('nt_nameserver_id') );
        }
    }

    for ( -299, -2592001, -2, -1, 2147483648, 'oops' ) {

        #invalid ttl
        $res = $group1->new_nameserver(
            name          => 'ns.somewhere.com.',
            address       => '1.2.3.4',
            export_format => 'bind',
            ttl           => $_
        );
        noerrok( $res, 300, "ttl $_" );
        ok( $res->get('error_msg')  =~ qr/Invalid TTL/,  "ttl $_" );
        ok( $res->get('error_desc') =~ qr/Sanity error/, "ttl $_" );
        if ( !$res->is_error ) {
            $res = $user->delete_nameserver(
                nt_nameserver_id => $res->get('nt_nameserver_id') );
        }
    }

    ####################
    # make test nameserver
    ####################

    $res = $group1->new_nameserver(
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'bind',
        ttl           => 86400
    );
    noerrok($res) &&
        ok( $res->get('nt_nameserver_id') =~ qr/^\d+$/ )
            or die "couldn't make test nameserver";
    $nsid1 = $res->get('nt_nameserver_id');

    $res = $group1->new_nameserver(
        name          => 'ns2.somewhere.com.',
        address       => '1.2.3.5',
        export_format => 'djbdns',
        ttl           => 86401
    );
    noerrok($res) &&
        ok( $res->get('nt_nameserver_id') =~ qr/^\d+$/ )
            or die "couldn't make test nameserver";
    $nsid2 = $res->get('nt_nameserver_id');
}

sub test_get_nameserver {

    my $res = $user->get_nameserver( nt_nameserver_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $user->get_nameserver( nt_nameserver_id => 'abc' );    #not integer
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $user->get_nameserver( nt_nameserver_id => 0 );    #not valid id
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test nameserver
    ####################
    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($ns1) &&
        is( $ns1->id, $nsid1 )
            or die "Couldn't get test nameserver $nsid1 : " . errtext($ns1);
    is( $ns1->get('name')         , 'ns.somewhere.com.' );
    is( $ns1->get('address')      , '1.2.3.4' );
    is( $ns1->get('export_format'), 'bind' );
    is( $ns1->get('ttl')          , '86400' );

    $ns2 = $user->get_nameserver( nt_nameserver_id => $nsid2 );
    noerrok($ns2)
        && is( $ns2->id, $nsid2 )
            or die "Couldn't get test nameserver $nsid2 : " . errtext($ns2);
    is( $ns2->get('name')         , 'ns2.somewhere.com.' );
    is( $ns2->get('address')      , '1.2.3.5' );
    is( $ns2->get('export_format'), 'djbdns' );
    is( $ns2->get('ttl')          , '86401' );

    %name = ( $nsid1 => 'ns.somewhere.com.', $nsid2 => 'ns2.somewhere.com.' );
    %address       = ( $nsid1 => '1.2.3.4', $nsid2 => '1.2.3.5' );
    %export_format = ( $nsid1 => 'bind',    $nsid2 => 'djbdns' );
    %ttl           = ( $nsid1 => '86400',   $nsid2 => '86401' );
}

sub test_get_nameserver_list {

    # missing param
    my $res = $user->get_nameserver_list( nameserver_list => "" );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nameserver_list' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # invalid int
    $res = $user->get_nameserver_list( nameserver_list => "abc" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nameserver_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # invalid id
    $res = $user->get_nameserver_list( nameserver_list => "0" );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nameserver_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test nameservers
    ####################
    $res = $user->get_nameserver_list( nameserver_list => "$nsid1,$nsid2" );
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 2, 'nameserver_list incorrect size' );
    if ( $res->size == 2 ) {
        @u = $res->list;
        is( $u[0]->get('name')         , $name{ $u[0]->id } );
        is( $u[1]->get('name')         , $name{ $u[1]->id } );
        is( $u[0]->get('address')      , $address{ $u[0]->id } );
        is( $u[1]->get('address')      , $address{ $u[1]->id } );
        is( $u[0]->get('export_format'), $export_format{ $u[0]->id } );
        is( $u[1]->get('export_format'), $export_format{ $u[1]->id } );
        is( $u[0]->get('ttl')          , $ttl{ $u[0]->id } );
        is( $u[1]->get('ttl')          , $ttl{ $u[1]->id } );
    }

    $res = $user->get_nameserver_list( nameserver_list => "$nsid1" );
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 1, 'nameserver_list incorrect size' );
    if ( $res->size == 1 ) {
        @u = $res->list;
        is( $u[0]->get('name')         , $name{$nsid1} );
        is( $u[0]->get('address')      , $address{$nsid1} );
        is( $u[0]->get('export_format'), $export_format{$nsid1} );
        is( $u[0]->get('ttl')          , $ttl{$nsid1} );
    }

    $res = $user->get_nameserver_list( nameserver_list => "$nsid2" );
    noerrok($res);
    isa_ok($res, 'NicTool::List' );
    is( $res->size, 1, 'nameserver_list incorrect size' );
    if ( $res->size == 1 ) {
        @u = $res->list;
        is( $u[0]->get('name')         , $name{$nsid2} );
        is( $u[0]->get('address')      , $address{$nsid2} );
        is( $u[0]->get('export_format'), $export_format{$nsid2} );
        is( $u[0]->get('ttl')          , $ttl{$nsid2} );
    }
}

sub test_get_group_nameservers {

    my $res = $group2->get_group_nameservers( nt_group_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # invalid int
    $res = $group2->get_group_nameservers( nt_group_id => 'abc' );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $group2->get_group_nameservers( nt_group_id => 0 ); # invalid id
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # get test nameservers
    ####################
    $res = $group1->get_group_nameservers;
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 2, 'group_nameservers incorrect size' );
    if ( $res->size == 2 ) {
        @u = $res->list;
        is( $u[0]->get('name')         , $name{ $u[0]->id } );
        is( $u[1]->get('name')         , $name{ $u[1]->id } );
        is( $u[0]->get('address')      , $address{ $u[0]->id } );
        is( $u[1]->get('address')      , $address{ $u[1]->id } );
        is( $u[0]->get('export_format'), $export_format{ $u[0]->id } );
        is( $u[1]->get('export_format'), $export_format{ $u[1]->id } );
        is( $u[0]->get('ttl')          , $ttl{ $u[0]->id } );
        is( $u[1]->get('ttl')          , $ttl{ $u[1]->id } );
        #warn Data::Dumper::Dumper($u[0]);
    }
}

sub test_move_nameserver {

    my $res = $group2->move_nameservers( nameserver_list => "" );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nameserver_list' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $group2->move_nameservers( nameserver_list => "abc" ); #invalid int
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nameserver_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $group2->move_nameservers( nameserver_list => "0" );    #invalid id
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nameserver_list' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $group2->move_nameservers(
        nt_group_id     => '',
        nameserver_list => "$nsid1,$nsid2"
    );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    # invalid int
    $res = $group2->move_nameservers(
        nt_group_id     => 'abc',
        nameserver_list => "$nsid1,$nsid2"
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    # invalid id
    $res = $group2->move_nameservers(
        nt_group_id     => 0,
        nameserver_list => "$nsid1,$nsid2"
    );
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_group_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    ####################
    # move test nameservers
    ####################

    $res = $group2->move_nameservers( nameserver_list => "$nsid1,$nsid2" );
    noerrok($res);

    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($ns1);
    is( $ns1->get('nt_group_id'), $gid2 );

    $ns2 = $user->get_nameserver( nt_nameserver_id => $nsid2 );
    noerrok($ns2);
    is( $ns2->get('nt_group_id'), $gid2 );

    $res = $group2->get_group_nameservers;
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 2, 'group_nameservers incorrect size' );
    if ( $res->size == 2 ) {
        @u = $res->list;
        is( $u[0]->get('name')         , $name{ $u[0]->id } );
        is( $u[1]->get('name')         , $name{ $u[1]->id } );
        is( $u[0]->get('address')      , $address{ $u[0]->id } );
        is( $u[1]->get('address')      , $address{ $u[1]->id } );
        is( $u[0]->get('export_format'), $export_format{ $u[0]->id } );
        is( $u[1]->get('export_format'), $export_format{ $u[1]->id } );
        is( $u[0]->get('ttl')          , $ttl{ $u[0]->id } );
        is( $u[1]->get('ttl')          , $ttl{ $u[1]->id } );
    }
}

sub test_edit_nameserver {

    #no nt_nameserver_id
    my $res = $ns1->edit_nameserver( nt_nameserver_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    #no nt_nameserver_id
    $res = $ns1->edit_nameserver( nt_nameserver_id => 'abc' ); #not integer
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    #no nt_nameserver_id
    $res = $ns1->edit_nameserver( nt_nameserver_id => 0 );  #not valid id
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    for ( qw{~ ` ! @ $ % ^ & * ( ) _ + = \ | ' " ; : < > / ?},
        ',', '#', "\n", ' ', qw({ }) )
    {

        #name has invalid chars
        $res = $ns1->edit_nameserver( name => 'a.b${_}d.com.' );
        noerrok( $res, 300, "char $_" );
        ok( $res->get('error_msg') =~
                qr/Nameserver name contains an invalid character/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
    }

    #name is invalid
    $res = $ns1->edit_nameserver( name => 'ns..somewhere.com.' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg')  =~ qr/Nameserver name must be a valid host/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #name has parts that start with invalid chars
    $res = $ns1->edit_nameserver( name => 'ns.-something.com.' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
            qr/Parts of a nameserver name cannot start with a dash/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #name not fully qualified
    $res = $ns1->edit_nameserver( name => 'ns.abc.com' );
    noerrok( $res, 300 );
    ok( $res->get('error_msg') =~
        qr/name must be a fully-qualified domain name with a dot at the end/
    );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );

    for (
        qw(1.x.2.3 .1.2.3 0.0.0.0 1234.1.2.3 256.2.3.4 24.56.22.0 1.-.2.3 1.2.3 1.2 1 1.2.3. -1.2.3.4),
        '1. .3.4', '1.2,3.4', '1.,.3.4' )
    {
        # address invalid
        $res = $ns1->edit_nameserver( address => $_ );
        noerrok( $res, 300, "address $_" );
        ok( $res->get('error_msg')  =~ qr/Invalid IP address/, "address $_" );
        ok( $res->get('error_desc') =~ qr/Sanity error/,       "address $_" );
    }

    for ( qw/ bin djbs DJB BIND NT / ) {

        #invalid export_format
        $res = $ns1->edit_nameserver( export_format => $_ );
        noerrok( $res, 300, "export_format $_" );
        ok( $res->get('error_msg')  =~ qr/Invalid export format/ );
        ok( $res->get('error_desc') =~ qr/Sanity error/ );
    }

    for ( qw/ -299 -2592001 -2 -1 2147483648 / ) {

        #invalid ttl
        $res = $ns1->edit_nameserver( ttl => $_ );
        noerrok( $res, 300, "ttl $_" );
        ok( $res->get('error_msg')  =~ qr/Invalid TTL/,  "ttl $_" );
        ok( $res->get('error_desc') =~ qr/Sanity error/, "ttl $_" );
    }

    ####################
    # edit test nameserver
    ####################

    $res = $ns1->edit_nameserver( name => "ns3.somewhere.com." );
    noerrok($res);
    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($ns1);
    $name{$nsid1} = 'ns3.somewhere.com.';
    is( $ns1->get('name')         , $name{$nsid1} );
    is( $ns1->get('address')      , $address{$nsid1} );
    is( $ns1->get('export_format'), $export_format{$nsid1} );
    is( $ns1->get('ttl')          , $ttl{$nsid1} );

    $res = $ns1->edit_nameserver( address => "1.2.3.6" );
    noerrok($res);
    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($ns1);
    $address{$nsid1} = '1.2.3.6';
    is( $ns1->get('name')         , $name{$nsid1} );
    is( $ns1->get('address')      , $address{$nsid1} );
    is( $ns1->get('export_format'), $export_format{$nsid1} );
    is( $ns1->get('ttl')          , $ttl{$nsid1} );

    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($ns1);
    is( $ns1->get('name')         , $name{$nsid1} );
    is( $ns1->get('address')      , $address{$nsid1} );
    is( $ns1->get('export_format'), $export_format{$nsid1} );
    is( $ns1->get('ttl')          , $ttl{$nsid1} );

    $res = $ns1->edit_nameserver( export_format => 'djbdns' );
    noerrok($res);
    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($ns1);
    $export_format{$nsid1} = 'djbdns';
    is( $ns1->get('name')         , $name{$nsid1} );
    is( $ns1->get('address')      , $address{$nsid1} );
    is( $ns1->get('export_format'), $export_format{$nsid1} );
    is( $ns1->get('ttl')          , $ttl{$nsid1} );

    $res = $ns1->edit_nameserver( ttl => "86402" );
    noerrok($res);
    $ns1 = $user->get_nameserver( nt_nameserver_id => $nsid1 );
    noerrok($ns1);
    $ttl{$nsid1} = '86402';
    is( $ns1->get('name')         , $name{$nsid1} );
    is( $ns1->get('address')      , $address{$nsid1} );
    is( $ns1->get('export_format'), $export_format{$nsid1} );
    is( $ns1->get('ttl')          , $ttl{$nsid1} );
}

sub test_delete_nameserver {

    # missing nt_nameserver_id
    my $res = $user->delete_nameserver( nt_nameserver_id => '' );
    noerrok( $res, 301 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Required parameters missing/ );

    $res = $user->delete_nameserver( nt_nameserver_id => 'abc' );    #not int
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );

    $res = $user->delete_nameserver( nt_nameserver_id => 0 );    #not valid
    noerrok( $res, 302 );
    is( $res->get('error_msg'), 'nt_nameserver_id' );
    ok( $res->get('error_desc') =~ qr/Some parameters were invalid/ );
}
