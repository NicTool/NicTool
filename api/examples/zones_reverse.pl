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

die "can't open import file!: $!\n" if ( ! -r $file);

my $nt = NicToolTest->new;
my $s;                      #store session string
my $r;                      #result of query
my $me;                     #details about self

my $debug = "y";
$me = &nictool_connect();

$| = 1;

open(INPUT, "<$file" ) or die "Unable to open $file: $!\n";
	while ( <INPUT> ) {
		chomp $_;
		my $zoneid = &find_the_zone_id($_);
		if (!$zoneid) {
			my $zoneid = &create_the_zone($_);
			&add_zone_records($zoneid, $_);
		} else {
			my $record = &get_zone_records($zoneid);
			&update_zone_records($record, $zoneid, $_);
		};
	};
close (INPUT);

undef $me;
$nt->logout();
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

sub find_the_zone_id {
	print "searching for: $_[0]...";
	my $r = $nt->get_group_zones(nt_group_id=>1,include_subgroups=>1,Search=>1,"1_field"=>"zone",'1_option'=>"=",'1_value'=>$_[0]);
	return $r->{'zones'}->[0]->{'nt_zone_id'};
};

sub create_the_zone {
	my %newzone = ( nt_group_id=>"68", zone=>$_[0], nameservers=>"3,4,5" );
	my $r = $nt->save_zone(%newzone);

	if ( $r->{'error_code'} eq "200" ) {
		print "ZONE SUCCESS: $r->{'nt_zone_id'}, $_[0] \n";
		if ( $nt->is_error($r) ) { die "Error adding zone:".$nt->is_error($r); };
		return $r->{'nt_zone_id'};
	} else {
		print "ZONE FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
	} 
};

sub get_zone_records {
	print "get_zone_records: $_[0], $_[1]\n" if ($debug eq "y");
	my %query = ( nt_zone_id=>"$_[0]" );
	my $r = $nt->get_zone_records(%query);
	if ($debug eq "y") { print "r: $r\n"; };
	if ($debug eq "y") { print "r->records: $r->{'records'} \n"; };
	for ( my $i = 0; $i < scalar(@{$r->{'records'}}); $i++ ) {
		print "get_zone_records: $r->{'records'}->[$i]->{'name'}, $r->{'records'}->[$i]->{'type'}, $r->{'records'}->[$i]->{'address'} \n";
	};
	# We return the entire array of records
	return $r->{'records'};
};

sub add_zone_records {
	# Variables passed are: 0 = zoneid, 1 = zone
	for ( my $i = 1; $i < 255; $i++) {
		my %zone_record = ( nt_zone_id=>$_[0], name=>"$i", type=>"PTR", address=>"$i\.$_[1]\.", weight=>"" );
		my $r = $nt->save_zone_record(%zone_record);
		if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
	};
};

sub update_zone_records {		
	# We get passed 0=record (an array of hashes) 1=zoneid 2=zone
	print "update zones sub\n";
	for ( my $i = 1; $i < 255; $i++) {
		print "loop $i\n";
		if ( ! $_[0]->[$i] ) {
			my %zone_record = ( nt_zone_id=>$_[1], name=>"$i", type=>"PTR", address=>"$i\.$_[2]\.", weight=>"" );
			my $r = $nt->save_zone_record(%zone_record);
			if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
		};
	}
};

sub save_zone_record {
	my %query = ( nt_zone_record_id=>"$_[0]", nt_zone_id=>"$_[1]", name=>"$_[2]", address=>"$_[3]", type=>"$_[4]", weight=>"$_[5]" );
	#print "values is: $_[0], $_[1], $_[2], $_[3], $_[4], $_[5] \n";
	my $r = $nt->save_zone_record(%query);
	if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
};
