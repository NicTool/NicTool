use strict;
use warnings;

use File::Find;
use Test::More;

open my $fh, '<', 'MANIFEST' or die "MANIFEST: $!";
my %listed = map { s/\s.*//sr => 1 } grep {/\S/} <$fh>;

ok -e $_, "$_ exists" for sort keys %listed;

my @modules;
find( sub { push @modules, $File::Find::name if /\.pm\z/ }, 'lib' );
ok $listed{$_}, "MANIFEST lists $_" for sort @modules;

done_testing();
