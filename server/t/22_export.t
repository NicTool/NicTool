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
use Test::Output;
$Data::Dumper::Sortkeys=1;

my $nsid = 0;
my $export = NicToolServer::Export->new( ns_id=>$nsid );
isa_ok( $export, 'NicToolServer::Export');

my $r;
# the tinydns exports need RR type mappings
my $types = _get_rr_types();
while ((my $key, my $val) = each %$types ) {
    $export->{rr_type_map}{ids}{ $key } = $val;
    $export->{rr_type_map}{names}{ $val } = $key;
};

#done_testing();
#exit;

# TODO: specify NS type when loading, so we can run these NS specific tests
$export->load_export_class();

#print "r: $r\n";
#_tests_that_require_db();
_is_ip_port();
_zr_nsec();
_zr_rrsig();
_aaaa_to_ptr();
_datestamp_to_int();
_zr_nsec3();
_zr_nsec3param();
_zr_ipseckey();
_get_export_data_dir();

done_testing() and exit;

# Test::More doesn't like the output of these, and I'm not sure why
# TODO: fix this Nov 18, 2011 - mps
ok( $export->preflight, 'preflight');  # check if export can succeed

ok( $export->export(), "export (nsid $nsid)");

sub _tests_that_require_db {
    $export->get_dbh(
        dsn  => Config('dsn'),
        user => Config('db_user'),
        pass => Config('db_pass'),
    );

    my $count = $export->get_modified_zones_count();
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

#   $r = $export->get_last_ns_export();
#   ok( $r, "get_last_ns_export, $nsid");
#   warn Data::Dumper::Dumper($r);

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

};

sub _is_ip_port {
    my @out_of_range = qw/ -100 -1 65536 1000000 /;
    my @good_ports = qw/ 0 1 53 995 65535 /;

    foreach ( @good_ports ) {
        my $r = $export->is_ip_port($_);
        ok(defined $r, "is_ip_port, valid, $_");
    };
    stderr_like { $export->is_ip_port('') } qr/empty/, "is_ip_port, empty";
    stderr_like { $export->is_ip_port() } qr/not defined/, "is_ip_port, undefined";
    stderr_like { $export->is_ip_port('a') } qr/non-numeric/, "is_ip_port, a";
    foreach ( @out_of_range ) {
	stderr_like { $export->is_ip_port($_) } qr/range/, "is_ip_port, out of range, $_";
    };
};

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
    cmp_ok( $r, 'eq', ':localhost.simerson.com.:46:\000\001\005\003\000\001Q\213Q\321A\323QZ\232\323\313g\010simerson\003com\000\220\133\227\057l\023\221\140\373\005\213t\307w\271\032Fk\273\231\202\235\375\100\232\100a\136\216\301\001\043\047\221\025\242\322\032\032\100\244\072\3628U\236O\223y\327\275\265\263\342\020\030\035\200\351\173.C\214\001\333g\007\052\014u\314\325\362D\340E\303\100\346u\241\266\327\323\371\176\345\075\343\227\237h\240.\350\244\355\307\262X\174\226\210\050\136\017\074\217\134\010\047\265\306PX\245\025\014\220\204\253\240\316\324\201\016\301aQ\002\005\230\240i\327T\323Z\051c\364\042\032\072\011\045\356\214\257\045\275\027\100-\217\226cz\272\320d\301\047\012\053D\202\051\353\021\031\133rdn\365\133\012\0522\006o\025C\232\357F7\3553J\356\340\140\002l\312s\345\213\040k\266\311Y\232\035li9\304De\134\261\216\211\221y\177\137\263\201d\177\212\012\050\252\303\357\031\042\100\134\362\372\100\040\341\237\245\174r\212\026F\330\233\330\362\353\201\327\261\033:86400::
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
sub _datestamp_to_int {
    $r = $export->{export_class}->datestamp_to_int( '20130401101010' );
    cmp_ok( $r, '==', 1364811010, "datestamp_to_int, $r");

    $r = $export->{export_class}->expand_aaaa( '2607:f060:b008:feed::6' );
    cmp_ok( $r, 'eq', '2607:f060:b008:feed:0000:0000:0000:0006', 'expand_aaaa');
#print "r: $r\n";
};

sub _aaaa_to_ptr {

    $r = $export->{export_class}->aaaa_to_ptr( {
        address    => '2607:f060:b008:feed::6',
        name       => 'ns2.cadillac.net.',
        ttl        => 86400,
        timestamp  => '',
        location   => '',
        } );

    cmp_ok( $r, 'eq', '^6.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.d.e.e.f.8.0.0.b.0.6.0.f.7.0.6.2.ip6.arpa.:ns2.cadillac.net.:86400::
', 'aaaa_to_ptr');
};

sub _zr_nsec3 {
    $r = $export->{export_class}->zr_nsec3( {
        name      => 'nsec3.simerson.com.',
        address   => '1 1 12 aabbccdd ( 2t7b4g4vsa5smi47k61mv5bv1a22bojr MX DNSKEY NS SOA NSEC3PARAM RRSIG )',
        description => '(A RRSIG NSEC)',
        ttl       => '86400',
        timestamp => '',
        location  => '',
    } );
    cmp_ok( $r, 'eq', ':nsec3.simerson.com.:50:\001\001\000\014\004\252\273\314\335\024\027N\262\100\237\342\213\313H\207\241\203o\225\177\012\204\045\342\173\000\007\042\001\000\000\000\002\220:86400::
', 'zr_nsec3');

};

sub _zr_ipseckey {
    $r = $export->{export_class}->zr_ipseckey( {
        name      => 'ipsec.simerson.com.',
        weight    => 1,    # precedence
        priority  => 3,    # gateway type
        other     => 2,    # algorithm
        address   => 'matt.simerson.net.',  # gateway
        description => '0sAQPeOwAGDPLrDebL1q5Lg8XW9B/d9MnxqlzIYKXhvZPWEHNYGP7AwA RT/tmkeDNn7HPMtgM6GIwQ4p0KGLfSRoUKbjtPlRVeWYLbsnNXeFU5bc hyYef0efYiKlxZdo',   # public key
        ttl       => '86400',
        timestamp => '',
        location  => '',
    } );
    cmp_ok( $r, 'eq', ':ipsec.simerson.com.:45:\001\003\002\004matt\010simerson\003net\000\322\300\020\075\343\260\000\140\317.\260\336l\275j\344\270\074\135oA\375\337L\237\032\245\314\206\012\136\033\331\075a\0075\201\217\354\014\000E\077\355\232G\2036\176\307\074\313\1403\241\210\301\016\051\320\241\213\175\044hP\246\343\264\371QU\345\230-\273\0475w\205S\226\334\207\046\036\177G\237b\042\245\305\227h:86400::
', 'zr_ipseckey');

};

sub _zr_nsec3param {
    $r = $export->{export_class}->zr_nsec3param( {
        name      => 'nsec3param.simerson.com.',
        address   => '1 1 12 aabbccdd 2t7b4g4vsa5smi47k61mv5bv1a22bojr',
        description => '',
        ttl       => '86400',
        timestamp => '',
        location  => '',
    } );
    cmp_ok( $r, 'eq', ':nsec3param.simerson.com.:51:\001\001\000\014\004\252\273\314\335:86400::
', 'zr_nsec3param');

};

sub _get_rr_types {
    return {
        1 => 'A',
        2 => 'NS',
        5 => 'CNAME',
        6 => 'SOA',
        12 => 'PTR',
        15 => 'MX',
        16 => 'TXT',
        24 => 'SIG',
        25 => 'KEY',
        28 => 'AAAA',
        29 => 'LOC',
        30 => 'NXT',
        33 => 'SRV',
        35 => 'NAPTR',
        39 => 'DNAME',
        43 => 'DS',
        44 => 'SSHFP',
        46 => 'RRSIG',
        47 => 'NSEC',
        48 => 'DNSKEY',
        50 => 'NSEC3',
        51 => 'NSEC3PARAM',
        99 => 'SPF',
        250 => 'TSIG',
        252 => 'AXFR',
    };
};

sub _get_export_data_dir {

    $export->{ns_ref}{datadir} = undef;
    $r = $export->get_export_data_dir();
    ok(!$r, 'get_export_data_dir, undef');

    $export->{ns_ref}{datadir} = '/etc/named';
    $r = $export->get_export_data_dir();
    ok($r eq '/etc/named', "get_export_data_dir, $r");

    $export->{ns_ref}{datadir} = '/etc/named/';
    $r = $export->get_export_data_dir();
    ok($r eq '/etc/named', "get_export_data_dir, w/trailing slash, $r");
}
