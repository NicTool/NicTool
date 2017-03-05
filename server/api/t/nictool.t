##########
# test some of the actual nictool calls
##########

use lib 't';
use TestConfig (41);
use Test;
use NicTool;

my $user = new NicTool(
    data_protocol => Config('data_protocol'),
    server_host   => Config('server_host'),
    server_port   => Config('server_port')
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

#make sure appropriate fields are there
ok( exists $user->user->{'store'}->{'first_name'} );
ok( exists $user->user->{'store'}->{'last_name'} );
ok( exists $user->user->{'store'}->{'username'} );
ok( exists $user->user->{'store'}->{'nt_user_id'} );
ok( exists $user->user->{'store'}->{'nt_group_id'} );
ok( exists $user->user->{'store'}->{'groupname'} );
ok( exists $user->user->{'store'}->{'email'} );
ok( exists $user->user->{'store'}->{'zone_create'} );
ok( exists $user->user->{'store'}->{'zone_write'} );
ok( exists $user->user->{'store'}->{'zone_delete'} );
ok( exists $user->user->{'store'}->{'zone_delegate'} );
ok( exists $user->user->{'store'}->{'group_create'} );
ok( exists $user->user->{'store'}->{'group_write'} );
ok( exists $user->user->{'store'}->{'group_delete'} );
ok( exists $user->user->{'store'}->{'zonerecord_create'} );
ok( exists $user->user->{'store'}->{'zonerecord_write'} );
ok( exists $user->user->{'store'}->{'zonerecord_delete'} );
ok( exists $user->user->{'store'}->{'zonerecord_delegate'} );
ok( exists $user->user->{'store'}->{'nameserver_create'} );
ok( exists $user->user->{'store'}->{'nameserver_write'} );
ok( exists $user->user->{'store'}->{'nameserver_delete'} );
ok( exists $user->user->{'store'}->{'user_create'} );
ok( exists $user->user->{'store'}->{'user_write'} );
ok( exists $user->user->{'store'}->{'user_delete'} );
ok( exists $user->user->{'store'}->{'usable_ns'} );

#test permissions shortcut calls
ok( !$user->can_zone_barf );

#get a list of the zones in this group
my $zonelist = $user->get_group->get_group_zones;
ok( ref $zonelist,   'NicTool::List' );
ok( $zonelist->size, scalar $zonelist->list );

#get a list of subgroups
my $sublist = $user->get_group->get_group_subgroups;
ok( ref $sublist,   'NicTool::List' );
ok( $sublist->size, scalar $sublist->list );

#get user's group
my $group = $user->get_group;
ok( ref $group, 'NicTool::Group' );

#verify name and ID are the same
ok( $group->id          => $user->get('nt_group_id') );
ok( $group->get('name') => $user->get('groupname') );

#logout
$user->logout;
ok( !$user->result->is_error );

#no more session
$user->verify_session;
ok( $user->result->is_error );
ok( $user->result->error_code => 403 );    # session has expired
