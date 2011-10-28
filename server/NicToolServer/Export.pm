package NicToolServer::Export;

use strict;
use warnings;

use Params::Validate  qw/ :all /;

# 
#
# A class for writing exports of DNS data from NicTool
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
    bless {
        'server' => $_[0],
        'nsid'   => $_[1],
        'dbix_r' => undef,
        'dbix_w' => undef,
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

    my @q_args;
    my $query = "SELECT id FROM nt_nameserver WHERE ";
    if    ( defined $p{id} ) {
        $query = "nt_nameserver_id=?";
        push @q_args, $p{id};
    }
    elsif ( defined $p{ip} ) {
        $query = "address=?";
        push @q_args, $p{ip};
    }
    elsif ( defined $p{name} ) {
        $query = "name=?";
        push @q_args, $p{name};
    }
    else {
        die "An id, ip, or name must be passed to get_nameserver_id\n";
    };

    return $self->{server}->exec_query($query, \@q_args);
};

sub get_dbix {
    my ($self, $dsn) = @_;

    $self->{dbix} = $self->{server}->get_dbix($dsn);
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
