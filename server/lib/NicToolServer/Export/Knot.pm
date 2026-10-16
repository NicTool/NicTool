package NicToolServer::Export::Knot;

# ABSTRACT: exporting DNS data to Knot DNS

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::BIND';

sub update_named_include {
    my ( $self, $dir ) = @_;

    if ( $self->{nte}->incremental ) {
        return $self->update_named_include_incremental($dir);
    }

    # full export, write a new include file
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my $fh      = $self->get_export_file( $self->include_file, $dir );
    foreach my $zone ( $self->{nte}->zones_exported() ) {
        if ( $ENV{'NT_EXPORT_KNOT_VERSION'} eq '1' ) {
            print $fh qq[$zone { file "$datadir/$zone"; }\n];
        }
        else {
            print $fh qq[zone: \n  - domain: $zone\n    file: $datadir/$zone\n];
        }
    }
    close $fh;
    return 1;
}

sub include_file {'knot.conf.nictool'}

# simerson.net { file "/var/db/knot/simerson.net"; }
sub include_line_zone {
    my ( $self, $line ) = @_;
    my ($zone) = split /\s/, $line;
    return $zone;
}

sub default_remote_login {'knot'}

sub makefile_targets {
    my ( $self, $exportdir, $remote_login, $address, $datadir ) = @_;
    return <<MAKE;
##################################
#########  Knot DNS  #############
##################################
# Make sure the export directory reflected below is correct
# then uncomment each of the targets.

compile: $exportdir/knot.conf.nictool
\ttest 1

remote: $exportdir/knot.conf.nictool
\trsync -az --delete $exportdir/ $remote_login\@$address:$datadir/

restart: $exportdir/knot.conf.nictool
\tssh $remote_login\@$address knotc reload
MAKE
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::Knot - exporting DNS data to Knot DNS

=head1 VERSION

version 2.41

=head1 SYNOPSIS

Export DNS information from NicTool as BIND zone files for the Knot DNS server.

=head1 NAME

NicToolServer::Export::Knot

=head1 knot.conf.local

This class will export a knot.conf.nictool file with all the NicTool zones assigned to that NicTool nameserver. It is expected that this file will be included into a knot.conf file via an include entry like this:

zone {
  include "/var/db/knot/named.conf.nictool";
  ...
}

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
