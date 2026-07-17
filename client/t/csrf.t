use strict;
use warnings;

use lib 'lib';

use Test::More tests => 8;

use NicToolClient;

# Minimal CGI stand-in: the cookie and param reads the CSRF code touches.
package MockCGI;

sub new    { my ( $class, %args ) = @_; bless {%args}, $class }
sub cookie { my ( $self, @args ) = @_; return $self->{cookies}{ $args[0] } if @args == 1; return 'SETCOOKIE' }
sub param  { my ( $self, $name ) = @_; return $self->{params}{$name} }

package main;

sub client_with { return NicToolClient->new( MockCGI->new(@_) ) }

my $session = 'abc123deadbeefsession';

# nav.cgi and group.cgi load concurrently in the frameset, as separate
# processes, with a valid session and no csrf cookie: the state after a browser
# restart. Random per-process tokens made them race to Set-Cookie and strand
# each other's forms with a dead token. (#335)
my $nav_token  = client_with( cookies => { NicTool => $session } )->get_csrf_token();
my $body_token = client_with( cookies => { NicTool => $session } )->get_csrf_token();

is( $nav_token, $body_token, 'concurrent frames derive an identical token' );
like( $nav_token, qr/^[0-9a-f]{40}$/, 'derived token is 40 char hex' );

my $other = client_with( cookies => { NicTool => 'a-totally-different-session' } );
isnt( $other->get_csrf_token(), $nav_token, 'distinct sessions derive distinct tokens' );

unlike( $nav_token, qr/\Q$session\E/, 'token does not embed the session id' );

# The csrf cookie is gone but the session cookie survives: re-deriving the same
# token keeps the rendered form valid for the next POST.
my $after_restart = client_with( cookies => { NicTool => $session } );
is( $after_restart->get_csrf_token(), $nav_token, 'token survives loss of the csrf cookie' );

my $poster = client_with(
    cookies => { NicTool => $session, NicTool_csrf => $nav_token },
    params  => { csrf_token => $nav_token },
);
ok( $poster->verify_csrf(), 'matching cookie and form token validates' );

my $forged = client_with(
    cookies => { NicTool => $session, NicTool_csrf => $nav_token },
    params  => { csrf_token => 'f' x 40 },
);
ok( !$forged->verify_csrf(), 'mismatched form token is rejected' );

# No session to derive from before login.
my $login = client_with( cookies => {} );
like( $login->get_csrf_token(), qr/^[0-9a-f]{40}$/, 'login page mints a random token' );
