#!/usr/bin/perl

package NicTool::Zones;

##
# NicTool::Zones by Matt Simerson <matt@tnpi.biz>
##

$NicTool::Zones::VERSION = "1.03";

##
# Description
##
# NicTool comes with a rich API for managing DNS information. This script uses
# that API to handle DNS provisioning, mass updates, and other functions. Right
# now I provide some basic functions via Apache and Perl.
#
# NicTool API docs: http://www.nictool.com/docs/api/
#

##
# ChangeLog
##
#
#  1.02  - 10.03.04 - Matt  - Integrated with NicTool (API functions)
#  1.01  - 07.08.03 - Matt  - Updated code forks back together (oops)
#  0.93  - 02.17.03 - Matt  - Added check functions
#                           - Prototyped my subroutines
#                           - Code fixes as necessary due to prototyping
#                           - Created HTTP.pm and moved HTTP forms into it
#                           - Finished moving UpdateZoneRecords to it's own pm
#                           - Miscellaneous code formatting changes for
#                             enhanced legibililty
#  0.92  - 02.11.03 - Matt  - Added check for $zhash before doing checks on
#                             $zhash->values.
#                           - Fixed a problem with add_zone_records introduced
#                             in 0.90. --Jason's OFS problem
#  0.91  - 01.24.03 - Matt  - Mozilla doesn't render text/plain as HTML
#  0.90  - 01.23.03 - Matt  - Revamped the main foreach loop to simplify code
#                             maintenance.
#                           - Fixed multi-line zone parsing in setup_http_vars
#                           - Moved big chunks of main foreach loop into subs
#  0.85  - 01.16.03 - Matt  - Moving form from HTML into CGI.pm
#                             makes HTML dynamic (less future maintenance)
#                             removes a static HTML page dependency
#                             gets rid of ugly HTML variable parsing
#                           - Improved error reporting for command line usage
#  0.84  - 01.08.03 - Matt  - Added a few new subroutines for dnsd.pl use
#  0.81  - 05.09.02 - Matt  - Updated $nt->save_ calls to edit_ and add_ (NicTool 2.0)
#          05.07.02 - Matt  - Made calls using nt_group_id use $me->(nt_user_id)
#          04.26.02 - Matt  - Fixed Perl Module calls
#  0.78    04.16.02 - Matt  - Forced all zones input as lower case
#  0.75  - 03.14.02 - M&J   - Fixed several problems with HTML batch requests
#          03.11.02 - Matt  - Added CGI support
#          03.08.02 - Matt  - Added a 3600 TTL to created zone records.
#          03.07.02 - Matt  - If we're not handed a mailip, set the mailip to
#                             the newip added Nameserver updates.
#          03.05.02 - Matt  - Finished up the update_zone stuff, added
#                             templates, reverse zones stuff
#          03.05.02 - Jason - Added reverse zones functions.
#          03.02.02 - Matt  - Added parsing of ~/.zone file and fixed a few errors
#          02.28.02 - Jason - Added delete function
#          02.27.02 - Matt  - Added templates for creating new zones and more debugging
#          02.25.02 - Matt  - Merged addzones.pl, modzones.pl, added get_ns

#######################################################################
#           Don't muck with anything below this line                  #
#######################################################################

use strict;
use NicTool;
use Getopt::Long;
use Data::Dumper;
use CGI qw(:standard);
use CGI::Carp qw( fatalsToBrowser );

use NicTool::Zones::Templates;
use NicTool::Zones::Nameservers;
use NicTool::Zones::CreateZone;
use NicTool::Zones::UpdateZoneRecords;
use NicTool::Zones::HTML;

use vars qw/ $action $nsfarm $template /;
use vars qw/ $delete $do_reverse $debug @zones $file /;
use vars qw/ $nt $me %conf /;

$conf{'author'} = "Matt Simerson";

$| = 1;

$ENV{'GATEWAY_INTERFACE'} ? process_cgi_input() : process_shell_input();

if ( !$conf{'mailip'} && $conf{'newip'} ) { $conf{'mailip'} = $conf{'newip'} }

##
# Connect to the NicToolServer via the NicToolClient API
#
#$me = &nictool_connect();

chomp @zones;
foreach my $z (@zones) {
    print "working on zone: $z.\n" if ($debug);
    $z = lc($z);
    if ( $z ne "" ) {
        my $zonehash = &find_one_zone_id($z);
        my $zoneid   = $zonehash->{'nt_zone_id'};

        if ( $action eq "add" ) { handle_add_action( $z, $zonehash ); }
        elsif ( $action eq "mod" ) { handle_mod_action( $z, $zonehash ); }
        elsif ( $action eq "del" ) { handle_del_action( $z, $zonehash ); }
        elsif ( $action eq "check" ) { handle_check_action( $z, $zonehash ); }
        else {
            print "main:\t" if $debug;
            print "WARNING: what was I supposed to do?\n";
        }
    }
    else {
        print "main:\t" if $debug;
        print "WARNING: zone name is empty! Skipping.\n";
    }
}
print "Exiting successfully.\n";

if ( $do_reverse eq "1" ) { &add_reverse( $zones[0] ); }

if ( $conf{'user'} eq 'ofs' ) { print "+ 100 DNS finished correctly\n"; }

exit_with_warn("Exiting normally\n");

##
#  Subroutines
##
# ---------------------------------------------------------------------------

sub handle_check_action {
    my ( $zone, $zhash ) = @_;
    my $group = "Inactive";

    my $ina = &get_nt_group_id($group);
    unless ($ina) {
        my $parent = "69";    # nt_group_id for 'interland.net' group
        $ina = &get_nt_group_id( $group, $parent );
    }

    if ($ina) {
        print "$group GID: $ina->{'nt_group_id'} ( $ina->{'name'} )\n";

        #@zones = &find_zone_ids($something_needs_to_go_here);
    }
    else {
        print "Darn! Couldn't find the group $group. Bye bye!\n";
    }
}

sub handle_mod_action {
    my ( $zone, $zhash ) = @_;

    print "handle_mod_action: " if $debug;

    if ( $zhash && $zhash->{'nt_zone_id'} ) {
        print "modifying $zone...\n";
        &update_zone( $zone, $zhash );
    }
    else {
        print "WARNING: zone $zone does not exist! Skipping.\n";
    }
}

sub handle_add_action {
    my ( $zone, $zhash ) = @_;

    if ( $zhash && $zhash->{'nt_zone_id'} ) {
        print "handle_add_action:\t" if $debug;
        print "WARNING: zone $zone already exists, skipping\n";
    }
    else {
        ;
        if ( $nsfarm && $template ) {
            my $r = &create_the_zone( $zone, $nsfarm, $debug, $nt );
            if ( $r->{'nt_zone_id'} ) {
                print "success\n.";
                &add_zone_records( $r->{'nt_zone_id'}, $zone, $template );
            }
            else {
                print "handle_add_action:\t" if $debug;
                print "failed to create: $zone with $template template.\n";
            }
        }
        else {
            print "handle_add_action:\t" if $debug;
            print "FAILED: no dnsfarm: $nsfarm or template: $template.\n";
        }
    }
}

sub handle_del_action {
    my ( $zone, $zhash ) = @_;
    my $zoneid;

    if ($zhash) { $zoneid = $zhash->{'nt_zone_id'} }

    unless ($zoneid) {
        print "handle_del_action:\t" if $debug;
        print "WARNING: zone doesn't exist: $zone\n";
    }
    else {
        my $record = &get_zone_records( $zoneid, "10000" );
        &delete_zone_records( $record, $zoneid, $zone );
        &delete_zone( $zoneid, $zone );
    }
}

sub update_zone {
    my ( $zone, $zhash ) = @_;
    my $zoneid;

    print "update_zone: $zone.\n" if ($debug);

    if ($zhash) { $zoneid = $zhash->{'nt_zone_id'} }

    if ($zoneid) {
        if ($nsfarm) {
            my $ns_old
                = find_zone_nameservers( $zoneid, $zhash->{'nt_group_id'} );
            my @ns = get_ns( $nsfarm, $debug );

            unless ( $ns[0] ) {
                exit_with_warn("nameserver $nsfarm doesn't exist\n");
            }

            if ( $ns[0] ne $ns_old->[0]->{'nt_group_id'} ) {
                &update_zone_group( $zoneid, $ns[0] );
            }

            if (    $ns[1] == $ns_old->[0]->{'nt_nameserver_id'}
                and $ns[2] == $ns_old->[1]->{'nt_nameserver_id'}
                and $ns[3] == $ns_old->[2]->{'nt_nameserver_id'} )
            {
                print "update_zone: nameservers up to date, skipping.\n"
                    if ($debug);
            }
            else {
                print "update_zone: gotta update the nameservers!\n"
                    if ($debug);
                &update_the_nameservers( $zoneid, $ns[0], $zhash->{'zone'},
                    "$ns[1],$ns[2],$ns[3]" );
            }
        }

        my $record = &get_zone_records( $zoneid, "100" );
        update_zone_records(
            $nt,             $record,        $zoneid,
            $zone,           $template,      $conf{'newip'},
            $conf{'mailip'}, $conf{'oldip'}, $debug
        );
    }
    else {
        print "update_zone:\t" if $debug;
        print "WARNING: zone doesn't exist: $zone\n";
    }
}

sub find_one_zone_id {
    my ($zone) = @_;
    print "find_one_zone_id:\t" if $debug;
    print "searching for $zone...";

    #                search for an exact match on the zone
    my $r = $nt->get_group_zones(
        nt_group_id       => $me->{nt_group_id},
        include_subgroups => 1,
        Search            => 1,
        '1_field'         => "zone",
        '1_option'        => "equals",
        '1_value'         => $zone
    );

    if ( $r->{'zones'}->[0]->{'nt_zone_id'} ) {
        print "found: $r->{'zones'}->[0]->{'nt_zone_id'}\n";
        return $r->{'zones'}->[0];
    }
    else {
        print "FAILED.\n";
        return 0;
    }
}

sub find_zone_nameservers {
    my ( $zid, $gid ) = @_;
    print "find_zone_nameservers: zoneid: $zid, groupid: $gid\n" if $debug;
    my %get_zone = ( nt_zone_id => $zid, nt_group_id => $gid );
    my $r = $nt->get_zone(%get_zone);
    if ($debug) {
        print
            "find_zone_nameservers: $r->{'nameservers'}->[0]->{'nt_nameserver_id'}, ";
        print "$r->{'nameservers'}->[1]->{'nt_nameserver_id'}, ";
        print "$r->{'nameservers'}->[2]->{'nt_nameserver_id'}\n";
    }
    return $r->{'nameservers'};
}

sub get_zone_records_by {
    my ( $zoneid, $field, $value ) = @_;
    my %query = ( nt_zone_id => "$zoneid" );

    if ($field) {
        $query{'Search'}   = 1;
        $query{"1_field"}  = $field;
        $query{"1_option"} = "equals";
        $query{"1_value"}  = $value;
    }

    my $r = $nt->get_zone_records(%query);
    print "get_zone_records_by: $zoneid\n";
    if ( $r->{'records'}->[0] && $debug ) {
        for ( my $i = 0; $i < scalar( @{ $r->{'records'} } ); $i++ ) {
            printf "%35s  %5s  %35s\n", $r->{'records'}->[$i]->{'name'},
                $r->{'records'}->[$i]->{'type'},
                $r->{'records'}->[$i]->{'address'};
        }
    }
    return $r->{'records'};
}

sub get_zone_records {
    my ( $zoneid, $limit ) = @_;

    my %query = (
        nt_zone_id => "$zoneid",
        limit      => $limit
    );

    my $r = $nt->get_zone_records(%query);

    if ($debug) {
        print "get_zone_records: r=$r, r->records=$r->{'records'} \n"
            if $debug;

        for ( my $i = 0; $i < scalar( @{ $r->{'records'} } ); $i++ ) {
            printf "%35s  %5s  %35s\n", $r->{'records'}->[$i]->{'name'},
                $r->{'records'}->[$i]->{'type'},
                $r->{'records'}->[$i]->{'address'};
            print
                "\t$r->{'records'}->[$i]->{'name'}, $r->{'records'}->[$i]->{'type'},
				$r->{'records'}->[$i]->{'address'} \n" if $debug;
        }
        print "get_zone_records: returning $r->{'records'}\n" if $debug;
    }
    return $r->{'records'};
}

sub add_reverse {
    my ($zone) = @_;

    # If IP is 10.1.2.3, look for 2.1.10.in-addr.arpa
    $conf{'newip'} =~ /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/;
    my $reverse    = "$3.$2.$1.in-addr.arpa";
    my $last_octet = $4;

    my $zonehash = &find_one_zone_id($reverse);
    my $zoneid   = $zonehash->{'nt_zone_id'};
    if ( !$zoneid ) {

        # No .arpa entry exists, add it
        my $r = &create_the_zone( $reverse, "reverse", $debug, $nt );
        if ( $r->{'nt_zone_id'} ) {
            &add_zone_records( $r->{'nt_zone_id'}, $zone, "reverse",
                $last_octet );
        }
    }
    else {

        # An .arpa zone exists, update for the zone record
        my $record = &get_zone_records( $zoneid, "100" );
        &update_zone_records(
            $nt,             $record,        $zoneid,
            $zone,           "reverse",      $conf{'newip'},
            $conf{'mailip'}, $conf{'oldip'}, $debug,
            $last_octet
        );
    }
}

sub add_zone_records {
    my ( $zoneid, $zone, $template, $reverse ) = @_;
    my %zone_record;

    print "add_zone_records: $zoneid, $zone, $template\n" if ($debug);

    # If you gave me a template, I'll use it, otherwise I'll use template #1
    $template = ( $template ne "" ) ? $template : "1";

    # we'll get back an array of hashes for the records to create:
    # nt_zone_id, name, type, address, weight
    my $recs = &zone_record_template( $zoneid, $zone, $template, $reverse,
        $conf{'newip'}, $conf{'mailip'}, $debug );

    if ( scalar( @{$recs} ) > 0 ) {
        for ( my $i = 0; $i < scalar( @{$recs} ); $i++ ) {
            %zone_record = (
                nt_zone_id  => $recs->[$i]->{'nt_zone_id'},
                name        => $recs->[$i]->{'name'},
                ttl         => "3600",
                description => "added by zones.pl",
                type        => $recs->[$i]->{'type'},
                address     => $recs->[$i]->{'address'},
                weight      => $recs->[$i]->{'weight'}
            );
            if ($debug) {
                print
                    "add_zone_records: $recs->[$i]->{'nt_zone_id'}, $recs->[$i]->{'name'}, ";
                print
                    "$recs->[$i]->{'type'}, $recs->[$i]->{'address'}, $recs->[$i]->{'weight'}\n";
            }
            my $r = $nt->new_zone_record(%zone_record);
            if ( $r->{'error_code'} ne "200" ) {
                print
                    "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
            }
        }
    }
    else {
        croak
            "Oh no, we didn't get any records back from the zone template!\n";
    }
}

sub update_zone_group {
    my ( $zoneid, $group_id ) = @_;

    print "update_zone_group: updating group...";

    my %mz = (
        zone_list   => $zoneid,
        nt_group_id => $group_id
    );

    my $r = $nt->move_zones(%mz);
    if ( $r->{'error_code'} ne "200" ) {
        print "FAILED\n";
        print "$r->{'error_code'}: $r->{'error_msg'}\n";
    }
    else {
        print "success\n";
    }
}

sub update_the_nameservers {
    my ( $zid, $gid, $zone, $ns ) = @_;

    print "update_the_nameservers: $zid, $gid, $zone, $ns...";
    my %sz = (
        nt_zone_id  => $zid,
        nt_group_id => $gid,

        #		zone         => $zone,
        ttl         => "86400",
        nameservers => $ns,
        mailaddr    => "hostmaster\.$zone\."
    );

    my $r = $nt->edit_zone(%sz);

    if ( $r->{'error_code'} eq "200" ) {
        print "succeeded\n";
    }
    else {
        print "\nWARNING: update_the_nameservers: FAILED.\n";
        print "   $r->{'error_code'}, $r->{'error_msg'}";
    }
}

sub edit_zone_record {
    my ( $zrid, $zid, $name, $add, $type, $mx_w ) = @_;
    print "edit_zone_record values: $zrid, $zid, $name, $add, $type, $mx_w \n"
        if $debug;

    my %query = (
        nt_zone_record_id => $zrid,
        nt_zone_id        => $zid,
        name              => $name,
        address           => $add,
        type              => $type,
        weight            => $mx_w
    );

    print "values is: $_[0], $_[1], $_[2], $_[3], $_[4], $_[5] \n"
        if ($debug);
    my $r = $nt->edit_zone_record(%query);
    if ( $r->{'error_code'} ne "200" ) {
        print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
    }
}

sub delete_zone_records {
    my ( $record, $zoneid, $zone ) = @_;

    print "delete_zone_records: $zoneid, $zone\n" if ($debug);

    #if ($debug) { print "\n" . scalar(@{$record}) . "\n"; };

    for ( my $i = 0; $i < scalar( @{$record} ); $i++ ) {
        if ($debug) {
            printf "\t%8s  %25s  %30s...",
                $record->[$i]->{'nt_zone_record_id'},
                $record->[$i]->{'name'}, $record->[$i]->{'address'};
        }

        my %foo
            = ( nt_zone_record_id => $record->[$i]->{'nt_zone_record_id'} );

        my $r = $nt->delete_zone_record(%foo);

        if ( $r->{'error_code'} ne "200" ) {
            print
                "FAILED.\n\t(Error $r->{'error_code'}: $r->{'error_msg'})\n";
        }
        else {
            print "SUCCESS.\n" if ($debug);
        }
    }
}

sub delete_zone {
    my ($zid) = @_;

    print "delete_zone: id: $zid...";

    my %del = ( zone_list => $zid );
    if ($debug) {
        foreach my $key ( keys %del ) { print "$key $del{$key}..."; }
    }

    my $r = $nt->delete_zones(%del);

    if ( $r->{'error_code'} eq "200" ) {
        print "SUCCESS.\n";
    }
    else {
        print "Error $r->{'error_code'}: $r->{'error_msg'}\n";
    }
}

sub find_zone_ids {
    my ($zone) = @_;

    print "find_zone_ids: searching for: %$zone%...";

    my $r = $nt->get_group_zones(
        nt_group_id       => $me->{nt_group_id},
        include_subgroups => 1,
        quick_search      => 1,
        search_value      => $zone
    );

    # this iterates on the returned list
    for ( my $i = 0; $i < scalar( @{ $r->{'zones'} } ); $i++ ) {
        if ($debug) {
            print "hash values:";
            print values %{ $r->{'zones'}->[$i] };
            print "\n";
            print "hash keys:";
            print keys %{ $r->{'zones'}->[$i] };
            print "\n";
        }
        print "zoneid: $r->{'zones'}->[$i]->{'nt_zone_id'} \n";
    }
    print "find_zone_ids: returning $r->{'zones'}" if ($debug);
    return $r->{'zones'};
}

sub nictool_connect {

    #	print "user: ." . $conf{'user'} . ". pass: ." . $conf{'pass'} . ".<br>";

    $nt = NicTool->new( server_host => "localhost", server_port => "8010" );
    my $r
        = $nt->login( username => $conf{'user'}, password => $conf{'pass'} );

    #print Dumper($r) if ( $debug);

    carp "error logging in: " . $nt->is_error($r) . "\n"
        if ( $nt->is_error($r) && $debug );
    if ($debug) {
        print "r:  $r<br>";

        #		print "userid: " . $r->{'nt_user_id'} . "<br>";
    }

    #	unless ( defined $r->{'nt_user_session'} ) {
    #		carp "Error: no session string returned.\n" if $debug;
    #		return 0;
    #	};
    $nt->set( nt_user_session => $r->{'nt_user_session'} );
    return $r;
}

sub parse_dot_file {
    my ($file) = @_;

    print "parse_dot_file: $file" if ($debug);

    open( DOT, $file );
    while (<DOT>) {
        chomp $_;
        if ( $_ !~ /^#/ ) {
            my @r = split(" ");
            if ( $r[0] eq "user" )   { $conf{'user'}   = $r[1]; }
            if ( $r[0] eq "pass" )   { $conf{'pass'}   = $r[1]; }
            if ( $r[0] eq "oldip" )  { $conf{'oldip'}  = $r[1]; }
            if ( $r[0] eq "newip" )  { $conf{'newip'}  = $r[1]; }
            if ( $r[0] eq "mailip" ) { $conf{'mailip'} = $r[1]; }
        }
    }
    if ($debug) {
        if ( $conf{'user'} )   { print ", $conf{'user'}"; }
        if ( $conf{'pass'} )   { print ", ******"; }
        if ( $conf{'oldip'} )  { print ", $conf{'oldip'}"; }
        if ( $conf{'newip'} )  { print ", $conf{'newip'}"; }
        if ( $conf{'mailip'} ) { print ", $conf{'mailip'}"; }
        print "\n";
    }
    close(DOT);
}

sub exit_with_warn {
    my ($message) = @_;

    if ($nt) {
        $nt->logout();
        undef $nt;
    }

    if ($message) {
        carp "\n$message\n\n";
    }
    exit;
}

sub setup_http_vars {

    print "setup_http_vars: " if $debug;

    $action         = param('action');
    $conf{'newip'}  = param('newip');
    $nsfarm         = param('nsfarm');
    $conf{'mailip'} = param('mailip');
    $template       = param('template');
    $conf{'user'}   = param('user');
    $conf{'pass'}   = param('pass');
    $do_reverse     = param('reverse');
    $debug          = param('debug');

    my $zones = param('zone_list');
    chomp $zones;

    @zones = split( "\n", $zones );
    foreach my $zone (@zones) {
        $zone = lc($zone);
        ($zone) = $zone =~ /([a-z0-9\.\-]*)/;
    }

    print "setup_http_vars: zone list: " . join( "\t", @zones ) . "\n"
        if $debug;
}

sub verify_global_vars {
    if ( param('newip') eq "" && param('template') ne "blank" ) {
        my $message = "The field New IP must not be blank!";
        print_zone_request_form( $NicTool::Zones::VERSION, "matt\@tnpi.biz",
            $conf{'author'}, $message );
    }
}

sub show_http_vars {
    print "HTTP ENV vars are:\n" if $debug;
    foreach my $key ( param() ) {
        my $foo = param($key);
        print "key: $key $foo\n";
    }
}

sub show_key_value_pairs {

    # Just prints out the values of a hash passed to it
    my (%array) = @_;
    foreach my $key ( keys %array ) {
        print "key: $key $array{$key}\n";
    }
}

sub get_nt_group_id {
    my ( $group, $parent ) = @_;

    # fetches the group id of a zone based on it's NicTool group name
    # http://admin.ns.interland.net/NicToolDocs/api.htm#GETGROUPSUBGROUPSFUNC

    unless ($parent) {
        print "setting \$parent from $parent to $me->{nt_group_id}.\n"
            if $debug;
        $parent = $me->{nt_group_id};
    }

    my $r = $nt->get_group_subgroups(
        nt_group_id       => $parent,
        include_subgroups => 1,
        quick_search      => 1,
        search_value      => $group
    );

    #		Search              => 1,
    #		'1_field'           => "group",
    #		'1_option'          => "equals",
    #		'1_value'           => $group );
    return $r->{'groups'}->[0];
}

sub process_cgi_input {
    print header('text/html');
    $debug = 1;

    if ( param('user') && param('pass') ) {
        $conf{'user'} = param('user');
        $conf{'pass'} = param('pass');

        if ( nictool_connect( \%conf ) ) {    # if NT login is successful
            if ( param('action') ) {

                # Process form inputs
                print "process_cgi_input: processing form inputs<br>"
                    if $debug;
                &setup_http_vars;
                &verify_global_vars;

                #&show_http_vars if $debug;
                return 1;
            }
            else {
                print_zone_request_form( $NicTool::Zones::VERSION,
                    "matt\@tnpi.biz", $conf{'author'}, undef );
            }
        }
        else {
            print_login_form( $NicTool::Zones::VERSION,
                "Invalid Login, Try Again!" );
        }
        exit_with_warn();
    }
    else {
        print_login_form( $NicTool::Zones::VERSION,
            "Enter your NicTool username and password" );
        exit_with_warn();
    }
}

sub print_usage {
    print
        "\n\t\t\tZones.pl  by $conf{'author'}               $NicTool::Zones::VERSION\n\n";
    print <<EOF
   usage: $0 -a <action> -u <user> -p <pass> [-z <zone> -f <file>]
      
      add:  -a add -ns interland.net -t 2
      del:  -a del
      mod:  -a mod
      check -a check
   
      --template --oldip --newip --mailip --debug
EOF
        ;
}

sub process_shell_input {

    # get options from the command line
    my %options = (
        'user=s'     => \$conf{'user'},
        'pass=s'     => \$conf{'pass'},
        'action=s'   => \$action,
        'ns=s'       => \$nsfarm,
        'zone=s'     => \@zones,
        'file=s'     => \$file,
        'template=s' => \$template,
        'delete=s'   => \$delete,
        'newip|ip=s' => \$conf{'newip'},
        'oldip=s'    => \$conf{'oldip'},
        'mailip=s'   => \$conf{'mailip'},
        'reverse=s'  => \$do_reverse,
        'debug|v=s'  => \$debug,
    );
    &GetOptions(%options);

    my ($homedir) = ( getpwuid($<) )[7];    # get the user's home dir
    if ( !$conf{'user'} && -r "$homedir/\.zones" ) {
        &parse_dot_file("$homedir/\.zones");
    }

    unless ( $conf{'user'} && $conf{'pass'} ) {
        print_usage;
        croak "Failed to get a username and password!\n";
    }
    if ( !$action || scalar(@zones) == 0 ) {
        print_usage;
        croak "No action or zone(s)!\n";
    }

    if ( $action eq "add" && !$conf{'newip'} ) {
        croak "\n You must provide an IP address (-newip xx.xx.xx.xx) \n\n";
    }
    elsif ( $action eq "add" && !$template ) {
        croak
            "\n You must select a template (-template <nameserver.com>)\n\n";
    }
    elsif ( $action eq "add" && !$nsfarm ) {
        croak "\n You must select a dns farm (-ns <xxxx.com>)\n\n";
    }

    ##
    # If we were handed a file on the command line, we expect it's a list
    # of zones that we're supposed to process
    #
    if ($file) {
        if ( -r $file ) {
            open( INPUT, $file ) or croak "Unable to open $file: $!\n";
            while (<INPUT>) {
                chomp $_;
                my @r = split( / /, $_ );
                push( @zones, lc( $r[0] ) );
            }
            close(INPUT);
        }
    }
    print "root: @zones\n" if ($debug);
}

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
