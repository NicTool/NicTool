use strict;
use warnings;

use JSON::PP;
use Test::More;

use lib 'api/lib';
use NicTool::Transport::REST;

{
    package Local::HTTP;

    sub new {
        my ( $class, @responses ) = @_;
        return bless { requests => [], responses => \@responses }, $class;
    }

    sub request {
        my ( $self, $method, $url, $options ) = @_;
        push @{ $self->{requests} }, [ $method, $url, $options ];
        return shift @{ $self->{responses} };
    }
}

sub response {
    my ($data) = @_;
    return {
        status  => 200,
        content => JSON::PP->new->encode($data),
    };
}

sub transport {
    my (@responses) = @_;
    my $rest = NicTool::Transport::REST->new(
        bless { _rest_jwt_token => 'jwt' }, 'Local::NicTool' );
    $rest->{http} = Local::HTTP->new(@responses);
    return $rest;
}

my $branch = transport(
    response({ group => { id => 2 } }),
    response({ group => [
        { id => 3, parent_gid => 2, name => 'child', has_children => 0 },
    ] }),
    response({ group => [
        { id => 2, parent_gid => 1, name => 'test group', has_children => 1 },
    ] }),
);
my @warnings;
my $branch_result;
{
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    $branch_result = $branch->send_request(
        'http://api:3000',
        action      => 'get_group_branch',
        nt_group_id => 3,
    );
}
is_deeply [ map { $_->{nt_group_id} } @{ $branch_result->{groups} } ],
    [ 2, 3 ], 'group branch is synthesized from v3 group reads';
is_deeply \@warnings, [], 'minimal GUI transport object emits no version warning';

my $empty = transport(response({ meta => {} }));
my $empty_result = $empty->send_request(
    'http://api:3000',
    action      => 'get_group_zones',
    nt_group_id => 2,
);
is_deeply $empty_result->{list}, [], 'empty list response always has list';
is_deeply $empty_result->{zones}, [], 'empty zone response always has zones';

my $subgroups = transport(response({
    group => [
        { id => 4, parent_gid => 2, name => 'subgroup', has_children => 0 },
    ],
}));
my $subgroup_result = $subgroups->send_request(
    'http://api:3000',
    action       => 'get_group_subgroups',
    nt_group_id  => 2,
    search_value => 'subgroup',
);
is $subgroup_result->{groups}[0]{nt_group_id}, 4,
    'subgroup list is adapted to the v2 shape';
like $subgroups->{http}{requests}[0][1],
    qr{/group\?parent_gid=2&name=subgroup$},
    'subgroup request maps parent and search parameters';

my $users = transport(response({
    user => [
        { id => 5, gid => 2, username => 'matched-user' },
    ],
    meta => { pagination => { filtered => 1, limit => 10, offset => 0 } },
}));
my $user_result = $users->send_request(
    'http://api:3000',
    action       => 'get_group_users',
    nt_group_id  => 2,
    search_value => 'matched-user',
    exact_match  => 1,
    limit        => 10,
    start        => 1,
);
is $user_result->{list}[0]{nt_user_id}, 5,
    'group user list is adapted under the v2 list key';
like $users->{http}{requests}[0][1],
    qr{/user\?exact_match=true&limit=10&gid=2&search=matched-user&offset=0$},
    'group user request maps search and pagination parameters';

# v3 strips gid from user rows; members pulled in by include_subgroups must
# keep their own group id rather than inheriting the requested one
my $sub_users = transport(response({
    user => [
        { id => 6, username => 'top', permissions => { group => { id => 2 } } },
        { id => 7, username => 'sub', permissions => { group => { id => 4 } } },
        { id => 8, username => 'bare' },
    ],
    meta => { pagination => { filtered => 3, limit => 10, offset => 0 } },
}));
my $sub_user_result = $sub_users->send_request(
    'http://api:3000',
    action            => 'get_group_users',
    nt_group_id       => 2,
    include_subgroups => 1,
    limit             => 10,
    start             => 1,
);
is_deeply [ map { $_->{nt_group_id} } @{ $sub_user_result->{list} } ],
    [ 2, 4, 2 ],
    'user listings keep each member own group id';

my $zones = transport(
    response({ zone => [ { id => 7, gid => 2, zone => 'one.test' } ] }),
    response({ zone => [ { id => 8, gid => 2, zone => 'two.test' } ] }),
);
my $zone_result = $zones->send_request(
    'http://api:3000',
    action    => 'get_zone_list',
    zone_list => '7,8',
);
is_deeply [ map { $_->{nt_zone_id} } @{ $zone_result->{zones} } ],
    [ 7, 8 ], 'ID list reads are aggregated through single-object v3 routes';

my $move_zones = transport(response({}), response({}));
my $move_result = $move_zones->send_request(
    'http://api:3000',
    action      => 'move_zones',
    nt_group_id => 4,
    zone_list   => '7,8',
);
is $move_result->{error_code}, 200,
    'multi-zone moves retain the v2 success response';
is_deeply [ map { $_->[0] } @{ $move_zones->{http}{requests} } ],
    [qw( PUT PUT )], 'multi-zone moves use PUT rather than DELETE';
is_deeply [ map { $_->[1] } @{ $move_zones->{http}{requests} } ],
    [qw( http://api:3000/zone/7 http://api:3000/zone/8 )],
    'each moved zone targets its v3 object route';
for my $request (@{ $move_zones->{http}{requests} }) {
    is_deeply(
        JSON::PP->new->decode( $request->[2]{content} ),
        { gid => 4 },
        'each moved zone receives the destination group'
    );
}

my $move_users = transport(response({}), response({}));
$move_users->send_request(
    'http://api:3000',
    action      => 'move_users',
    nt_group_id => 4,
    user_list   => [ 5, 6 ],
);
is_deeply [ map { $_->[1] } @{ $move_users->{http}{requests} } ],
    [qw( http://api:3000/user/5 http://api:3000/user/6 )],
    'multi-user moves use each v3 user route';

my $move_nameservers = transport(response({}), response({}));
$move_nameservers->send_request(
    'http://api:3000',
    action          => 'move_nameservers',
    nt_group_id     => 4,
    nameserver_list => '10,11',
);
is_deeply [ map { $_->[1] } @{ $move_nameservers->{http}{requests} } ],
    [qw( http://api:3000/nameserver/10 http://api:3000/nameserver/11 )],
    'multi-nameserver moves use each v3 nameserver route';

my $zone_logs = transport(response({
    log => [ {
        id => 12, gid => 4, uid => 5, zid => 7,
        timestamp => 123456, action => 'deleted', zone => 'logged.test.',
    } ],
    meta => { pagination => { total => 3, filtered => 1, limit => 50, offset => 0 } },
}));
my $zone_log_result = $zone_logs->send_request(
    'http://api:3000',
    action            => 'get_group_zones_log',
    nt_group_id       => 4,
    include_subgroups => 1,
    search_value      => 'logged.test.',
    limit             => 50,
    start             => 1,
);
is $zone_log_result->{log}[0]{nt_zone_log_id}, 12,
    'zone log ids are adapted to the v2 shape';
is $zone_log_result->{log}[0]{nt_zone_id}, 7,
    'zone log object ids are adapted to the v2 shape';
is $zone_log_result->{total}, 1, 'zone log filtered total is retained';
is_deeply $zone_log_result->{group_map}, {},
    'zone log response always supplies a group map';
like $zone_logs->{http}{requests}[0][1],
    qr{/log/zone\?include_subgroups=true&limit=50&gid=4&search=logged\.test\.&offset=0$},
    'zone log request maps scope, search, and pagination';

my $record_logs = transport(response({
    log => [ {
        id => 13, uid => 5, zid => 7, zrid => 8,
        timestamp => 123456, action => 'deleted', owner => 'host.logged.test.',
        type => 'A', address => '192.0.2.8',
    } ],
    meta => { pagination => { total => 1, filtered => 1, limit => 20, offset => 0 } },
}));
my $record_log_result = $record_logs->send_request(
    'http://api:3000',
    action      => 'get_zone_record_log',
    nt_zone_id => 7,
    limit       => 20,
    start       => 1,
    '1_sortfield' => 'name',
    '1_sortmod'   => 'Ascending',
);
is $record_log_result->{log}[0]{nt_zone_record_log_id}, 13,
    'record log ids are adapted to the v2 shape';
is $record_log_result->{log}[0]{nt_zone_record_id}, 8,
    'record log object ids are adapted to the v2 shape';
is $record_log_result->{log}[0]{name}, 'host.logged.test.',
    'record log owners use the v2 name field';
like $record_logs->{http}{requests}[0][1], qr{sort_by=owner},
    'record log maps name sorting to owner';
like $record_logs->{http}{requests}[0][1], qr{sort_dir=asc},
    'record log maps ascending sort direction';

my $global_logs = transport(response({
    log => [ {
        id => 14, gid => 4, uid => 5, timestamp => 123456,
        action => 'added', object => 'zone', object_id => 7,
        title => 'logged.test.', description => 'initial creation zone',
    } ],
    meta => { pagination => { total => 1, filtered => 1, limit => 50, offset => 0 } },
}));
my $global_log_result = $global_logs->send_request(
    'http://api:3000',
    action      => 'get_global_application_log',
    nt_group_id => 4,
    limit       => 50,
    start       => 1,
);
is $global_log_result->{log}[0]{nt_user_global_log_id}, 14,
    'global log ids are adapted to the v2 shape';
is $global_log_result->{log}[0]{nt_user_id}, 5,
    'global log actor ids are adapted to the v2 shape';

my $user_logs = transport(response({
    log => [ {
        id => 15, gid => 4, uid => 5, timestamp => 123456,
        action => 'added', object => 'zone', object_id => 7,
        title => 'logged.test.', description => 'initial creation zone',
    } ],
    meta => { pagination => { total => 1, filtered => 1, limit => 20, offset => 0 } },
}));
my $user_log_result = $user_logs->send_request(
    'http://api:3000',
    action      => 'get_user_global_log',
    nt_group_id => 4,
    nt_user_id  => 5,
    limit       => 20,
    start       => 1,
);
is $user_log_result->{list}[0]{nt_user_global_log_id}, 15,
    'user global logs use the v2 list and field shape';
like $user_logs->{http}{requests}[0][1],
    qr{/log/global\?.*gid=4.*uid=5},
    'user global logs scope the v3 request to the selected user';

my $record_log_entry = transport(
    response({ zone_record => [ { id => 8, zid => 7 } ] }),
    response({
        log => [ {
            id => 13, uid => 5, zid => 7, zrid => 8,
            timestamp => 123456, action => 'deleted', owner => 'host.logged.test.',
            type => 'A', address => '192.0.2.8',
        } ],
        meta => { pagination => { total => 1, filtered => 1, limit => 50, offset => 0 } },
    }),
);
my $record_log_entry_result = $record_log_entry->send_request(
    'http://api:3000',
    action                    => 'get_zone_record_log_entry',
    nt_zone_record_id         => 8,
    nt_zone_record_log_id     => 13,
);
is $record_log_entry_result->{nt_zone_record_log_id}, 13,
    'one record log entry is adapted as a v2 object';
like $record_log_entry->{http}{requests}[1][1],
    qr{/log/zone_record\?.*id=13.*zid=7|/log/zone_record\?.*zid=7.*id=13},
    'record log entry lookup is scoped to its zone and log id';

my $swagger = {
    paths => {
        '/nameserver' => { post => { parameters => [ {
            in => 'body', schema => { '$ref' => '#/definitions/Nameserver' },
        } ] } },
        '/zone_record' => { post => { parameters => [ {
            in => 'body', schema => { '$ref' => '#/definitions/ZoneRecord' },
        } ] } },
    },
    definitions => {
        Nameserver => { properties => {
            type => { '$ref' => '#/definitions/NameserverType' },
        } },
        NameserverType => { type => 'string', enum => [qw( bind nsd )] },
        ZoneRecord => { properties => {
            type => { '$ref' => '#/definitions/RecordType' },
        } },
        RecordType => { type => 'string', enum => [qw( A AAAA TXT )] },
    },
};

my $ns_types = transport(response($swagger));
my $ns_type_result = $ns_types->send_request(
    'http://api:3000',
    action => 'get_nameserver_export_types',
    type   => 'ALL',
);
is_deeply [ map { $_->{name} } @{ $ns_type_result->{types} } ],
    [qw( bind nsd )], 'nameserver choices come from the v3 API schema';

my $rr_types = transport(response($swagger));
my $rr_type_result = $rr_types->send_request(
    'http://api:3000',
    action => 'get_record_type',
    type   => 'ALL',
);
is_deeply [ map { $_->{name} } @{ $rr_type_result->{types} } ],
    [qw( A AAAA TXT )], 'record choices come from the v3 API schema';

my $delegated_zone = transport(
    response({ zone => [ { id => 9, gid => 1, zone => 'delegated.test' } ] }),
    response({ group => { id => 2 } }),
    response({ delegation => [ {
        delegated_by_id => 1,
        delegated_by_name => 'root',
        delegate_write => 1,
        delegate_delete => 1,
        delegate_delegate => 0,
        delegate_add_records => 1,
        delegate_delete_records => 1,
    } ] }),
);
my $delegated_zone_result = $delegated_zone->send_request(
    'http://api:3000',
    action      => 'get_zone',
    nt_zone_id => 9,
);
is $delegated_zone_result->{delegate_write}, 1,
    'GUI zone reads derive delegation from the authenticated session group';
is $delegated_zone_result->{delegated_by_id}, 1,
    'GUI zone reads retain delegation identity';
like $delegated_zone->{http}{requests}[2][1],
    qr{/delegation\?oid=9&gid=2&type=ZONE$},
    'GUI delegation lookup uses the session group';

my $delegated_zones = transport(
    response({ zone => [ { id => 9, gid => 1, zone => 'delegated.test' } ] }),
    response({ group => { id => 2 } }),
    response({ delegation => [ {
        delegated_by_id => 1,
        delegated_by_name => 'root',
        delegate_write => 1,
        delegate_delete => 1,
        delegate_delegate => 0,
        delegate_add_records => 1,
        delegate_delete_records => 1,
    } ] }),
);
my $delegated_zones_result = $delegated_zones->send_request(
    'http://api:3000',
    action      => 'get_group_zones',
    nt_group_id => 2,
);
is $delegated_zones_result->{zones}[0]{delegated_by_id}, 1,
    'GUI zone lists retain delegation identity';
is $delegated_zones_result->{zones}[0]{delegate_delete}, 1,
    'GUI zone lists retain delegation permissions';

my $new_zone = transport(response({ zone => [ { id => 9, gid => 2 } ] }));
my $new_zone_result = $new_zone->send_request(
    'http://api:3000',
    action      => 'new_zone',
    nt_group_id => 2,
    zone        => 'new.test',
    nameservers => '',
    serial      => '',
    template    => 'none',
);
is $new_zone_result->{nt_zone_id}, 9, 'zone create response is adapted';
my $zone_body = JSON::PP->new->decode(
    $new_zone->{http}{requests}[0][2]{content} );
is $zone_body->{serial}, 0, 'empty zone serial becomes the v3 default';
ok !exists $zone_body->{nameservers}, 'empty nameserver selection is omitted';
ok !exists $zone_body->{template}, 'client-side record template is omitted';

my $edit_zone = transport(response({ zone => [ { id => 9, gid => 2 } ] }));
$edit_zone->send_request(
    'http://api:3000',
    action      => 'edit_zone',
    nt_group_id => 4,
    nt_zone_id  => 9,
    zone        => 'new.test',
    nameservers => '',
    ttl         => 7200,
);
my $edit_zone_body = JSON::PP->new->decode(
    $edit_zone->{http}{requests}[0][2]{content} );
ok !exists $edit_zone_body->{zone}, 'zone edit omits the immutable name';
ok !exists $edit_zone_body->{gid}, 'zone edit omits the browsed group id';
ok !exists $edit_zone_body->{nameservers}, 'zone edit omits an empty nameserver selection';
is $edit_zone_body->{ttl}, 7200, 'zone edit retains mutable fields';

my $move_zone = transport(response({ zone => [ { id => 9, gid => 4 } ] }));
$move_zone->send_request(
    'http://api:3000',
    action      => 'move_zones',
    nt_group_id => 4,
    zone_list   => '9',
);
is $move_zone->{http}{requests}[0][1], 'http://api:3000/zone/9',
    'a single-zone move targets its v3 object route';
is_deeply(
    JSON::PP->new->decode( $move_zone->{http}{requests}[0][2]{content} ),
    { gid => 4 },
    'a single-zone move sends the destination group'
);

my $edit_user = transport(response({ user => [ { id => 5 } ] }));
$edit_user->send_request(
    'http://api:3000',
    action      => 'edit_user',
    nt_group_id => 4,
    nt_user_id  => 5,
    first_name  => 'renamed',
    password2   => '',
);
my $edit_user_body = JSON::PP->new->decode(
    $edit_user->{http}{requests}[0][2]{content} );
ok !exists $edit_user_body->{gid}, 'user edit omits the browsed group id';
is $edit_user_body->{first_name}, 'renamed', 'user edit retains profile fields';

my $sorted_records = transport(response({ zone_record => [] }));
$sorted_records->send_request(
    'http://api:3000',
    action        => 'get_zone_records',
    nt_zone_id    => 9,
    '1_sortfield' => 'name',
    '1_sortmod'   => 'Descending',
);
like $sorted_records->{http}{requests}[0][1], qr{sort_by=owner&sort_dir=desc},
    'record listings map the v2 name sort to owner';

my $sorted_zones = transport(response({ zone => [] }));
$sorted_zones->send_request(
    'http://api:3000',
    action            => 'get_group_zones',
    nt_group_id       => 2,
    include_subgroups => 1,
    '1_sortfield'     => 'group_name',
    '1_sortmod'       => 'Ascending',
);
unlike $sorted_zones->{http}{requests}[0][1], qr{sort_by},
    'zone listings drop the group sort v3 lacks';

my $new_group = transport(response({ group => [ { id => 12 } ] }));
$new_group->send_request(
    'http://api:3000',
    action       => 'new_group',
    nt_group_id  => 2,
    name         => 'permission.test',
    group_write  => 1,
    zone_delete  => 0,
);
my $group_body = JSON::PP->new->decode(
    $new_group->{http}{requests}[0][2]{content} );
is $group_body->{group_write}, JSON::PP::true,
    'group permission flags become JSON booleans';
is $group_body->{zone_delete}, JSON::PP::false,
    'false permission flags become JSON booleans';

my $new_ns = transport(response({ nameserver => [ { id => 10, gid => 2 } ] }));
$new_ns->send_request(
    'http://api:3000',
    action          => 'new_nameserver',
    nt_group_id     => 2,
    name            => 'ns.new.test.',
    address         => '192.0.2.10',
    address6        => undef,
    remote_login    => undef,
    export_format   => 'bind',
    export_interval => 120,
    export_serials  => 1,
);
my $ns_body = JSON::PP->new->decode(
    $new_ns->{http}{requests}[0][2]{content} );
is_deeply $ns_body->{export}, { interval => 120, serials => JSON::PP::true },
    'flat v2 export settings become the v3 export object';
ok !exists $ns_body->{address6}, 'undefined optional fields are omitted';
ok !exists $ns_body->{export_interval}, 'flat export fields are removed';

my $edit_ns = transport(response({ nameserver => [ { id => 10, gid => 2 } ] }));
$edit_ns->send_request(
    'http://api:3000',
    action           => 'edit_nameserver',
    nt_group_id      => 2,
    nt_nameserver_id => 10,
    description      => 'changed',
);
my $edit_ns_body = JSON::PP->new->decode(
    $edit_ns->{http}{requests}[0][2]{content} );
ok !exists $edit_ns_body->{gid}, 'nameserver edit omits immutable group id';

my $new_record = transport(
    response({ zone => [ { id => 9, gid => 2, zone => 'new.test' } ] }),
    response({
        zone_record => [ { id => 11, zid => 9, type => 'A', owner => 'a.new.test.' } ],
    }),
);
$new_record->send_request(
    'http://api:3000',
    action        => 'new_zone_record',
    nt_group_id   => 2,
    nt_zone_id    => 9,
    name          => 'a',
    type          => 'A',
    address       => '192.0.2.11',
);
my $record_body = JSON::PP->new->decode(
    $new_record->{http}{requests}[1][2]{content} );
ok !exists $record_body->{gid}, 'zone record writes omit the display group id';

my $sshfp = transport(response({
    zone_record => [ {
        id => 12, zid => 9, owner => 'ssh.new.test.', type => 'SSHFP',
        algorithm => 1, fptype => 1, fingerprint => 'abcdef',
    } ],
}));
$sshfp->send_request(
    'http://api:3000',
    action        => 'new_zone_record',
    nt_group_id   => 2,
    nt_zone_id    => 9,
    name          => 'ssh.new.test.',
    type          => 'SSHFP',
    address       => 'abcdef',
    weight        => '1',
    other         => '1',
);
my $sshfp_body = JSON::PP->new->decode(
    $sshfp->{http}{requests}[0][2]{content} );
is $sshfp_body->{fptype}, 1,
    'SSHFP accepts the legacy other-column fingerprint type fallback';
ok !exists $sshfp_body->{other}, 'SSHFP fallback removes the unused column';

my $naptr = transport(response({
    zone_record => [ {
        id => 13, zid => 9, owner => 'naptr.new.test.', type => 'NAPTR',
        order => 100, preference => 10, flags => 'U', service => 'E2U+sip',
        regexp => '!^.*$!sip:info@example.com!', replacement => '.',
    } ],
}));
$naptr->send_request(
    'http://api:3000',
    action        => 'new_zone_record',
    nt_group_id   => 2,
    nt_zone_id    => 9,
    name          => 'naptr.new.test.',
    type          => 'NAPTR',
    address       => '"U" "E2U+sip" "!^.*$!sip:info@example.com!"',
    weight        => '100',
    priority      => '10',
    description   => '.',
);
my $naptr_body = JSON::PP->new->decode(
    $naptr->{http}{requests}[0][2]{content} );
is_deeply {
    map { $_ => $naptr_body->{$_} }
        qw(order preference flags service regexp replacement)
}, {
    order => 100, preference => 10, flags => 'U', service => 'E2U+sip',
    regexp => '!^.*$!sip:info@example.com!', replacement => '.',
}, 'packed v2 NAPTR fields become RFC fields';
my $naptr_read = transport(response({
    zone_record => [ {
        id => 13, zid => 9, owner => 'naptr.new.test.', type => 'NAPTR',
        order => 100, preference => 10, flags => 'U', service => 'E2U+sip',
        regexp => '!^.*$!sip:info@example.com!', replacement => '.',
    } ],
}), response({ zone => [ { id => 9, gid => 2, zone => 'new.test.' } ] }));
my $naptr_result = $naptr_read->send_request(
    'http://api:3000',
    action     => 'get_zone_records',
    nt_zone_id => 9,
);
is $naptr_result->{records}[0]{address},
    '"U" "E2U+sip" "!^.*$!sip:info@example.com!"',
    'RFC NAPTR fields return in the v2 packed address column';

my $naptr_short = transport(response({
    zone_record => [ {
        id => 14, zid => 9, owner => 'short.new.test.', type => 'NAPTR',
        order => 100, preference => 10, flags => 'U', service => '',
        regexp => '!^.*$!sip:info@example.com!', replacement => '.',
    } ],
}));
$naptr_short->send_request(
    'http://api:3000',
    action        => 'new_zone_record',
    nt_group_id   => 2,
    nt_zone_id    => 9,
    name          => 'short.new.test.',
    type          => 'NAPTR',
    address       => '!^.*$!sip:info@example.com!',
    weight        => '100',
    priority      => '10',
    other         => 'u',
);
my $naptr_short_body = JSON::PP->new->decode(
    $naptr_short->{http}{requests}[0][2]{content} );
is_deeply {
    map { $_ => $naptr_short_body->{$_} }
        qw(flags service regexp replacement)
}, {
    flags => 'u', service => '', regexp => '!^.*$!sip:info@example.com!',
    replacement => '.',
}, 'legacy NAPTR shorthand receives valid RFC defaults';

my $naptr_partial = transport(response({
    zone_record => [ { id => 14, zid => 9, owner => 'short.new.test.', type => 'NAPTR' } ],
}), response({ zone => [ { id => 9, gid => 2, zone => 'new.test.' } ] }));
$naptr_partial->send_request(
    'http://api:3000',
    action            => 'edit_zone_record',
    nt_zone_record_id => 14,
    type              => 'NAPTR',
    ttl               => 7200,
);
my $naptr_partial_body = JSON::PP->new->decode(
    $naptr_partial->{http}{requests}[0][2]{content} );
ok !exists $naptr_partial_body->{regexp},
    'partial NAPTR edits do not clear omitted rdata fields';

# the v2 sanity layer expanded '@', 'name.@', and 'name.&' against the zone
# before storing; v3 gets the qualified owner and address instead
sub owner_body {
    my (%record) = @_;
    my $rest = transport(
        response({ zone => [ { id => 5, zone => 'zone.com.', gid => 2 } ] }),
        response({ zone_record => [ { id => 9, zid => 5 } ] }),
    );
    $rest->send_request(
        'http://api:3000',
        action     => 'new_zone_record',
        nt_zone_id => 5,
        type       => 'A',
        address    => '10.0.0.1',
        ttl        => 86400,
        %record,
    );
    my ($post) = grep { $_->[0] eq 'POST' } @{ $rest->{http}{requests} };
    return JSON::PP->new->decode( $post->[2]{content} );
}
is owner_body( name => '@' )->{owner}, 'zone.com.',
    'an @ owner is the zone apex';
is owner_body( name => '' )->{owner}, 'zone.com.',
    'an empty owner is the zone apex';
is owner_body( name => 'www.@' )->{owner}, 'www.zone.com.',
    'a name.@ owner is expanded against the zone';
is owner_body( name => 'www' )->{owner}, 'www.zone.com.',
    'a relative owner is qualified against the zone';
is owner_body( name => 'www.zone.com.' )->{owner}, 'www.zone.com.',
    'a qualified owner is left alone';
is owner_body( name => 'cn', type => 'CNAME', address => '@' )->{cname},
    'zone.com.', 'an @ address is the zone apex';
is owner_body( name => 'cn', type => 'CNAME', address => 'mail.@' )->{cname},
    'mail.zone.com.', 'a name.@ address is expanded against the zone';
is owner_body( name => '@', type => 'MX', address => 'mail.@', weight => 10 )->{exchange},
    'mail.zone.com.', 'a name.@ address is expanded for mapped rdata fields';
is owner_body( name => '1', type => 'PTR', address => '1.0.0.10.&' )->{dname},
    '1.0.0.10.in-addr.arpa.', 'a name.& address is expanded to in-addr.arpa';

# parameter errors answer like the v2 server did, before any v3 request
sub param_error {
    my ( $action, %vars ) = @_;
    my $rest   = transport();
    my $result = $rest->send_request( 'http://api:3000', action => $action, %vars );
    is scalar @{ $rest->{http}{requests} }, 0, "$action: no request for a bad $result->{error_msg}";
    return "$result->{error_code} $result->{error_msg}";
}
is param_error( 'get_zone', nt_zone_id => '' ),    '301 nt_zone_id', 'missing path id is 301';
is param_error( 'get_zone', nt_zone_id => 'abc' ), '302 nt_zone_id', 'non-numeric path id is 302';
is param_error( 'get_zone', nt_zone_id => 0 ),     '302 nt_zone_id', 'zero path id is 302';
is param_error( 'delete_zones', zone_list => '' ),     '301 zone_list', 'empty delete list is 301';
is param_error( 'delete_zones', zone_list => 'abc' ),  '302 zone_list', 'bad delete list is 302';
is param_error( 'delete_zones', zone_list => '5,abc' ), '302 zone_list', 'partly bad delete list is 302';
is param_error( 'delete_users', user_list => [] ),     '301 user_list', 'empty arrayref list is 301';
is param_error( 'delete_users', user_list => [ 5, '' ] ), '301 user_list', 'an empty list entry is 301';
is param_error( 'delete_zones', zone_list => '5,,6' ),   '301 zone_list', 'an empty list element is 301';
is param_error( 'move_zones', zone_list => '5,6', nt_group_id => '' ),
    '301 nt_group_id', 'multi-zone move without a group is 301';
is param_error( 'move_zones', zone_list => '5,6', nt_group_id => 'abc' ),
    '302 nt_group_id', 'multi-zone move to a bad group is 302';
is param_error( 'move_users', user_list => '7', nt_group_id => 0 ),
    '302 nt_group_id', 'single-user move to group 0 is 302';

my $multi_move = transport( response({}), response({}) );
$multi_move->send_request( 'http://api:3000',
    action => 'move_zones', zone_list => '5,6', nt_group_id => 3 );
is_deeply [ map { $_->[1] } @{ $multi_move->{http}{requests} } ],
    [ 'http://api:3000/zone/5', 'http://api:3000/zone/6' ],
    'a valid multi-zone move still reaches every zone';

# the GUI filters its record-type menu on forward/reverse, so the flags
# must follow the v2 metadata rather than treating every type as universal
my $typed = transport(response({
    paths => { '/zone_record' => { post => { parameters => [ {
        in => 'body', schema => { properties => { type => {
            type => 'string', enum => [qw( A AAAA MX PTR SPF SOA SVCB )],
        } } },
    } ] } } },
}));
my $typed_result = $typed->send_request(
    'http://api:3000', action => 'get_record_type', type => 'ALL' );
is_deeply { map { $_->{name} => "$_->{forward}/$_->{reverse}" } @{ $typed_result->{types} } },
    { A => '1/1', AAAA => '1/0', MX => '1/0', PTR => '1/1', SPF => '0/0',
      SOA => '0/0', SVCB => '1/1' },
    'record type forward/reverse flags follow the v2 metadata';

done_testing;
