#!/usr/bin/perl

use strict;
use warnings;

use lib '.';
use lib 'lib';
use Data::Dumper;
use Getopt::Long;
use Params::Validate qw/:all/;
$Data::Dumper::Sortkeys=1;

use NicToolServer::Export;

# process command line options
Getopt::Long::GetOptions(
    'force'     => \my $force,
    'daemon'    => \my $daemon,
    'dsn=s'     => \my $dsn,
    'user=s'    => \my $dbuser,
    'pass=s'    => \my $dbpass,
    'nsid=i'    => \my $nsid,
) or die "error parsing command line options";

my $export = NicToolServer::Export->new( ns_id=>$nsid || 0 );
$export->get_dbh( 
    dsn  => $dsn || ask('database DSN', default=>'DBI:mysql:database=nictool;host=localhost;port=3306'),
    user => $dbuser || ask('database user', default=>'nictool'),
    pass => $dbpass || ask('database password',password=>1),
);

$nsid || get_nsid();

my $count = $export->get_modified_zones();
print "found $count zones\n";
my $r = $export->export();


sub get_nsid {
    my $nslist = $export->get_active_nameservers();
    printf( "\n%5s   %25s   %9s\n", 'nsid', 'name', 'format' );
    my $format = "%5.0f   %25s   %9s\n";
    foreach my $ns (@$nslist) {
        printf $format, $ns->{nt_nameserver_id}, $ns->{name}, $ns->{export_format};
    };
    $nsid = ask("nsid", default => 0);
    $export = NicToolServer::Export->new( ns_id=>$nsid );
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

    return $response if length $response  > 0;         # if they typed something, return it
    return $default if defined $default;   # return the default, if available
    return '';                             # return empty handed
}

