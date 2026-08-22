use strict;
use warnings;

use Test::More;

use lib 'lib';
use NicToolServerAPI;

{
    package NicTool::Transport::REST;

    sub new {
        my ( $class, $nt ) = @_;
        return bless { nt => $nt }, $class;
    }

    sub send_request {
        my ( $self, $url, %vars ) = @_;
        $self->{url} = $url;
        return {
            error_code => 200,
            error_msg  => 'OK',
            action     => $vars{action},
            token      => $self->{nt}{_rest_jwt_token},
        };
    }
}
$INC{'NicTool/Transport/REST.pm'} = __FILE__;

my $api = bless {}, 'NicToolServerAPI';

my $login = $api->send_rest_request(
    'http://api:3000',
    action => 'login',
);
ok !exists $login->{error_code}, 'login success omits the v2 error code';

my $session = $api->send_rest_request(
    'http://api:3000',
    action          => 'verify_session',
    nt_user_session => 'jwt',
);
ok !exists $session->{error_code}, 'session success omits the v2 error code';
is $session->{token}, 'jwt', 'session cookie becomes the REST bearer token';

my $group = $api->send_rest_request(
    'http://api:3000',
    action          => 'get_group',
    nt_user_session => 'jwt',
);
is $group->{error_code}, 200, 'ordinary GUI actions retain the v2 success code';

done_testing;
