#!perl

use strict;
use warnings;

use Test::More;
use Test::MinimumVersion;

# Sync this floor with MIN_PERL_VERSION in the four Makefile.PLs and the
# floor cell of ci-perl-floor.yml. See PR #349.
my $min = '5.030';
all_minimum_version_ok($min, {
    paths => [
        'lib', 'bin', 't',                                 # server
        'api/lib', 'api/t',                                # server/api
        '../client/lib', '../client/bin', '../client/t',   # client
    ],
});
