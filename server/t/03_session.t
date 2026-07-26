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

done_testing();
