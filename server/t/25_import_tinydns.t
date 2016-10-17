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
        foo => ':domain.com:abcd\072abcd\072abcd\072abcd\072abcd\072abcd\072123:',
    },
];

foreach my $test ( @$genericTests ) {

    my $before = $test->{'raw'};
    # $before =~ s/:16:/:/;
    $before =~ s/:16:\\[\d]{3,}/:/;
    cmp_ok($before, 'eq', $test->{'foo'}, 'generic: ' . $test->{raw});
}

done_testing();
