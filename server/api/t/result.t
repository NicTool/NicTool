##########
# test NicTool::Result class
##########

use Test;
BEGIN { plan tests => 14 }

use NicTool::Result;
ok(1);

#test default settings
my $nt = new NicTool::Result( {} );
ok( ref $nt,         'NicTool::Result' );
ok( $nt->type,       'Result' );
ok( $nt->error_code, '200' );
ok( $nt->error_msg,  'OK' );
ok( !$nt->is_error );

#test initialization with error settings
$nt = new NicTool::Result( {}, error_code => 700, error_msg => 'Some Error' );
ok( $nt->error_code, 700 );
ok( $nt->error_msg,  'Some Error' );
ok( $nt->is_error );

#test initialization with other values
$nt = new NicTool::Result( {}, { 'test' => [ 'some', 'array' ] } );
ok( $nt->error_code, 200 );
ok( $nt->error_msg,  'OK' );
ok( !$nt->is_error );
ok( $nt->has('test') );
ok( ref $nt->get('test'), 'ARRAY' );

