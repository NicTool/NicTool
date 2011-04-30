#!/usr/bin/perl

use Getopt::Long;                                                                                                                                          
use NicToolTest;
use Data::Dumper;

my %options = (
   'user=s' => \$user, 'pass=s' => \$pass, 'file=s' => \$file,
);

&GetOptions (%options);
 
if (!$user && !$pass && !$file ) {
        die "usage: $0 -u <user> -p <pass> -f <file>\n";
};

if ( ! -r $file) { die "can't open import file!: $!\n"; };

my $nt = NicToolTest->new;
my $s;                      #store session string
my $r;                      #result of query
my $me;                     #details about self

my $oldip = "64.227.180.70";
my $newip = "64.226.52.77";
my $mailip = "208.147.46.91";

$nt->set(server_host=>"localhost");
$nt->set(server_port=>"8010");
$r = $nt->login(username=>$user,password=>$pass);
#print Dumper($r);
die "error logging in: ".$nt->is_error($r)."\n" if $nt->is_error($r); 
die "Error: no session string returned.\n" if ! defined $r->{nt_user_session};
$nt->set(nt_user_session=>$r->{nt_user_session});

#session string is stored in NicToolTest object now and used for further queries.
$me = $r;

open(INPUT, $file ) or die "Unable to open $file: $!\n";
	while ( <INPUT> ) {
		chomp $_;
		my $zoneid = &find_the_zone_id($_);
		my $record = &get_zone_records($zoneid);
		
		for ( my $i = 0; $i < scalar(@{$record}); $i++ ) {
			print "zone record: $record->[$i]->{'name'}, $record->[$i]->{'type'}, $record->[$i]->{'address'} \n";
			if ( $record->[$i]->{'name'} eq "www" && $record->[$i]->{'address'} eq $oldip ) {
				&update_zone_record( $record->[$i]->{'nt_zone_record_id'}, $zoneid, $record->[$i]->{'name'}, $newip, $record->[$i]->{'type'}, $record->[$i]->{'weight'});
			} elsif ( $record->[$i]->{'name'} eq "mail" && $record->[$i]->{'address'} eq $oldip ) {
				&update_zone_record( $record->[$i]->{'nt_zone_record_id'}, $zoneid, $record->[$i]->{'name'}, $mailip, $record->[$i]->{'type'}, $record->[$i]->{'weight'});
			} elsif ( $record->[$i]->{'address'} eq $oldip ) {
				&update_zone_record( $record->[$i]->{'nt_zone_record_id'}, $zoneid, $record->[$i]->{'name'}, $newip, $record->[$i]->{'type'}, $record->[$i]->{'weight'});
			} elsif ( $record->[$i]->{'name'} eq "$_\." && $record->[$i]->{'address'} eq "mail.$_\." ) {
				&update_zone_record( $record->[$i]->{'nt_zone_record_id'}, $zoneid, $record->[$i]->{'name'}, $mailip, $record->[$i]->{'type'}, $record->[$i]->{'weight'});
			} else {
				print "didn't match record: $record->[$i]->{'nt_zone_record_id'} on zone $_. \n";
			};
		};
	};
close (INPUT);


$nt->logout();

exit 0;

sub update_zone_record {
	my %query = ( nt_zone_record_id=>"$_[0]", nt_zone_id=>"$_[1]", name=>"$_[2]", address=>"$_[3]", type=>"$_[4]", weight=>"$_[5]" );
	#print "values is: $_[0], $_[1], $_[2], $_[3], $_[4], $_[5] \n";
	my $r = $nt->save_zone_record(%query);
	if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
};

sub get_zone_records {
	my %query = ( nt_zone_id=>"$_[0]" );
	my $r = $nt->get_zone_records(%query);
	if ($debug eq "y") { print "r: $r\n"; };
	if ($debug eq "y") { print "r->records: $r->{'records'} \n"; };
	#for ( my $i = 0; $i < scalar(@{$r->{'records'}}); $i++ ) {
		#print "zone record: $r->{'records'}->[$i]->{'name'}, $r->{'records'}->[$i]->{'type'}, $r->{'records'}->[$i]->{'address'} \n";
	#};
	# We return the entire array of records
	return $r->{'records'};
};

sub find_the_zone_id {
	my $zone = $_[0];
	my $groupid = "1";
	print "searching for: $zone\n";
	#my $r = $nt->get_group_zones(nt_group_id=>$groupid,quick_search=>1,search_value=>$zone);
	my $r = $nt->get_group_zones(nt_group_id=>$groupid,include_subgroups=>1,quick_search=>1,search_value=>$zone);
	if ($debug eq "y") { print "r: $r\n"; };
	if ($debug eq "y") { print keys %{$r}; print "\n"; };
	if ($debug eq "y") { print values %{$r}; print "\n"; };
	#print "r values: $r->{'error_msg'}, $r->{'total_pages'}, $r->{'error_code'}, $r->{'total'}, $r->{'pages'}, $r->{'start'}, $r->{'limit'}, $r->{'zones'}, $r->{'end'}\n";
	if ($debug eq "y") { print "hash keys:"; print keys %{$r->{'zones'}->[0]}; print "\n"; };
	#print "nt_group_id: $r->{'zones'}->[0]->{'nt_zone_id'} zone:  $r->{'zones'}->[0]->{'zone'} \n";
	return $r->{'zones'}->[0]->{'nt_zone_id'};
};

