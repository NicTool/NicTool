##########
##########
# transport.t
# see that transport protocol loading works
##########

use lib 't';
use TestConfig (5);
use Test;
use NicTool;
ok(1);
my $user;
$user = new NicTool(
    data_protocol => 'croap',
    server_host   => Config('server_host'),
    server_port   => Config('server_port')
);
eval {
    $user->login( username => 'root', password => Config('rootpassword') );
};
ok( $@
        =~ /Unable to use class NicTool::Transport::CROAP for data protocol 'croap'/
);

$user = new NicTool(
    data_protocol => Config('data_protocol'),
    server_host   => Config('server_host'),
    server_port   => Config('server_port')
);
eval {
    $user->login( username => 'root', password => Config('rootpassword') );
};
ok( !$@ );
ok( $user->{'transport'} );
my $t = uc( Config('data_protocol') );
$t =~ s/_//g;
ok( ref $user->{'transport'} => "NicTool::Transport::$t" );

