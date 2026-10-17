package NicToolServer::Export::PowerDNS;

# ABSTRACT: exporting DNS data to PowerDNS servers

use strict;
use warnings;

use parent 'NicToolServer::Export::BIND';

sub default_remote_login {'powerdns'}

sub makefile_targets {
    my ( $self, $exportdir, $remote_login, $address, $datadir ) = @_;
    return <<MAKE;
################################
#########  PowerDNS  ###########
################################

compile: $exportdir/named.conf.nictool
\ttest 1

remote: $exportdir/named.conf.nictool
\trsync -az --delete $exportdir/ $remote_login\@$address:$datadir/

restart: $exportdir/named.conf.nictool
\tssh $remote_login\@$address pdns_control cycle
MAKE
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::PowerDNS - exporting DNS data to PowerDNS servers

=head1 VERSION

version 2.42

=head1 SYNOPSIS

Export DNS information from to PowerDNS BIND file backend

A working PowerDNS pipe backend script is included in the NicToolServer
distribution as bin/nt_powerdns.pl. It serves PowerDNS requests directly
from the data in the NicTool tables.

This module is used for PowerDNS with the zone files back end.

=head1 NAME

NicToolServer::Export::PowerDNS

=head1 named.conf.local

This class will export a named.conf.nictool file with all the zones assigned to that nameserver.

=head1 AUTHOR

Matt Simerson

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
