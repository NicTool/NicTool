use strict;
use warnings;
use lib 'lib';

use Test::More;
use NicTool;

my $nt = NicTool->new;

for my $call (qw/ get_user_global_log get_global_application_log get_group_zones_log get_zone_record_log /) {
    is( NicTool::API->result_type($call), 'Log', "$call returns a Log" );
}

my $log = $nt->_object_for_type( 'Log', error_code => 200, total => 1, log => [ { action => 'added' } ] );
isa_ok( $log, 'NicTool::Log' );
isa_ok( $log, 'NicTool::Result' );
is( $log->error_code,             200,     'error_code' );
is( $log->get('total'),           1,       'total' );
is( $log->get('log')->[0]{action}, 'added', 'log rows' );

done_testing();
