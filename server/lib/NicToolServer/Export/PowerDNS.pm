package NicToolServer::Export::PowerDNS;
# ABSTRACT: exporting DNS data to PowerDNS servers

=pod

A working PowerDNS pipe backend script is included in the NicToolServer
distribution as bin/nt_powerdns.pl. It serves PowerDNS requests directly
from the data in the NicTool tables.

This module is used for PowerDNS with the zone files back end.

=cut

use strict;
use warnings;

use parent 'NicToolServer::Export::BIND';

use Cwd;
use IO::File;
use File::Copy;

sub write_makefile {
    my $self = shift;

    my $exportdir = $self->{nte}->get_export_dir or do {
        warn "no export dir!";
        return;
    };
    return 1 if -e "$exportdir/Makefile";   # already exists

    my $address = $self->{nte}{ns_ref}{address} || '127.0.0.1';
    my $datadir = $self->{nte}{ns_ref}{datadir} || getcwd . '/data-all';
    $datadir =~ s/\/$//;  # strip off any trailing /
    open my $M, '>', "$exportdir/Makefile" or do {
        warn "unable to open ./Makefile: $!\n";
        return;
    };
    print $M <<MAKE
# After a successful export, 3 make targets are run: compile, remote, restart
# Each target can do anything you'd like.
# See https://www.gnu.org/software/make/manual/make.html

################################
#########  PowerDNS  ###########
################################

compile: $exportdir/named.conf.nictool
\ttest 1

remote: $exportdir/named.conf.nictool
\trsync -az --delete $exportdir/ powerdns\@$address:$datadir/

restart: $exportdir/named.conf.nictool
\tssh powerdns\@$address pdns_control cycle
MAKE
;
    close $M;
    return 1;
};

1;

__END__

=head1 NAME

NicToolServer::Export::PowerDNS

=head1 SYNOPSIS

Export DNS information from to PowerDNS BIND file backend

=head1 named.conf.local

This class will export a named.conf.nictool file with all the zones assigned to that nameserver.

=head1 AUTHOR

Matt Simerson

=cut
