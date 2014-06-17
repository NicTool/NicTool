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

sub postflight {
    my $self = shift;
    my $dir = shift || $self->{nte}->get_export_dir or return;

    $self->update_knot_include( $dir ) or return;

    return 1 if ! $self->{nte}{postflight_extra};

    $self->write_makefile() or return;
    $self->compile() or return;
    $self->rsync()   or return;
    $self->restart() or return;

    return 1;
}

sub update_knot_include {
    my ($self, $dir) = @_;
#   if ( $self->{nte}->incremental ) {
#       return $self->update_knot_include_incremental( $dir );
#   };
# full export, write a new include  file
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my $fh = $self->get_export_file( 'knot.conf.nictool', $dir );
    foreach my $zone ( $self->{nte}->zones_exported() ) {
        print $fh qq[$zone { file "$datadir/$zone"; }\n];
    };
    close $fh;
    return 1;
};

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

##################################
#########  Knot DNS  #############
##################################
# Make sure the export directory reflected below is correct
# then uncomment each of the targets.

compile: $exportdir/knot.conf.nictool
\ttest 1

remote: $exportdir/knot.conf.nictool
\trsync -az --delete $exportdir/ knot\@$address:$datadir/

restart: $exportdir/knot.conf.nictool
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

=head1 knot.conf.local

This class will export a knot.conf.nictool file with all the NicTool zones assigned to that NicTool nameserver. It is expected that this file will be included into a knot.conf file via an include entry like this:

zone {
  include "/var/db/knot/named.conf.nictool";
  ...
}

=cut
