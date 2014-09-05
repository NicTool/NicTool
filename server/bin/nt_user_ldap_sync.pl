#!/usr/bin/perl

=begin comment

The MIT License (MIT)

Copyright (c) 2014 Vyronas Tsingaras, vtsingaras@it.auth.gr

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=end comment

=cut

use Net::LDAP;
use Net::LDAPS;
#Edit lib directive with path to NicToolServerAPI.pm parent directory
use lib "/home/vtsingaras/NicTool/client/lib/";
use NicToolServerAPI;
use strict;
use warnings;

#LDAP Settings, edit
my $server = "ldap.example.org";
my $port = 636;
my $basedn = "ou=People,o=example,c=org";
my $filter = 'ldapobjectfilter';
my $binddn = "uid=searcher,o=example,c=org";
my $bindpw = "password";
my $new_user_group = "newusers_example";
#NicToolServer settings, edit
my $ntconf = { ntuser  =>  'root',
	    ntpass  =>  'rootpass',
	    nthost  =>  '127.0.0.1',
	    ntport  =>  8082,
	};
#Stop editing now

my $search_ldap = Net::LDAPS->new($server, port=>$port);
$search_ldap->bind($binddn, password=>"$bindpw");
#Get all people
my $result = $search_ldap->search(base=>$basedn, filter=>$filter);
die $result->error if $result->code;
print ("Importing: " . $result->count . " accounts\n");

#Setup NicTool
my $nt = new NicToolServerAPI;
$NicToolServerAPI::server_host = $ntconf->{nthost};
$NicToolServerAPI::server_port = $ntconf->{ntport};
$NicToolServerAPI::data_protocol = "soap";
$NicToolServerAPI::use_https_authentication = 0;
#Login to NicTool Server
my $ntuser = $nt->send_request(action => "login", username => $ntconf->{ntuser}, password => $ntconf->{ntpass});
if( $ntuser->{error_code} ) {
    print( "Unable to log in: " . $ntuser->{error_code} . " " . $ntuser->{error_msg} . "\n" );
    exit 1;
} else {
    print( "Logged in as " . $ntuser->{first_name} . " " . $ntuser->{last_name} . "\n" );
}
#Find group
my $ntgroup_id;
my $resp;
$resp = $nt->send_request(
	action => "get_group_subgroups",
	nt_user_session => $ntuser->{nt_user_session},
	nt_group_id => ( $ntuser->{nt_group_id} ),
	include_subgroups   => 1,
	search_value        => $new_user_group,
	quick_search        => 1,
);
if( @{$resp->{groups}} == 0 ) {
	warn( "*** Group " . $new_user_group . " not found.\n\n" );
	exit 1;
} elsif( @{$resp->{groups}} > 1 ) {
	warn( "*** Group parameter too vague - found more than one match.\n" );
	warn( "*** Please resubmit query.\n\n" );
	exit 1;
} else {
	# There should be only one
	print( "Binding to group " . $resp->{groups}->[0]->{name} . "\n" );
	$ntgroup_id = $resp->{groups}->[0]->{nt_group_id};
}
#Parse LDAP results
next_user: foreach my $entry ($result->entries) {
	my $fname = $entry->get_value("givenName");
	my $lname = $entry->get_value("sn");
	my $username = $entry->get_value("uid");
	my $email = $entry->get_value("mail") || 'notgiven@example.org';

	#Create users in NicTool
	#First check if user exists in some other group
	#Find Root group (usually same as root's group)
	$resp = $nt->send_request(action => "get_group_users", nt_user_session => $ntuser->{nt_user_session}, nt_group_id => 					$ntgroup_id, include_subgroups => 1, limit => 255);
	foreach my $nictool_user (@{$resp->{list}}) {
		next if $username eq $nictool_user->{username};
	}		

	$ntgroup_id = $ntuser->{nt_group_id};
	$resp = $nt->send_request(action => "new_user", nt_user_session => $ntuser->{nt_user_session}, first_name => "$fname",
				last_name => "$lname", email => "$email", username => "$username",
				nt_group_id => $ntgroup_id,password => "scekriitp4ss",
				password2 => "scekriitp4ss", inherit_group_permissions => 1);
	print( "Creating user: " . $username . "\n" );
	#Don't die if user exists already
	die $resp->{error_msg} if ( ($resp->{error_code} != 300) && (($resp->{error_code} != 300)));
}
#End user creation
#Find Root group (usually same as root's group)
$ntgroup_id = $ntuser->{nt_group_id};
#Get list of nictool users
$resp = $nt->send_request(action => "get_group_users", nt_user_session => $ntuser->{nt_user_session}, nt_group_id => $ntgroup_id, include_subgroups => 1, limit => 255);
foreach my $nictool_user (@{$resp->{list}}) {
    my $uname = $nictool_user->{username};
    #Check if user is LDAP user
    my $result = $search_ldap->search(base=>$basedn, filter=>"(&(uid=$uname)$filter)", attrs=>['dn']);
    next if $result->count == 1;
    #Deleting the root account is maybe a bad idea.
    next if $uname eq "root";
    #User doesn't exist on LDAP anymore, delete him
    print ("Deleting user: " . $uname . "\n");
    $resp = $nt->send_request(action => "delete_users", nt_user_session => $ntuser->{nt_user_session}, user_list => "$nictool_user->{nt_user_id}");
    die $resp->{error_msg} if $resp->{error_code} != 200;
}

$search_ldap->unbind;

