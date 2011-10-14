#!/usr/bin/perl
#
# $Id: build_summary.pl 639 2008-09-13 04:43:46Z matt $
#
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

# TODO TODO TODO

# every X minutes, this scripts computes totals of the number of
# objects and the opertions on those objects in the last X minutes.

use strict;
use DBI;

my $DEBUG     = 0;
my $DEBUG_SQL = 0;

my %sums = (
    nt_zone_general_summary => {
        table     => 'nt_zone',
        field     => 'zones',
        log_table => 'nt_zone_log'
    },
    nt_group_summary => {
        table     => 'nt_group',
        field     => 'groups',
        log_table => 'nt_group_log'
    },
    nt_user_summary => {
        table     => 'nt_user',
        field     => 'users',
        log_table => 'nt_user_log'
    },
    nt_nameserver_general_summary => {
        table     => 'nt_nameserver',
        field     => 'nameservers',
        log_table => 'nt_nameserver_log'
    }
);

my $now = time;
my $sum_start;
if ( $ARGV[0] )
{ # if true, compute stats for THIS hour, otherwise, step back to last _full_ hour.
    $sum_start = $now - ( $now % 3600 );
}
else {
    $sum_start = $now - ( $now % 3600 ) - 3600;
}
my $sum_end = $sum_start + 3599;
my $period  = $sum_end;

if ($DEBUG) {
    my $sum_startx = localtime($sum_start);
    my $sum_endx   = localtime($sum_end);
    print "computing stats from $sum_startx to $sum_endx (period #$period)\n";
}

my ( $sth, $sql );
my %log_actions = ( 'additions', 1, 'modifications', 2, 'deletions', 3 );
my $dbh = &db_object;

&traverse_groups('1');    # start at parent_group_id 1

$sth = undef;
$dbh->disconnect;

# recursive function that builds a tree of group and sub-group pairings, once it hits the end of a
# tree (a node), it generates summaries. this allows bottom up building of the child counts.
sub traverse_groups {
    my $seed = shift;
    my @children;
    my $sth
        = $dbh->prepare(
        "select * from nt_group where parent_group_id = $seed and (DELETED IS NULL OR (DELETED >= $sum_start AND DELETED <= $sum_end))"
        );
    $sth->execute;
    while ( my $r = $sth->fetchrow_hashref ) {
        print
            "found sub-group of nt_group_id $seed -- $r->{'name'} ($r->{'group_id'})\n"
            if $DEBUG;
        push( @children, $r->{'nt_group_id'} );
        &traverse_groups( $r->{'nt_group_id'} );
    }
    &generate_summary( $seed, @children );
}

# given a gid and it's children, generate summary stats
sub generate_summary {
    my $gid      = shift;
    my @children = @_;

    foreach my $sum ( keys %sums ) {
        my $data = {};

        # count the total # of objects at this group level
        $sql
            = "select count(*) from $sums{$sum}->{'table'} where nt_group_id = $gid AND added <= $sum_end AND (DELETED IS NULL OR (DELETED >= $sum_start AND DELETED <= $sum_end))";
        print "sql = $sql\n" if $DEBUG_SQL;
        $sth = $dbh->prepare($sql);
        $sth->execute;
        $data->{ $sums{$sum}->{'field'} } = $sth->fetch->[0];
        $sth->finish;

        # add up the total child objects that this nt_group_id owns.
        if (@children) {
            $sql
                = "SELECT sum($sums{$sum}->{field}),sum(children) from $sum where period = $period AND nt_group_id IN (";
            $sql .= join( ',', @children ) . ")";
            $sth = $dbh->prepare($sql);
            $sth->execute;
            my $results = $sth->fetch;
            $data->{children} = $results->[0] + $results->[1];
            print "sql = $sql\n" if $DEBUG_SQL;
        }
        $data->{children} = '0' unless ( $data->{children} );

        # count sum_log actions of type X in last period
        foreach my $action ( keys %log_actions ) {
            $sql
                = "select count(*) from $sums{$sum}->{'log_table'} where nt_group_id = $gid AND timestamp >= $sum_start AND timestamp <= $sum_end AND nt_log_action_id = $log_actions{$action}";
            $sth = $dbh->prepare($sql);
            $sth->execute;
            $data->{$action} = $sth->fetch->[0];
            if (@children) {
                $sql
                    = "select sum($action), sum(child_$action) from $sum where period = $period AND nt_group_id in (";
                $sql .= join( ',', @children ) . ")";
                $sth = $dbh->prepare($sql);
                $sth->execute;
                my $results = $sth->fetch;
                $data->{"child_$action"} = $results->[0] + $results->[1];
            }
            else {
                $data->{"child_$action"} = 0;
            }
        }

        $sth->finish;
        if ($DEBUG) {
            print "$sum totals for gid $gid with children @children:\n";
            foreach my $dk ( keys %$data ) {
                print "$dk = $data->{$dk}\n";
            }
        }
        $data->{nt_group_id} = $gid;
        $data->{period}      = $period;

        my @columns = keys(%$data);
        $sql = "INSERT INTO $sum( " . join( ',', @columns ) . ") VALUES (";
        $sql
            .= join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
        $dbh->do($sql) || warn "sql = $sql\n";

        if ( $sum eq "nt_zone_general_summary" ) {
            my %data = (
                'zone_records',              0,
                'zone_record_additions',     0,
                'zone_record_modifications', 0,
                'zone_record_deletions',     0,
                'queries_norecord',          0,
                'queries_successful',        0,
                'zone_nameservers',          0,
                'zone_nameserver_additions', 0,
                'zone_nameserver_deletions', 0
            );
            &zone_summary( $gid, \%data );
            &update_general_summary( $sum, \%data, $gid, \@children,
                'nt_zone_id' );
        }

        if ( $sum eq "nt_user_general_summary" ) {
            my %data = ( 'logins', 0, 'logouts', 0, 'timeouts', 0 );
            &user_summary( $gid, \%data );
            &update_general_summary( $sum, \%data, $gid, \@children,
                'nt_user_id' );
        }
        if ( $sum eq "nt_nameserver_general_summary" ) {
            my %data = (
                'queries_norecord', 0, 'queries_successful', 0,
                'queries_nozone',   0, 'total_zones',        0,
                'total_records',    0
            );
            &nameserver_summary( $gid, \%data );
            &update_general_summary( $sum, \%data, $gid, \@children,
                'nt_nameserver_id' );
        }

    }
}

sub update_general_summary {
    my ( $table, $data, $gid, $children, $key ) = @_;
    delete( $data->{$key} );
    delete( $data->{period} );
    my @sum_fields = keys( %{$data} );

    my ( $sql, $sth );
    if ( @{$children} ) {

        # this is nasty, but it works .. TODO - cleanup
        my @child_fields = @sum_fields;
        for ( my $i; $i <= $#child_fields; $i++ ) {
            $child_fields[$i] =~ s/(.*)/sum(child_$1),sum($1)/;
        }
        my $count = join( ",", @child_fields );
        $sql
            = "select $count from $table where period = $period and nt_group_id in (";
        $sql .= join( ',', @{$children} ) . ")";
        $sth = $dbh->prepare($sql);
        $sth->execute || warn "failed sql = $sql\n";
        my $child_data = $sth->fetchrow_hashref;
        foreach my $key ( keys %$child_data ) {
            my $field = $key;
            $field =~ s/sum\(//;
            $field =~ s/\)//;
            $field =~ s/(.*)/child_$1/;
            if ( $field =~ /child_child_/ ) {
                my $real_field = $field;
                $real_field =~ s/child_(.*)/$1/;
                $data->{$real_field} += $child_data->{$key};
                next;
            }
            $data->{$field} = $child_data->{$key};
            push( @sum_fields, $field );
        }
    }

    $sql
        = "UPDATE $table SET "
        . join( ',',
        map( "$_ = " . $dbh->quote( $data->{$_} ), @sum_fields ) )
        . " WHERE nt_group_id = $gid AND period = $period";

    #warn "$table sql = $sql ..\n";
    $dbh->do($sql);
}

sub db_object {
    my $engine   = 'mysql';
    my $database = 'nictool';
    my $host     = 'localhost';
    my $user     = 'nictool';
    my $password = 'v205';
    my @connect
        = ( "dbi:$engine:database=$database:host=$host", $user, $password );
    my $dbh ||= DBI->connect(@connect);
    print "@connect" unless $dbh;
    return $dbh;
}

sub zone_summary {
    my ( $gid, $t ) = @_;

    my $sth
        = $dbh->prepare(
        "select nt_zone_id from nt_zone where nt_group_id = $gid AND (DELETED IS NULL OR (DELETED >= $sum_start AND DELETED <= $sum_end))"
        );
    $sth->execute;
    while ( my $z = $sth->fetchrow_hashref ) {

        my %data = ( 'nt_zone_id', $z->{'nt_zone_id'}, 'period', $period );

        # zone record totals
        &zone_record_summary( $z->{'nt_zone_id'}, \%data );

        # zone nameserver (query) totals
        &zone_nameserver_summary( $z->{'nt_zone_id'}, \%data );

        # zone_record_operations
        &zone_ops_sum( $z->{'nt_zone_id'}, 'nt_zone_record_log',
            'zone_record_', \%data );

        # zone_nameserver_opertions
        &zone_ops_sum( $z->{'nt_zone_id'}, 'nt_zone_nameserver_log',
            'zone_nameserver_', \%data );

# save nt_zone_summary and save/update nt_zone_current_summary. also add data to t for group total..
        &save_obj_summary( \%data, $t, 'nt_zone_summary',
            'nt_zone_current_summary', 'nt_zone_id' );

    }
}

sub zone_ops_sum {
    my ( $zone_id, $logtable, $hashkey, $h ) = @_;

    my ( $sql, $sth, $additions, $modifications, $deletions );
    $h->{ $hashkey . 'additions' }     = 0;
    $h->{ $hashkey . 'modifications' } = 0
        unless ( $hashkey eq "zone_nameserver_" );
    $h->{ $hashkey . 'deletions' } = 0;

    foreach my $action ( keys %log_actions ) {
        next
            if ( $action eq "modifications"
            && $hashkey eq "zone_nameserver_" );
        $sql
            = "select count(*) from $logtable where nt_zone_id = $zone_id AND nt_log_action_id = $log_actions{$action} AND timestamp >= $sum_start AND timestamp <= $sum_end";
        $sth = $dbh->prepare($sql);
        $sth->execute;
        $h->{ $hashkey . $action } = $sth->fetch->[0];
    }
}

sub zone_record_summary {
    my ( $zone_id, $h ) = @_;

    $h->{'zone_records'} = 0;
    my $sth
        = $dbh->prepare(
        "select * from nt_zone_record where nt_zone_id = $zone_id AND added <= $sum_end AND (DELETED IS NULL OR (DELETED >= $sum_start AND DELETED <= $sum_end))"
        );
    $sth->execute;
    while ( my $r = $sth->fetchrow_hashref ) {
        my $rid = $r->{'nt_zone_record_id'};
        my $sql
            = "select count(*) from nt_nameserver_qlog where nt_zone_record_id = $rid AND timestamp >= $sum_start AND timestamp <= $sum_end";
        my $sthq = $dbh->prepare($sql);
        $sthq->execute;
        my $queries = $sthq->fetch->[0];
        $dbh->do(
            "INSERT into nt_zone_record_summary(period, nt_zone_record_id, queries) values ($period, $rid, $queries)"
        );
        $h->{'zone_records'}++;

        my $sql
            = "select nt_zone_record_id from nt_zone_record_current_summary WHERE nt_zone_record_id = $rid";
        my $sth_current = $dbh->prepare($sql);
        $sth_current->execute;
        if ( $sth_current->rows ) {
            $dbh->do(
                "UPDATE nt_zone_record_current_summary set period = $period, queries = $queries where nt_zone_record_id = $rid"
            );
        }
        else {
            $dbh->do(
                "INSERT into nt_zone_record_current_summary(nt_zone_record_id, period, queries) VALUES ($rid, $period, $queries)"
            );
        }
    }
}

sub zone_nameserver_summary {
    my ( $zone_id, $h ) = @_;

    $h->{'queries_norecord'}   = 0;
    $h->{'queries_successful'} = 0;
    $h->{'zone_nameservers'}   = 0;
    my $total_q_f   = 0;
    my $total_q_s   = 0;
    my $nameservers = 0;
    my $sth_ns
        = $dbh->prepare(
        "select nt_nameserver_id,nt_zone_nameserver_id from nt_zone_nameserver where nt_zone_id = $zone_id AND added <= $sum_end AND (DELETED IS NULL OR (DELETED >= $sum_start AND DELETED <= $sum_end))"
        );
    $sth_ns->execute;

    while ( my $ns_row = $sth_ns->fetch ) {
        my $ns_id      = $ns_row->[0];
        my $zone_ns_id = $ns_row->[1];
        my $sth
            = $dbh->prepare(
            "select count(*) from nt_nameserver_qlog where nt_zone_id = $zone_id AND nt_zone_record_id != 0 AND nt_nameserver_id = $ns_id AND timestamp >= $sum_start and timestamp <= $sum_end"
            );
        $sth->execute;
        my $successful = $sth->fetch->[0];
        $sth
            = $dbh->prepare(
            "select count(*) from nt_nameserver_qlog where nt_zone_id = $zone_id AND nt_nameserver_id = $ns_id AND nt_zone_record_id = 0 AND timestamp >= $sum_start and timestamp <= $sum_end"
            );
        $sth->execute;
        my $norecord = $sth->fetch->[0];
        $dbh->do(
            "INSERT into nt_zone_nameserver_summary(period, nt_zone_nameserver_id, queries_norecord, queries_successful) VALUES ($period,$zone_ns_id, $norecord, $successful)"
        );
        $h->{'queries_norecord'}   += $norecord;
        $h->{'queries_successful'} += $successful;
        $h->{'zone_nameservers'}++;

        my $sth_current
            = $dbh->prepare(
            "select nt_zone_nameserver_id from nt_zone_nameserver_current_summary WHERE nt_zone_nameserver_id = $zone_ns_id"
            );
        $sth_current->execute;
        if ( $sth_current->rows ) {
            $dbh->do(
                "UPDATE nt_zone_nameserver_current_summary set period = $period, queries_norecord = $norecord, queries_successful = $successful where nt_zone_nameserver_id = $zone_ns_id"
            );
        }
        else {
            $dbh->do(
                "INSERT into nt_zone_nameserver_current_summary(nt_zone_nameserver_id, period, queries_norecord, queries_successful) VALUES ($zone_ns_id, $period, $norecord, $successful)"
            );
        }

    }
}

sub nameserver_summary {
    my ( $gid, $t ) = @_;

    my $sth
        = $dbh->prepare(
        "select nt_nameserver_id from nt_nameserver where nt_group_id = $gid AND added <= $sum_end AND (DELETED IS NULL OR (DELETED >= $sum_start AND DELETED <= $sum_end))"
        );
    $sth->execute;
    while ( my $ns = $sth->fetchrow_hashref ) {

        my %data = (
            'nt_nameserver_id', $ns->{'nt_nameserver_id'},
            'period', $period
        );

        # total queries_nozone
        my $sth
            = $dbh->prepare(
            "select count(*) from nt_nameserver_qlog where nt_zone_id = 0 AND nt_zone_record_id = 0 AND nt_nameserver_id = $ns->{'nt_nameserver_id'} AND timestamp >= $sum_start AND timestamp <= $sum_end"
            );
        $sth->execute;
        $data{queries_nozone} = $sth->fetch->[0];

        # total queries_norecord
        $sth
            = $dbh->prepare(
            "select count(*) from nt_nameserver_qlog where nt_zone_id != 0 AND nt_zone_record_id = 0 AND nt_nameserver_id = $ns->{'nt_nameserver_id'} AND timestamp >= $sum_start AND timestamp <= $sum_end"
            );
        $sth->execute;
        $data{queries_norecord} = $sth->fetch->[0];

        # total queries_successful
        $sth
            = $dbh->prepare(
            "select count(*) from nt_nameserver_qlog where nt_zone_id != 0 AND nt_zone_record_id != 0 AND nt_nameserver_id = $ns->{'nt_nameserver_id'} AND timestamp >= $sum_start AND timestamp <= $sum_end"
            );
        $sth->execute;
        $data{queries_successful} = $sth->fetch->[0];

        # total zones
        &nameserver_obj_summary( $ns->{'nt_nameserver_id'}, \%data );

# save nt_nameserver_summary and save/update nt_nameserver_current_summary. also add data to t for group total..
        &save_obj_summary( \%data, $t, 'nt_nameserver_summary',
            'nt_nameserver_current_summary',
            'nt_nameserver_id' );

    }
}

sub nameserver_obj_summary {
    my ( $ns_id, $h ) = @_;

    $h->{total_records} = 0;
    $h->{total_zones}   = 0;
    my %z;
    my $sth
        = $dbh->prepare(
        "select nt_zone_id from nt_zone_nameserver where nt_nameserver_id = $ns_id AND added <= $sum_end AND (DELETED IS NULL OR (DELETED >= $sum_start AND DELETED <= $sum_end))"
        );
    $sth->execute;
    while ( my $zns = $sth->fetchrow_hashref ) {
        $z{ $zns->{'nt_zone_id'} } = 1;
    }
    foreach my $zone_id ( keys %z ) {
        $h->{total_zones}++;
        $sth
            = $dbh->prepare(
            "select zone_records from nt_zone_summary where period = $period and nt_zone_id = $zone_id"
            );
        $sth->execute;
        my $f;
        $h->{total_records} += $f->[0] if ( $f = $sth->fetch );
    }
}

sub user_summary {
    my ( $gid, $t ) = @_;

    my $sth
        = $dbh->prepare(
        "select nt_user_id from nt_user where nt_group_id = $gid AND (DELETED IS NULL OR (DELETED >= $sum_start AND DELETED <= $sum_end))"
        );
    $sth->execute;
    while ( my $user = $sth->fetchrow_hashref ) {

        my %data = (
            'logins', 0, 'logouts', 0, 'timeouts', 0, 'nt_user_id',
            $user->{'nt_user_id'}, 'period', $period
        );

        # total logins
        my $sth
            = $dbh->prepare(
            "select count(*) from nt_user_session_log where nt_user_id = $user->{'nt_user_id'} AND nt_log_action_id = 4 AND timestamp >= $sum_start AND timestamp <= $sum_end"
            );
        $sth->execute;
        $data{logins} = $sth->fetch->[0];

        # total logouts
        my $sth
            = $dbh->prepare(
            "select count(*) from nt_user_session_log where nt_user_id = $user->{'nt_user_id'} AND nt_log_action_id = 5 AND timestamp >= $sum_start AND timestamp <= $sum_end"
            );
        $sth->execute;
        $data{logouts} = $sth->fetch->[0];

        # total timeouts
        my $sth
            = $dbh->prepare(
            "select count(*) from nt_user_session_log where nt_user_id = $user->{'nt_user_id'} AND nt_log_action_id = 6 AND timestamp >= $sum_start AND timestamp <= $sum_end"
            );
        $sth->execute;
        $data{timeouts} = $sth->fetch->[0];

        &save_obj_summary( \%data, $t, 'nt_user_summary',
            'nt_user_current_summary', 'nt_user_id' );
    }
}

sub save_obj_summary {
    my ( $data, $t, $sum_table, $sum_current_table, $key ) = @_;

    # add specific obj totals to group totals..
    my @columns;
    foreach my $x ( keys %{$data} ) {
        $t->{$x} += $data->{$x};
        push( @columns, $x );
    }

    my $sql
        = "INSERT into $sum_table ("
        . join( ',', @columns )
        . ") VALUES ("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
    $dbh->do($sql);

    $sql = "select $key from $sum_current_table where $key = $data->{$key}";
    my $sth_z = $dbh->prepare($sql);
    $sth_z->execute;
    if ( $sth_z->rows ) {
        $sql
            = "UPDATE $sum_current_table SET "
            . join( ',',
            map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ) )
            . " WHERE $key = $data->{$key}";
        $dbh->do($sql) || warn "failed sql = $sql\n";
    }
    else {
        $sql
            = "INSERT into $sum_current_table ("
            . join( ',', @columns )
            . ") VALUES ("
            . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
        $dbh->do($sql) || warn "failed sql = $sql\n";
    }
}

