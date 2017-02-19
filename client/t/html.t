
use strict;
use warnings;

use Data::Dumper;
use English;
use Test::More;

eval 'use Test::HTML::Lint';
if ( $EVAL_ERROR ) {
    plan skip_all => 'Test::HTML::Lint not available';
    exit
}
else {
    plan 'no_plan';
};

use_ok( 'Test::HTML::Lint' );

my $templates = "templates";
if ( ! -d $templates ) {
    $templates = "../templates";
}

if ( -d $templates ) {
    foreach my $file ( glob "$templates/*.html" ) {
        html_fragment_ok( $file, "HTML valid: $file" );
    };
};

