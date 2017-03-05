package NicTool::Cache;
use strict;
###
# a simple path based cache
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

sub new { bless {}, $_[0] }

sub del {
    my ( $self, @path ) = @_;
    my $cache = $self;
    my $id    = pop @path;
    foreach (@path) { $cache = $cache->{$_}; }
    delete $cache->{$id};
}

sub add {
    my ( $self, $obj, @path ) = @_;
    my $cache = $self;
    my $id    = pop @path;
    return if !defined $id;
    foreach (@path) {
        return if !defined $_;
        $cache->{$_} = {} if !exists $cache->{$_};
        $cache = $cache->{$_};
    }
    $cache->{$id} = $obj;
}

sub get {
    my ( $self, @path ) = @_;
    my $cache = $self;
    my $id    = pop @path;
    foreach (@path) {
        $cache = $cache->{$_};
    }
    if ( $id && $cache->{$id} ) {
        return $cache->{$id};
    };
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::Cache

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
