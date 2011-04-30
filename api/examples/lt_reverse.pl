#!/usr/bin/perl

use NicToolTest;
use Getopt::Long;
use Data::Dumper;
use CGI qw(:standard);
use strict;

use lib ".";
use Zones::Nameservers;
use Zones::CreateZone;

$| = 1;

my($user, $pass, $action, $dnsfarm, $template );
my($delete, $do_reverse, $debug, @zones, $file);

my %options = (
  	'user=s' 	=> \$user,
  	'pass=s'		=> \$pass,
	'action=s'	=> \$action,
	'ns=s'		=> \$dnsfarm,
	'zone=s'		=> \@zones,
  	'file=s' 	=> \my $file,
	'delete=s'	=> \$delete,
	'reverse=s'	=> \$do_reverse,
	'debug|v=s'	=> \$debug,
);
&GetOptions (%options);
my ($homedir) = (getpwuid ($<))[7];        # get the user's home dir
if (!$user && -r "$homedir/\.zones") { &parse_dot_file("$homedir/\.zones"); };

#print @zones;
#die "@zones";

if (!$user || !$pass || !$action) { 
	print "\nusage: $0 -a <action> -u <user> -p <pass> [-z <zone> -f <file>]\n
      add: -a add -ns interland.net -t 2
      del: -a del -d 1\n      mod: -a mod --debug\n\n";
	die;
};

if ( $file ) { 
	if ( -r $file ) {
		open(INPUT, $file ) or die "Unable to open input $file: $!\n";
			my $i = 0;
			while ( <INPUT> ) { 
				chomp $_; 
				my @r = split(/,/, $_); 
				my %s = ( sn => lc($r[0]), ip => $r[1], domain => lc($r[2]) ); 
				@zones[$i] = \%s;
				$i++;
			};
		close (INPUT);
	};
};

my $nt = NicToolTest->new;
my $s;                      #store session string
my $me = &nictool_connect();  # session string is stored for further queries.

foreach my $z ( @zones ) {
	#print "$z->{'ip'} $z->{'domain'} $z->{'sn'} \n";

	$z->{'ip'} =~ /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/;
	my $reverse = "$3.$2.$1.in-addr.arpa";
	my $last_octet = $4;

	my $zonehash = &find_one_zone_id($reverse);
	my $zoneid = $zonehash->{'nt_zone_id'};

	if ( !$zoneid ) {
		print "Adding zone $reverse...";
		my $r = &create_the_zone($reverse, "interland.net", $debug, $nt);
		if ( $r->{'nt_zone_id'} ) {
			print "success\n.";
		} else { 
			print "FAILED: \n";
		};
	};

	my $record = &find_one_zone_record($zoneid, $last_octet);
	if ( $record->[0]->{'name'} ne "" ) {
		&update_zone_record($record, $zoneid, $reverse, "", $last_octet, $z->{'domain'}, $z->{'sn'});
	} else {
		# variables we get passed: 0=zoneid, 1=zone, 2=template, 3=reverse octet
		&add_zone_record($zoneid, $z->{'domain'}, "", $last_octet, $reverse, $z->{'sn'} );
	};
};

if($user eq 'ofs') { print "+ 100 DNS finished correctly\n"; }
exit_with_warn( "Exiting normally\n" );
exit 0;

###
###  Subroutines
###

sub update_zone_record {		
	#   We get passed 0=record (array of hashes) 1=zoneid 2=zone 3=template [4=last_octet] [5=domain] [6=sn]
	#print "update_zone_record: $_[0], $_[1], $_[2], $_[3], $_[4], $_[5], $_[6]\n";

	if ( $_[0]->[0]->{'name'} eq $_[4] ) {
		if ( $_[0]->[0]->{'address'} eq "$_[5]\." ) {
			print "skipped : $_[4]\.$_[2] = $_[5], $_[6]\n";
		} else {
			print "conflict: $_[4]\.$_[2] = $_[5]($_[0]->[0]->{'address'}), $_[6]\n";
		};
	} else {
		print "not updated: $_[4]\.$_[2] = $_[5]\n";
	};
};

sub add_zone_record {
	# variables we get passed: 0=zoneid, 1=zone, 2=template, 3=reverse octet
	print "add_zone_record: $_[0], $_[1], $_[2], $_[3]\n" if ($debug);
	my %zr = ( 
		nt_zone_id		=>	$_[0],
		name				=>	$_[3],
		ttl				=> "3600",
		description		=> "added by zones.pl",
		type				=>	"PTR",
		address			=>	"$_[1]\.",
		weight			=>	""
	);
	my $foo = \%zr;
	print "adding  : $foo->{'name'}\.$_[4], $foo->{'address'}, $_[5]\n";
	my $r = $nt->save_zone_record(%zr);
	if ( $r->{'error_code'} ne "200" ) { print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n"; };
};

sub find_one_zone_id {
	print "find_one_zone_id:\t...$_[0]... = " if ($debug) ;
	#                search for an exact match on the zone
	my $r = $nt->get_group_zones(
		nt_group_id=>1,
		include_subgroups=>1,
		Search=>1,
		"1_field"=>"zone",
		'1_option'=>"equals",
		'1_value'=>$_[0]
	);
	if ( $r->{'error_code'} eq "200" ) {
		print "$r->{'zones'}->[0]->{'nt_zone_id'}\n" if ($debug) ;
		return $r->{'zones'}->[0];
	} else {
		print "failed.\n\tWARNING: $r->{'error_msg'}\n" if ($debug);
	};
};


sub find_one_zone_record {
	my $r = $nt->get_zone_records(
			nt_zone_id  => "$_[0]",
			Search		=> 1,
			"1_field"	=> "name",
			"1_option"	=> "equals",
			"1_value"	=> $_[1]
	);
	#print "find_one_zone_record: $_[0]\n";
	return $r->{'records'};
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
		};
	};
	if ($debug) {
		if ( $user ) { print ", $user"; };
		if ( $pass ) { print ", ******"; };
		print "\n";
	};
};

sub exit_with_warn {
	$nt->logout();
	undef $nt;
	die "$_[0]\n";
};

