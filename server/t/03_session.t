use strict;
use warnings;

use Test::More;

use lib 'lib';

use NicToolServer::User;
use NicToolServer::Session;

my $session = bless {}, 'NicToolServer::Session';

local $ENV{UNIQUE_ID} = 'apache-unique-id';
is( $session->session_id, 'apache-unique-id', 'uses UNIQUE_ID when available' );

local $ENV{UNIQUE_ID};
my %seen;

for ( 1 .. 1000 ) {
    my $id = $session->session_id;
    ok( !$seen{$id}++, 'generated unique session id' );
}

done_testing();
