package NicToolServer::Export::NSD;

# ABSTRACT: exporting DNS data to NSD

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::BIND';

sub update_named_include {
    my ( $self, $dir ) = @_;

    # full export, write a new include file
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my $fh      = $self->get_export_file( 'nsd.nictool.conf', $dir );
    foreach my $zone ( $self->{nte}->zones_exported ) {
        print $fh <<EO_ZONE;
zone:
    name: $zone
    zonefile: $datadir/$zone

EO_ZONE
    }
    close $fh;
    return 1;
}

sub default_remote_login {'nsd'}

sub makefile_targets {
    my ( $self, $exportdir, $remote_login, $address, $datadir ) = @_;
    return <<EO_MAKE;
################################
#########    NSD   #############
################################
# Note: you will need to configure zonesdir in nsd.conf to point to this
# export directory. Make sure the export directory reflected below is correct
# then uncomment each of the targets.

# NSD v4
compile: $exportdir/nsd.nictool.conf
\ttest 1

remote: $exportdir
\trsync -az --delete $exportdir/ $remote_login\@$address:$datadir/

restart: $exportdir
\tssh $remote_login\@$address "nsd-control reconfig && nsd-control reload"

EO_MAKE
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::NSD - exporting DNS data to NSD

=head1 VERSION

version 2.41

=head1 SYNOPSIS

Export DNS information from NicTool as BIND zone files for the NSD name server.

=head1 NAME

NicToolServer::Export::NSD

=head1 named.conf.local

This class will export a named.conf.nictool file with all the NicTool zones assigned to that NicTool nameserver. It is expected that this file will be included into a named.conf file via an include entry like this:

 include "/etc/namedb/master/named.conf.nictool";

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
