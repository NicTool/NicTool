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

_characterCount();

done_testing();
exit;

sub _characterCount {
    cmp_ok( $tinydns->characterCount("1234567890"), 'eq', '\012', 'characterCount, 1234567890');
    cmp_ok( $tinydns->characterCount("a"), 'eq', '\001', 'characterCount, a');
};

