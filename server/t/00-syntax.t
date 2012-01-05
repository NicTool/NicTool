
#use strict;

use Config qw/ myconfig /;
use Data::Dumper;
use English qw/ -no_match_vars /;
use Test::More tests => 19;

use lib 'lib';

my $this_perl = $Config{'perlpath'} || $EXECUTABLE_NAME;

ok( $this_perl, "this_perl: $this_perl" );

if ($OSNAME ne 'VMS' && $Config{_exe} ) {
   $this_perl .= $Config{_exe}
     unless $this_perl =~ m/$Config{_exe}$/i;
};

my @modules = glob "lib/*.pm";
push @modules, glob "lib/*/*.pm";
push @modules, glob "lib/*/*/*.pm";
foreach my $mod ( @modules ) {
    chomp $mod;
    next if $mod eq 'lib/NicToolServer/Response.pm'; # ony runs under mod_perl2
    my $cmd = "$this_perl -c $mod";
    my $r = `$cmd 2>&1`;
    my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
    my $pretty_name = substr($mod, 4);
    ok( $exit_code == 0, "syntax $pretty_name");
};

#my $r = `$this_perl -c lib/nictoolserver.conf 2>&1`;
#my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
#ok( $exit_code == 0, "syntax nictoolserver.conf");
