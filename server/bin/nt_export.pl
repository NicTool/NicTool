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
use Sys::Hostname;
#$Data::Dumper::Sortkeys=1;

use NicToolServer::Export;

BEGIN {
    # This executes before the main script. Hence we are
    # able to seed the @INC path with the directory where the "real"
    # script resides.

    my $LIB_DIR;

    # is the executable called using $PATH? (i.e. does not start with / )
    if ($0 !~ m%^/%) {
        (my $prog = $0) =~ s%^.*/([^/]+)$%$1%;
        my @PATH=split (':', $ENV{'PATH'});
        push @PATH, '.', undef;
        foreach my $dir (@PATH) {
            if (-f "$dir/$prog") { # found it!
                $dir =~ s/\./`pwd`/eo;
                chomp $dir;
                $::PROG_LOCATION = -l $prog ? readlink ($prog) : $prog;
                last;
            }
        }
    }
    else {
        # Check to see if $0 is a symbolic link or not.
        $::PROG_LOCATION = -l $0 ? readlink ($0) : $0;
    }

    # Set $LIB_DIR to point to the lib/NicToolServer dir in my parent dir
    ($LIB_DIR = $::PROG_LOCATION) =~ s%/[^/]+$%../lib/NicToolServer%;
    unshift @INC, $LIB_DIR;
    # above probably eliminates the need of all the uses of the lib module
}


$|++;  # output autoflush (so log msgs aren't buffered)

# process command line options
Getopt::Long::GetOptions(
    'daemon'    => \my $daemon,
    'dsn=s'     => \my $dsn,
    'conf=s'    => \my $conf,
    'help'      => \my $usage,
    'incremental'=>\my $incremental,
    'force'     => \my $force,
    'nsid=i'    => \my $nsid,
    'user=s'    => \my $db_user,
    'pass=s'    => \my $db_pass,
    'pfextra'   => \my $postflight_extra,
    'verbose'   => \my $verbose,
) or do {
    print STDERR "error parsing command line options";
    exit 2;
};

usage() and exit if $usage;

if ( ! defined $dsn || ! defined $db_user || ! defined $db_pass ) {
    get_db_creds_from_nictoolserver_conf($conf);
}

$dsn     ||= ask( "database DSN",
             default => 'DBI:mysql:database=nictool;host=127.0.0.1;port=3306');
$db_user ||= ask( "database user", default => 'root' );
$db_pass ||= ask( "database pass", password => 1 );

my $export = NicToolServer::Export->new( 
    ns_id => $nsid || 0,
    force => $force || 0,
    pfextra => $postflight_extra ? 1 : 0,
    debug => $verbose || 0,
    );
$export->incremental( $incremental || 0);
$export->get_dbh( dsn => $dsn, user => $db_user, pass => $db_pass,) or do {
    print STDERR "database connection failed";
    exit 2;
};

# If nsid has not been specified, try to locate the nsid for this server,
# or display a table of nsid to use to generate the zone files.
if ( !defined $nsid ) {
    $nsid = $export->{ns_id} = get_nsid($export);
    $export->set_active_nameserver($nsid);
}

local $SIG{HUP}  = \&graceful_exit;
local $SIG{TERM} = \&graceful_exit;
local $SIG{PIPE} = \&graceful_exit;
local $SIG{USR1} = \&graceful_exit;
local $SIG{SEGV} = \&graceful_exit;
local $SIG{ALRM} = \&graceful_exit;

my $result;
if ( $daemon ) { $result = $export->daemon(); }
else           { $result = $export->export(); };

exit $result;


sub get_nsid {
    my $export = shift || die "get_nsid() requires a NicToolServer::Export object";
    my $nslist = $export->get_active_nameservers();
    
    # determine if the current hostname is a listed nameserver
    my $me = hostname();
    foreach my $nsentry (@$nslist) {
        if ($nsentry->{name} =~ /^$me\./) {
            return $nsentry->{nt_nameserver_id};
        }
    }
    
    printf( "\n%5s   %25s   %9s\n", 'nsid', 'name', 'format' );
    my $format = "%5.0f   %25s   %9s\n";
    foreach my $ns (sort @$nslist) {
        printf $format, $ns->{nt_nameserver_id}, $ns->{name}, $ns->{export_format};
    };
    print STDERR "\nERROR: missing nsid. Try this:
    
    $0 -nsid N\n";
    exit 2;
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

    my $file = shift || '';
    my $prog_dir; ($prog_dir = $::PROG_LOCATION) =~ s%^(.*)/[^/]+$%$1%;

    if (! -r $file) {
        # try a number of locations to try to find the config file
        $file = undef;
        my @dirs_to_try = ("$prog_dir/../lib", 'lib', '../server/lib',
                           '../lib', '..', '.');
        foreach my $dir (@dirs_to_try) {
            if (-r "$dir/nictoolserver.conf") {
                $file = "$dir/nictoolserver.conf";
                last;
            }
        }

        # clean up the path
        $file =~ s%/[^/]+/../%/%g;

        # Unable to locate the config file
        return if !defined($file);
    }
    
    if ($verbose) {
        print "nsid $nsid " if $nsid;
        print "reading DB settings from $file\n";
    }
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

  $0 -help

  $0 -nsid <N> [-daemon] [-force] [-verbose] [-incremental] [--conf FILE]

If nt_export is unable to automatically locate/access nictoolserver.conf,
you can specify --conf with the path to the file. In addition, you may 
specify the database connection properties manually:

   -dsn   DBI:mysql:database=nictool;host=127.0.0.1;port=3306
   -user  root
   -pass  mySecretPassWord

Run the script without any -nsid argument to see a list of name servers.
If nt_export is being executed on a registered name server, the nsid
parameter will be automatically detected and the export will commence. 

When nt_export is executed, it will indicate if the export occurred with
the exit status. An exit status of 1 is returned when the export did 
occur and an exit status of 0 when the export did not occur (or no updates).
If nt_export detects an error, then an exit status of 2 is returned. 

EOHELP
;
};
