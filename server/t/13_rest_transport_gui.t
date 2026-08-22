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

done_testing;
