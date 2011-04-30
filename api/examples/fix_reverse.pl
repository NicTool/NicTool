#!/usr/bin/perl

package Zones;

my $author = "Matt Simerson";
my $email  = "msimerson\@interland.com";

##
# ChangeLog
##
my $version = "0.92";
#

#######################################################################
#           Don't muck with anything below this line                  #
#######################################################################

use strict;
use NicToolTest;
use Getopt::Long;
use Data::Dumper;
use CGI qw(:standard);

use lib "/usr/home/matt/scripts";
use Zones::Templates;
use Zones::Nameservers;
use Zones::CreateZone;

use vars qw/ $user $pass $action $nsfarm $template $newip $oldip /;
use vars qw/ $mailip $delete $do_reverse $debug @zones $file /;
use vars qw/ $nt $me /;

$| = 1;

&process_shell_input;

if ( !$mailip && $newip ) { $mailip = $newip };

##
# Connect to the NicToolServer via the NicToolClient API
#
$me = &nictool_connect($user, $pass); 

chomp @zones;
foreach my $z ( @zones ) {
	$z = lc($z);
	if ($z ne "") {
		my $zonehash = &find_one_zone_id($z);
		&handle_mod_action($z, $zonehash);
	} else {
		print "main:\t" if $debug;
		print "WARNING: zone name is empty! Skipping.\n";
	};
};
print "Exiting successfully.\n";

exit_with_warn( "Exiting normally\n" );


###
###  Subroutines
###

sub handle_mod_action {
	my ($zone, $zhash) = @_;
	if ( $zhash && $zhash->{'nt_zone_id'} ) { 
		print "modifying $zone...\n"; 
		&update_zone($zone, $zhash);
	} else {
		print "handle_mod_action:\t" if $debug;
		print "WARNING: zone $zone does not exist! Skipping.\n"; 
	};
};

sub handle_add_action {
	my ($zone, $zhash) = @_;

	if ( $zhash && $zhash->{'nt_zone_id'} ) { 
		print "handle_add_action:\t" if $debug;
		print "WARNING: zone $zone already exists, skipping\n"; 
	} else { ;
		if ( $nsfarm && $template ) {
			my $r = &create_the_zone($zone, $nsfarm, $debug, $nt);
			if ( $r->{'nt_zone_id'} ) {
				print "success\n.";
				&add_zone_records($r->{'nt_zone_id'}, $zone, $template);
			} else {
				print "handle_add_action:\t" if $debug;
				print "failed to create: $zone with $template template.\n";
			};
		} else { 
			print "handle_add_action:\t" if $debug;
			print "FAILED: no dnsfarm: $nsfarm or template: $template.\n";
		};
	};
};

sub handle_del_action {
	my ($zone, $zhash) = @_;
	my $zoneid;
	if ($zhash) {
		$zoneid = $zhash->{'nt_zone_id'};
	};

	if (! $zoneid ) { 
		print "handle_del_action:\t" if $debug;
		print "WARNING: zone doesn't exist: $zone\n"; 
	} else {
		my $record = &get_zone_records($zoneid, "10000");
		&delete_zone_records($record, $zoneid, $zone);
		&delete_zone($zoneid, $zone);
	};
};

sub update_zone {
	my ($zone, $zhash) = @_;
	my $zoneid;
	if ($zhash) { $zoneid = $zhash->{'nt_zone_id'}; };

	$nsfarm = "nameserve.net";
	if ($zoneid) {
		if ( $nsfarm ) {
			my $ns_old = &find_zone_nameservers($zoneid, $zhash->{'nt_group_id'});
			my @ns = &get_ns($nsfarm, $debug);
			if (!$ns[0]) { exit_with_warn( "nameserver $nsfarm doesn't exist\n" ); };
			if ( $ns[0] ne $ns_old->[0]->{'nt_group_id'} ) {
				&update_zone_group( $zoneid, $ns[0] );
			};
			if ( $ns[1] eq $ns_old->[0]->{'nt_nameserver_id'} &&  $ns[2] eq $ns_old->[1]->{'nt_nameserver_id'} &&  $ns[3] eq $ns_old->[2]->{'nt_nameserver_id'} ) {
				print "update_zone: nameservers up to date, skipping ns update.\n" if ($debug);
			} else {
				print "update_zone: gotta update the nameservers!\n" if ($debug);
				&update_the_nameservers( $zoneid, $ns[0], $zhash->{'zone'}, "$ns[1],$ns[2],$ns[3]" );
			};
		};
	} else {
		print "update_zone:\t" if $debug;
		print "WARNING: zone doesn't exist: $zone\n"; 
	};
};

sub find_one_zone_id {
	my ($zone) = @_;
	print "find_one_zone_id:\t" if $debug;
	print "searching for $zone...";
	#                search for an exact match on the zone
	my $r = $nt->get_group_zones(
		nt_group_id=>$me->{nt_group_id},
		include_subgroups=>1,
		Search=>1,
		"1_field"=>"zone",
		'1_option'=>"equals",
		'1_value'=>$zone 
	);

	if ( $r->{'zones'}->[0]->{'nt_zone_id'} ) {
		print "found: $r->{'zones'}->[0]->{'nt_zone_id'}\n";
		return $r->{'zones'}->[0];
	} else {
		print "FAILED.\n";
		return 0;
	};
};

sub find_zone_nameservers {
	my ($zoneid, $groupid) = @_;
	print "find_zone_nameservers: zoneid: $_[0], groupid: $_[1]\n" if $debug;
	my %get_zone = ( nt_zone_id=>$zoneid, nt_group_id=>$groupid );
	my $r = $nt->get_zone(%get_zone);
	if ($debug) {
		print "find_zone_nameservers: $r->{'nameservers'}->[0]->{'nt_nameserver_id'}, ";
		print "$r->{'nameservers'}->[1]->{'nt_nameserver_id'}, ";
		print "$r->{'nameservers'}->[2]->{'nt_nameserver_id'}\n";
	};
	return $r->{'nameservers'};
};

sub get_zone_records_by {
	my ($zoneid, $field, $value) = @_;
	my %query = ( nt_zone_id=>"$zoneid" );

	if ($field) { 
		$query{'Search'}   = 1;
		$query{"1_field"}  = $field;
		$query{"1_option"} = "equals";
		$query{"1_value"}  = $value;
	};

	my $r = $nt->get_zone_records(%query);
	print "get_zone_records_by: $zoneid\n";
	if ($r->{'records'}->[0] && $debug) {
		for ( my $i = 0; $i < scalar(@{$r->{'records'}}); $i++ ) {
			printf "%35s  %5s  %35s\n", $r->{'records'}->[$i]->{'name'}, $r->{'records'}->[$i]->{'type'}, $r->{'records'}->[$i]->{'address'};
		};
	};
	return $r->{'records'};
};

sub get_zone_records {
	my ($zoneid, $limit) = @_;
	my %query = ( 
		nt_zone_id=>"$zoneid",
		limit => $limit );
	my $r = $nt->get_zone_records(%query);
	if ($debug) { 
		print "get_zone_records: $zoneid\n";
		print "get_zone_records: r=$r, r->records=$r->{'records'} \n" if $debug;
		for ( my $i = 0; $i < scalar(@{$r->{'records'}}); $i++ ) {
			printf "%35s  %5s  %35s\n", $r->{'records'}->[$i]->{'name'}, $r->{'records'}->[$i]->{'type'}, $r->{'records'}->[$i]->{'address'};
			print "\t$r->{'records'}->[$i]->{'name'}, $r->{'records'}->[$i]->{'type'}, $r->{'records'}->[$i]->{'address'} \n" if $debug;
		};
		print "get_zone_records: returning $r->{'records'}\n" if $debug;
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
		my $record = &get_zone_records($zoneid, "100");
		&update_zone_records($record, $zoneid, $_[0], "reverse", $last_octet);
	}
};

sub add_zone_records {
	my ($zoneid, $zone, $template, $reverse) = @_;
	my %zone_record;

	print "add_zone_records: $zoneid, $zone, $template\n" if ($debug);

	# If you gave me a template, I'll use it, otherwise I'll use template #1
	$template = ($template ne "") ? $template : "1";

	# we'll get back an array of hashes for the records to create: 
	# nt_zone_id, name, type, address, weight
	my $recs = &zone_record_template($zoneid, $zone, $template, $reverse, $newip, $mailip, $debug);

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
			if ( $r->{'error_code'} ne "200" ) { 
				print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; 
			};
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
	my %sz = (	nt_zone_id   => $_[0], 
				nt_group_id  => $_[1],
	#			zone         => $_[2],
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
	my ($rec, $zid, $zone, $template, $last_octet) = @_;
	my %zone_record;
	my $updated = "n";

	print "update_zone_records: $zid, $zone, $template, $last_octet\n" if ($debug);
	if ( $template ne "" ) {
		my $new = &zone_record_template($zid, $zone, $template, $last_octet, $newip, $mailip, $debug);
		# we'll get back an array of hashes: nt_zone_id, name, type, address, weight
		#
		# next we'll iterate over each new record to create and check to see 
		#  if there isn't an existing record to update first
		for ( my $i = 0; $i < scalar(@{$new}); $i++ ) {
			for ( my $old = 0; $old < scalar(@{$rec}); $old++ ) {
				if ( $rec->[$old]->{'type'} eq $new->[$i]->{'type'} && $rec->[$old]->{'name'} eq $new->[$i]->{'name'} ) {
					print "updating: $rec->[$old]->{'nt_zone_id'}, $rec->[$old]->{'name'}, $rec->[$old]->{'type'} from $rec->[$old]->{'address'} to $new->[$i]->{'address'}\n" if ($debug);
					%zone_record = ( 
						nt_zone_record_id => $rec->[$old]->{'nt_zone_record_id'},
						nt_zone_id	=>	$new->[$i]->{'nt_zone_id'},
						name			=>	$new->[$i]->{'name'}, 
						ttl			=> "3600",
						type			=>	$new->[$i]->{'type'}, 
						address		=>	$new->[$i]->{'address'}, 
						weight		=>	$new->[$i]->{'weight'},
						description => $rec->[$old]->{'description'}
					);
					my $r = $nt->edit_zone_record(%zone_record);
					if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
					$updated="y";
					$old="100000";
				} else {
					print "No match: $new->[$i]->{'type'}, $new->[$i]->{'name'} !=  $rec->[$old]->{'type'}, $rec->[$old]->{'name'}\n" if ($debug);
					$updated="n";
				};
			};
			if ( $updated ne "y" ) {
				%zone_record = ( 
					nt_zone_id	=>	$new->[$i]->{'nt_zone_id'},
					name			=>	$new->[$i]->{'name'}, 
					type			=>	$new->[$i]->{'type'}, 
					address		=>	$new->[$i]->{'address'}, 
					weight		=>	$new->[$i]->{'weight'} 
				);
				print "update_zone_record: $new->[$i]->{'name'}, $new->[$i]->{'type'}, $new->[$i]->{'address'}, $new->[$i]->{'weight'}\n" if ($debug);
				my $r = $nt->new_zone_record(%zone_record);
				if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
			};
		};

	} else {
		for ( my $i = 0; $i < scalar(@{$rec}); $i++ ) {
			print "update_zone_records: $rec->[$i]->{'name'}, $rec->[$i]->{'type'}, $rec->[$i]->{'address'}\n" if ($debug);
			if ( $rec->[$i]->{'type'} eq "A" ) {
				if ( $rec->[$i]->{'name'} eq "mail" && $rec->[$i]->{'address'} eq $oldip && $mailip ne "" ) {
					&edit_zone_record( 
						$rec->[$i]->{'nt_zone_record_id'},
						$zid, 
						$rec->[$i]->{'name'},
						$mailip,
						$rec->[$i]->{'type'},
						$rec->[$i]->{'weight'}
					);
				} elsif ( $rec->[$i]->{'address'} eq $oldip ) {
					&edit_zone_record( 
						$rec->[$i]->{'nt_zone_record_id'}, 
						$zid, 
						$rec->[$i]->{'name'}, 
						$newip, 
						$rec->[$i]->{'type'}, 
						$rec->[$i]->{'weight'}
					);
				} else {
					print "didn't match record: $rec->[$i]->{'nt_zone_record_id'} on zone $zone. \n";
				};
			} elsif ( $rec->[$i]->{'type'} eq "MX" ) {
				if ( $rec->[$i]->{'name'} eq "$zone\." && $rec->[$i]->{'address'} eq "mail.$zone\." ) {
					print "mx for $zone is ok\n";
				} elsif ( $rec->[$i]->{'name'} eq "$zone\." && $rec->[$i]->{'address'} eq $oldip ) {
					print "WARNING: mx record must be a FQDN (see RFC 1035) - updated from $rec->[$i]->{'address'} to mail\.$zone\.\n";
					&edit_zone_record( 
						$rec->[$i]->{'nt_zone_record_id'}, 
						$zid, 
						$rec->[$i]->{'name'}, 
						"mail\.$zone\.", 
						$rec->[$i]->{'type'}, 
						$rec->[$i]->{'weight'}
					);
				} else {
					print "WARNING: mx for $zone is unverified\n";
				};
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
	my ($record, $zoneid, $zone) = @_;
	print "delete_zone_records: $zoneid, $zone\n" if ($debug);
	#if ($debug) { print "\n" . scalar(@{$record}) . $n; };
	for ( my $i = 0; $i < scalar(@{$record}); $i++ ) {
 		if ($debug) {
			printf "\t%8s  %25s  %30s...", $record->[$i]->{'nt_zone_record_id'}, $record->[$i]->{'name'}, $record->[$i]->{'address'};
		};
		my %foo = ( nt_zone_record_id=>$record->[$i]->{'nt_zone_record_id'} );
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
			print "hash keys:"; print keys %{$r->{'zones'}->[$i]}; print "\n"; 
		};
		print "zoneid: $r->{'zones'}->[$i]->{'nt_zone_id'} \n";
	};
	print "find_zone_ids: returning $r->{'zones'}" if ($debug);
	return $r->{'zones'};
};

sub nictool_connect {
	my ($user, $pass) = @_;
	$nt = NicToolTest->new;
	$nt->set(server_host=>"localhost");
	$nt->set(server_port=>"8010");
	my $r = $nt->login(username=>$user,password=>$pass);
	#print Dumper($r) if ( $debug);
	warn "error logging in: ".$nt->is_error($r)."\n" if ( $nt->is_error($r) && $debug); 
	if ( ! defined $r->{nt_user_session} ) {
		warn "Error: no session string returned.\n" if $debug;
		return 0;
	};
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
	close(DOT);
};

sub exit_with_warn {
	$nt->logout();
	undef $nt;
	die "$_[0]\n";
};

sub setup_http_vars {	
	$action     = param('action');
	$newip      = param('newip');
	$nsfarm     = param('nsfarm');
	$mailip     = param('mailip');
	$template   = param('template');
	$user       = param('user');
	$pass       = param('pass');
	$do_reverse = param('reverse');
	$debug      = param('debug');

	my $zones   = param('zone_list');
	chomp $zones;
	@zones   = split("\n", $zones);
	foreach my $zone (@zones) {
		$zone = lc($zone);
		($zone) = $zone =~ /([a-z0-9\.\-]*)/;
	};
	print "zones: ". join ("\t", @zones) . "\n" if $debug;
};

sub verify_global_vars {
	if ( param('newip') eq "" ) {
		print_zone_request_form("The field New IP must not be blank!");
	};
};

sub show_http_vars {
	print "HTTP ENV vars are:\n" if $debug;
	foreach my $key ( param() ) {
		my $foo = param($key);
		print "key: $key $foo\n"
	} 
};

sub show_key_value_pairs {
	# Just prints out the values of a hash passed to it
	my (%array) = @_;
	foreach my $key (keys %array) {
		print "key: $key $array{$key}\n";
	};
};

sub get_group_id {
	# fetches the group id of a zone based on it's NicTool group name
	# http://admin.ns.interland.net/NicToolDocs/api.htm#GETGROUPSUBGROUPSFUNC

	my ($group) = @_;
	my $r = $nt->get_group_subgroups(
		'nt_group_id'       => $me->{nt_group_id},
		'include_subgroups' => 1, 
		'1_field'           => "group",
		'1_option'          => "equals",
		'1_value'           => $group );
	return $r->{'groups'}->[0];
};

sub print_login_form {
	my ($message) = @_;
	my $formatted_message = "<center><font color=\"red\" font=\"sans serif\" size=\"-2\">$message</font></center>"; 
	print header('text/html'),
		start_html("Zones Login Page"),
		h1({-align=>'center'}, 'Zones Login Page'),
		hr, 
		start_form({-name=>"ZonesForm", onSubmit=>"validateForm"}),
			table({-border=>0, -width=>"35%", align=>'center'},
			Tr({-align=>'middle'},
			[
				td(['', $formatted_message ]),
				td(['Username', textfield('user')]),
				td(['Password', password_field('pass')]),
				td([submit, '']),
			])
			),
		end_form,
		hr;
		print "<font size=\"-2\" face=\"sans serif\">Zones $version By Matt Simerson</font><br>";
};

sub print_zone_request_form {
	my @templates = &template_list;
	my @nslist = sort (&get_ns_list);
	my @actions = ( "", "add", "mod", "del");

	my $font   = '<font face="Arial, Helvetica, sans-serif">';
	my $font2  = '<font face="Arial, Helvetica, sans-serif" size="+2">';
	my $font_1 = '<font face="Arial, Helvetica, sans-serif" size="-1">';
	my $font_2 = '<font face="Arial, Helvetica, sans-serif" size="-2">';

	print header('text/html'),
		start_html(-title => "Zone Import Request", 
					-author  => $email,
					-BGCOLOR => 'white' ),
		h1({-align=>'center'}, $font2.'Zone Import Request'),
		start_form,
			table({-border=>0, -width=>"95%"},
			Tr({-align=>'LEFT'},
			[
				td({-colspan=>'4'}, [hr]),
				td({-colspan=>'4'}, [$font_1."v$version - Status: Stable - Real Time Processing via CGI.pm"]),
				td({-colspan=>'4'}, [hr]),
				td(['', $font_1.'Zone Options', '', $font_1.'IP Settings']),
				td([$font_1.'Action: ', popup_menu(-name=>'action', -values=>[@actions]), $font_1.'New IP', textfield(-name=>'newip', -size=>15)]),
				td([$font_1.'Nameserver Farm', popup_menu(-name=>'nsfarm', -values=>[@nslist], -default=>'interland.net'), $font_1.'Mail IP', textfield(-name=>'mailip', -size=>15).'<br>'.$font_2.'(if different than new)']),
				td([a({href=>"http://admin.ns.interland.net/templates.html"}, $font_1."Template").'<br>'.$font_2.'(click for examples)', popup_menu(-name=>'template', -values=>[@templates]),' ', ' ' ]),
				'<td></td><td colspan="3"><hr></td>',
				'<td></td><td colspan="3">'.$font_1.'User Information: This form will be submitted using YOUR NicTool login name and password. The logs will reflect this.</td>',
				'<td></td><td colspan="3"><hr></td>',
				td([$font_1.'NT User: ', textfield(-name=>'user', -size=>'15'), $font_1.'NT Pass', password_field(-name=>'pass', -size=>15)]),
				'<td></td><td colspan="3"><hr></td>',
				'<td></td><td colspan="3">'.$font_1.'Zones: This has to be a zone or list of zones. Zones must be entered one per line. Zones have two (and ONLY two) parts.',
				'<td></td><td colspan="3"><hr></td>',
				'<td></td><td colspan="2">	<textarea name="zone_list" rows="10" cols="40"></textarea></td><td><h3>NOTICE:</h3><br>A zone is also known as a domain name. The same rules apply.<br><br>This is a zone: interland.net<br><br>This is NOT: www.interland.net<br></td>',
				td({-colspan=>'4', -align=>'center'}, hr),
				td(['Options', checkbox(-name=>'debug', -label=>' Debug'),'', checkbox(-name=>'reverse', -label=>' Reverse').$font_2.'<br>(Create Matching PTR)' ]),
			] )
			),
			,p,
		submit,
		end_form,
		hr;
};

				#td({-colspan=>'4'}, 'Zones: This has to be a zone or list of zones. Zones must be entered one per line. Zones have two (and ONLY two) parts.'),

sub process_cgi_input {
	if ( param('user') && param('pass') ) {
		$me = &nictool_connect(param('user'), param('pass') );    # Log into NicTool
		if ($me) {                               # if NT login is successful
			if ( param('action') ) {
				# Process form inputs
				print header('text/html');
				print "process_cgi_input: processing form inputs<br>" if $debug;
				&setup_http_vars;
				&verify_global_vars;
				#&show_http_vars if $debug;
				return 1;
			} else {
				&print_zone_request_form;
			};
		} else {
			&print_login_form("Invalid Login, Try Again!");
		};
		&exit_with_warn("process_cgi_input: exiting normally");
	} else {
		&print_login_form("Enter your NicTool username and password");
		&exit_with_warn("process_cgi_input: exiting normally");
	};
};

sub print_usage {
	print "\n\t\t\tZones.pl  by $author               $version\n\n";
	print "usage: $0 -a <action> -u <user> -p <pass> [-z <zone> -f <file>]\n
      add: -a add -ns interland.net -t 2
      del: -a del\n
		mod: -a mod\n
      --template --oldip --newip --mailip --debug\n\n";
};

sub process_shell_input {

	# get options from the command line
	my %options = (
   	'user=s' 	 => \$user,
   	'pass=s'		 => \$pass,
		'action=s'	 => \$action,
		'ns=s'		 => \$nsfarm,
		'zone=s'		 => \@zones,
   	'file=s' 	 => \$file,
		'template=s' => \$template,
		'delete=s'	 => \$delete,
		'newip|ip=s' => \$newip,
		'oldip=s'	 => \$oldip,
		'mailip=s'	 => \$mailip,
		'reverse=s'  => \$do_reverse,
		'debug|v=s'  => \$debug,
	);
	&GetOptions (%options);

	my ($homedir) = (getpwuid ($<))[7];        # get the user's home dir
	if (!$user && -r "$homedir/\.zones") { &parse_dot_file("$homedir/\.zones"); };

	if (!$user || !$pass) { &print_usage; die "Failed to get a username and password!\n"; };

	if ( $action eq "add" && !$newip ) {
		die "\n You must provide an IP address (-newip xx.xx.xx.xx) \n\n";
	} elsif ( $action eq "add" && !$template) {
		die "\n You must select a template (-template <nameserver.com>)\n\n";
	} elsif ( $action eq "add" && !$nsfarm ) {
		die "\n You must select a dns farm (-ns <xxxx.com>)\n\n";
	};

	##
	# If we were handed a file on the command line, we expect it's a list
	# of zones that we're supposed to process
	#
	if ( $file ) { 
		if ( -r $file ) {
			open(INPUT, $file ) or die "Unable to open $file: $!\n";
				while ( <INPUT> ) { 
					chomp $_; 
					my @r = split(/ /, $_); 
					push(@zones, lc($r[0])); 
				};
			close (INPUT);
		}; 
	};
	print "root: @zones\n" if ($debug);
};



my $javas = "<script language='JavaScript'>
function validateForm() {
	if(formName.nt_user.value == '') {
		alert('You must enter a NIC Tool Username');
		formName.nt_user.focus();
		event.returnValue=false;
	}
	else if(formName.nt_pass.value == '') {
		alert('You must enter a NIC Tool Password');
		formName.nt_pass.focus();
		event.returnValue=false;
	}
	else if(formName.action.options[0].selected) {
		alert('You must select an action');
		formName.action.focus();
		event.returnValue=false;
	}
	else if(formName.zone_list.value == '') {
		alert('You must enter at least one zone name');
		formName.zone_list.focus();
		event.returnValue=false;
	}
	else if((formName.action.options[1].selected)||(formName.action.options[2].selected)) {
		// add / mod
		if(formName.newip.value == '') {
			alert('You must enter an IP address to add/modify zones');
			formName.newip.focus();
			event.returnValue=false;
		}
		else if(formName.ns_farm.options[0].selected) {
			alert('You must select a Name Server Farm to add/modify zones');
			formName.ns_farm.focus();
			event.returnValue=false;
		}
		else if(formName.template.options[0].selected) {
			alert('You must select a template to add/modify zones');
			formName.template.focus();
			event.returnValue=false;
		}
		else if(formName.template.options[0].selected) {
			alert('You must select a template to add/modify zones');
			formName.template.focus();
			event.returnValue=false;
		}
	}
	else if(formName.action.options[3].selected) {
		// del
		var splitIndex = formName.zone_list.value.indexOf('\n');
		splitIndex++;
		if((splitIndex > 0) && (splitIndex < formName.zone_list.value.length)) {
			alert('You may only delete one zone at a time');
			formName.zone_list.focus();
			event.returnValue=false;
		}
	}

}
</script>";

#<form name="formName" action="/cgi-bin/zones.pl" onSubmit="validateForm()">
#<select name="action">
#<input type="text" name="newip" size="15">
#<select name="nsfarm">
#<input type="text" name="mailip" size="15">
#<select name="template">
#<input type="text" name="nt_user" size="15">
#<input type="password" name="nt_pass" size="15">
#<textarea name="zone_list" rows="10" cols="40"></textarea>
#<input type="checkbox" name="debug" value="1"> Debug<br>
#<input type="checkbox" name="reverse" value="1"> Reverse<br>
#<input type="Submit" name="Submit" value="Submit">
#<input type="reset" name="reset" value="Reset">
