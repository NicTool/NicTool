#!/usr/bin/perl

use strict;
use warnings;

use lib '.';
use lib 'lib';
use lib '../lib';
use lib '../server/lib';
#use Data::Dumper;
use Getopt::Long;
use Params::Validate qw/:all/;
#$Data::Dumper::Sortkeys=1;

use NicToolServer::Export;

$|++;  # output autoflush (so log msgs aren't buffered)

# process command line options
Getopt::Long::GetOptions(
    'daemon'    => \my $daemon,
    'dsn=s'     => \my $dsn,
    'help'      => \my $usage,
    'force'     => \my $force,
    'nsid=i'    => \my $nsid,
    'user=s'    => \my $db_user,
    'pass=s'    => \my $db_pass,
    'pfextra'   => \my $postflight_extra,
    'verbose'   => \my $verbose,
) or die "error parsing command line options";

usage() and exit if $usage;

if ( ! defined $dsn || ! defined $db_user || ! defined $db_pass ) {
    get_db_creds_from_nictoolserver_conf();
}

$dsn     = ask( "database DSN", default  =>
        'DBI:mysql:database=nictool;host=localhost;port=3306') if ! $dsn;
$db_user = ask( "database user", default => 'root' ) if ! $db_user;
$db_pass = ask( "database pass", password => 1 ) if ! $db_pass;

my $export = NicToolServer::Export->new( 
    ns_id => $nsid || 0,
    force => $force || 0,
    pfextra => $postflight_extra ? 1 : 0,
    debug => $verbose || 0,
    );
$export->get_dbh( dsn => $dsn, user => $db_user, pass => $db_pass,) 
    or die "database connection failed";

defined $nsid || get_nsid();

local $SIG{HUP}  = \&graceful_exit;
local $SIG{TERM} = \&graceful_exit;
local $SIG{PIPE} = \&graceful_exit;
local $SIG{USR1} = \&graceful_exit;
local $SIG{SEGV} = \&graceful_exit;
local $SIG{ALRM} = \&graceful_exit;

if ( $daemon ) { $export->daemon(); }
else           { $export->export(); };

exit 0;

sub get_nsid {
    my $nslist = $export->get_active_nameservers();
    printf( "\n%5s   %25s   %9s\n", 'nsid', 'name', 'format' );
    my $format = "%5.0f   %25s   %9s\n";
    foreach my $ns (sort @$nslist) {
        printf $format, $ns->{nt_nameserver_id}, $ns->{name}, $ns->{export_format};
    };
    die "\nERROR: missing nsid. Try this:
    
    $0 -nsid N\n";
};

sub ask {
    my $question = shift;
    my %p = validate( @_,
        {   default  => { type => SCALAR, optional => 1 },
            password => { type => BOOLEAN, optional => 1 },
        }
    );

    my $pass     = $p{password};
    my $default  = $p{default};
    my $response;

PROMPT:
    print "Please enter $question";
    print " [$default]" if defined $default;
    print ": ";
    system "stty -echo" if $pass;
    $response = <STDIN>;
    system "stty echo" if $pass;
    chomp $response;

    return $response if length $response  > 0; # they typed something, return it
    return $default if defined $default;   # return the default, if available
    return '';                             # return empty handed
}

sub get_db_creds_from_nictoolserver_conf {

    my $file = "lib/nictoolserver.conf";
    $file = "../server/lib/nictoolserver.conf" if ! -f $file;
    $file = "../lib/nictoolserver.conf" if ! -f $file;
    $file = "../nictoolserver.conf" if ! -f $file;
    $file = "nictoolserver.conf" if ! -f $file;
    return if ! -f $file;

    print "nsid $nsid " if $nsid;
    print "reading DB settings from $file\n";
    my $contents = `cat $file`;

    if ( ! $dsn ) {
        ($dsn) = $contents =~ m/['"](DBI:mysql.*?)["']/;
    };

    if ( ! $db_user ) {
        ($db_user) = $contents =~ m/db_user\s+=\s+'(\w+)'/;
    };

    if ( ! $db_pass ) {
        ($db_pass) = $contents =~ m/db_pass\s+=\s+'(.*)?'/;
    };
};

sub graceful_exit {
    my $signal = shift;
    $export->elog( "exiting: received signal ($signal)" );
    exit;
}

sub usage {
    print <<EOHELP

  $0 -nsid <N> [-daemon] [-force] [-verbose]

If nt_export is unable to locate/access nictoolserver.conf, you can supply
the database connection properties manually:

   -dsn   DBI:mysql:database=nictool;host=localhost;port=3306
   -user  root
   -pass  mySecretPassWord

Run the script without any -nsid argument to see a list of NSIDs available.

EOHELP
;
};
