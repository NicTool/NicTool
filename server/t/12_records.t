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
 create new zones inside the group
 create records to test inside the zones
 test all the zone record related API calls
 delete the test records
 delete the zones
 delete the nameservers
 delete the groups

=head1 TODO

 logs

=cut

use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test;

BEGIN { plan tests => 2748 }

$user = new NicTool(
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

my $fqdn = 'fully.qualified.com.';
my @ascii = map( chr $_, 0..128);  # ascii table
# weed out legit chars (a-z, 0-9, - . *)
my @invalid_ascii = grep /[^0-9a-zA-Z_\-\.\*]/, @ascii;
# the contents of invalid_ascii look a lot like this:
# ! # " $ % & ' ( ) + , / : ; < = > ? @ \ ^ ` { | } ~ - .

#try to do the tests
eval {&doit};
warn $@ if $@;

#delete objects even if other tests bail
eval {&del};
warn $@ if $@;

sub doit {

    ####################
    # setup            #
    ####################

    # make a new group
    $res = $user->get_group->new_group( name => 'test_delete_me1' );
    die "Couldn't create test group1"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid1 = $res->get('nt_group_id');

    $group1 = $user->get_group( nt_group_id => $gid1 );
    die "Couldn't get test group1"
        unless noerrok($group1)
            and ok( $group1->id, $gid1 );

    # make a new group
    $res = $user->get_group->new_group( name => 'test_delete_me2' );
    die "Couldn't create test group2"
        unless noerrok($res)
            and ok( $res->get('nt_group_id') => qr/^\d+$/ );
    $gid2 = $res->get('nt_group_id');

    $group2 = $user->get_group( nt_group_id => $gid2 );
    die "Couldn't get test group2"
        unless noerrok($group2)
            and ok( $group2->id, $gid2 );

    # make test nameservers
    $res = $group1->new_nameserver(
        name          => 'ns.somewhere.com.',
        address       => '1.2.3.4',
        export_format => 'bind',
        ttl           => 86400
    );
    die "couldn't make test nameserver"
        unless noerrok($res)
            and ok( $res->get('nt_nameserver_id') => qr/^\d+$/ );
    $nsid1 = $res->get('nt_nameserver_id');

    $res = $group1->new_nameserver(
        name          => 'ns2.somewhere.com.',
        address       => '1.2.3.5',
        export_format => 'djbdns',
        ttl           => 86401
    );
    die "couldn't make test nameserver"
        unless noerrok($res)
            and ok( $res->get('nt_nameserver_id') => qr/^\d+$/ );
    $nsid2 = $res->get('nt_nameserver_id');

# make new zones
    $res = $group1->new_zone(
        zone        => 'test.com',
        serial      => 0,
        ttl         => 86400,
        nameservers => "$nsid1,$nsid2",
        description => "test delete me",
        mailaddr    => "somebody.somewhere.com",
        refresh     => 10,
        retry       => 20,
        expire      => 30,
        minimum     => 40,
    );
    die "couldn't make test zone1"
        unless noerrok($res)
            and ok( $res->get('nt_zone_id') => qr/^\d+$/ );
    $zid1 = $res->get('nt_zone_id');
    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    die "Couldn't get test zone 1" unless noerrok($zone1);

    $res = $group1->new_zone(
        zone        => 'anothertest.com',
        serial      => '1',
        ttl         => '86401',
        nameservers => "$nsid1,$nsid2",
        description => "test delete me also",
        mailaddr    => "somebodyelse.somewhere.com",
        refresh     => 100,
        retry       => 200,
        expire      => 300,
        minimum     => 400,
    );
    die "couldn't make test zone2"
        unless noerrok($res)
            and ok( $res->get('nt_zone_id') => qr/^\d+$/ );
    $zid2 = $res->get('nt_zone_id');
    $zone2 = $user->get_zone( nt_zone_id => $zid2 );
    die "Couldn't get test zone 1" unless noerrok($zone2);

####################
    # new_zone_record  #
####################

    #no zone_id
    $res = $zone1->new_zone_record(
        nt_zone_id => '',
        name       => 'a',
        type       => 'A',
        ttl        => 86400,
        address    => '1.1.1.1'
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->{'nt_zone_record_id'} );
    }

    #invalid zone_id
    foreach ( qw/ abc 0 / ) {
        $res = $zone1->new_zone_record(
            nt_zone_id => $_,
            name       => 'a',
            type       => 'A',
            ttl        => 86400,
            address    => '1.1.1.1'
        );
        noerrok( $res, 302 );
        ok( $res->get('error_msg')  => 'nt_zone_id' );
        ok( $res->get('error_desc') => qr/Some parameters were invalid/ );
        if ( !$res->is_error ) {
            $res = $user->delete_zone_record(
                nt_zone_record_id => $res->{'nt_zone_record_id'} );
        }
    };

    #missing name value
    $res = $zone1->new_zone_record(
        #name=>'a',
        type    => 'A',
        ttl     => 86400,
        address => '1.1.1.1'
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'name' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->{'nt_zone_record_id'} );
    }

    #no type value
    $res = $zone1->new_zone_record(
        name => 'a',
        #type=>'A',
        ttl     => 86400,
        address => '1.1.1.1'
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'type' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->{'nt_zone_record_id'} );
    }

    #no address value
    $res = $zone1->new_zone_record(
        name => 'a',
        type => 'A',
        ttl  => 86400,
        #address=>'1.1.1.1'
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'address' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->{'nt_zone_record_id'} );
    }

#invalid name (wildcards)
    for ( qw/ something* some*thing *something something.* / ) {

        $res = $zone1->new_zone_record(
            name    => $_,
            type    => 'A',
            ttl     => 86400,
            address => '1.1.1.1'
        );
        noerrok( $res, 300, "name $_" );
        ok( $res->get('error_msg') =>
                qr/only \*\.something or \* \(by itself\) is a valid wildcard record/
        );
        ok( $res->get('error_desc') => qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_zone_record(
                nt_zone_record_id => $res->{'nt_zone_record_id'} );
        }
    }

#invalid name (bad chars)
# for IDN support, any 8bit octet is valid for name char
#   for $type ( qw/A AAAA MX NS CNAME PTR SRV/ ) {
#       for my $char ( @invalid_ascii ) {
#
#           $res = $zone1->new_zone_record(
#               name    => "some${char}thing",
#               type    => $type,
#               ttl     => 86400,
#               address => $type eq 'A' ? '1.1.1.1' : 'a.b.c.d.',
#               ($type eq 'MX' ? (weight => 1) : ()),
#           );
#           noerrok( $res, 300, "type $type name some${char}thing" );
#           ok( $res->get('error_msg') => qr/invalid character/ );
#           ok( $res->get('error_desc') => qr/Sanity error/ );
#           if ( !$res->is_error ) {
#               $res = $user->delete_zone_record(
#                   nt_zone_record_id => $res->{'nt_zone_record_id'} );
#           }
#       }
#   }

    #invalid name (fqdn)
    foreach my $name ( qw/ a.m. something.test. / ) {

        $res = $zone1->new_zone_record(
            name    => $name,
            type    => 'A',
            ttl     => 86400,
            address => '1.1.1.1'
        );
        noerrok( $res, 300, "name $name" );
        ok( $res->get('error_msg') => qr/absolute host names are NOT allowed/, "new_zone_record: $name" );
        ok( $res->get('error_desc') => qr/Sanity error/, "new_zone_record: $name" );
        if ( !$res->is_error ) {
            $res = $user->delete_zone_record( nt_zone_record_id => $res->{'nt_zone_record_id'} );
        }
    }

    #invalid chars in address
    for $type ( qw/ A AAAA MX NS CNAME PTR SRV / ) {
        for my $char ( @invalid_ascii ) {
            next if $type eq 'AAAA' && $char eq ':';  # legal char

            $res = $zone1->new_zone_record(
                name    => "something",
                address => "some${char}thing",
                type    => $type,
                ttl     => 86400,
                ($type eq 'MX' ? (weight => 1) : ()),
            );
            noerrok( $res, 300, "type $type address some${char}thing" );
            ok( $res->get('error_msg')  => qr/invalid character / );
            ok( $res->get('error_desc') => qr/Sanity error/ );
            if ( !$res->is_error ) {
                $res = $user->delete_zone_record(
                    nt_zone_record_id => $res->{'nt_zone_record_id'} );
            }
        }
    }

    #invalid record type
    for ( qw/ blah x Y P Q R S TU VW XYZ 1 23 / ) {
        $res = $zone1->new_zone_record(
            name    => "something",
            address => "1.2.3.4",
            type    => $_,
            ttl     => 86400,
        );
        noerrok( $res, 300, "type $_" );
        ok( $res->get('error_msg')  => qr/Invalid record type/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_zone_record(
                nt_zone_record_id => $res->{'nt_zone_record_id'} );
        }
    }

#invalid address for type
    for my $type ( qw/ MX NS / ) {
        for my $address ( qw{ -blah -blah.something - something.-something
                /blah.something blah./something.com } ) {

            $res = $zone1->new_zone_record(
                name    => "something",
                address => $address,
                type    => $type,
                ttl     => 86400,
                ($type eq 'MX' ? (weight => 1) : ()),
            );
            noerrok( $res, 300, "type $type address $address" );
            ok( $res->get('error_msg') => qr/must point to a FQDN/, "new_zone_record $type $address" );
            ok( $res->get('error_desc') => qr/Sanity error/, "new_zone_record $type $address" );
            if ( !$res->is_error ) {
                $res = $user->delete_zone_record(
                    nt_zone_record_id => $res->{'nt_zone_record_id'} );
            }
        }
    }

    for my $type ( qw/ MX NS / ) {

        $res = $zone1->new_zone_record(
            name    => "something",
            address => '1.2.3.4',
            type    => $type,
            ttl     => 86400,
            ($type eq 'MX' ? (weight => 1) : ()),
        );
        noerrok( $res, 300, "type $type address '1.2.3.4" );
        ok( $res->get('error_msg') => qr/must point to a FQDN/, "new_zone_record, $type" );
        ok( $res->get('error_desc') => qr/Sanity error/, "new_zone_record, $type" );
        if ( !$res->is_error ) {
            $res = $user->delete_zone_record(
                nt_zone_record_id => $res->{'nt_zone_record_id'} );
        }
    }

#invalid IP address for A records
    for ( qw/ 1.x.2.3 .1.2.3 0.0.0.0 1234.1.2.3 256.2.3.4  1.-.2.3 1.2.3 1.2
              1 1.2.3. -1.2.3.4/, '1. .3.4', '1.2,3.4', '1.,.3.4' ) {

        $res = $zone1->new_zone_record(
            name    => "something",
            address => $_,
            type    => 'A',
            ttl     => 86400,
        );
        noerrok( $res, 300, "A record, invalid address $_" );
        ok( $res->get('error_msg') =>
                qr/Address for A records must be a valid IP address/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_zone_record(
                nt_zone_record_id => $res->{'nt_zone_record_id'} );
        }
    }

#   #invalid to have NS record with same name as zone
#      unless you want to delegate the zone...
#    $res = $zone1->new_zone_record(
#        name    => '@',
#        address => 'ns.somewhere.com.',
#        type    => 'NS',
#        ttl     => 86400,
#    );
#    noerrok( $res, 300, "redundant NS record test" );
#    ok( $res->get('error_msg') =>
#            qr/The NS Records for 'test\.com\.' will automatically be created when the Zone is published to a Nameserver/
#    );
#    ok( $res->get('error_desc') => qr/Sanity error/ );
#    if ( !$res->is_error ) {
#        $res = $user->delete_zone_record(
#            nt_zone_record_id => $res->{'nt_zone_record_id'} );
#    }

#invalid ttl
    for ( qw/ -1 -4 -299 2147483648 / ) {

        $res = $zone1->new_zone_record(
            name    => "something",
            address => '1.2.3.4',
            type    => 'A',
            ttl     => $_
        );
        noerrok( $res, 300, "ttl $_" );
        ok( $res->get('error_msg')  => qr/Invalid TTL/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
        if ( !$res->is_error ) {
            $res = $user->delete_zone_record(
                nt_zone_record_id => $res->{'nt_zone_record_id'} );
        }
    }

    ####################
    # success tests    #
    ####################

my @success_tests = (
    { name => 'x',            address => '1.2.3.4', type => 'A',  ttl=>3600 },
    { name => '2x',           address => '1.2.3.5', type => 'A',  ttl=>3600 },
    { name => '*',            address => '1.1.1.3', type => 'A',  ttl=>3601 },
    { name => '*.something',  address => '1.1.1.4', type => 'A',  ttl=>3602 },
    { name => 'some.*.thing', address => '1.1.1.5', type => 'A',  ttl=>3603 },
    { name => 'x',            address => $fqdn,     type => 'NS', ttl=>300  },
    { name => 'x',            address => $fqdn,     type => 'MX', ttl=>301, weight=>1 },
    { name => '_sip._udp',    address => $fqdn,     type => 'SRV', priority=>1, other=>2, weight=>1},
    { name => 'test.com.', address => 'v=spf1 mx a ip4:127.0.0.6 -all', type => 'TXT' },
    { name => 'test.com.', address => 'v=spf1 mx a ip4:127.0.0.6 ~all', type => 'TXT' },
    { name => 'test.com.', address => 'v=spf1 mx a ip4:127.0.0.6 ?all', type => 'TXT' },
    { name => 'test.com.', address => 'v=spf1 mx a ip4:127.0.0.6 -all', type => 'SPF' },
    { name => 'test.com.', address => 'v=spf1 mx a ip4:127.0.0.6 ~all', type => 'SPF' },
    { name => 'test.com.', address => 'v=spf1 mx a ip4:127.0.0.6 ?all', type => 'SPF' },
    { name => 'www', address => '2607:f729:0000:0000:0000:0000:0000:0001', type => 'AAAA', },
);

# new record success tests
    foreach ( @success_tests ) {
#warn "name: $_->{name}\n";
        $res = $zone1->new_zone_record(
            name    => $_->{name},
            address => $_->{address},
            type    => $_->{type},
            ($_->{ttl} ? (ttl => $_->{ttl}) : ()),
            ($_->{weight} ? (weight => $_->{weight}) : ()),
            ($_->{priority} ? (priority => $_->{priority}) : ()),
            ($_->{other} ? (other => $_->{other}) : ()),
        );
        noerrok($res);
        $t = $res->get('nt_zone_record_id');
        if ( $t ) {
            $res = $user->delete_zone_record( nt_zone_record_id => $t );
            die "couldn't delete test record $t " unless noerrok($res);
        };
    };


    #multiple CNAMES with same name
    $res = $zone1->new_zone_record(
        name    => 'x',
        address => $fqdn,
        type    => 'CNAME',
    );
    noerrok($res);
    $t = $res->get('nt_zone_record_id');

    $res = $zone1->new_zone_record(
        name    => 'x',
        address => $fqdn,
        type    => 'CNAME',
    );
    noerrok( $res, 300, 'multiple CNAME records' );
    ok( $res->get('error_msg') =>
            qr/multiple CNAME records with the same name are NOT allowed/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->get('nt_zone_record_id') );
    }
    $res = $user->delete_zone_record( nt_zone_record_id => $t );
    die "couldn't delete test record $t " unless noerrok($res);

    #CNAME conflict with A record
    $res = $zone1->new_zone_record(
        name    => 'x',
        address => '1.2.3.4',
        type    => 'A',
    );
    noerrok($res);
    $t = $res->get('nt_zone_record_id');

    $res = $zone1->new_zone_record(
        name    => 'x',
        address => $fqdn,
        type    => 'CNAME',
    );
    noerrok( $res, 300, 'CNAME conflict with A records' );
    ok( $res->get('error_msg') => qr/record x already exists within zone as/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->get('nt_zone_record_id') );
    }
    $res = $user->delete_zone_record( nt_zone_record_id => $t );
    die "couldn't delete test record $t " unless noerrok($res);

    #A conflict with CNAME record
    $res = $zone1->new_zone_record(
        name    => 'x',
        address => 'abc.defg.com.',
        type    => 'CNAME',
    );
    noerrok($res);
    $t = $res->get('nt_zone_record_id');

    $res = $zone1->new_zone_record(
        name    => 'x',
        address => '1.2.3.4',
        type    => 'A',
    );
    noerrok( $res, 300, 'A conflict with CNAME records' );
    ok( $res->get('error_msg') =>
            qr/record x already exists within zone as an Alias \(CNAME\) record/
    );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->get('nt_zone_record_id') );
    }
    $res = $user->delete_zone_record( nt_zone_record_id => $t );
    die "couldn't delete test record $t " unless noerrok($res);

    #conflicting sub-zones and records
    $res = $group1->new_zone( zone => 'sub.test.com' );
    noerrok($res);
    $t = $res->get('nt_zone_id');

    $res = $zone1->new_zone_record(
        name    => 'sub',
        address => '1.2.3.4',
        type    => 'A',
    );
    noerrok( $res, 300, "record conflicts with subzone", "new_zone_record, A sub" );
    ok( $res->get('error_msg') =>
            qr/Cannot create\/edit Record .*: it conflicts with existing zone/
    );
    ok( $res->get('error_desc') => qr/Sanity error/, "new_zone_record, A sub" );

    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->get('nt_zone_record_id') );
    }

    $res = $zone1->new_zone_record(
        name    => 'sub.sub',
        address => '1.2.3.4',
        type    => 'A',
    );
    noerrok( $res, 300, "record conflicts with subzone" );
    ok( $res->get('error_msg') =>
            qr/Cannot create\/edit Record .*: it conflicts with existing zone/
    );
    ok( $res->get('error_desc') => qr/Sanity error/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->get('nt_zone_record_id') );
    }

    $res = $user->delete_zones( zone_list => $t );
    noerrok($res);

    ####################
    # create test records
    ####################

    %zr1 = (
        name        => 'a',
        ttl         => 86400,
        description => 'record 1',
        type        => 'A',
        address     => '192.168.1.1',
        weight      => 0
    );
    $res = $zone1->new_zone_record(%zr1);
    die "Couldn't create test record"
        unless noerrok($res)
            and $res->get('nt_zone_record_id') =~ /^\d+$/;
    $zrid1 = $res->get('nt_zone_record_id');
    $zr1 = $user->get_zone_record( nt_zone_record_id => $zrid1 );
    die "Couldn't get test record 1"
        unless noerrok($res)
            and $zr1->get('nt_zone_record_id') eq $zrid1;

    %zr2 = (
        name        => 'b',
        ttl         => 86401,
        description => 'record 2',
        type        => 'MX',
        address     => 'som.com.',
        weight      => 0,
    );
    $res = $zone1->new_zone_record(%zr2);
    die "Couldn't create test record"
        unless noerrok($res)
            and $res->get('nt_zone_record_id') =~ /^\d+$/;
    $zrid2 = $res->get('nt_zone_record_id');
    $zr2 = $user->get_zone_record( nt_zone_record_id => $zrid2 );
    die "Couldn't get test record 1"
        unless noerrok($res)
            and $zr2->get('nt_zone_record_id') eq $zrid2;

####################
    # get_zone_record
####################

    ####################
    # parameters       #
    ####################

    $res = $user->get_zone_record( nt_zone_record_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $user->get_zone_record( nt_zone_record_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $user->get_zone_record( nt_zone_record_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

####################
    # get_zone_records
####################

    ####################
    # parameters       #
    ####################

    $res = $zone1->get_zone_records( nt_zone_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $zone1->get_zone_records( nt_zone_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $zone1->get_zone_records( nt_zone_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    ####################
    # get test records #
    ####################

    $res = $zone1->get_zone_records;
    noerrok($res);
    ok( ref $res   => 'NicTool::List' );
    ok( $res->size => 2 );
    $saw1 = 0;
    $saw2 = 0;
    if ( $res->size => 2 ) {
        for $z ( $res->list ) {
            if ( $z->id eq $zrid1 ) {
                $saw1 = 1;
                for (qw(name ttl address description type weight)) {
                    ok( $z->get($_) => $zr1{$_} );
                }
            }
            elsif ( $z->id eq $zrid2 ) {
                $saw2 = 1;
                for (qw(name ttl address description type weight)) {
                    ok( $z->get($_) => $zr2{$_} );
                }

            }
        }
    }
    if ( !$saw1 ) {
        for ( 1 .. 5 ) { ok( 0, 1, "Didn't find test zone record 1" ) }
    }
    if ( !$saw2 ) {
        for ( 1 .. 5 ) { ok( 0, 1, "Didn't find test zone record 2" ) }
    }

####################
    # edit_zone_record
####################

    ####################
    # parameters       #
    ####################

    #no zone_id
    $res = $zr1->edit_zone_record(
        nt_zone_record_id => '',
        name              => 'c',
        type              => 'A',
        ttl               => 86403,
        address           => '1.1.1.3'
    );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );
    if ( !$res->is_error ) {
        $res = $user->delete_zone_record(
            nt_zone_record_id => $res->{'nt_zone_record_id'} );
    }

    #invalid zone_id
    $res = $zr1->edit_zone_record(
        nt_zone_record_id => 'abc',
        name              => 'c',
        type              => 'A',
        ttl               => 86403,
        address           => '1.1.1.3'
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    #invalid zone_id
    $res = $zr1->edit_zone_record(
        nt_zone_record_id => 0,
        name              => 'c',
        type              => 'A',
        ttl               => 86403,
        address           => '1.1.1.3'
    );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    for (qw(something* some*thing *something something.*)) {

        #invalid name
        $res = $zr1->edit_zone_record(
            name    => $_,
            type    => 'A',
            ttl     => 86403,
            address => '1.1.1.3'
        );
        noerrok( $res, 300, "name $_" );
        ok( $res->get('error_msg') =>
                qr/only \*\.something or \* \(by itself\) is a valid wildcard record/
        );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

# invalid chars in name, address
    #for $type ( qw/ A MX NS CNAME PTR / ) {
    for $type ( qw/ MX / ) {
        for my $char ( @invalid_ascii ) {

            #invalid chars in name
            $res = $zr1->edit_zone_record(
                name    => "some${char}thing",
                type    => $type,
                address => $type eq 'A' ? '1.1.1.1' : 'a.b.c.d.',
                ttl     => 86403,
            );
            noerrok( $res, 300, "type $type name some${char}thing" );
            ok( $res->get('error_msg')  => qr/invalid character/ );
            ok( $res->get('error_desc') => qr/Sanity error/ );

            #invalid chars in address
            $res = $zr1->edit_zone_record(
                name    => "something",
                type    => $type,
                address => "some${char}thing",
                ttl     => 86403,
            );
            noerrok( $res, 300, "type $type address some${char}thing" );
            ok( $res->get('error_msg')  => qr/invalid character / );
            ok( $res->get('error_desc') => qr/Sanity error/ );
        }
    }

#invalid name
    for ( qw/ a.m. something.test. / ) {

        $res = $zr1->edit_zone_record(
            name    => $_,
            type    => 'A',
            ttl     => 86403,
            address => '1.1.1.3'
        );
        noerrok( $res, 300, "name $_" );
        ok( $res->get('error_msg') =>
                qr/absolute host names are NOT allowed/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

#invalid record type
    for ( qw/ blah x Y P Q R S TU VW XYZ 1 23/ ) {

        $res = $zr1->edit_zone_record(
            name    => "something",
            address => "1.2.3.4",
            type    => $_,
            ttl     => 86403,
        );
        noerrok( $res, 300, "type $_" );
        ok( $res->get('error_msg')  => qr/Invalid record type/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

    for my $type ( qw/ MX NS SRV / ) {
        for my $address ( qw( -blah -blah.something -
            something.-something /blah.something blah./something.com) ) {

#invalid address for type
            $res = $zr1->edit_zone_record(
                name    => "something",
                address => $address,
                type    => $type,
                ttl     => 86403,
                (($type eq 'MX' || $type eq 'SRV') ? (weight => 1) : ()),
                ($type eq 'SRV' ? (priority => 1) : ()),
                ($type eq 'SRV' ? (other => 1) : ()),
            );
            noerrok( $res, 300, "type $type address $address" );
            ok( $res->get('error_msg') => qr/must point to a FQDN/, "edit_zone_record, $type, $address" );
            ok( $res->get('error_desc') => qr/Sanity error/, "edit_zone_record, $type, $address" );

#invalid address for preset type
            $res = $zr1->edit_zone_record(
                type    => $type,
                address => 'fully.ok.name.',
                (($type eq 'MX' || $type eq 'SRV') ? (weight => 1) : ()),
                ($type eq 'SRV' ? (priority => 1) : ()),
                ($type eq 'SRV' ? (other => 1) : ()),
            );
            noerrok($res);
            for (  qw[ -blah -blah.something - something.-something /blah.something blah./something.com ] ) {
                $res = $zr1->edit_zone_record( address => $address );
                noerrok( $res, 300, "type $type address $address" );
                ok( $res->get('error_msg') => qr/must point to a FQDN/, "edit_zone_record, $type, $address" );
                ok( $res->get('error_desc') => qr/Sanity error/, "edit_zone_record, $type, $address" );
            }
        }
    }

#invalid address for type
    for my $type ( qw/ MX NS SRV / ) {
        for my $address ( qw/ 1.2.3.4 5.1.2.8 5.1.2 a.b.c / ) {

            $res = $zr1->edit_zone_record(
                name    => "something",
                address => $address,
                type    => $type,
                ttl     => 86403,
                (($type eq 'MX' || $type eq 'SRV') ? (weight => 1) : ()),
                ($type eq 'SRV' ? (priority => 1) : ()),
                ($type eq 'SRV' ? (other => 1) : ()),
            );
            noerrok( $res, 300, "type $type address $address" );
            ok( $res->get('error_msg')  => qr/must point to a FQDN/ );
            ok( $res->get('error_desc') => qr/Sanity error/ );

            $res = $zr1->edit_zone_record(
                type    => $type,
                address => 'fully.ok.name.',
                (($type eq 'MX' || $type eq 'SRV') ? (weight => 1) : ()),
                ($type eq 'SRV' ? (priority => 1) : ()),
                ($type eq 'SRV' ? (other => 1) : ()),
            );
            noerrok($res);

            #invalid address for preset type
            $res = $zr1->edit_zone_record( address => $address );
            noerrok( $res, 300, "type $type address $address" );
            ok( $res->get('error_msg')  => qr/must point to a FQDN/ );
            ok( $res->get('error_desc') => qr/Sanity error/ );
        }
    }

#invalid IP address for A records
    for my $address ( qw/ 1.x.2.3 .1.2.3 0.0.0.0 1234.1.2.3 256.2.3.4  1.-.2.3 1.2.3 1.2
            1 1.2.3. -1.2.3.4/, '1. .3.4', '1.2,3.4', '1.,.3.4' ) {

        $res = $zr1->edit_zone_record(
            name    => "something",
            address => $address,
            type    => 'A',
            ttl     => 86403,
        );
        noerrok( $res, 300, "address $address" );
        ok( $res->get('error_msg') =>
                qr/Address for A records must be a valid IP address/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

#invalid IP address for AAAA records
    for ( qw/ abcd:efg1::1 1.2.3.4 200.200.200.200 / ) {

        $res = $zr1->edit_zone_record(
            name    => "something",
            address => $_,
            type    => 'AAAA',
            ttl     => 86403,
        );
        noerrok( $res, 300, "address $_" );
        ok( $res->get('error_msg') => qr/must be a valid IPv6 address/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    };

#invalid IP address for preset A record
    $res = $zr1->edit_zone_record( type => 'A', address => '1.2.3.4');
    noerrok($res);

    for ( qw(1.x.2.3 .1.2.3 0.0.0.0 1234.1.2.3 256.2.3.4  1.-.2.3 1.2.3 1.2
             1 1.2.3. -1.2.3.4), '1. .3.4', '1.2,3.4', '1.,.3.4' ) {

        $res = $zr1->edit_zone_record( address => $_ );
        noerrok( $res, 300, "address $_" );
        ok( $res->get('error_msg') =>
                qr/Address for A records must be a valid IP address/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

    #invalid to have NS record with same name as zone...
#   $res = $zr1->edit_zone_record(
#       name    => '@',
#       address => 'ns.somewhere.com.',
#       type    => 'NS',
#       ttl     => 86400,
#   );
#   noerrok( $res, 300, "redundant NS record test" );
#   ok( $res->get('error_msg') =>
#           qr/The NS Records for 'test\.com\.' will automatically be created when the Zone is published to a Nameserver/
#   );
#   ok( $res->get('error_desc') => qr/Sanity error/ );

#invalid ttl
    for ( qw/ -1 -4 -299 2147483648 -2 / ) {

        $res = $zr1->edit_zone_record(
            name    => "something",
            type    => 'A',
            address => '1.2.3.4',
            ttl     => $_,
        );
        noerrok( $res, 300, "ttl $_" );
        ok( $res->get('error_msg')  => qr/Invalid TTL/ );
        ok( $res->get('error_desc') => qr/Sanity error/ );
    }

    ####################
    # success tests    #
    ####################

    foreach ( @success_tests ) {
        $res = $zr1->edit_zone_record(
            name    => $_->{name},
            address => $_->{address},
            type    => $_->{type},
            (($_->{type} eq 'MX' || $_->{type} eq 'SRV') ? (weight => 1) : ()),
            ($_->{type} eq 'SRV' ? (priority => 1) : ()),
            ($_->{type} eq 'SRV' ? (other => 1) : ()),
        );

        noerrok($res);
        $zr1->refresh;
        ok( $zr1->get('name'),    $_->{name}    );
        ok( $zr1->get('address'), $_->{address} );
        ok( $zr1->get('type'),    $_->{type}    );
    };

# SPF with shortcut expansion
    $res = $zr1->edit_zone_record(
        name    => '@',
        address => 'v=spf1 mx a ip4:127.0.0.6 -all',
        type    => 'SPF',
    );
    noerrok($res);
    $zr1->refresh;
    ok( $zr1->get('name'),    'test.com.' );
    ok( $zr1->get('address'), 'v=spf1 mx a ip4:127.0.0.6 -all' );
    ok( $zr1->get('type'),    'SPF' );

# TXT with shortcut expansion
    $res = $zr1->edit_zone_record(
        name    => '@',
        address => 'v=spf1 mx a ip4:127.0.0.6 -all',
        type    => 'TXT',
    );
    noerrok($res);
    $zr1->refresh;
    ok( $zr1->get('name'),    'test.com.' );
    ok( $zr1->get('address'), 'v=spf1 mx a ip4:127.0.0.6 -all' );
    ok( $zr1->get('type'),    'TXT' );

# AAAA with shortcut expansion
    $res = $zr1->edit_zone_record(
        name    => 'www',
        address => '2001:db8::0001',
        type    => 'AAAA',
    );
    noerrok($res);
    $zr1->refresh;
    ok( $zr1->get('name'),    'www' );
    ok( $zr1->get('address'), '2001:0db8:0000:0000:0000:0000:0000:0001' );
    ok( $zr1->get('type'),    'AAAA' );

    # multiple CNAMES with same name
    $res = $zr1->edit_zone_record(
        name    => 'x',
        address => $fqdn,
        type    => 'CNAME',
    );
    noerrok($res);
    $zr1->refresh;
    ok( $zr1->get('name'),    'x' );
    ok( $zr1->get('address'), $fqdn );
    ok( $zr1->get('type'),    'CNAME' );

    $res = $zr2->edit_zone_record(
        name    => 'x',
        address => $fqdn,
        type    => 'CNAME',
    );
    noerrok( $res, 300, 'multiple CNAME records' );
    ok( $res->get('error_msg') =>
            qr/multiple CNAME records with the same name are NOT allowed/ );
    ok( $res->get('error_desc') => qr/Sanity error/ );

#CNAME conflict with A record
    $res = $zr1->edit_zone_record(
        name    => 'x',
        address => '1.2.3.4',
        type    => 'A',
    );
    noerrok($res);
    $zr1->refresh;
    ok( $zr1->get('name'),    'x' );
    ok( $zr1->get('address'), '1.2.3.4' );
    ok( $zr1->get('type'),    'A' );

    $res = $zr2->edit_zone_record(
        name    => 'x',
        address => $fqdn,
        type    => 'CNAME',
    );
    noerrok( $res, 300, 'CNAME conflict with A records' );
    ok( $res->get('error_msg') =>
            qr/record x already exists within zone as an/
    );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    # A conflict with CNAME record
    $res = $zr1->edit_zone_record(
        name    => 'x',
        address => 'abc.defg.com.',
        type    => 'CNAME',
    );
    noerrok($res);
    $zr1->refresh;
    ok( $zr1->get('name'),    'x' );
    ok( $zr1->get('address'), 'abc.defg.com.' );
    ok( $zr1->get('type'),    'CNAME' );

    $res = $zr2->edit_zone_record(
        name    => 'x',
        address => '1.2.3.4',
        type    => 'A',
    );
    noerrok( $res, 300, 'A conflict with CNAME records' );
    ok( $res->get('error_msg') =>
            qr/record x already exists within zone as an Alias \(CNAME\) record/
    );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    #conflicting sub-zones and records
    $res = $group1->new_zone( zone => 'sub.test.com' );
    noerrok($res);
    $t = $res->get('nt_zone_id');

    $res = $zr1->edit_zone_record(
        name    => 'sub',
        address => '1.2.3.4',
        type    => 'A',
    );
    noerrok( $res, 300, "record conflicts with subzone" );
    ok( $res->get('error_msg') =>
            qr/Cannot create\/edit Record .*: it conflicts with existing zone/
    );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    $res = $zr1->edit_zone_record(
        name    => 'sub.sub',
        address => '1.2.3.4',
        type    => 'A',
    );
    noerrok( $res, 300, "record conflicts with subzone" );
    ok( $res->get('error_msg') =>
            qr/Cannot create\/edit Record .*: it conflicts with existing zone/
    );
    ok( $res->get('error_desc') => qr/Sanity error/ );

    $res = $user->delete_zones( zone_list => $t );
    noerrok($res);

####################
# delete_zone_record
####################

    ####################
    # parameters       #
    ####################
    $res = $user->delete_zone_record( nt_zone_record_id => '' );
    noerrok( $res, 301 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Required parameters missing/ );

    $res = $user->delete_zone_record( nt_zone_record_id => 'abc' );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

    $res = $user->delete_zone_record( nt_zone_record_id => 0 );
    noerrok( $res, 302 );
    ok( $res->get('error_msg')  => 'nt_zone_record_id' );
    ok( $res->get('error_desc') => qr/Some parameters were invalid/ );

####################
# get_record_type
####################

    $res = $user->get_record_type( type => 'ALL');
    noerrok($res);
    #warn Data::Dumper::Dumper($res);
}

sub del {

    if ( defined $zrid2 ) {
        $res = $user->delete_zone_record( nt_zone_record_id => $zrid2 );
        unless ( noerrok($res) ) {
            warn Data::Dumper::Dumper($res);
        }
    }
    else {
        ok( 1, 0, "Couldn't delete test zone record 2" );
    }
    if ( defined $zrid1 ) {
        $res = $user->delete_zone_record( nt_zone_record_id => $zrid1 );
        unless ( noerrok($res) ) {
            warn Data::Dumper::Dumper($res);
        }
    }
    else {
        ok( 1, 0, "Couldn't delete test zone record 1" );
    }

    if ( defined $zid1 ) {
        $res = $user->delete_zones( zone_list => $zid1 );
        unless ( noerrok($res) ) {
            warn Data::Dumper::Dumper($res);
        }
    }
    else {
        ok( 1, 0, "Couldn't delete test zone 1" );
    }

    if ( defined $zid2 ) {
        $res = $user->delete_zones( zone_list => $zid2 );
        unless ( noerrok($res) ) {
            warn Data::Dumper::Dumper($res);
        }
    }
    else {
        ok( 1, 0, "Couldn't delete test zone 2" );
    }

    if ( defined $nsid1 ) {
        $res = $user->delete_nameserver( nt_nameserver_id => $nsid1 );
        unless ( noerrok($res) ) {
            warn Data::Dumper::Dumper($res);
        }
    }
    else {
        ok( 1, 0, "Couldn't delete test nameserver1" );
    }
    if ( defined $nsid2 ) {
        $res = $user->delete_nameserver( nt_nameserver_id => $nsid2 );
        unless ( noerrok($res) ) {
            warn Data::Dumper::Dumper($res);
        }
    }
    else {
        ok( 1, 0, "Couldn't delete test nameserver2" );
    }

    if ( defined $gid1 ) {
        $res = $user->delete_group( nt_group_id => $gid1 );
        noerrok($res);
    }
    else {
        ok( 1, 0, "Couldn't delete test group1" );
    }
    if ( defined $gid2 ) {
        $res = $user->delete_group( nt_group_id => $gid2 );
        noerrok($res);
    }
    else {
        ok( 1, 0, "Couldn't delete test group2" );
    }
}

