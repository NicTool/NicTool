#!/usr/bin/perl
#
# $Id: nt_export_djb.pl 968 2009-10-28 00:44:28Z matt $
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under
# the terms of the Affero General Public License as published by Affero,
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#

use strict;
use DBI;
use Cwd 'cwd';
use Getopt::Long;
use Digest::MD5;

my $DEBUG     = 0;
my $DEBUG_SQL = 0;
my $opens     = 0;
my $closes    = 0;
my @oldargv   = @ARGV;
my ( $nsid, $rsync, $make, $opt_dbids, $opt_noserials, $do_build_cdb, $ck_md5,
    $force );
my %options = (
    'make=s'    => \$make,
    'nsid=i'    => \$nsid,
    'r'         => \$rsync,
    'dbids'     => \$opt_dbids,
    'noserials' => \$opt_noserials,
    'buildcdb'  => \$do_build_cdb,
    'md5'       => \$ck_md5,
    'force'     => \$force
);

&GetOptions(%options);

unless ($nsid) {
    die
        "usage: $0 -nsid X [-make command|-buildcdb] [-md5] [-r] [-dbids] [-noserials] [-force]\n
  Required parameters:

    -nsid (existing nt_nameserver_id)

  Optional parameters:

    -r enables  rsync
    -make XXX   runs 'make XXX' in data export directory
    -buildcdb   calls 'tinydns-data' in the export directory unless -make
    -md5        test if md5 sum has changed
    -dbids      appends database IDS to the end of each line in 'data'
    -noserials  causes export to not dump serial numbers
    -force      causes rsync despite md5 check if last export failed\n\n";
}

# send errors to STDOUT for logging by supervise/multilog (thanks Matt!)
open( STDERR, ">&STDOUT" );
select(STDERR);
$| = 1;
select(STDOUT);
$| = 1;

local $SIG{HUP}  = \&graceful_exit;
local $SIG{TERM} = \&graceful_exit;
local $SIG{PIPE} = \&graceful_exit;
local $SIG{USR1} = \&graceful_exit;
local $SIG{SEGV} = \&graceful_exit;
local $SIG{ALRM} = \&graceful_exit;

my $start_time      = time();
my $dbh_read        = &db_object_read;
my $dbh_write       = &db_object_write;
my $ns              = &get_ns($nsid);
my $ns_status_exist = 0;

$ns->{'name'} =~ s/\.$//;
my $last_export_status = &get_export_status( $ns, $dbh_read );
my $last_export_failed = $last_export_status =~ /last:FAILED/ ? 1 : 0;
&set_export_status( $ns, $dbh_write, "export starting" );
#my $db_row = &start_export_log( $ns, time() );

my $data_dir;
if ( exists( $ENV{'TINYDNS_DATA_DIR'} ) ) {
    $data_dir = $ENV{'TINYDNS_DATA_DIR'};
}
else {
    $data_dir = "data-$ns->{'name'}";
}

if ( !-d $data_dir ) {
    if ( !mkdir( "$data_dir", 0755 ) ) {
        die "I couldn't create $data_dir: $!\n";
    }
}
else {
    if ( !-w $data_dir ) {
        my $iam = getpwuid($<);    # $<  is REAL_USER_ID
        die "FATAL ERROR: $data_dir is not writable by user $iam.
You might fix this like so:\n
      chown -R $iam $data_dir\n\n";
    }

    # directory exists, we're all set.
}

my $cwd = cwd;
chdir($data_dir) || die "couldn't chdir to $data_dir -- $!\n";
rename( "data",     "data.orig" )     if -f "data";
rename( "data.md5", "data.orig.md5" ) if -f "data.md5";

my $sec_build_data_start = time;

&set_export_status( $ns, $dbh_write, "dumping data from DB" );
my $nt_export_djb_path;
if ( exists( $ENV{'NT_EXPORT_DJB'} ) ) {
    $nt_export_djb_path = $ENV{'NT_EXPORT_DJB'};
}
else {
    $nt_export_djb_path = "$cwd/nt_export_djb";
}

$ENV{'NT_APPEND_DB_IDS'} = 1 if ($opt_dbids);
$ENV{'NT_PRINT_SERIALS'} = 1 unless ($opt_noserials);

die "NT_EXPORT_DJB ($nt_export_djb_path) does not exist!\n"
    unless ( -e $nt_export_djb_path );
die "NT_EXPORT_DJB ($nt_export_djb_path) is not executable!\n"
    unless ( -x $nt_export_djb_path );

my $nt_export_djb_ret = system("$nt_export_djb_path $nsid");
if ($nt_export_djb_ret) {
    die "$nt_export_djb_path exited non-zero (with error) -- $nt_export_djb_ret\n";
}

my $sec_build_data = time - $sec_build_data_start;

my $sec_build_cdb;
if ( $make ne '' ) {
    &set_export_status( $ns, $dbh_write, "make $make" );
    $sec_build_cdb = &runmake($make);
}
elsif ($do_build_cdb) {
    $sec_build_cdb = &build_cdb($ns);
}

my $sec_rsync_cdb;
my $export = "successful";

if ($rsync) {
    if ( !$ck_md5 ) {
        &set_export_status( $ns, $dbh_write, "remote rsync" );
        $sec_rsync_cdb = &rsync_cdb($ns);
    }
    else {
        my $diff = files_diff(qw(data data.orig));
        if ($diff) {
            warn "Checksums differ: doing rsync\n";
            &set_export_status( $ns, $dbh_write, "remote rsync" );
            $sec_rsync_cdb = &rsync_cdb($ns);
        }
        elsif ( $last_export_failed && $force ) {
            warn "Previous export failed: forcing rsync\n";
            &set_export_status( $ns, $dbh_write, "remote rsync" );
            $sec_rsync_cdb = &rsync_cdb($ns);
        }
        else {
            #no change to db
            $export        = "success(no_change)";
            $sec_rsync_cdb = 0;
        }
    }
    $export = "FAILED" if $sec_rsync_cdb lt 0;
}
else {
    if ($ck_md5) {
        my $diff = files_diff(qw(data data.orig));
        if ( !$diff ) {
            $export = "success(no_change)";
        }
    }
}

# TODO - log size of data and data.cdb
# disabled 9/28/2007 - not being used - mps
#&finish_export_log($db_row, time(), $sec_build_data, $sec_build_cdb, $sec_rsync_cdb);

chdir($cwd);
warn
    "$ns->{name}: build_data: $sec_build_data build_cdb: $sec_build_cdb rsync_cdb: $sec_rsync_cdb\n"
    if $DEBUG;

my $runningtime = time - $start_time;
my $waitleft    = $ns->{export_interval} - $runningtime;

if ( $runningtime < $ns->{export_interval} ) {
    my $tstring = localtime( $start_time + $runningtime + $waitleft );
    $tstring = substr( $tstring, 4, 15 );
    &set_export_status( $ns, $dbh_write, "last:$export, next: $tstring" );
}
else {
    &set_export_status( $ns, $dbh_write, "export finished:$export" );
}

$dbh_write->disconnect;
$closes++;
$dbh_read->disconnect;
$closes++;
while ( $runningtime < $ns->{export_interval} ) {
    if ( $waitleft < 60 ) {
        sleep $waitleft;
    }
    else {
        sleep 60;
    }
    $dbh_write = &db_object_write;
    my $prev_export_interval = $ns->{export_interval};
    $dbh_read    = &db_object_read;
    $ns          = &get_ns($nsid);
    $runningtime = time - $start_time;
    $waitleft    = $ns->{export_interval} - $runningtime;
    &set_export_status( $ns, $dbh_write,
        "next update starts in $waitleft seconds" )
        if ( $prev_export_interval != $ns->{export_interval} );
    $dbh_write->disconnect;
    $closes++;
    $dbh_read->disconnect;
    $closes++;
}

#$dbh_write = &db_object_write unless ($dbh_write->{Active});
#&set_export_status($ns, $dbh_write, "spawning next export");
#$dbh_write->disconnect;
#$closes++;
#$dbh_read->disconnect ;
#$closes++;
exec( ( $0, @oldargv ) );

### helper subroutines
sub get_ns {
    my ($nsid) = @_;
    my $sql = "SELECT * FROM nt_nameserver WHERE nt_nameserver_id = "
        . $dbh_read->quote($nsid);
    my $sth = $dbh_read->prepare($sql);
    warn "$sql\n" if $DEBUG_SQL;
    $sth->execute || die "failed sql = $sql\n";
    my $ret = $sth->fetchrow_hashref;
    die "invalid nt_nameserver_id $nsid!\n" unless ($ret);
    return $ret;
}

sub db_object_read {
    my $self = shift;
    my @env_vars
        = qw(NT_DB_TYPE NT_DB_NAME NT_DB_HOST_NAME NT_DB_USER_NAME NT_DB_PASSWORD);

    foreach (@env_vars) {
        warn "required environment variable not set -- $_\n" unless $ENV{$_};
    }

    my $engine   = $ENV{'NT_DB_TYPE'};
    my $database = $ENV{'NT_DB_NAME'};
    my $host     = $ENV{'NT_DB_HOST_NAME'};
    my $user     = $ENV{'NT_DB_USER_NAME'};
    my $password = $ENV{'NT_DB_PASSWORD'};
    my $port     = $ENV{'NT_DB_HOST_PORT'};

    unless ($port) {
        $port = '3306';                   # default MySQL port
        $ENV{'NT_DB_HOST_PORT'} = 3306;
    }

    my @connect
        = ( "dbi:$engine:database=$database:host=$host", $user, $password );
    my $dbh_read = DBI->connect(@connect);
    $opens++;
    die "db_object_read: couldn't connect to DB @ '@connect'\n"
        unless $dbh_read;
    return $dbh_read;
}

sub db_object_write {
    my $self = shift;
    my ( $engine, $database, $host, $user, $password, $port );

    if ( $ENV{'NT_UPDATE_DB_TYPE'} ) {
        $engine = $ENV{'NT_UPDATE_DB_TYPE'};
    }
    else {
        $engine = $ENV{'NT_DB_TYPE'};
    }

    if ( $ENV{'NT_UPDATE_DB_NAME'} ) {
        $database = $ENV{'NT_UPDATE_DB_NAME'};
    }
    else {
        $database = $ENV{'NT_DB_NAME'};
    }

    if ( $ENV{'NT_UPDATE_DB_HOST_NAME'} ) {
        $host = $ENV{'NT_UPDATE_DB_HOST_NAME'};
    }
    else {
        $host = $ENV{'NT_DB_HOST_NAME'};
    }

    if ( $ENV{'NT_UPDATE_DB_USER_NAME'} ) {
        $user = $ENV{'NT_UPDATE_DB_USER_NAME'};
    }
    else {
        $user = $ENV{'NT_DB_USER_NAME'};
    }

    if ( $ENV{'NT_UPDATE_DB_PASSWORD'} ) {
        $password = $ENV{'NT_UPDATE_DB_PASSWORD'};
    }
    else {
        $password = $ENV{'NT_DB_PASSWORD'};
    }

    if ( $ENV{'NT_UPDATE_DB_HOST_PORT'} ) {
        $port = $ENV{'NT_UPDATE_DB_HOST_PORT'};
    }
    else {
        $port = $ENV{'NT_DB_HOST_PORT'};
    }

    $port ||= '3306';

    my @connect
        = ( "dbi:$engine:database=$database:host=$host", $user, $password );
    my $dbh_write = DBI->connect(@connect);
    $opens++;
    warn "db_object_write: couldn't connect to DB @ '@connect'\n"
        unless $dbh_write;
    return $dbh_write;
}

sub build_cdb {
    my ($ns) = @_;
    warn "building data.cdb for $ns->{name}\n" if $DEBUG;
    my $cdb_start = time;
    my $tinydata = '/usr/local/bin/tinydns-data';
    $tinydata = '/usr/bin/tinydns-data' if ! -x $tinydata;
    die "unable to find tinydns-data" if ! -x $tinydata;
    my $djb_error = system($tinydata);
    if ( $djb_error ne 0 ) {
        my $blah = $djb_error / 256;
        die "tinydns-data returned non-zero exist status ($djb_error:$blah). WE MUST HAVE PROBLEMS.\n";
    }
    return time - $cdb_start;
}

sub rsync_cdb {
    my ($ns) = @_;

    my @nslist;
    if ( exists( $ENV{'RSYNC_HOSTS'} ) ) {
        my $rhosts = $ENV{'RSYNC_HOSTS'};
        @nslist = split( / /, $rhosts );
    }
    else {
        $nslist[0] = $ns->{'address'};
    }

    my $ret           = 1;
    my $rsync_start   = time;
    my $rsync_success = 1;
    my $rsync_fail    = 0;
    my $rsync_path;
    if ( exists( $ENV{'RSYNC_BIN'} ) ) {
        $rsync_path = $ENV{'RSYNC_BIN'};
    }
    else {
        $rsync_path = 'rsync';
    }

    foreach my $rhost (@nslist) {
        $rsync_fail = 0;
        for ( my $limit = 0; $limit < 3; $limit++ ) {
            warn "rsync try #$limit ..\n" if $DEBUG;
            $ret
                = system(
                "$rsync_path -az -e ssh data.cdb tinydns\@$rhost:$ns->{'datadir'}/data.cdb"
                );
            warn
                "$rsync_path -az -e ssh data.cdb tinydns\@$rhost:$ns->{'datadir'}/data.cdb\n"
                if $DEBUG;
            warn "($ns->{'name'}) rsync ret = $ret! ($limit)\n"
                unless ( $ret == 0 );
            $rsync_fail = 1 if $ret != 0;
            $limit = 3
                if ( $ret == 0 || $ret == 5120 )
                ;    # 5120 = user interrupt (ctrl-c)
        }
        $rsync_success = 0 if ( $rsync_fail == 1 );
    }
    if ($rsync_success) {
        warn "rsync: finished\n";
    }
    else {
        warn "rsync: FAILED ($ret)\n";
        return -1;
    }
    return time - $rsync_start;
}

sub start_export_log {
    my ( $ns, $date_start ) = @_;
    my $sql
        = "INSERT INTO nt_nameserver_export_log(nt_nameserver_id, date_start) VALUES ($ns->{nt_nameserver_id}, $date_start)";
    $dbh_write->do($sql);
    warn "$sql\n" if $DEBUG_SQL;
    return $dbh_write->{'mysql_insertid'};
}

sub finish_export_log {
    my ( $row, $date_finish, @stats ) = @_;
    my $i = 1;
    foreach (@stats) {
        $_ = "stat$i = " . $dbh_write->quote($_);
        $i++;
    }
    my $sql
        = "UPDATE nt_nameserver_export_log set "
        . join( ',', @stats )
        . ", date_finish = $date_finish WHERE nt_nameserver_export_log_id = $row";
    $dbh_write->do($sql);
    warn "$sql\n" if $DEBUG_SQL;
}

sub get_export_status {
    my ( $ns, $dbh ) = @_;
    my $sql
        = "SELECT status FROM nt_nameserver_export_procstatus WHERE nt_nameserver_id = "
        . $dbh->quote( $ns->{nt_nameserver_id} );
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $DEBUG_SQL;
    $sth->execute;
    if ( my $nshash = $sth->fetchrow_hashref ) {
        return $nshash->{status};
    }
    else {
        return undef;
    }
}

sub set_export_status {
    my ( $ns, $dbh, $status ) = @_;
    my $sql;
    unless ($ns_status_exist) {
        $sql
            = "SELECT nt_nameserver_id FROM nt_nameserver_export_procstatus WHERE nt_nameserver_id = "
            . $dbh->quote( $ns->{nt_nameserver_id} );
        my $sth = $dbh->prepare($sql);
        warn "$sql\n" if $DEBUG_SQL;
        $sth->execute;
        if ( my $nshash = $sth->fetchrow_hashref ) {
            $sql
                = "UPDATE nt_nameserver_export_procstatus set timestamp = "
                . time()
                . ", status = "
                . $dbh->quote($status)
                . " WHERE nt_nameserver_id = $ns->{nt_nameserver_id}";
        }
        else {
            $sql
                = "INSERT INTO nt_nameserver_export_procstatus(nt_nameserver_id, timestamp, status) VALUES ($ns->{nt_nameserver_id},"
                . time() . ","
                . $dbh->quote($status) . ")";
        }
        $ns_status_exist = 1;
    }
    else {
        $sql
            = "UPDATE nt_nameserver_export_procstatus set timestamp = "
            . time()
            . ", status = "
            . $dbh->quote($status)
            . " WHERE nt_nameserver_id = $ns->{nt_nameserver_id}";
    }
    $dbh->do($sql);
    warn "$sql\n" if $DEBUG_SQL;
}

sub graceful_exit {
    my $signal = shift;

    my $dbh = &db_object_write;
    &set_export_status( $ns, $dbh, "export process stopped ($signal)" );
    $dbh->disconnect;
    $closes++;
    exit;
}

sub runmake {
    my $cmd        = shift;
    my $make_start = time;
    system("make $cmd");    # or die "unable to exec make $cmd -- $!\n";
    return time - $make_start;
}

sub files_diff {

    #my $dir = shift;
    my @files = @_;
    return -1 unless scalar @files eq 2;
    my @md5sums;
    foreach my $f (@files) {
        return -1 unless -f $f;
        my $ctx = Digest::MD5->new;
        my $sum;
        if ( -f "$f.md5" ) {
            open( F, "$f.md5" );
            my $sum = <F>;
            close(F);
            chomp $sum;
        }
        if ( !-f "$f.md5" || $sum !~ /[0-9a-f]+/i ) {
            open( F, "$f" );
            $ctx->addfile(*F);
            $sum = $ctx->hexdigest;
            close(F);
        }
        push( @md5sums, $sum );
        open( F, ">$f.md5" );
        print F $sum;
        close(F);
    }

  #warn "checksum $files[0]: $md5sums[0], $files[1]: $md5sums[1]\n" if $DEBUG;
    if ( $md5sums[0] eq $md5sums[1] ) {
        return 0;
    }
    return 1;
}

