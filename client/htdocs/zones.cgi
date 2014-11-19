#!/usr/bin/perl

use strict;
use Data::Dumper;

require 'nictoolclient.conf';

main();

sub main {
    my $q = new CGI();
    my $nt_obj = new NicToolClient($q);

    return if $nt_obj->check_setup ne 'OK';

    my $user = $nt_obj->verify_session();

    if ($user && ref $user) {
        print $q->header (-charset=>"utf-8");
        display( $nt_obj, $q, $user );
    }
}

sub display {

    my ( $nt_obj, $q, $user ) = @_;

    $nt_obj->parse_template($NicToolClient::start_html_template);
    $nt_obj->parse_template(
        $NicToolClient::body_frame_start_template,
        username  => $user->{'username'},
        groupname => $user->{'groupname'},
        userid    => $user->{'nt_user_id'}
    );

    my $gid = $q->param('nt_group_id');
    my $level = $nt_obj->display_group_tree( $user, $user->{'nt_group_id'}, $gid, 0);

    $nt_obj->display_zone_list_options( $user, $gid, $level, 1 );

    my $group = $nt_obj->get_group( nt_group_id => $gid );

    my %vars = setup_http_vars( $q, 1 );
    $vars{'ns_tree'} = $nt_obj->get_usable_nameservers( nt_group_id => $gid );

    print_zone_request_form( $nt_obj, $q, %vars );

    if ( $q->param('action') ) {

        # Process form inputs
        print "processing form inputs <br>\n" if $vars{'debug'};
        print "form action:  $vars{'action'} <br>\n"
            if ( $vars{'action'} && $vars{'debug'} );
        %vars = verify_global_vars( $q, %vars );
        if ( $vars{'message'} ) { print "$vars{'message'} <br>\n"; return 0; };

        my $zones = $vars{'zones'};

        if ( $q->param('action') eq "add" ) {
            foreach my $zone (@$zones) {
                zone_add( $zone, $nt_obj, $q, %vars );
            }
        }
        elsif ( $q->param('action') eq "mod" ) {
            foreach my $zone (@$zones) { print "modifying zone: $zone<br>"; }
        }
        elsif ( $q->param('action') eq "del" ) {
            foreach my $zone (@$zones) { print "deleting zone: $zone<br>"; }
        }
    }

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub print_zone_request_form {

    my ( $nt_obj, $q, %vars ) = @_;

    my @templates = $nt_obj->zone_record_template_list();
    my @actions   = ("add");

    my $gid = $q->param('nt_group_id');
    print $q->start_form,
        $q->hidden( -name => 'nt_group_id', -default => $gid );

    print qq{
<table class="fat">
 <tr class="dark_bg">
  <td colspan="4" class="center"><b>Batch Zone Creation</b></td>
 </tr>
 <tr class="light_grey_bg">
  <td class="right"> Action: </td>
  <td> },
        $q->popup_menu(
        -name    => 'action',
        -values  => [@actions],
        -default => $q->param('action')
        ),
        qq{   </td>
  <td class="right">New IP:</td>
  <td> },
        $q->textfield(
        -name  => 'newip',
        -size  => 15,
        -value => $q->param('newip')
        ),
        qq{
  </td>
 </tr>
 <tr class="light_grey_bg">
  <td><a href="javascript:void window.open('templates.cgi','templates_win','width=640,height=580,scrollbars,resizable=yes')"> Template:</a></td>
  <td> },
        $q->popup_menu( -name => 'template', -values => [@templates] ),
        qq{
  </td>
  <td class="right">Mail IP: </td>
  <td> },
        $q->textfield(
        -name  => 'mailip',
        -size  => 15,
        -value => $q->param('mailip')
        ),
  qq{<br>(if different than new) </td>
 </tr>
 <tr class="light_grey_bg">
  <td> Nameservers </td>
  <td colspan="3">}, print_ns_tree( $q, %vars ), qq{ </td>
 </tr>
 <tr class="light_grey_bg">
  <td></td>
  <td colspan="3" class="center"><br>
    Zones must be a zone or list of zones, entered one per line. Zones have only two parts.<br>
  </td>
 </tr>
 <tr class="light_grey_bg">
  <td>Zones:</td>
  <td colspan="2"> <textarea name="zone_list" rows="10" cols="40"> },
        $q->param('zone_list'), qq{ </textarea></td>
  <td>A zone is also known as a domain name.<br>The same rules apply.<br>
	<br>This is a zone: example.com<br><br>This is NOT: www.example.com
  </td>
 </tr>
 <tr class="light_grey_bg">
  <td>Options:</td>
  <td colspan="3"> }, $q->checkbox( -name => 'debug', -label => ' Debug' ), ' <br> ',
        qq{
  </td>
 </tr> },
        $q->td( { -colspan => '4', -class => 'center' }, $q->submit, ),
        qq{
 </tr>
</table> },
        $q->end_form;
}

sub find_one_zone_id {
    my ( $zone, $nt, %vars ) = @_;

    my $debug = 0;
    print "searching for $zone..." if $debug;

    my $r = $nt->get_group_zones(    # search for an exact match
        nt_group_id       => $nt->{nt_group_id},
        include_subgroups => 1,
        Search            => 1,
        '1_field'         => "zone",
        '1_option'        => "equals",
        '1_value'         => $zone
    );

    if ( $r->{'zones'}->[0]->{'nt_zone_id'} ) {
        print "found: $r->{'zones'}->[0]->{'nt_zone_id'}\n" if $debug;
        return $r->{'zones'}->[0];
    }
    else {
        print "FAILED.\n" if $debug;
        return 0;
    }
}


sub zone_add {
    my ( $zone, $nt, $q, %vars ) = @_;

    print "zone_add: $zone ...";

    # see if zone exists
    my $id = find_one_zone_id( $zone, $nt, %vars );

    if ($id) { print "exists, skipping.<br>"; return 0; }

    my %zone_vars = (
        mailaddr    => "hostmaster.$zone.",
        description => "batch created",
        zone        => $zone,
        nameservers => join( ',', $q->param('nameservers') ),
    );
    foreach my $s ( qw/ refresh retry expire minimum ttl serial nt_group_id / ) {
        $zone_vars{$s} = $vars{$s};
    };

    print Data::Dumper::Dumper(%zone_vars) if $vars{'debug'};

    # create zone
    my $r = $nt->new_zone(%zone_vars);
    if ( $r->{'error_code'} != 200 ) {
        print
            "$r->{'error_code'}: $r->{'error_msg'} : $r->{'error_desc'} <br>";
        print Data::Dumper::Dumper($r);
        return 0;
    }

    # add zone records based on template
    add_zone_records(
        $nt, $q,
        $nt->zone_record_template(
            {   zone       => $zone,
                nt_zone_id => $r->{'nt_zone_id'},
                template   => $q->param('template'),
                newip      => $q->param('newip'),
                mailip     => $q->param('mailip'),
                debug      => $q->param('debug')
            }
        )
    );

    print "success.<br>"; # return success
}

sub add_zone_records {
    my ( $nt, $q, $recs ) = @_;

    return if scalar( @{$recs} ) <= 0;

    for ( my $i = 0; $i < scalar( @{$recs} ); $i++ ) {
        my %zone_record = (
            nt_zone_id  => $recs->[$i]->{'nt_zone_id'},
            name        => $recs->[$i]->{'name'},
            ttl         => '3600',
            description => 'batch added',
            type        => $recs->[$i]->{'type'},
            address     => $recs->[$i]->{'address'},
            weight      => $recs->[$i]->{'weight'}
        );
        if ( $q->param('debug') ) {
            print "add_zone_records: $recs->[$i]->{'nt_zone_id'}, $recs->[$i]->{'name'}, ";
            print "$recs->[$i]->{'type'}, $recs->[$i]->{'address'}, $recs->[$i]->{'weight'}\n";
            #print Data::Dumper::Dumper(%zone_record);
        }
        my $r = $nt->new_zone_record(%zone_record);
        if ( $r->{'error_code'} ne "200" ) {
            print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
            print Data::Dumper::Dumper($r);
        }
    }
}

sub verify_global_vars {
    my ( $q, %vars ) = @_;

    if ( $q->param('newip') eq '' && $q->param('template') ne "blank" ) {
        $vars{'message'} = "The field New IP must not be blank!";
    }
    return %vars;
}

sub setup_http_vars {
    my ( $q, $debug ) = @_;

    my %data;
    my @fields
        = qw(nt_group_id action newip nameservers mailip template do_reverse debug);
    foreach (@fields) { $data{$_} = $q->param($_) }
    $data{'nameservers'} = join( ',', $q->param('nameservers') );

    $data{'ttl'}     = $NicToolClient::default_zone_ttl     || 86400;
    $data{'refresh'} = $NicToolClient::default_zone_refresh || 16384;
    $data{'retry'}   = $NicToolClient::default_zone_retry   || 2048;
    $data{'expire'}  = $NicToolClient::default_zone_expire  || 1048576;
    $data{'minimum'} = $NicToolClient::default_zone_minimum || 2560;
    $data{'mailaddr'} = $NicToolClient::default_zone_mailaddr
        || 'hostmaster.ZONE.TLD';

    my $zones = $q->param('zone_list');
    chomp $zones;
    my @zones = split( "\n", $zones );

    # lower case the names, strip off any trailing invalid characters
    foreach (@zones) { ($_) = lc($_) =~ /([a-z0-9\.\-]*)/; }
    $data{'zones'} = \@zones;

    return %data;
}

sub print_ns_tree {
    my ( $q, %vars ) = @_;

    unless ( defined $vars{'ns_tree'} ) {
        return "No available nameservers.";
    }

    if ( @{ $vars{'ns_tree'}->{'nameservers'} } == 0 ) {
        return "No available nameservers.";
    }

    my $string;
    foreach ( 1 .. scalar( @{ $vars{'ns_tree'}->{'nameservers'} } ) ) {
        last if ( $_ > 10 );

        my $ns = $vars{'ns_tree'}->{'nameservers'}->[ $_ - 1 ];

        $string .= $q->checkbox(
            -name    => "nameservers",
            -checked => ( $_ < 4 ? 1 : 0 ),
            -value   => $ns->{'nt_nameserver_id'},
            -label   => "$ns->{'description'} ($ns->{'name'})"
        ) . "<BR>";
    }
    return $string;
}


