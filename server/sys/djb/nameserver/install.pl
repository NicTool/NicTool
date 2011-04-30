#!/usr/bin/perl

#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01+ Copyright 2004-2008 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under 
# the terms of the Affero General Public License as published by Affero, 
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT 
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#
# Changelog: Rob Lensen <rob@bsdfreaks.nl>
#           - Perl strict updates
#           - Change log/run script to use the log user
#

use strict;
use warnings;
use Cwd;
use English;
use Getopt::Long;

if ( !-f "sample/nt_export_djb.pl" or !-f "sample/nt_export_djb") 
{
	die "WARNING: you must run make in sys/djb before running this script!!!\n" 
};

my $vals = {};

# allow them to be passed in on the command line
GetOptions (
    'directory'    => \$vals->{'service_dir'},
    'nsid'         => \$vals->{'nsid'},
    'user'         => \$vals->{'user'},
    'loguser'      => \$vals->{'loguser'},
    'db_host'      => \$vals->{'NT_DB_HOST_NAME'},
    'db_name'      => \$vals->{'NT_DB_NAME'},
    'db_user'      => \$vals->{'NT_DB_USER_NAME'},
    'db_pass'      => \$vals->{'NT_DB_PASSWORD'},
    'db_type'      => \$vals->{'NT_DB_TYPE'},
    'exportopts'   => \$vals->{'export_opts'},
    'ns_local'     => \$vals->{'ns_local'},
);

# and then prompt for missing values
$vals->{'service_dir'}      ||= answer("directory for the new nameserver", "/usr/local/nictool-x1.nictool.com");
$vals->{'nsid'}             ||= answer("the nictool nameserver id", "");
$vals->{'user'}             ||= answer("the system user the export process runs as", "ntexport");
$vals->{'loguser'}          ||= answer("the system user the log process runs as", "bin");
$vals->{'NT_DB_HOST_NAME'}  ||= answer("the database host",   "localhost");
$vals->{'NT_DB_NAME'}       ||= answer("the database name",   "nictool");
$vals->{'NT_DB_USER_NAME'}  ||= answer("database user",       "nicDBuser");
$vals->{'NT_DB_PASSWORD'}   ||= answer("database pass",       "");
$vals->{'NT_DB_TYPE'}       ||= "mysql"; # answer("database type",       "mysql");
$vals->{'export_opts'}      ||= answer("export options",      "-r -md5 -force -noserials -buildcdb");
$vals->{'ns_local'} ||= yes_or_no("Typically you will run NicTool on one host and your DNS servers on another. This export expects to send the data to the remote server based on the settings in the nameservers definition within NicTool. You can also run a DNS server locally on this host. Will this DNS server be running locally?", "n");
if ( $vals->{'ns_local'} ) {
    $vals->{'TINYDNS_DATA_DIR'} = answer("the path to your tinydns data dir", "/usr/local/tinydns-ns1/root");
};

my $dir = $vals->{'service_dir'};
if ( -d $dir) {
    die "ERROR: selected dir $dir already exists!\n";
};

print "setting up your nameserver with values shown.\n";
use Data::Dumper;
print Dumper $vals;

if ( 1 == 0 ) {
    exit;
};

system("cp -rf sample $dir");
open(F,"sample/run");
open(O,">$dir/run");
while(<F>){
	s/DIR/$dir/;
	s/NSID/$vals->{'nsid'}/;
	s/OPTS/$vals->{'export_opts'}/;
	s/USER/$vals->{'user'}/;
	s/LOGUSER/$vals->{'loguser'}/;
	print O $_;
}
close(O);
close(F);

open(F,"sample/log/run");
open(O,">$dir/log/run");
while(<F>){
	s/LOGUSER/$vals->{'loguser'}/;
	print O $_;
}
close(O);
close(F);

foreach ( qw(NT_DB_HOST_NAME  NT_DB_NAME  NT_DB_PASSWORD  NT_DB_TYPE  NT_DB_USER_NAME) ){
	system ("echo \"$vals->{$_}\" > $dir/env/$_");
}
system("chown -R $vals->{'user'}:$vals->{'user'} $dir");
system("chown $vals->{'loguser'}:$vals->{'loguser'} $dir/log/status");
system("chown $vals->{'loguser'}:$vals->{'loguser'} $dir/log/main");

print "done.\n";

1;

sub answer {

    my ( $question, $default, $timeout) = @_;
    
    # this sub is useless without a question.
    unless ($question) {
        die "question called incorrectly. RTFM. \n";
    }   
    
    my ($response);
    
    print "Please enter $question: ";
    print "($default) : " if $default;
    
    if ($timeout) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timeout;
            $response = <STDIN>;
            alarm 0;
        };  
        if ($EVAL_ERROR) {
            ( $EVAL_ERROR eq "alarm\n" )
              ? print "timed out!\n"
              : warn;    # propagate unexpected errors
        }
    }
    else {
        $response = <STDIN>;
    }

    chomp $response;
    # if they typed something, return it
    return $response if ( $response ne "" );

    # otherwise, return the default if available
    return $default if $default;

    # and finally return empty handed
    return "";
}

sub yes_or_no {

    my ($question) = @_;
    
   unless ($question) {
        die "yes_or_no called incorrectly. RTFM. \n";
    };

    my ($response);

    print "\n\t\t$question";
    do {
        print "(y/n): ";
        $response = lc(<STDIN>);
        chomp($response);
    } until ( $response eq "n" || $response eq "y" );

    $response eq "y" ? return 1 : return 0;
}
