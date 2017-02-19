package NicToolServer;
# ABSTRACT: NicTool API reference server

use strict;
use DBI;
use DBIx::Simple;
use RPC::XML;
use Data::Dumper;
use Net::IP;

$NicToolServer::VERSION = '2.33';

$NicToolServer::MIN_PROTOCOL_VERSION = '1.0';
$NicToolServer::MAX_PROTOCOL_VERSION = '1.0';

sub new {
    bless {
        'Apache' => $_[1],
        'client' => $_[2],
        'dbh'    => $_[3],
        'meta'   => $_[4],
        'user'   => $_[5],
        },
        $_[0];
}

sub debug             {0}
sub debug_auth        {0}
sub debug_session_sql {0}
sub debug_sql         {0}
sub debug_permissions {0}
sub debug_result      {0}
sub debug_request     {0}
sub debug_logs        {0}

sub handler {
    my $r = shift;

    my $dbh = &NicToolServer::dbh;

    # create & initialize required objects
    my $client_obj = NicToolServer::Client->new( $r, $dbh );
    my $self = NicToolServer->new( $r, $client_obj, $dbh, {} );
    my $response_obj = NicToolServer::Response->new( $r, $client_obj );

    # process session verification, login or logouts by just responding with the user hash
    my $error
        = NicToolServer::Session->new( $r, $client_obj, $dbh )->verify();
    warn "request: " . Data::Dumper::Dumper( $client_obj->data )
        if $self->debug_request;
    warn "request: error: " . Data::Dumper::Dumper($error)
        if $self->debug_request and $error;
    return $response_obj->respond($error) if $error;

    my $action = uc $client_obj->data()->{action};

    return $response_obj->respond( $client_obj->data()->{user} )
        if (   $action eq 'LOGIN'
            or $action eq 'VERIFY_SESSION'
            or $action eq 'LOGOUT' );

    $self->{user} = $client_obj->data()->{user};

    my $cmd = $self->api_commands->{$action} or do {

        # fart on unknown actions
        warn "unknown NicToolServer action: $action\n" if $self->debug;
        $response_obj->respond( $self->error_response( 500, $action ) );
    };

    # check permissions
    $error = $self->verify_obj_usage( $cmd, $client_obj->data(), $action );
    return $response_obj->respond($error) if $error;

    # create obj, call method, return response
    my $class = 'NicToolServer::' . $cmd->{class};
    my $obj   = $class->new(
        $self->{Apache}, $self->{client}, $self->{dbh},
        $self->{meta},   $self->{user}
    );
    my $method = $cmd->{method};
    warn "calling NicToolServer action: $cmd->{class}::$cmd->{method} ("
        . $action . ")\n"
        if $self->debug;
    my $res;
    eval { $res = $obj->$method( $client_obj->data() ) };
    warn "result: " . Data::Dumper::Dumper($res) if $self->debug_result;

    if ($@) {
        return $response_obj->send_error( $self->error_response( 508, $@ ) );
    }
    return $response_obj->respond($res);

    $dbh->disconnect;
}

sub ver_check {
    my $self = shift;
    #check the protocol version if included
    my $pv   = $self->{client}->protocol_version;
    return undef unless $pv;
    return $self->error_response( 510,
        "This server requires at least protocol version $NicToolServer::MIN_PROTOCOL_VERSION. You have specified protocol version $pv"
    ) if $pv lt $NicToolServer::MIN_PROTOCOL_VERSION;
    return $self->error_response( 510,
        "This server allows at most protocol version $NicToolServer::MIN_PROTOCOL_VERSION. You have specified protocol version $pv"
    ) if $pv gt $NicToolServer::MAX_PROTOCOL_VERSION;
}

sub api_commands {
    my $self = shift;
    return {

        # user API
        'get_user' => {
            'class'      => 'User',
            'method'     => 'get_user',
            'parameters' => {
                'nt_user_id' =>
                    { access => 'read', required => 1, type => 'USER' },
            },
        },
        'new_user' => {
            'class'      => 'User::Sanity',
            'method'     => 'new_user',
            'creation'   => 'USER',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
                'username'  => { required => 1 },
                'email'     => { required => 1 },
                'password'  => { required => 1 },
                'password2' => { required => 1 },
            },
        },
        'edit_user' => {
            'class'      => 'User::Sanity',
            'method'     => 'edit_user',
            'parameters' => {
                'nt_user_id' =>
                    { access => 'write', required => 1, type => 'USER' },
                'usable_nameservers' => {
                    access   => 'read',
                    type     => 'NAMESERVER',
                    list     => 1,
                    empty    => 1,
                    required => 0
                },
            },
        },
        'delete_users' => {
            'class'      => 'User',
            'method'     => 'delete_users',
            'parameters' => {
                'user_list' => {
                    access   => 'delete',
                    required => 1,
                    type     => 'USER',
                    list     => 1
                },
            },
        },
        'get_group_users' => {
            'class'      => 'User::Sanity',
            'method'     => 'get_group_users',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_user_list' => {
            'class'      => 'User::Sanity',
            'method'     => 'get_user_list',
            'parameters' => {
                'user_list' => {
                    access   => 'read',
                    required => 1,
                    type     => 'USER',
                    list     => 1
                },
            },
        },
        'move_users' => {
            'class'      => 'User::Sanity',
            'method'     => 'move_users',
            'parameters' => {
                'user_list' => {
                    access   => 'write',
                    required => 1,
                    type     => 'USER',
                    list     => 1
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_user_global_log' => {
            'class'      => 'User::Sanity',
            'method'     => 'get_user_global_log',
            'parameters' => {
                'nt_user_id' =>
                    { access => 'read', required => 1, type => 'USER' },
            },
        },

        # group API

        'get_group' => {
            'class'      => 'Group',
            'method'     => 'get_group',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'new_group' => {
            'class'      => 'Group::Sanity',
            'method'     => 'new_group',
            'creation'   => 'GROUP',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
                'name'               => { required => 1 },
                'usable_nameservers' => {
                    required => 0,
                    access   => 'read',
                    type     => 'NAMESERVER',
                    list     => 1
                },
            },
        },
        'edit_group' => {
            'class'      => 'Group::Sanity',
            'method'     => 'edit_group',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'write', required => 1, type => 'GROUP' },
                'usable_nameservers' => {
                    required => 0,
                    access   => 'read',
                    empty    => 1,
                    type     => 'NAMESERVER',
                    list     => 1
                },
            },
        },
        'delete_group' => {
            'class'      => 'Group',
            'method'     => 'delete_group',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'delete', required => 1, type => 'GROUP' },
            },
        },
        'get_group_groups' => {
            'class'      => 'Group',
            'method'     => 'get_group_groups',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_group_branch' => {
            'class'      => 'Group',
            'method'     => 'get_group_branch',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_group_subgroups' => {
            'class'      => 'Group::Sanity',
            'method'     => 'get_group_subgroups',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_global_application_log' => {
            'class'      => 'Group::Sanity',
            'method'     => 'get_global_application_log',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },

        # zone API
        'get_zone' => {
            'class'      => 'Zone',
            'method'     => 'get_zone',
            'parameters' => {
                'nt_zone_id' =>
                    { access => 'read', required => 1, type => 'ZONE' },
            },
        },

        'get_group_zones' => {
            'class'      => 'Zone::Sanity',
            'method'     => 'get_group_zones',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_group_zones_log' => {
            'class'      => 'Zone::Sanity',
            'method'     => 'get_group_zones_log',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'new_zone' => {
            'class'      => 'Zone::Sanity',
            'method'     => 'new_zone',
            'creation'   => 'ZONE',
            'parameters' => {
                'nameservers' => {
                    access   => 'read',
                    required => 0,
                    type     => 'NAMESERVER',
                    list     => 1,
                    empty    => 1
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
                'zone' => { required => 1 },
            },
        },
        'edit_zone' => {
            'class'      => 'Zone::Sanity',
            'method'     => 'edit_zone',
            'parameters' => {
                'nt_zone_id' =>
                    { 'access' => 'write', required => 1, type => 'ZONE' },
                'nameservers' => {
                    access   => 'read',
                    required => 0,
                    type     => 'NAMESERVER',
                    list     => 1,
                    empty    => 1
                },
            },
        },
        'delete_zones' => {
            'class'      => 'Zone',
            'method'     => 'delete_zones',
            'parameters' => {
                'zone_list' => {
                    access   => 'delete',
                    delegate => 'none',
                    pseudo   => 'none',
                    required => 1,
                    type     => 'ZONE',
                    list     => 1
                },
            },
        },
        'get_zone_log' => {
            'class'      => 'Zone',
            'method'     => 'get_zone_log',
            'parameters' => {
                'nt_zone_id' =>
                    { 'access' => 'read', required => 1, type => 'ZONE' },
            },
        },
        'get_zone_records' => {
            'class'      => 'Zone::Sanity',
            'method'     => 'get_zone_records',
            'parameters' => {
                'nt_zone_id' =>
                    { 'access' => 'read', required => 1, type => 'ZONE' },
            },
        },
        'move_zones' => {
            'class'      => 'Zone::Sanity',
            'method'     => 'move_zones',
            'parameters' => {
                'zone_list' => {
                    access   => 'write',
                    required => 1,
                    type     => 'ZONE',
                    list     => 1
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_zone_list' => {
            'class'      => 'Zone',
            'method'     => 'get_zone_list',
            'parameters' => {
                'zone_list' => {
                    access   => 'read',
                    required => 1,
                    type     => 'ZONE',
                    list     => 1
                },
            },
        },

        # zone_record API
        'new_zone_record' => {
            'class'      => 'Zone::Record::Sanity',
            'method'     => 'new_zone_record',
            'creation'   => 'ZONERECORD',
            'parameters' => {
                'nt_zone_id' => {
                    access   => 'read',
                    pseudo   => 'none',
                    delgate  => 'zone_perm_add_records',
                    required => 1,
                    type     => 'ZONE'
                },
                'name' => { required => 1 },

                #'ttl'=>{required=>1},
                'address' => { required => 1 },
                'type'    => { required => 1 },
            },
        },
        'edit_zone_record' => {
            'class'      => 'Zone::Record::Sanity',
            'method'     => 'edit_zone_record',
            'parameters' => {
                'nt_zone_record_id' => {
                    access   => 'write',
                    required => 1,
                    type     => 'ZONERECORD'
                },
            },
        },
        'delete_zone_record' => {
            'class'      => 'Zone::Record',
            'method'     => 'delete_zone_record',
            'parameters' => {
                'nt_zone_record_id' => {
                    access   => 'delete',
                    pseudo   => 'zone_perm_delete_records',
                    delegate => 'none',
                    required => 1,
                    type     => 'ZONERECORD'
                },
            },
        },
        'get_zone_record' => {
            'class'      => 'Zone::Record',
            'method'     => 'get_zone_record',
            'parameters' => {
                'nt_zone_record_id' =>
                    { access => 'read', required => 1, type => 'ZONERECORD' },
            },
        },
        'get_zone_record_log' => {
            'class'      => 'Zone::Sanity',
            'method'     => 'get_zone_record_log',
            'parameters' => {
                'nt_zone_id' =>
                    { access => 'read', required => 1, type => 'ZONE' },
            },
        },
        'get_zone_record_log_entry' => {
            'class'      => 'Zone::Record',
            'method'     => 'get_zone_record_log_entry',
            'parameters' => {
                'nt_zone_record_log_id' => { required => 1, id => 1 },
                'nt_zone_record_id' =>
                    { access => 'read', required => 1, type => 'ZONERECORD' },
            },
        },
        'get_record_type' => {
            'class'      => 'Zone::Record',
            'method'     => 'get_record_type',
            'parameters' => {
                    'type' => { required => 1 },
                },
        },

        # nameserver API
        'get_nameserver' => {
            'class'      => 'Nameserver',
            'method'     => 'get_nameserver',
            'parameters' => {

         #'nt_nameserver_id'=>{access=>'read',required=>1,type=>'NAMESERVER'},
                'nt_nameserver_id' => { required => 1, type => 'NAMESERVER' },
            },
        },
        'get_nameserver_tree' => {
            'result' => $self->error_response(
                503, 'get_nameserver_tree.  Use get_usable_nameservers.'
            ),
        },
        'get_usable_nameservers' => {
            'class'      => 'Nameserver',
            'method'     => 'get_usable_nameservers',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 0, type => 'GROUP' },
            },
        },
        'get_nameserver_export_types' => {
            'class'      => 'Nameserver',
            'method'     => 'get_nameserver_export_types',
            'parameters' => {
                    'type' => { required => 1 },
                },
        },
        'new_nameserver' => {
            'class'      => 'Nameserver::Sanity',
            'method'     => 'new_nameserver',
            'creation'   => 'NAMESERVER',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
                'address'       => { required => 1 },
                'name'          => { required => 1 },
                'export_format' => { required => 1 },
            },
        },
        'edit_nameserver' => {
            'class'      => 'Nameserver::Sanity',
            'method'     => 'edit_nameserver',
            'parameters' => {
                'nt_nameserver_id' => {
                    access   => 'write',
                    required => 1,
                    type     => 'NAMESERVER'
                },
            },
        },
        'delete_nameserver' => {
            'class'      => 'Nameserver',
            'method'     => 'delete_nameserver',
            'parameters' => {
                'nt_nameserver_id' => {
                    access   => 'delete',
                    required => 1,
                    type     => 'NAMESERVER'
                },
            },
        },
        'get_group_nameservers' => {
            'class'      => 'Nameserver::Sanity',
            'method'     => 'get_group_nameservers',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_nameserver_list' => {
            'class'      => 'Nameserver',
            'method'     => 'get_nameserver_list',
            'parameters' => {
                'nameserver_list' => {
                    access   => 'read',
                    required => 1,
                    type     => 'NAMESERVER',
                    list     => 1
                },
            },
        },
        'move_nameservers' => {
            'class'      => 'Nameserver::Sanity',
            'method'     => 'move_nameservers',
            'parameters' => {
                'nameserver_list' => {
                    access   => 'write',
                    required => 1,
                    type     => 'NAMESERVER',
                    list     => 1
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },

        #Permissions API
        'get_group_permissions' => {
            'class'      => 'Permission',
            'method'     => 'get_group_permissions',
            'parameters' => {
                'nt_group_id' =>
                    { access => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_user_permissions' => {
            'class'      => 'Permission',
            'method'     => 'get_user_permissions',
            'parameters' => {
                'nt_user_id' =>
                    { access => 'read', required => 1, type => 'USER' },
            },
        },
        'delegate_zones' => {
            class      => 'Permission',
            method     => 'delegate_zones',
            parameters => {
                zone_list => {
                    list     => 1,
                    access   => 'delegate',
                    delegate => 'perm_delegate',
                    pseudo   => 'none',
                    required => 1,
                    type     => 'ZONE'
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'delegate_zone_records' => {
            'class'      => 'Permission',
            'method'     => 'delegate_zone_records',
            'parameters' => {
                'zonerecord_list' => {
                    list     => 1,
                    access   => 'delegate',
                    delegate => 'perm_delegate',
                    pseudo   => 'none',
                    required => 1,
                    type     => 'ZONERECORD'
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'edit_zone_delegation' => {
            'class'      => 'Permission',
            'method'     => 'edit_zone_delegation',
            'parameters' => {
                'nt_zone_id' => {
                    access   => 'delegate',
                    delegate => 'none',
                    pseudo   => 'none',
                    required => 1,
                    type     => 'ZONE'
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'edit_zone_record_delegation' => {
            'class'      => 'Permission',
            'method'     => 'edit_zone_record_delegation',
            'parameters' => {
                'nt_zone_record_id' => {
                    access   => 'delegate',
                    delegate => 'none',
                    pseudo   => 'none',
                    required => 1,
                    type     => 'ZONERECORD'
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'delete_zone_delegation' => {
            'class'      => 'Permission',
            'method'     => 'delete_zone_delegation',
            'parameters' => {
                'nt_zone_id' => {
                    access   => 'delegate',
                    delegate => 'perm_delete',
                    pseudo   => 'none',
                    required => 1,
                    type     => 'ZONE'
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'delete_zone_record_delegation' => {
            'class'      => 'Permission',
            'method'     => 'delete_zone_record_delegation',
            'parameters' => {
                'nt_zone_record_id' => {
                    access   => 'delegate',
                    delegate => 'perm_delete',
                    pseudo   => 'none',
                    required => 1,
                    type     => 'ZONERECORD'
                },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_delegated_zones' => {
            'class'      => 'Permission',
            'method'     => 'get_delegated_zones',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_delegated_zone_records' => {
            'class'      => 'Permission',
            'method'     => 'get_delegated_zone_records',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'get_zone_delegates' => {
            'class'      => 'Permission',
            'method'     => 'get_zone_delegates',
            'parameters' => {
                'nt_zone_id' =>
                    { access => 'read', required => 1, type => 'ZONE' },
            },
        },
        'get_zone_record_delegates' => {
            'class'      => 'Permission',
            'method'     => 'get_zone_record_delegates',
            'parameters' => {
                'nt_zone_record_id' =>
                    { access => 'read', required => 1, type => 'ZONERECORD' },
            },
        },
    };
}

sub error_response {
    my ( $self, $code, $msg ) = @_;
    my $errs = {
        200 => 'OK',
        201 => 'Warning',

        #data error
        300 => 'Sanity error',
        301 => 'Required parameters missing',
        302 => 'Some parameters were invalid',

        #logical error
        403 => 'Invalid Username and/or password',

        #403=>'You are trying to access an object outside of your tree',
        404 => 'Access Permission denied',

        #405=>'Delegation Permission denied: ',
        #406=>'Creation Permission denied: ',
        #407=>'Delegate Access Permission denied: ',

        #transport/com error
        500 => 'Request for unknown action',
        501 => 'Data transport Content-Type not supported',
        502 => 'XML-RPC Parse Error',
        503 => 'Method has been deprecated',
        505 => 'SQL error',
        507 => 'Internal consistency error',
        508 => 'Internal Error',
        510 => 'Incorrect Protocol Version',

        #failure
        600 => 'Failure',
        601 => 'Object Not Found',

        #601=>'Group has no permissions',
        #602=>'User has no permissions',
        #603=>'The delegation already exists',
        #604=>'No such delegation exists',
        #610=>'Group not found',
        700 => 'Unknown Error',
    };
    $code ||= 700;
    $msg = join( ":", caller ) if $code == 700;

    my $res = {
        'error_code' => $code,
        'error_msg'  => $msg,
        'error_desc' => $errs->{$code}
    };
    return $res;
}

sub is_error_response {
    my ( $self, $data ) = @_;
    return ( !exists $data->{error_code} or $data->{error_code} != 200 );
}

sub error {
    my ($self, $type, $message) = @_;
    $self->{errors}{$type}++ if $type;
    push @{ $self->{error_messages} }, $message;
};

sub verify_required {
    my ( $self, $req, $data ) = @_;
    my @missing;

    foreach my $p ( @{$req} ) {

        # must exist and be a integer
        push( @missing, $p ) if !exists $data->{$p};
        push( @missing, $p ) unless ( $data->{$p} || $data->{$p} == 0 );
        foreach ( split( /,/, $data->{$p} ) ) {
            push( @missing, $p ) unless ( $self->valid_integer($_) );
        }
    }
    return 0 unless (@missing);

    return $self->error_response( 301, join( " ", @missing ) );

}

sub get_group_id {
    my ( $self, $key, $id, $type ) = @_;
    my $sql;
    my $rid = '';
    if ( $key eq 'nt_group_id' or uc($type) eq 'GROUP' ) {
        $sql = "SELECT parent_group_id FROM nt_group WHERE nt_group_id = ?";
        my $ids = $self->exec_query( $sql, $id );
        my $rid = $ids->[0]->{parent_group_id};
        $rid = 1 if $rid eq 0;
    }
    elsif ( $key eq 'nt_zone_id' or uc($type) eq 'ZONE' ) {
        $sql = "SELECT nt_group_id FROM nt_zone WHERE nt_zone_id = ?";
        my $ids = $self->exec_query( $sql, $id );
        $rid = $ids->[0]->{nt_group_id} if $ids;
    }
    elsif ( $key eq 'nt_zone_record_id' or uc($type) eq 'ZONERECORD' ) {
        $sql
            = "SELECT nt_zone.nt_group_id FROM nt_zone_record,nt_zone "
            . "WHERE nt_zone_record.nt_zone_record_id = ? "
            . "AND nt_zone.nt_zone_id=nt_zone_record.nt_zone_id";
        my $ids = $self->exec_query( $sql, $id );
        $rid = $ids->[0]->{nt_group_id} if $ids;
    }
    elsif ( $key eq 'nt_nameserver_id' or uc($type) eq 'NAMESERVER' ) {
        $sql = "SELECT nt_group_id FROM nt_nameserver "
            . "WHERE nt_nameserver_id = ?";
        my $ids = $self->exec_query( $sql, $id );
        $rid = $ids->[0]->{nt_group_id} if $ids;
    }
    elsif ( $key eq 'nt_user_id' or uc($type) eq 'USER' ) {
        $sql = "SELECT nt_group_id FROM nt_user WHERE nt_user_id = ?";
        my $ids = $self->exec_query( $sql, $id );
        $rid = $ids->[0]->{nt_group_id} if $ids;
    }

    #warn "returning ID $rid";
    return $rid;
}

sub get_group_permissions {
    my ( $self, $groupid ) = @_;
    my $sql
        = "SELECT * FROM nt_perm WHERE nt_group_id=? AND nt_user_id=0 AND deleted!=1";
    my $perms = $self->exec_query( $sql, $groupid );
    return $perms->[0];
}

sub get_user_permissions {
    my ( $self, $userid ) = @_;
    my $sql
        = "SELECT * FROM nt_perm WHERE nt_group_id=0 AND nt_user_id=? AND deleted!=1";
    my $perms = $self->exec_query( $sql, $userid );
    return $perms->[0];
}

sub get_access_permission {

    # return 1 if user has $access permissions on the object $id of type $type, else 0
    my ( $self, $type, $id, $access ) = @_;
    warn "##############################\nget_access_permission ("
        . join( ",", caller )
        . ")\n##############################\n"

        #"      params: ".Data::Dumper::Dumper($params).""
        if $self->debug_permissions;
    my @error = $self->check_permission( '', $id, $access, $type );

    #warn "get_access_permission: @error returning " . ( $error[0] ? 0 : 1 );
    return $error[0] ? 0 : 1;
}

sub check_permission {
    my ($self,   $key,      $id,       $access, $type,
        $islist, $creation, $delegate, $pseudo
    ) = @_;

    #my $access = $api->{parameters}{$key}{access};
    #my $creation = $api->{creation};

    my $user_id  = $self->{user}{nt_user_id};
    my $group_id = $self->{user}{nt_group_id};
    my $obj_group_id
        = $type =~ /group/i ? $id : $self->get_group_id( $key, $id, $type );

    my $group_ok = $self->group_usage_ok($obj_group_id);

    my $permissions = $self->{user};

    my $debug
        = "key:$key,id:$id,type:$type,access:$access,creation:$creation,obj_group_id:$obj_group_id,group_ok:$group_ok,delegate:$delegate,pseudo:$pseudo:("
        . join( ",", caller ) . ")";

    #check creation
    if ($creation) {
        unless ( $permissions->{ lc $creation . "_create" } ) {
            warn "NO creation of $creation. $debug"
                if $self->debug_permissions;
            return ( '404', "Not allowed to create new " . lc $creation );
        }
        else {
            warn "ALLOW creation of $creation." if $self->debug_permissions;
        }
    }

    #user access
    if ( $type eq 'USER' and $id eq $user_id ) {

        #self read always true, delete false.
        $self->set_param_meta( $key, self => 1 );
        if ( $access eq 'write' ) {
            if ( $permissions->{"self_write"} ) {
                warn "YES self write. $debug" if $self->debug_permissions;
                return undef;
            }
            else {
                warn "NO self write. $debug" if $self->debug_permissions;
                return ( '404', "Not allowed to modify self" );
            }
        }
        elsif ( $access eq 'delete' ) {
            warn "NO self delete access. $debug" if $self->debug_permissions;
            return ( '404', "Not allowed to delete self" );
        }
    }

    # can't delete your own group
    if ( $type eq 'GROUP' and $id eq $group_id ) {

        # not allowed to delete or edit your own group
        $self->set_param_meta( $key, selfgroup => 1 );
        if ( $access eq 'delete' ) {
            warn "NO self group delete. $debug" if $self->debug_permissions;
            return ( '404', "Not allowed to delete your own group" );
        }
        elsif ( $access eq 'write' ) {
            warn "NO self group write. $debug" if $self->debug_permissions;
            return ( '404', "Not allowed to edit your own group" );
        }
    }

    # allow "publish" access to usable nameservers (when modifying/creating a zone)
    if ( $type eq 'NAMESERVER' and $access eq 'read' ) {
        my %usable_ns = map { $_ => 1 } split /,/, $permissions->{usable_ns};
        if ( $usable_ns{$id} ) {
            warn "YES usable nameserver: $debug" if $self->debug_permissions;
            return undef;
        }
    }

    if ($group_ok) {
        warn "OWN" if $self->debug_permissions;
        $self->set_param_meta( $islist ? "$key:$id" : $key, own => 1 );
        if ( $access ne 'read' ) {
            unless ( $permissions->{ lc $type . "_$access" } ) {
                warn "NO $access access for $type. $debug"
                    if $self->debug_permissions;
                return ( '404',
                          "You have no '$access' permission for "
                        . lc $type
                        . " objects" );
            }
            else {
                warn "YES $access access for $type. $debug"
                    if $self->debug_permissions;
                return undef;
            }
        }
    }
    else {

        #now we check access permissions for the delegated object
        my $del = $self->get_delegate_access( $id, $type );
        if ($del) {
            $self->set_param_meta( $islist ? "$key:$id" : $key,
                delegate => $del );
            if ( $del->{pseudo} and $pseudo ) {
                if ( $pseudo eq 'none' ) {
                    warn "NO pseudo '$pseudo': $debug"
                        if $self->debug_permissions;
                    return ( '404',
                        "You have no '$access' permission for the delegated object"
                    );

                }
                elsif ( $del->{$pseudo} ) {
                    warn "YES pseudo '$pseudo': $debug"
                        if $self->debug_permissions;
                    return undef;
                }
                else {
                    warn "NO pseudo '$pseudo': $debug"
                        if $self->debug_permissions;
                    return ( '404',
                        "You have no '$access' permission for the delegated object"
                    );
                }
            }
            elsif ($delegate) {
                if ( $delegate eq 'none' ) {
                    warn "NO delegate '$delegate' '$access': $debug"
                        if $self->debug_permissions;
                    return ( '404',
                        "You have no '$access' permission for the delegated object"
                    );
                }
                elsif ( $del->{$delegate} ) {
                    warn "YES delegate '$delegate' '$access': $debug"
                        if $self->debug_permissions;
                    return undef;
                }
                else {
                    warn "NO delegate '$delegate' '$access': $debug"
                        if $self->debug_permissions;
                    return ( '404',
                        "You have no '$access' permission for the delegated object"
                    );

                }
            }
            elsif ( $access ne 'read' ) {
                if ( !$del->{"perm_$access"} ) {
                    warn "NO delegate '$access': $debug"
                        if $self->debug_permissions;

                    #warn Data::Dumper::Dumper($del);
                    return ( '404',
                        "You have no '$access' permission for the delegated object"
                    );
                }
                else {

                    #warn Data::Dumper::Dumper($del);
                    warn "YES delegate '$access': $debug"
                        if $self->debug_permissions;
                }
            }
            else {
                warn "YES delegate read: $debug" if $self->debug_permissions;
            }
        }
        else {
            warn "NO access: $debug" if $self->debug_permissions;
            return ( '404',
                "No Access Allowed to that object ($type : $id)" );
        }
    }

    warn "YES fallthrough: $debug" if $self->debug_permissions;

    return undef;
}

sub get_delegate_access {
    my ( $self, $id, $type ) = @_;
    my $user_id  = $self->{user}{nt_user_id};
    my $group_id = $self->{user}{nt_group_id};

    #check delegation

    #XXX if we delegate more than just zones/zonerecords do something here:
    my %tables = ( ZONE => 'nt_zone' );
    my %fields = ( ZONE => 'nt_zone_id' );

    return undef unless $type eq 'ZONE' or $type eq 'ZONERECORD';
    my $sql;
    if ( $type eq 'ZONERECORD' ) {
        return $self->get_zonerecord_delegate_access( $id, $type );
    }
    else {
        $sql
            = "SELECT nt_delegate.*,nt_group.name AS group_name FROM nt_delegate "
            . " INNER JOIN $tables{$type} on $tables{$type}.$fields{$type} = nt_delegate.nt_object_id AND nt_delegate.nt_object_type='$type'"
            . " INNER JOIN nt_group on $tables{$type}.nt_group_id = nt_group.nt_group_id"
            . " WHERE nt_delegate.nt_group_id=? AND nt_delegate.nt_object_id=? AND nt_delegate.nt_object_type=?";
        my $r = $self->exec_query( $sql, [ $group_id, $id, $type ] );
        my $auth_data = $r->[0];

    #warn "Auth data: ".Data::Dumper::Dumper($auth_data) if $self->debug_permissions;
        if ( !$auth_data && $type eq 'ZONE' ) {

    #see if any records in the zone are delegated, if so then read access is allowed
            $sql
                = "SELECT count(*) AS count,nt_group.name AS group_name FROM nt_delegate "
                . " INNER JOIN nt_zone_record on nt_zone_record.nt_zone_record_id = nt_delegate.nt_object_id AND nt_delegate.nt_object_type='ZONERECORD'"
                . " INNER JOIN nt_zone on nt_zone.nt_zone_id = nt_zone_record.nt_zone_id"
                . " INNER JOIN nt_group on nt_delegate.nt_group_id = nt_group.nt_group_id"
                . " WHERE nt_delegate.nt_group_id=? AND nt_zone.nt_zone_id=? "
                . " GROUP BY nt_zone.zone";
            my $r = $self->exec_query( $sql, [ $group_id, $id ] );
            my $result = $r->[0];

            if ( $result && $result->{count} gt 0 ) {
                return +{
                    pseudo                     => 1,
                    'perm_write'               => 0,
                    'perm_delete'              => 0,
                    'perm_delegate'            => 0,
                    'zone_perm_add_records'    => 0,
                    'zone_perm_delete_records' => 0,
                    'group_name'               => $result->{group_name},
                };
            }

        }
        return $auth_data;
    }
}

sub get_zonerecord_delegate_access {
    my ( $self, $id, $type ) = @_;
    my $user_id  = $self->{user}{nt_user_id};
    my $group_id = $self->{user}{nt_group_id};

    #check delegation
    my $sql
        = "SELECT nt_delegate.*,nt_group.name AS group_name FROM nt_delegate "
        . " INNER JOIN nt_zone_record on nt_zone_record.nt_zone_record_id= nt_delegate.nt_object_id AND nt_delegate.nt_object_type='ZONERECORD'"
        . " INNER JOIN nt_zone on nt_zone.nt_zone_id=nt_zone_record.nt_zone_id"
        . " INNER JOIN nt_group on nt_zone.nt_group_id = nt_group.nt_group_id"
        . " WHERE nt_delegate.nt_group_id=? AND nt_delegate.nt_object_id=? AND nt_delegate.nt_object_type='ZONERECORD'";

    my $r = $self->exec_query( $sql, [ $group_id, $id ] );
    return $r->[0] if $r->[0];

    $sql
        = "SELECT nt_delegate.*, 1 AS pseudo, nt_group.name AS group_name FROM nt_delegate "
        . " INNER JOIN nt_zone on nt_zone.nt_zone_id=nt_delegate.nt_object_id AND nt_delegate.nt_object_type='ZONE'"
        . " INNER JOIN nt_zone_record on nt_zone_record.nt_zone_id= nt_zone.nt_zone_id"
        . " INNER JOIN nt_group on nt_zone.nt_group_id = nt_group.nt_group_id"
        . " WHERE nt_zone_record.nt_zone_record_id=?";
    $r = $self->exec_query( $sql, $id );
    return $r->[0];
}

sub verify_obj_usage {
    my ( $self, $api, $data, $cmd ) = @_;

    my @error;
    return $api->{result} if exists $api->{result};
    my $params = $api->{parameters};

    warn "##############################\n$cmd VERIFY OBJECT USAGE\n##############################\n"

        #"      params: ".Data::Dumper::Dumper($params).""
        if $self->debug_permissions;

    #verify that required parameters are present
    my @missing;
    foreach my $p ( grep { $$params{$_}->{required} } keys %$params ) {

        #warn "parameter $p exists:".exists $data->{$p};
        if ( ( !exists $data->{$p} ) or ( $data->{$p} eq '' ) ) {
            push @missing, $p;
        }
        elsif ( $$params{$p}->{list} ) {

            #warn "got list in call ".Data::Dumper::Dumper($data);
            if ( ref $data->{$p} eq 'ARRAY' ) {
                foreach ( @{ $data->{$p} } ) {
                    if ( $_ eq '' ) {
                        push( @missing, $p );
                        last;
                    }
                }
                $data->{$p} = join( ",", @{ $data->{$p} } );
            }
            else {
                my @blah = split( /,/, $data->{$p} );
                foreach (@blah) {
                    if ( $_ eq '' ) {
                        push( @missing, $p );
                        last;
                    }
                }
                push( @missing, $p ) unless @blah;
            }
        }
    }
    if (@missing) {
        return $self->error_response( 301, join( " ", @missing ) );
    }
    my @invalid;
    foreach my $p (
        grep { exists $data->{$_} and $$params{$_}->{type} }
        keys %$params
        )
    {
        next
            if $$params{$p}->{empty}
                and ( !defined $data->{$p} or $data->{$p} eq '' );   #empty ok
            #warn "data is ".Data::Dumper::Dumper($data->{$p});
            #warn "checking value of $p.  is list? ".$$params{$p}->{list};
        if ( $$params{$p}->{list} ) {
            if ( ref $data->{$p} eq 'ARRAY' ) {

          #warn "got array ref $p in call ".Data::Dumper::Dumper($data->{$p});
                foreach ( @{ $data->{$p} } ) {
                    if ( !$self->valid_id($_) ) {
                        push( @invalid, $p );
                        last;
                    }
                }
                $data->{$p} = join( ",", @{ $data->{$p} } );
            }
            else {
                my @blah = split( /,/, $data->{$p} );
                foreach (@blah) {
                    if ( !$self->valid_id($_) ) {
                        push( @invalid, $p );
                        last;
                    }
                }
                push( @invalid, $p ) unless @blah;
            }

            #warn "list $p is now ".Data::Dumper::Dumper($data->{$p});
        }
        else {
            push @invalid, $p unless $self->valid_id( $data->{$p} );
        }
    }
    if (@invalid) {
        return $self->error_response( 302, join( " ", @invalid ) );
    }

    #verify that appropriate permission level is available for all objects
    foreach my $f (
        grep { exists $data->{$_} and $$params{$_}->{type} }
        keys %$params
        )
    {

        next unless $$params{$f}->{access};
        my $type = $$params{$f}->{type};

        #if($type=~s/^parameters://){
        #$type=$data->{$type};
        #}
        if ( $$params{$f}->{list} ) {
            if ( ref $data->{$f} eq 'ARRAY' ) {
                $data->{$f} = join( ",", @{ $data->{$f} } );
            }
            my @items = split( /,/, $data->{$f} );
            foreach my $i (@items) {
                @error = $self->check_permission(
                    $f,
                    $i,
                    $api->{parameters}{$f}{access},
                    $type,
                    1,
                    $api->{creation},
                    $$params{$f}->{delegate},
                    $$params{$f}->{pseudo}
                );

                #warn @error if defined $error[0];
                last if defined $error[0];
            }
            last if defined $error[0];
        }
        else {
            @error = $self->check_permission(
                $f,
                $data->{$f},
                $api->{parameters}{$f}{access},
                $type,
                0,
                $api->{creation},
                $$params{$f}->{delegate},
                $$params{$f}->{pseudo}
            );
        }

        warn "ERROR: " . join( " ", @error )
            if $error[0] && $self->debug_permissions;
        return $self->error_response(@error) if $error[0];
    }
    return $error[0] ? $self->error_response(@error) : 0;
}

sub get_param_meta {
    my ($self, $param, $key) = @_;
    #gets keyed data for a certain parameter of the function call

    #warn Data::Dumper::Dumper($self->{meta});
    return $self->{meta}{$param}{$key};
}

sub set_param_meta {
    my ($self, $param, $key, $value) = @_;
    #Sets keyed info about a parameter for the function call

    #warn "setting param meta: param $param, key $key, value $value";
    #$self->{meta}={} unless exists $self->{meta};
    $self->{meta}{$param} = {} unless exists $self->{meta}{$param};
    $self->{meta}{$param}{$key} = $value;

#warn "final param meta: param $param, key $key, value ".Data::Dumper::Dumper($self->{meta});;
}

sub valid_id {
    my ( $self, $id ) = @_;
    return ( $id + 0 ne '0' ) && ( $self->valid_integer($id) );
}

sub valid_integer {
    my ( $self, $int ) = @_;

    #warn "checking integer: $int";
    return !1 unless $int =~ /^\d+$/;
    return !1 unless $int < 4500000000;
    return !1 unless $int >= 0;

    return 1;
}

sub valid_16bit_int {
    my ( $self, $type, $value ) = @_;

    my $rc = 1;

    if ( $value eq '' ) {
        $self->error( $type, "$type is required." );
        $rc = 0;
    }

    #   check for non-digits
    if ( $value =~ /\D/ ) {
        $self->error( $type, "Non-numeric digits are not allowed. ($value)" );
        $rc = 0;
    }

    #   make sure it is >= 0 and < 65536
    if ( $value < 0 || $value > 65535 ) {
        $self->error( $type, "$type must be a 16bit integer (in the range 0-65535)" );
        $rc = 0;
    }

    return $rc;
}

sub valid_ip_address {
    my ( $self, $ip ) = @_;

    # IPv6 addresses have colons
    return 1 if $ip =~ m/:/ && Net::IP::ip_is_ipv6($ip) == 1;

    return 0 if grep( /\./, split( //, $ip ) ) != 3;    # need 3 dots

    my @x = split( /\./, $ip );
    return 0 unless @x == 4;                            # need 4 nums

    return 0 unless $x[0] > 0;

    return 0 if 0 + $x[0] + $x[1] + $x[2] + $x[3] == 0; # 0.0.0.0 invalid
    return 0 if grep( $_ eq '255', @x ) == 4;    #255.255.255.255 invalid

    foreach (@x) {
        return 0 unless /^\d{1,3}$/ && $_ >= 0 && $_ <= 255;
        $_ = 0 + $_;   # convert strings to integers
    }

    return join '.', @x;
}

sub valid_ttl {
    my $self = shift;
    my $ttl = shift;

    if ( ! defined $ttl ) {
        $self->error( 'ttl', "Invalid TTL -- required" );
        return;
    };
    if ( $ttl =~ /\D/ ) {
        $self->error( 'ttl', "Invalid TTL -- must be numeric" );
        return;
    };

    return 1 if ( $ttl >= 0 && $ttl <= 2147483647 );
# Clarifications to the DNS specification: http://tools.ietf.org/html/rfc2181
# valid TTL is unsigned number from 0 to 2147483647

    $self->error( 'ttl', "Invalid TTL -- valid ttl range is 0 to 2,147,483,647: RFC 2181" );
    return;
};

sub group_usage_ok {
    my ( $self, $id ) = @_;

    my $user = $self->{user};
    my $res  = 0;
    if (   $user->{nt_group_id} == $id
        || $self->is_subgroup( $user->{nt_group_id}, $id ) )
    {
        $res = 1;
    }
    warn
        "::::group_usage_ok: $id subgroup of group $user->{nt_group_id} ? : $res"
        if $self->debug_permissions;
    return $res;
}

sub get_group_map {
    my ( $self, $top_group_id, $groups ) = @_;

    my %map;

    my @blah = @{$groups};
    if ( $#blah == -1 ) {
        warn
            "\n\nuhh, param passed, but nothing in it. get_group_map needs top_group_id + group list arrray for IN clause.\n";
        warn
            "this only happens when there are no groups within a zone? I think.. --ai\n\n\n";
        return \%map;
    }

    my $sql
        = "SELECT nt_group.name, nt_group.nt_group_id, nt_group_subgroups.nt_subgroup_id "
        . "FROM nt_group, nt_group_subgroups "
        . "WHERE nt_group_subgroups.nt_subgroup_id IN("
        . join( ',', @$groups ) . ") "
        . "AND nt_group.nt_group_id = nt_group_subgroups.nt_group_id "
        . "AND nt_group.deleted=0 "
        . "ORDER BY nt_group_subgroups.nt_subgroup_id, nt_group_subgroups.rank DESC";

    my $subgroups = $self->exec_query($sql);

    if ($subgroups) {
        my $skipping = 0;

        foreach my $r (@$subgroups) {

            if ( $r->{nt_group_id} == $top_group_id ) {
                $skipping = $r->{nt_subgroup_id};
            }
            elsif ( $r->{nt_subgroup_id} == $top_group_id ) {
                next;
            }
            elsif ($skipping) {
                if ( $skipping != $r->{nt_subgroup_id} ) {
                    $skipping = 0;
                }
                else {
                    next;
                }
            }

            unshift( @{ $map{ $r->{nt_subgroup_id} } }, $r );
        }
    }

    return \%map;
}

sub get_subgroup_ids {
    my ( $self, $nt_group_id ) = @_;

    my $sql = "SELECT nt_subgroup_id FROM nt_group_subgroups "
        . " WHERE nt_group_id = ?";
    my $subgroups = $self->exec_query( $sql, $nt_group_id );

    my @list;
    foreach (@$subgroups) { push( @list, $_->{nt_subgroup_id} ); }
    return \@list;
}

sub get_parentgroup_ids {
    my ( $self, $nt_group_id ) = @_;

    my $sql
        = "SELECT nt_group_id FROM nt_group_subgroups WHERE nt_subgroup_id = ?";
    my $subgroups = $self->exec_query( $sql, $nt_group_id );

    my @list;
    foreach (@$subgroups) { push( @list, $_->{nt_group_id} ); }
    return \@list;
}

sub is_subgroup {
    my ( $self, $nt_group_id, $gid ) = @_;

    my $sql = "SELECT COUNT(*) AS count
    FROM nt_group_subgroups WHERE nt_group_id = ?
         AND nt_subgroup_id = ?";
    my $subgroups = $self->exec_query( $sql, [ $nt_group_id, $gid ] )
        or return 0;
    return $subgroups->[0]->{count} ? 1 : 0;
}

sub get_group_branches {
    my ( $self, $nt_group_id ) = @_;
    my @groups;
    my $nextgroup = $nt_group_id;
    while ($nextgroup) {
        my $sql
            = "SELECT parent_group_id FROM nt_group WHERE nt_group_id = ?";
        my $ids = $self->exec_query( $sql, $nextgroup );
        unshift @groups, $nextgroup if $ids->[0];
        $nextgroup = $ids->[0]->{parent_group_id};
    }
}

sub get_option {
    my ($self, $option) = @_;

    my $refs = $self->exec_query(
        "SELECT option_value FROM nt_options WHERE option_name=?",
        [$option],
    );
    return if ! scalar @$refs;
    return $refs->[0]{option_value};
};

sub dbh {

    #warn Data::Dumper::Dumper(\@_);
    my ( $self, $dsn ) = @_;
    if ( !$dsn || $dsn !~ /^DBI/ ) {
        $dsn = $NicToolServer::dsn or die "missing DSN!";
    }

    my $dbh
        = DBI->connect( $dsn, $NicToolServer::db_user,
        $NicToolServer::db_pass )
        or die "unable to connect to database: " . $DBI::errstr . "\n";

    return $dbh;
}

sub dbix {
    my $self = shift;
    return $self->{dbix} if $self->{dbix};
    $self->{dbix} = DBIx::Simple->connect( $self->{dbh} )
        or die DBIx::Simple->error;
    return $self->{dbix};
}

sub escape {
    my ( $self, $toencode ) = @_;
    $toencode =~ s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
    return $toencode;
}

sub exec_query {
    my $self = shift;
    my ( $query, $params, $extra ) = @_;

    my @caller = caller;
    my $err = sprintf( "exec_query called by %s, %s\n", $caller[0], $caller[2] );
    $err .= "\t$query\n\t";

    die "invalid arguments to exec_query! ($err)" if $extra;

    my @params;
    if ( defined $params ) {    # dereference $params into @params
        @params = ref $params eq 'ARRAY' ? @$params : $params;
        $err .= join( ', ', @params ) . "\n";
    }

    warn $err if $self->debug_sql;

    my $dbix = DBIx::Simple->connect( $self->{dbh} )
        or die DBIx::Simple->error;

    if ( $query =~ /^(REPLACE|INSERT) INTO/ ) {
        my ($table) = $query =~ /(?:REPLACE|INSERT) INTO (\w+)[\s\(]/;
        eval { $dbix->query( $query, @params ); };
        if ( $@ or $dbix->error ne 'DBI error: ' ) {
            warn $err . $dbix->error; # if $self->debug_sql;
            return;
        }
        return $dbix->last_insert_id( undef, undef, $table, undef );

        # don't test the value of last_insert_id. If the table doesn't have an
        # autoincrement field, the value is always zero
    }
    elsif ( $query =~ /^DELETE|UPDATE/ ) {
        eval { $dbix->query( $query, @params ) };
        if ( $@ or $dbix->error ne 'DBI error: ' ) {
            warn $err . $dbix->error; # if $self->debug_sql;
            return;
        }
        return $dbix->query("SELECT ROW_COUNT()")->list;
    }

    if ( $query !~ /^[\s+]?SELECT/ ) {
        warn "no support for this query. I'll try anyway\n$err";
    };

    my $r;
    eval { $r = $dbix->query( $query, @params )->hashes; };
    warn "$err\t$@\n$query" if $@;    #&& $self->debug_sql );
    warn $err . $dbix->error if $dbix->error ne 'DBI error: ';
    return $r;
}

sub check_object_deleted {
    my ( $self, $otype, $oid ) = @_;
    my %map = (
        zone => { table => 'nt_zone', field => 'nt_zone_id' },
        zonerecord =>
            { table => 'nt_zone_record', field => 'nt_zone_record_id' },
        nameserver =>
            { table => 'nt_nameserver', field => 'nt_nameserver_id' },
        group => { table => 'nt_group', field => 'nt_group_id' },
        user  => { table => 'nt_user',  field => 'nt_user_id' },
    );

    if ( my $dbst = $map{ lc($otype) } ) {
        my $sql
            = "SELECT deleted FROM $dbst->{table} WHERE $dbst->{field} = ?";
        my $deletes = $self->exec_query( $sql, $oid );
        return $deletes->[0]->{deleted} if $deletes->[0];
    }
}

sub get_title {
    my ( $self, $otype, $oid ) = @_;
    my $sql;
    if ( $otype =~ /^zone$/i ) {
        $sql = "SELECT zone AS title FROM nt_zone WHERE nt_zone_id = ?";
    }
    elsif ( $otype =~ /^zonerecord$/i ) {
        $sql
            = "SELECT CONCAT(nt_zone_record.name,'.',nt_zone.zone) AS title FROM nt_zone_record"
            . " INNER JOIN nt_zone on nt_zone_record.nt_zone_id=nt_zone.nt_zone_id"
            . " WHERE nt_zone_record.nt_zone_record_id = ?";
    }
    elsif ( $otype =~ /^nameserver$/i ) {
        $sql
            = "SELECT CONCAT(address,' (',name,')') AS title FROM nt_nameserver"
            . " WHERE nt_nameserver_id = ?";
    }
    elsif ( $otype =~ /^group$/i ) {
        $sql = "SELECT name AS title FROM nt_group WHERE nt_group_id = ?";
    }
    elsif ( $otype =~ /^user$/i ) {
        $sql
            = "SELECT CONCAT(username,' (',first_name,' ',last_name,')') AS title FROM nt_user"
            . " WHERE nt_user_id = ?";
    }
    else {
        return "($otype)";
    }

    my $titles = $self->exec_query( $sql, $oid );
    return "($otype)" if !$titles;
    return $titles->[0]->{title};
}

sub diff_changes {
    my ( $self, $data, $prev_data ) = @_;
    my @changes;

    my %perms =

    #map {$a=$_;local $_=$a; s/_/ /g;s/names/n s/g;s/zoner/z r/g;s/deleg/d g/g;s/(\S)\S+/$1/g;s/\s//g; ($a=>$_)} qw(user_create user_can_delegate user_delete user_write group_create group_delegate group_delete group_write zone_create zone_delegate zone_delete zone_write zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write nameserver_create nameserver_delegate nameserver_delete nameserver_write self_write);
        (
        'zonerecord_create'   => 'ZRC',
        'group_write'         => 'GW',
        'user_write'          => 'UW',
        'zone_delegate'       => 'ZDG',
        'nameserver_delete'   => 'NSD',
        'zone_create'         => 'ZC',
        'group_delete'        => 'GD',
        'zonerecord_delete'   => 'ZRD',
        'user_create'         => 'UC',
        'self_write'          => 'SW',
        'nameserver_write'    => 'NSW',
        'zone_delete'         => 'ZD',
        'zonerecord_write'    => 'ZRW',
        'nameserver_create'   => 'NSC',
        'user_delete'         => 'UD',
        'zonerecord_delegate' => 'ZRDG',
        'zone_write'          => 'ZW',
        'group_create'        => 'GC'
        );

    foreach my $f ( keys %$prev_data ) {
        next if ! exists $data->{$f};
        next if $data->{$f} eq $prev_data->{$f};

        if ( $f eq 'description' || $f eq 'password' ) {
            # description field is long & not critical
            push @changes, "changed $f";
        }
        elsif ( exists $perms{$f} ) {
            push @changes, qq[changed $perms{$f} from '$prev_data->{$f}' to '$data->{$f}'];
        }
        else {
            push @changes, "changed $f from '$prev_data->{$f}' to '$data->{$f}'";
        }
    }
    if ( ! scalar @changes ) {
        push @changes, "nothing modified";
    }
    return join( ", ", @changes );
}

sub throw_sanity_error {
    my $self = shift;
    my $res = $self->error_response( 300,
        join( " AND ", @{ $self->{error_messages} } ) );
    $res->{sanity_err} = $self->{errors};
    $res->{sanity_msg} = $self->{error_messages};
    return $res;
}

sub format_search_conditions {
    my ( $self, $data, $field_map ) = @_;

    my @conditions = $self->get_advanced_search_conditions( $data, $field_map );
    push @conditions, $self->get_quick_search_conditions( $data, $field_map );
    return \@conditions;
};

sub get_quick_search_conditions {
    my ($self, $data, $field_map ) = @_;

    return if ! $data->{quick_search};

    my $dbh = $self->{dbh};
    my $value = $dbh->quote( $data->{search_value} );

    my @conditions;
    my $x = 1;
    foreach my $key ( keys %$field_map ) {
        next if ! $field_map->{$key}->{quicksearch};
        my $s = $x++ == 1 ? ' ' : ' OR ';
        $s .= $field_map->{$key}->{field};

        if ( $data->{exact_match} ) {
            $s .= ' = ';
        }
        else {
            $s .= ' LIKE ';
            $value =~ s/^'/'%/;
            $value =~ s/'$/%'/;
        };

        $s .= $value;
        push @conditions, $s;
    }
    return @conditions;
}

sub get_advanced_search_conditions {
    my ( $self, $data, $field_map ) = @_;

    return if ! $data->{Search};
    my $dbh = $self->{dbh};
    my @conditions;

    for my $i ( 1 .. 5 ) {
        my $field  = $i . '_field';
        my $option = $i . '_option';
        my $value  = $i . '_value';

        next unless $data->{ $field };
        $data->{ $option } = 'CONTAINS' if ! exists $data->{ $option };

        my $cond = $i == 1 ? '' : uc( $data->{ $i . '_inclusive' } ) . ' ';
        $cond .= $field_map->{ $data->{ $field } }->{field};

        my $qv = $dbh->quote( $data->{ $value } );
        my $ucopt = uc( $data->{ $option } );

        if ( $field_map->{ $data->{ $field } }->{timefield} ) {
            if ( $ucopt =~ /^(?:EQUALS|CONTAINS|STARTS|ENDS)/ ) {
                $cond .= $data->{ $option } . "UNIX_TIMESTAMP( $qv )";
            }
            else {
                $cond .= "=UNIX_TIMESTAMP( $qv )";
            };
        }
        elsif ( $ucopt eq 'EQUALS' ) {
            $cond .= "=$qv";
        }
        elsif ( $ucopt eq 'CONTAINS' ) {
            my $val = $qv;
            $val =~ s/^'/'%/;
            $val =~ s/'$/%'/;
            $cond .= " LIKE $val";
        }
        elsif ( $ucopt eq 'STARTS WITH' ) {
            my $val = $qv;
            $val =~ s/'$/%'/;
            $cond .= " LIKE $val";
        }
        elsif ( $ucopt eq 'ENDS WITH' ) {
            my $val = $qv;
            $val =~ s/^'/'%/;
            $cond .= " LIKE $val";
        }
        else {
            $cond .= $data->{ $option } . $qv;
        }

        push @conditions, $cond;
    }

    return @conditions;
}

sub format_sort_conditions {
    my ( $self, $data, $field_map, $default ) = @_;

    my @sortby;

    if ( $data->{Sort} ) {
        foreach ( 1 .. 3 ) {
            if ( $data->{ $_ . '_sortfield' } ) {
                push(
                    @sortby,
                    $field_map->{ $data->{ $_ . '_sortfield' } }->{field}
                        . (
                        uc( $data->{ $_ . '_sortmod' } ) eq 'ASCENDING'
                        ? ''
                        : ' DESC'
                        )
                );
            }
        }
    }
    else {

        # if no default specified, return empty arrayref
        push( @sortby, $default ) if $default;
    }

    return \@sortby;
}

sub set_paging_vars {
    my ( $self, $data, $r_data ) = @_;

    if ( $data->{limit} !~ /^\d+$/ ) {
        $r_data->{limit} = 20;
    }
    else {
        $r_data->{limit} = $data->{limit};
        $r_data->{limit} = 255 if $data->{limit} > 255;  # why? (mps Jan 2012)
    }

    if ( $data->{page} && ( $data->{page} =~ /^\d+$/ ) ) {
        $r_data->{start} = ( $data->{page} - 1 ) * $r_data->{limit} + 1;
    }
    elsif ( $data->{start} && ( $data->{start} =~ /^\d+$/ ) ) {
        $r_data->{start} = $data->{start};
    }
    else {
        $r_data->{start} = 1;
    }

    if ( $r_data->{start} >= $r_data->{total} ) {
        if ( $r_data->{total} % $r_data->{limit} ) {
            $r_data->{start}
                = int( $r_data->{total} / $r_data->{limit} )
                * $r_data->{limit} + 1;
        }
        else {
            $r_data->{start} = $r_data->{total} - $r_data->{limit} + 1;
        }
    }

    $r_data->{end} = ( $r_data->{start} + $r_data->{limit} ) - 1;
    $r_data->{page}
        = $r_data->{end} % $r_data->{limit}
        ? int( $r_data->{end} / $r_data->{limit} ) + 1
        : $r_data->{end} / $r_data->{limit};
    $r_data->{total_pages}
        = $r_data->{total} % $r_data->{limit}
        ? int( $r_data->{total} / $r_data->{limit} ) + 1
        : $r_data->{total} / $r_data->{limit};
}

sub search_params_sanity_check {
    my ( $self, $data, @fields ) = @_;
    my %f = map { $_ => 1 } @fields;
    my %o = map { $_ => 1 } (
        'contains', 'starts with', 'ends with', 'equals',
        '>',        '>=',          '<',         '<=',
        '='
    );
    my %i = map { $_ => 1 } ( 'and', 'or' );

    #search stuff
    if ( $data->{Search} ) {
        foreach my $int ( 1 .. 5 ) {
            next unless exists $data->{ $int . "_field" };
            foreach (qw(option value)) {
                $self->error(
                    $int . "_$_",
                    "Parameter $int"
                        . "_$_ must be included with $int"
                        . "_field ."
                ) unless exists $data->{ $int . "_$_" };
            }

            $self->error(
                $int . "_field",
                "Parameter $int"
                    . "_field is an invalid field : '"
                    . $data->{ $int . "_field" }
                    . "'. Use one of "
                    . join( ", ", map {"'$_'"} keys %f )
            ) unless exists $f{ $data->{ $int . "_field" } };
            $self->error(
                $int . "_option",
                "Parameter $int"
                    . "_option is invalid: '"
                    . $data->{ $int . "_option" }
                    . "'. Use one of "
                    . join( ", ", map {"'$_'"} keys %o )
            ) unless exists $o{ lc( $data->{ $int . "_option" } ) };

            next unless $int > 1;
            $self->error(
                $int . "_inclusive",
                "Parameter $int"
                    . "_inclusive is invalid: '"
                    . $data->{ $int . "_inclusive" }
                    . "'. Use one of "
                    . join( ", ", map {"'$_'"} keys %i )
            ) unless exists $i{ lc( $data->{ $int . "_inclusive" } ) };
        }
    }
    elsif ( $data->{quick_search} ) {
        $self->error( "search_value",
            "Must include parameter 'search_value' with 'quick_search'." )
            unless exists $data->{search_value};
    }

    #sort stuff
    if ( $data->{Sort} ) {
        foreach my $int ( 1 .. 3 ) {
            next unless exists $data->{ $int . "_sortfield" };
            $self->error(
                $int . "_sortfield",
                "Sort parameter $int"
                    . "_sortfield is invalid: '"
                    . $data->{ $int . "_sortfield" }
                    . "'.  Use one of "
                    . join( ", ", map {"'$_'"} keys %f )
            ) unless exists $f{ $data->{ $int . "_sortfield" } };
        }
    }

    #paging stuff
    #just make sure start,page,limit, are valid ints (or blank)
    foreach my $sort ( grep { $data->{$_} } qw(start page limit) ) {
        $self->error( $sort,
            "Paging field '$sort' must be an integer." )
            unless $data->{$sort} =~ /^\d+$/;
    }

}

sub clean_perm_data {
    my ($self, $obj) = @_;

    foreach ( qw/ nt_user_id nt_group_id nt_perm_id perm_name / ) {
        delete $obj->{$_};
    };
};

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer - NicTool API reference server

=head1 VERSION

version 2.33

=head1 SYNOPSIS

=head1 NAME

NicToolServer - NicTool API reference server

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abe Shelton

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
