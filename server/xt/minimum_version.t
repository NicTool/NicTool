#!perl

use strict;
use warnings;

use Test::More;
use Test::MinimumVersion;

# MUST stay in sync with MIN_PERL_VERSION in:
#   Makefile.PL              (top-level)
#   server/Makefile.PL
#   server/api/Makefile.PL
#   client/Makefile.PL
# And with the floor cell of .github/workflows/ci-perl-floor.yml.
my $min = '5.022';   # placeholder — set to actual floor when bump PR lands

# Run from server/ cwd (matches ci.yml `prove -v xt/*.t` step).
all_minimum_version_ok($min, {
    paths => [
        'lib', 'bin', 't',                                 # server
        'api/lib', 'api/t',                                # server/api
        '../client/lib', '../client/bin', '../client/t',   # client
    ],
});
