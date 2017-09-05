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

package NicTool::Record;


use NicTool::DBObject;
our @ISA = 'NicTool::DBObject';

sub _id_name {'nt_zone_record_id'}

sub _api {
    +{  _get_self => { 'function' => 'get_zone_record', 'includeid' => 1 },
        _delete_self =>
            { 'function' => 'delete_zone_record', 'includeid' => 1 },
        edit_zone_record              => { 'includeid' => 1 },
        delete_zone_record            => { 'includeid' => 1 },
        get_zone_record               => { 'includeid' => 1 },
        get_zone_record_delegates     => { 'includeid' => 1 },
        get_zone_records              => { 'include'   => 'nt_zone_id' },
        get_zone_record_log_entry     => { 'includeid' => 1 },
        edit_zone_record_delegation   => { 'includeid' => 1 },
        delete_zone_record_delegation => { 'includeid' => 1 },
        get_zone_record_delegates     => { 'includeid' => 1 },
    };
}

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::Record

=head1 VERSION

version 1.02

=head1 SYNOPSIS

    my $record = $nt->get_group_zones->next->get_zone_records->next;

=head1 DESCRIPTION

A B<NicTool::Zone> object represents a zone in the NicTool system.
Using an instance of B<NicTool::Zone> you can call a number of NicTool
API functions without specifying the 'nt_zone_id' parameter, and that
parameter will be supplied by this object.

The API functions which you can call are:

=over

=item edit_zone

Returns a B<NicTool::Result> object.

=item get_zone_log

Returns a B<NicTool::Result> object.

=item get_zone_application_log

Returns a B<NicTool::Result> object.

=item new_zone_record

Returns a B<NicTool::Result> object.

=item get_zone_record

Returns a B<NicTool::Record> objects.

=item get_zone_records

Returns a B<NicTool::List> containing B<NicTool::Record> objects.

=item get_zone_record_log

Returns a B<NicTool::Result> object.

=item edit_zone_delegation

Returns a B<NicTool::Result> object.

=item delete_zone_delegation

Returns a B<NicTool::Result> object.

=item get_zone_delegates

Returns a B<NicTool::List> containing B<NicTool::Group> objects.

=back

=head1 NAME

NicTool::Record - Class representing a Record in the NicTool system.

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
