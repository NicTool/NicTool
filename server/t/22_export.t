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
my $count = $export->get_modified_zones();

isa_ok( $export, 'NicToolServer::Export');
ok( defined $count, "found $count zones");

done_testing();
exit;

# Test::More doesn't like the output of these, and I'm not sure why
# TODO: fix this Nov 18, 2011 - mps
ok( $export->preflight, 'preflight');  # check if export can succeed

ok( $export->export(), "export (nsid $nsid)");

#warn Dumper($r);
exit;

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

#warn Data::Dumper::Dumper($r);

