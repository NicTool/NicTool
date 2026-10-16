package NicTool::Group;
###
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abraham Ingersoll & Greg Schueler
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

use strict;
use lib 'lib';
use NicTool::DBObject;
our @ISA = 'NicTool::DBObject';

sub _id_name {'nt_group_id'}

# API functions that act on a group: a Group supplies its own id, and the
# objects within a group supply their nt_group_id
sub group_functions {
    qw/ new_user new_group get_group get_group_users move_users edit_group delete_group
        get_group_groups get_group_branch get_group_subgroups get_global_application_log
        get_group_zones new_zone move_zones new_nameserver get_group_nameservers
        move_nameservers delegate_zones delegate_zone_records edit_zone_delegation
        edit_zone_record_delegation delete_zone_delegation delete_zone_record_delegation
        get_delegated_zones get_delegated_zone_records /;
}

sub _api {
    +{  _get_self    => { 'function' => 'get_group',    'includeid' => 1 },
        _delete_self => { 'function' => 'delete_group', 'includeid' => 1 },
        ( map { $_ => { 'includeid' => 1 } } group_functions() ),
        edit_group => { 'includeid' => 1, sully => 1 },
    };
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::Group

=head1 VERSION

version 1.02

=head1 SYNOPSIS

    my $group = $nt->get_group;

=head1 DESCRIPTION

A B<NicTool::Group> object represents a group in the NicTool system.
Using an instance of B<NicTool::Group> you can call a number of NicTool
API functions without specifying the 'nt_group_id' parameter, and that
parameter will be supplied by this object.

The API functions which you can call are:

=over

=item new_user

Returns a B<NicTool::Result> object. 

=item get_group

Returns a B<NicTool::Group> object. 

=item get_group_users

Returns a B<NicTool::List> containing B<NicTool::User> objects. 

=item move_users

Returns a B<NicTool::Result> object. 

=item edit_group

Returns a B<NicTool::Result> object. 

=item delete_group

Returns a B<NicTool::Result> object. 

=item get_group_groups

Returns a B<NicTool::List> containing B<NicTool::Group> objects. 

=item get_group_branch

Returns a B<NicTool::Result> object. 

=item get_group_subgroups

Returns a B<NicTool::List> containing B<NicTool::Group> objects. 

=item get_global_application_log

Returns a B<NicTool::Result> object. 

=item get_group_zones

Returns a B<NicTool::List> containing B<NicTool::Zone> objects. 

=item new_zone

Returns a B<NicTool::Result> object. 

=item move_zones

Returns a B<NicTool::Result> object. 

=item new_nameserver

Returns a B<NicTool::Result> object. 

=item get_group_nameservers

Returns a B<NicTool::List> containing B<NicTool::Nameserver> objects. 

=item move_nameservers

Returns a B<NicTool::Result> object. 

=item delegate_zones

Returns a B<NicTool::Result> object. 

=item delegate_zone_records

Returns a B<NicTool::Result> object. 

=item edit_zone_delegation

Returns a B<NicTool::Result> object. 

=item edit_zone_record_delegation

Returns a B<NicTool::Result> object. 

=item delete_zone_delegation

Returns a B<NicTool::Result> object. 

=item delete_zone_record_delegation

Returns a B<NicTool::Result> object. 

=item get_delegated_zones

Returns a B<NicTool::List> containing B<NicTool::Zone> objects. 

=item get_delegated_zone_records

Returns a B<NicTool::List> containing B<NicTool::Record> objects. 

=back

=head1 NAME

NicTool::Group - Class representing a Group in the NicTool system.

=head1 SEE ALSO

=over

=item *

The NicTool API documentation.

=item *

L<NicTool::Group>

=item *

L<NicTool::List>

=item *

L<NicTool::Nameserver>

=item *

L<NicTool::Record>

=item *

L<NicTool::User>

=item *

L<NicTool::Zone>

=back

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abraham Ingersoll

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abraham Ingersoll, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
