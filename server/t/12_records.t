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

# use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test::More 'no_plan';

my $user = nt_api_connect();

my $fqdn  = 'fully.qualified.com.';
my @ascii = map( chr $_, 0 .. 128 );    # ascii table

# weed out legit chars (a-z, 0-9, - . *)
my @invalid_ascii = grep /[^0-9a-zA-Z_\-\.\*]/, @ascii;

# the contents of invalid_ascii look like this:
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

    $gid1 = new_id_ok( $user->get_group->new_group( name => 'test_delete_me1' ),
        'nt_group_id', "Couldn't create test group1" );
    $group1 =
        fetched_ok( $user->get_group( nt_group_id => $gid1 ), $gid1, "Couldn't get test group1" );

    $gid2 = new_id_ok( $user->get_group->new_group( name => 'test_delete_me2' ),
        'nt_group_id', "Couldn't create test group2" );
    $group2 =
        fetched_ok( $user->get_group( nt_group_id => $gid2 ), $gid2, "Couldn't get test group2" );

    # make test nameservers
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
    $zid1  = new_id_ok( $res, 'nt_zone_id', "couldn't make test zone1" );
    $zone1 = $user->get_zone( nt_zone_id => $zid1 );
    noerrok($zone1)
        or die "Couldn't get test zone 1";

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
    $zid2  = new_id_ok( $res, 'nt_zone_id', "couldn't make test zone2" );
    $zone2 = $user->get_zone( nt_zone_id => $zid2 );
    noerrok($zone2) or die "Couldn't get test zone 1";

    ####################
    # new_zone_record  #
    ####################

    # a name in the zone, in another case, takes the zone's spelling
    for my $case ( [ 'WWW.TEST.COM.', 'WWW' ], [ 'Test.Com.', 'test.com.' ] ) {
        my ( $name, $stored ) = @$case;
        $res = $zone1->new_zone_record(
            name    => $name,
            address => '1.2.3.4',
            type    => 'A',
            ttl     => 86400,
        );
        noerrok($res) or next;
        my $zrid = $res->get('nt_zone_record_id');
        is( $user->get_zone_record( nt_zone_record_id => $zrid )->get('name'), $stored, "$name is stored as $stored" );
        $user->delete_zone_record( nt_zone_record_id => $zrid );
    }

    # no address value
    $res = $zone1->new_zone_record(
        name => 'a',
        type => 'A',
        ttl  => 86400,

        #address=>'1.1.1.1'
    );
    param_error_ok( $res, 301, 'address' );
    delete_if_created($res);

    # invalid record type
    for (qw/ blah x Y P Q R S TU VW XYZ 1 23 /) {
        $res = $zone1->new_zone_record(
            name    => "something",
            address => "1.2.3.4",
            type    => $_,
            ttl     => 86400,
        );
        sanity_error_ok( $res, qr/Invalid record type/, "type $_" );
        delete_if_created($res);
    }

    # TTL update of RRset
    {
        my ( @zr, @id );
        my ($i) = 0;
        foreach ( '1.2.3.4', '2.3.4.5' ) {
            my $id = $zone1->new_zone_record(
                name    => "rrsetname",
                address => $_,
                type    => 'A',
                ttl     => 86400
            );
            my $zrid = $id->get('nt_zone_record_id');
            my $zr   = $user->get_zone_record( nt_zone_record_id => $zrid );
            $id[$i] = $zrid;
            $zr[ $i++ ] = $zr;
        }

        $res = $zr[0]->edit_zone_record( ttl => 6000 );

        # Test that the update has been propagated to the whole RRset
        is( $zr[0]->get('ttl'), $zr[1]->get('ttl') );

        # Cleanup after us...
        foreach (@id) {
            $res = $user->delete_zone_record( nt_zone_record_id => $_ );
            noerrok($res) or die "Could not delete test record $_";
        }
    }

    ####################
    # success tests    #
    ####################

    my @success_tests = (
        { name => 'x',  address => '1.2.3.4', type => 'A', ttl => 3600 },
        { name => '2x', address => '1.2.3.5', type => 'A', ttl => 3600 },
        { name => '*',  address => '1.1.1.3', type => 'A', ttl => 3601 },
        {   name    => '*.something',
            address => '1.1.1.4',
            type    => 'A',
            ttl     => 3602
        },
        { name => 'x', address => $fqdn, type => 'NS', ttl => 300 },
        {   name    => 'x',
            address => $fqdn,
            type    => 'MX',
            ttl     => 301,
            weight  => 1
        },
        {   name     => '_sip._udp',
            address  => $fqdn,
            type     => 'SRV',
            priority => 1,
            other    => 2,
            weight   => 1
        },
        {   name    => 'test.com.',
            address => 'v=spf1 mx a ip4:127.0.0.6 -all',
            type    => 'TXT'
        },
        {   name    => 'test.com.',
            address => 'v=spf1 mx a ip4:127.0.0.6 ~all',
            type    => 'TXT'
        },
        {   name    => 'test.com.',
            address => 'v=spf1 mx a ip4:127.0.0.6 ?all',
            type    => 'TXT'
        },
        {   name    => 'test.com.',
            address => 'v=spf1 mx a ip4:127.0.0.6 -all',
            type    => 'SPF'
        },
        {   name    => 'test.com.',
            address => 'v=spf1 mx a ip4:127.0.0.6 ~all',
            type    => 'SPF'
        },
        {   name    => 'test.com.',
            address => 'v=spf1 mx a ip4:127.0.0.6 ?all',
            type    => 'SPF'
        },
        {   name    => 'www',
            address => '2607:f729:0000:0000:0000:0000:0000:0001',
            type    => 'AAAA',
        },
        {   name    => 'test.com.',
            weight  => '0',
            other   => "issue",
            address => "ca.example.com",
            type    => 'CAA',
            ttl     => 3600
        },
        {   name    => 'test.com.',
            weight  => '128',
            other   => "iodef",
            address => "mailto:security@test.com",
            type    => 'CAA',
            ttl     => 3600
        },
        {   name    => 'test.com.',
            weight  => '0',
            other   => "iodef",
            address => "https://ca-report.test.com/",
            type    => 'CAA',
            ttl     => 3600
        },
    );

    # new record success tests
    foreach (@success_tests) {

        #warn "name: $_->{name}\n";
        $res = $zone1->new_zone_record( record_args($_) );
        noerrok($res);
        $t = $res->get('nt_zone_record_id');
        if ($t) {
            $res = $user->delete_zone_record( nt_zone_record_id => $t );
            noerrok($res) or die "couldn't delete test record $t ";
        }
    }

    my @misplaced = map { [ $_, 'A', '1.1.1.5' ] } 'some.*', 'some.*.thing', '*.*.thing', '**',
        'some*thing', '*something';
    push @misplaced, map { [ $_, 'TXT', 'x' ] } 'some.*.thing', 'foo*bar';
    for my $case (@misplaced) {
        my ( $name, $type, $address ) = @$case;
        $res = $zone1->new_zone_record(
            name    => $name,
            address => $address,
            type    => $type,
            ttl     => 3603,
        );
        noerrok( $res, 300, "$type $name is not a wildcard owner" );
        like( $res->get('error_msg'), qr/only \*\.something or \*/, 'reports the wildcard rule' );
        if ( my $made = $res->get('nt_zone_record_id') ) {
            $user->delete_zone_record( nt_zone_record_id => $made );
        }
    }

    $res = $zone1->new_zone_record(
        name    => '*.bad!name',
        address => '1.1.1.5',
        type    => 'A',
        ttl     => 3603
    );
    noerrok( $res, 300, 'a wildcard owner gets the character check too' );
    like( $res->get('error_msg'), qr/invalid character/, 'reports the bad character' );
    if ( my $made = $res->get('nt_zone_record_id') ) {
        $user->delete_zone_record( nt_zone_record_id => $made );
    }

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
    ok( $res->get('error_msg') =~
            qr/Cannot create\/edit Record .*: it conflicts with existing zone/ );
    ok( $res->get('error_desc') =~ qr/Sanity error/, "new_zone_record, A sub" );

    if ( !$res->is_error ) {
        $res = $user->delete_zone_record( nt_zone_record_id => $res->get('nt_zone_record_id') );
    }

    $res = $zone1->new_zone_record(
        name    => 'sub.sub',
        address => '1.2.3.4',
        type    => 'A',
    );
    sanity_error_ok(
        $res,
        qr/Cannot create\/edit Record .*: it conflicts with existing zone/,
        "record conflicts with subzone"
    );
    if ( !$res->is_error ) {
        $res = $user->delete_zone_record( nt_zone_record_id => $res->get('nt_zone_record_id') );
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
    $res   = $zone1->new_zone_record(%zr1);
    $zrid1 = new_id_ok( $res, 'nt_zone_record_id', "Couldn't create test record" );
    $zr1   = $user->get_zone_record( nt_zone_record_id => $zrid1 );
    noerrok($res) && is( $zr1->get('nt_zone_record_id'), $zrid1 )
        or die "Couldn't get test record 1";

    %zr2 = (
        name        => 'b',
        ttl         => 86401,
        description => 'record 2',
        type        => 'MX',
        address     => 'som.com.',
        weight      => 0,
    );
    $res   = $zone1->new_zone_record(%zr2);
    $zrid2 = new_id_ok( $res, 'nt_zone_record_id', "Couldn't create test record" );
    $zr2   = $user->get_zone_record( nt_zone_record_id => $zrid2 );
    noerrok($res) && is( $zr2->get('nt_zone_record_id'), $zrid2 )
        or die "Couldn't get test record 1";

    ####################
    # get_zone_record
    ####################

    ####################
    # parameters       #
    ####################

    bad_id_ok( 'nt_zone_record_id', sub { $user->get_zone_record( nt_zone_record_id => shift ) } );

    # Regression: sortby was previously interpolated straight into ORDER BY in
    # get_zone_record, letting any authenticated user append SQL. The fix drops
    # ORDER BY entirely (PK lookup, at most one row), so any sortby value -- even
    # a SQL-injection payload -- must be ignored and the record returned cleanly.
    for my $payload (
        "name; DROP TABLE nt_user --",
        "name) UNION SELECT password FROM nt_user --",
        "name/**/UNION/**/SELECT/**/1",
        "1=1",
        "name'",
        "",
    )
    {
        $res = $user->get_zone_record(
            nt_zone_record_id => $zrid1,
            sortby            => $payload,
        );
        noerrok($res);
        is( $res->get('nt_zone_record_id'), $zrid1,
            "sortby payload ignored: " . substr( $payload, 0, 30 ) );
    }

    ####################
    # get_zone_records
    ####################

    ####################
    # parameters       #
    ####################

    bad_id_ok( 'nt_zone_id', sub { $zone1->get_zone_records( nt_zone_id => shift ) } );

    ####################
    # get test records #
    ####################

    $res = $zone1->get_zone_records;
    noerrok($res);
    isa_ok( $res, 'NicTool::List' );
    is( $res->size, 2 );
    $saw1 = 0;
    $saw2 = 0;
    if ( $res->size => 2 ) {
        for $z ( $res->list ) {
            if ( $z->id eq $zrid1 ) {
                $saw1 = 1;
                for (qw(name ttl address description type weight)) {
                    is( $z->get($_), $zr1{$_} );
                }
            }
            elsif ( $z->id eq $zrid2 ) {
                $saw2 = 1;
                for (qw(name ttl address description type weight)) {
                    is( $z->get($_), $zr2{$_} );
                }

            }
        }
    }
    if ( !$saw1 ) {
        for ( 1 .. 5 ) { is( 0, 1, "Didn't find test zone record 1" ) }
    }
    if ( !$saw2 ) {
        for ( 1 .. 5 ) { is( 0, 1, "Didn't find test zone record 2" ) }
    }

    #############################
    # issue #310 regressions    #
    #############################

    {
        my $created = $zone1->new_zone_record(
            name        => 'issue310-a',
            ttl         => 86400,
            description => 'issue310 before',
            type        => 'A',
            address     => '203.0.113.10',
        );
        noerrok($created) or die "Couldn't create issue310 A record";

        my $issue310_a_id = $created->get('nt_zone_record_id');
        my $updated       = $zone1->new_zone_record(
            nt_zone_record_id => $issue310_a_id,
            nt_zone_id        => $zid1,
            name              => 'issue310-a',
            ttl               => 300,
            description       => 'issue310 after',
            type              => 'A',
            address           => '203.0.113.10',
        );
        noerrok( $updated, 200, 'new_zone_record updates existing A record' )
            or die errtext($updated);
        is( $updated->get('nt_zone_record_id'),
            $issue310_a_id, 'new_zone_record returns existing A record id when updating' );

        my $issue310_a = $user->get_zone_record( nt_zone_record_id => $issue310_a_id );
        noerrok($issue310_a);
        is( $issue310_a->get('ttl'), 300, 'updated A record ttl changed in place' );
        is( $issue310_a->get('description'),
            'issue310 after',
            'updated A record description changed in place'
        );

        my $zone_records = $zone1->get_zone_records;
        noerrok($zone_records);
        my @issue310_a_matches = grep {
                   $_->get('name') eq 'issue310-a'
                && $_->get('type') eq 'A'
                && $_->get('address') eq '203.0.113.10'
        } $zone_records->list;
        is( scalar @issue310_a_matches,
            1, 'update via new_zone_record does not duplicate A record' );

        $res = $user->delete_zone_record( nt_zone_record_id => $issue310_a_id );
        noerrok($res)
            or die "Could not delete issue310 A record $issue310_a_id";
    }

    {
        my $created = $zone1->new_zone_record(
            name        => 'issue310-cname',
            ttl         => 86400,
            description => 'issue310 cname before',
            type        => 'CNAME',
            address     => 'before.example.net.',
        );
        noerrok($created) or die "Couldn't create issue310 CNAME record";

        my $issue310_cname_id = $created->get('nt_zone_record_id');
        my $updated           = $zone1->new_zone_record(
            nt_zone_record_id => $issue310_cname_id,
            nt_zone_id        => $zid1,
            name              => 'issue310-cname',
            ttl               => 300,
            description       => 'issue310 cname after',
            type              => 'CNAME',
            address           => 'before.example.net.',
        );
        noerrok( $updated, 200, 'new_zone_record updates existing CNAME record' )
            or die errtext($updated);
        is( $updated->get('nt_zone_record_id'),
            $issue310_cname_id, 'new_zone_record returns existing CNAME id when updating' );

        my $issue310_cname = $user->get_zone_record( nt_zone_record_id => $issue310_cname_id );
        noerrok($issue310_cname);
        is( $issue310_cname->get('ttl'), 300, 'updated CNAME ttl changed in place' );
        is( $issue310_cname->get('description'),
            'issue310 cname after',
            'updated CNAME description changed in place'
        );

        my $zone_records = $zone1->get_zone_records;
        noerrok($zone_records);
        my @issue310_cname_matches = grep {
                   $_->get('name') eq 'issue310-cname'
                && $_->get('type') eq 'CNAME'
                && $_->get('address') eq 'before.example.net.'
        } $zone_records->list;
        is( scalar @issue310_cname_matches,
            1, 'update via new_zone_record does not duplicate CNAME record' );

        $res = $user->delete_zone_record( nt_zone_record_id => $issue310_cname_id );
        noerrok($res)
            or die "Could not delete issue310 CNAME record $issue310_cname_id";
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
    param_error_ok( $res, 301, 'nt_zone_record_id' );
    delete_if_created($res);

    # invalid chars in name, address
    #for $type ( qw/ A MX NS CNAME PTR / ) {
    for $type (qw/ MX /) {
        for my $char (@invalid_ascii) {

            #invalid chars in name
            $res = $zr1->edit_zone_record(
                name    => "some${char}thing",
                type    => $type,
                address => $type eq 'A' ? '1.1.1.1' : 'a.b.c.d.',
                ttl     => 86403,
            );
            sanity_error_ok( $res, qr/invalid character/, "type $type name some${char}thing" );

            #invalid chars in address
            $res = $zr1->edit_zone_record(
                name    => "something",
                type    => $type,
                address => "some${char}thing",
                ttl     => 86403,
            );
            sanity_error_ok( $res, qr/invalid character /, "type $type address some${char}thing" );
        }
    }

    # invalid name
    for (qw/ a.m. something.test. /) {

        $res = $zr1->edit_zone_record(
            name    => $_,
            type    => 'A',
            ttl     => 86403,
            address => '1.1.1.3'
        );
        sanity_error_ok( $res, qr/absolute host names are NOT allowed/, "name $_" );
    }

    # invalid record type
    for (qw/ blah x Y P Q R S TU VW XYZ 1 23/) {

        $res = $zr1->edit_zone_record(
            name    => "something",
            address => "1.2.3.4",
            type    => $_,
            ttl     => 86403,
        );
        sanity_error_ok( $res, qr/Invalid record type/, "type $_" );
    }

    for my $type (qw/ MX NS SRV /) {
        for my $address (
            qw( -blah -blah.something -
            something.-something /blah.something blah./something.com)
            )
        {

            # invalid address for type
            $res = $zr1->edit_zone_record(
                name    => "something",
                address => $address,
                type    => $type,
                ttl     => 86403,
                mx_srv_args($type),
            );
            noerrok( $res, 300, "type $type address $address" );
            ok( $res->get('error_msg') =~ qr/must point to a FQDN/,
                "edit_zone_record, $type, $address" );
            ok( $res->get('error_desc') =~ qr/Sanity error/, "edit_zone_record, $type, $address" );

            # invalid address for preset type
            $res = $zr1->edit_zone_record(
                type    => $type,
                address => 'fully.ok.name.',
                mx_srv_args($type),
            );
            noerrok($res);
            for (
                qw[ -blah -blah.something - something.-something /blah.something blah./something.com ]
                )
            {
                $res = $zr1->edit_zone_record( address => $address );
                noerrok( $res, 300, "type $type address $address" );
                ok( $res->get('error_msg') =~ qr/must point to a FQDN/,
                    "edit_zone_record, $type, $address" );
                ok( $res->get('error_desc') =~ qr/Sanity error/,
                    "edit_zone_record, $type, $address"
                );
            }
        }
    }

    # invalid address for type
    for my $type (qw/ MX NS SRV /) {
        for my $address (qw/ 1.2.3.4 5.1.2.8 5.1.2 a.b.c /) {

            $res = $zr1->edit_zone_record(
                name    => "something",
                address => $address,
                type    => $type,
                ttl     => 86403,
                mx_srv_args($type),
            );
            sanity_error_ok( $res, qr/must point to a FQDN/, "type $type address $address" );

            $res = $zr1->edit_zone_record(
                type    => $type,
                address => 'fully.ok.name.',
                mx_srv_args($type),
            );
            noerrok($res);

            #invalid address for preset type
            $res = $zr1->edit_zone_record( address => $address );
            sanity_error_ok( $res, qr/must point to a FQDN/, "type $type address $address" );
        }
    }

    # invalid IP address for A records
    my @bad_ipv4 = (
        qw/ 1.x.2.3 .1.2.3 0.0.0.0 1234.1.2.3 256.2.3.4  1.-.2.3 1.2.3 1.2
            1 1.2.3. -1.2.3.4/, '1. .3.4', '1.2,3.4', '1.,.3.4'
    );
    for my $address (@bad_ipv4) {

        $res = $zr1->edit_zone_record(
            name    => "something",
            address => $address,
            type    => 'A',
            ttl     => 86403,
        );
        sanity_error_ok(
            $res,
            qr/Address for A records must be a valid IP address/,
            "address $address"
        );
    }

    # invalid IP address for AAAA records
    for (qw/ abcd:efg1::1 1.2.3.4 200.200.200.200 /) {

        $res = $zr1->edit_zone_record(
            name    => "something",
            address => $_,
            type    => 'AAAA',
            ttl     => 86403,
        );
        sanity_error_ok( $res, qr/must be a valid IPv6 address/, "address $_" );
    }

    #invalid IP address for preset A record
    $res = $zr1->edit_zone_record( type => 'A', address => '1.2.3.4' );
    noerrok($res);

    for (@bad_ipv4) {
        sanity_error_ok(
            $zr1->edit_zone_record( address => $_ ),
            qr/Address for A records must be a valid IP address/,
            "address $_"
        );
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
    #   ok( $res->get('error_desc') =~ qr/Sanity error/ );

    #invalid ttl
    for (qw/ -1 -4 -299 2147483648 -2 /) {

        $res = $zr1->edit_zone_record(
            name    => "something",
            type    => 'A',
            address => '1.2.3.4',
            ttl     => $_,
        );
        sanity_error_ok( $res, qr/Invalid TTL/, "ttl $_" );
    }

    ####################
    # success tests    #
    ####################

    foreach (@success_tests) {
        edited_ok( $zr1, { record_args($_) }, @{$_}{qw/ name address type /} );
    }

    # SPF with shortcut expansion
    edited_ok( $zr1, { name => '@', address => 'v=spf1 mx a ip4:127.0.0.6 -all', type => 'SPF' },
        'test.com.', 'v=spf1 mx a ip4:127.0.0.6 -all', 'SPF' );

    # TXT with shortcut expansion
    edited_ok( $zr1, { name => '@', address => 'v=spf1 mx a ip4:127.0.0.6 -all', type => 'TXT' },
        'test.com.', 'v=spf1 mx a ip4:127.0.0.6 -all', 'TXT' );

    # AAAA with shortcut expansion
    edited_ok( $zr1, { name => 'www', address => '2001:db8::0001', type => 'AAAA' },
        'www', '2001:0db8:0000:0000:0000:0000:0000:0001', 'AAAA' );

    # multiple CNAMES with same name
    edited_ok( $zr1, { name => 'x', address => $fqdn, type => 'CNAME' }, 'x', $fqdn, 'CNAME' );

    $res = $zr2->edit_zone_record( name => 'x', address => $fqdn, type => 'CNAME' );
    sanity_error_ok(
        $res,
        qr/multiple CNAME records with the same name are NOT allowed/,
        'multiple CNAME records'
    );

    # CNAME conflict with A record
    edited_ok( $zr1, { name => 'x', address => '1.2.3.4', type => 'A' }, 'x', '1.2.3.4', 'A' );

    $res = $zr2->edit_zone_record( name => 'x', address => $fqdn, type => 'CNAME' );
    sanity_error_ok(
        $res,
        qr/record x already exists within zone as an/,
        'CNAME conflict with A records'
    );

    # A conflict with CNAME record
    edited_ok( $zr1, { name => 'x', address => 'abc.defg.com.', type => 'CNAME' },
        'x', 'abc.defg.com.', 'CNAME' );

    $res = $zr2->edit_zone_record( name => 'x', address => '1.2.3.4', type => 'A' );
    sanity_error_ok(
        $res,
        qr/record x already exists within zone as an Alias \(CNAME\) record/,
        'A conflict with CNAME records'
    );

    # conflicting sub-zones and records
    $res = $group1->new_zone( zone => 'sub.test.com' );
    noerrok($res);
    $t = $res->get('nt_zone_id');

    $res = $zr1->edit_zone_record(
        name    => 'sub',
        address => '1.2.3.4',
        type    => 'A',
    );
    sanity_error_ok(
        $res,
        qr/Cannot create\/edit Record .*: it conflicts with existing zone/,
        "record conflicts with subzone"
    );

    $res = $zr1->edit_zone_record(
        name    => 'sub.sub',
        address => '1.2.3.4',
        type    => 'A',
    );
    sanity_error_ok(
        $res,
        qr/Cannot create\/edit Record .*: it conflicts with existing zone/,
        "record conflicts with subzone"
    );

    $res = $user->delete_zones( zone_list => $t );
    noerrok($res);

    ####################
    # delete_zone_record
    ####################

    bad_id_ok( 'nt_zone_record_id',
        sub { $user->delete_zone_record( nt_zone_record_id => shift ) } );

    ####################
    # get_record_type
    ####################

    $res = $user->get_record_type( type => 'ALL' );
    noerrok($res);

    #warn Data::Dumper::Dumper($res);
}

sub record_args {
    my ($test) = @_;
    return (
        name    => $test->{name},
        address => $test->{address},
        type    => $test->{type},
        map { defined $test->{$_} ? ( $_ => $test->{$_} ) : () } qw/ ttl weight priority other /
    );
}

sub mx_srv_args {
    my ($type) = @_;
    return (
        ( ( $type eq 'MX' || $type eq 'SRV' ) ? ( weight   => 1 ) : () ),
        ( $type eq 'SRV'                      ? ( priority => 1 ) : () ),
        ( $type eq 'SRV'                      ? ( other    => 1 ) : () ),
    );
}

sub edited_ok {
    my ( $zr, $args, $name, $address, $type ) = @_;
    noerrok( $zr->edit_zone_record(%$args) );
    $zr->refresh;
    is( $zr->get('name'),    $name );
    is( $zr->get('address'), $address );
    is( $zr->get('type'),    $type );
}

sub delete_if_created {
    my ($res) = @_;
    $user->delete_zone_record( nt_zone_record_id => $res->{'nt_zone_record_id'} )
        if !$res->is_error;
}

sub del {

    for (
        [ $zrid2, 'delete_zone_record', nt_zone_record_id => 'zone record 2' ],
        [ $zrid1, 'delete_zone_record', nt_zone_record_id => 'zone record 1' ],
        [ $zid1,  'delete_zones',       zone_list         => 'zone 1' ],
        [ $zid2,  'delete_zones',       zone_list         => 'zone 2' ],
        [ $nsid1, 'delete_nameserver',  nt_nameserver_id  => 'nameserver1' ],
        [ $nsid2, 'delete_nameserver',  nt_nameserver_id  => 'nameserver2' ],
        [ $gid1,  'delete_group',       nt_group_id       => 'group1' ],
        [ $gid2,  'delete_group',       nt_group_id       => 'group2' ],
        )
    {
        my ( $id, $call, $param, $label ) = @$_;
        if ( !defined $id ) {
            is( 1, 0, "Couldn't delete test $label" );
            next;
        }
        $res = $user->$call( $param => $id );
        next                            if noerrok($res);
        warn Data::Dumper::Dumper($res) if $call ne 'delete_group';
    }
}
