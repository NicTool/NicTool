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
    if ( $self->{nte}->incremental ) {
        return $self->update_knot_include_incremental( $dir );
    };
# full export, write a new include  file
    my $datadir = $self->{nte}->get_export_data_dir || $dir;
    my $fh = $self->get_export_file( 'knot.conf.nictool', $dir );
    foreach my $zone ( $self->{nte}->zones_exported() ) {
        print $fh qq[$zone { file "$datadir/$zone"; }\n];
    };
    close $fh;
    return 1;
};

sub update_knot_include_incremental {
    my ($self, $dir) = @_;

# check that the zone(s) modified since our last export are in the
# include file, else append it.
#
# there's likely to be more lines in the include file than zones to append
# build a lookup table of changed zones and pass through the file once
    my $to_add = $self->get_changed_zones( $dir );
    my $file   = "$dir/knot.conf.nictool";

    my $in = IO::File->new($file, '<') or do {
            warn "unable to read $file\n";
            return;
        };

    my $out = IO::File->new("$file.tmp", '>') or do {
            warn "unable to append $file.tmp\n";
            return;
        };

# simerson.net { file "/var/db/knot/simerson.net"; }
    while ( my $line = <$in> ) {
        my ($zone) = split /\s/, $line;
        if ( $to_add->{$zone} ) {
            delete $to_add->{$zone};   # exists, remove from add list
        };
        if ( ! $self->{nte}{zones_deleted}{$zone} ) {
            $out->print( $line );
        };
    };
    $in->close;

    foreach my $key ( keys %$to_add ) {
        $out->print( $to_add->{$key} );
    };
    $out->close;
    unlink $file;
    File::Copy::move("$file.tmp", $file);
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
    my $remote_login = $self->{nte}{ns_ref}{remote_login} || 'knot';
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
\trsync -az --delete $exportdir/ $remote_login\@$address:$datadir/

restart: $exportdir/knot.conf.nictool
\tssh $remote_login\@$address knotc reload
MAKE
;
    close $M;
    return 1;
};

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::Knot - exporting DNS data to Knot DNS

=head1 VERSION

version 2.33

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

Abe Shelton

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
