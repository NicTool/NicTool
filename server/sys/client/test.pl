use lib 't';
use Test::Harness;
my @files = qw(
    object cache result list api transport protocol nictool
);
runtests( map {"t/$_.t"} @files );
