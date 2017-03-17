# NicTool v2.27 Copyright 2014 The Network People, Inc.
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

# use lib '.';
use lib 't';
use lib 'lib';
use Data::Dumper;
use NicToolTest;
use NicToolServer::Export::tinydns;
use Test::More;
$Data::Dumper::Sortkeys=1;

my $nsid = 0;

my $tinydns = NicToolServer::Export::tinydns->new();
isa_ok($tinydns, 'NicToolServer::Export::tinydns');

my $r;

test_pack_hex();
test_escape();
test_escapeNumber();
test_characterCount();
test_zr_spf();

done_testing();
exit;

sub test_pack_hex {
    my %tests = (
        '0' => '\000',
        '9' => '\011',
        'A' => '\012',
        'a' => '\012',
        'f' => '\017',
    );

    foreach my $char (sort keys %tests) {
        my $r = $tinydns->pack_hex($char);
        cmp_ok($r, 'eq', $tests{$char}, "pack_hex: $char -> $r");
    }
}

sub test_escape {
    my %tests = (
        ':' => '\072',
        '\\' => '\134',
        'a' => 'a',
        '0' => '0',
        '#' => '#',
    );

    foreach my $char (sort keys %tests) {
        my $r = $tinydns->escape($char);
        cmp_ok($r, 'eq', $tests{$char}, "escape: $char -> $r");
    }
}

sub test_escapeNumber {
    my %tests = (
        '0' => '\000\000',
        '65535' => '\377\377',
    );

    foreach my $num (sort keys %tests) {
        my $r = $tinydns->escapeNumber($num);
        cmp_ok($r, 'eq', $tests{$num}, "escapeNumber: $num -> $r");
    }
}

sub test_zr_spf {
    cmp_ok(
        $tinydns->zr_spf({
            name => 'example.net',
            address => 'v=spf1 include:_spf.google.com ~all',
            ttl => 86400,
        }),
        'eq',
        ':example.net:99:\043v=spf1 include\072_spf.google.com ~all:86400::
',
        'SPF record'
    );

    cmp_ok(
        $tinydns->zr_spf({
            name => 'example.net',
            address => "v=spf1 mx ip4:195.69.128.111 ip4:64.106.174.60 ip4:64.106.174.62 ip4:94.231.108.35 ip4:94.231.109.44 ip4:158.36.191.0/25 ip4:18 8.180.92.15 ip4:188.180.92.200 ip4:193.111.162.0/24 include:spf.example.net include:spf.protection.outlook.com include:spf.comendosystems.com ip4:94.231.107.21 ip4:94.231.107.22 ip4:94.231.107.23 ip4:94.231.107.24 ip4:94.231.107.25 ip4:94.231.107.26 ip4:94.231.107.28 ip4:94.231.107.29 ip4:94.231.107.220 ip4:94.231.107.221 ip4:85.191.122.238 ip4:85.191.122.249 ip4:85.191.122.250 ip4:93.191.155.22 ip4:93.191.155.203 ip4:93.191.155.224 ip4:158.69.117.38 ip4:158.69.117.37 ip4:89.234.13.177 ip4:93.91.20.9 ip 4:93.91.20.10 ip4:140.78.3.65 ip4:132.212.11.48 ip4:132.205.7.81 ip4:132.205.1.11 ip4:132.205.122.20 ip4:140.77.51.2 include:mail.example.com -all"
        }),
        'eq',
        ':example.net:99:\377v=spf1 mx ip4\072195.69.128.111 ip4\07264.106.174.60 ip4\07264.106.174.62 ip4\07294.231.108.35 ip4\07294.231.109.44 ip4\072158.36.191.0\05725 ip4\07218 8.180.92.15 ip4\072188.180.92.200 ip4\072193.111.162.0\05724 include\072spf.example.net include\072spf.protection.outlook.com include\072spf.come\377ndosystems.com ip4\07294.231.107.21 ip4\07294.231.107.22 ip4\07294.231.107.23 ip4\07294.231.107.24 ip4\07294.231.107.25 ip4\07294.231.107.26 ip4\07294.231.107.28 ip4\07294.231.107.29 ip4\07294.231.107.220 ip4\07294.231.107.221 ip4\07285.191.122.238 ip4\07285.191.122.249 ip4\07285.191.122.250 i\377p4\07293.191.155.22 ip4\07293.191.155.203 ip4\07293.191.155.224 ip4\072158.69.117.38 ip4\072158.69.117.37 ip4\07289.234.13.177 ip4\07293.91.20.9 ip 4\07293.91.20.10 ip4\072140.78.3.65 ip4\072132.212.11.48 ip4\072132.205.7.81 ip4\072132.205.1.11 ip4\072132.205.122.20 ip4\072140.77.51.2 include\072mai\022l.example.com -all:::
', 'multi-string (longer than 255 bytes) SPF'
    );
}

sub test_characterCount {
    cmp_ok( $tinydns->characterCount("1234567890"), 'eq', '\012', 'characterCount, 1234567890');
    cmp_ok( $tinydns->characterCount("a"), 'eq', '\001', 'characterCount, a');
};
