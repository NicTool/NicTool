package NicToolServer::Export::Knot;
# ABSTRACT: exporting DNS data to Knot DNS

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::BIND';

use Cwd;
use IO::File;
use File::Copy;
use Params::Validate qw/ :all /;

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

##################################
#########  Knot DNS  #############
##################################
# Note: add instructions here...
# Make sure the export directory reflected below is correct
# then uncomment each of the targets.

compile: $exportdir/named.conf.nictool
\ttest 1

remote: $exportdir/named.conf.nictool
\trsync -az --delete $exportdir/ nsd\@$address:$exportdir/

restart: $exportdir/named.conf.nictool
\tssh knot\@$address knotc reload
MAKE
;
    close $M;
    return 1;
};

1;

__END__

=head1 NAME

NicToolServer::Export::Knot

=head1 SYNOPSIS

Export DNS information from NicTool as BIND zone files for the Knot DNS server.

=head1 named.conf.local

This class will export a named.conf.nictool file with all the NicTool zones assigned to that NicTool nameserver. It is expected that this file will be included into a named.conf file via an include entry like this:

 include "/etc/namedb/master/named.conf.nictool";

=cut
