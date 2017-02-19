#!/usr/bin/perl
###
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
###

package NicTool::User;


use NicTool::DBObject;
our @ISA = 'NicTool::DBObject';

sub _id_name {nt_user_id}

sub _api {
    +{  _get_self    => { 'function' => 'get_user', 'includeid' => 1 },
        _delete_self => {
            'function'  => 'delete_users',
            'includeas' => { 'user_list', 'nt_user_id' }
        },
        edit_user           => { 'includeid' => 1 },
        get_user            => { 'includeid' => 1 },
        get_user_global_log => { 'includeid' => 1 },
        logout              => {},

        #group functions
        new_group                     => { 'include' => ['nt_group_id'] },
        get_group                     => { 'include' => ['nt_group_id'] },
        new_user                      => { 'include' => ['nt_group_id'] },
        get_group_users               => { 'include' => ['nt_group_id'] },
        move_users                    => { 'include' => ['nt_group_id'] },
        edit_group                    => { 'include' => ['nt_group_id'] },
        delete_group                  => { 'include' => ['nt_group_id'] },
        get_group_groups              => { 'include' => ['nt_group_id'] },
        get_group_branch              => { 'include' => ['nt_group_id'] },
        get_group_subgroups           => { 'include' => ['nt_group_id'] },
        get_global_application_log    => { 'include' => ['nt_group_id'] },
        get_group_zones               => { 'include' => ['nt_group_id'] },
        new_zone                      => { 'include' => ['nt_group_id'] },
        move_zones                    => { 'include' => ['nt_group_id'] },
        new_nameserver                => { 'include' => ['nt_group_id'] },
        get_group_nameservers         => { 'include' => ['nt_group_id'] },
        move_nameservers              => { 'include' => ['nt_group_id'] },
        delegate_zones                => { 'include' => ['nt_group_id'] },
        delegate_zone_records         => { 'include' => ['nt_group_id'] },
        edit_zone_delegation          => { 'include' => ['nt_group_id'] },
        edit_zone_record_delegation   => { 'include' => ['nt_group_id'] },
        delete_zone_delegation        => { 'include' => ['nt_group_id'] },
        delete_zone_record_delegation => { 'include' => ['nt_group_id'] },
        get_delegated_zones           => { 'include' => ['nt_group_id'] },
        get_delegated_zone_records    => { 'include' => ['nt_group_id'] },
    };
}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::User

=head1 VERSION

version 1.02

=head1 SYNOPSIS

    my $user = $nt->get_user;

=head1 DESCRIPTION

A B<NicTool::User> object represents a user in the NicTool system.
Using an instance of B<NicTool::User> you can call a number of NicTool
API functions without specifying the 'nt_user_id' parameter, and that
parameter will be supplied by this object.

The API functions which you can call are:

=over

=item edit_user

Returns a B<NicTool::Result> object.

=item get_user_global_log

Returns a B<NicTool::Result> object.

=item logout

Returns a B<NicTool::Result> object.

=back

A User in the NicTool system also has an 'nt_group_id' parameter 
which specifies the group the user belongs to.  Because of this, you
can also call any of the API functions specified in L<NicTool::Group>
and the 'nt_group_id' parameter will be supplied automatically.

=head1 NAME

NicTool::User - Class representing a User in the NicTool system.

=head1 SEE ALSO

=over

=item *

The NicTool API documentation.

=item *

L<NicTool::Result>

=item *

L<NicTool::Group>

=back

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
