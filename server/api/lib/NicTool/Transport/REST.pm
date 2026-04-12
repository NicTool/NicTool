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

    # Flatten nested permissions into v2 flat keys
    _flatten_permissions($result);

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

    return {
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
}

sub _adapt_session {
    my ($self, $data) = @_;

    my $user  = $data->{user}  // {};
    my $group = $data->{group} // {};
    my $sess  = $data->{session} // {};

    return {
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
    return \%out;
}

sub _resource_for_action {
    my ($action) = @_;
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
    return 0;
}

sub _http_error {
    my ($status, $data) = @_;
    my $msg = $data->{message}
        // $data->{err}
        // $data->{error}
        // ($data->{meta} ? $data->{meta}{msg} : undef)
        // "HTTP $status";
    return { error_code => $status, error_msg => "REST: $msg" };
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
        if ($category eq 'nameserver' && $cat_perms->{usable}) {
            $result->{usable_ns} = $cat_perms->{usable};
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
