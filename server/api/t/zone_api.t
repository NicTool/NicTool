use strict;
use warnings;
use lib 'lib';

use Test::More;
use NicTool::Zone;

my $api = NicTool::Zone->_api;

for my $method (qw/ edit_zone_delegation delete_zone_delegation /) {
    ok( $api->{$method}{includeid}, "$method supplies the zone's nt_zone_id" );
    ok( !$api->{$method}{include}, "$method leaves nt_group_id to the caller" );
}

is_deeply( $api->{new_group}, { include => ['nt_group_id'] },
    'new_group takes the zone group, like the other group functions' );

done_testing();
