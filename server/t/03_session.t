use strict;
use warnings;

use Test::More;

use lib 'lib';

use NicToolServer::User;
use NicToolServer::Session;

my $session = bless {}, 'NicToolServer::Session';

# mod_unique_id output is not a CSPRNG; its presence must not displace urandom.
local $ENV{UNIQUE_ID} = 'apache-unique-id';
isnt( $session->session_id, 'apache-unique-id', 'UNIQUE_ID is ignored' );
like( $session->session_id, qr/^[0-9a-f]{32}$/, 'session id is 32 char hex' );

my %seen;

for ( 1 .. 1000 ) {
    my $id = $session->session_id;
    ok( !$seen{$id}++, 'generated unique session id' );
}

my @deleted;
{
    no warnings qw(redefine once);
    local *NicToolServer::Session::get_option          = sub {45};
    local *NicToolServer::Session::_insert_session_log = sub { };
    local *NicToolServer::Session::_delete_session     = sub { push @deleted, $_[1] };
    local *NicToolServer::Session::exec_query          = sub {
        [   { nt_user_session_id => 1, nt_user_id => 1, nt_user_session => $session->session_id },
            { nt_user_session_id => 2, nt_user_id => 1, nt_user_session => '3$' . ( 'a' x 64 ) },
            { nt_user_session_id => 3, nt_user_id => 1, nt_user_session => '0123456789abcdef' },
        ];
    };
    $session->timeout_sessions;
}
is_deeply( \@deleted, [ 1, 3 ], 'timeout expires older v2 sessions and leaves v3 its own' );

for my $foreign ( '3.0.0', '3$' . ( 'a' x 64 ), 'A' x 32, undef ) {
    my ( $err, $found ) = $session->_get_session($foreign);
    ok( !$err && !$found, 'refuses a session it did not write: ' . ( $foreign // 'undef' ) );
}

done_testing();
