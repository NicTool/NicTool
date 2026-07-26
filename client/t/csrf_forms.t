use strict;
use warnings;

use Test::More;

# Companion to csrf_links.t: every POST form must embed the csrf token, or
# the Save/Create it submits dies in verify_csrf. Links got a scanner after
# #354 taught us that rendered-but-untested markup rots; forms get the same.
#
# A form counts when the source opens it via CGI.pm's start_form (POSTs by
# default here) or a literal <form> that declares a method. Button-only
# forms (window-close, history-back) declare no method and are skipped.
my @sources = ( glob('htdocs/*.cgi'), 'lib/NicToolClient.pm' );
plan tests => scalar @sources;

for my $file (@sources) {
    open my $fh, '<', $file or die "$file: $!";
    my $src = do { local $/; <$fh> };
    close $fh;

    my @missing;

    while (
        $src =~ /
            ( start_form\b | <form\b[^>]*\bmethod=["']?post["']?[^>]* )
        /gix
        )
    {
        my $open = pos($src) - length($1);
        my $line = 1 + ( substr( $src, 0, $open ) =~ tr/\n// );

        # An unterminated form has no bounded body to search, and scanning to
        # end of file would let an unrelated token further down vouch for it.
        my $rest = substr( $src, pos($src) );
        if ( $rest !~ /(end_form|<\/form)/i ) {
            push @missing, "$file:$line (form is never closed)";
            next;
        }

        # The hidden field must appear before the form is closed. Only
        # csrf_hidden_field counts: a bare csrf_token would also match a
        # destructive link's query string, which does nothing for the submit.
        next if substr( $rest, 0, $-[1] ) =~ /csrf_hidden_field/;

        push @missing, "$file:$line";
    }

    is( scalar @missing, 0, "$file: POST forms carry a csrf token" )
        or diag( join "\n", @missing );
}
