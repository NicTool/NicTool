package TestConfig;

#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under
# the terms of the Affero General Public License as published by Affero,
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#

use lib "sys/client";
use lib "../sys/client";

sub import {
    my $settings;
    my $file = "test.cfg";
    -f $file or $file = "t/test.cfg";
    -f $file or die "could not find your test.cfg file in t/test.cfg\n";

    open( F, "<$file" );
    my $c;
    {
        local $/;
        $c = <F>;
    }
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

    die
        "You must edit the file 'test.cfg' to specify connection parameters in order to perform transport layer tests."
        unless $settings;

    my $conf = sub {
        my $param = shift;
        return $settings->{$param};
    };
    *main::Config = $conf;

    if ( exists $settings->{'lib'} ) {
        eval "
	        use lib '$settings->{'lib'}'
        ";
    }

    eval " use NicTool ";
    die
        "Couldn't 'use NicTool'. $@\n Please either install the NicTool client library, or edit 'test.cfg' to specify its location."
        if $@;

}

1;

