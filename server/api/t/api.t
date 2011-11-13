##########
##########
# api.t
# test the NicTool::API class
##########

use Test;
BEGIN { plan tests => 10 }

use NicTool::API;
ok(1);

#result_type is the type of the resulting object
my $res = NicTool::API->result_type('login');
ok( $res => 'User' );

$res = NicTool::API->result_is_list('login');
ok( !$res );

$res = NicTool::API->result_is_list('get_zone_record_delegates');
ok($res);

$res = NicTool::API->result_list_param('login');
ok( !$res );

$res = NicTool::API->result_list_param('get_zone_record_delegates');
ok( $res => 'delegates' );

$res = NicTool::API->param_access( 'get_zone_record_delegates',
    'nt_zone_record_id' );
ok( $res => 'read' );

$res = NicTool::API->param_list( 'get_zone_record_delegates',
    'nt_zone_record_id' );
ok( !$res );

$res = NicTool::API->param_type( 'get_zone_record_delegates',
    'nt_zone_record_id' );
ok( $res => 'ZONERECORD' );

$res = NicTool::API->param_required( 'get_zone_record_delegates',
    'nt_zone_record_id' );
ok($res);

