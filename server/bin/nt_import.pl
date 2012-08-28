#!/usr/bin/perl

use strict;
use warnings;

use lib '.';
use lib 'lib';
#use lib '../server/lib';
use Data::Dumper;
use English;
use Getopt::Long;
use Params::Validate qw/:all/;
#$Data::Dumper::Sortkeys=1;

use NicToolServer::Import::tinydns;

# process command line options
Getopt::Long::GetOptions(
    'host=s'    => \my $nt_host,
    'port=s'    => \my $nt_port,
    'file=s'    => \my $filename,
    'user=s'    => \my $nt_user,
    'pass=s'    => \my $nt_pass,
    'verbose'   => \my $verbose,
) or die "error parsing command line options";

$nt_user ||= ask( "nicool user" ) if ! $nt_user;
$nt_pass ||= ask( "nictool pass", password => 1 ) if ! $nt_pass;

my $nti = NicToolServer::Import::tinydns->new(
    debug => $verbose || 0,
    );

my $fn = $nti->get_import_file( $filename ) 
    or die "unable to find import file. Specify with -file option";
print "file: $filename, $fn\n";

my $nt = $nti->nt_connect($nt_host, $nt_port, $nt_user, $nt_port);

$nti->import_records();

exit 0;

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

