
use Config 'myconfig';
use Data::Dumper;
use English '-no_match_vars';
use Test::More tests => 24;

use lib 'lib';

ok( -d 'htdocs', 'htdocs directory' ) or die 'could not find htdocs directory';

my $this_perl = $Config{'perlpath'} || $EXECUTABLE_NAME;

ok( $this_perl, "this_perl: $this_perl" );

my $perl_args = "-I lib";

if ($OSNAME ne 'VMS' && $Config{_exe} ) {
   $this_perl .= $Config{_exe}
     unless $this_perl =~ m/$Config{_exe}$/i;
}

my $fileGlobs = [ 'lib/*.pm', 'htdocs/*.cgi' ];

foreach my $glob ( @$fileGlobs ) {
    foreach ( glob $glob ) {
        chomp;
        my $cmd = "$this_perl $perl_args -c $_";
        $cmd .= ' 2>/dev/null >/dev/null';
        system $cmd;
        my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
        ok( $exit_code == 0, "syntax $_");
    };
};

my $r = `$this_perl $perl_args -c lib/nictoolclient.conf.dist 2>&1`;
my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
ok( $exit_code == 0, "syntax nictoolclient.conf");
