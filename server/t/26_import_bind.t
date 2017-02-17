# NicTool v2.33 Copyright 2015 The Network People, Inc.
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
use_ok('NicToolServer::Import::BIND');
$Data::Dumper::Sortkeys=1;

my $bind = NicToolServer::Import::BIND->new();
ok($bind, 'new');

# TODO: create a test group, import test zones into that group, validate imports, then clean up
#$bind->import_records('t/fixtures/named.conf');

done_testing();
