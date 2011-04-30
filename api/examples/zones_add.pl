#!/usr/bin/perl

use Getopt::Long;                                                                                                                                          
use NicToolTest;
use Data::Dumper;
use strict;

my %options = (
   'user=s' => \my $user,
   'pass=s' => \my $passwd,
   'file=s' => \my $file,
);

&GetOptions (%options);
 
if (!$user && !$passwd && !$file ) {
        die "\nusage: $0 -u <user> -p <pass> -f <file>\n\n";
};

if ( ! -r $file) {
	die "can't open import file!: $!\n";
};

my $nt = NicToolTest->new;
my $s;                      #store session string
my $r;                      #result of query
my $me;                     #details about self

#session string is stored in NicToolTest object now and used for further queries.
#$me = $r;
$me = &nictool_connect();

open(INPUT, $file ) or die "Unable to open $file: $!\n";
	while ( <INPUT> ) {
		chomp $_;
		&create_the_zone($_);
	};
close (INPUT);

exit 0;

sub nictool_connect {
	$nt->set(server_host=>"localhost");
	$nt->set(server_port=>"8010");
	$r = $nt->login(username=>$user,password=>$passwd);
	#print Dumper($r);
	die "error logging in: ".$nt->is_error($r)."\n" if $nt->is_error($r); 
	die "Error: no session string returned.\n" if ! defined $r->{nt_user_session};
	$nt->set(nt_user_session=>$r->{nt_user_session});
	return $r;
};

sub create_the_zone {
	my $new_zone = $_[0];

	my %newzone = ( nt_group_id => "10", zone => $new_zone, nameservers => "3,4,5" );
	my $r = $nt->save_zone(%newzone);

	if ( $r->{'error_code'} eq "200" ) {
		print "ZONE SUCCESS: $r->{'nt_zone_id'} \n";
		if ( $nt->is_error($r) ) { die "Error adding zone:".$nt->is_error($r); };
		#print Dumper($r);
		&add_records($r->{'nt_zone_id'}, $new_zone);
	} else {
		print "ZONE FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
		#print Dumper($r);
	} 
};


sub add_records {
	my %zone_record = ( nt_zone_id => $_[0], name => "$_[1]\.", type => "A", address => "64.227.180.130", weight => "" );
	my $r = $nt->save_zone_record(%zone_record);
	if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };

	%zone_record = ( nt_zone_id => $_[0], name => "www\.$_[1]\.", type => "CNAME", address => "$_[1]\.", weight => "" );
	$r = $nt->save_zone_record(%zone_record);
	if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };

	%zone_record = ( nt_zone_id => $_[0], name => "$_[1]\.", type => "MX", address => "mail\.$_[1]\.", weight => "10" );
	$r = $nt->save_zone_record(%zone_record);
	if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };

	%zone_record = ( nt_zone_id => $_[0], name => "mail\.$_[1]\.", type => "A", address => "64.227.180.130", weight => "" );
	$r = $nt->save_zone_record(%zone_record);
	if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };

};

exit 1;

