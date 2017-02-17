#!/usr/bin/perl
use strict;
###
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under
# the terms of the Affero General Public License as published by Affero,
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#
###

package NicTool::API;

sub new {
    my $pkg = shift;
    print "new API for package $pkg\n";
    return bless {}, $pkg;
}

sub api_commands {
    {   'login' => {
            'parameters' => {
                'username' => { required => 1 },
                'password' => { required => 1 },
            },
            'result-type' => 'User',
        },
        'logout'         => {},
        'verify_session' => {},

        # user API
        'get_user' => {
            'class'      => 'User',
            'method'     => 'get_user',
            'parameters' => {
                'nt_user_id' =>
                    { access => 'read', required => 1, type => 'USER' },
            },
            'result-type' => 'User',
        },
        'new_user' => {
            'class'      => 'User::Sanity',
            'method'     => 'new_user',
            'creation'   => 'USER',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
                'username' => { required => 1 },
                'email'    => { required => 1 },
            },
        },
        'edit_user' => {
            'class'      => 'User::Sanity',
            'method'     => 'edit_user',
            'parameters' => {
                'nt_user_id' =>
                    { access => 'write', required => 1, type => 'USER' },
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
            'class'      => 'User',
            'method'     => 'get_group_users',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type'       => 'User',
            'result-list'       => 1,
            'result-list-param' => 'list',
        },
        'get_user_list' => {
            'class'      => 'User',
            'method'     => 'get_user_list',
            'parameters' => {
                'user_list' => {
                    access   => 'read',
                    required => 1,
                    type     => 'USER',
                    list     => 1
                },
            },
            'result-type'       => 'User',
            'result-list'       => 1,
            'result-list-param' => 'list',
        },
        'move_users' => {
            'class'      => 'User',
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
            'class'      => 'User',
            'method'     => 'get_user_global_log',
            'parameters' => {
                'nt_user_id' =>
                    { access => 'read', required => 1, type => 'USER' },
            },
            'result-type' => 'Log',
        },

        # group API

        'get_group' => {
            'class'      => 'Group',
            'method'     => 'get_group',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type' => 'Group',
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
            'result-type'       => 'Group',
            'result-list'       => 1,
            'result-list-param' => 'groups',
        },
        'get_group_branch' => {
            'class'      => 'Group',
            'method'     => 'get_group_branch',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type'       => 'Group',
            'result-list'       => 1,
            'result-list-param' => 'groups',
        },
        'get_group_subgroups' => {
            'class'      => 'Group',
            'method'     => 'get_group_subgroups',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type'       => 'Group',
            'result-list'       => 1,
            'result-list-param' => 'groups',
        },
        'get_global_application_log' => {
            'class'      => 'Group',
            'method'     => 'get_global_application_log',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type' => 'Log',
        },

        # zone API
        'get_zone' => {
            'class'      => 'Zone',
            'method'     => 'get_zone',
            'parameters' => {
                'nt_zone_id' =>
                    { access => 'read', required => 1, type => 'ZONE' },
            },
            'result-type' => 'Zone',
        },

        'get_group_zones' => {
            'class'      => 'Zone',
            'method'     => 'get_group_zones',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type'       => 'Zone',
            'result-list'       => 1,
            'result-list-param' => 'zones'
        },
        'get_group_zones_log' => {
            'class'      => 'Zone',
            'method'     => 'get_group_zones_log',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type' => 'Log'
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
                    list     => 1
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
                    list     => 1
                },
            },
        },
        'delete_zones' => {
            'class'      => 'Zone',
            'method'     => 'delete_zones',
            'parameters' => {
                'zone_list' => {
                    access   => 'delete',
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
            'result-type' => 'Log',
        },
        'get_zone_records' => {
            'class'      => 'Zone',
            'method'     => 'get_zone_records',
            'parameters' => {
                'nt_zone_id' =>
                    { 'access' => 'read', required => 1, type => 'ZONE' },
            },
            'result-type'       => 'Record',
            'result-list'       => 1,
            'result-list-param' => 'records',
        },
        'get_zone_application_log' => {
            'class'      => 'Zone',
            'method'     => 'get_zone_application_log',
            'parameters' => {
                'nt_zone_id' =>
                    { access => 'read', required => 1, type => 'ZONE' },
            },
            'result-type' => 'Log',
        },
        'move_zones' => {
            'class'      => 'Zone',
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
            'result-type'       => 'Zone',
            'result-list'       => 1,
            'result-list-param' => 'zones',

        },

        # zone_record API

        'new_zone_record' => {
            'class'      => 'Zone::Record::Sanity',
            'method'     => 'new_zone_record',
            'creation'   => 'ZONERECORD',
            'parameters' => {
                'nt_zone_id' =>
                    { access => 'read', required => 1, type => 'ZONE' },
                'name'    => { required => 1 },
                'ttl'     => { required => 1 },
                'address' => { required => 1 },
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
            'result-type' => 'Record',
        },
        'get_zone_record_log' => {
            'class'      => 'Zone::Record',
            'method'     => 'get_zone_record_log',
            'parameters' => {
                'nt_zone_id' =>
                    { access => 'read', required => 1, type => 'ZONE' },
            },
            'result-type' => 'Log',
        },
        'get_zone_record_log_entry' => {
            'class'      => 'Zone::Record',
            'method'     => 'get_zone_record_log_entry',
            'parameters' => {
                'nt_zone_record_id' =>
                    { access => 'read', required => 1, type => 'ZONERECORD' },
            },
            'result-type' => 'Log',
        },
        'get_record_type' => {
            'class'      => 'Zone::Record',
            'method'     => 'get_record_type',
            'parameters' => { 'type' => { required => 1 }, },
            'result-type'       => 'Record',
            'result-list'       => 1,
            'result-list-param' => 'types',
        },

        # nameserver API
        'get_nameserver' => {
            'class'      => 'Nameserver',
            'method'     => 'get_nameserver',
            'parameters' => {
                'nt_nameserver_id' =>
                    { access => 'read', required => 1, type => 'NAMESERVER' },
            },
            'result-type' => 'Nameserver',
        },
        'get_usable_nameservers' => {
            'class'  => 'Nameserver',
            'method' => 'get_usable_nameservers',
            'parameters' =>
                { #'nt_group_id'=>{'access'=>'read',required=>1,type=>'GROUP'},
                },
            'result-type'       => 'Nameserver',
            'result-list'       => 1,
            'result-list-param' => 'nameservers',
        },
        'get_nameserver_export_types' => {
            'class'      => 'Nameserver',
            'method'     => 'get_nameserver_export_types',
            'parameters' => { 'type' => { required => 1 }, },
            'result-type'       => 'Nameserver',
            'result-list'       => 1,
            'result-list-param' => 'types',
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
            'class'      => 'Nameserver',
            'method'     => 'get_group_nameservers',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type'       => 'Nameserver',
            'result-list'       => 1,
            'result-list-param' => 'list',
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
            'result-type'       => 'Nameserver',
            'result-list'       => 1,
            'result-list-param' => 'list',
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

        'delegate_zones' => {
            'class'      => 'Permission',
            'method'     => 'delegate_zones',
            'parameters' => {
                'zone_list' => {
                    list     => 1,
                    access   => 'delegate',
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
                'nt_zone_id' =>
                    { access => 'delegate', required => 1, type => 'ZONE' },
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
                'nt_zone_id' =>
                    { access => 'delete', required => 1, type => 'ZONE' },
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
        },
        'delete_zone_record_delegation' => {
            'class'      => 'Permission',
            'method'     => 'delete_zone_record_delegation',
            'parameters' => {
                'nt_zone_record_id' => {
                    access   => 'delete',
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
            'result-type'       => 'Zone',
            'result-list'       => 1,
            'result-list-param' => 'ZONE',
        },
        'get_delegated_zone_records' => {
            'class'      => 'Permission',
            'method'     => 'get_delegated_zone_records',
            'parameters' => {
                'nt_group_id' =>
                    { 'access' => 'read', required => 1, type => 'GROUP' },
            },
            'result-type'       => 'Record',
            'result-list'       => 1,
            'result-list-param' => 'ZONERECORD',
        },
        'get_zone_delegates' => {
            'class'      => 'Permission',
            'method'     => 'get_zone_delegates',
            'parameters' => {
                'nt_zone_id' =>
                    { access => 'read', required => 1, type => 'ZONE' },
            },
            'result-type'       => 'Group',
            'result-list'       => 1,
            'result-list-param' => 'delegates',
        },
        'get_zone_record_delegates' => {
            'class'      => 'Permission',
            'method'     => 'get_zone_record_delegates',
            'parameters' => {
                'nt_zone_record_id' =>
                    { access => 'read', required => 1, type => 'ZONERECORD' },
            },
            'result-type'       => 'Group',
            'result-list'       => 1,
            'result-list-param' => 'delegates',
        },
    };
}

sub result_type {
    my ( $p, $call ) = @_;
    return api_commands->{$call}->{'result-type'};
}

sub result_is_list {
    my ( $p, $call ) = @_;
    return api_commands->{$call}->{'result-list'};
}

sub result_list_param {
    my ( $p, $call ) = @_;
    return api_commands->{$call}->{'result-list-param'};
}

sub parameters {
    my ( $p, $call, $param, $field ) = @_;

    my $obj = api_commands->{$call}->{parameters};
    return $obj if !$param;
    $obj = $obj->{$param};
    return $obj if !$field;
    return $obj->{$field};
}

sub param_access {
    my ( $p, $call, $param ) = @_;
    return $p->parameters( $call, $param, 'access' );
}

sub param_list {
    my ( $p, $call, $param ) = @_;
    return $p->parameters( $call, $param, 'list' );
}

sub param_type {
    my ( $p, $call, $param ) = @_;
    return $p->parameters( $call, $param, 'type' );
}

sub param_required {
    my ( $p, $call, $param ) = @_;
    return $p->parameters( $call, $param, 'required' );
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::API

=head1 VERSION

version 1.02

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
