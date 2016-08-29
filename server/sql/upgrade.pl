#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use DBIx::Simple;
use Getopt::Long;
use Params::Validate qw/:all/;
$Data::Dumper::Sortkeys=1;

# process command line options
Getopt::Long::GetOptions(
    'dsn=s'     => \my $dsn,
    'user=s'    => \my $db_user,
    'pass=s'    => \my $db_pass,
    'host=s'    => \my $db_host,
    ) or die "error parsing command line options";

if ( ! defined $dsn || ! defined $db_user || ! defined $db_pass ) {
    get_db_creds_from_nictoolserver_conf();
}

$db_host = ask( "database host", default => '127.0.0.1') if ! $db_host;
$dsn     = ask( "database DSN", default  => "DBI:mysql:database=nictool;host=$db_host;port=3306") if ! $dsn;
$db_user = ask( "database user", default => 'root' ) if ! $db_user;
$db_pass = ask( "database pass", password => 1 ) if ! $db_pass;

prompt_last_chance();

my $dbh  = DBIx::Simple->connect( $dsn, $db_user, $db_pass )
            or die DBIx::Simple->error;

# NOTE: when making schema changes, update db_version in 12_nt_options.sql
my @versions = qw/ 2.00 2.05 2.08 2.09 2.10 2.11 2.14 2.15 2.16 2.17 2.18
                   2.24 2.27 2.28 2.29 2.30 /;

foreach my $version ( @versions ) {
# first, run a DB test query
    my $test_sub = '_sql_test_' . $version;  # assemble sub name
    $test_sub =~ s/\./_/g;                   # replace . with _
    no strict 'refs';  ## no critic
    my $is_applied = &$test_sub;
    use strict;
    if ( $is_applied ) {                     # run the test
        print "Skipping v$version SQL updates (already applied).\n";
        next;
    };

# run the SQL updates, if needed
    print "applying v $version SQL updates\n";
    my $queries = '_sql_' . $version;
    $queries =~ s/\./_/g;                   # replace . with _
    no strict 'refs';  ## no critic
    my $q_string = &$queries;             # fetch the queries
    use strict;
    $q_string =~ s/[\s]{2,}/ /g;          # condense whitespace
    foreach my $q ( split(';', $q_string )  ) { # split string into queries
        next if $q =~ /^\s+$/;            # skip blank entries
        print "$q;\n";                    # show the query to user
        sleep 1;                          # give 'em time to read it
        $dbh->query( $q ) or die DBIx::Simple->error;   # run it!
    };
    print "\n";
};

sub _sql_2_some_fine_day {
    my @tables = $dbh->query("SHOW TABLES")->flat;
    my $convert_to_innodb = engine_innodb( @tables );
    return <<EO_SOME_DAY
/* InnoDB is the default database format in mysql 5.5. You want to upgrade
** MySQL to 5.5 due to significant InnoDB performance gains. Don't forget to
** adjust my.cnf for optimal performance. */

$convert_to_innodb

/* When switched to InnoDB, these constraints can be added */

ALTER TABLE `nt_zone_log` ADD FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_log` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_log` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_record` ADD FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_record_log` ADD FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_record_log` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_record_log` ADD FOREIGN KEY (`nt_zone_record_id`) REFERENCES `nt_zone_record` (`nt_zone_record_id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `nt_user_session_log` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_user_session` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_user_global_log` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `nt_nameserver` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `nt_group_subgroups` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_group_log` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `nt_delegate` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;
EO_SOME_DAY
;
};


sub _sql_test_2_32 {
    my $r = _get_db_version() or return 1;  # query failed
    return 0 if $r eq '2.30';   # update!
    return 1;                   # don't update
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
    my $r = _get_db_version() or return 1;  # query failed
    return 0 if $r eq '2.29';   # update!
    return 1;                   # don't update
};

sub _sql_2_30 {
    <<EO_SQL_2_30
ALTER table nt_user MODIFY password VARCHAR(255);
ALTER table nt_user_log MODIFY password VARCHAR(255);

UPDATE nt_options SET option_value='2.30' WHERE option_name='db_version';
EO_SQL_2_30
}

sub _sql_test_2_29 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed
    return 1 if $r eq '2.29';   # already up-to-date
    return 0 if $r eq '2.28';   # do it!
    return 1;                   # don't update
};

sub _sql_2_29 {
    <<EO_SQL_2_29
ALTER TABLE nt_zone_record_log ADD COLUMN location VARCHAR(2) DEFAULT NULL AFTER other;

UPDATE nt_options SET option_value='2.29' WHERE option_name='db_version';
EO_SQL_2_29
}

sub _sql_test_2_28 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed
    return 1 if $r eq '2.28';   # already up-to-date
    return 0 if $r eq '2.27';   # do it!
    return 1;                   # don't update
};

sub _sql_2_28 {
    <<EO_SQL_2_28
ALTER TABLE nt_zone ADD COLUMN last_publish TIMESTAMP DEFAULT 0 AFTER last_modified;

UPDATE nt_options SET option_value='2.28' WHERE option_name='db_version';
EO_SQL_2_28
}

sub _sql_test_2_27 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed

    my $exists = $dbh->query("SELECT option_value FROM nt_options WHERE option_name='session_timeout'")->hashes;
    if (scalar $exists && $exists->[0] && $exists->[0]{option_value}) {
        return 1;               # already updated
    };

    return 0 if $r eq '2.24';   # do it!
    return 1;                   # don't update
};

sub _sql_2_27 {
    <<EO_SQL_2_27
ALTER TABLE nt_user ADD COLUMN pass_salt VARCHAR(16) AFTER password;
ALTER TABLE nt_user_log ADD COLUMN pass_salt VARCHAR(16) AFTER password;

INSERT INTO nt_options
VALUES (2,'session_timeout','45'),
       (3,'default_group','NicTool');

UPDATE nt_options SET option_value='2.27' WHERE option_name='db_version';
EO_SQL_2_27
}

sub _sql_test_2_24 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `nt_nameserver` LIKE 'export_type_id'")->hashes;
    if (scalar $exists && $exists->[0] && $exists->[0]{field}) {
        return 1;               # already updated
    };

    return 0 if $r eq '2.18';   # do it!
    return 1;                   # don't update
};

sub _sql_2_24 {
    <<EO_SQL_2_24
ALTER TABLE `nt_nameserver` ADD column address6 VARCHAR(127)  NULL DEFAULT NULL AFTER address;
ALTER TABLE `nt_nameserver` ADD column remote_login VARCHAR(127) DEFAULT NULL AFTER address6;
ALTER TABLE `nt_nameserver` ADD column export_type_id INT UNSIGNED DEFAULT '1' AFTER remote_login;
ALTER TABLE `nt_nameserver_log` ADD column `address6` VARCHAR(127) NULL DEFAULT NULL AFTER address;
ALTER TABLE `nt_nameserver_log` ADD column export_type_id INT UNSIGNED NULL AFTER address6;

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

UPDATE nt_nameserver SET export_type_id=1 WHERE export_format IN ('tinydns','djb','djbdns');
UPDATE nt_nameserver SET export_type_id=2 WHERE export_format='bind';
UPDATE nt_nameserver SET export_type_id=3 WHERE export_format='maradns';
UPDATE nt_nameserver SET export_type_id=4 WHERE export_format='powerdns';
ALTER TABLE nt_nameserver DROP column export_format;

UPDATE nt_options SET option_value='2.24' WHERE option_name='db_version';
EO_SQL_2_24
};

sub _sql_test_2_18 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `resource_record_type` LIKE 'obsolete'")->hashes;
    if (scalar $exists && $exists->[0] && $exists->[0]{field}) {
        return 1;               # already updated
    };

    return 0 if $r eq '2.17';   # do it!
    return 1;                   # don't update
};

sub _sql_2_18 {
    <<EO_SQL_2_18
ALTER TABLE resource_record_type ADD column obsolete TINYINT(1) NOT NULL DEFAULT '0' AFTER forward;
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
};

sub _sql_test_2_17 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `nt_user` LIKE 'is_admin'")->hashes;
    if (scalar $exists && $exists->[0] && $exists->[0]{field}) {
        return 1;               # already updated
    };

    return 0 if $r eq '2.16';   # do it!
    return 1;                   # don't update
};

sub _sql_2_17 {

    return <<EO_SQL_2_17
ALTER TABLE nt_user ADD COLUMN is_admin TINYINT(1) UNSIGNED default '0' AFTER email;
EO_SQL_2_17
}

sub _sql_test_2_16 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed

    my $exists = $dbh->query("SHOW COLUMNS FROM `nt_perm` LIKE 'usable_ns'")->hashes;
    if (scalar $exists && $exists->[0] && $exists->[0]{field}) {
        return 1;               # already updated
    };

    return 0 if $r eq '2.15';   # do it!
    return 1;                   # don't update
};

sub _sql_2_16 {
    return <<EO_SQL_2_16
ALTER TABLE nt_perm ADD column usable_ns VARCHAR(50) AFTER self_write;
UPDATE nt_perm SET usable_ns=(CONCAT_WS(',', usable_ns0,usable_ns1,usable_ns2,usable_ns3,usable_ns4,usable_ns5,usable_ns6,usable_ns7,usable_ns8,usable_ns9));
ALTER TABLE nt_perm DROP column usable_ns0;
ALTER TABLE nt_perm DROP column usable_ns1;
ALTER TABLE nt_perm DROP column usable_ns2;
ALTER TABLE nt_perm DROP column usable_ns3;
ALTER TABLE nt_perm DROP column usable_ns4;
ALTER TABLE nt_perm DROP column usable_ns5;
ALTER TABLE nt_perm DROP column usable_ns6;
ALTER TABLE nt_perm DROP column usable_ns7;
ALTER TABLE nt_perm DROP column usable_ns8;
ALTER TABLE nt_perm DROP column usable_ns9;
ALTER TABLE nt_zone_record MODIFY address VARCHAR(512) NOT NULL;
ALTER TABLE nt_zone_record_log MODIFY address VARCHAR(512) NOT NULL;
UPDATE nt_options SET option_value='2.16' WHERE option_name='db_version';
EO_SQL_2_16
};

sub _sql_test_2_15 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed
    return 0 if $r eq '2.14';   # do it!
    return 1;                   # don't update
};

sub _sql_2_15 {
    <<EO_SQL_2_15
/* submitted by Arthur Gouros, remove legacy \072 chars */
UPDATE nt_zone_record SET address = REPLACE(address,'\\072',':');
UPDATE nt_options SET option_value='2.15' WHERE option_name='db_version';
EO_SQL_2_15
;
};

sub _sql_test_2_14 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed
    return 0 if $r eq '2.11';   # do it! (no DB changes since v2.11)
    return 1;                   # don't update
};

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
};

sub _sql_test_2_11 {
    my $r = _get_db_version();
    return 1 if ! defined $r;   # query failed
    return 0 if $r eq '2.10';   # do it!
    return 1;                   # don't update
};

sub _sql_2_11 {

    my @tables = qw/ nt_delegate  nt_delegate_log    nt_perm                  nt_options
        nt_group            nt_group_log             nt_group_subgroups
        nt_nameserver       nt_nameserver_log        nt_nameserver_export_log nt_nameserver_qlog nt_nameserver_qlogfile
        nt_user             nt_user_global_log       nt_user_log
        nt_user_session     nt_user_session_log
        nt_zone             nt_zone_log              nt_zone_nameserver
        nt_zone_record      nt_zone_record_log       resource_record_type     /;

    my $encode_utf8 = encode_utf8( @tables );

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
};

sub _sql_test_2_10 {
    my $r;
    my $sql = 'SELECT option_value FROM nt_options WHERE option_value="2.09"';
    eval { $r = $dbh->query( $sql )->list; };
    return 1 if ! defined $r;   # query failed, 2.09 not applied yet
    return 0 if $r eq '2.09';   # set is_applied=0
    return 1;                   # DB version is probably > 2.09 already
};

sub _sql_2_10 {

    my @tables = qw/ nt_delegate nt_delegate_log nt_options nt_perm
        nt_group nt_group_log nt_group_subgroups nt_nameserver nt_nameserver_log
        nt_nameserver_export_log nt_nameserver_qlog nt_nameserver_qlogfile
        nt_user nt_user_log nt_user_global_log nt_user_session nt_user_session_log
        nt_zone nt_zone_log nt_zone_record nt_zone_record_log /;

    my $encode_utf8 = encode_utf8( @tables );

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
};

sub _sql_test_2_09 {
# the nt_options table was added in 2.09.
    my $r;
    eval { $r = $dbh->query( 'SELECT option_id FROM nt_options LIMIT 1' ); };
    return 0 if ! defined $r;   # query failed, set is_applied=0
    return $r;                  # result will be a positive int
};

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
};

sub _sql_test_2_08 {
# was varchar 15. These queries will succeed after the initial failure
    $dbh->query( "SET sql_mode='STRICT_ALL_TABLES'" );
    my $r = $dbh->query( "REPLACE INTO nt_user SET
            nt_group_id=1, email='deleteme\@test.com',
            first_name = 'first', last_name = 'last',
            username   = 'test',  password  = '123456789012345678',
            deleted='1'"
        );
    my $id = $dbh->last_insert_id( undef, undef, 'nt_user', undef );
    $dbh->query( "SET sql_mode=''" );
# ID will be undefined if the query fails.
# Otherwise, it'll return some positive integer, meaning 'patch applied'
    return $id;
};

sub _sql_2_08 {
    return <<EO_SQL_2_08
ALTER table nt_user MODIFY password VARCHAR(128);
ALTER table nt_user_log MODIFY password VARCHAR(128);
EO_SQL_2_08
;
};

sub _sql_test_2_05 {
    my $r;
    eval { $r = $dbh->query( 'SELECT priority FROM nt_zone_record LIMIT 1' )->list; };
    return 1 if $dbh->error eq 'DBI error: ';  # the query succeeded
    return;
};

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
};

sub _sql_test_2_00 {

    # the nt_perm table was introduced in 2.00. A failed query means the patch
    # needs to be applied.
    return $dbh->query( 'SELECT nt_perm_id FROM nt_perm')->list;
};

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
};


sub ask {
    my $question = shift;
    my %p = validate( @_,
        {   default  => { type => SCALAR|UNDEF, optional => 1 },
            password => { type => BOOLEAN, optional => 1 },
        }
    );

    my $pass     = $p{password};
    my $default  = $p{default};
    my $response;

PROMPT:
    print "Please enter $question";
    print " [$default]" if defined $default;
    print ": ";
    system "stty -echo" if $pass;
    $response = <STDIN>;
    system "stty echo" if $pass;
    chomp $response;

    return $response if length $response > 0; # they typed something, return it
    return $default if defined $default;   # return the default, if available
    return '';                             # return empty handed
}

sub encode_utf8 {
    my @table_names = @_;

    my $string = '';
    foreach my $table_name ( @_ ) {
        $string .= "ALTER TABLE $table_name CHARACTER SET = utf8;\n";
        $string .= "ALTER TABLE $table_name COLLATE = utf8_bin;\n";
    };

    return $string;
};

sub engine_innodb {
    my @table_names = @_;

    my $string = '';
    foreach my $table_name ( @_ ) {
        # MySQL 4.1 and prior
        #$string .= "ALTER TABLE $table_name TYPE = InnoDB;\n";

        # MySQL 4.1+
        $string .= "ALTER TABLE $table_name ENGINE = InnoDB;\n";
    };
    return $string;
};

sub get_db_creds_from_nictoolserver_conf {

    my $file = "lib/nictoolserver.conf";
    $file = "../lib/nictoolserver.conf" if ! -f $file;
    $file = "../nictoolserver.conf" if ! -f $file;
    $file = "nictoolserver.conf" if ! -f $file;
    return if ! -f $file;

    print "reading DB settings from $file\n";
    my $contents = `cat $file`;

    if ( ! $dsn ) {
        #warn "\tparsing DB DSN from $file\n";
        ($dsn) = $contents =~ m/['"](DBI:mysql.*?)["']/;
    };

    if ( ! $db_user ) {
        #warn "\tparsing DB user from $file\n";
        ($db_user) = $contents =~ m/db_user\s+=\s+'(\w+)'/;
    };

    if ( ! $db_pass ) {
        #warn "\tparsing DB pass from $file\n";
        ($db_pass) = $contents =~ m/db_pass\s+=\s+'(.*)?'/;
    };
};

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
};

sub _get_db_version {
    my $sql = 'SELECT option_value FROM nt_options WHERE option_name="db_version"';
    my $r;
    eval { $r = $dbh->query( $sql )->list; };
    return $r;
};

