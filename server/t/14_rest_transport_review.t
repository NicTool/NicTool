use strict;
use warnings;

use JSON::PP;
use Test::More;

use lib 'api/lib';
use NicTool::Transport::REST;

{
    package Local::ReviewHTTP;

    sub new {
        my ($class, @responses) = @_;
        return bless { requests => [], responses => \@responses }, $class;
    }

    sub request {
        my ($self, $method, $url, $options) = @_;
        push @{ $self->{requests} }, [ $method, $url, $options ];
        return shift @{ $self->{responses} };
    }
}

sub response {
    my ($data) = @_;
    return status_response(200, $data);
}

sub status_response {
    my ($status, $data) = @_;
    return {
        status  => $status,
        content => JSON::PP->new->encode($data),
    };
}

sub transport {
    my (@responses) = @_;
    my $rest = NicTool::Transport::REST->new(
        bless { _rest_jwt_token => 'jwt' }, 'Local::ReviewNicTool' );
    $rest->{http} = Local::ReviewHTTP->new(@responses);
    return $rest;
}

sub slurp {
    my ($file) = @_;
    open my $fh, '<', $file or die "Cannot read $file: $!";
    my $text = do { local $/; <$fh> };
    close $fh;
    return $text;
}

my $setup_source = slurp('../dist/setup/setup-test-env.pl');
my ($rest_config) = $setup_source
    =~ m{server/t/test-rest\.cfg.*?<<EOF \);(.*?)^EOF$}ms;
ok defined $rest_config, 'REST test config template is present';
like $rest_config, qr/^dsn\s*=>/m, 'REST test config includes the db dsn';
like $rest_config, qr/^db_user\s*=>/m, 'REST test config includes the db user';
like $rest_config, qr/^db_pass\s*=>/m, 'REST test config includes the db password';

my $delegation_source = slurp('xt/16_delegation.t');
my @subclients = grep { /data_protocol\s*=>/ }
    $delegation_source =~ /new NicTool\((.*?)\n\s*\);/sg;
is scalar @subclients, 3,
    'delegation tests create three protocol-configured subclients';
like $_, qr/transfer_protocol\s*=>/,
    'delegation subclient carries the transfer protocol' for @subclients;

my $swagger = {
    paths => {
        '/zone_record' => {
            post => {
                parameters => [ {
                    in => 'body',
                    schema => { properties => {
                        type => { type => 'string', enum => [qw( A AAAA TXT MX )] },
                    } },
                } ],
            },
        },
    },
};
my $rr_types = transport(response($swagger));
my $rr_type_result = $rr_types->send_request(
    'http://api:3000', action => 'get_record_type', type => 'ALL' );
is_deeply [ map { $_->{id} } @{ $rr_type_result->{types} } ],
    [ 1, 28, 16, 15 ], 'record choices retain their IETF type codes';

my $rr_type_by_id = transport(response($swagger));
is $rr_type_by_id->send_request(
    'http://api:3000', action => 'get_record_type', type => 15 ),
    'MX', 'numeric record type lookup uses the IETF code';

my $empty_columns = transport(
    response({ zone => [ { id => 9, gid => 2, zone => 'new.test' } ] }),
    response({ zone_record => [ { id => 11, zid => 9, type => 'A' } ] }),
);
$empty_columns->send_request(
    'http://api:3000',
    action       => 'new_zone_record',
    nt_zone_id   => 9,
    name         => 'a',
    type         => 'A',
    address      => '192.0.2.11',
    weight       => '',
    priority     => '',
);
my $empty_body = JSON::PP->new->decode(
    $empty_columns->{http}{requests}[1][2]{content} );
ok !exists $empty_body->{weight}, 'empty record weight is omitted';
ok !exists $empty_body->{priority}, 'empty record priority is omitted';

my $ds = transport(response({ zone_record => [ { id => 15, zid => 9, type => 'DS' } ] }));
$ds->send_request(
    'http://api:3000',
    action       => 'new_zone_record',
    nt_zone_id   => 9,
    name         => 'ds.new.test.',
    type         => 'DS',
    address      => 'ABCD',
    weight       => 12345,
    priority     => 8,
    other        => 2,
);
my $ds_body = JSON::PP->new->decode($ds->{http}{requests}[0][2]{content});
is_deeply { map { $_ => $ds_body->{$_} }
        ('key tag', 'algorithm', 'digest type', 'digest') },
    {
        'key tag'     => 12345,
        algorithm     => 8,
        'digest type' => 2,
        digest        => 'ABCD',
    }, 'DS columns become the matching RFC fields';

my $ds_read = transport(response({ zone_record => [ {
    id => 15, zid => 9, type => 'DS', digest => 'ABCD',
    'key tag' => 12345, algorithm => 8, 'digest type' => 2,
} ] }));
my $ds_result = $ds_read->send_request(
    'http://api:3000', action => 'get_zone_records', nt_zone_id => 9 );
is_deeply { map { $_ => $ds_result->{records}[0]{$_} }
        qw(weight priority other address) },
    { weight => 12345, priority => 8, other => 2, address => 'ABCD' },
    'DS RFC fields return in the matching v2 columns';

my $key = transport(response({ zone_record => [ { id => 16, zid => 9, type => 'KEY' } ] }));
$key->send_request(
    'http://api:3000',
    action       => 'new_zone_record',
    nt_zone_id   => 9,
    name         => 'key.new.test.',
    type         => 'KEY',
    address      => 'base64',
    weight       => 256,
    priority     => 3,
    other        => 8,
);
my $key_body = JSON::PP->new->decode($key->{http}{requests}[0][2]{content});
is_deeply { map { $_ => $key_body->{$_} }
        qw(flags protocol algorithm publickey) },
    { flags => 256, protocol => 3, algorithm => 8, publickey => 'base64' },
    'KEY uses the DNSKEY column convention';

my $key_read = transport(response({ zone_record => [ {
    id => 16, zid => 9, type => 'KEY', publickey => 'base64',
    flags => 256, protocol => 3, algorithm => 8,
} ] }));
my $key_result = $key_read->send_request(
    'http://api:3000', action => 'get_zone_records', nt_zone_id => 9 );
is_deeply { map { $_ => $key_result->{records}[0]{$_} }
        qw(weight priority other address) },
    { weight => 256, priority => 3, other => 8, address => 'base64' },
    'KEY RFC fields return in the DNSKEY v2 columns';

sub record_body {
    my (%record) = @_;
    my $rest = transport(
        response({ zone => [ { id => 5, zone => 'zone.com.', gid => 2 } ] }),
        response({ zone_record => [ { id => 9, zid => 5 } ] }),
    );
    $rest->send_request(
        'http://api:3000', action => 'new_zone_record',
        nt_zone_id => 5, ttl => 86400, %record );
    my ($post) = grep { $_->[0] eq 'POST' } @{ $rest->{http}{requests} };
    return JSON::PP->new->decode($post->[2]{content});
}

is record_body(name => 'alias', type => 'CNAME', address => 'www')->{cname},
    'www.zone.com.', 'a relative CNAME target is qualified against the zone';
is record_body(name => '@', type => 'MX', address => 'mail', weight => 10)->{exchange},
    'mail.zone.com.', 'a relative MX target is qualified against the zone';
is record_body(name => '@', type => 'NS', address => 'ns1')->{dname},
    'ns1.zone.com.', 'a relative NS target is qualified against the zone';
is record_body(name => '_sip._tcp', type => 'SRV', address => 'sip', other => 5060)->{target},
    'sip.zone.com.', 'a relative SRV target is qualified against the zone';
is record_body(name => '2', type => 'PTR', address => 'host')->{dname},
    'host.zone.com.', 'a relative PTR target is qualified against the zone';

my $partial_delete = transport(
    response({}), status_response(403, { error => 'denied' }), response({}) );
my $partial_delete_result = $partial_delete->send_request(
    'http://api:3000', action => 'delete_zones', zone_list => '5,6,7' );
is scalar @{ $partial_delete->{http}{requests} }, 3,
    'a failed batch delete still attempts every id';
is_deeply $partial_delete_result->{completed_ids}, [ 5, 7 ],
    'batch delete reports completed ids';
is_deeply $partial_delete_result->{failed_ids}, [6],
    'batch delete reports failed ids';
like $partial_delete_result->{error_msg},
    qr/completed ids: 5,7; failed ids: 6/,
    'batch delete explains the partial result';

my $partial_move = transport(
    response({}), status_response(409, { error => 'blocked' }), response({}) );
my $partial_move_result = $partial_move->send_request(
    'http://api:3000', action => 'move_zones',
    zone_list => '5,6,7', nt_group_id => 3 );
is scalar @{ $partial_move->{http}{requests} }, 3,
    'a failed batch move still attempts every id';
is_deeply $partial_move_result->{completed_ids}, [ 5, 7 ],
    'batch move reports completed ids';
is_deeply $partial_move_result->{failed_ids}, [6],
    'batch move reports failed ids';

my $multi_delegate = transport(
    response({ zone => [ { id => 5, gid => 2 } ] }),
    response({ zone => [ { id => 6, gid => 2 } ] }),
    response({}), response({}),
);
$multi_delegate->send_request(
    'http://api:3000',
    action       => 'delegate_zones',
    zone_list    => '5,6',
    nt_group_id  => 3,
    nt_zone_id   => 99,
    optional     => undef,
    perm_write   => 1,
);
my @delegate_posts = grep { $_->[0] eq 'POST' }
    @{ $multi_delegate->{http}{requests} };
is scalar @delegate_posts, 2, 'multi-create sends one request for each id';
for my $at (0 .. $#delegate_posts) {
    my $body = JSON::PP->new->decode($delegate_posts[$at][2]{content});
    is $body->{oid}, 5 + $at, 'multi-create uses the list id as oid';
    ok !exists $body->{zid}, 'multi-create removes a stray zid';
    ok !exists $body->{optional}, 'multi-create removes undefined values';
}

my $partial_delegate = transport(
    response({ zone => [ { id => 5, gid => 2 } ] }),
    response({ zone => [ { id => 6, gid => 2 } ] }),
    response({ zone => [ { id => 7, gid => 2 } ] }),
    response({}), status_response(403, { error => 'denied' }), response({}),
);
my $partial_delegate_result = $partial_delegate->send_request(
    'http://api:3000', action => 'delegate_zones',
    zone_list => '5,6,7', nt_group_id => 3, perm_write => 1 );
is scalar(grep { $_->[0] eq 'POST' } @{ $partial_delegate->{http}{requests} }), 3,
    'a failed batch create still attempts every id';
is_deeply $partial_delegate_result->{completed_ids}, [ 5, 7 ],
    'batch create reports completed ids';
is_deeply $partial_delegate_result->{failed_ids}, [6],
    'batch create reports failed ids';

my $array_batch_error = transport(
    response({}), status_response(502, []), response({}) );
my $array_batch_result = $array_batch_error->send_request(
    'http://api:3000', action => 'delete_zones', zone_list => '5,6,7' );
is_deeply $array_batch_result->{failed_ids}, [6],
    'a non-object batch error body identifies the failed id';

my $scalar_error = transport(status_response(502, 'gateway timeout'));
my $scalar_error_result = $scalar_error->send_request(
    'http://api:3000', action => 'get_group', nt_group_id => 2 );
is $scalar_error_result->{error_code}, 502,
    'a scalar JSON error body returns a v2 error hash';
like $scalar_error_result->{error_msg}, qr/gateway timeout/,
    'a scalar JSON error body retains its message';

my $array_success = transport(status_response(200, []));
my $array_success_result = $array_success->send_request(
    'http://api:3000', action => 'get_group', nt_group_id => 2 );
is $array_success_result->{error_code}, 502,
    'a non-object success body returns a v2 gateway error';

my $denied_edit = transport(
    status_response(403, { error => 'denied read' }),
    status_response(404, { error => 'No Access Allowed to that object' }),
);
my $denied_edit_result = $denied_edit->send_request(
    'http://api:3000', action => 'edit_zone', nt_zone_id => 9, ttl => 7200 );
is $denied_edit_result->{error_code}, 404,
    'a serial lookup failure does not mask the edit response';
like $denied_edit_result->{error_msg}, qr/No Access Allowed/,
    'a denied zone edit retains the API message';

my $group_listing = transport(
    response({ group => [
        { id => 3, parent_gid => 2, name => 'one' },
        { id => 4, parent_gid => 2, name => 'two' },
        { id => 5, parent_gid => 2, name => 'three' },
    ] }),
    response({ group => [
        { id => 2, parent_gid => 1, name => 'root' },
        { id => 3, parent_gid => 2, name => 'one' },
        { id => 4, parent_gid => 2, name => 'two' },
        { id => 5, parent_gid => 2, name => 'three' },
        { id => 6, parent_gid => 4, name => 'grandchild' },
    ] }),
);
my $group_listing_result = $group_listing->send_request(
    'http://api:3000', action => 'get_group_groups', nt_group_id => 2 );
is scalar @{ $group_listing->{http}{requests} }, 2,
    'group listings derive child flags from one subtree read';
is_deeply [ map { $_->{has_children} } @{ $group_listing_result->{groups} } ],
    [ 0, 1, 0 ], 'group listing child flags match the subtree';

done_testing;
