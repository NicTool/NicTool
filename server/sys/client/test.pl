#!/usr/bin/perl
use lib 't';
use lib 'lib';
use Test::Harness;
my @files = qw(
    object cache result list api transport protocol nictool
);
runtests( map {"t/$_.t"} @files );
