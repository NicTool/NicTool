
use strict;
use warnings;

use Data::Dumper;
use English;
use Test::More;

eval "use Test::HTML::Lint";

if ( $EVAL_ERROR ) {
    warn Data::Dumper::Dumper( $EVAL_ERROR );
    plan skip_all => 'Test::HTML::Lint not installed';
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
        html_ok( $file, "HTML valid: $file" );
    };
};


my $htdocs = "htdocs";
if ( ! -d $htdocs ) {
    $htdocs = "../htdocs";
}

if ( -d $htdocs ) {
    foreach my $file ( glob "$htdocs/*.cgi" ) {
        html_ok( $file, "HTML valid: $file" );
    };
};
