package NicToolServer::Export;

use strict;
use warnings;

#use Params::Validate  qw/ :all /;

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
};

sub get_dbh {
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
