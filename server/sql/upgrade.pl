#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use DBIx::Simple;
use Getopt::Long;
use Params::Validate qw/:all/;
$Data::Dumper::Sortkeys = 1;

# process command line options
Getopt::Long::GetOptions(
    'dsn=s'  => \my $dsn,
    'user=s' => \my $db_user,
    'pass=s' => \my $db_pass,
    'host=s' => \my $db_host,
    'prune' => \my $prune,
) or die "error parsing command line options";

if ( !defined $dsn || !defined $db_user || !defined $db_pass ) {
    get_db_creds_from_nictoolserver_conf();
}

$db_host = ask( "database host", default => 'localhost' ) if !$db_host;
$dsn     = ask( "database DSN",  default => "DBI:mysql:database=nictool;host=$db_host;port=3306" )
    if !$dsn;
$db_user = ask( "database user", default  => 'root' ) if !$db_user;
$db_pass = ask( "database pass", password => 1 )      if !$db_pass;

prompt_last_chance();

my $dbh = DBIx::Simple->connect( $dsn, $db_user, $db_pass )
    or die DBIx::Simple->error;

# NOTE: when making schema changes, update db_version in 12_nt_options.sql
my @versions = qw/ 2.00 2.05 2.08 2.09 2.10 2.11 2.14 2.15 2.16 2.17 2.18
    2.24 2.27 2.28 2.29 2.30 2.32 2.34 2.35 2.40 2.41 /;

foreach my $version (@versions) {

    # first, run a DB test query
    my $test_sub = '_sql_test_' . $version;    # assemble sub name
    $test_sub =~ s/\./_/g;                     # replace . with _
    no strict 'refs';                          ## no critic
    my $is_applied = &$test_sub;
    use strict;
    if ($is_applied) {                         # run the test
        print "Skipping v$version SQL updates (already applied).\n";
        next;
    }

    # run the SQL updates, if needed
    print "applying v $version SQL updates\n";
    my $queries = '_sql_' . $version;
    $queries =~ s/\./_/g;                      # replace . with _
    no strict 'refs';                          ## no critic
    my $q_string = &$queries;                  # fetch the queries
    use strict;
    $q_string =~ s/[\s]{2,}/ /g;               # condense whitespace

    foreach my $q ( split( ';', $q_string ) ) {    # split string into queries
        next if $q =~ /^\s+$/;                         # skip blank entries
        print "$q;\n";                                 # show the query to user
        sleep 1;                                       # give 'em time to read it
        $dbh->query($q) or die DBIx::Simple->error;    # run it!
    }
    print "\n";
}

heal();

sub _fks_2_41 {
    return (
        # [ table, constraint_name, column, ref_table, ref_column ]
        [ 'nt_zone_log',         'nt_zone_log_ibfk_1',         'nt_zone_id',        'nt_zone',        'nt_zone_id' ],
        [ 'nt_zone_log',         'nt_zone_log_ibfk_2',         'nt_group_id',       'nt_group',       'nt_group_id' ],
        [ 'nt_zone_log',         'nt_zone_log_ibfk_3',         'nt_user_id',        'nt_user',        'nt_user_id' ],
        [ 'nt_zone_record',      'nt_zone_record_ibfk_1',      'nt_zone_id',        'nt_zone',        'nt_zone_id' ],
        [ 'nt_zone_record_log',  'nt_zone_record_log_ibfk_1', 'nt_zone_id',         'nt_zone',        'nt_zone_id' ],
        [ 'nt_zone_record_log',  'nt_zone_record_log_ibfk_2', 'nt_user_id',         'nt_user',        'nt_user_id' ],
        [ 'nt_zone_record_log',  'nt_zone_record_log_ibfk_3', 'nt_zone_record_id',  'nt_zone_record', 'nt_zone_record_id' ],
        [ 'nt_user_session_log', 'nt_user_session_log_ibfk_1', 'nt_user_id',        'nt_user',        'nt_user_id' ],
        [ 'nt_user_session',     'nt_user_session_ibfk_1',     'nt_user_id',        'nt_user',        'nt_user_id' ],
        [ 'nt_user_global_log',  'nt_user_global_log_ibfk_1',  'nt_user_id',        'nt_user',        'nt_user_id' ],
        [ 'nt_nameserver',       'nt_nameserver_ibfk_1',       'nt_group_id',       'nt_group',       'nt_group_id' ],
        [ 'nt_group_subgroups',  'nt_group_subgroups_ibfk_1',  'nt_group_id',       'nt_group',       'nt_group_id' ],
        [ 'nt_group_log',        'nt_group_log_ibfk_1',        'nt_group_id',       'nt_group',       'nt_group_id' ],
        [ 'nt_delegate',         'nt_delegate_ibfk_1',         'nt_group_id',       'nt_group',       'nt_group_id' ],
    );
}

sub _try_list {
    my ($sql) = @_;
    my @r;
    # flat, not list: list returns only the first row
    eval { @r = $dbh->query($sql)->flat; };
    return @r;
}

# Version-independent repairs for drift left behind by historical versions of
# this script (see the git log of sql/upgrade.pl). Detection is read-only;
# every fix is idempotent and preserves data.
sub heal {

    my @heals;

    # pre-2026 _sql_test_2_08 left a probe row in nt_user on every single run.
    # Only rows matching the probe's complete fingerprint AND referenced by
    # nothing are removed; a legitimate deleted account keeps its audit trail.
    my $probe_where =
        "nt_group_id=1 AND first_name='first' AND last_name='last'
            AND username='test' AND password='123456789012345678'
            AND email='deleteme\@test.com' AND deleted=1";
    my @probe_ids = _try_list("SELECT nt_user_id FROM nt_user WHERE $probe_where");
    my @unreferenced = grep { !_user_is_referenced($_) } @probe_ids;
    push @heals,
        [ "remove nt_user probe row(s) left by old _sql_test_2_08",
          "DELETE FROM nt_user WHERE nt_user_id IN (" . join( ',', @unreferenced ) . ")
            AND $probe_where" ]
        if @unreferenced;

    # 2014-2020 releases of the v2.28 block created last_publish as
    # TIMESTAMP NOT NULL DEFAULT 0 (changed to DATETIME NULL in #249)
    my ($lp_type) = _try_list(
        "SELECT DATA_TYPE FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'nt_zone' AND COLUMN_NAME = 'last_publish'");
    push @heals,
        [ "nt_zone.last_publish is TIMESTAMP (pre-#249 v2.28 block); convert to DATETIME",
          "ALTER TABLE nt_zone MODIFY last_publish DATETIME DEFAULT NULL" ]
        if $lp_type && lc($lp_type) eq 'timestamp';

    # releases 2.31-2.33 shipped the v2.32 block but never wired 2.32 into the version list
    for my $table (qw/ nt_nameserver_qlog nt_nameserver_qlogfile /) {
        my ($present) = _try_list(
            "SELECT COUNT(*) FROM information_schema.TABLES
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '$table'");
        push @heals,
            [ "drop $table (v2.32 block was skipped by releases 2.31-2.33)",
              "DROP TABLE IF EXISTS $table" ]
            if $present;
    }

    # the v2.10 block as released in 2011 created nt_zone_nameserver.nt_zone_id
    # as smallint; fixed a week later (863a05e), healed for upgraders in v2.11
    my ($zn_type) = _try_list(
        "SELECT COLUMN_TYPE FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'nt_zone_nameserver' AND COLUMN_NAME = 'nt_zone_id'");
    push @heals,
        [ "nt_zone_nameserver.nt_zone_id is smallint (2011 v2.10 block); widen to int",
          "ALTER TABLE nt_zone_nameserver MODIFY nt_zone_id int(10) unsigned NOT NULL" ]
        if $zn_type && $zn_type =~ /smallint/i;

    # DBs upgraded through both the 2011 v2.10 and v2.11 blocks carry duplicate
    # unique indexes: zone_ns_id (2.10, canonical) and zone_ns (2.11 heal)
    my %zn_idx = map { $_ => 1 } _try_list(
        "SELECT DISTINCT INDEX_NAME FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'nt_zone_nameserver'");
    push @heals,
        [ "drop duplicate nt_zone_nameserver index zone_ns (zone_ns_id is canonical)",
          "ALTER TABLE nt_zone_nameserver DROP INDEX zone_ns" ]
        if $zn_idx{zone_ns} && $zn_idx{zone_ns_id};

    # a 2014 release window applied v2.27 without adding the pass_salt columns
    for my $table (qw/ nt_user nt_user_log /) {
        push @heals,
            [ "$table.pass_salt missing (2014 v2.27 probe bug); add it",
              "ALTER TABLE $table ADD COLUMN pass_salt VARCHAR(16) AFTER password" ]
            if !_column_exists( $table, 'pass_salt' );
    }

    # the v2.18 block shipped on CPAN in 2013 lacked several RR types; restore
    # any missing rows (without touching flags on rows the operator may have edited)
    my ($rrt_count) = _try_list(
        "SELECT COUNT(*) FROM resource_record_type WHERE id IN
            (1,2,5,6,12,13,15,16,24,25,28,29,30,33,35,39,43,44,46,47,48,50,51,99,250,252,256,257)");
    push @heals,
        [ "restore missing resource_record_type rows (2013 v2.18 block shipped fewer)",
          "INSERT IGNORE INTO resource_record_type (id, name, description, reverse, forward, obsolete)
            VALUES
            (1,'A','Address',1,1,0), (2,'NS','Name Server',1,1,0),
            (5,'CNAME','Canonical Name',1,1,0), (6,'SOA','Start Of Authority',0,0,0),
            (12,'PTR','Pointer',1,1,0), (13,'HINFO','Host Info',0,0,1),
            (15,'MX','Mail Exchanger',0,1,0), (16,'TXT','Text',1,1,0),
            (24,'SIG','Signature',0,0,0), (25,'KEY','Key',0,0,0),
            (28,'AAAA','Address IPv6',0,1,0), (29,'LOC','Location',0,1,0),
            (30,'NXT','Next',0,0,1), (33,'SRV','Service',0,1,0),
            (35,'NAPTR','Naming Authority Pointer',1,1,0), (39,'DNAME','Delegation Name',0,0,0),
            (43,'DS','Delegation Signer',1,1,0), (44,'SSHFP','Secure Shell Key Fingerprints',0,1,0),
            (46,'RRSIG','Resource Record Signature',0,1,0), (47,'NSEC','Next Secure',0,1,0),
            (48,'DNSKEY','DNS Public Key',0,1,0), (50,'NSEC3','Next Secure v3',0,0,0),
            (51,'NSEC3PARAM','NSEC3 Parameters',0,0,0), (99,'SPF','Sender Policy Framework',0,0,1),
            (250,'TSIG','Transaction Signature',0,0,0), (252,'AXFR',NULL,0,0,0),
            (256,'URI','URI',0,1,0), (257,'CAA','Certification Authority Authorization',0,1,0)" ]
        if defined $rrt_count && $rrt_count < 28;

    # 2014 pre-release versions of the v2.24 block lacked the knot export type
    my ($knot) = _try_list("SELECT COUNT(*) FROM nt_nameserver_export_type WHERE id=8");
    push @heals,
        [ "restore nt_nameserver_export_type row 8 (knot)",
          "INSERT IGNORE INTO nt_nameserver_export_type (id, name, descr, url)
            VALUES (8,'knot','Knot DNS','www.knot-dns.cz')" ]
        if defined $knot && !$knot;

    return if !@heals;

    print "applying schema repairs\n";
    for my $heal (@heals) {
        my ( $why, $sql ) = @$heal;
        $sql =~ s/[\s]{2,}/ /g;
        print "  # $why\n  $sql;\n";
        $dbh->query($sql) or die DBIx::Simple->error;
    }
    print "\n";
}

# true if any row anywhere refers to this user id. An unreadable table counts
# as a reference: deletion must be provably safe, so probe rows are kept when
# in doubt (they are harmless; the old script tolerated them for a decade).
sub _user_is_referenced {
    my ($id) = @_;
    $id =~ /\A[0-9]+\z/ or return 1;
    for my $ref (
        [ 'nt_group_log',        'nt_user_id' ],
        [ 'nt_user_log',         'nt_user_id' ],
        [ 'nt_user_log',         'modified_user_id' ],
        [ 'nt_user_session',     'nt_user_id' ],
        [ 'nt_user_session_log', 'nt_user_id' ],
        [ 'nt_user_global_log',  'nt_user_id' ],
        [ 'nt_nameserver_log',   'nt_user_id' ],
        [ 'nt_zone_log',         'nt_user_id' ],
        [ 'nt_zone_record_log',  'nt_user_id' ],
        [ 'nt_perm',             'nt_user_id' ],
        [ 'nt_delegate',         'delegated_by_id' ],
        [ 'nt_delegate_log',     'nt_user_id' ],
        # polymorphic references: the id column points at a user only when
        # the accompanying type column says so
        [ 'nt_delegate',        'nt_object_id', "nt_object_type = 'USER'" ],
        [ 'nt_delegate_log',    'nt_object_id', "nt_object_type = 'USER'" ],
        [ 'nt_user_global_log', 'object_id',    "object = 'user'" ],
        [ 'nt_user_global_log', 'target_id',    "target = 'user'" ],
    ) {
        my ( $table, $column, $cond ) = @$ref;
        my ($tables) = _try_list(
            "SELECT COUNT(*) FROM information_schema.TABLES
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '$table'");
        next if defined $tables && !$tables;    # table absent: nothing to reference
        my $where = "$column = $id" . ( $cond ? " AND $cond" : '' );
        my ($n) = _try_list("SELECT COUNT(*) FROM $table WHERE $where");
        if ( !defined $n || $n ) {
            print "  leaving nt_user row $id: matches the old _sql_test_2_08 probe "
                . "fingerprint but is referenced by $table.$column\n";
            return 1;
        }
    }
    return 0;
}

sub _column_exists {
    my ( $table, $column ) = @_;
    my $r;
    eval { $r = $dbh->query("SHOW COLUMNS FROM `$table` LIKE '$column'")->hashes; };
    return ( $r && $r->[0] && $r->[0]{field} ) ? 1 : 0;
}

sub _existing_fks {
    my $rows;
    eval {
        $rows = $dbh->query(
            "SELECT TABLE_NAME AS t, CONSTRAINT_NAME AS c FROM information_schema.TABLE_CONSTRAINTS " .
                "WHERE TABLE_SCHEMA = DATABASE() AND CONSTRAINT_TYPE = 'FOREIGN KEY'"
        )->hashes;
    };
    my %existing;
    return \%existing if !$rows;
    for my $row (@$rows) {
        $existing{ $row->{t} }{ $row->{c} } = 1;
    }
    return \%existing;
}

sub _sql_test_2_41 {
    my $r = _get_db_version();
    return 1 if !defined $r;    # query failed

    my $existing = _existing_fks();
    for my $fk ( _fks_2_41() ) {
        my ( $table, $name ) = @$fk;
        return 0 if !$existing->{$table}{$name};    # any expected FK missing -> apply
    }

    return 0 if $r < 2.41;                          # FKs present but db_version behind
    return 1;
}

# The v2.41 FKs to nt_user cannot be added while log rows reference users that
# don't exist. Two repairable classes, neither of which warrants deleting audit
# history (the previously documented remedies, DELETE and --prune, do):
#  - nt_user_id=0 in nt_zone_record_log: the Zone/Record/Sanity.pm TTL-sync
#    cascade dropped attribution (fixed alongside this). The actor is provable
#    when exactly one attributed edit of the same RRset carries the same new
#    TTL in the same second; anything less stays unattributed, never guessed.
#    nt_zone_log rows never came from that cascade, so they are not remapped.
#  - nt_user_id>0 with no nt_user row: the user was hard-deleted. Restore a
#    tombstone row (deleted=1) so history keeps its original attribution.
# Rows referencing hard-deleted zones/groups/records have no parent to repair
# and still go through the existing prune/abort path.
sub _repair_user_orphans_2_41 {

    # The cascade's fingerprint: _valid_ttl copies the triggering edit's new
    # TTL onto every *other* record of the same RRset (zone + name + type),
    # logging each as 'modified' in the same request. Attribute an orphan only
    # to the single attributed 'added'/'modified' sibling matching all of that.
    my ($zeros) = _try_list(
        "SELECT COUNT(*) FROM nt_zone_record_log WHERE nt_user_id = 0");
    if ($zeros) {
        my $q = "UPDATE nt_zone_record_log o
            JOIN (
                SELECT o.nt_zone_record_log_id AS id, MIN(t.nt_user_id) AS new_user
                FROM nt_zone_record_log o
                JOIN nt_zone_record_log t ON t.nt_zone_id = o.nt_zone_id
                    AND t.name = o.name
                    AND t.type_id = o.type_id
                    AND t.ttl = o.ttl
                    AND t.timestamp = o.timestamp
                    AND t.nt_zone_record_id <> o.nt_zone_record_id
                    AND t.action IN ('added','modified')
                    AND t.nt_user_id <> 0
                JOIN nt_user u ON u.nt_user_id = t.nt_user_id
                WHERE o.nt_user_id = 0 AND o.action = 'modified'
                GROUP BY o.nt_zone_record_log_id
                HAVING COUNT(DISTINCT t.nt_user_id) = 1
            ) m ON m.id = o.nt_zone_record_log_id
            SET o.nt_user_id = m.new_user
            WHERE o.nt_user_id = 0";
        $q =~ s/[\s]{2,}/ /g;
        print "repairing nt_zone_record_log: $zeros row(s) missing attribution "
            . "(nt_user_id=0), remapping TTL-sync cascade rows to the "
            . "triggering user where provable\n$q;\n";
        $dbh->query($q) or die DBIx::Simple->error;
    }

    my %seen;
    my @user_fk_tables = grep { !$seen{$_}++ }
        map { $_->[0] } grep { $_->[3] eq 'nt_user' } _fks_2_41();

    # restore tombstone users for rows referencing hard-deleted user ids
    my %orphan_ids;
    for my $table (@user_fk_tables) {
        $orphan_ids{$_} = 1 for _try_list(
            "SELECT DISTINCT l.nt_user_id FROM `$table` l
                LEFT JOIN nt_user u ON u.nt_user_id = l.nt_user_id
                WHERE u.nt_user_id IS NULL AND l.nt_user_id <> 0");
    }
    if (%orphan_ids) {
        my ($group_id) = _try_list("SELECT MIN(nt_group_id) FROM nt_group");
        for my $uid ( sort { $a <=> $b } keys %orphan_ids ) {
            print "repairing nt_user: restoring tombstone for hard-deleted user $uid "
                . "(still referenced by logs)\n";
            $dbh->query(
                "INSERT INTO nt_user
                    (nt_user_id, nt_group_id, first_name, last_name, username, password, email, deleted)
                 VALUES ($uid, $group_id, 'Deleted', 'User', 'deleted-user-$uid', '', '', 1)"
            ) or die DBIx::Simple->error;
        }
    }

    # any nt_user_id=0 rows the heuristic could not resolve get an honest
    # 'unattributed' system user, not a guess and not a DELETE
    my $sys_id;
    for my $table (@user_fk_tables) {
        my ($zeros) = _try_list("SELECT COUNT(*) FROM `$table` WHERE nt_user_id = 0");
        next if !$zeros;
        $sys_id ||= _ensure_unattributed_user();
        print "repairing $table: $zeros row(s) with no identifiable actor, "
            . "assigning to 'unattributed' (nt_user $sys_id)\n";
        $dbh->query("UPDATE `$table` SET nt_user_id = $sys_id WHERE nt_user_id = 0")
            or die DBIx::Simple->error;
    }
}

sub _ensure_unattributed_user {
    my ($id) = _try_list(
        "SELECT nt_user_id FROM nt_user WHERE username = 'unattributed' AND deleted = 1");
    return $id if $id;

    my ($group_id) = _try_list("SELECT MIN(nt_group_id) FROM nt_group");
    $dbh->query(
        "INSERT INTO nt_user (nt_group_id, first_name, last_name, username, password, email, deleted)
         VALUES ($group_id, 'Unattributed', 'Actions', 'unattributed', '', '', 1)"
    ) or die DBIx::Simple->error;
    return $dbh->last_insert_id( undef, undef, 'nt_user', undef );
}

sub _sql_2_41 {
    _repair_user_orphans_2_41();

    my @tables            = $dbh->query("SHOW TABLES")->flat;
    my $convert_to_innodb = engine_innodb(@tables);
    my $existing          = _existing_fks();

    my @pending;       # FKs still to add
    my @orphan_sql;    # DELETE statements for tables with orphans
    my @orphan_info;   # ($table, $count) for the abort report
    for my $fk ( _fks_2_41() ) {
        my ( $table, $name, $col, $ref_table, $ref_col ) = @$fk;
        next if $existing->{$table}{$name};         # skip already-applied FKs (resumable)
        push @pending, $fk;

        my $delete_sql =
              "DELETE l FROM `$table` l LEFT JOIN `$ref_table` p "
            . "ON l.`$col` = p.`$ref_col` WHERE p.`$ref_col` IS NULL;";
        my ($count) = $dbh->query(
            "SELECT COUNT(*) FROM `$table` l LEFT JOIN `$ref_table` p "
            . "ON l.`$col` = p.`$ref_col` WHERE p.`$ref_col` IS NULL"
        )->list;
        next if !$count;
        push @orphan_sql, $delete_sql;
        push @orphan_info, [ $table, $col, $ref_table, $count ];
    }

    if ( @orphan_info && !$prune ) {
        print STDERR "\n\nThe v2.41 FK constraints cannot be applied because orphan rows exist\n"
            . "(these reference hard-deleted parent rows; user-attribution orphans are\n"
            . "repaired automatically and never reach this point):\n\n";
        for my $row (@orphan_info) {
            printf STDERR "  %d orphan row(s): %s.%s -> %s\n", $row->[3], $row->[0], $row->[1], $row->[2];
        }
        print STDERR "\nRun the following SQL to remove the orphans, then re-run upgrade.pl:\n\n";
        print STDERR "$_\n" for @orphan_sql;
        print STDERR "\nAlternatively, re-run with --prune to delete these rows automatically.\n\n";
        die "Aborting upgrade.\n";
    }

    my $statements = '';
    for my $fk (@pending) {
        my ( $table, $name, $col, $ref_table, $ref_col ) = @$fk;
        if ($prune) {
            $statements .=
                  "DELETE l FROM `$table` l LEFT JOIN `$ref_table` p "
                . "ON l.`$col` = p.`$ref_col` WHERE p.`$ref_col` IS NULL;\n";
        }
        $statements .=
              "ALTER TABLE `$table` ADD CONSTRAINT `$name` "
            . "FOREIGN KEY (`$col`) REFERENCES `$ref_table` (`$ref_col`) "
            . "ON DELETE CASCADE ON UPDATE CASCADE;\n";
    }

    return <<EO_SQL_2_41
/* Ensure all tables use InnoDB (default since MySQL 5.5) */

$convert_to_innodb

$statements
UPDATE nt_options SET option_value='2.41' WHERE option_name='db_version';
EO_SQL_2_41
        ;
}

sub _sql_test_2_40 {
    my $r = _get_db_version();
    return 1 if !defined $r;    # query failed

    my $tbl = $dbh->query("SHOW TABLES LIKE 'nt_nameserver_export_type'")->hashes;
    return 1 unless scalar $tbl && $tbl->[0];    # table missing

    my $normalized =
        $dbh->query("SELECT id FROM nt_nameserver_export_type WHERE id=6 AND name='nsd'")->hashes;
    return 0 unless scalar $normalized && $normalized->[0];

    return 0 if $r < 2.40;                       # do it! bump db_version
    return 1;                                    # don't update
}

sub _sql_2_40 {
    <<EO_SQL_2_40;
UPDATE nt_nameserver_export_type SET name='nsd' WHERE id=6 AND LOWER(name)='nsd';
UPDATE nt_options SET option_value='2.40' WHERE option_name='db_version';
EO_SQL_2_40
}

sub _tables_2_35 {
    return qw/
        nt_group            nt_group_log             nt_group_subgroups
        nt_user             nt_user_global_log       nt_user_log
        nt_user_session     nt_user_session_log
        nt_nameserver       nt_nameserver_log        nt_nameserver_export_log
        nt_zone             nt_zone_log              nt_zone_nameserver
        nt_zone_record      nt_zone_record_log
        nt_perm             nt_options
        resource_record_type
        /;
}

sub _sql_test_2_35 {
    my $r = _get_db_version();
    return 1 if !defined $r;                     # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `nt_zone_log` LIKE 'location'")->hashes;
    return 0
        unless scalar $exists
        && $exists->[0]
        && $exists->[0]{field};                  # column missing

    # a partial 2.35 run (e.g. killed by the MyISAM key-length limit) leaves
    # some tables unconverted; the block is idempotent, so re-apply
    my $tables = join ',', map {"'$_'"} _tables_2_35();
    my ($unconverted) = _try_list(
        "SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME IN ($tables)
              AND TABLE_COLLATION NOT LIKE 'utf8mb4%'");
    return 0 if $unconverted;

    my ($addr_len) = _try_list(
        "SELECT CHARACTER_MAXIMUM_LENGTH FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'nt_zone_record' AND COLUMN_NAME = 'address'");
    return 0 if $addr_len && $addr_len < 5120;   # column not yet widened

    return 0 if $r < 2.35;                       # update!
    return 1;                                    # don't update
}

# columns widened to utf8mb4 by the v2.35 ALTERs below: table => { column => chars }
sub _new_widths_2_35 {
    return (
        nt_nameserver      => { name => 127, description => 255, address => 127, address6 => 127, remote_login => 127 },
        nt_zone            => { zone => 255, mailaddr => 127, description => 255, location => 8 },
        nt_zone_log        => { zone => 255, mailaddr => 127, description => 255, location => 8 },
        nt_zone_record     => { name => 255, description => 255, address => 5120, other => 512, location => 2 },
        nt_zone_record_log => { name => 255, description => 255, address => 5120, other => 512, location => 2 },
        nt_user            => { first_name => 120, last_name => 160, username => 200, password => 1020, email => 400 },
        nt_user_log        => { first_name => 120, last_name => 160, username => 200, password => 1020, email => 400 },
        nt_group           => { name => 255 },
    );
}

# Indexes created by older releases span whole columns: 2.34's own 02_nt_user.sql
# shipped KEY nt_user_idx1 (username,password). Once v2.35 widens those columns to
# utf8mb4, such an index exceeds InnoDB's 3072-byte key limit and the ALTER dies.
# Detect any index that would exceed the limit and rebuild it with the 191-char
# prefixes the current create scripts use.
sub _index_heal_2_35 {
    my %widths = _new_widths_2_35();
    my $limit  = 3072;    # InnoDB max key bytes; utf8mb4 is 4 bytes/char
    my $prefix = 191;     # canonical prefix length, matches sql/*.sql

    my ( $drop, $add ) = ( '', '' );
    my $has_user_idx1 = 0;

    for my $table ( sort keys %widths ) {
        my $rows;
        eval {
            $rows = $dbh->query(
                "SELECT INDEX_NAME AS i, SEQ_IN_INDEX AS s, COLUMN_NAME AS c,
                        SUB_PART AS p, NON_UNIQUE AS n
                    FROM information_schema.STATISTICS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '$table'
                    ORDER BY INDEX_NAME, SEQ_IN_INDEX"
            )->hashes;
        };
        next if !$rows;

        my %idx;
        for my $row (@$rows) {
            next if $row->{i} eq 'PRIMARY';
            push @{ $idx{ $row->{i} } }, $row;
        }
        $has_user_idx1 = 1 if $table eq 'nt_user' && $idx{nt_user_idx1};

        for my $name ( sort keys %idx ) {
            my $projected = 0;
            for my $part ( @{ $idx{$name} } ) {
                my $chars = $widths{$table}{ $part->{c} };
                $chars = $part->{p} if defined $part->{p} && ( !defined $chars || $part->{p} < $chars );
                $chars = 32 if !defined $chars;    # column not widened here (int, enum, ...)
                $projected += $chars * 4;
            }
            next if $projected <= $limit;

            if ( !$idx{$name}[0]{n} ) {            # NON_UNIQUE=0
                die "Index $table.$name would exceed InnoDB's $limit-byte limit after the\n"
                    . "utf8mb4 conversion, and it is UNIQUE, so it cannot be safely rebuilt\n"
                    . "with column prefixes. Please resolve it manually, then re-run.\n";
            }

            my @parts;
            for my $part ( @{ $idx{$name} } ) {
                my $chars = $widths{$table}{ $part->{c} };
                $chars = $part->{p} if defined $part->{p} && ( !defined $chars || $part->{p} < $chars );
                if ( defined $chars && $chars > $prefix ) {
                    push @parts, "`$part->{c}`($prefix)";
                }
                else {
                    push @parts, defined $part->{p} ? "`$part->{c}`($part->{p})" : "`$part->{c}`";
                }
            }
            $drop .= "ALTER TABLE `$table` DROP INDEX `$name`;\n";
            $add  .= "ALTER TABLE `$table` ADD KEY `$name` (" . join( ',', @parts ) . ");\n";
        }
    }

    # a prior partial run (or manual remediation) may have dropped nt_user_idx1
    # without re-creating it; restore the canonical form from 02_nt_user.sql
    if ( !$has_user_idx1 ) {
        $add .= "ALTER TABLE `nt_user` ADD KEY `nt_user_idx1` (`username`($prefix),`password`($prefix));\n";
    }

    return ( $drop, $add );
}

# The utf8mb4 conversion re-encodes column contents based on their declared
# charset. If a latin1/utf8 database holds bytes that don't match its declared
# charset (classic mojibake), conversion can corrupt them. Warn the operator.
sub _utf8_preflight_2_35 {
    my %widths = _new_widths_2_35();

    my @nonascii;
    for my $table ( sort keys %widths ) {
        for my $col ( sort keys %{ $widths{$table} } ) {
            my $count;
            eval {
                ($count) = $dbh->query(
                    "SELECT COUNT(*) FROM `$table` WHERE `$col` <> CONVERT(`$col` USING ASCII)"
                )->list;
            };
            push @nonascii, "  $table.$col: $count row(s)" if $count;
        }
    }
    return if !@nonascii;

    my $report = join "\n", @nonascii;
    print STDERR <<EO_UTF8_WARN;

WARNING: non-ASCII data detected in text columns:

$report

The v2.35 update converts these columns to utf8mb4. If this database has ever
stored misencoded bytes (e.g. UTF-8 written through a latin1 connection), the
conversion can garble them. If unsure, verify those rows on a copy of the
database first. You have a backup, right?

Continuing in 10 seconds (Ctrl-C to abort)...
EO_UTF8_WARN
    sleep 10;
}

sub _sql_2_35 {

    my @tables = _tables_2_35();

    # Convert to InnoDB BEFORE widening columns to utf8mb4: MyISAM (the historical
    # default engine) limits index keys to 1000 bytes, InnoDB allows 3072. On a
    # MyISAM table the ALTERs below die with "Specified key was too long".
    my $convert_to_innodb = engine_innodb(@tables);

    my ( $drop_oversized, $add_prefixed ) = _index_heal_2_35();

    _utf8_preflight_2_35();

    my $encode_utf8mb4 = encode_utf8mb4(@tables);

    # a previous partial run may have already added nt_zone_log.location
    my $zone_log_location = _column_exists( 'nt_zone_log', 'location' ) ? 'MODIFY' : 'ADD';

    <<EO_SQL_2_35
/* Mark SPF as obsolete and disable */
UPDATE resource_record_type SET forward=0, obsolete=1 WHERE id=99;

/* InnoDB before utf8mb4: MyISAM's 1000-byte index key limit cannot hold the new schema */
$convert_to_innodb

/* Indexes that would exceed the key-length limit post-conversion (re-created below, prefixed) */
$drop_oversized

/*  Update CHARACTER & COLLATION for VARCHAR columns */

ALTER TABLE nt_nameserver DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin,
    MODIFY name         varchar(127) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    MODIFY description  varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY address      varchar(127) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    MODIFY address6     varchar(127) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY remote_login varchar(127) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL;

ALTER TABLE nt_zone DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin,
    MODIFY zone        varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    MODIFY mailaddr    varchar(127) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY description varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY location    varchar(8)   CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY last_publish DATETIME DEFAULT NULL;

ALTER TABLE nt_zone_log DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin,
    MODIFY zone        varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    MODIFY mailaddr    varchar(127) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY description varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    $zone_log_location location    varchar(8)   CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL;

ALTER TABLE nt_zone_record DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin,
  MODIFY name        varchar(255)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  MODIFY description varchar(255)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  MODIFY address     varchar(5120) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  MODIFY other       varchar(512)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  MODIFY location    varchar(2)    CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL;

ALTER TABLE nt_zone_record_log DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin,
  MODIFY name        varchar(255)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  MODIFY description varchar(255)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  MODIFY address     varchar(5120) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  MODIFY other       varchar(512)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  MODIFY location    varchar(2)    CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL;

ALTER TABLE nt_user DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin,
    MODIFY first_name varchar(120)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY last_name  varchar(160)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY username   varchar(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    MODIFY password   varchar(1020) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY email      varchar(400)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '';

ALTER TABLE nt_user_log DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin,
    MODIFY first_name varchar(120)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY last_name  varchar(160)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY username   varchar(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    MODIFY password   varchar(1020) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    MODIFY email      varchar(400)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '';

ALTER TABLE nt_group DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin,
    MODIFY name varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '';

/* re-create the oversized indexes, now with 191-char prefixes (as in sql/*.sql) */
$add_prefixed

$encode_utf8mb4


UPDATE nt_options SET option_value='2.35' WHERE option_name='db_version';
EO_SQL_2_35
        ;
}

sub _sql_test_2_34 {
    my $r = _get_db_version();
    return 1 if !defined $r;     # query failed
    return 0 if $r < 2.34;       # update!
    return 1;                    # don't update
}

sub _sql_2_34 {
    <<EO_SQL_2_34
INSERT IGNORE INTO `resource_record_type` (`id`, `name`, `description`, `reverse`, `forward`, `obsolete`)
VALUES
    (13,'HINFO','Host Info',0,0,1),
    (256,'URI','URI',0,1,0),
    (257,'CAA','Certification Authority Authorization',0,1,0);

UPDATE nt_options SET option_value='2.34' WHERE option_name='db_version';
EO_SQL_2_34
        ;
}

sub _sql_test_2_32 {
    my $r = _get_db_version();
    return 1 if !defined $r;     # query failed
    return 0 if $r < 2.32;       # update!
    return 1;                    # don't update
}

sub _sql_2_32 {
    <<EO_SQL_2_32
DROP TABLE IF EXISTS nt_nameserver_qlog;
DROP TABLE IF EXISTS nt_nameserver_qlogfile;

UPDATE nt_options SET option_value='2.32' WHERE option_name='db_version';
EO_SQL_2_32
        ;
}

sub _sql_test_2_30 {
    my $r = _get_db_version();
    return 1 if !defined $r;     # query failed
    return 0 if $r < 2.30;       # update!
    return 1;                    # don't update
}

sub _sql_2_30 {
    <<EO_SQL_2_30;
ALTER table nt_user MODIFY password VARCHAR(255);
ALTER table nt_user_log MODIFY password VARCHAR(255);

UPDATE nt_options SET option_value='2.30' WHERE option_name='db_version';
EO_SQL_2_30
}

sub _sql_test_2_29 {
    my $r = _get_db_version();
    return 1 if !defined $r;    # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `nt_zone_record_log` LIKE 'location'")->hashes;
    return 0
        unless scalar $exists
        && $exists->[0]
        && $exists->[0]{field};    # column missing
    return 0 if $r < 2.29;         # do it!
    return 1;                      # don't update
}

sub _sql_2_29 {
    my $sql = '';
    $sql .= "ALTER TABLE nt_zone_record_log ADD COLUMN location VARCHAR(2) DEFAULT NULL AFTER other;\n"
        if !_column_exists( 'nt_zone_record_log', 'location' );

    return $sql . <<EO_SQL_2_29;
UPDATE nt_options SET option_value='2.29' WHERE option_name='db_version';
EO_SQL_2_29
}

sub _sql_test_2_28 {
    my $r = _get_db_version();
    return 1 if !defined $r;    # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `nt_zone` LIKE 'last_publish'")->hashes;
    return 0
        unless scalar $exists
        && $exists->[0]
        && $exists->[0]{field};    # column missing
    return 0 if $r < 2.28;         # do it!
    return 1;                      # don't update
}

sub _sql_2_28 {
    my $sql = '';
    $sql .= "ALTER TABLE nt_zone ADD COLUMN last_publish DATETIME DEFAULT NULL AFTER last_modified;\n"
        if !_column_exists( 'nt_zone', 'last_publish' );

    return $sql . <<EO_SQL_2_28;
UPDATE nt_options SET option_value='2.28' WHERE option_name='db_version';
EO_SQL_2_28
}

sub _sql_test_2_27 {
    my $r = _get_db_version();
    return 1 if !defined $r;    # query failed

    my $exists =
        $dbh->query("SELECT option_value FROM nt_options WHERE option_name='session_timeout'")
        ->hashes;
    return 0
        unless scalar $exists
        && $exists->[0]
        && $exists->[0]{option_value};    # option missing
    return 0 if $r < 2.27;                # do it!
    return 1;                             # don't update
}

sub _sql_2_27 {
    my $sql = '';
    $sql .= "ALTER TABLE nt_user ADD COLUMN pass_salt VARCHAR(16) AFTER password;\n"
        if !_column_exists( 'nt_user', 'pass_salt' );
    $sql .= "ALTER TABLE nt_user_log ADD COLUMN pass_salt VARCHAR(16) AFTER password;\n"
        if !_column_exists( 'nt_user_log', 'pass_salt' );

    return $sql . <<EO_SQL_2_27;
INSERT IGNORE INTO nt_options
VALUES (2,'session_timeout','45'),
       (3,'default_group','NicTool');

UPDATE nt_options SET option_value='2.27' WHERE option_name='db_version';
EO_SQL_2_27
}

sub _sql_test_2_24 {
    my $r = _get_db_version();
    return 1 if !defined $r;    # query failed

    # handle schema drift by checking for missing schema objects
    my $col = $dbh->query("SHOW COLUMNS FROM `nt_nameserver` LIKE 'export_type_id'")->hashes;
    return 0
        unless scalar $col && $col->[0] && $col->[0]{field};    # column missing

    my $tbl = $dbh->query("SHOW TABLES LIKE 'nt_nameserver_export_type'")->hashes;
    return 0 unless scalar $tbl && $tbl->[0];                   # table missing

    return 0 if $r < 2.24;                                      # do it!
    return 1;                                                   # don't update
}

sub _sql_2_24 {
    my $sql = '';
    $sql .= "ALTER TABLE `nt_nameserver` ADD column address6 VARCHAR(127)  NULL DEFAULT NULL AFTER address;\n"
        if !_column_exists( 'nt_nameserver', 'address6' );
    $sql .= "ALTER TABLE `nt_nameserver` ADD column remote_login VARCHAR(127) DEFAULT NULL AFTER address6;\n"
        if !_column_exists( 'nt_nameserver', 'remote_login' );
    $sql .= "ALTER TABLE `nt_nameserver` ADD column export_type_id INT UNSIGNED DEFAULT '1' AFTER remote_login;\n"
        if !_column_exists( 'nt_nameserver', 'export_type_id' );
    $sql .= "ALTER TABLE `nt_nameserver_log` ADD column `address6` VARCHAR(127) NULL DEFAULT NULL AFTER address;\n"
        if !_column_exists( 'nt_nameserver_log', 'address6' );
    $sql .= "ALTER TABLE `nt_nameserver_log` ADD column export_type_id INT UNSIGNED NULL AFTER address6;\n"
        if !_column_exists( 'nt_nameserver_log', 'export_type_id' );

    # migrate & drop export_format, unless a previous run already did
    my $export_format_sql = '';
    if ( _column_exists( 'nt_nameserver', 'export_format' ) ) {
        $export_format_sql = <<EO_EXPORT_FORMAT;
UPDATE nt_nameserver SET export_type_id=1 WHERE export_format IN ('tinydns','djb','djbdns');
UPDATE nt_nameserver SET export_type_id=2 WHERE export_format='bind';
UPDATE nt_nameserver SET export_type_id=3 WHERE export_format='maradns';
UPDATE nt_nameserver SET export_type_id=4 WHERE export_format='powerdns';
ALTER TABLE nt_nameserver DROP column export_format;
EO_EXPORT_FORMAT
    }

    return $sql . <<EO_SQL_2_24;
DROP TABLE IF EXISTS nt_nameserver_export_types;
DROP TABLE IF EXISTS nt_nameserver_export_type;
CREATE TABLE `nt_nameserver_export_type` (
    `id`     int UNSIGNED NOT NULL AUTO_INCREMENT,
    `name`   varchar(16) NOT NULL DEFAULT '',
    `descr`  varchar(56) NOT NULL DEFAULT '',
    `url`    varchar(128) DEFAULT NULL,
    PRIMARY KEY (`id`)
) DEFAULT CHARSET=utf8;

INSERT INTO `nt_nameserver_export_type` (`id`, `name`, `descr`, `url`)
VALUES (1,'djbdns',    'djbdns (tinydns & axfrdns)',  'cr.yp.to/djbdns.html'),
       (2,'bind',      'BIND (zone files)',  'www.isc.org/downloads/bind/'),
       (3,'maradns',   'MaraDNS',            'maradns.samiam.org'),
       (4,'powerdns',  'PowerDNS',           'www.powerdns.com'),
       (5,'bind-nsupdate','BIND (nsupdate protocol)','www.isc.org/downloads/bind/'),
       (6,'NSD',       'NSD (Name Server Daemon)', 'www.nlnetlabs.nl/projects/nsd/'),
       (7,'dynect',    'DynECT Standard DNS','dyn.com/managed-dns/'),
       (8,'knot',      'Knot DNS',           'www.knot-dns.cz');

$export_format_sql
UPDATE nt_options SET option_value='2.24' WHERE option_name='db_version';
EO_SQL_2_24
}

sub _sql_test_2_18 {
    my $r = _get_db_version();
    return 1 if !defined $r;    # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `resource_record_type` LIKE 'obsolete'")->hashes;
    return 0
        unless scalar $exists
        && $exists->[0]
        && $exists->[0]{field};    # column missing

    return 0 if $r < 2.18;         # do it!
    return 1;                      # don't update
}

sub _sql_2_18 {
    my $sql = '';
    $sql .= "ALTER TABLE resource_record_type ADD column obsolete TINYINT(1) NOT NULL DEFAULT '0' AFTER forward;\n"
        if !_column_exists( 'resource_record_type', 'obsolete' );

    return $sql . <<EO_SQL_2_18;
REPLACE INTO `resource_record_type`
 (`id`, `name`, `description`, `reverse`, `forward`, `obsolete`)
VALUES
 (35,'NAPTR','Naming Authority Pointer',1,1,0),
 (39,'DNAME','Delegation Name',0,0,0),
 (43,'DS','Delegation Signer',0,1,0),
 (44,'SSHFP','Secure Shell Key Fingerprints',0,1,0),
 (46,'RRSIG','Resource Record Signature',0,1,0),
 (47,'NSEC','Next Secure',0,1,0),
 (48,'DNSKEY','DNS Public Key',0,1,0),
 (50,'NSEC3','Next Secure v3',0,0,0),
 (51,'NSEC3PARAM','NSEC3 Parameters',0,0,0) ;

UPDATE nt_zone SET mailaddr=CONCAT('hostmaster.',zone,'.') WHERE mailaddr IS NULL;
UPDATE nt_zone SET mailaddr=CONCAT('hostmaster.',zone,'.') WHERE mailaddr LIKE 'hostmaster.ZONE.TLD%';
UPDATE nt_zone SET mailaddr=SUBSTRING(mailaddr, 1, LENGTH(mailaddr)-1) WHERE mailaddr LIKE '%.';
UPDATE nt_options SET option_value='2.18' WHERE option_name='db_version';
EO_SQL_2_18
}

sub _sql_test_2_17 {
    my $r = _get_db_version();
    return 1 if !defined $r;    # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `nt_user` LIKE 'is_admin'")->hashes;
    return 0
        unless scalar $exists
        && $exists->[0]
        && $exists->[0]{field};    # column missing
    return 0 if $r < 2.17;         # do it!
    return 1;                      # don't update
}

sub _sql_2_17 {
    my $sql = '';
    $sql .= "ALTER TABLE nt_user ADD COLUMN is_admin TINYINT(1) UNSIGNED default '0' AFTER email;\n"
        if !_column_exists( 'nt_user', 'is_admin' );
    return $sql;
}

sub _sql_test_2_16 {
    my $r = _get_db_version();
    return 1 if !defined $r;       # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `nt_perm` LIKE 'usable_ns'")->hashes;
    return 0
        unless scalar $exists
        && $exists->[0]
        && $exists->[0]{field};    # column missing
    return 0 if $r eq '2.15';      # do it!
    return 1;                      # don't update
}

sub _sql_2_16 {
    my $sql = '';
    $sql .= "ALTER TABLE nt_perm ADD column usable_ns VARCHAR(50) AFTER self_write;\n"
        if !_column_exists( 'nt_perm', 'usable_ns' );

    if ( _column_exists( 'nt_perm', 'usable_ns0' ) ) {
        $sql .= "UPDATE nt_perm SET usable_ns=(CONCAT_WS(',', usable_ns0,usable_ns1,usable_ns2,usable_ns3,usable_ns4,usable_ns5,usable_ns6,usable_ns7,usable_ns8,usable_ns9));\n";
    }
    for my $n ( 0 .. 9 ) {
        $sql .= "ALTER TABLE nt_perm DROP column usable_ns$n;\n"
            if _column_exists( 'nt_perm', "usable_ns$n" );
    }

    return $sql . <<EO_SQL_2_16;
ALTER TABLE nt_zone_record MODIFY address VARCHAR(512) NOT NULL;
ALTER TABLE nt_zone_record_log MODIFY address VARCHAR(512) NOT NULL;
UPDATE nt_options SET option_value='2.16' WHERE option_name='db_version';
EO_SQL_2_16
}

sub _sql_test_2_15 {
    my $r = _get_db_version();
    return 1 if !defined $r;     # query failed
    return 0 if $r < 2.15;       # do it!
    return 1;                    # don't update
}

sub _sql_2_15 {
    <<EO_SQL_2_15
/* submitted by Arthur Gouros, remove legacy \072 chars */
UPDATE nt_zone_record SET address = REPLACE(address,'\\072',':');
UPDATE nt_options SET option_value='2.15' WHERE option_name='db_version';
EO_SQL_2_15
        ;
}

sub _sql_test_2_14 {
    my $r = _get_db_version();
    return 1 if !defined $r;     # query failed
    return 0 if $r < 2.14;       # do it! (no DB changes since v2.11)
    return 1;                    # don't update
}

sub _sql_2_14 {
    <<EO_SQL_2_14
ALTER TABLE nt_nameserver MODIFY export_format VARCHAR(12) NOT NULL;
ALTER TABLE nt_nameserver_log MODIFY export_format VARCHAR(12) NULL DEFAULT NULL;

DROP TABLE IF EXISTS nt_nameserver_export_types;
CREATE TABLE nt_nameserver_export_types (
   id tinyint(3) unsigned NOT NULL AUTO_INCREMENT,
   type varchar(12) NOT NULL DEFAULT '',
   PRIMARY KEY (`id`)
) DEFAULT CHARSET=utf8;

INSERT INTO `nt_nameserver_export_types` (`id`, `type`)
VALUES
    (1,'tinydns'),
    (2,'bind'),
    (3,'maradns'),
    (4,'powerdns');

UPDATE nt_options SET option_value='2.14' WHERE option_name='db_version';
EO_SQL_2_14
        ;
}

sub _sql_test_2_11 {
    my $r = _get_db_version();
    return 1 if !defined $r;     # query failed
    return 0 if $r < 2.11;       # do it!
    return 1;                    # don't update
}

sub _sql_2_11 {

    my @tables = qw/ nt_delegate  nt_delegate_log    nt_perm                  nt_options
        nt_group            nt_group_log             nt_group_subgroups
        nt_nameserver       nt_nameserver_log        nt_nameserver_export_log nt_nameserver_qlog nt_nameserver_qlogfile
        nt_user             nt_user_global_log       nt_user_log
        nt_user_session     nt_user_session_log
        nt_zone             nt_zone_log              nt_zone_nameserver
        nt_zone_record      nt_zone_record_log       resource_record_type     /;

    my $encode_utf8 = encode_utf8(@tables);

    return <<EO_211
/* convert nt_zone_record.type to type_id (related to resource_record_type) */
ALTER TABLE nt_zone_record ADD `type_id` smallint(2) UNSIGNED NOT NULL AFTER `type`;
UPDATE nt_zone_record SET type_id=1 WHERE type='A';
UPDATE nt_zone_record SET type_id=2 WHERE type='NS';
UPDATE nt_zone_record SET type_id=5 WHERE type='CNAME';
UPDATE nt_zone_record SET type_id=12 WHERE type='PTR';
UPDATE nt_zone_record SET type_id=15 WHERE type='MX';
UPDATE nt_zone_record SET type_id=16 WHERE type='TXT';
UPDATE nt_zone_record SET type_id=28 WHERE type='AAAA';
UPDATE nt_zone_record SET type_id=33 WHERE type='SRV';
UPDATE nt_zone_record SET type_id=99 WHERE type='SPF';
ALTER TABLE nt_zone_record DROP `type`;

ALTER TABLE nt_zone_record_log ADD `type_id` smallint(2) UNSIGNED NOT NULL AFTER `type`;
UPDATE nt_zone_record_log SET type_id=1 WHERE type='A';
UPDATE nt_zone_record_log SET type_id=2 WHERE type='NS';
UPDATE nt_zone_record_log SET type_id=5 WHERE type='CNAME';
UPDATE nt_zone_record_log SET type_id=12 WHERE type='PTR';
UPDATE nt_zone_record_log SET type_id=15 WHERE type='MX';
UPDATE nt_zone_record_log SET type_id=16 WHERE type='TXT';
UPDATE nt_zone_record_log SET type_id=28 WHERE type='AAAA';
UPDATE nt_zone_record_log SET type_id=33 WHERE type='SRV';
UPDATE nt_zone_record_log SET type_id=99 WHERE type='SPF';
ALTER TABLE nt_zone_record_log DROP `type`;

DELETE FROM nt_zone_nameserver WHERE nt_nameserver_id=0;
ALTER TABLE nt_zone_nameserver MODIFY nt_zone_id int(10) unsigned NOT NULL;
ALTER TABLE nt_zone_nameserver ADD UNIQUE KEY `zone_ns` (`nt_zone_id`,`nt_nameserver_id`);

$encode_utf8

UPDATE nt_nameserver_export_log SET success=0 WHERE success IS NULL;
UPDATE nt_nameserver_export_log SET result_id=0 WHERE result_id IS NULL;
ALTER TABLE nt_nameserver_export_log MODIFY `success` tinyint(1) UNSIGNED NOT NULL DEFAULT '0';
ALTER TABLE nt_nameserver_export_log CHANGE `result_id` `copied` tinyint(1) UNSIGNED NOT NULL DEFAULT '0';

DROP TABLE IF EXISTS resource_record_type;
CREATE TABLE resource_record_type (
   id              smallint(2) unsigned NOT NULL,
   name            varchar(10) NOT NULL,
   description     varchar(55) NULL DEFAULT NULL,
   reverse         tinyint(1) UNSIGNED NOT NULL DEFAULT 1,
   forward         tinyint(1) UNSIGNED NOT NULL DEFAULT 1,
PRIMARY KEY (`id`),
UNIQUE `name` (`name`)
) DEFAULT CHARSET=utf8;

INSERT INTO `resource_record_type` VALUES (2,'NS','Name Server',1,1),(5,'CNAME','Canonical Name',1,1),(6,'SOA',NULL,0,0),(12,'PTR','Pointer',1,0),(15,'MX','Mail Exchanger',0,1),(28,'AAAA','Address IPv6',0,1),(33,'SRV','Service',0,1),(99,'SPF','Sender Policy Framework',0,1),(252,'AXFR',NULL,0,1),(1,'A','Address',0,1),(16,'TXT','Text',1,1),(48,'DNSKEY',NULL,0,1),(43,'DS',NULL,0,1),(25,'KEY',NULL,0,1),(29,'LOC','Location',0,0);

UPDATE nt_options SET option_value='2.11' WHERE option_name='db_version';
EO_211
        ;
}

sub _sql_test_2_10 {
    my $r = _get_db_version();
    return 1 if !defined $r;     # query failed, 2.09 not applied yet
    return 0 if $r < 2.10;       # do it!
    return 1;                    # DB version is probably > 2.09 already
}

sub _sql_2_10 {

    my @tables = qw/ nt_delegate nt_delegate_log nt_options nt_perm
        nt_group nt_group_log nt_group_subgroups nt_nameserver nt_nameserver_log
        nt_nameserver_export_log nt_nameserver_qlog nt_nameserver_qlogfile
        nt_user nt_user_log nt_user_global_log nt_user_session nt_user_session_log
        nt_zone nt_zone_log nt_zone_record nt_zone_record_log /;

    my $encode_utf8 = encode_utf8(@tables);

    <<EO_SQL_2_10
/* Alter the nt_zone_record table first, which will fail early if the
** 2.05 update hasn't already been applied. */

/* nt_zone_record */
ALTER TABLE nt_zone_record ADD `location` VARCHAR(2) DEFAULT NULL  AFTER `other`;
ALTER TABLE nt_zone_record ADD `timestamp` timestamp NULL DEFAULT NULL AFTER `location`;
ALTER TABLE nt_zone_record MODIFY type enum('A','AAAA','MX','PTR','NS','TXT','CNAME','SRV','SPF') NOT NULL;
ALTER TABLE nt_zone_record_log MODIFY type enum('A','AAAA','MX','PTR','NS','TXT','CNAME','SRV','SPF');


/* this will throw an error upon subsequent attempts. To avoid destroying
** data (like dropping that table after the ns0..9 fields are dropped) if
** this sql portion is run twice, we start with the create. */
CREATE TABLE nt_zone_nameserver (
    nt_zone_id           int(10) unsigned NOT NULL,
    nt_nameserver_id     smallint(5) unsigned NOT NULL,
  UNIQUE KEY `zone_ns_id` (`nt_zone_id`,`nt_nameserver_id`)
) DEFAULT CHARSET=utf8;

/* New database table, replacing nt_zone_record.type ENUM */
DROP TABLE IF EXISTS resource_record_type;
CREATE TABLE resource_record_type (
    id              smallint(2) unsigned NOT NULL AUTO_INCREMENT,
    name            varchar(10) NOT NULL,
PRIMARY KEY (`id`)
) DEFAULT CHARSET=utf8;

INSERT INTO resource_record_type VALUES (2,'NS'),(5,'CNAME'),(6,'SOA'),(12,'PTR'),(15,'MX'),(28,'AAAA'),(33,'SRV'),(99,'SPF'),(252,'AXFR'),(1,'A'),(16,'TXT'),(48,'DNSKEY'),(43,'DS'),(25,'KEY');


/* change all table.deleted columns from enum to tinyint(1) */
ALTER TABLE `nt_zone_record` MODIFY deleted tinyint(1) UNSIGNED NOT NULL DEFAULT 0;
/* and then decrement the values because enums are evil */
UPDATE nt_zone_record SET deleted=deleted-1;
ALTER TABLE `nt_zone` MODIFY deleted tinyint(1) UNSIGNED NOT NULL DEFAULT 0;
UPDATE nt_zone SET deleted=deleted-1;
ALTER TABLE `nt_user` MODIFY deleted tinyint(1) UNSIGNED NOT NULL DEFAULT 0;
UPDATE nt_user SET deleted=deleted-1;
ALTER TABLE `nt_perm` MODIFY deleted tinyint(1) UNSIGNED NOT NULL DEFAULT 0;
UPDATE nt_perm SET deleted=deleted-1;
ALTER TABLE `nt_nameserver` MODIFY deleted tinyint(1) UNSIGNED NOT NULL DEFAULT 0;
UPDATE nt_nameserver SET deleted=deleted-1;
ALTER TABLE `nt_group` MODIFY deleted tinyint(1) UNSIGNED NOT NULL DEFAULT 0;
UPDATE nt_group SET deleted=deleted-1;
ALTER TABLE `nt_delegate` MODIFY deleted tinyint(1) UNSIGNED NOT NULL DEFAULT 0;
UPDATE nt_delegate SET deleted=deleted-1;


/* nt_zone */
ALTER TABLE nt_zone ADD column `location` VARCHAR(2) DEFAULT NULL  AFTER `ttl`;
ALTER TABLE nt_zone ADD column `last_modified` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP AFTER `location`;

/* import NS settings from existing nt_zone.ns0..ns9 */
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns0 FROM nt_zone WHERE ns0 IS NOT NULL AND ns0 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns1 FROM nt_zone WHERE ns1 IS NOT NULL AND ns1 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns2 FROM nt_zone WHERE ns2 IS NOT NULL AND ns2 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns3 FROM nt_zone WHERE ns3 IS NOT NULL AND ns3 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns4 FROM nt_zone WHERE ns4 IS NOT NULL AND ns4 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns5 FROM nt_zone WHERE ns5 IS NOT NULL AND ns5 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns6 FROM nt_zone WHERE ns6 IS NOT NULL AND ns6 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns7 FROM nt_zone WHERE ns7 IS NOT NULL AND ns7 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns8 FROM nt_zone WHERE ns8 IS NOT NULL AND ns8 != 0;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns9 FROM nt_zone WHERE ns9 IS NOT NULL AND ns9 != 0;
/* and then kiss them columns goodbye. And don't let the door hit your ... */
ALTER TABLE nt_zone DROP column ns0;
ALTER TABLE nt_zone DROP column ns1;
ALTER TABLE nt_zone DROP column ns2;
ALTER TABLE nt_zone DROP column ns3;
ALTER TABLE nt_zone DROP column ns4;
ALTER TABLE nt_zone DROP column ns5;
ALTER TABLE nt_zone DROP column ns6;
ALTER TABLE nt_zone DROP column ns7;
ALTER TABLE nt_zone DROP column ns8;
ALTER TABLE nt_zone DROP column ns9;

/* nt_nameserver */
ALTER TABLE nt_nameserver DROP column `service_type`;
ALTER TABLE nt_nameserver ADD `export_serials` tinyint(1) UNSIGNED NOT NULL DEFAULT '1'  AFTER `export_interval`;
ALTER TABLE nt_nameserver ADD `export_status` varchar(255) NULL DEFAULT NULL  AFTER `export_serials`;
ALTER TABLE nt_nameserver MODIFY output_format enum('tinydns','djb','nt','bind') NOT NULL;
UPDATE nt_nameserver SET output_format='tinydns' WHERE output_format='nt';
UPDATE nt_nameserver SET output_format='tinydns' WHERE output_format='djb';
ALTER TABLE nt_nameserver CHANGE `output_format` `export_format` enum('tinydns','bind') NOT NULL;

/* nt_nameserver_log */
DELETE FROM nt_nameserver_log WHERE output_format NOT IN ('tinydns','djb','nt','bind') OR output_format IS NULL;
ALTER TABLE nt_nameserver_log DROP column `service_type`;
ALTER TABLE nt_nameserver_log ADD `export_serials` tinyint(1) UNSIGNED NOT NULL DEFAULT '1'  AFTER `export_interval`;
ALTER TABLE nt_nameserver_log MODIFY output_format enum('djb','tinydns','bind','nt') NOT NULL;
UPDATE nt_nameserver_log SET output_format='tinydns' WHERE output_format='nt';
UPDATE nt_nameserver_log SET output_format='tinydns' WHERE output_format='djb';
ALTER TABLE nt_nameserver_log CHANGE `output_format` `export_format` enum('tinydns','bind') NOT NULL;

/* nt_nameserver_export_log */
ALTER TABLE nt_nameserver_export_log ADD `result_id` int NULL DEFAULT NULL  AFTER `date_finish`;
ALTER TABLE nt_nameserver_export_log ADD `message` varchar(256) NULL DEFAULT NULL  AFTER `result_id`;
ALTER TABLE nt_nameserver_export_log ADD `success` tinyint(1) UNSIGNED NULL DEFAULT NULL  AFTER `message`;
ALTER TABLE nt_nameserver_export_log ADD `partial` tinyint(1) UNSIGNED NOT NULL DEFAULT 0  AFTER `success`;
ALTER TABLE nt_nameserver_export_log ADD `date_start_new` timestamp NULL DEFAULT NULL AFTER date_start;
UPDATE nt_nameserver_export_log SET date_start_new = FROM_UNIXTIME(date_start);
ALTER TABLE nt_nameserver_export_log DROP COLUMN date_start;
ALTER TABLE nt_nameserver_export_log CHANGE date_start_new date_start timestamp NULL DEFAULT NULL;
ALTER TABLE nt_nameserver_export_log ADD `date_end` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP AFTER date_finish;
UPDATE nt_nameserver_export_log SET date_end = FROM_UNIXTIME(date_finish);
ALTER TABLE nt_nameserver_export_log DROP COLUMN date_finish;

DROP TABLE IF EXISTS nt_nameserver_export_procstatus;

/* Convert all character encodings to UTF8 bin. */
$encode_utf8

UPDATE nt_options SET option_value='2.10' WHERE option_name='db_version';

EO_SQL_2_10
        ;
}

sub _sql_test_2_09 {

    # the nt_options table (with the db_version row) was added in 2.09
    return defined _get_db_version() ? 1 : 0;
}

sub _sql_2_09 {
    <<EO_SQL_2_09
DROP TABLE IF EXISTS nt_options;
CREATE TABLE nt_options (
  option_id int(11) unsigned NOT NULL auto_increment,
  option_name varchar(64) NOT NULL default '',
  option_value text NOT NULL,
  PRIMARY KEY  (`option_id`),
  UNIQUE KEY `option_name` (`option_name`)
);

INSERT INTO `nt_options` VALUES (1,'db_version','2.09');

DROP TABLE IF EXISTS nt_group_summary;
DROP TABLE IF EXISTS nt_group_current_summary;
DROP TABLE IF EXISTS nt_nameserver_general_summary;
DROP TABLE IF EXISTS nt_nameserver_summary;
DROP TABLE IF EXISTS nt_nameserver_current_summary;
DROP TABLE IF EXISTS nt_user_general_summary;
DROP TABLE IF EXISTS nt_user_summary;
DROP TABLE IF EXISTS nt_user_current_summary;
DROP TABLE IF EXISTS nt_zone_general_summary;
DROP TABLE IF EXISTS nt_zone_summary;
DROP TABLE IF EXISTS nt_zone_current_summary;
DROP TABLE IF EXISTS nt_zone_record_summary;
DROP TABLE IF EXISTS nt_zone_record_current_summary;
DROP TABLE IF EXISTS nt_zone_ns_log;

ALTER TABLE nt_nameserver_export_log DROP column stat9;
ALTER TABLE nt_nameserver_export_log DROP column stat8;
ALTER TABLE nt_nameserver_export_log DROP column stat7;
ALTER TABLE nt_nameserver_export_log DROP column stat6;
ALTER TABLE nt_nameserver_export_log DROP column stat5;
ALTER TABLE nt_nameserver_export_log DROP column stat4;
ALTER TABLE nt_nameserver_export_log DROP column stat3;
ALTER TABLE nt_nameserver_export_log DROP column stat2;
ALTER TABLE nt_nameserver_export_log DROP column stat1;

EO_SQL_2_09
        ;
}

sub _sql_test_2_08 {

    # v2.08 widened nt_user.password from varchar(15) to varchar(128)
    my $len;
    eval {
        ($len) = $dbh->query(
            "SELECT CHARACTER_MAXIMUM_LENGTH FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME   = 'nt_user'
                  AND COLUMN_NAME  = 'password'"
        )->list;
    };
    return ( $len && $len >= 128 ) ? 1 : 0;
}

sub _sql_2_08 {
    return <<EO_SQL_2_08
ALTER table nt_user MODIFY password VARCHAR(128);
ALTER table nt_user_log MODIFY password VARCHAR(128);
EO_SQL_2_08
        ;
}

sub _sql_test_2_05 {

    # nt_zone_record.priority was added in v2.05
    return _column_exists( 'nt_zone_record', 'priority' );
}

sub _sql_2_05 {

    <<EO_SQL_2_05
ALTER TABLE nt_zone_record     ADD priority SMALLINT UNSIGNED DEFAULT 0 AFTER weight;
ALTER TABLE nt_zone_record     ADD other    SMALLINT UNSIGNED DEFAULT 0 AFTER priority;
ALTER TABLE nt_zone_record     MODIFY type enum('A','AAAA','MX','PTR','NS','TXT','CNAME','SRV');

ALTER TABLE nt_zone_record_log ADD priority SMALLINT UNSIGNED DEFAULT 0 AFTER weight;
ALTER TABLE nt_zone_record_log ADD other    SMALLINT UNSIGNED DEFAULT 0 AFTER priority;
ALTER TABLE nt_zone_record_log MODIFY type enum('A','AAAA','MX','PTR','NS','TXT','CNAME','SRV');
EO_SQL_2_05
        ;
}

sub _sql_test_2_00 {

    # the nt_perm table was introduced in 2.00
    my $r;
    eval { $r = $dbh->query("SHOW TABLES LIKE 'nt_perm'")->hashes; };
    return ( $r && $r->[0] ) ? 1 : 0;
}

sub _sql_2_00 {
    <<EO_SQL_2_00
CREATE TABLE nt_perm(
    nt_perm_id          INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_group_id         INT UNSIGNED DEFAULT NULL,
    nt_user_id          INT UNSIGNED DEFAULT NULL,
    inherit_perm        INT UNSIGNED DEFAULT NULL,
    perm_name           VARCHAR(50),

    group_write             TINYINT UNSIGNED NOT NULL DEFAULT 0,
    group_create            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    group_delete            TINYINT UNSIGNED NOT NULL DEFAULT 0,

    zone_write              TINYINT UNSIGNED NOT NULL DEFAULT 0,
    zone_create             TINYINT UNSIGNED NOT NULL DEFAULT 0,
    zone_delegate           TINYINT UNSIGNED NOT NULL DEFAULT 0,
    zone_delete             TINYINT UNSIGNED NOT NULL DEFAULT 0,

    zonerecord_write        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    zonerecord_create       TINYINT UNSIGNED NOT NULL DEFAULT 0,
    zonerecord_delegate     TINYINT UNSIGNED NOT NULL DEFAULT 0,
    zonerecord_delete       TINYINT UNSIGNED NOT NULL DEFAULT 0,

    user_write              TINYINT UNSIGNED NOT NULL DEFAULT 0,
    user_create             TINYINT UNSIGNED NOT NULL DEFAULT 0,
    user_delete             TINYINT UNSIGNED NOT NULL DEFAULT 0,

    nameserver_write        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    nameserver_create       TINYINT UNSIGNED NOT NULL DEFAULT 0,
    nameserver_delete       TINYINT UNSIGNED NOT NULL DEFAULT 0,

    self_write              TINYINT UNSIGNED NOT NULL DEFAULT 0,

    usable_ns0      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns1      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns2      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns3      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns4      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns5      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns6      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns7      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns8      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    usable_ns9      SMALLINT UNSIGNED NOT NULL DEFAULT 0,

    deleted             ENUM('0','1') DEFAULT '0' NOT NULL
);
CREATE INDEX nt_perm_idx1 on nt_perm(nt_group_id,nt_user_id);
CREATE INDEX nt_perm_idx2 on nt_perm(nt_user_id);

INSERT INTO nt_perm VALUES(1,1,0,NULL,NULL,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,0,0,0,0,0,0,0,0,'0');

DROP TABLE IF EXISTS nt_delegate;
CREATE TABLE nt_delegate(
    nt_group_id         INT UNSIGNED NOT NULL,
    nt_object_id        INT UNSIGNED NOT NULL,
    nt_object_type      ENUM('ZONE','ZONERECORD','NAMESERVER','USER','GROUP') NOT NULL ,
    delegated_by_id     INT UNSIGNED NOT NULL,
    delegated_by_name     VARCHAR(50),


    perm_write          TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    perm_delete         TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    perm_delegate       TINYINT UNSIGNED DEFAULT 1 NOT NULL,

    zone_perm_add_records           TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_delete_records        TINYINT UNSIGNED DEFAULT 1 NOT NULL,

    zone_perm_modify_zone           TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_mailaddr       TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_desc           TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_minimum        TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_serial         TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_refresh        TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_retry          TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_expire         TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_ttl            TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_nameservers    TINYINT UNSIGNED DEFAULT 1 NOT NULL,

    zonerecord_perm_modify_name     TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_type     TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_addr     TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_weight   TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_ttl      TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_desc     TINYINT UNSIGNED DEFAULT 1 NOT NULL,

    deleted             ENUM('0','1') DEFAULT '0' NOT NULL
);
CREATE INDEX nt_delegate_idx1 on nt_delegate(nt_group_id,nt_object_id,nt_object_type);
CREATE INDEX nt_delegate_idx2 on nt_delegate(nt_object_id,nt_object_type);


DROP TABLE IF EXISTS nt_delegate_log;
CREATE TABLE nt_delegate_log(
    nt_delegate_log_id              INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nt_user_id                      INT UNSIGNED NOT NULL,
    nt_user_name                    VARCHAR(50),
    action                          ENUM('delegated','modified','deleted') NOT NULL,
    nt_object_type                  ENUM('ZONE','ZONERECORD','NAMESERVER','USER','GROUP') NOT NULL ,
    nt_object_id                    INT UNSIGNED NOT NULL,
    nt_group_id                     INT UNSIGNED NOT NULL,
    timestamp                       INT UNSIGNED NOT NULL,

    perm_write                      TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    perm_delete                     TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    perm_delegate                   TINYINT UNSIGNED DEFAULT 1 NOT NULL,

    zone_perm_add_records           TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_delete_records        TINYINT UNSIGNED DEFAULT 1 NOT NULL,

    zone_perm_modify_zone           TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_mailaddr       TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_desc           TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_minimum        TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_serial         TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_refresh        TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_retry          TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_expire         TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_ttl            TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zone_perm_modify_nameservers    TINYINT UNSIGNED DEFAULT 1 NOT NULL,

    zonerecord_perm_modify_name     TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_type     TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_addr     TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_weight   TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_ttl      TINYINT UNSIGNED DEFAULT 1 NOT NULL,
    zonerecord_perm_modify_desc     TINYINT UNSIGNED DEFAULT 1 NOT NULL
);


ALTER TABLE nt_user_global_log
    MODIFY action ENUM('added','deleted','modified','moved','recovered','delegated','modified delegation','removed delegation') NOT NULL;
ALTER TABLE nt_user_global_log
    ADD target
        ENUM('zone','group','user','nameserver','zone_record')
    AFTER object_id;
ALTER TABLE nt_user_global_log
    ADD target_id
        INT UNSIGNED
    AFTER target;
ALTER TABLE nt_user_global_log
    ADD target_name
        VARCHAR(255)
    AFTER target_id;

INSERT INTO nt_perm (nt_group_id,group_write, group_create, group_delete, zone_write, zone_create, zone_delegate, zone_delete, zonerecord_write, zonerecord_create, zonerecord_delegate, zonerecord_delete, user_write, user_create, user_delete, nameserver_write, nameserver_create, nameserver_delete, self_write)
    SELECT nt_group_id, 1 as group_write, 1 as group_create, 1 as group_delete, 1 as zone_write, 1 as zone_create, 1 as zone_delegate, 1 as zone_delete, 1 as zonerecord_write, 1 as zonerecord_create, 1 as zonerecord_delegate, 1 as zonerecord_delete, 1 as user_write, 1 as user_create, 1 as user_delete, 1 as nameserver_write, 1 as nameserver_create, 1 as nameserver_delete, 1 as self_write FROM nt_group;
EO_SQL_2_00
        ;
}

sub ask {
    my $question = shift;
    my %p        = validate(
        @_,
        {   default  => { type => SCALAR | UNDEF, optional => 1 },
            password => { type => BOOLEAN,        optional => 1 },
        }
    );

    my $pass    = $p{password};
    my $default = $p{default};
    my $response;

PROMPT:
    print "Please enter $question";
    print " [$default]" if defined $default;
    print ": ";
    system "stty -echo" if $pass;
    $response = <STDIN>;
    system "stty echo" if $pass;
    chomp $response;

    return $response
        if length $response > 0;    # they typed something, return it
    return $default if defined $default;    # return the default, if available
    return '';                              # return empty handed
}

sub encode_utf8 {
    my @table_names = @_;

    my $string = '';
    foreach my $table_name (@_) {
        $string .= "ALTER TABLE $table_name CHARACTER SET = utf8;\n";
        $string .= "ALTER TABLE $table_name COLLATE = utf8_bin;\n";
    }

    return $string;
}

sub encode_utf8mb4 {
    my @table_names = @_;

    my $string = 'ALTER DATABASE nictool DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin;';
    foreach my $table_name (@_) {
        $string .= "ALTER TABLE $table_name DEFAULT CHARACTER SET = utf8mb4 COLLATE = utf8mb4_bin;
 OPTIMIZE TABLE $table_name;\n";
    }

    return $string;
}

sub engine_innodb {
    my @table_names = @_;

    my %engines;
    eval {
        my $rows = $dbh->query(
            "SELECT TABLE_NAME AS t, ENGINE AS e FROM information_schema.TABLES " .
                "WHERE TABLE_SCHEMA = DATABASE()"
        )->hashes;
        for my $row ( @{ $rows || [] } ) {
            $engines{ $row->{t} } = $row->{e};
        }
    };

    my $string = '';
    foreach my $table_name (@table_names) {
        my $engine = $engines{$table_name} || '';
        next if uc($engine) eq 'INNODB';            # skip tables already on InnoDB
        $string .= "ALTER TABLE $table_name ENGINE = InnoDB;\n";
    }
    return $string;
}

sub get_db_creds_from_nictoolserver_conf {

    my $file = "lib/nictoolserver.conf";
    $file = "../lib/nictoolserver.conf" if !-f $file;
    $file = "../nictoolserver.conf"     if !-f $file;
    $file = "nictoolserver.conf"        if !-f $file;
    return if !-f $file;

    print "reading DB settings from $file\n";
    my $contents = `cat $file`;

    if ( !$dsn ) {

        #warn "\tparsing DB DSN from $file\n";
        ($dsn) = $contents =~ m/['"](DBI:(?:mysql|MariaDB).*?)["']/;
    }

    if ( !$db_user ) {

        #warn "\tparsing DB user from $file\n";
        ($db_user) = $contents =~ m/db_user\s+=\s+'(\w+)'/;
    }

    if ( !$db_pass ) {

        #warn "\tparsing DB pass from $file\n";
        ($db_pass) = $contents =~ m/db_pass\s+=\s+'(.*)?'/;
    }
}

sub prompt_last_chance {
    print qq{
Beginning SQL upgrades.
If any of the information is incorrect, press Control-C now!
-------------------------
DB_DSN:  $dsn
DB_USER: $db_user
DB_PASS: $db_pass
-------------------------

You made a backup already, right?
  # mysqldump -u root -p nictool > nictool-2011-11-16.sql
  # gzip nictool-2011-11-16.sql

Hit return to continue...
};

        my $r = <STDIN>;
}

sub _get_db_version {
    my $sql = 'SELECT option_value FROM nt_options WHERE option_name="db_version"';
    my $r;
    eval { $r = $dbh->query($sql)->list; };
    return $r;
}

