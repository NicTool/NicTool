package NicTool::Transport::REST;

# ABSTRACT: REST/JSON transport for NicTool v3 API

use strict;
use warnings;
use parent 'NicTool::Transport';
use HTTP::Tiny;
use JSON::PP;

my $JSON = JSON::PP->new->utf8->allow_nonref;

# v2 action -> { method, path, [id_param], [id_from_list], [query_map] }
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
    get_group_zones => { method => 'GET',     path => '/zone',
                         query_map => { nt_group_id => 'gid' } },

    # Zone records
    new_zone_record    => { method => 'POST',   path => '/zone_record' },
    get_zone_record    => { method => 'GET',     path => '/zone_record/:nt_zone_record_id' },
    get_zone_records   => { method => 'GET',     path => '/zone_record',
                            query_map => { nt_zone_id => 'zid' } },
    edit_zone_record   => { method => 'PUT',     path => '/zone_record/:nt_zone_record_id' },
    delete_zone_record => { method => 'DELETE',  path => '/zone_record/:nt_zone_record_id' },

    # Groups
    new_group        => { method => 'POST',   path => '/group' },
    get_group        => { method => 'GET',     path => '/group/:nt_group_id' },
    edit_group       => { method => 'PUT',     path => '/group/:nt_group_id' },
    delete_group     => { method => 'DELETE',  path => '/group/:nt_group_id' },
    get_group_groups => { method => 'GET',     path => '/group',
                          query_map => { nt_group_id => 'parent_gid' } },

    # Users
    new_user        => { method => 'POST',   path => '/user' },
    get_user        => { method => 'GET',     path => '/user/:nt_user_id' },
    edit_user       => { method => 'PUT',     path => '/user/:nt_user_id' },
    delete_users    => { method => 'DELETE',  path => '/user/:id',
                         id_from_list => 'user_list' },
    get_group_users => { method => 'GET',     path => '/user',
                         query_map => { nt_group_id => 'gid' } },

    # Nameservers
    new_nameserver        => { method => 'POST',   path => '/nameserver' },
    get_nameserver        => { method => 'GET',     path => '/nameserver/:nt_nameserver_id' },
    edit_nameserver       => { method => 'PUT',     path => '/nameserver/:nt_nameserver_id' },
    delete_nameserver     => { method => 'DELETE',  path => '/nameserver/:nt_nameserver_id' },
    get_group_nameservers => { method => 'GET',     path => '/nameserver',
                               query_map => { nt_group_id => 'gid' } },

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
    group       => { id => 'nt_group_id',
                     parent_group_id => 'parent_group_id' },
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

    $self->{http} ||= HTTP::Tiny->new(
        agent   => "NicTool-REST/$NicTool::VERSION",
        timeout => 30,
    );
    my $resp = $self->{http}->request('GET', $self->_base_url . $path,
        { headers => \%headers });
    return undef unless $resp->{status} == 200 && $resp->{content};
    return eval { $JSON->decode($resp->{content}) };
}

sub _qualify_owner {
    my ($self, $body) = @_;
    my $zid = $body->{zid} or return;

    my $zone = $self->_get_zone($zid) or return;
    (my $bare = $zone->{zone}) =~ s/\.$//;
    $body->{owner} .= $body->{owner} eq $bare ? '.' : ".$bare.";
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


sub send_request {
    my ($self, $url, %vars) = @_;

    my $action = delete $vars{action};
    delete $vars{nt_user_session};
    delete $vars{nt_protocol_version};

    my $spec = $ACTION_MAP{$action};
    return _not_implemented($action) unless $spec;

    my $http_method = $spec->{method};
    my $path        = $spec->{path};

    # For id_from_list actions, extract IDs from an arrayref or comma-separated list
    my $list_raw;
    if ($spec->{id_from_list}) {
        $list_raw = delete $vars{$spec->{id_from_list}} // '';
        my @vals = ref $list_raw eq 'ARRAY' ? @$list_raw : split /,/, $list_raw;
        my @ids = grep { defined && /^\d+$/ && $_ > 0 } @vals;
        if (@ids > 1) {
            if ($http_method eq 'POST') {
                return $self->_multi_create($url, $action, $spec, \@ids, %vars);
            }
            return $self->_multi_delete($url, $spec, \@ids, %vars);
        }
        $vars{id} = $ids[0] if @ids;
    }

    # delegation calls: reject missing/invalid list, object and group ids
    # with the error codes the v2 client expects
    if ( $action =~ /delegat/ ) {
        my $id_param = $action =~ /zone_record/ ? 'nt_zone_record_id' : 'nt_zone_id';

        if ( defined $list_raw && !exists $vars{id} ) {
            return _v2_param_error( $spec->{id_from_list},
                length $list_raw ? 302 : 301 );
        }

        my $oid = exists $vars{id} ? $vars{id} : $vars{$id_param};
        if ( $action !~ /^get_delegated_/ ) {
            if ( !defined $oid || $oid eq '' ) {
                return _v2_param_error( $id_param, 301 );
            }
            if ( $oid !~ /^\d+$/ || $oid == 0 ) {
                return _v2_param_error( $id_param, 302 );
            }
        }

        my $gid = $vars{nt_group_id};
        if ( $action =~ /^get_delegated_/ || $http_method ne 'GET' ) {
            if ( !defined $gid || $gid eq '' ) {
                return _v2_param_error( 'nt_group_id', 301 );
            }
            if ( $gid !~ /^\d+$/ || $gid == 0 ) {
                return _v2_param_error( 'nt_group_id', 302 );
            }
        }

        # delegating an object to the group that already owns it is a no-op
        # the v2 server rejected as a sanity error
        if (   $http_method eq 'POST'
            && defined $oid
            && ( my $obj_gid = $self->_delegation_object_gid( $action, $oid ) ) )
        {
            if ( $obj_gid == $gid ) {
                return {
                    error_code => 300,
                    error_msg  => 'Cannot delegate to your own group.',
                    error_desc => 'Sanity error',
                };
            }
        }
    }

    # Substitute :param placeholders in path
    $path =~ s{:(\w+)}{
        my $key = $1;
        my $val = delete $vars{$key};
        defined $val ? $val : ''
    }ge;

    # Build query string for GET requests
    my $query = '';
    if ($spec->{query_map}) {
        my @qparts;
        for my $v2key (keys %{$spec->{query_map}}) {
            my $v3key = $spec->{query_map}{$v2key};
            my $val = delete $vars{$v2key};
            push @qparts, "$v3key=$val" if defined $val;
        }
        $query = '?' . join('&', @qparts) if @qparts;
    }

    # Translate remaining v2 param names to v3
    my %body;
    for my $key (keys %vars) {
        my $v3key = $PARAM_V3{$key} // $key;
        $body{$v3key} = $vars{$key};
    }

    # new_group: v2 sends nt_group_id as parent, v3 wants parent_gid
    if ($action eq 'new_group' && exists $body{gid}) {
        $body{parent_gid} = delete $body{gid};
    }

    # zone_record: v2 uses 'name', v3 uses 'owner'
    if ($action =~ /zone_record/ && exists $body{name}) {
        $body{owner} = delete $body{name};
    }

    # zone_record: qualify relative owners against their zone, like the v2
    # server did; v3's RR parser rejects them
    if (   $action =~ /^(?:new|edit)_zone_record$/
        && defined $body{owner}
        && $body{owner} !~ /\.$/ )
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
    for my $bkey (qw(inherit_group_permissions is_admin deleted)) {
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

    $self->{http} ||= HTTP::Tiny->new(
        agent      => "NicTool-REST/$NicTool::VERSION",
        timeout    => 30,
    );

    my $resp = $self->{http}->request($http_method, $full_url, \%opts);

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

        $self->{http} ||= HTTP::Tiny->new(
            agent   => "NicTool-REST/$NicTool::VERSION",
            timeout => 30,
        );

        my $resp = $self->{http}->request('DELETE', $full_url,
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

    $self->{http} ||= HTTP::Tiny->new(
        agent   => "NicTool-REST/$NicTool::VERSION",
        timeout => 30,
    );

    for my $id (@$ids) {
        $body{oid} = $id;

        my %headers = ('Content-Type' => 'application/json');
        $headers{'Authorization'} = "Bearer $token" if $token;

        my $resp = $self->{http}->request('POST', $url . $path,
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
    get_zone_records             => 'records',
    get_usable_nameservers       => 'nameservers',
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

    # Determine resource type from action
    my $resource = _resource_for_action($action);
    my $rkey     = $RESOURCE_FOR{$resource} // $resource;

    my $result = { error_code => 200, error_msg => 'OK' };

    my $entity_data = $data->{$rkey};

    # v3 group endpoints return a single object for single-entity routes,
    # zone/user/nameserver return arrays -- normalize to array
    if (ref $entity_data eq 'HASH') {
        $entity_data = [$entity_data];
    }

    if (!$entity_data || ref $entity_data ne 'ARRAY') {
        return $result;
    }

    my $is_list = _is_list_action($action);
    my $is_create = ($action =~ /^new_/);

    if ($is_list) {
        my @remapped = map {
            my $r = _remap_fields($_, $resource);
            $r->{deleted} //= 0
                if $resource =~ /^(?:zone|zone_record|group|user|nameserver)$/;
            $self->_unqualify_owner($r) if $resource eq 'zone_record';
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
            $result->{total}  = $pg->{total}    // 0;
            $result->{start}  = ($pg->{offset}  // 0);
            $result->{end}    = $result->{start} + scalar(@remapped);
            $result->{page}   = 1;
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
        $entity->{deleted} //= 0
            if $resource =~ /^(?:zone|zone_record|group|user|nameserver)$/;
        $self->_unqualify_owner($entity) if $resource eq 'zone_record';
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

    my $gid = $self->_nt->{user}{store}{nt_group_id};
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
    $self->{http} ||= HTTP::Tiny->new(
        agent   => "NicTool-REST/$NicTool::VERSION",
        timeout => 30,
    );

    my $resp = $self->{http}->request('GET',
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
        my $delegated = $self->_get_json(
            "/delegation?gid=$gid&type=ZONERECORD" );
        for my $record (@{ $delegated->{delegation} // [] }) {
            my $rid = $record->{nt_zone_record_id} // $record->{nt_object_id};
            next unless $rid;
            my $zr = $self->_get_json("/zone_record/$rid");
            next unless $zr && $zr->{zone_record} && $zr->{zone_record}[0];
            next unless $zr->{zone_record}[0]{zid} == $oid;
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
    $result->{delegate_write}          = $d->{delegate_write}          // 0;
    $result->{delegate_delete}         = $d->{delegate_delete}         // 0;
    $result->{delegate_delegate}       = $d->{delegate_delegate}       // 0;
    $result->{delegate_add_records}    = $d->{delegate_add_records}    // 0;
    $result->{delegate_delete_records} = $d->{delegate_delete_records} // 0;
}

sub _base_url {
    my ($self) = @_;
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
    return 'group'       if $action =~ /group/;
    return 'user'        if $action =~ /user/;
    return 'permission'  if $action =~ /perm/;
    return 'session';
}

sub _is_list_action {
    my ($action) = @_;
    return 1 if $action =~ /^get_group_(?:zones|users|nameservers|groups)$/;
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
        $desc = 'Access Permission denied';
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
