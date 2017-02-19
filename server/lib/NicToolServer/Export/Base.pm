package NicToolServer::Export::Base;
# ABSTRACT: abstract base class for exporter modules

use strict;
use warnings;
use Cwd;
use File::Copy;
use IO::File;

sub new {
    my $class = shift;

    my $self = bless {
        nte => shift,
    },
    $class;

    warn "NicToolServer::Export object not provided!" if ! $self->{nte};
    return $self;
}

sub get_export_file {
    my $self = shift;
    my $zone = shift or die $self->{nte}->elog("missing zone");
    my $dir = shift || $self->{nte}->get_export_dir or return;

    my $file = "$dir/$zone";
    my $fh = IO::File->new($file, '>') or do {
        warn $self->{nte}->elog("unable to open `$file' for writing: $!");
        return;
    };
    return $fh;
};

sub get_records {
    my $self = shift;
    my $zone_id = shift;

    my $sql = "SELECT r.name, r.ttl, r.description, t.name AS type, r.address, r.weight,
    priority, other, location, UNIX_TIMESTAMP(timestamp) AS timestamp
        FROM nt_zone_record r
        LEFT JOIN resource_record_type t ON t.id=r.type_id
         WHERE r.deleted=0 AND r.nt_zone_id=?";

    return $self->{nte}->exec_query( $sql, $zone_id );
}

sub export_db {
    my ($self) = @_;

    my $dir = $self->{nte}->get_export_dir or die "missing export dir!\n";

    # for incremental, get_ns_zones returns only changed zones.
    foreach my $z ( @{ $self->{nte}->get_ns_zones() } ) {
        my $zone = $z->{zone};
        $self->{nte}->zones_exported($zone);
        my $fh = $self->get_export_file( $zone, $dir );
        $self->{nte}{zone_name} = $zone;

        # these records don't exist in DB, generate them here
        $fh->print($self->{nte}->zr_soa( $z ));
        $fh->print($self->{nte}->zr_ns(  $z ));

        my $records = $self->get_records( $z->{nt_zone_id} );
        foreach my $r ( @$records ) {
            my $method = 'zr_' . lc $r->{type};
            if ($r->{ttl} == 0) { $r->{ttl} = ''; }
            if ($r->{name} eq $zone) { $r->{name} .= '.'; } # append a .
            $r->{location}  ||= '';
            $fh->print($self->$method($r));
        }
        $fh->close;
    }

    # remote deleted zone files
    foreach my $z ( @{ $self->{nte}->get_ns_zones( deleted => 1) } ) {
        my $zone = $z->{zone};
        if ($self->{nte}->in_export_list($zone)) {
            warn "$zone was also created, skipping delete\n";
            next;
        };
        my $file = "$dir/$zone";
        next if ! -f $file;  # already deleted
        if ( unlink $file ) {
            $self->{nte}->elog("deleted $zone");
        }
        else {
            $self->{nte}->elog("error deleting $file: $!");
        };
        $self->{nte}{zones_deleted}{$zone} = 1;
    };

    return 1;
}

sub qualify {
    my ($self, $record, $zone) = @_;
    return $record if '.' eq substr($record,-1,1);  # record is already FQDN
    $zone ||= $self->{nte}{zone_name} or return $record;

# substr is measurably faster than the regexp
#return $record if $record =~ /$zone$/;   # ends in zone, just no .
    my $chars = length($zone);
    if ( $zone eq substr( $record, (-1 * $chars), $chars ) ) {
        return $record;    # name included zone name
    };

    return "$record.$zone"       # append zone name
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::Base - abstract base class for exporter modules

=head1 VERSION

version 2.33

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
