
use Config qw/ myconfig /;
use Data::Dumper;
use English qw/ -no_match_vars /;
use Test::More tests => 24;

use lib 'lib';

ok( -d 'htdocs', 'htdocs directory' ) or die 'could not find htdocs directory';

my $this_perl = $Config{'perlpath'} || $EXECUTABLE_NAME;

ok( $this_perl, "this_perl: $this_perl" );

if ($OSNAME ne 'VMS' && $Config{_exe} ) {
   $this_perl .= $Config{_exe}
     unless $this_perl =~ m/$Config{_exe}$/i;
}

foreach ( glob "htdocs/*.cgi" ) {
    #print "file: $file\n";
    my $cmd = "$this_perl -c $_";
    $cmd .= ' 2>/dev/null >/dev/null';
    #print "$cmd\n";
    my $r = system $cmd;
    ok( $r == 0, "syntax $_");
};

foreach ( glob "lib/*.pm" ) {
    chomp;
    my $cmd = "$this_perl -c $_";
    my $r = `$cmd 2>&1`;
    my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
    my $pretty_name = substr($_, 4);
    ok( $exit_code == 0, "syntax $pretty_name");
};

my $r = `$this_perl -c lib/nictoolclient.conf 2>&1`;
my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
ok( $exit_code == 0, "syntax nictoolclient.conf");
