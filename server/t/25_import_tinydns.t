# NicTool v2.29 Copyright 2014 The Network People, Inc.
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
use Test::More;
use_ok('NicToolServer::Import::tinydns');
$Data::Dumper::Sortkeys=1;

my $tinydns = NicToolServer::Import::tinydns->new();
ok($tinydns, "new");

my $r = $tinydns->ip_to_ptr('10.0.1.2');
cmp_ok($r, 'eq', '2.1.0.10.in-addr.arpa.', "ip_to_ptr: $r");

my $genericTests = [
    {
        raw => ':domain.com:16:\041abcd\072abcd\072abcd\072abcd\072abcd\072abcd\072123:',
        after => ':domain.com:abcd\072abcd\072abcd\072abcd\072abcd\072abcd\072123:',
    },
];

foreach my $test ( @$genericTests ) {

    my $before = $test->{'raw'};
    # $before =~ s/:16:/:/;
    $before =~ s/:16:\\[\d]{3,}/:/;
    cmp_ok($before, 'eq', $test->{'after'}, 'generic: ' . $test->{raw});
}

test_unescape_octal();
test_unescape_packed_hex();

done_testing();


sub test_unescape_octal {
    my %escaped_octal = (
        'v=DMARC1; p=reject; rua=mailto\072dmarc@foo.com; ruf=mailto\072dmarc@foo.com; pct=100'
        => 'v=DMARC1; p=reject; rua=mailto:dmarc@foo.com; ruf=mailto:dmarc@foo.com; pct=100',
    );

    foreach my $oct ( keys %escaped_octal ) {
        my $r = $tinydns->unescape_octal( $oct );
        cmp_ok($r, 'eq', $escaped_octal{$oct}, "unescape_oct, $oct");
    };
}

sub test_unescape_packed_hex {

    my %packed_hex = (
        '\040\001\005\000\000\220\000\001\000\000\000\000\000\000\000\022' =>
            '2001:0500:0090:0001:0000:0000:0000:0012',
        '\046\007\360\140\260\010\376\355\000\000\000\000\000\000\000\006' =>
            '2607:f060:b008:feed:0000:0000:0000:0006',
        '&\007\360\140\260\010\376\355\000\000\000\000\000\000\000\006' =>
            '2607:f060:b008:feed:0000:0000:0000:0006',
    );

    foreach my $hex ( sort keys %packed_hex ) {
        my $r = $tinydns->unescape_packed_hex( $hex );
        cmp_ok($r, 'eq', $packed_hex{$hex}, "unescape_packed_hex, $hex");
    };
}
