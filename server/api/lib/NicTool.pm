package NicTool;
# ABSTRACT: A client framework for interaction with a NicToolServer via SOAP or XML-RPC.

use strict;
use Carp;
use SOAP::Lite;
#use Data::Dumper;

use lib 'lib';
use NicTool::API;
use NicTool::Result;
use NicTool::List;
use NicTool::Transport;
use NicTool::Cache;
our $AUTOLOAD;

$NicTool::VERSION = '1.03';

=head1 SYNOPSIS

    use NicTool;

    my $nt = NicTool->new(server_host=>'some.com',server_port=>'8082');
    $nt->login(username=>'me',password=>'guess');
    my @zones = $nt->get_group_zones;

=head1 DESCRIPTION

NicTool is an object-oriented client-side framework interface to the 
NicToolServer API.  Each of the different types of NicTool objects is 
represented by an appropriately named class.  The classes know which 
NicToolServer API functions it makes sense for them to call directly,
and which parameters to automatically insert. 

For example, a B<NicTool::Group> object will automatically insert its 
own nt_group_id setting into a call to get_group_zones.  A 
B<NicTool::User> object also has an nt_group_id field, and can do the 
same thing.

Another convenience is the ability to substitute any B<NicTool> object,
such as a B<NicTool::Group>, where an object ID is expected. This also
works within array references one level deep.
E.G.
   @zones=$group->get_group_zones->list;
   $user->delete_zones(zone_list=>\@zones);

   is functionally equivalent to

   @zones=map{$_->id} $group->get_group_zones->list;
   $user->delete_zones(zone_list=>\@zones);

For API functions which may not have a clear link to any one type of
object, the B<NicTool> class can call those directly, and you will have
to specify all of the parameters.  

B<NicTool::Group> and B<NicTool::User> objects also have shortcuts 
defined for examining their permissions settings.  A method call like
"can_something" will return the value of the "something" permission.
E.G. 
    $user->can_zone_create

=head1 LIMITATIONS

As of this version (1.00), Support there is not direct support for Logs.
Function calls which return logs or log entries will return instances
of B<NicTool::Result>.

=cut

=head1 METHODS

=over

=item new(CONFIG_PARAM_LIST)

Constructor for the B<NicTool> class.  CONFIG_PARAM_LIST is a list of 
keyed parameters.  The following keys may be used.  Those with Default
values do not need to be specified.

=over

=item server_host

The hostname of the NicToolServer

=item server_port

The port for the server

=item transfer_protocol

The transfer protocol to use. May be 'http' or 'https'.
(Default 'http')

=item data_protocol

The data transport protocol to use.  This may be 'soap' or 'xml_rpc'.
(Default 'soap')

=item nt_user_session

You may specify an session string with this parameter if you need to
use an already existing (and valid) session with the server. 
(Default '')

=item use_protocol_version

Flag telling whether the nt_protocol_version should be used in requests. If this is
set to TRUE and the server doesn't support the protocol version used, each call
will result in an error. If this is FALSE the protocol version will not be sent
and the server shouldn't complain (though if the protocols are mismatched you may
get funky behavior). (Default FALSE)

=item nt_protocol_version

The protocol version to send if use_protocol_version is TRUE. This client library
only conforms to protocol version 1.0 at this time. (Default "1.0")

=item cache_groups

Flag telling whether calls to I<get_group> should cache the results.
(Groups probably won't be changed behind your back.) (Default TRUE)

=item cache_users

Flag telling whether calls to I<get_user> should cache the results.
(Users probably won't be changed behind your back.) (Default TRUE)

=item cache_zones

Flag telling whether calls to I<get_zone> should cache the results.
(Default FALSE)

=item cache_records

Flag telling whether calls to I<get_zone_record> should cache the results.
(Default FALSE)

=item cache_nameservers
Flag telling whether calls to I<get_nameserver> should cache the 
results. (Nameservers probably won't be changed behind your back.)
(Default TRUE)
    
=back

All of these parameters are optional for the constructor.  Instead they
may be given to the I<config> method after you have an instance of 
B<NicTool>.

=cut

sub new {
    my $pkg  = shift;
    my $self = bless $pkg->_conf, $pkg;
    my %conf = @_;
    foreach ( keys %conf ) {
        $self->{$_} = $conf{$_} if exists $self->{$_};
    }
    $self->{cache} = NicTool::Cache->new;
    return $self;
}

sub set {
    my $self = shift;
    my $var  = shift;
    my $val  = shift;
    $self->{$var} = $val if exists $self->{$var};
}

sub _api {
    +{  login                         => {},
        logout                        => {},
        verify_session                => {},
        get_delegated_zones           => {},
        get_delegated_zone_records    => {},
        get_user                      => {},
        new_user                      => {},
        edit_user                     => {},
        delete_users                  => {},
        get_user_list                 => {},
        move_users                    => {},
        get_group                     => {},
        new_group                     => {},
        edit_group                    => {},
        delete_group                  => {},
        get_zone                      => {},
        get_zone_delegates            => {},
        new_zone                      => {},
        edit_zone                     => {},
        delete_zones                  => {},
        move_zones                    => {},
        get_zone_list                 => {},
        get_zone_record               => {},
        get_zone_records              => {},
        get_zone_record_delegates     => {},
        get_record_type               => {},
        new_zone_record               => {},
        edit_zone_record              => {},
        delete_zone_record            => {},
        get_nameserver                => {},
        get_usable_nameservers        => {},
        get_nameserver_export_types   => {},
        new_nameserver                => {},
        edit_nameserver               => {},
        delete_nameserver             => {},
        get_nameserver_list           => {},
        move_nameservers              => {},
        delegate_zones                => {},
        delegate_zone_records         => {},
        edit_zone_delegation          => {},
        edit_zone_record_delegation   => {},
        delete_zone_delegation        => {},
        delete_zone_record_delegation => {},
    };
}

sub _should_cache {
    my $self = shift;
    +{  get_group => $self->{cache_groups} ? 'nt_group_id' : '',
        get_user  => $self->{cache_users}  ? 'nt_user_id'  : '',
        get_zone  => $self->{cache_zones}  ? 'nt_zone_id'  : '',
        get_zone_record => $self->{cache_records} ? 'nt_zone_record_id'
        : '',
        get_nameserver => $self->{cache_nameservers} ? 'nt_nameserver_id'
        : '',
    };
}

sub _conf {
    return {
        'server_host'         => 'localhost',
        'server_port'         => '8082',
        'transfer_protocol'   => 'http',
        'data_protocol'       => 'soap',
        'nt_user_session'     => undef,
        'use_protocol_version'=> 0,
        'nt_protocol_version' => '1.0',

        'cache_groups'        => 1,
        'cache_users'         => 1,
        'cache_zones'         => 0,
        'cache_records'       => 0,
        'cache_nameservers'   => 1,

        'debug_soap_setup'    => 0,
        'debug_soap_request'  => 0,
        'debug_soap_response' => 0,
        'debug_request'       => 0,
        'debug_response'      => 0,
        'debug_cache_hit'     => 0,
        'debug_cache_miss'    => 0,
        'pause'               => 0,
    };
}

=item config(CONFIG_PARAM_LIST)

I<config> changes the setting of one of the configuration parameters.
The keys for CONFIG_PARAM_LIST are the same as those listed for the
I<new> method.

=cut

sub config {
    my $self = shift;
    while ( @_ > 1 && @_ % 2 == 0 ) {
        my ( $var, $val ) = ( shift, shift );
        $self->{$var} = $val if exists $self->{$var};
    }
}

sub _send_request {
    my $self = shift;
    $self->{transport}
        = NicTool::Transport->get_transport_agent( $self->{data_protocol},
        $self ) or
    croak "No transport available! (data protocol is $self->{data_protocol} )";
    return $self->{transport}->_send_request(@_);
}

sub _object_for_type {
    my ( $self, $type, @rest ) = @_;
    my $package = "NicTool::" . ucfirst( lc($type) );
    my $obj;
    eval "use $package; \$obj= $package->new(\$self,\@rest)"; ## no critic
    if ($@) {
        carp $@;
        return '';
    }
    return $obj;
}

sub _cache_sully_object {
    my $self = shift;
    my $obj  = shift;
    $self->_cache_sully( $obj->type, $obj->id );
}

sub _cache_sully {
    my $self = shift;
    my $type = shift;
    my $id   = shift;
    $self->{cache}->del( lc($type), $id );
}

sub _cache_object {
    my $self = shift;
    my $obj  = shift;
    $self->{cache}->add( $obj, lc( $obj->type ), $obj->id );
}

sub _cache_get {
    my ( $self, $type, $id ) = @_;
    my $res = $self->{cache}->get( lc($type), $id );
    if ( $res && $self->{debug_cache_hit} ) {
        print "\t\tcache_hit: " . lc($type) . ":$id\n";
    }
    elsif ( !$res && $self->{debug_cache_miss} ) {
        print "\t\tcache_miss: " . lc($type) . ":$id\n";
    }
    return $res;
}

=item nt_user_session

Returns the session string for the current session

=cut

sub nt_user_session {
    my $self = shift;
    return $self->{nt_user_session};
}

=item nt_protocol_version

Returns the protocol version

=cut

sub nt_protocol_version {
    my $self = shift;
    return $self->{nt_protocol_version};
}

=item use_protocol_version

Returns whether the protocol version string is sent to the server

=cut

sub use_protocol_version {
    my $self = shift;
    return $self->{use_protocol_version};
}

=item user

Returns the B<NicTool::User> object for the currently logged in user.

=cut

sub user {
    my $self = shift;
    return $self->{user};
}

=item result

Returns the B<NicTool::Result> object for the last function call.

=cut

sub result {
    my $self = shift;
    return $self->{result};
}

sub _dispatch {
    my $self   = shift;
    my $method = shift;
    my @args   = @_;
    my %args   = ( action => $method, @args );
    $args{nt_user_session} = $self->{nt_user_session}
        if $self->{nt_user_session};
    $args{nt_protocol_version} = $self->{nt_protocol_version}
        if $self->{use_protocol_version};

    foreach my $a ( keys %args ) {
        next unless ref $args{$a};
        if ( ref $args{$a}
            && UNIVERSAL::isa( $args{$a}, 'NicTool::DBObject' ) )
        {

#carp "setting arg $a to id for object ".(ref $args{$a})." ID is ".$args{$a}->id;

            $args{$a} = $args{$a}->id;
        }
        elsif ( ref $args{$a} eq 'ARRAY' ) {
            foreach ( @{ $args{$a} } ) {
                next unless ref $_;
                if ( ref $_ && UNIVERSAL::isa( $_, 'NicTool::DBObject' ) ) {
                    $_ = $_->id;
                }
                elsif ( ref $_ ne 'HASH' or ref $_ ne 'ARRAY' ) {
                    croak "Unknown object type for parameter $a : "
                        . join( ":", ref $_, caller );
                }
            }
        }
        elsif ( ref $args{$a} ne 'HASH' ) {
            croak "Unknown object type for parameter $a : "
                . join( ":", ref $args{$a}, caller );
        }
    }

    print "\t\trequest: $method ( " . join( ", ", keys %args ) . " )\n"
        if $self->{debug_request};
    if ( $self->{pause} ) {
        if ( $self->{last_time} && $self->{last_time} >= time ) {
            sleep 1;
        }
        $self->{last_time} = time;
    }
    my $result = $self->_send_request(%args);
    print "\t\tresult: $method ( " . join( ", ", keys %{$result} ) . " )\n"
        if $self->{debug_response};
    $self->{nt_user_session} = $result->{nt_user_session}
        if exists $result->{nt_user_session};
    my $islist = NicTool::API->result_is_list($method);
    my $type   = NicTool::API->result_type($method) || 'Result';

    #print "type is $type, method is $method";
    my $obj;
    unless ($islist) {
        $obj = $self->_object_for_type( $type, $result );
    }
    else {
        $obj = NicTool::List->new( $self, $type,
            NicTool::API->result_list_param($method), $result );

    }
    if ( $method eq 'login' and $type eq 'User' and $obj ) {

        #carp "logged in user: ".Data::Dumper::Dumper($obj);
        $self->{user} = $obj;
    }
    elsif ( $method eq 'logout' ) {
        $self->{user}  = undef;
        $self->{cache} = NicTool::Cache->new;
    }

    #$obj->{nt}=$self if $obj;
    $self->{result} = $obj;
    return $obj;
}

sub _api_call {
    my $self   = shift;
    my $method = shift;
    if ( $self->_api->{$method} ) {
        return 1;
    }
    return '';
}

=item FUNCTION(PARAM_LIST)

Any function in the NicTool API can be called directly with an instance
of B<NicTool>.  Since the B<NicTool> object caches the 
B<NicTool::User> object
of the logged in user, it lets that object first attempt to call 
FUNCTION.  (see L<NicTool::User>).  If the B<NicTool::User> object does 
not call the function, NicTool calls it directly to the server and 
returns the result. The B<NicTool> object also caches the result, and 
it can be retrieved with the I<result> method.

=over

=item return

Returns the B<NicTool::Result> object (or subclass) representing the
result of the function call.

=back

=cut

sub AUTOLOAD {
    my ($self) = shift;
    return if $AUTOLOAD =~ /DESTROY/;

    $AUTOLOAD =~ s/.*:://;

    my $res = $self->{user} ? $self->{user}->$AUTOLOAD(@_) : undef;
    return $res if defined $res;

    if ( $self->_api_call($AUTOLOAD) ) {
        return $self->_dispatch( $AUTOLOAD, @_ );
    }

    if ( $AUTOLOAD =~ /can_([^:]+)$/ ) {
        return $self->{user}->get($1);
    }

    croak "No such method '$AUTOLOAD'";
}

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

This software is Copyright (c) 2011 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007


=head1 SEE ALSO

=over

=item *

L<NicTool::Result>

=item *

L<NicTool::User>

=item *

L<NicTool::Group>

=item *

L<NicTool::Zone>

=item *

L<NicTool::Record>

=item *

L<NicTool::Nameserver>

=item *

L<NicTool::List>

=item *

L<RPC::XML>

=item *

L<SOAP::Lite>

=item *

L<Crypt::SSLeay>

=back

=cut

1;

