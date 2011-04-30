#!/usr/bin/perl

package Zones;

use NicToolTest;
use Getopt::Long;
use Data::Dumper;
use CGI qw(:standard);
use strict;

use lib "/usr/home/matt/scripts";
use Zones::Templates;
use Zones::Nameservers;
use Zones::CreateZone;

$| = 1;

my($user, $pass, $action, $dnsfarm, $template, $newip, $oldip);
my($mailip, $delete, $do_reverse, $debug, @zones, @oldips, @mailips, $file);

	my %options = (
   	'user=s' 	=> \$user,
   	'pass=s'		=> \$pass,
		'action=s'	=> \$action,
		'ns=s'		=> \$dnsfarm,
		'zone=s'		=> \@zones,
   	'file=s' 	=> \my $file,
		'template=s'	=> \$template,
		'delete=s'	=> \$delete,
		'newip|ip=s'=> \$newip,
		'oldip=s'	=> \my $oldip,
		'mailip=s'	=> \$mailip,
		'reverse=s'	=> \$do_reverse,
		'debug|v=s'	=> \$debug,
	);
	&GetOptions (%options);
	my ($homedir) = (getpwuid ($<))[7];        # get the user's home dir
	if (!$user && -r "$homedir/\.zones") { &parse_dot_file("$homedir/\.zones"); };

if (!$user || !$pass || !$action) { 
	print "\nusage: $0 -a <action> -u <user> -p <pass> [-z <zone> -f <file>]\n
      add: -a add -ns interland.net -t 2
      del: -a del -d 1\n      mod: -a mod\n
      --template --oldip --newip --mailip --debug\n\n";
	die; 
};

if ( $file ) { if ( -r $file ) {
	open(INPUT, $file ) or die "Unable to open input $file: $!\n";
		while ( <INPUT> ) { 
			chomp $_; 
			my @r = split(/ /, $_); 
			push(@zones, lc($r[0])); 
			push(@oldips, lc($r[1])); 
			push(@mailips, lc($r[2])); 
		};
	close (INPUT);
}; };

my $nt = NicToolTest->new;
my $s;                      #store session string
print "root: @zones\n" if ($debug);
my $me = &nictool_connect();  # session string is stored for further queries.

my $count = 0;
foreach my $z ( @zones ) {
	$z = lc($z);
	my $zonehash = &find_one_zone_id($z);
	my $zoneid = $zonehash->{'nt_zone_id'};

	if ( !$zoneid && $delete ne "1" ) {            # no zoneid and no delete flag
	} elsif ( $zoneid && $delete ne "1" ) {        # zoneid & no delete flag
		if ( $action ne "mod" ) { print "WARNING: zone $z already exists, updating\n"; };
		my $record = &get_zone_records($zoneid);
		$mailip = $mailips[$count];
		$oldip = $oldips[$count];
		&update_zone_records($record, $zoneid, $z, $template, $count);
	} else {
		print "WARNING: what was I supposed to do?\n";
	};
	$count++;
};

if($user eq 'ofs') { print "+ 100 DNS finished correctly\n"; }
exit_with_warn( "Exiting normally\n" );
exit 0;

###
###  Subroutines
###

sub find_one_zone_id {
	print "find_one_zone_id:\t$_[0] = ";
	#                search for an exact match on the zone
	my $r = $nt->get_group_zones(
		nt_group_id=>$me->{nt_group_id},
		include_subgroups=>1,
		Search=>1,
		"1_field"=>"zone",
		'1_option'=>"equals",
		'1_value'=>$_[0] );
	print "$r->{'zones'}->[0]->{'nt_zone_id'}\n";
	return $r->{'zones'}->[0];
};

sub find_zone_nameservers {
	print "find_zone_nameservers: zoneid: $_[0], groupid: $_[1]\n" if ($debug);
	#my %gz = ( nt_zone_id=>$zoneid );
	my %get_zone = ( nt_zone_id=>$_[0], nt_group_id=>$_[1] );
	my $r = $nt->get_zone(%get_zone);
	if ($debug) {
		print "find_zone_nameservers: $r->{'nameservers'}->[0]->{'nt_nameserver_id'}, ";
		print "$r->{'nameservers'}->[1]->{'nt_nameserver_id'}, ";
		print "$r->{'nameservers'}->[2]->{'nt_nameserver_id'}\n";
	};
	return $r->{'nameservers'};
};

sub get_zone_records {
	my %query = ( nt_zone_id=>"$_[0]" );
	my $r = $nt->get_zone_records(%query);
	if ($debug) { 
		#print "get_zone_records: r=$r, r->records=$r->{'records'} \n";
		print "get_zone_records: $_[0]\n";
		for ( my $i = 0; $i < scalar(@{$r->{'records'}}); $i++ ) {
			printf "%35s  %5s  %35s\n", $r->{'records'}->[$i]->{'name'}, $r->{'records'}->[$i]->{'type'}, $r->{'records'}->[$i]->{'address'};
			#print "\t$r->{'records'}->[$i]->{'name'}, $r->{'records'}->[$i]->{'type'}, $r->{'records'}->[$i]->{'address'} \n";
		};
		#print "get_zone_records: returning $r->{'records'}\n";
	};
	return $r->{'records'};
};

sub add_reverse {
	# If IP is 10.1.2.3, look for 2.1.10.in-addr.arpa
	$newip =~ /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/;
	my $reverse = "$3.$2.$1.in-addr.arpa";
	my $last_octet = $4;
	my $zonehash = &find_one_zone_id($reverse);
	my $zoneid = $zonehash->{'nt_zone_id'};
	if(!$zoneid) {   
		# No .arpa entry exists, add it
		my $r = &create_the_zone($reverse, "reverse", $debug, $nt);
		if( $r->{'nt_zone_id'} ) {
			&add_zone_records($r->{'nt_zone_id'}, $_[0], "reverse", $last_octet);
		}
	} else { 
		# An .arpa zone exists, update for the zone record 
		my $record = &get_zone_records($zoneid);
		&update_zone_records($record, $zoneid, $_[0], "reverse", $last_octet);
	}
};

sub add_zone_records {
	# variables we get passed: 0=zoneid, 1=zone, 2=template, 3=reverse octet
	my %zone_record;
	print "add_zone_records: $_[0], $_[1], $_[2]\n" if ($debug);
	# If you gave me a template, I'll use it, otherwise I'll use template #1
	$_[2] = ($_[2] ne "") ? $_[2] : "1";
	my $recs = &zone_record_template($_[0], $_[1], $_[2], $_[3], $newip, $mailip, $debug);
	# we'll get back an array of hashes for the 
	# records to create: nt_zone_id, name, type, address, weight
	if (scalar(@{$recs}) > 0 ) {
		for ( my $i = 0; $i < scalar(@{$recs}); $i++ ) {
			%zone_record = ( 
				nt_zone_id		=>	$recs->[$i]->{'nt_zone_id'}, 
				name				=>	$recs->[$i]->{'name'}, 
				ttl				=> "3600",
				description		=> "added by zones.pl",
				type				=>	$recs->[$i]->{'type'}, 
				address			=>	$recs->[$i]->{'address'}, 
				weight			=>	$recs->[$i]->{'weight'} 
			);
			if ($debug) {
				print "add_zone_records: $recs->[$i]->{'nt_zone_id'}, $recs->[$i]->{'name'}, ";
				print "$recs->[$i]->{'type'}, $recs->[$i]->{'address'}, $recs->[$i]->{'weight'}\n";
			};
			my $r = $nt->new_zone_record(%zone_record);
			if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
		};
	} else {
		die "Oh no, we didn't get any records back from the zone template!\n";
	};
};

sub update_zone_group {
	print "update_zone_group: updating group...";
	my %mz = ( zone_list=>"$_[0]", nt_group_id=>"$_[1]" );
	my $r = $nt->move_zones( %mz );
	if ( $r->{'error_code'} ne "200" ) {
		print "FAILED\n";
		print "$r->{'error_code'}: $r->{'error_msg'}\n";
	} else {
		print "success\n";
	};
};

sub update_the_nameservers {
	print "update_the_nameservers: $_[0], $_[1], $_[2], $_[3]...";
	#my %sz = (	nt_zone_id   => $_[0], 
	#			nt_group_id  => $_[1],
	#			zone         => $_[2],
	#			ttl			 => "86400",
	#			nameservers  => $_[3],
	#			mailaddr		 => "hostmaster\.$_[2]\." );
	my %sz = (	nt_zone_id   => $_[0], 
				nt_group_id  => $_[1],
				ttl			 => "86400",
				nameservers  => $_[3],
				mailaddr		 => "hostmaster\.$_[2]\." );
	my $r = $nt->edit_zone(%sz);
	if ( $r->{'error_code'} eq "200" ) {
		print "succeeded\n";
	} else {
		print "\nWARNING: update_the_nameservers: failed\n";
		print "   $r->{'error_code'}, $r->{'error_msg'}";
	};
};

sub update_zone_records {		
	#   We get passed 0=record (array of hashes) 1=zoneid 2=zone 3=template [4=last_octet]
	my %zone_record;
	my $updated="n";
	print "update_zone_records: $_[0], $_[1], $_[2], $_[3]\n" if ($debug);
		for ( my $i = 0; $i < scalar(@{$_[0]}); $i++ ) {
			print "update_zone_records: $_[0]->[$i]->{'name'}, $_[0]->[$i]->{'type'}, $_[0]->[$i]->{'address'}\n" if ($debug);
			if ( $_[0]->[$i]->{'type'} eq "A" ) {
				if ( $_[0]->[$i]->{'name'} eq "mail" && $_[0]->[$i]->{'address'} eq $oldip && $mailip ne "" ) {
					&edit_zone_record( 
						$_[0]->[$i]->{'nt_zone_record_id'},
						$_[1], 
						"oldmail",
						$oldip,
						$_[0]->[$i]->{'type'},
						$_[0]->[$i]->{'weight'}
					);

					%zone_record = (
						nt_zone_id     => $_[1],
						name           => $_[0]->[$i]->{'name'},
						ttl            => "3600",
						description    => "added by zones.pl",
						type           => "A",
						address        => $mailip,
						weight         => $_[0]->[$i]->{'weight'}
					);
					if ($debug) {
						print "add_zone_records: $_[0]->[$i]->{'nt_zone_id'}, $_[0]->[$i]->{'name'}, ";
						print "$_[0]->[$i]->{'type'}, $_[0]->[$i]->{'address'}, $_[0]->[$i]->{'weight'}\n";
					};   
					my $r = $nt->new_zone_record(%zone_record);    
					if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
				} else {
					print "didn't match record: $_[0]->[$i]->{'nt_zone_record_id'} on zone $_[2]. \n";
				};
			};
	};
};

sub edit_zone_record {
	my %query = ( nt_zone_record_id=>"$_[0]", nt_zone_id=>"$_[1]", name=>"$_[2]", address=>"$_[3]", type=>"$_[4]", weight=>"$_[5]" );
	print "values is: $_[0], $_[1], $_[2], $_[3], $_[4], $_[5] \n" if ($debug);
	my $r = $nt->edit_zone_record(%query);
	if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
};

sub delete_zone_records {		
	# We get passed 0=record (an array of hashes) 1=zoneid 2=zone
	print "delete_zone_records: $_[1], $_[2]\n" if ($debug);
	#if ($debug) { print "\n", scalar(@{$_[0]}), "\n"; };
	for ( my $i = 0; $i < scalar(@{$_[0]}); $i++ ) {
 		if ($debug) {
			printf "\t%8s  %25s  %30s...", $_[0]->[$i]->{'nt_zone_record_id'}, $_[0]->[$i]->{'name'}, $_[0]->[$i]->{'address'};
		};
		my %foo = ( nt_zone_record_id=>$_[0]->[$i]->{'nt_zone_record_id'} );
		my $r = $nt->delete_zone_record(%foo);
		if ( $r->{'error_code'} ne "200" ) { 
			print "FAILED.\n\t(Error $r->{'error_code'}: $r->{'error_msg'})\n"; 
		} else {
			print "SUCCESS.\n" if ($debug);
		};
	}
}

sub delete_zone {
	print "delete_zone: id: $_[0]...";
	my %del = ( zone_list=>$_[0] );
	if ($debug) { foreach my $key (keys %del) { print "$key $del{$key}..."; }; }
	my $r = $nt->delete_zones(%del);
	if ($r->{'error_code'} eq "200") { 
		print "SUCCESS.\n";
	} else {
		print "Error $r->{'error_code'}: $r->{'error_msg'}\n"; 
	};
};

sub find_zone_ids {
	print "find_zone_ids: searching for: %$_[0]%...";
	my $r = $nt->get_group_zones(nt_group_id=>$me->{nt_group_id},include_subgroups=>1,quick_search=>1,search_value=>$_[0]);
	#          this iterates on the returned list
	for ( my $i = 0; $i < scalar(@{$r->{'zones'}}); $i++ ) {
		if ($debug) { 
			print "hash values:"; print values %{$r->{'zones'}->[$i]}; print "\n";
			print "hash keys:"; print keys %{$r->{'zones'}->[$i]}; print "\n"; };
		print "zoneid: $r->{'zones'}->[$i]->{'nt_zone_id'}\n";
	};
	print "find_zone_ids: returning $r->{'zones'}" if ($debug);
	return $r->{'zones'};
};

sub nictool_connect {
	$nt->set(server_host=>"localhost");
	$nt->set(server_port=>"8010");
	my $r = $nt->login(username=>$user,password=>$pass);
	#print Dumper($r) if ( $debug);
	die "error logging in: ".$nt->is_error($r)."\n" if $nt->is_error($r); 
	die "Error: no session string returned.\n" if ! defined $r->{nt_user_session};
	$nt->set(nt_user_session=>$r->{nt_user_session});
	return $r;
};

sub parse_dot_file {
	print "parse_dot_file: $_[0]" if ($debug);
	open(DOT, $_[0]);
	while (<DOT>) {
		chomp $_;
		if ( $_ !~ /^#/ ) {
			my @r = split(" ");
			if ($r[0] eq "user") { $user = $r[1]; };
			if ($r[0] eq "pass") { $pass = $r[1]; };
			if ($r[0] eq "oldip") { $oldip = $r[1]; };
			if ($r[0] eq "newip") { $newip = $r[1]; };
			if ($r[0] eq "mailip") { $mailip = $r[1]; };
		};
	};
	if ($debug) {
		if ( $user ) { print ", $user"; };
		if ( $pass ) { print ", ******"; };
		if ( $oldip ) { print ", $oldip"; };
		if ( $newip ) { print ", $newip"; };
		if ( $mailip ) { print ", $mailip"; };
		print "\n";
	};
};

sub exit_with_warn {
	$nt->logout();
	undef $nt;
	die "$_[0]\n";
};

sub parse_form_data {
	if ( $ENV{'GATEWAY_INTERFACE'} ) {
		my %FORM_DATA = @_;
		my $query_string;
		if ($ENV{'REQUEST_METHOD'} eq "GET") {
			$query_string = $ENV{'QUERY_STRING'};
		} elsif ( $ENV{'REQUEST_METHOD'} eq "POST") {
			read (STDIN, $query_string, $ENV{'CONTENT_LENGTH'});
		};
		#print "query_string: $query_string \n";
		my @key_value_pairs = split (/&/, $query_string);
		foreach my $key_value (@key_value_pairs) {
			(my $key, my $value) = split(/=/, $key_value);
			$value =~ tr/+//;
			$value =~ s/%0D%0A/:/g;
			$value =~ s/%([\dA-Fa-f])/pack ("C", hex ($1))/eg;
			$key =~ tr/+//;
			$key =~ s/%([\dA-Fa-f][\dA-Fa-f])/pack ("C", hex($1))/eg;
	
			if(defined($FORM_DATA{$key})) {
				$FORM_DATA{$key} = join("\0", $FORM_DATA{$key}, $value);
		 	} else {
				$FORM_DATA{$key} = $value;
			};
		};
		return %FORM_DATA;
	};
};	

sub setup_global_vars {	
   $user       = $_[0]->{'nt_user'};
	$pass       = $_[0]->{nt_pass};
	$action     = $_[0]->{action};
	$dnsfarm    = $_[0]->{nsfarm};
	@zones      = split(/:/, $_[0]->{zone_list});
	$template   = $_[0]->{template};
	if ( $_[0]->{action} eq "del" ) {
		$delete    = "1";
	};
	$newip      = $_[0]->{newip};
	$mailip     = $_[0]->{mailip};
	$do_reverse = $_[0]->{reverse};
	$debug      = $_[0]->{debug};
};

sub show_http_vars {
	foreach my $key (keys %ENV) {
		print "key: $key $ENV{$key}\n"
	} 
};

sub show_key_value_pairs {
	foreach my $key (keys %{$_[0]}) {
		print "key: $key $_[0]{$key}\n";
	};
};
