package TestConfig;

use strict;
use Test;

sub import {
    my $settings;
    my $pkg = shift;
    my $cnt = shift;

    my $file = "test.cfg";
    -f $file or $file = "t/test.cfg";
    -f $file or die "could not find your test.cfg file in t/test.cfg\n";

    open( F, "<$file" );
    my $c;
    local $/ = '';
    $c = <F>;
    close(F);
    my $s = eval $c;
    if (   $s->{'server_host'}
        && $s->{'server_port'}
        && $s->{'data_protocol'}
        && $s->{'username'}
        && $s->{'password'} )
    {
        $settings = $s;
    }

    my $conf = sub {
        my $param = shift;
        return $settings->{$param};
    };
    *main::Config = $conf;

    if ($settings) {
        plan tests => $cnt;
    }
    else {
        plan tests => 0;
        warn
            "You must edit the file 'test.cfg' to specify connection parameters in order to perform transport layer and protocol tests.\n";
        exit 0;
    }
}

1;

