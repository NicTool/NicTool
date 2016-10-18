
use Config 'myconfig';
use Data::Dumper;
use English '-no_match_vars';
use Test::More 'no_plan';

use lib 'lib';

my $this_perl = $Config{'perlpath'} || $EXECUTABLE_NAME;

ok( $this_perl, "this_perl: $this_perl" );

if ($OSNAME ne 'VMS' && $Config{_exe} ) {
   $this_perl .= $Config{_exe}
     unless $this_perl =~ m/$Config{_exe}$/i;
};

my @moduleGlobs = ( 'lib/*.pm', 'lib/*/*.pm', 'lib/*/*/*.pm' );
foreach my $glob ( @moduleGlobs ) {
    foreach my $mod ( glob $glob ) {
        chomp $mod;
        next if $mod eq 'lib/NicToolServer/Client.pm'; # ony runs under mod_perl2
        next if $mod eq 'lib/NicToolServer/Response.pm'; # ony runs under mod_perl2
        my $cmd = "$this_perl -I lib -c $mod 2>/dev/null 1>/dev/null";
        system $cmd;
        my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
        ok( $exit_code == 0, "syntax $mod");
    };
};

# only works when mod_perl is loadable
#my $r = `$this_perl -I lib -c lib/nictoolserver.conf.dist 2>&1`;
#my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
#ok( $exit_code == 0, "syntax nictoolserver.conf");
