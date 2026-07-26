use strict;
use warnings;

use lib 'lib';

use Test::More tests => 12;

use NicToolClient;

# Minimal CGI stand-in: the cookie and param reads the CSRF code touches.
package MockCGI;

sub new    { my ( $class, %args ) = @_; bless {%args}, $class }
sub cookie { my ( $self, @args ) = @_; return $self->{cookies}{ $args[0] } if @args == 1; return 'SETCOOKIE' }
sub param  { my ( $self, $name ) = @_; return $self->{params}{$name} }

package main;

sub client_with { return NicToolClient->new( MockCGI->new(@_) ) }

# hex, and shaped like the real thing: NicToolServer::Session::session_id
# unpacks 16 urandom bytes. A fixture with non-hex characters in it cannot be
# embedded in a hex-only token, which would leave the no-leak check below
# unable to fail for the reason it exists.
my $session = 'd41d8cd98f00b204e9800998ecf8427e';

# nav.cgi and group.cgi load concurrently in the frameset, as separate
# processes, with a valid session and no csrf cookie: the state after a browser
# restart. Random per-process tokens made them race to Set-Cookie and strand
# each other's forms with a dead token. (#335)
my $nav_token  = client_with( cookies => { NicTool => $session } )->get_csrf_token();
my $body_token = client_with( cookies => { NicTool => $session } )->get_csrf_token();

is( $nav_token, $body_token, 'concurrent frames derive an identical token' );
like( $nav_token, qr/^[0-9a-f]{40}$/, 'derived token is 40 char hex' );

my $other = client_with( cookies => { NicTool => '9e107d9d372bb6826bd81d3542a419d6' } );
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

# Verification is bound to the session, not the cookie: a POST whose csrf
# cookie was lost mid-session still validates on the derived form token alone.
my $cookieless = client_with(
    cookies => { NicTool => $session },
    params  => { csrf_token => $nav_token },
);
ok( $cookieless->verify_csrf(), 'derived form token validates without a csrf cookie' );

# An attacker who plants a matching cookie/form pair never held the session,
# so the pair cannot be the derived token. Double-submit alone accepted this.
my $planted = client_with(
    cookies => { NicTool => $session, NicTool_csrf => 'a' x 40 },
    params  => { csrf_token => 'a' x 40 },
);
ok( !$planted->verify_csrf(), 'planted cookie/form pair is rejected for a live session' );

my $tokenless = client_with( cookies => { NicTool => $session, NicTool_csrf => $nav_token } );
ok( !$tokenless->verify_csrf(), 'missing form token is rejected' );

# No session to derive from before login.
my $login = client_with( cookies => {} );
like( $login->get_csrf_token(), qr/^[0-9a-f]{40}$/, 'login page mints a random token' );

# Pre-login the double-submit fallback still guards the login form itself.
my $prelogin_token = $login->get_csrf_token();
my $prelogin_post  = client_with(
    cookies => { NicTool_csrf => $prelogin_token },
    params  => { csrf_token => $prelogin_token },
);
ok( $prelogin_post->verify_csrf(), 'pre-login double-submit fallback validates' );
