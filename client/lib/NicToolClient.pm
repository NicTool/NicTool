package NicToolClient;
# ABSTRACT: CGI Interface to NicToolServer

use strict;
use vars qw/ $AUTOLOAD /;
use NicToolServerAPI();

$NicToolClient::VERSION = '2.11';
$NicToolClient::NTURL   = 'http://www.nictool.com/';
$NicToolClient::LICENSE = 'http://www.affero.org/oagpl.html';
$NicToolClient::SRCURL  = 'http://www.nictool.com/download/NicTool.tar.gz';

sub new {
    my $class = shift;
    my $q     = shift;

    my $nt_server_obj = new NicToolServerAPI();

    bless { 'nt_server_obj' => $nt_server_obj, 'CGI' => $q }, $class;
}

sub no_gui_hints {0}

sub help_link {
    my ($self,$helptopic, $text) = @_;

    return '' if !$NicToolClient::show_help_links;
    return qq{ &nbsp; [<a href="javascript:void window.open('help.cgi?topic=$helptopic', 'help_win', 'width=640,height=480,scrollbars,resizable=yes')">}
        . ( $text ? $text : '' )
        . qq{<img src="$NicToolClient::image_dir/help-small.gif" alt="Help"></a>]};
}

sub rr_types {
    my $self = shift;
    my $r = $self->get_record_type(type=>'ALL');
    return $r->{types};
}

sub ns_export_formats {
    {   'bind'    => 'BIND (ISC\'s Berkeley Internet Named Daemon)',
        'tinydns' => 'tinydns (part of DJBDNS)',
    };
}

sub obj_to_cgi_map {
    {   'nameserver' =>
            { 'image' => 'zone.gif', 'url' => 'group_nameservers.cgi' },
        'zone'        => { 'image' => 'zone.gif',     'url' => 'zone.cgi' },
        'user'        => { 'image' => 'user.gif',     'url' => 'user.cgi' },
        'group'       => { 'image' => 'group.gif',    'url' => 'group.cgi' },
        'zone_record' => { 'image' => 'r_record.gif', 'url' => 'zone.cgi' },
    };
}

sub check_setup {
    my $self = shift;

    my $server_obj = $self->{'nt_server_obj'};
    my $q          = $self->{'CGI'};

    my $message = $server_obj->check_setup();

    if ( $message ne 'OK' ) {
        print $q->header;
        $self->parse_template( $NicToolClient::setup_error_template,
            message => $message );
    }

    return $message;
}

sub login_user {
    my $self = shift;

    my $server_obj = $self->{'nt_server_obj'};
    my $q          = $self->{'CGI'};

    return $server_obj->send_request(
        action   => "login",
        username => $q->param('username'),
        password => $q->param('password')
    );
}

sub logout_user {
    my $self = shift;

    my $server_obj = $self->{'nt_server_obj'};
    my $q          = $self->{'CGI'};

    return $server_obj->send_request(
        action          => "logout",
        nt_user_session => $q->cookie('NicTool')
    );
}

sub display_login {
    my ( $self, $error ) = @_;

    my $q = $self->{'CGI'};

    my $cookie = $q->cookie(
        -name    => 'NicTool',
        -value   => '',
        -expires => '-1d',
        -path    => '/'
    );
    print $q->header( -cookie => $cookie );
    if ( !ref $error ) {
        $error = { 'error_code' => 'XXX', 'error_msg' => $error };
    }
    if ( $error->{'error_code'} ne 200 ) {
        $self->parse_template(
            $NicToolClient::login_template,
            'message' => $error->{'error_msg'}
        );
    }
    else {
        $self->parse_template($NicToolClient::login_template);
    }

}

sub verify_session {
    my $self = shift;

    my $server_obj = $self->{'nt_server_obj'};
    my $q          = $self->{'CGI'};

    my $response = $server_obj->send_request(
        action          => "verify_session",
        nt_user_session => $q->cookie('NicTool')
    );
    my $error_msg;

    #warn "verify_session response: ".Data::Dumper::Dumper($response);
    if ( ref($response) ) {
        if ( $response->{'error_code'} ) {
            $error_msg = $response->{'error_msg'};
        }
        else {
            return $response;
        }
    }
    else {
        $error_msg = $response;
    }

    my $cookie = $q->cookie(
        -name    => 'NicTool',
        -value   => '',
        -expires => '-1d',
        -path    => '/'
    );
    print $q->header( -cookie => $cookie );
    print "<html>\n";
    print "<script language='JavaScript'>\n";
    print "parent.location = 'index.cgi?message="
        . $q->escape($error_msg) . "';\n";
    print "</script>\n";
    print "</html>";

    $self->parse_template( $NicToolClient::login_template,
        'message' => $error_msg );

}

sub parse_template {
    my $self     = shift;
    my $template = shift;

    my %temp = @_;
    my $vars = \%temp;

    # only for stuff defined in the $NicToolClient:: namespace
    $self->fill_template_vars($vars)
        ;    # TODO - cache # unless ($self->{'fill_vars'});

    open( FILE, "<$template" ) || die "unable to find template: $template\n";

    while (<FILE>) {
        s/{{(.+?)}}/$vars->{$1}/g;
        s/{{ONLOAD_JS}}/$temp{'ONLOAD_JS'}/g;
        print;
    }

    close(FILE);
}

sub fill_template_vars {
    my $self = shift;
    my $vars = shift;

    my @fields = qw( app_title app_dir image_dir generic_error_message VERSION SRCURL LICENSE NTURL );

    foreach my $f (@fields) {
        my $temp;
        eval "\$temp = \$NicToolClient::$f";
        $vars->{$f} = $temp;
    }
}

sub display_group_tree {
    my ( $self, $user, $user_group, $curr_group, $in_summary ) = @_;

    $curr_group ||= $user_group;

    my $rv = $self->{'nt_server_obj'}->send_request(
        action          => "get_group_branch",
        nt_group_id     => $curr_group,
        nt_user_session => $self->{'CGI'}->cookie('NicTool')
    );

    if ( $rv->{'error_code'} != 200 ) {
        $curr_group = $user_group;
        $rv         = $self->{'nt_server_obj'}->send_request(
            action          => "get_group_branch",
            nt_group_id     => $curr_group,
            nt_user_session => $self->{'CGI'}->cookie('NicTool')
        );
    }

    my $count = scalar( @{ $rv->{'groups'} } ) - 1;
    my @list;

    foreach ( 0 .. $count ) {
        my $group = $rv->{'groups'}->[$_];
        push( @list, $group->{'name'} );

        my @options;
        if ( $group->{'nt_group_id'} != $user_group ) {
            my $name = 'View Details';
            if ($user->{'group_write'}
                && ( !exists $group->{'delegate_write'}
                    || $group->{'delegate_write'} )
                )
            {
                $name = 'Edit';
            };
            push( @options,
                "<td><a href=group.cgi?nt_group_id=$group->{'nt_group_id'}&edit=1>$name</a></td>"
            );
            if ($user->{"group_delete"}
                && ( !exists $group->{'delegate_delete'}
                    || $group->{'delegate_delete'} )
                )
            {
                push( @options,
                    "<td><a href=group.cgi?nt_group_id=$group->{'parent_group_id'}&delete=$group->{'nt_group_id'} onClick=\"return confirm('Delete "
                        . join( ' / ', @list )
                        . " and all associated data?');\">Delete</a></td>"
                );
            }
            else {
                push @options, "<td class='disabled'>Delete</td>";
            }
        }
        push( @options,
            "<td><img src=$NicToolClient::image_dir/folder_closed.gif></td><td><a href=group_zones.cgi?nt_group_id=$group->{'nt_group_id'}>Zones</a></td>"
        );
        push( @options,
            "<td><img src=$NicToolClient::image_dir/folder_closed.gif></td><td><a href=group_nameservers.cgi?nt_group_id=$group->{'nt_group_id'}>Nameservers</a></td>"
        );
        push( @options,
            "<td><img src=$NicToolClient::image_dir/folder_closed.gif></td><td><a href=group_users.cgi?nt_group_id=$group->{'nt_group_id'}>Users</a></td>"
        );
        push( @options,
            "<td><img src=$NicToolClient::image_dir/folder_closed.gif></td><td><a href=group_log.cgi?nt_group_id=$group->{'nt_group_id'}>Log</a></td>"
        );

        print qq[
<table width=100%>
 <tr class=light_grey_bg>
  <td>
   <table class='no_pad' width=100%>
    <tr>
        ];

        for my $x ( 1 .. $_ ) {
            print "<td><img src=$NicToolClient::image_dir/"
                . ( $x == $_ ? 'dirtree_elbow' : 'transparent' )
                . ".gif width=17 height=17></td>";
        }

        print "<td><img src=$NicToolClient::image_dir/group.gif></td>";

        if ( $in_summary and ( $_ == $count ) ) {
            print
                "<td nowrap><b>$group->{'name'}</b></td>";
        }
        else {
            print
                "<td nowrap><a href=group.cgi?nt_group_id=$group->{'nt_group_id'}>$group->{'name'}</a></td>";
        }

        print "
     <td align=right width=100%>
      <table class='no_pad'><tr>",
            join( '<td>&nbsp;|&nbsp;</td>', @options) . "</tr></table></td>";
        print "
    </tr>
   </table>
  </td>
 </tr>
</table>";
    }

    return $count + 1;
}

sub display_zone_list_options {
    my ( $self, $user, $group_id, $level, $in_zone_list ) = @_;

    my $q = $self->{'CGI'};

    my @options;
    if ( $user->{'zone_create'} ) {
        push( @options,
            "<a href=group_zones.cgi?nt_group_id=$group_id&new=1>New Zone</a>"
        ) unless ($in_zone_list);
    }
    else {
        push @options, '<span class="disabled">New Zone</span>'
            unless $in_zone_list;
    }
    push( @options,
        "<a href=group_zones_log.cgi?nt_group_id=$group_id>View Zone Log</a>"
    ) unless ($in_zone_list);

    print qq[ 
<table style="width:100%">
 <tr class=light_grey_bg>
  <td>
   <table class="no_pad" style="width: 100%;">
    <tr>];

    for my $x ( 1 .. $level ) {
        print qq[<td><img src="$NicToolClient::image_dir/]
            . ( $x == $level ? 'dirtree_elbow' : 'transparent' )
            . qq[.gif" width=17 height=17></td>];
    }

    print "<td><img src=$NicToolClient::image_dir/folder_open.gif></td>";

    if ($in_zone_list) {
        print qq[<td style="text-wrap: none;"><b>Zones</b></td>];
    }
    else {
        print qq[<td style="text-wrap: none;"><a href="group_zones.cgi?nt_group_id=$group_id">Zones</a></td>];
    }

    print "<td align=right width=100%>", join( ' | ', @options ), "</td>
    </tr></table>
    </td></tr></table>";
}

sub display_user_list_options {
    my ( $self, $user, $group_id, $level, $in_user_list ) = @_;

    my $q = $self->{'CGI'};

    my @options;
    if ( $user->{'user_create'} ) {
        push @options, qq[<a href="group_users.cgi?nt_group_id=$group_id&new=1">New User</a>]
        unless ($in_user_list);
    }
    else {
        push @options, '<span class="disabled">New User</span>' unless $in_user_list;
    }

    print qq[<table width=100%>
    <tr class=light_grey_bg>
    <td>
    <table class="no_pad" width=100%>
    <tr>];

    for my $x ( 1 .. $level ) {
        print "<td><img src=$NicToolClient::image_dir/"
            . ( $x == $level ? 'dirtree_elbow' : 'transparent' )
            . ".gif width=17 height=17></td>";
    }

    print "<td><img src=$NicToolClient::image_dir/folder_open.gif></td>";

    if ($in_user_list) {
        print "<td nowrap><b>Users</b></td>";
    }
    else {
        print qq[<td nowrap><a href="group_users.cgi?nt_group_id=$group_id">Users</a></td>];
    }

    print "<td align=right width=100%>", join( ' | ', @options ), "</td>";
    print "</tr></table>";
    print "</td></tr></table>";
}

sub display_zone_options {
    my ( $self, $user, $zone, $level, $in_zone ) = @_;

    my $group = $self->get_group( nt_group_id => $user->{'nt_group_id'} );

    my $q = $self->{'CGI'};

    my $isdelegate = exists $zone->{'delegated_by_id'} ? 1 : 0;

    my @options;

    #delete option
    if ( $user->{'zone_delete'} && !$isdelegate && !$zone->{'deleted'} ) {
        push @options,
                  qq[<a href="group_zones.cgi?nt_group_id=]
                . $q->param('nt_group_id')
                . qq[&zone_list=$zone->{'nt_zone_id'}&delete=1" onClick="return confirm('Delete $zone->{'zone'} and all associated resource records?');">Delete</a>];
    }
    elsif ( $zone->{'deleted'} ) {
        push @options, qq[<a href="zone.cgi?nt_group_id=$zone->{'nt_group_id'}&nt_zone_id=$zone->{'nt_zone_id'}&edit_zone=1&undelete=1">Undelete</a>];

    }
    elsif ( !$isdelegate ) {
        push @options, '<span style="disabled">Delete</span>';
    }
    elsif ($user->{'zone_delete'}
        && $isdelegate
        && $zone->{'delegate_delete'} )
    {
        push @options, qq[<a href="group_zones.cgi?nt_group_id=$q->param('nt_group_id')&nt_zone_id=$zone->{'nt_zone_id'}&deletedelegate=1" onClick="return confirm('Remove delegation of $zone->{'zone'}?');">Remove Delegation</a>];
    }
    elsif ($isdelegate) {
        push @options, '<span class="disabled">Remove Delegation</span>';
    }

    if ( $user->{'zone_write'} && !$isdelegate && !$zone->{'deleted'} ) {
        push @options, qq[<a href="javascript:void window.open('move_zones.cgi?obj_list=$zone->{'nt_zone_id'}', 'move_win', 'width=640,height=480,scrollbars,resizable=yes')">Move</a>] if $group->{'has_children'};
    }
    elsif ( !$isdelegate ) {
        push @options, '<span class="disabled">Move</span>' if $group->{'has_children'};
    }

    if ( $user->{'zone_delegate'} && !$isdelegate && !$zone->{'deleted'} ) {
        push @options, qq[<a href="javascript:void window.open('delegate_zones.cgi?obj_list=$zone->{'nt_zone_id'}', 'delegate_win', 'width=640,height=480,scrollbars,resizable=yes')">Delegate</a>] if $group->{'has_children'};
    }
    elsif ( !$isdelegate ) {
        push @options, '<span class="disabled">Delegate</span>' if $group->{'has_children'};
    }
    elsif ($user->{'zone_delegate'}
        && $isdelegate
        && $zone->{'delegate_delegate'} )
    {
        push @options, qq[<a href="javascript:void window.open('delegate_zones.cgi?obj_list=$zone->{'nt_zone_id'}', 'delegate_win', 'width=640,height=480,scrollbars,resizable=yes')">Re-Delegate</a>] if $group->{'has_children'};
    }
    elsif ($isdelegate) {
        push @options, '<span color="disabled">Re-Delegate</span>' if $group->{'has_children'};
    }
    print qq[<table width=100%>
    <tr class=light_grey_bg>
    <td>
    <table class="no_pad" width=100%>
    <tr>];

    for my $x ( 1 .. $level ) {
        print "<td><img src=$NicToolClient::image_dir/"
            . ( $x == $level ? 'dirtree_elbow' : 'transparent' )
            . ".gif width=17 height=17></td>";
    }
    if ($isdelegate) {
        my $type = ( $zone->{'pseudo'} ? 'pseudo' : 'delegated' );
        print "<td><img src=$NicToolClient::image_dir/zone-$type.gif></td>";
    }
    else {
        print "<td><img src=$NicToolClient::image_dir/zone.gif></td>";
    }

    my $tag = (
        $isdelegate && !$zone->{'pseudo'}
        ? "&nbsp;<img src=$NicToolClient::image_dir/perm-"
            . ( $zone->{'delegate_write'} ? "write.gif" : "nowrite.gif" )
            . ">"

        : ''
    );
    if ($in_zone) {
        print "<td nowrap><b>$zone->{'zone'}</b>$tag</td>";
    }
    else {
        print qq[<td nowrap><a href="zone.cgi?nt_group_id=$q->param('nt_group_id')&nt_zone_id=$zone->{'nt_zone_id'}">$zone->{'zone'}</a>$tag</td>];
    }

    print "<td align=right width=100%>", join( ' | ', @options ), "</td>";
    print "</tr></table>";
    print "</td></tr></table>";
}

sub display_nameserver_options {
    my ( $self, $user, $group_id, $level, $in_ns_summary ) = @_;

    my @options;
    if ( $user->{'nameserver_create'} ) {
        push( @options,
            "<a href=group_nameservers.cgi?nt_group_id=$group_id&edit=1>New Nameserver</a>"
        ) if !$in_ns_summary;
    }
    else {
        push @options, '<span class="disabled">New Nameserver</class>' if !$in_ns_summary;
    }

    print qq[<table width=100%>
    <tr class=light_grey_bg>
    <td>
    <table class="no_pad" width=100%>
    <tr>];

    for my $x ( 1 .. $level ) {
        print "<td><img src=$NicToolClient::image_dir/"
            . ( $x == $level ? 'dirtree_elbow' : 'transparent' )
            . ".gif width=17 height=17></td>";
    }

    print "<td><img src=$NicToolClient::image_dir/folder_open.gif></td>";

    if ($in_ns_summary) {
        print "<td nowrap><b>Nameservers</b></td>";
    }
    else {
        print "<td nowrap><a href=group_nameservers.cgi?nt_group_id=$group_id>Nameservers</a></td>";
    }

    print "<td align=right width=100%>", join( ' | ', @options ), "</td>";
    print "</tr></table>";
    print "</td></tr></table>";
}

sub paging_fields {
    [   qw(quick_search search_value Search 1_field 1_option 1_value 1_inclusive 2_field 2_option 2_value 2_inclusive
            3_field 3_option 3_value 3_inclusive 4_field 4_option 4_value 4_inclusive 5_field 5_option 5_value 5_inclusive
            change_sortorder 1_sortfield 1_sortmod 2_sortfield 2_sortmod 3_sortfield 3_sortmod start limit page edit_search
            edit_sortorder include_subgroups)
    ];
}

sub prepare_search_params {
    my ( $self, $q, $field_labels, $params, $sort_fields, $default_limit,
        $moreparams )
        = @_;

    $default_limit ||= 20;

    my $search_query = '';

    if ( $q->param('Search') ) {
        foreach ( 1 .. 5 ) {
            if (   $q->param( $_ . '_field' ) ne '--'
                && $q->param( $_ . '_option' ) ne '--'
                && $q->param( $_ . '_value' )  ne '' )
            {
                $params->{'Search'} = 1;

                if ( $_ != 1 ) {
                    $params->{ $_ . '_inclusive' }
                        = $q->param( $_ . '_inclusive' );
                    $params->{'search_query'}
                        .= ' ' . uc( $q->param( $_ . '_inclusive' ) ) . ' ';
                }

                $params->{ $_ . '_field' }  = $q->param( $_ . '_field' );
                $params->{ $_ . '_option' } = $q->param( $_ . '_option' );
                $params->{ $_ . '_value' }  = $q->param( $_ . '_value' );

                $params->{'search_query'}
                    .= $field_labels->{ $q->param( $_ . '_field' ) } . ' '
                    . $q->param( $_ . '_option' ) . " '"
                    . $q->param( $_ . '_value' ) . "'";
            }
        }
    }

    if ( $q->param('change_sortorder') || $params->{'Search'} ) {
        foreach ( 1 .. 3 ) {
            if ( $q->param( $_ . '_sortfield' ) ne '--' ) {
                $sort_fields->{ $q->param( $_ . '_sortfield' ) } = {
                    'order' => $_,
                    'mod'   => $q->param( $_ . '_sortmod' )
                };

                $params->{'Sort'} = 1;
                $params->{ $_ . '_sortfield' }
                    = $q->param( $_ . '_sortfield' );
                $params->{ $_ . '_sortmod' } = $q->param( $_ . '_sortmod' );
            }
        }
    }

    if ( $q->param('quick_search') ) {
        if ( $q->param('search_value') ) {
            $params->{'quick_search'} = 1;
            $params->{'search_value'} = $q->param('search_value');
            $params->{'search_query'} = "'" . $q->param('search_value') . "'";
        }
    }

    $params->{'search_query'} ||= 'ALL';

    $params->{'include_subgroups'} = $q->param('include_subgroups');
    $params->{'exact_match'}       = $q->param('exact_match');

    $params->{'limit'} = $default_limit;
    $params->{'page'}  = $q->param('page');
    $params->{'start'} = $q->param('start');
}

sub display_search_rows {
    my ( $self, $q, $rv, $params, $cgi_name, $state_fields,
        $include_subgroups, $moreparams )
        = @_;

    my $morestr = join( "&", map {"$_=$moreparams->{$_}"} keys %$moreparams );

    if (   !( $q->param('Search') )
        && !( $q->param('quick_search') )
        && ( !($include_subgroups) && ( $rv->{'total'} <= $rv->{'limit'} ) ) )
    {
        return;
    }

    my @state_vars;
    foreach ( @{ $self->paging_fields }, @$state_fields ) {

        next if ( $_ eq 'start' );
        next if ( $_ eq 'limit' );
        next if ( $_ eq 'page' );

        push( @state_vars, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    print qq[<table width=100%>
    <tr class=dark_grey_bg><td><table class="no_pad" width=100%>
    <tr>],
    $q->startform( -action => $cgi_name, -method => 'POST' );
    foreach (@$state_fields) {
        print $q->hidden( -name => $_ );
    }
    print "<td>";
    print $q->textfield(
        -name     => 'search_value',
        -size     => 30,
        -override => 1
    );
    print $q->hidden(
        -name     => 'quick_search',
        -value    => 'Enter',
        -override => 1
    );
    foreach ( keys %$moreparams ) {
        print $q->hidden(
            -name     => $_,
            -value    => $moreparams->{$_},
            -override => 1
        );
    }
    print $q->submit( -name => 'quick_search', -value => 'Search' );
    print " &nbsp; &nbsp;",
        $q->checkbox(
        -name    => 'include_subgroups',
        -value   => 1,
        -label   => 'include sub-groups',
        -checked => $NicToolClient::include_subgroups_checked
        ) if $include_subgroups;
    print " &nbsp; &nbsp;",
        $q->checkbox(
        -name    => 'exact_match',
        -value   => 1,
        -label   => 'exact match',
        -checked => $NicToolClient::exact_match_checked
        );
    print "</td>";

    print $q->endform;
    print $q->startform( -action => $cgi_name, -method => 'POST' );
    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if ( $_ eq 'page' );

        print $q->hidden( -name => $_ ) if ( $q->param($_) );
    }
    foreach ( keys %$moreparams ) {
        print $q->hidden(
            -name     => $_,
            -value    => $moreparams->{$_},
            -override => 1
        );
    }
    print "<td align=right>";
    if ( $rv->{'start'} - $rv->{'limit'} >= 0 ) {
        print "<a href=$cgi_name?"
            . join( '&', @state_vars )
            . "&start=1&limit=$params->{'limit'}"
            . ( $morestr ? "&$morestr" : "" )
            . "><b><<</b></a> &nbsp; ";
        print "<a href=$cgi_name?"
            . join( '&', @state_vars )
            . "&start="
            . ( $rv->{'start'} - $rv->{'limit'} )
            . "&limit=$params->{'limit'}"
            . ( $morestr ? "&$morestr" : "" )
            . "><B><</b></a> &nbsp; ";
    }
    print "Page ",
        $q->textfield(
        -name  => 'page',
        -value => (
            $rv->{'end'} % $rv->{'limit'}
            ? int( $rv->{'end'} / $rv->{'limit'} ) + 1
            : $rv->{'end'} / $rv->{'limit'}
        ),
        -size     => 4,
        -override => 1
        ),
        " of $rv->{'total_pages'}";
    if ( ( $rv->{'end'} + 1 ) <= $rv->{'total'} ) {
        print " &nbsp; <a href=$cgi_name?"
            . join( '&', @state_vars )
            . "&start="
            . ( $rv->{'end'} + 1 )
            . "&limit=$params->{'limit'}"
            . ( $morestr ? "&$morestr" : "" )
            . "><b>></b></a>";
        print " &nbsp; <a href=$cgi_name?"
            . join( '&', @state_vars )
            . "&page=$rv->{'total_pages'}&limit=$params->{'limit'}"
            . ( $morestr ? "&$morestr" : "" )
            . "><b>>></b></a>";
    }
    print "</td>";
    print "</tr>";
    print "</table></td></tr>";
    print "</table>";

    @state_vars = ();
    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if ( $_ eq 'edit_search' );
        next if ( $_ eq 'edit_sortorder' );

        push( @state_vars, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    print qq[
<table width=100%>
 <tr class=dark_grey_bg><td><table class="no_pad" width=100%>
    <tr>
     <td>Search: $params->{'search_query'} found $rv->{'total'} records</td>
     <td align=right><a href="$cgi_name?]
        . join( '&', @state_vars )
        . "&edit_search=1"
        . ( $morestr ? "&$morestr" : "" )
        . qq[">Advanced Search</a> | <a href="$cgi_name?]
        . join( '&', @state_vars )
        . "&edit_sortorder=1"
        . ( $morestr ? "&$morestr" : "" )
        . qq[">Change Sort Order</a> | <a href=$cgi_name?]
        . join( '&',
        map( "$_=" . $q->escape( $q->param($_) ), @$state_fields ) )
        . ( $morestr ? "&$morestr" : "" )
        . ">Browse All</a>
        </td>
    </tr></table></td></tr>
</table>";
}

sub display_sort_options {
    my ( $self, $q, $columns, $labels, $cgi_name, $state_fields,
        $include_subgroups, $moreparams )
        = @_;

    print $q->startform( -action => $cgi_name, -method => 'POST' );
    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if ( $_ =~ /sort/i );
        next if ( $_ eq 'edit_sortorder' );
        next if ( $_ eq 'start' );
        next if ( $_ eq 'limit' );
        next if ( $_ eq 'page' );

        print $q->hidden( -name => $_ ) if ( $q->param($_) );
    }
    foreach ( keys %$moreparams ) {
        print $q->hidden(
            -name     => $_,
            -value    => $moreparams->{$_},
            -override => 1
        );
    }

    print "<table width=100%>";
    print "<tr class=dark_bg><td colspan=2><b>Change Sort Order</b></td></tr>";
    foreach ( 1 .. 3 ) {
        print "<tr class=light_grey_bg>";
        print "<td nowrap>",
            ( $_ == 1 ? 'Sort by' : 'Then by' ), "</td>";
        print "<td width=100%>";
        print $q->popup_menu(
            -name     => $_ . '_sortfield',
            -values   => [ '--', @$columns ],
            -labels   => { '--' => '--', %$labels },
            -override => 1
            ),
            " ";
        print $q->popup_menu(
            -name     => $_ . '_sortmod',
            -values   => [ 'Ascending', 'Descending' ],
            -override => 1
        );
        print "</td>";
        print "</tr>";
    }
    print qq[<tr class=dark_grey_bg><td colspan=2 align=center><table class="no_pad"><tr>
    <td>],
    $q->submit( -name => 'change_sortorder', -value => 'Change' ),
    qq[</td>],
    $q->endform,
    $q->startform( -action => $cgi_name, -method => 'POST' );

    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if ( $_ eq 'edit_sortorder' );

        print $q->hidden( -name => $_ ) if ( $q->param($_) );
    }

    print "<td>";
    print $q->submit('Cancel'), "</td></tr>";
    print "</table></td></tr></table>";
    print $q->endform;
}

sub display_advanced_search {
    my ( $self, $q, $columns, $labels, $cgi_name, $state_fields,
        $include_subgroups, $moreparams )
        = @_;

    my @options = (
        'equals', 'contains', 'starts with', 'ends with',
        '<',      '<=',       '>',           '>='
    );

    print $q->start_form( -action => $cgi_name, -method => 'POST' );

    foreach (@$state_fields) {
        print $q->hidden( -name => $_ );
    }

    foreach ( keys %$moreparams ) {
        print $q->hidden(
            -name     => $_,
            -value    => $moreparams->{$_},
            -override => 1
        );
    }

    print "<table width=100%>";
    print "<tr class=dark_bg><td colspan=2><b>Advanced Search</b></td></tr>";
    print "<tr class=light_grey_bg><td colspan=2>",
        $q->checkbox(
        -name    => 'include_subgroups',
        -value   => 1,
        -label   => 'include sub-groups',
        -checked => $NicToolClient::include_subgroups_checked,
        ),
        "</td></tr>";

    print "<tr class=dark_grey_bg>";
    foreach ( ( 'Inclusive / Exclusive', 'Condition' ) ) {
        print "<td align=center>", $_, "</td>";
    }
    print "</tr>";

    foreach ( 1 .. 5 ) {
        print "<tr class=light_grey_bg>\n";
        print "<td align=center>",
            (
            $_ == 1 ? '&nbsp;' : $q->radio_group(
                -name     => $_ . '_inclusive',
                -values   => [ 'And', 'Or' ],
                -default  => 'Or',
                -override => 1
            )
            ),
            "</td>\n";
        print "<td>",
            $q->popup_menu(
            -name     => $_ . '_field',
            -values   => [ '--', @$columns ],
            -labels   => { '--' => '- select -', %$labels },
            -override => 1
            );
        print $q->popup_menu(
            -name     => $_ . '_option',
            -values   => \@options,
            -override => 1
        ) . "\n";
        print $q->textfield(
            -name     => $_ . '_value',
            -size     => 30,
            -override => 1
            ),
            "</td>\n";
        print "</tr>\n";
    }
    print "</table>";

    print "<table width=100%>";
    print "<tr class=dark_grey_bg><td colspan=2><b>Sort Order</b> (optional)</td></tr>";
    foreach ( 1 .. 3 ) {
        print "<tr class=light_grey_bg>";
        print "<td>", ( $_ == 1 ? 'sort by' : "then by" ), "</td>";
        print "<td>",
            $q->popup_menu(
            -name   => $_ . '_sortfield',
            -values => [ '--', @$columns ],
            -labels => { '--' => '--', %$labels }
            ),
            $q->popup_menu(
            -name   => $_ . '_sortmod',
            -values => [ 'Ascending', 'Descending' ]
            ),
            "</td>";
        print "</tr>";
    }
    print "</table>";

    print qq[<table width=100%>
    <tr class=dark_grey_bg><td align=center><table class="no_pad"><tr>
    <td>],
    $q->submit('Search'),
    "</td>",
    $q->endform,
    $q->startform( -action => $cgi_name, -method => 'POST' );

    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if ( $_ eq 'edit_search' );

        print $q->hidden( -name => $_ ) if ( $q->param($_) );
    }

    print "<td>";
    print $q->submit('Cancel'), "</td></tr>";
    print "</table></td></tr>";
    print "</table>";

    print $q->endform();
}

sub display_group_list {
    my ( $self, $q, $user, $cgi, $action, $excludeid, $moreparams ) = @_;

    my @columns = qw(group sub_groups);
    $action ||= 'move';
    my %labels = (
        group      => 'Group',
        sub_groups => '*Sub Groups',
    );

    $q->param( 'nt_group_id', $user->{'nt_group_id'} )
        unless $q->param('nt_group_id');

    my $group = $self->get_group( nt_group_id => $q->param('nt_group_id') );

    unless ( $group->{'has_children'} ) {
        print qq( <center><span style="color:red;"><strong>Group $group->{'name'} has no sub-groups!</strong></span></center>);
        $q->param( 'nt_group_id', $group->{'parent_group_id'} );
        $group = $self->get_group( nt_group_id => $q->param('nt_group_id') );
    }
    my $include_subgroups = $group->{'has_children'} ? 'sub-groups' : undef;

    my %params = (
        nt_group_id    => $q->param('nt_group_id'),
        start_group_id => $user->{'nt_group_id'}
    );
    $params{'include_parent'} = 1
        if ( $user->{'nt_group_id'} == $q->param('nt_group_id') );

    my %sort_fields;
    $self->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        $NicToolClient::page_length );

    $sort_fields{'group'} = { 'order' => 1, 'mod' => 'Ascending' }
        unless %sort_fields;
    my $rv = $self->get_group_subgroups(%params);

    $self->display_sort_options( $q, \@columns, \%labels, $cgi,
        [ 'obj_list', 'nt_group_id' ],
        $include_subgroups, $moreparams )
        if $q->param('edit_sortorder');
    $self->display_advanced_search( $q, \@columns, \%labels, $cgi,
        [ 'obj_list', 'nt_group_id' ],
        $include_subgroups, $moreparams )
        if $q->param('edit_search');

    return $self->display_error($rv) if ( $rv->{'error_code'} != 200 );

    my $groups = $rv->{'groups'};
    my $map    = $rv->{'group_map'};

    my @state_fields;
    foreach ( @{ $self->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }
    print qq[<table width=100%>
    <tr class=dark_grey_bg><td>
    <table class="no_pad" width=100%>
    <tr>
    <td><b>Select the group to $action to.</b></td>
    <td align=right> &nbsp; </td>
    </tr></table></td></tr>
    </table>];

    $self->display_search_rows( $q, $rv, \%params, $cgi,
        [ 'obj_list', 'nt_group_id' ],
        $include_subgroups, $moreparams );

    if (@$groups) {
        print qq[<table width=100%>
        <tr class=dark_grey_bg>
        <td>
        <table class="no_pad">
        <tr><td></td>],
        $q->endform,
        $q->start_form(
            -action => $cgi,
            -method => 'POST',
            -name   => 'new'
        ),
        "\n",
        $q->hidden(
            -name     => 'obj_list',
            -value    => join( ',', $q->param('obj_list') ),
            -override => 1
        ),
        "\n";

        foreach ( @{ $self->paging_fields() } ) {
            print $q->hidden( -name => $_ ) if ( $q->param($_) );
        }
        foreach ( keys %$moreparams ) {
            print $q->hidden( -name => $_, -value => $moreparams->{$_} );
        }
        print "<td></td></tr>";
        print "</table>";

        print "&nbsp;</td>";
        foreach (@columns) {
            if ( $sort_fields{$_} ) {
                print qq[<td class=dark_bg align=center><table class="no_pad">
                <tr>
                <td>$labels{$_}</td>
                <td>&nbsp; &nbsp; $sort_fields{$_}->{'order'}</td>
                <td><img src=$NicToolClient::image_dir/],
                    (
                    uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING'
                    ? 'up.gif'
                    : 'down.gif'
                    ),
                    "></tD>";
                print "</tr></table></td>";

            }
            else {
                print "<td align=center>$labels{$_}</td>";
            }
        }
        print "</tr>";

        my $x = 0;

        foreach my $group (@$groups) {
            print "<tr class="
                . ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' )
                . ">";
            if ( $group->{'nt_group_id'} eq $excludeid ) {
                print "<td width=1%> &nbsp;</td>";
            }
            else {
                print
                    "<td width=1%><input type=radio name=group_list value='$group->{'nt_group_id'}'",
                    ( $x == 1 ? " checked" : "" ), "></td>";

            }

            print qq[<td><table class="no_pad"><tr>
            <td><img src=$NicToolClient::image_dir/group.gif></td>
            <td>],
                join(
                ' / ',
                map( "<a href=$cgi?nt_group_id=$_->{'nt_group_id'}&obj_list="
                        . $q->param('obj_list')
                        . (
                        $moreparams
                        ? "&"
                            . join( "&",
                            map {"$_=$moreparams->{$_}"} keys %$moreparams )
                        : ''
                        )
                        . ">$_->{'name'}</a>",
                    (   @{ $map->{ $group->{'nt_group_id'} } },
                        {   nt_group_id => $group->{'nt_group_id'},
                            name        => $group->{'name'}
                        }
                        ) )
                ),
                "</td></tr></table></td>";

            print "<td>",
                ( $group->{'children'} ? $group->{'children'} : 'n/a' ),
                "</td></tr>";
        }

        print "</table>";
    }

    #print $q->endform;
}

sub redirect_from_log {
    my ( $self, $q ) = @_;

    my $message;

    if ( $q->param('object') eq 'zone' ) {
        my $obj = $self->get_zone(
            nt_group_id => $q->param('nt_group_id'),
            nt_zone_id  => $q->param('obj_id')
        );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {

#if( $obj->{'deleted'} ) {
#$message = "$obj->{'zone'} is deleted. You are unable to view deleted zones.";
#} else {
            print $q->redirect(
                "zone.cgi?nt_group_id=$obj->{'nt_group_id'}&nt_zone_id=$obj->{'nt_zone_id'}"
            );

            #}
        }
    }
    elsif ( $q->param('object') eq 'nameserver' ) {
        my $obj = $self->get_nameserver(
            nt_group_id      => $q->param('nt_group_id'),
            nt_nameserver_id => $q->param('obj_id')
        );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {
            if ( $obj->{'deleted'} ) {
                $message = {
                    error_msg =>
                        "Cannot view Nameserver '$obj->{'name'}': the object has been deleted.",
                    error_desc => 'Object is deleted',
                    error_code => 'client'
                };
            }
            else {
                print $q->redirect(
                    "group_nameservers.cgi?nt_group_id=$obj->{'nt_group_id'}&nt_nameserver_id=$obj->{'nt_nameserver_id'}&edit=1"
                );
            }
        }
    }
    elsif ( $q->param('object') eq 'user' ) {
        my $obj = $self->get_user(
            nt_group_id => $q->param('nt_group_id'),
            nt_user_id  => $q->param('obj_id')
        );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {
            if ( $obj->{'deleted'} ) {
                $message = {
                    error_msg =>
                        "Cannot view User '$obj->{'username'}': the object has been deleted.",
                    error_desc => 'Object is deleted',
                    error_code => 'client'
                };
            }
            else {
                print $q->redirect(
                    "user.cgi?nt_group_id=$obj->{'nt_group_id'}&nt_user_id=$obj->{'nt_user_id'}"
                );
            }
        }
    }
    elsif ( $q->param('object') eq 'zone_record' ) {
        my $obj = $self->get_zone_record(
            nt_zone_record_id => $q->param('obj_id') );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {
            if ( $obj->{'deleted'} ) {
                $message = {
                    error_msg =>
                        "Cannot view Zone Record '$obj->{'name'}': the object has been deleted.",
                    error_desc => 'Object is deleted',
                    error_code => 'client'
                };
            }
            else {
                print $q->redirect( "zone.cgi?nt_group_id="
                        . $q->param('nt_group_id')
                        . "&nt_zone_id=$obj->{'nt_zone_id'}&nt_zone_record_id=$obj->{'nt_zone_record_id'}&edit_record=1"
                );
            }
        }
    }
    elsif ( $q->param('object') eq 'group' ) {
        my $obj = $self->get_group( nt_group_id => $q->param('obj_id') );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {
            if ( $obj->{'deleted'} ) {
                $message = {
                    error_msg =>
                        "Cannot view Group '$obj->{'name'}': the object has been deleted.",
                    error_desc => 'Object is deleted',
                    error_code => 'client'
                };
            }
            else {
                print $q->redirect(
                    "group.cgi?nt_group_id=$obj->{'nt_group_id'}");
            }
        }
    }
    else {
        $message = {
            error_msg  => "Unable to find object",
            error_desc => 'Not Found',
            error_code => 'client'
        };
    }

    return $message;
}

sub display_move_javascript {
    my ( $self, $cgi, $name ) = @_;
    print <<ENDJS;
<script language='javascript'>
function selectAllorNone(group, action) {
    if(group.length){
        for( var x = 0; x < group.length; x++ ) {
                group[x].checked = action;
        }
    }else{
        group.checked=action;
    }
}
function open_move(list) {
    var obj_list = new Array();
    if( list.length ) {
            var y = 0;
            for( x = 0; x < list.length; x++ ) {
                    if( list[x].checked ) obj_list[y++] = list[x].value;
            }
    } else {
            if( list.checked ) obj_list[0] = list.value;
    }
    if( obj_list.length > 0 ) {
            newwin = window.open('$cgi?obj_list=' + obj_list.join(','), 'move_win', 'width=640,height=480,scrollbars,resizable=yes');
            newwin.opener = self;
    } else {
            alert('Select at least one $name');
    }
}
</script>
ENDJS
}

sub display_delegate_javascript {
    my ( $self, $cgi, $name ) = @_;
    print <<ENDJS;
<script language='javascript'>
function open_delegate(list) {
    var obj_list = new Array();
    if( list.length ) {
            var y = 0;
            for( x = 0; x < list.length; x++ ) {
                    if( list[x].checked ) obj_list[y++] = list[x].value;
            }
    } else {
            if( list.checked ) obj_list[0] = list.value;
    }
    if( obj_list.length > 0 ) {
            newwin = window.open('$cgi?obj_list=' + obj_list.join(','), 'move_win', 'width=640,height=480,scrollbars,resizable=yes');
            newwin.opener = self;
    } else {
            alert('Select at least one $name');
    }
}
</script>
ENDJS
}

sub display_perms_javascript {
    my ( $self, $cgi, $name ) = @_;
    print <<ENDJS;
<script language='javascript'>

//access types
function selectAllEdit(form, action) {
    if(form.group_write)
        form.group_write.checked=action;
    if(form.user_write)
        form.user_write.checked=action;
    if(form.zone_write)
        form.zone_write.checked=action;
    if(form.zonerecord_write)
        form.zonerecord_write.checked=action;
    if(form.nameserver_write)
        form.nameserver_write.checked=action;
    if(form.self_write)
        form.self_write.checked=action;
}
function selectAllCreate(form, action) {
    if(form.group_create)
        form.group_create.checked=action;
    if(form.user_create)
        form.user_create.checked=action;
    if(form.zone_create)
        form.zone_create.checked=action;
    if(form.zonerecord_create)
        form.zonerecord_create.checked=action;
    if(form.nameserver_create)
        form.nameserver_create.checked=action;
}
function selectAllDelete(form, action) {
    if(form.group_delete)
        form.group_delete.checked=action;
    if(form.user_delete)
        form.user_delete.checked=action;
    if(form.zone_delete)
        form.zone_delete.checked=action;
    if(form.zonerecord_delete)
        form.zonerecord_delete.checked=action;
    if(form.nameserver_delete)
        form.nameserver_delete.checked=action;
}
function selectAllDelegate(form, action) {
    if(form.zone_delegate)
        form.zone_delegate.checked=action;
    if(form.zonerecord_delegate)
        form.zonerecord_delegate.checked=action;
}
function selectAllAll(form, action) {
    selectAllEdit(form,action);
    selectAllCreate(form,action);
    selectAllDelete(form,action);
    selectAllDelegate(form,action);
}


//object types
function selectAllGroup(form, action) {
    if(form.group_write)
        form.group_write.checked=action;
    if(form.group_create)
        form.group_create.checked=action;
    if(form.group_delete)
        form.group_delete.checked=action;
}
function selectAllUser(form, action) {
    if(form.user_write)
        form.user_write.checked=action;
    if(form.user_create)
        form.user_create.checked=action;
    if(form.user_delete)
        form.user_delete.checked=action;
}
function selectAllZone(form, action) {
    if(form.zone_create)
        form.zone_create.checked=action;
    if(form.zone_write)
        form.zone_write.checked=action;
    if(form.zone_delete)
        form.zone_delete.checked=action;
    if(form.zone_delegate)
        form.zone_delegate.checked=action;
}
function selectAllZonerecord(form, action) {
    if(form.zonerecord_write)
        form.zonerecord_write.checked=action;
    if(form.zonerecord_create)
        form.zonerecord_create.checked=action;
    if(form.zonerecord_delete)
        form.zonerecord_delete.checked=action;
    if(form.zonerecord_delegate)
        form.zonerecord_delegate.checked=action;
}
function selectAllNameserver(form, action) {
    if(form.nameserver_write)
        form.nameserver_write.checked=action;
    if(form.nameserver_create)
        form.nameserver_create.checked=action;
    if(form.nameserver_delete)
        form.nameserver_delete.checked=action;
}
function selectAllSelf(form, action) {
    if(form.self_write)
        form.self_write.checked=action;
}
</script>
ENDJS
}

sub display_hr {
    print qq[<table style="width:100%;"><tr><td><hr></td></tr></table>];
}

sub error_message {
    my ( $self, $code, $msg ) = @_;
    $code ||= 700;
    my $errs = {
        200 => ['OK'],

        300 => ['Sanity Error'],
        301 => [
            'Some Required Parameters Missing',
            "Data may be missing from a previous operation.  Please click 'Back' on your browser and try again."
        ],
        302 => ['Some parameters were invalid'],

        403 => [
            'Invalid Username and/or password',
            $NicToolClient::generic_error_message
        ],
        404 => [
            'Access Permission Denied',
            $NicToolClient::generic_error_message
        ],

        #405=>'Delegation Permission denied: ',
        #406=>'Creation Permission denied: ',
        #407=>'Delegate Access Permission denied: ',

        500 => [
            'Unknown Action Requested',
            $NicToolClient::generic_error_message
        ],
        501 => [
            'Client-Server Connectivity Error',
            $NicToolClient::generic_error_message
        ],
        502 =>
            [ 'XML-RPC Data Error', $NicToolClient::generic_error_message ],
        503 => [
            'Method has been deprecated',
            $NicToolClient::generic_error_message
        ],
        505 =>
            [ 'Database Query Error', $NicToolClient::generic_error_message ],
        507 => [ 'Internal Error', $NicToolClient::generic_error_message ],
        508 => [ 'Internal Error', $NicToolClient::generic_error_message ],
        510 => [
            'Incorrect Protocol Version Number',
            'You probably need to upgrade the client to connect to the chosen server.'
        ],

        600 => ['Failed to Complete Request'],
        601 => ['Object Not Found'],

        700    => [ 'Unknown Error', $NicToolClient::generic_error_message ],
        client => ['Client Error'],
    };

    my $res = $errs->{$code};
    $res ||= $errs->{700};

    #$res.=$msg if $msg;
    return $res;
}

sub display_nice_message {
    my ( $self, $message, $title, $explain ) = @_;
    my @msgs = split( /\bAND\b/, $message );
    $message = qq( <li style="color: blue;"> )
        . join( qq(<br>\n<li style="color: blue;"> ), @msgs )
        . '<br>';

    print qq{
        <table width=100% align=center>
            <tr><td align=left class=dark_bg>
                <B>$title</b></td></tr>
            <tr>
                <td align=left class=light_grey_bg> $message<p> $explain </td>
            </tr>
            <tr>
                <td align=center class=dark_grey_bg>&nbsp;</td>
            </tr>
        </table>
    };
    return 0;
}

sub display_nice_error {
    my ( $self, $error, $actionmsg, $back ) = @_;
    my ( $message, $explain )
        = @{ $self->error_message( $error->{'error_code'} ) };
    my $err = $error->{'error_desc'} || 'Error';
    $actionmsg = ": " . $actionmsg if $actionmsg;
    my $errmsg = $error->{'error_msg'};
    my @msgs = split( /\bAND\b/, $errmsg );
    $errmsg = "<span class=error><li>"
        . join( "</span><br>\n<span class=error><li>", @msgs )
        . "</span><br>";
    print qq(
        <table width=100% align=center>
            <tr><td align=left class=error_bg>
                <strong>$message</strong>$actionmsg</td></tr>
            <tr>
                <td align=left class=light_grey_bg> $errmsg<p> $explain </td>
            </tr>
            <tr>
                <td align=right class="dark_grey_bg dark">)
        . (
        $back
        ? '<form><input type=submit value="Back" onClick="javascript:history.go(-1)"></form>'
        : '&nbsp;'
        )
        . qq[ ($error->{'error_code'})</td>
            </tr>
        </table>
    ];

    warn "Client error: $error->{'error_code'}: $error->{'error_msg'}: "
        . join( ":", caller );
    return 0;
}

sub display_error {
    my ( $self, $error ) = @_;

    print qq[ <center class="error"><b>$error->{'error_msg'}</b></center> ];

    warn
        "Client error: $error->{'error_code'}: $error->{'error_msg'}: $error->{'error_desc'} "
        . join( ":", caller );
    return 0;
}

sub zone_record_template_list {

    # the templates available in zone_record_template
    return qw( none basic wildcard basic-spf wildcard-spf );
}

sub zone_record_template {
    my ( $self, $vals ) = @_;

    my $zone     = $vals->{'zone'};
    my $id       = $vals->{'nt_zone_id'};
    my $template = $vals->{'template'};
    my $newip    = $vals->{'newip'};
    my $mailip   = $vals->{'mailip'} || $newip;
    my $debug    = $vals->{'debug'};

    return 0 if ( $template eq "none" || $template eq "" );

    print "zone_record_template: $id, $zone, $template\n" if $debug;

    #               basic template
    #       zone.com.        IN     A      xx.xxx.xx.xx
    #       zone.com.        IN  10 MX     zone.com.
    #       mail             IN     A      xx.xxx.xx.xx
    #       www.zone.com.    IN     CNAME  zone.com.

    my %record1 = (
        nt_zone_id => $id,
        name       => "$zone.",
        type       => "A",
        address    => $newip
    );
    my %record2 = (
        nt_zone_id => $id,
        name       => "mail",
        type       => "A",
        address    => $mailip
    );
    my %record3 = (
        nt_zone_id => $id,
        name       => "www",
        type       => "CNAME",
        address    => "$zone."
    );
    my %record4 = (
        nt_zone_id => $id,
        name       => "$zone.",
        type       => "MX",
        address    => "mail.$zone.",
        weight     => "10"
    );
    my @zr = ( \%record1, \%record2, \%record3, \%record4 );

    if ( $template eq "wildcard" ) {

        #          template Basic with hostname wildcard
        #       zone.com.        IN     A      NN.NNN.NN.NN
        #       zone.com.        IN  10 MX     mail.zone.com.
        #       mail             IN     A      NN.NNN.NN.NN
        #       *.zone.com.      IN     CNAME  zone.com.
        #
        %record3 = (
            nt_zone_id => $id,
            name       => "*",
            type       => "CNAME",
            address    => "$zone."
        );
        @zr = ( \%record1, \%record2, \%record3, \%record4 );
    }
    elsif ( $template eq "basic-spf" ) {
        my %record5 = (
            nt_zone_id => $id,
            name       => "$zone.",
            type       => "TXT",
            address    => "v=spf1 a mx -all"
        );
        my %record6 = (
            nt_zone_id => $id,
            name       => "$zone.",
            type       => "SPF",
            address    => "v=spf1 a mx -all"
        );
        @zr = ( \%record1, \%record2, \%record3, \%record4, \%record5, \%record6 );
    }
    elsif ( $template eq "wildcard-spf" ) {
        %record3 = (
            nt_zone_id => $id,
            name       => "*",
            type       => "CNAME",
            address    => "$zone."
        );
        my %record5 = (
            nt_zone_id => $id,
            name       => "$zone.",
            type       => "TXT",
            address    => "v=spf1 a mx -all"
        );
        my %record6 = (
            nt_zone_id => $id,
            name       => "$zone.",
            type       => "SPF",
            address    => "v=spf1 a mx -all"
        );
        @zr = ( \%record1, \%record2, \%record3, \%record4, \%record5, \%record6 );
    }

    return \@zr;
}

sub refresh_nav {
    my $self = shift;

    print "<script language='JavaScript'>\n";
    print "parent.nav.location = parent.nav.location;\n";
    print "</script>";
}

sub AUTOLOAD {
    my $self = shift;

    my $type = ref($self);
    my $name = $AUTOLOAD;

    unless ( ref($self) ) {
        warn "$type" . "::AUTOLOAD $self is not an object -- (params: @_)\n";
        return undef;
    }

    return if $name =~ /::DESTROY$/;

    $name =~ s/.*://;    # strip fully-qualified portion

    if ( $name =~ /^(get_|new_|edit_|delegate_|save_|delete_|move_)/i ) {
        return $self->{'nt_server_obj'}->send_request(
            action => "$name",
            @_, nt_user_session => $self->{'CGI'}->cookie('NicTool')
        );
    }
    else {
        return { error_code => '900', error_msg => 'Invalid action' };
    }
}

1;
__END__

=head1 SYNOPSIS

Methods used by the CGI files in the htdocs directory

=cut
