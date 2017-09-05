# NicTool v2.24 Copyright 2014 The Network People, Inc.
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
use Test::More;
use_ok('NicToolServer::Import::Base');

$Data::Dumper::Sortkeys=1;

my $base = NicToolServer::Import::Base->new();
ok($base, "new");

my $get_zone_tests = {
    'host.example.com'  => 'example.com',
    'host.example.com.' => 'example.com',
    'www.bbc.co.uk'     => 'bbc.co.uk',
    'www.bbc.co.uk.'    => 'bbc.co.uk',
};

foreach my $fqdn ( keys %$get_zone_tests ) {
    cmp_ok($base->get_zone($fqdn), 'eq', $get_zone_tests->{$fqdn}, "$fqdn");
};

done_testing();
