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
        zone_list => [],
    },
    $class;

    warn "oops, a NicToolServer::Export object wasn't provided!" 
        if ! $self->{nte};
    return $self;
}

sub get_export_file {
    my $self = shift;
    my $zone = shift or die $self->{nte}->elog("missing zone");
    my $dir = shift || $self->{nte}->get_export_dir or return;

    my $file = "$dir/$zone";
    my $fh = IO::File->new($file, '>')
        or die $self->{nte}->elog("unable to open `$file' for writing: $!");
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
    my $self = shift;

    foreach my $z ( @{ $self->{nte}->get_ns_zones } ) {
        push @{$self->{zone_list}}, $z->{zone};
        my $fh = $self->get_export_file( $z->{zone} );
        $self->{nte}{zone_name} = $z->{zone};

        $fh->print($self->{nte}->zr_soa( $z ));
        $fh->print($self->{nte}->zr_ns(  $z ));

        my $records = $self->get_records( $z->{nt_zone_id} );
        foreach my $r ( @$records ) {
            my $type   = lc( $r->{type} );
            my $method = "zr_${type}";
            $r->{location}  ||= '';
            $fh->print($self->$method($r));
        }
        close $fh;
    }   
}

1;

