# NicTool v2.10 Copyright 2011 The Network People, Inc.
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

use strict;
use warnings;

use lib '.';
use lib 't';
use lib 'lib';
use Data::Dumper;
use NicToolTest;
use NicToolServer::Export;
use Test::More;
$Data::Dumper::Sortkeys=1;

my $nsid = 0;
my $export = NicToolServer::Export->new( ns_id=>$nsid );
$export->get_dbh(
    dsn  => Config('dsn'),
    user => Config('db_user'),
    pass => Config('db_pass'),
);

my $r;
my $count = $export->get_modified_zones_count();

isa_ok( $export, 'NicToolServer::Export');
ok( defined $count, "found $count zones");

my $types = $export->get_rr_types();
ok( $types, 'get_rr_types' );
#print Dumper($types);

cmp_ok( $export->get_rr_id('A'), '==', 1, 'get_rr_id');
cmp_ok( $export->get_rr_id('NS'), '==', 2, 'get_rr_id');

cmp_ok( $export->get_rr_name(1), 'eq', 'A', 'get_rr_name');
cmp_ok( $export->get_rr_name(2), 'eq', 'NS', 'get_rr_name');

# this will get all zones, since we haven't given it a 'since' time
$r = $export->get_modified_zones_count();
ok( defined $r, "get_modified_zones_count, $r");

my @bad_ports = qw/ -100 -1 65536 1000000 a /;
my @good_ports = qw/ 1 53 995 65535 /;

foreach ( @bad_ports ) {
    ok( ! $export->is_ip_port($_), "is_ip_port, invalid, $_");
};
foreach ( @good_ports ) {
    ok( $export->is_ip_port($_), "is_ip_port, valid, $_");
};

done_testing() and exit;

# TODO: specify NS type when loading, so we can run these NS specific tests
$export->load_export_class();
$r = $export->{export_class}->datestamp_to_int( '20130401101010' );
cmp_ok( $r, '==', 1364811010, "datestamp_to_int, $r");

$r = $export->{export_class}->expand_aaaa( '2607:f060:b008:feed::6' );
cmp_ok( $r, 'eq', '2607:f060:b008:feed:0000:0000:0000:0006', 'expand_aaaa');
#print "r: $r\n";

$r = $export->{export_class}->aaaa_to_ptr( {
    address    => $r,
    name       => 'ns2.cadillac.net.',
    ttl        => 86400,
    timestamp  => '',
    location   => '',
    } );
cmp_ok( $r, 'eq', '^6.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.d.e.e.f.8.0.0.b.0.6.0.f.7.0.6.2.ip6.arpa.:ns2.cadillac.net.:86400::
', 'aaaa_to_ptr');

#print "r: $r\n";
#_zr_nsec();
#_zr_rrsig();

done_testing() and exit;

#$r = $export->get_last_ns_export();
#ok( $r, "get_last_ns_export, $nsid");
#warn Data::Dumper::Dumper($r);
#exit;

#my $logid = $export->get_log_id( success=>1 );
#$logid = $export->get_log_id( success=>1,partial=>1 );

$r = $export->get_last_ns_export( success=>1 );
ok( $r, "get_last_ns_export, $nsid, success");
#warn Data::Dumper::Dumper($r);

$r = $export->get_last_ns_export( success=>1, partial=>1 );
ok( $r, "get_last_ns_export, nsid $nsid, success, partial");
#warn Data::Dumper::Dumper($r);

#$r = $export->get_zone_list( ns_id=> 0 );
#$r = $export->get_zone_list( ns_id=> $nsid );
#ok( $r, "export ($nsid), ".scalar @$r." zones");
#warn Data::Dumper::Dumper($r);
#exit;

# Test::More doesn't like the output of these, and I'm not sure why
# TODO: fix this Nov 18, 2011 - mps
ok( $export->preflight, 'preflight');  # check if export can succeed

ok( $export->export(), "export (nsid $nsid)");

sub _zr_rrsig {
    $r = $export->{export_class}->zr_rrsig( {
        name      => 'localhost.simerson.com.',
        address   => 'A 5 3 86411 20130701084611 ( 20130402084611 52071 simerson.com. kFuXL2wTkWD7BYt0x3e5GkZru5mCnf1
        AmkBh Xo7BASMnkRWi0hoaQKQ68jhVnk+Tede9tbPi EBgdg
        Ol7LkOMAdtnByoMdczV8kTgRcNA5nWh ttfT+X7lPeOXn2ig
        Luik7ceyWHyWiCheDzyP XAgntcZQWKUVDJCEq6DO1IEOwWF
        RAgWYoGnX VNNaKWP0Iho6CSXujK8lvRdALY+WY3q60GTB J
        worRIIp6xEZW3JkbvVbCioyBm8VQ5rvRjft M0ru4GACbMpz
        5Ysga7bJWZodbGk5xERlXLGO iZF5f1+zgWR/igooqsPvGSJ
        AXPL6QCDhn6V8cooWRtib2PLrgdexGw== )',
        description => '',
        ttl       => '86400',
        timestamp => '',
        location  => '',
    } );
    cmp_ok( $r, 'eq', 'A 5 3 86411 20130701084611 20130402084611 52071 simerson.com. kFuXL2wTkWD7BYt0x3e5GkZru5mCnf1AmkBhXo7BASMnkRWi0hoaQKQ68jhVnk+Tede9tbPiEBgdgOl7LkOMAdtnByoMdczV8kTgRcNA5nWhttfT+X7lPeOXn2igLuik7ceyWHyWiCheDzyPXAgntcZQWKUVDJCEq6DO1IEOwWFRAgWYoGnXVNNaKWP0Iho6CSXujK8lvRdALY+WY3q60GTBJworRIIp6xEZW3JkbvVbCioyBm8VQ5rvRjftM0ru4GACbMpz5Ysga7bJWZodbGk5xERlXLGOiZF5f1+zgWR/igooqsPvGSJAXPL6QCDhn6V8cooWRtib2PLrgdexGw==
', 'zr_rrsig');
};

sub _zr_nsec {
    $r = $export->{export_class}->zr_nsec( {
        name      => 'localhost.simerson.com.',
        address   => 'mbp-hires.simerson.com.',
        description => '(A RRSIG NSEC)',
        ttl       => '86400',
        timestamp => '',
        location  => '',
    } );
    cmp_ok( $r, 'eq', ':localhost.simerson.com.:47:\011mbp-hires\010simerson\003com\000\000\006\100\000\000\000\000\003:86400::
    ', 'zr_nsec');

    $r = $export->{export_class}->zr_nsec( {
        name      => 'localhost.simerson.com.',
        address   => 'mbp-hires.simerson.com.',
        description => 'A RRSIG NSEC',
        ttl       => '86400',
        timestamp => '',
        location  => '',
    } );
    cmp_ok( $r, 'eq', ':localhost.simerson.com.:47:\011mbp-hires\010simerson\003com\000\000\006\100\000\000\000\000\003:86400::
    ', 'zr_nsec');
    print $r;
};
