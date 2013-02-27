##########
# test using the protocol version
##########

use lib 'lib';
use lib 't';
use TestConfig (15);
use Test;
use NicTool;
ok(1);

my $user = new NicTool(
    data_protocol        => Config('data_protocol'),
    server_host          => Config('server_host'),
    server_port          => Config('server_port'),
    use_protocol_version => 1
);
ok( ref $user, 'NicTool' );

#login
$user->login(
    username => Config('username'),
    password => Config('password')
);
ok( !$user->result->is_error );
if ( $user->result->is_error ) {
    die "Error logging in: ("
        . $user->result->error_code . ") "
        . $user->result->error_msg;
}

ok( $user->nt_user_session );
my $session = $user->nt_user_session;

#verify session
$user->verify_session;
ok( !$user->result->is_error );
ok( $user->result->get('nt_user_session') => $session );

#logout
$user->logout;
ok( !$user->result->is_error );

#no more session
$user->verify_session;
ok( $user->result->is_error );
ok( $user->result->error_code => 403 );    # session has expired

#now give some bogus protocol version
$user->config( nt_protocol_version => 'XXX' );    #larger than any number
$user->login(
    username => Config('username'),
    password => Config('password')
);
ok( $user->result->is_error );
ok( $user->result->error_code, 510 );
ok( $user->result->error_msg =~ /at most protocol version/ );

#print "Error logging in: (".$user->result->error_code.") ".$user->result->error_msg;

#now give some bogus protocol version
$user->config( nt_protocol_version => '-' );      #smaller than any number
$user->login(
    username => Config('username'),
    password => Config('password')
);
ok( $user->result->is_error );
ok( $user->result->error_code, 510 );
ok( $user->result->error_msg =~ /at least protocol version/ );

#print "Error logging in: (".$user->result->error_code.") ".$user->result->error_msg;
