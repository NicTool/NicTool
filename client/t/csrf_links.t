use strict;
use warnings;

use Test::More;

my @sources = ( glob('htdocs/*.cgi'), glob('templates/*.html'), 'lib/NicToolClient.pm' );
plan tests => scalar @sources;

for my $file (@sources) {
    open my $fh, '<', $file or die "$file: $!";
    my $src = do { local $/; <$fh> };
    close $fh;

    my @missing;

    while ( $src =~ /href="(.*?)"/gs ) {
        my $href = $1;
        next if $href !~ /(?:[?&;])(?:delete|deletedelegate|delete_record|logout)=/;
        next if $href =~ /csrf_token/;

        my $line = 1 + ( substr( $src, 0, pos $src ) =~ tr/\n// );
        ( my $flat = $href ) =~ s/\s+/ /g;
        push @missing, "$file:$line: $flat";
    }

    is( scalar @missing, 0, "$file: state-changing links carry a csrf_token" )
        or diag( join "\n", @missing );
}
