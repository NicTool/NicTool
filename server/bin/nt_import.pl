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
$Data::Dumper::Sortkeys=1;

use NicToolServer::Import::Base;

# process command line options
Getopt::Long::GetOptions(
    'group_id=s'=> \my $group_id,
    'host=s'    => \my $nt_host,
    'port=s'    => \my $nt_port,
    'file=s'    => \my $filename,
    'user=s'    => \my $nt_user,
    'pass=s'    => \my $nt_pass,
    'use-https' => \my $nt_https,
    'type=s'    => \my $type,
    'verbose'   => \my $verbose,
    'help'      => \my $help,
) or die "error parsing command line options";

if($help) {
     print "usage: $0 [-OPTIONS]...\n\n";
     print "Import DNS data into NicTool\n\n";
     print "Options:\n";
     print "  --host           Hostname or IP address of NicTool Server\n";
     print "  --port           NicTool server port (default: 8082)\n";
     print "  --user           NicTool username\n";
     print "  --pass           NicTool password\n";
     print "  --type           Import type (tinydns or bind)\n";
     print "  --file           File to import data from (data for tinydns, named.conf for bind)\n";
     print "  --group_id       NicTool group id zones are placed into\n";
     print "  --use-https      Use https towards NicTool Server\n";
     print "  --verbose        Show extra messages verbose\n\n";
     print "Report issues at https://github.com/msimerson/NicTool/issues\n";
     exit 0;
}

$filename ||=ask( "Location of file you would like to import data from") if ! $filename;
$nt_user ||= ask( "NicTool user you would like to import data as" ) if ! $nt_user;
$nt_pass ||= ask( "NicTool user password", password => 1 ) if ! $nt_pass;

my $nti;
$type ||= get_type(); load_type($type);
my $nt = $nti->nt_connect($nt_host, $nt_port, $nt_user, $nt_pass, $nt_https);

$group_id ||= $nt->result->{store}{nt_group_id} || die "unable to get group ID\n";
warn Dumper($nt->result->{store}) if $verbose;
$nti->group_id( $group_id );

print "\nStarting import using: $filename\n";
$nti->import_records($filename);

exit 0;

sub load_type {
    my $type = shift;
    print "loading type: $type\n";
    if ( $type =~ /bind/i ) {
        require NicToolServer::Import::BIND;
        $nti = NicToolServer::Import::BIND->new( debug => $verbose || 0 );
        return;
    }
    elsif ( $type =~ /tinydns/i ) {
        require NicToolServer::Import::tinydns;
        $nti = NicToolServer::Import::tinydns->new( debug => $verbose || 0 );
        return;
    };
    die "unknown type: $type\n";
};

sub get_type {
    return ask("are you importing from tinydns or BIND?", default=>'BIND');
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

