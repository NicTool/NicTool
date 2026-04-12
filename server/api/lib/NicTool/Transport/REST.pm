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

sub send_request {
    my ($self, $url, %vars) = @_;

    my $action = delete $vars{action};
    delete $vars{nt_user_session};
    delete $vars{nt_protocol_version};

    my $spec = $ACTION_MAP{$action};
    return _not_implemented($action) unless $spec;

    my $http_method = $spec->{method};
    my $path        = $spec->{path};

    # For id_from_list actions, extract first ID from comma-separated list
    if ($spec->{id_from_list}) {
        my $list_val = delete $vars{$spec->{id_from_list}} // '';
        my @ids = grep { /^\d+$/ } split /,/, $list_val;
        if (@ids > 1) {
            if ($http_method eq 'POST') {
                return $self->_multi_create($url, $action, $spec, \@ids, %vars);
            }
            return $self->_multi_delete($url, $spec, \@ids, %vars);
        }
        $vars{id} = $ids[0] if @ids;
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

    # user: v2 sends password2 (confirmation), v3 doesn't use it
    delete $body{password2};

    # nameserver: v2 sends export_format, v3 nests it as export.type
    if ($action =~ /nameserver/ && exists $body{export_format}) {
        $body{export} = { type => delete $body{export_format} };
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

    return $self->_adapt_response($action, $data);
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
            _flatten_permissions($r);
            $r;
        } @$entity_data;
        $result->{list} = \@remapped;
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
