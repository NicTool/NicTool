package NicToolServer::Export;

use strict;
use warnings;

use Params::Validate  qw/ :all /;

#
# Methods for writing exports of DNS data from NicTool
#
# this class will support the creation of nt_export_djb.pl, nt_export_bind.pl,
# and ease the creation of export scripts for other DNS servers.

# nt_nameserver_export
#   nt_nameserver_id
#   timestamp
#   status
#   timestamp_last_success
#   

sub new {
    die "please pass in a NicToolServer object" if ref $_[1] ne 'NicToolServer';
    bless {
        'dbix_r' => undef,
        'dbix_w' => undef,
        'nsid'   => $_[2],
        'server' => $_[1],
    },
    $_[0];
};

sub get_nameserver_id {
    my $self = shift;
    my %p = validate(@_,
        {
            id   => { type => SCALAR, optional => 1 },
            name => { type => SCALAR, optional => 1 },
            ip   => { type => SCALAR, optional => 1 },
        }
    );

    die "An id, ip, or name must be passed to get_nameserver_id\n"
        if ( ! $p{id} && ! $p{name} && ! $p{id} );

    my @q_args;
    my $query = "SELECT nt_nameserver_id AS id FROM nt_nameserver 
        WHERE deleted='0'";

    if ( defined $p{id} ) {
        $query .= " AND nt_nameserver_id=?";
        push @q_args, $p{id};
    };
    if ( defined $p{ip} ) {
        $query .= " AND address=?";
        push @q_args, $p{ip};
    };
    if ( defined $p{name} ) {
        $query .= " AND name=?";
        push @q_args, $p{name};
    };

    my $nameservers = $self->{server}->exec_query($query, \@q_args);
    return $nameservers->[0]->{id};
};


sub get_last_ns_update {
    my $self = shift;
    my %p = validate(@_,
        {
            id     => { type => SCALAR },
            result => { type => SCALAR, optional => 1, default => 'any' },
        }
    );

    my $query = "SELECT nt_nameserver_export_log_id AS id, date_start, 
        date_finish, message
      FROM nt_nameserver_export_log
        WHERE nt_nameserver_id=?";


};

sub get_dbh {
    my ($self, $dsn) = @_;

    $self->{dbh} = $self->{server}->dbh($dsn);
# get database handles (r/w and r/o) used by the export processes
#
# if a r/o handle is provided, use it for reading zone data. This is useful
# for sites with replicated mysql servers and a local db slave.
#
# The write handle is used for all other purposes. If a specific DSN 
# is provided in the nt_nameserver table, use it. Else use the settings in
# nictoolserver.conf.
#
# 
 
};

sub get_export_status {
    my ($self, $ns_id, $status) = @_;

#SELECT status FROM nt_nameserver_export_procstatus WHERE nt_nameserver_id = 



}




1;
