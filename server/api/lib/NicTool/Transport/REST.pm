package NicTool::Transport::REST;

# ABSTRACT: REST/JSON transport for NicTool v3 API

use strict;
use warnings;
use parent 'NicTool::Transport';
use HTTP::Tiny;
use JSON::PP;

my $JSON = JSON::PP->new->utf8->allow_nonref;

# v2 action -> { method, path, [id_from_list], [query_map], [synthesize] }
# :param in path is substituted from %vars and removed before body
my %ACTION_MAP = (
    # Session
    login          => { method => 'POST',   path => '/session' },
    logout         => { method => 'DELETE',  path => '/session' },
    verify_session => { method => 'GET',     path => '/session' },

    # Zones
    new_zone        => { method => 'POST',   path => '/zone' },
    get_zone        => { method => 'GET',     path => '/zone/:nt_zone_id' },
    edit_zone       => { method => 'PUT',     path => '/zone/:nt_zone_id' },
    delete_zones    => { method => 'DELETE',  path => '/zone/:id',
                         id_from_list => 'zone_list' },
    move_zones      => { method => 'PUT',     path => '/zone/:id',
                         id_from_list => 'zone_list' },
    get_zone_list   => { method => 'GET',     path => '/zone/:id',
                         id_from_list => 'zone_list' },
    get_group_zones => { method => 'GET',     path => '/zone',
                         query_map => { nt_group_id => 'gid',
                                        include_subgroups => 'include_subgroups',
                                        limit => 'limit', start => 'offset',
                                        search_value => 'search',
                                        '1_sortfield' => 'sort_by',
                                        '1_sortmod' => 'sort_dir' } },

    # Zone records
    new_zone_record    => { method => 'POST',   path => '/zone_record' },
    get_zone_record    => { method => 'GET',     path => '/zone_record/:nt_zone_record_id' },
    get_zone_records   => { method => 'GET',     path => '/zone_record',
                            query_map => { nt_zone_id => 'zid',
                                           limit => 'limit', start => 'offset',
                                           search_value => 'search',
                                           '1_sortfield' => 'sort_by',
                                           '1_sortmod' => 'sort_dir' } },
    edit_zone_record   => { method => 'PUT',     path => '/zone_record/:nt_zone_record_id' },
    delete_zone_record => { method => 'DELETE',  path => '/zone_record/:nt_zone_record_id' },
    get_record_type    => { method => 'GET',     path => '/swagger.json',
                            synthesize => 'record_types' },

    # Groups
    new_group        => { method => 'POST',   path => '/group' },
    get_group        => { method => 'GET',     path => '/group/:nt_group_id' },
    edit_group       => { method => 'PUT',     path => '/group/:nt_group_id' },
    delete_group     => { method => 'DELETE',  path => '/group/:nt_group_id' },
    get_group_groups => { method => 'GET',     path => '/group',
                          query_map => { nt_group_id => 'parent_gid' } },
    get_group_branch => { method => 'GET',     path => '/group/:nt_group_id',
                          synthesize => 'group_branch' },
    get_group_subgroups => { method => 'GET',  path => '/group',
                             query_map => { nt_group_id => 'parent_gid',
                                            search_value => 'name',
                                            include_subgroups => 'include_subgroups' } },

    # Users
    new_user        => { method => 'POST',   path => '/user' },
    get_user        => { method => 'GET',     path => '/user/:nt_user_id' },
    edit_user       => { method => 'PUT',     path => '/user/:nt_user_id' },
    delete_users    => { method => 'DELETE',  path => '/user/:id',
                         id_from_list => 'user_list' },
    move_users      => { method => 'PUT',     path => '/user/:id',
                         id_from_list => 'user_list' },
    get_user_list   => { method => 'GET',     path => '/user/:id',
                         id_from_list => 'user_list' },
    get_group_users => { method => 'GET',     path => '/user',
                         query_map => { nt_group_id => 'gid',
                                        include_subgroups => 'include_subgroups',
                                        limit => 'limit', start => 'offset',
                                        search_value => 'search',
                                        exact_match => 'exact_match',
                                        '1_sortfield' => 'sort_by',
                                        '1_sortmod' => 'sort_dir' } },

    # Nameservers
    new_nameserver        => { method => 'POST',   path => '/nameserver' },
    get_nameserver        => { method => 'GET',     path => '/nameserver/:nt_nameserver_id' },
    edit_nameserver       => { method => 'PUT',     path => '/nameserver/:nt_nameserver_id' },
    delete_nameserver     => { method => 'DELETE',  path => '/nameserver/:nt_nameserver_id' },
    move_nameservers      => { method => 'PUT',     path => '/nameserver/:id',
                               id_from_list => 'nameserver_list' },
    get_nameserver_list   => { method => 'GET',     path => '/nameserver/:id',
                               id_from_list => 'nameserver_list' },
    get_group_nameservers => { method => 'GET',     path => '/nameserver',
                               query_map => { nt_group_id => 'gid' } },
    get_usable_nameservers => { method => 'GET',    path => '/nameserver',
                                synthesize => 'usable_nameservers' },
    get_nameserver_export_types => { method => 'GET', path => '/swagger.json',
                                     synthesize => 'nameserver_types' },

    # Audit logs
    get_global_application_log => { method => 'GET', path => '/log/global',
                                    query_map => { nt_group_id => 'gid',
                                                   include_subgroups => 'include_subgroups',
                                                   limit => 'limit', start => 'offset',
                                                   search_value => 'search',
                                                   exact_match => 'exact_match',
                                                   '1_sortfield' => 'sort_by',
                                                   '1_sortmod' => 'sort_dir' } },
    get_user_global_log => { method => 'GET', path => '/log/global',
                             query_map => { nt_group_id => 'gid',
                                            nt_user_id => 'uid',
                                            limit => 'limit', start => 'offset',
                                            search_value => 'search',
                                            exact_match => 'exact_match',
                                            '1_sortfield' => 'sort_by',
                                            '1_sortmod' => 'sort_dir' } },
    get_group_zones_log => { method => 'GET', path => '/log/zone',
                             query_map => { nt_group_id => 'gid',
                                            include_subgroups => 'include_subgroups',
                                            limit => 'limit', start => 'offset',
                                            search_value => 'search',
                                            exact_match => 'exact_match',
                                            '1_sortfield' => 'sort_by',
                                            '1_sortmod' => 'sort_dir' } },
    get_zone_record_log => { method => 'GET', path => '/log/zone_record',
                             query_map => { nt_zone_id => 'zid',
                                            limit => 'limit', start => 'offset',
                                            search_value => 'search',
                                            exact_match => 'exact_match',
                                            '1_sortfield' => 'sort_by',
                                            '1_sortmod' => 'sort_dir' } },
    get_zone_record_log_entry => { method => 'GET', path => '/log/zone_record',
                                   query_map => { nt_zone_id => 'zid',
                                                  nt_zone_record_log_id => 'id' } },

    # Zone delegation
    delegate_zones         => { method => 'POST',   path => '/delegation',
                                id_from_list => 'zone_list' },
    get_delegated_zones    => { method => 'GET',    path => '/delegation',
                                query_map => { nt_group_id => 'gid' } },
    get_zone_delegates     => { method => 'GET',    path => '/delegation',
                                query_map => { nt_zone_id => 'oid' } },
    edit_zone_delegation   => { method => 'PUT',    path => '/delegation' },
    delete_zone_delegation => { method => 'DELETE', path => '/delegation',
                                query_map => { nt_zone_id => 'oid',
                                               nt_group_id => 'gid' } },

    # Zone record delegation
    delegate_zone_records         => { method => 'POST',   path => '/delegation',
                                       id_from_list => 'zonerecord_list' },
    get_delegated_zone_records    => { method => 'GET',    path => '/delegation',
                                       query_map => { nt_group_id => 'gid' } },
    get_zone_record_delegates     => { method => 'GET',    path => '/delegation',
                                       query_map => { nt_zone_record_id => 'oid' } },
    edit_zone_record_delegation   => { method => 'PUT',    path => '/delegation' },
    delete_zone_record_delegation => { method => 'DELETE', path => '/delegation',
                                       query_map => { nt_zone_record_id => 'oid',
                                                      nt_group_id => 'gid' } },
);

# v2 param names -> v3 body/query param names
my %PARAM_V3 = (
    nt_zone_id        => 'zid',
    nt_zone_record_id => 'zrid',
    nt_group_id       => 'gid',
    nt_user_id        => 'uid',
    nt_nameserver_id  => 'nsid',
);

# v3 field -> v2 field, keyed by resource type
my %FIELD_V2 = (
    zone        => { id => 'nt_zone_id',        gid => 'nt_group_id' },
    zone_record => { id => 'nt_zone_record_id', zid => 'nt_zone_id',
                     gid => 'nt_group_id', owner => 'name' },
    user        => { id => 'nt_user_id',         gid => 'nt_group_id' },
    group       => { id => 'nt_group_id', parent_gid => 'parent_group_id' },
    nameserver  => { id => 'nt_nameserver_id',   gid => 'nt_group_id' },
    permission  => { id => 'nt_perm_id' },
    delegation  => {},
);

# action prefix -> v3 resource key in response JSON
my %RESOURCE_FOR = (
    zone        => 'zone',
    zone_record => 'zone_record',
    group       => 'group',
    user        => 'user',
    nameserver  => 'nameserver',
    permission  => 'permission',
    session     => 'session',
    delegation  => 'delegation',
);

# v3 returns RFC field names for zone records; v2 uses generic DB columns
# (address, weight, priority, other, description).  Map them back.
my %ZR_RFC_TO_V2 = (
    CAA   => { value => 'address', flags => 'weight', tag => 'other' },
    CNAME => { cname => 'address' },
    DNAME => { target => 'address' },
    DNSKEY => { publickey => 'address', flags => 'weight',
                protocol => 'priority', algorithm => 'other' },
    DS    => { digest => 'address', 'digest type' => 'weight',
               algorithm => 'priority', 'key tag' => 'other' },
    HINFO => { os => 'address', cpu => 'other' },
    HTTPS => { 'target name' => 'address', params => 'other' },
    KEY   => { publickey => 'address', protocol => 'weight',
               algorithm => 'priority', flags => 'other' },
    MX    => { exchange => 'address', preference => 'weight' },
    NAPTR => { order => 'weight', preference => 'priority',
               replacement => 'description' },
    NS    => { dname => 'address' },
    OPENPGPKEY => { 'public key' => 'address' },
    PTR   => { dname => 'address' },
    SPF   => { data => 'address' },
    SRV   => { target => 'address', port => 'other' },
    SSHFP => { fingerprint => 'address', algorithm => 'weight',
               fptype => 'priority' },
    SVCB  => { 'target name' => 'address', params => 'other' },
    TXT   => { data => 'address' },
    URI   => { target => 'address' },
);

sub _remap_zr_rfc_to_v2 {
    my ($out) = @_;
    my $map = $ZR_RFC_TO_V2{$out->{type}} or return;
    for my $rfc_name (keys %$map) {
        if (exists $out->{$rfc_name}) {
            $out->{$map->{$rfc_name}} = delete $out->{$rfc_name};
        }
    }
    if ($out->{type} eq 'NAPTR') {
        my @parts = map { delete $out->{$_} // '' } qw(flags service regexp);
        $out->{address} = join ' ', map { qq{"$_"} } @parts;
    }
}

sub _unpack_v2_naptr {
    my ($body, $default_replacement) = @_;
    return unless exists $body->{address} || exists $body->{other};

    my $packed = delete $body->{address} // '';
    my @parts;

    if ($packed =~ /^\s*"([^"]*)"\s+"([^"]*)"\s+"([^"]*)"\s*$/) {
        @parts = ($1, $2, $3);
    } elsif ($packed =~ /^'([^']*)','([^']*)','([^']*)'$/) {
        @parts = ($1, $2, $3);
    } else {
        @parts = (delete($body->{other}) // '', '', $packed);
    }

    @{$body}{qw(flags service regexp)} = @parts;
    if (   $default_replacement
        && (!defined $body->{description} || !length $body->{description}) )
    {
        $body->{description} = '.';
    }
    delete $body->{other};
}

# v2 DB columns -> v3 RFC field names, the inverse of %ZR_RFC_TO_V2
my %ZR_V2_TO_RFC = map {
    $_ => { reverse %{ $ZR_RFC_TO_V2{$_} } }
} keys %ZR_RFC_TO_V2;

sub _v2_param_error {
    my ($param, $code) = @_;
    return {
        error_code => $code,
        error_msg  => $param,
        error_desc => $code == 301
            ? 'Required parameters missing'
            : 'Some parameters were invalid',
    };
}

sub _get_json {
    my ($self, $path) = @_;
    my $token = $self->_nt->{_rest_jwt_token};
    my %headers = ('Content-Type' => 'application/json');
    $headers{'Authorization'} = "Bearer $token" if $token;

    my $resp = $self->_http->request('GET', $self->_base_url . $path,
        { headers => \%headers });
    return undef unless $resp->{status} == 200 && $resp->{content};
    return eval { $JSON->decode($resp->{content}) };
}

sub _qualify_owner {
    my ($self, $body) = @_;
    my $zid = $body->{zid} or return;

    my $zone = $self->_get_zone($zid) or return;
    (my $bare = $zone->{zone}) =~ s/\.$//;

    # the v2 sanity layer expanded these shortcuts before storing
    for my $field (qw(owner address)) {
        next unless defined $body->{$field};
        if ($body->{$field} eq '@') {
            $body->{$field} = "$bare.";
        }
        elsif ($body->{$field} =~ s/\.\@$//) {
            $body->{$field} .= ".$bare.";
        }
    }
    $body->{address} =~ s/\.\&$/.in-addr.arpa./ if defined $body->{address};

    return if !defined $body->{owner} || $body->{owner} =~ /\.$/;
    $body->{owner} = $body->{owner} eq '' || $body->{owner} eq $bare
        ? "$bare."
        : "$body->{owner}.$bare.";
}

# v3 hands back the zone's nameserver ids; v2's GUI reads whole rows
sub _expand_zone_nameservers {
    my ($self, $zone) = @_;
    my $ids = $zone->{nameservers};
    return unless ref $ids eq 'ARRAY';

    my @rows;
    for my $nsid (@$ids) {
        my $data = $self->{nameservers_by_id}{$nsid}
            //= $self->_get_json("/nameserver/$nsid");
        my $ns = $data && $data->{nameserver} && $data->{nameserver}[0] or next;
        my $row = _remap_fields($ns, 'nameserver');
        $row->{deleted} //= 0;
        push @rows, $row;
    }
    $zone->{nameservers} = \@rows;
}

# zone id -> { zone, gid }, cached for the life of the transport
sub _get_zone {
    my ($self, $zid) = @_;
    return undef unless $zid && $zid =~ /^\d+$/;

    $self->{zones_by_zid} //= {};
    if (!exists $self->{zones_by_zid}{$zid}) {
        my $data = $self->_get_json("/zone/$zid");
        return undef unless $data && $data->{zone} && $data->{zone}[0];
        my $z = $data->{zone}[0];
        $self->{zones_by_zid}{$zid}
            = { zone => $z->{zone}, gid => $z->{gid} };
    }
    return $self->{zones_by_zid}{$zid};
}

# v2 kept record owners relative to their zone ('a' for 'a.zone.com.');
# v3 stores them fully qualified, so strip the known zone suffix back off
sub _unqualify_owner {
    my ($self, $entity) = @_;
    return unless $entity && ref $entity eq 'HASH';
    my $owner = $entity->{name};
    return unless defined $owner && $owner =~ /\.$/;

    # _remap_fields has already renamed zid -> nt_zone_id
    my $zone = $self->_get_zone( $entity->{nt_zone_id} ) or return;
    (my $bare = $zone->{zone}) =~ s/\.$//;
    return unless $bare;

    if ($owner eq "$bare.") {
        $entity->{name} = '';
    }
    else {
        $entity->{name} =~ s/\.\Q$bare\E\.$//;
    }
}

# owning group id of a delegated object (zone, or the zone under a record)
sub _delegation_object_gid {
    my ($self, $action, $oid) = @_;
    if ( $action =~ /zone_record/ ) {
        my $data = $self->_get_json("/zone_record/$oid");
        return undef unless $data && $data->{zone_record} && $data->{zone_record}[0];
        my $zone = $self->_get_zone( $data->{zone_record}[0]{zid} );
        return undef unless $zone;
        return $zone->{gid};
    }
    my $zone = $self->_get_zone($oid);
    return undef unless $zone;
    return $zone->{gid};
}

sub _get_group_branch {
    my ($self, $target_gid) = @_;
    return _v2_param_error( 'nt_group_id', 301 )
        unless defined $target_gid && length $target_gid;
    return _v2_param_error( 'nt_group_id', 302 )
        unless $target_gid =~ /^\d+$/ && $target_gid > 0;

    my $session = $self->_get_json('/session');
    my $user_gid = $session && $session->{group} ? $session->{group}{id} : undef;
    return _http_error( 401, {} ) unless $user_gid;

    my @groups;
    my %seen;
    my $gid = $target_gid;
    while ($gid && !$seen{$gid}++) {
        my $data = $self->_get_json("/group/$gid");
        my $rows = $data ? $data->{group} : undef;
        return _http_error( 404, { error => 'Group not found' } )
            unless ref $rows eq 'ARRAY' && @$rows;

        my $group = _remap_fields( $rows->[0], 'group' );
        $self->_set_group_has_children($group);
        unshift @groups, $group;
        last if $gid == $user_gid;
        $gid = $group->{parent_group_id};
    }

    return _http_error( 403, { error => 'Group is outside the user branch' } )
        unless @groups && $groups[0]{nt_group_id} == $user_gid;
    return { error_code => 200, error_msg => 'OK', groups => \@groups };
}

sub _get_usable_nameservers {
    my ($self, $target_gid) = @_;

    my $session = $self->_get_json('/session');
    return _http_error( 401, {} ) unless $session && $session->{group}{id};
    $target_gid ||= $session->{group}{id};

    my $branch = $self->_get_group_branch($target_gid);
    return $branch if $branch->{error_code} != 200;

    my @raw;
    my %seen;
    for my $group (@{ $branch->{groups} }) {
        my $data = $self->_get_json('/nameserver?gid=' . $group->{nt_group_id});
        for my $ns (@{ $data->{nameserver} // [] }) {
            push @raw, $ns unless $seen{ $ns->{id} }++;
        }
    }

    my $usable = $session->{permissions}{nameserver}{usable} // [];
    for my $nsid (@$usable) {
        next if $seen{$nsid}++;
        my $data = $self->_get_json("/nameserver/$nsid");
        push @raw, @{ $data->{nameserver} // [] };
    }

    return $self->_adapt_response('get_usable_nameservers', { nameserver => \@raw });
}

# which zone kinds each record type applies to, as the v2 GUI menus had it
# (server/sql/06_resource_records.sql); v3 types it never knew get both
my %RR_TYPE_ZONES = (
    A     => [ 1, 1 ], NS    => [ 1, 1 ], CNAME => [ 1, 1 ], SOA   => [ 0, 0 ],
    PTR   => [ 1, 1 ], HINFO => [ 0, 0 ], MX    => [ 1, 0 ], TXT   => [ 1, 1 ],
    SIG   => [ 0, 0 ], KEY   => [ 0, 0 ], AAAA  => [ 1, 0 ], LOC   => [ 1, 0 ],
    NXT   => [ 0, 0 ], SRV   => [ 1, 0 ], NAPTR => [ 1, 1 ], DNAME => [ 0, 0 ],
    DS    => [ 1, 1 ], SSHFP => [ 1, 0 ], RRSIG => [ 1, 0 ], NSEC  => [ 1, 0 ],
    DNSKEY => [ 1, 0 ], NSEC3 => [ 0, 0 ], NSEC3PARAM => [ 0, 0 ], SPF => [ 0, 0 ],
    TSIG  => [ 0, 0 ], AXFR  => [ 0, 0 ], URI   => [ 1, 0 ], CAA   => [ 1, 0 ],
);

sub _get_api_types {
    my ($self, $kind, $lookup) = @_;
    my ($path, $field) = $kind eq 'record_types'
        ? ('/zone_record', 'type')
        : ('/nameserver', 'type');
    my $swagger = $self->_get_json('/swagger.json');
    my $enum = _swagger_enum( $swagger, $path, 'post', $field );
    return _http_error( 502, { error => 'API schema has no type choices' } )
        unless @$enum;

    my @types;
    my $id = 0;
    for my $name (@$enum) {
        my $type = {
            id          => ++$id,
            name        => $name,
            description => $name,
            descr       => $name,
            url         => '',
        };
        if ($kind eq 'record_types') {
            my $zones = $RR_TYPE_ZONES{$name} // [ 1, 1 ];
            $type->{forward} = $zones->[0];
            $type->{reverse} = $zones->[1];
        }
        push @types, $type;
    }

    return { error_code => 200, error_msg => 'OK', types => \@types }
        if $lookup eq 'ALL';
    return $types[$lookup - 1]{name}
        if defined $lookup && $lookup =~ /^\d+$/ && $lookup > 0 && $lookup <= @types;
    for my $type (@types) {
        return $type->{id} if defined $lookup && $type->{name} eq $lookup;
    }
    return undef;
}

sub _swagger_enum {
    my ($swagger, $path, $method, $field) = @_;
    return [] unless ref $swagger eq 'HASH';
    my $params = $swagger->{paths}{$path}{$method}{parameters};
    return [] unless ref $params eq 'ARRAY';
    my ($body) = grep { ($_->{in} // '') eq 'body' } @$params;
    return [] unless $body;

    my $schema = _swagger_resolve( $swagger, $body->{schema} );
    return [] unless $schema && ref $schema->{properties} eq 'HASH';
    my $property = _swagger_resolve( $swagger, $schema->{properties}{$field} );
    return ref $property->{enum} eq 'ARRAY' ? $property->{enum} : [];
}

sub _swagger_resolve {
    my ($swagger, $node) = @_;
    while (ref $node eq 'HASH' && $node->{'$ref'}) {
        my $ref = $node->{'$ref'};
        return undef unless $ref =~ m{^#/definitions/([^/]+)$};
        $node = $swagger->{definitions}{$1};
    }
    return $node;
}

sub _set_group_has_children {
    my ($self, $group) = @_;
    return if exists $group->{has_children};
    my $gid = $group->{nt_group_id} or return;
    my $data = $self->_get_json("/group?parent_gid=$gid");
    $group->{has_children} = @{ $data->{group} // [] } ? 1 : 0;
}

sub _http {
    my ($self) = @_;
    my $agent = 'NicTool-REST';
    $agent .= "/$NicTool::VERSION"
        if defined $NicTool::VERSION && length $NicTool::VERSION;
    return $self->{http} ||= HTTP::Tiny->new(
        agent   => $agent,
        timeout => 30,
    );
}

sub _uri_escape {
    my ($value) = @_;
    $value = "$value";
    $value =~ s/([^A-Za-z0-9\-._~])/sprintf '%%%02X', ord $1/ge;
    return $value;
}


sub send_request {
    my ($self, $url, %vars) = @_;

    my $action = delete $vars{action};
    delete $vars{nt_user_session};
    delete $vars{nt_protocol_version};
    $self->{base_url} = $url;
    $self->{request_group_id} = $vars{nt_group_id};
    delete $self->{record_delegated_zids};

    my $spec = $ACTION_MAP{$action};
    return _not_implemented($action) unless $spec;

    if ( ($spec->{synthesize} // '') eq 'group_branch' ) {
        return $self->_get_group_branch( $vars{nt_group_id} );
    }
    if ( ($spec->{synthesize} // '') eq 'usable_nameservers' ) {
        return $self->_get_usable_nameservers( $vars{nt_group_id} );
    }
    if ( ($spec->{synthesize} // '') =~ /^(?:record|nameserver)_types$/ ) {
        return $self->_get_api_types( $spec->{synthesize}, $vars{type} );
    }

    my $http_method = $spec->{method};
    my $path        = $spec->{path};

    if ($action eq 'get_zone_record_log_entry') {
        my $zrid = delete $vars{nt_zone_record_id};
        return _v2_param_error('nt_zone_record_id', 301)
            unless defined $zrid && length $zrid;
        return _v2_param_error('nt_zone_record_id', 302)
            unless $zrid =~ /^\d+$/ && $zrid > 0;
        my $record = $self->_get_json("/zone_record/$zrid");
        return _http_error(404, { error => 'No such zone record exists' })
            unless $record && $record->{zone_record} && $record->{zone_record}[0];
        $vars{nt_zone_id} = $record->{zone_record}[0]{zid};
    }

    # id_from_list actions take an arrayref or a comma-separated list; the
    # v2 server answered 301 for an empty list and 302 for a bad entry
    my @ids;
    if ($spec->{id_from_list}) {
        my $list_raw = delete $vars{$spec->{id_from_list}} // '';
        my @vals = ref $list_raw eq 'ARRAY' ? @$list_raw : split /,/, $list_raw;
        return _v2_param_error( $spec->{id_from_list}, 301 )
            if !@vals || grep { !defined || $_ eq '' } @vals;
        return _v2_param_error( $spec->{id_from_list}, 302 )
            if grep { !/^\d+$/ || $_ == 0 } @vals;
        @ids = @vals;
    }

    # every action parameter is checked before anything is dispatched,
    # however many ids the list carried
    if ( $action =~ /^move_/ ) {
        my $gid = $vars{nt_group_id};
        return _v2_param_error( 'nt_group_id', 301 ) if !defined $gid || $gid eq '';
        return _v2_param_error( 'nt_group_id', 302 ) if $gid !~ /^\d+$/ || $gid == 0;
    }

    # delegation calls: reject missing/invalid object and group ids
    # with the error codes the v2 client expects
    if ( $action =~ /delegat/ ) {
        my $id_param = $action =~ /zone_record/ ? 'nt_zone_record_id' : 'nt_zone_id';
        my @oids = @ids ? @ids : ( $vars{$id_param} );

        if ( $action !~ /^get_delegated_/ ) {
            for my $oid (@oids) {
                return _v2_param_error( $id_param, 301 ) if !defined $oid || $oid eq '';
                return _v2_param_error( $id_param, 302 ) if $oid !~ /^\d+$/ || $oid == 0;
            }
        }

        my $gid = $vars{nt_group_id};
        if ( $action =~ /^get_delegated_/ || $http_method ne 'GET' ) {
            return _v2_param_error( 'nt_group_id', 301 ) if !defined $gid || $gid eq '';
            return _v2_param_error( 'nt_group_id', 302 ) if $gid !~ /^\d+$/ || $gid == 0;
        }

        # delegating an object to the group that already owns it is a no-op
        # the v2 server rejected as a sanity error
        if ( $http_method eq 'POST' ) {
            for my $oid (@oids) {
                my $obj_gid = $self->_delegation_object_gid( $action, $oid ) or next;
                if ( $obj_gid == $gid ) {
                    return {
                        error_code => 300,
                        error_msg  => 'Cannot delegate to your own group.',
                        error_desc => 'Sanity error',
                    };
                }
            }
        }
    }

    if (@ids > 1) {
        if ($http_method eq 'GET') {
            return $self->_multi_get($action, $spec, \@ids);
        }
        if ($http_method eq 'POST') {
            return $self->_multi_create($url, $action, $spec, \@ids, %vars);
        }
        if ($http_method eq 'PUT') {
            return $self->_multi_put($url, $spec, \@ids, %vars);
        }
        return $self->_multi_delete($url, $spec, \@ids, %vars);
    }
    $vars{id} = $ids[0] if @ids;

    # Substitute :param placeholders in path; v3 treats an empty segment as
    # the collection, so a missing or bad id must stop here
    for my $key ( $path =~ /:(\w+)/g ) {
        my $val   = delete $vars{$key};
        my $param = $key eq 'id' ? $spec->{id_from_list} // $key : $key;
        return _v2_param_error( $param, 301 ) if !defined $val || $val eq '';
        return _v2_param_error( $param, 302 ) if $val !~ /^\d+$/ || $val == 0;
        $path =~ s/:\Q$key\E(?!\w)/$val/;
    }

    # Build query string for GET requests
    my $query = '';
    if ($spec->{query_map}) {
        my @qparts;
        for my $v2key (sort keys %{$spec->{query_map}}) {
            my $v3key = $spec->{query_map}{$v2key};
            my $val = delete $vars{$v2key};
            next unless defined $val && length $val;
            $val = $val > 0 ? $val - 1 : 0 if $v3key eq 'offset';
            if ($v3key eq 'sort_dir') {
                $val = lc $val;
                $val = 'asc'  if $val eq 'ascending';
                $val = 'desc' if $val eq 'descending';
            }
            if ($v3key eq 'sort_by') {
                $val = 'owner'
                    if $action =~ /^get_zone_record(?:s|_log)$/ && $val eq 'name';
                # v3 zone listings cannot sort by the owning group
                next if $action eq 'get_group_zones' && $val eq 'group_name';
            }
            $val = $val ? 'true' : 'false'
                if $v3key eq 'include_subgroups' || $v3key eq 'exact_match';
            push @qparts, _uri_escape($v3key) . '=' . _uri_escape($val);
        }
        $query = '?' . join('&', @qparts) if @qparts;
    }

    # Translate remaining v2 param names to v3
    my %body;
    for my $key (keys %vars) {
        my $v3key = $PARAM_V3{$key} // $key;
        $body{$v3key} = $vars{$key};
    }
    delete $body{$_} for grep { !defined $body{$_} } keys %body;

    # new_group: v2 sends nt_group_id as parent, v3 wants parent_gid
    if ($action eq 'new_group' && exists $body{gid}) {
        $body{parent_gid} = delete $body{gid};
    }

    if ($action =~ /^(?:new|edit)_zone$/) {
        delete $body{template};

        # v2 sends the selection as a comma list of ids; an empty list clears it
        if (exists $body{nameservers}) {
            my $value = delete $body{nameservers};
            my @ids = ref $value eq 'ARRAY' ? @$value : split /,/, $value // '';
            return _v2_param_error( 'nameservers', 302 )
                if grep { !defined || !/^\d+$/ || $_ == 0 } @ids;
            my %seen;
            $body{nameservers} = [ grep { !$seen{$_}++ } map { $_ + 0 } @ids ];
        }
    }

    if ($action eq 'new_zone') {
        $body{serial} = 0
            unless defined $body{serial} && $body{serial} =~ /^\d+$/;
    }
    delete $body{zone} if $action eq 'edit_zone';

    # edit forms carry the browsed group; moves go through move_*
    delete $body{gid} if $action =~ /^edit_(?:zone|user)$/;

    # zone_record: v2 uses 'name', v3 uses 'owner'
    if ($action =~ /zone_record/ && exists $body{name}) {
        $body{owner} = delete $body{name};
    }
    delete $body{gid} if $action =~ /^(?:new|edit)_zone_record$/;

    # zone_record: qualify relative owners against their zone, like the v2
    # server did; v3's RR parser rejects them
    if (   $action =~ /^(?:new|edit)_zone_record$/
        && (   ( defined $body{owner} && $body{owner} !~ /\.$/ )
            || ( defined $body{address} && $body{address} =~ /(?:^|\.)[\@\&]$/ ) ) )
    {
        if ($action eq 'edit_zone_record' && !$body{zid} && $path =~ m{/zone_record/(\d+)$}) {
            my $data = $self->_get_json("/zone_record/$1");
            if ($data && $data->{zone_record} && $data->{zone_record}[0]) {
                $body{zid} = $data->{zone_record}[0]{zid};
            }
        }
        $self->_qualify_owner( \%body );
    }

    # zone_record: v2 generic DB columns -> v3 RFC field names
    # (A/TXT/etc. use 'address' in both; only mapped types change)
    if ($action =~ /^(?:new|edit)_zone_record$/ && $body{type}) {
        if ($body{type} eq 'SSHFP') {
            $body{priority} = $body{other}
                if !exists $body{priority} && exists $body{other};
            delete $body{other};
        }
        _unpack_v2_naptr(\%body, $action eq 'new_zone_record')
            if $body{type} eq 'NAPTR';

        my $map = $ZR_V2_TO_RFC{ $body{type} };
        if ($map) {
            for my $v2col (keys %$map) {
                $body{ $map->{$v2col} } = delete $body{$v2col}
                    if exists $body{$v2col};
            }
        }
    }

    # user: v2 sends password2 (confirmation), v3 doesn't use it
    delete $body{password2};

    # nameserver: v2 calls it export_format, v3 wants a flat type
    if ($action =~ /nameserver/ && exists $body{export_format}) {
        $body{type} = delete $body{export_format};
    }

    if ($action =~ /^(?:new|edit)_nameserver$/) {
        delete $body{gid} if $action eq 'edit_nameserver';
        my %export;
        if (exists $body{export_interval}) {
            my $value = delete $body{export_interval};
            $export{interval} = $value + 0 if length $value;
        }
        if (exists $body{export_serials}) {
            my $value = delete $body{export_serials};
            $export{serials} = $value ? \1 : \0 if length $value;
        }
        $body{export} = \%export if %export;
    }

    # nameserver: v3 requires ttl, v2 doesn't always send it
    if ($action eq 'new_nameserver' && !exists $body{ttl}) {
        $body{ttl} = 86400;
    }

    # v2 sends usable_nameservers, v3 uses usable_ns (array of ints)
    if (exists $body{usable_nameservers}) {
        my $val = delete $body{usable_nameservers};
        if (ref $val eq 'ARRAY') {
            $body{usable_ns} = [ map { $_ + 0 } @$val ];
        } elsif (!ref $val && length($val)) {
            $body{usable_ns} = [ map { $_ + 0 } split(/,/, $val) ];
        } else {
            $body{usable_ns} = [];
        }
    }

    # v2 sends booleans as 0/1 integers; v3 Joi expects real booleans
    for my $bkey (qw(
        inherit_group_permissions is_admin deleted
        group_write group_create group_delete
        zone_write zone_create zone_delegate zone_delete
        zonerecord_write zonerecord_create zonerecord_delegate zonerecord_delete
        user_write user_create user_delete
        nameserver_write nameserver_create nameserver_delete self_write
    )) {
        $body{$bkey} = $body{$bkey} ? \1 : \0 if exists $body{$bkey};
    }

    if ($action eq 'edit_zone' && defined $body{serial}) {
        $body{serial} = _increment_serial($body{serial});
    }

    # delegation: inject object type and remap object ID param
    if ($action =~ /delegat/) {
        my $dtype = _delegation_type($action);

        # v2 uses nt_zone_id (-> zid via PARAM_V3), but v3 delegation wants 'oid'
        # Also handle 'id' set by id_from_list extraction
        for my $old_key (qw(zid zrid nsid id)) {
            if (exists $body{$old_key}) {
                $body{oid} = delete $body{$old_key};
                last;
            }
        }

        # Coerce delegation perm fields from 0/1 to JSON booleans
        for my $pkey (qw(perm_write perm_delete perm_delegate
                         zone_perm_add_records zone_perm_delete_records)) {
            $body{$pkey} = $body{$pkey} ? \1 : \0 if exists $body{$pkey};
        }

        if ($http_method =~ /^(?:POST|PUT)$/) {
            $body{type} = $dtype;
        }
        else {
            $query .= ($query ? '&' : '?') . "type=$dtype";
        }
    }

    # Build request
    my $full_url = $url . $path . $query;
    my $token = $self->_nt->{_rest_jwt_token};

    my %headers = ('Content-Type' => 'application/json');
    $headers{'Authorization'} = "Bearer $token" if $token;

    my %opts = (headers => \%headers);
    if ($http_method =~ /^(?:POST|PUT)$/ && %body) {
        $opts{content} = $JSON->encode(\%body);
    }

    my $resp = $self->_http->request($http_method, $full_url, \%opts);

    # Decode response
    my $data = {};
    if ($resp->{content} && length $resp->{content}) {
        eval { $data = $JSON->decode($resp->{content}) };
        if ($@) {
            return {
                error_code => 508,
                error_msg  => "REST: JSON parse error: $@",
            };
        }
    }

    # HTTP errors
    if ($resp->{status} >= 400) {
        return _http_error($resp->{status}, $data);
    }

    if (
        $action =~ /^get_(?:zone|zone_record|group|user|nameserver)$/
        && $path =~ m{/\d+$}
    ) {
        my $resource = _resource_for_action($action);
        my $rkey = $RESOURCE_FOR{$resource} // $resource;
        my $entities = $data->{$rkey};
        if (!$entities || (ref $entities eq 'ARRAY' && !@$entities)) {
            my $retry_url = $full_url . ($full_url =~ /\?/ ? '&' : '?') . 'deleted=true';
            my $retry = $self->{http}->request('GET', $retry_url,
                { headers => \%headers });
            if ($retry->{status} < 400 && $retry->{content}) {
                my $retry_data = eval { $JSON->decode($retry->{content}) };
                $data = $retry_data if $retry_data;
            }
        }
    }

    return $self->_adapt_response($action, $data);
}

sub _increment_serial {
    my ($serial) = @_;
    return ++$serial if length($serial) < 10 || $serial <= 1970000000;
    return 1 if $serial + 1 >= 2**32;
    return ++$serial unless $serial =~ /^(\d{4})(\d{2})(\d{2})(\d{2})$/;

    my $serial_date = "$1$2$3";
    my @now = localtime;
    my $today = sprintf '%04d%02d%02d', $now[5] + 1900, $now[4] + 1, $now[3];
    return $today . '00' if $serial_date < $today;
    return ++$serial;
}

sub _multi_get {
    my ($self, $action, $spec, $ids) = @_;

    my $resource = _resource_for_action($action);
    my $rkey = $RESOURCE_FOR{$resource} // $resource;
    my @entities;

    for my $id (@$ids) {
        my $path = $spec->{path};
        $path =~ s{:id}{$id}g;
        my $data = $self->_get_json($path);
        next unless $data && ref $data->{$rkey} eq 'ARRAY';
        if ($resource eq 'user' && ref $data->{group} eq 'HASH') {
            $_->{gid} //= $data->{group}{id} for @{ $data->{$rkey} };
        }
        push @entities, @{ $data->{$rkey} };
    }

    return $self->_adapt_response($action, { $rkey => \@entities });
}

sub _multi_delete {
    my ($self, $url, $spec, $ids, %vars) = @_;

    for my $id (@$ids) {
        my %call_vars = (%vars, id => $id);
        my $path = $spec->{path};
        $path =~ s{:id}{$id}g;

        my $full_url = $url . $path;
        my $token = $self->_nt->{_rest_jwt_token};

        my %headers = ('Content-Type' => 'application/json');
        $headers{'Authorization'} = "Bearer $token" if $token;

        my $resp = $self->_http->request('DELETE', $full_url,
            { headers => \%headers });

        if ($resp->{status} >= 400) {
            my $data = {};
            if ($resp->{content} && length $resp->{content}) {
                eval { $data = $JSON->decode($resp->{content}) };
            }
            return _http_error($resp->{status}, $data);
        }
    }

    return { error_code => 200, error_msg => 'OK' };
}

sub _multi_put {
    my ($self, $url, $spec, $ids, %vars) = @_;

    my %body;
    for my $key (keys %vars) {
        my $v3key = $PARAM_V3{$key} // $key;
        $body{$v3key} = $vars{$key};
    }
    delete $body{$_} for grep { !defined $body{$_} } keys %body;

    my $token = $self->_nt->{_rest_jwt_token};
    my %headers = ('Content-Type' => 'application/json');
    $headers{'Authorization'} = "Bearer $token" if $token;

    for my $id (@$ids) {
        my $path = $spec->{path};
        $path =~ s{:id}{$id}g;

        my $resp = $self->_http->request('PUT', $url . $path, {
            headers => \%headers,
            content => $JSON->encode(\%body),
        });

        if ($resp->{status} >= 400) {
            my $data = {};
            if ($resp->{content} && length $resp->{content}) {
                eval { $data = $JSON->decode($resp->{content}) };
            }
            return _http_error($resp->{status}, $data);
        }
    }

    return { error_code => 200, error_msg => 'OK' };
}

sub _multi_create {
    my ($self, $url, $action, $spec, $ids, %vars) = @_;

    my $dtype = _delegation_type($action);

    # Translate v2 param names to v3
    my %body;
    for my $key (keys %vars) {
        my $v3key = $PARAM_V3{$key} // $key;
        $body{$v3key} = $vars{$key};
    }
    $body{type} = $dtype;

    # Coerce delegation perm fields from 0/1 to JSON booleans
    for my $pkey (qw(perm_write perm_delete perm_delegate
                     zone_perm_add_records zone_perm_delete_records)) {
        $body{$pkey} = $body{$pkey} ? \1 : \0 if exists $body{$pkey};
    }

    my $path  = $spec->{path};
    my $token = $self->_nt->{_rest_jwt_token};

    for my $id (@$ids) {
        $body{oid} = $id;

        my %headers = ('Content-Type' => 'application/json');
        $headers{'Authorization'} = "Bearer $token" if $token;

        my $resp = $self->_http->request('POST', $url . $path,
            { headers => \%headers, content => $JSON->encode(\%body) });

        if ($resp->{status} >= 400) {
            my $data = {};
            if ($resp->{content} && length $resp->{content}) {
                eval { $data = $JSON->decode($resp->{content}) };
            }
            return _http_error($resp->{status}, $data);
        }
    }

    return { error_code => 200, error_msg => 'OK' };
}

sub _delegation_type {
    my ($action) = @_;
    return 'ZONERECORD' if $action =~ /zone_record/;
    return 'NAMESERVER' if $action =~ /nameserver/;
    return 'GROUP'      if $action =~ /group/;
    return 'ZONE';
}

# v2 client reads lists from a per-action key (NicTool::API
# result-list-param); mirror the response under that name too
my %LIST_PARAM = (
    get_group_groups             => 'groups',
    get_group_branch             => 'groups',
    get_group_subgroups          => 'groups',
    get_group_zones              => 'zones',
    get_zone_list                => 'zones',
    get_zone_records             => 'records',
    get_usable_nameservers       => 'nameservers',
    get_user_list                => 'list',
    get_nameserver_list          => 'list',
    get_nameserver_export_types  => 'types',
    get_delegated_zones          => 'ZONE',
    get_delegated_zone_records   => 'ZONERECORD',
    get_zone_delegates           => 'delegates',
    get_zone_record_delegates    => 'delegates',
);

sub _adapt_response {
    my ($self, $action, $data) = @_;

    # Login: extract JWT, flatten user/group/session
    if ($action eq 'login') {
        return $self->_adapt_login($data);
    }

    if ($action eq 'verify_session') {
        return $self->_adapt_session($data);
    }

    if ($action eq 'logout') {
        $self->_nt->{_rest_jwt_token} = undef;
        return { error_code => 200, error_msg => 'OK' };
    }

    if ($action =~ /^(?:get_global_application_log|get_user_global_log|get_group_zones_log|get_zone_record_log|get_zone_record_log_entry)$/) {
        return _adapt_log_response($action, $data);
    }

    # Determine resource type from action
    my $resource = _resource_for_action($action);
    my $rkey     = $RESOURCE_FOR{$resource} // $resource;

    my $result = { error_code => 200, error_msg => 'OK' };
    my $is_list = _is_list_action($action);
    my $is_create = ($action =~ /^new_/);

    if ($is_list) {
        $result->{list} = [];
        my $list_param = $LIST_PARAM{$action};
        $result->{$list_param} = [] if $list_param;
        $result->{total} = 0;
    }

    my $entity_data = $data->{$rkey};

    # v3 group endpoints return a single object for single-entity routes,
    # zone/user/nameserver return arrays -- normalize to array
    if (ref $entity_data eq 'HASH') {
        $entity_data = [$entity_data];
    }

    if (!$entity_data || ref $entity_data ne 'ARRAY') {
        return $result;
    }

    if ($is_list) {
        my @remapped = map {
            my $r = _remap_fields($_, $resource);
            if ($resource eq 'user') {
                # the effective perm rides on the user's own group, so it names
                # the member's real group even in include_subgroups listings
                my $perm_gid
                    = ref $r->{permissions} eq 'HASH'
                    ? $r->{permissions}{group}{id}
                    : undef;
                $r->{nt_group_id}
                    //= defined $perm_gid && length $perm_gid ? $perm_gid
                    : $self->{request_group_id};
            }
            $self->_set_group_has_children($r) if $resource eq 'group';
            $r->{deleted} //= 0
                if $resource =~ /^(?:zone|zone_record|group|user|nameserver)$/;
            $self->_unqualify_owner($r) if $resource eq 'zone_record';
            $self->_supplement_delegation($r, 'get_zone')
                if $action eq 'get_group_zones';
            if ($action =~ /^get_delegated_(?:zones|zone_records)$/) {
                my $oid = $action eq 'get_delegated_zones'
                    ? $r->{nt_zone_id}
                    : $r->{nt_zone_record_id};
                my $gid = $self->_delegation_object_gid($action, $oid);
                $r->{nt_group_id} = $gid if $gid;
            }
            _flatten_permissions($r);
            $r;
        } @$entity_data;
        $result->{list} = \@remapped;
        my $list_param = $LIST_PARAM{$action};
        $result->{$list_param} = \@remapped if $list_param;
        if (my $pg = $data->{meta}{pagination}) {
            $result->{total}  = $pg->{filtered} // $pg->{total} // 0;
            $result->{start}  = ($pg->{offset} // 0) + 1;
            $result->{end}    = $result->{start} + scalar(@remapped) - 1;
            my $limit = $pg->{limit} || scalar(@remapped) || 1;
            $result->{page} = int(($pg->{offset} // 0) / $limit) + 1;
        }
        else {
            $result->{total} = scalar @remapped;
        }
    }
    elsif ($is_create) {
        my $entity = _remap_fields($entity_data->[0], $resource);
        my $id_field = $FIELD_V2{$resource}{id} // 'id';
        $result->{$id_field} = $entity->{$id_field};
    }
    else {
        # Single-entity GET/PUT/DELETE
        my $entity = _remap_fields($entity_data->[0], $resource);
        $self->_set_group_has_children($entity) if $resource eq 'group';
        $entity->{deleted} //= 0
            if $resource =~ /^(?:zone|zone_record|group|user|nameserver)$/;
        $self->_unqualify_owner($entity) if $resource eq 'zone_record';
        $self->_expand_zone_nameservers($entity) if $resource eq 'zone';
        %$result = (%$result, %$entity);
    }

    # Include group info if present (user routes return it)
    if ($data->{group} && ref $data->{group} eq 'HASH') {
        $result->{nt_group_id} //= $data->{group}{id};
    }

    # Include permissions if present (user/session routes return them)
    if ($data->{permissions} && ref $data->{permissions} eq 'HASH') {
        $result->{permissions} = $data->{permissions};
    }

    # Flatten nested permissions into v2 flat keys
    _flatten_permissions($result);

    # For single-entity zone/zone_record GETs, fetch delegation permissions
    if ($action =~ /^get_zone(?:_record)?$/ && !$is_list && !$is_create) {
        $self->_supplement_delegation($result, $action);
    }

    return $result;
}

sub _adapt_log_response {
    my ($action, $data) = @_;

    my %field_map = (
        get_global_application_log => {
            id  => 'nt_user_global_log_id',
            gid => 'nt_group_id',
            uid => 'nt_user_id',
        },
        get_user_global_log => {
            id  => 'nt_user_global_log_id',
            gid => 'nt_group_id',
            uid => 'nt_user_id',
        },
        get_group_zones_log => {
            id  => 'nt_zone_log_id',
            gid => 'nt_group_id',
            uid => 'nt_user_id',
            zid => 'nt_zone_id',
        },
        get_zone_record_log => {
            id    => 'nt_zone_record_log_id',
            uid   => 'nt_user_id',
            zid   => 'nt_zone_id',
            zrid  => 'nt_zone_record_id',
            owner => 'name',
        },
        get_zone_record_log_entry => {
            id    => 'nt_zone_record_log_id',
            uid   => 'nt_user_id',
            zid   => 'nt_zone_id',
            zrid  => 'nt_zone_record_id',
            owner => 'name',
        },
    );

    my @log;
    for my $entry (@{ $data->{log} // [] }) {
        my %row = %$entry;
        for my $v3key (keys %{ $field_map{$action} }) {
            next unless exists $row{$v3key};
            $row{ $field_map{$action}{$v3key} } = delete $row{$v3key};
        }
        push @log, \%row;
    }

    my $pg = $data->{meta}{pagination} // {};
    my $start = ($pg->{offset} // 0) + 1;
    my $limit = $pg->{limit} || scalar(@log) || 1;
    my $result = {
        error_code => 200,
        error_msg  => 'OK',
        log        => \@log,
        group_map  => {},
        total      => $pg->{filtered} // $pg->{total} // scalar(@log),
        start      => $start,
        end        => $start + scalar(@log) - 1,
        limit      => $limit,
        page       => int(($pg->{offset} // 0) / $limit) + 1,
    };
    $result->{list} = $result->{log} if $action eq 'get_user_global_log';
    return {
        error_code => 600,
        error_msg  => 'No such log entry exists',
    } if $action eq 'get_zone_record_log_entry' && !@log;
    return { error_code => 200, error_msg => 'OK', %{ $log[0] } }
        if $action eq 'get_zone_record_log_entry';
    return $result;
}

sub _adapt_login {
    my ($self, $data) = @_;

    my $token = $data->{session}{token};
    unless ($token) {
        return {
            error_code => 401,
            error_msg  => $data->{err}
                // $data->{meta}{msg}
                // 'REST: login failed - no token',
        };
    }

    $self->_nt->{_rest_jwt_token} = $token;

    my $user  = $data->{user}  // {};
    my $group = $data->{group} // {};

    my $result = {
        error_code      => 200,
        error_msg       => 'OK',
        nt_user_session => $token,
        nt_user_id      => $user->{id},
        nt_group_id     => $group->{id},
        username        => $user->{username},
        first_name      => $user->{first_name},
        last_name       => $user->{last_name},
        email           => $user->{email},
    };

    if ($data->{permissions}) {
        $result->{permissions} = $data->{permissions};
        _flatten_permissions($result);
    }

    return $result;
}

sub _adapt_session {
    my ($self, $data) = @_;

    my $user  = $data->{user}  // {};
    my $group = $data->{group} // {};
    my $sess  = $data->{session} // {};

    my $result = {
        error_code      => 200,
        error_msg       => 'OK',
        nt_user_session => $self->_nt->{_rest_jwt_token},
        nt_user_id      => $user->{id},
        nt_group_id     => $group->{id},
        username        => $user->{username},
        first_name      => $user->{first_name},
        last_name       => $user->{last_name},
        email           => $user->{email},
    };

    # Include permissions in session response (v2 verify_session returns them)
    if ($data->{permissions}) {
        $result->{permissions} = $data->{permissions};
        _flatten_permissions($result);
    }

    return $result;
}

sub _supplement_delegation {
    my ($self, $result, $action) = @_;

    my $gid = $self->_session_group_id;
    return unless $gid;

    my $oid;
    my $type;
    if ($action eq 'get_zone') {
        $oid  = $result->{nt_zone_id};
        $type = 'ZONE';
    } elsif ($action eq 'get_zone_record') {
        $oid  = $result->{nt_zone_record_id};
        $type = 'ZONERECORD';
    }
    return unless $oid;

    my $url   = $self->_base_url;
    my $token = $self->_nt->{_rest_jwt_token};
    my $resp = $self->_http->request('GET',
        "$url/delegation?oid=$oid&gid=$gid&type=$type",
        { headers => {
            'Content-Type'  => 'application/json',
            'Authorization' => "Bearer $token",
        }});

    return unless $resp->{status} == 200 && $resp->{content};
    my $data = eval { $JSON->decode($resp->{content}) };
    if (   $action eq 'get_zone'
        && (!$data || !$data->{delegation} || !@{$data->{delegation}}) )
    {
        if ( $self->_record_delegated_zids($gid)->{$oid} ) {
            $result->{pseudo}                  = 1;
            $result->{deleted}                 = 0;
            $result->{delegate_write}          = 0;
            $result->{delegate_delete}         = 0;
            $result->{delegate_delegate}       = 0;
            $result->{delegate_add_records}    = 0;
            $result->{delegate_delete_records} = 0;
            return;
        }
    }

    return unless $data && $data->{delegation} && @{$data->{delegation}};

    my $d = $data->{delegation}[0];
    $result->{delegated_by_id}          = $d->{delegated_by_id};
    $result->{delegated_by_name}        = $d->{delegated_by_name};
    $result->{delegate_write}          = $d->{delegate_write}          // 0;
    $result->{delegate_delete}         = $d->{delegate_delete}         // 0;
    $result->{delegate_delegate}       = $d->{delegate_delegate}       // 0;
    $result->{delegate_add_records}    = $d->{delegate_add_records}    // 0;
    $result->{delegate_delete_records} = $d->{delegate_delete_records} // 0;
}

# zones holding a record delegated to the group; a zone list asks this
# once per zone, so fetch and index the delegated records once per request
sub _record_delegated_zids {
    my ($self, $gid) = @_;
    return $self->{record_delegated_zids}{$gid} //= do {
        my %zids;
        my $delegated = $self->_get_json("/delegation?gid=$gid&type=ZONERECORD");
        for my $record (@{ $delegated->{delegation} // [] }) {
            my $rid = $record->{nt_zone_record_id} // $record->{nt_object_id};
            next unless $rid;
            my $zr = $self->_get_json("/zone_record/$rid");
            next unless $zr && $zr->{zone_record} && $zr->{zone_record}[0];
            $zids{ $zr->{zone_record}[0]{zid} } = 1;
        }
        \%zids;
    };
}

sub _session_group_id {
    my ($self) = @_;
    return $self->{session_group_id} if exists $self->{session_group_id};

    my $gid = eval { $self->_nt->{user}{store}{nt_group_id} };
    if (!$gid) {
        my $session = $self->_get_json('/session');
        $gid = $session->{group}{id}
            if $session && $session->{group};
    }
    $self->{session_group_id} = $gid;
    return $gid;
}

sub _base_url {
    my ($self) = @_;
    return $self->{base_url} if $self->{base_url};
    my $nt   = $self->_nt;
    my $proto = $nt->{transfer_protocol} || 'http';
    my $host  = $nt->{server_host} || 'localhost';
    my $port  = $nt->{server_port} || 3000;
    return "$proto://$host:$port";
}

sub _remap_fields {
    my ($entity, $resource) = @_;
    return {} unless $entity && ref $entity eq 'HASH';

    my %out = %$entity;
    my $map = $FIELD_V2{$resource};
    if ($map) {
        for my $v3key (keys %$map) {
            if (exists $out{$v3key}) {
                $out{$map->{$v3key}} = delete $out{$v3key};
            }
        }
    }

    # zone_record: map v3 RFC field names back to v2 DB column names
    if ($resource eq 'zone_record' && $out{type}) {
        _remap_zr_rfc_to_v2(\%out);
    }

    # zone_record: v2 expects weight/priority even when 0
    if ($resource eq 'zone_record') {
        $out{weight}   //= 0;
        $out{priority} //= 0;
    }

    # nameserver: flatten v3 nested export object to v2 flat fields
    if ($resource eq 'nameserver' && ref $out{export} eq 'HASH') {
        my $exp = delete $out{export};
        $out{export_format}   = $exp->{type}     if exists $exp->{type};
        $out{export_interval} = $exp->{interval}  if exists $exp->{interval};
        $out{export_serials}  = $exp->{serials}   if exists $exp->{serials};
        $out{export_status}   = $exp->{status}    if exists $exp->{status};
    }

    # v3 returns the export type as a flat field
    if ($resource eq 'nameserver' && exists $out{type}) {
        $out{export_format} //= delete $out{type};
    }

    return \%out;
}

sub _resource_for_action {
    my ($action) = @_;
    return 'delegation'  if $action =~ /delegat/;
    return 'zone_record' if $action =~ /zone_record/;
    return 'nameserver'  if $action =~ /nameserver/;
    return 'zone'        if $action =~ /zone/;
    return 'user'        if $action =~ /user/;
    return 'group'       if $action =~ /group/;
    return 'permission'  if $action =~ /perm/;
    return 'session';
}

sub _is_list_action {
    my ($action) = @_;
    return 1 if $action =~ /^get_group_(?:zones|users|nameservers|groups)$/;
    return 1 if $action =~ /^get_(?:group_subgroups|zone_list|user_list|nameserver_list)$/;
    return 1 if $action eq 'get_usable_nameservers';
    return 1 if $action eq 'get_zone_records';
    return 1 if $action =~ /^get_(?:delegated_|zone_delegates|zone_record_delegates)/;
    return 0;
}

sub _http_error {
    my ($status, $data) = @_;
    my $code = $data->{error_code} // $status;
    my $msg  = $data->{error_msg}
        // $data->{message}
        // $data->{err}
        // $data->{error}
        // ($data->{meta} ? $data->{meta}{msg} : undef)
        // "HTTP $status";
    my $desc = '';
    if ($data->{error_msg}) {
        # v2 clients branch on error_desc, so mirror NicToolServer::error_response
        # where v3's codes line up; permission denials stay the catch-all
        my %desc_for = (
            300 => 'Sanity error',
            301 => 'Required parameters missing',
            302 => 'Some parameters were invalid',
            400 => 'Some parameters were invalid',
            409 => 'Sanity error',
            601 => 'Object Not Found',
        );
        $desc = $desc_for{$code} // 'Access Permission denied';
    } else {
        $msg = "REST: $msg";
    }
    return { error_code => $code, error_msg => $msg, error_desc => $desc };
}

sub _flatten_permissions {
    my ($result) = @_;
    my $perms = delete $result->{permissions};
    return unless $perms && ref $perms eq 'HASH';

    # v3 nests: { group: { create: true }, zone: { write: false } }
    # v2 expects: group_create => 1, zone_write => 0
    for my $category (qw(group zone zonerecord user nameserver)) {
        my $cat_perms = $perms->{$category};
        next unless $cat_perms && ref $cat_perms eq 'HASH';
        for my $perm (keys %$cat_perms) {
            next if $perm eq 'id';
            next if $perm eq 'usable';
            my $v2key = "${category}_${perm}";
            my $val = $cat_perms->{$perm};
            $result->{$v2key} = ref $val ? $val
                : $val && $val ne '0' ? 1 : 0;
        }
        if ($category eq 'nameserver' && exists $cat_perms->{usable}) {
            my $u = $cat_perms->{usable};
            $result->{usable_ns} = ref $u eq 'ARRAY'
                ? join(',', @$u) : ($u // '');
        }
    }
    # Top-level permission fields
    $result->{self_write} = $perms->{self_write} ? 1 : 0
        if exists $perms->{self_write};
}

sub _not_implemented {
    my ($action) = @_;
    return {
        error_code => 510,
        error_msg  => "REST: action '$action' is not yet implemented in v3 API",
    };
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::Transport::REST - REST/JSON transport for NicTool v3 API

=head1 DESCRIPTION

Maps NicTool v2 RPC-style method calls to the v3 REST API.
Handles JWT authentication, parameter translation, and response
flattening so the v2 client and test suite work transparently
against the v3 API.

=cut
