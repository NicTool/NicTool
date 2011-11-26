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
    ) or die "error parsing command line options";

if ( ! defined $dsn || ! defined $db_user || ! defined $db_pass ) {
    get_db_creds_from_nictoolserver_conf();
}

$dsn     = ask( "database DSN", default  => 
        'DBI:mysql:database=nictool;host=localhost;port=3306') if ! $dsn;
$db_user = ask( "database user", default => 'root' ) if ! $db_user;
$db_pass = ask( "database pass", password => 1 ) if ! $db_pass;

prompt_last_chance();

my $dbh  = DBIx::Simple->connect( $dsn, $db_user, $db_pass )
            or die DBIx::Simple->error;

my @versions = qw/ 2.00 2.05 2.08 2.09 2.10 2.11 /;

foreach my $version ( @versions ) { 
# first, run a DB test query 
    my $test_sub = '_sql_test_' . $version;  # assemble sub name
    $test_sub =~ s/\./_/g;                   # replace . with _
    no strict 'refs';
    if ( &{ $test_sub } ) {                  # run the test
        print "Skipping v$version SQL updates (already applied).\n";
        next;
    };

# run the SQL updates, if needed
    print "applying v $version SQL updates\n";
    my $query = '_sql_' . $version;
    $query =~ s/\./_/g;                   # replace . with _
    my $q_string = &{ $query };           # fetch the queries
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
    return <<EO_SOME_DAY
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


sub _sql_test_2_11 {
    my $r = $dbh->query( 'SELECT option_value FROM nt_options WHERE option_value="2.10"' )->list;
    return 1 if ! defined $r;   # query failed
    return 1 if $r ne '2.10';
    return;   # do the update
};

sub _sql_2_11 {

    my @tables = qw/ nt_delegate  nt_delegate_log    nt_perm                  nt_options 
        nt_group            nt_group_log             nt_group_subgroups  
        nt_nameserver       nt_nameserver_log        nt_nameserver_export_log nt_nameserver_qlog nt_nameserver_qlogfile
        nt_user             nt_user_global_log       nt_user_log              
        nt_user_session     nt_user_session_log
        nt_zone             nt_zone_log              nt_zone_nameserver       
        nt_zone_record      nt_zone_record_log       resource_record_type     /;

    my $convert_to_innodb = engine_innodb( @tables );
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

/* InnoDB is the default database format in mysql 5.5. You want to upgrade
** MySQL to 5.5 due to significant InnoDB performance gains. Don't forget to
** adjust my.cnf for optimal performance. */

$convert_to_innodb
$encode_utf8

ALTER TABLE nt_nameserver_export_log DROP `result_id`;
ALTER TABLE resource_record_type ADD UNIQUE `name` (`name`);
INSERT INTO resource_record_type (`id`,`name`,`description`,`reverse`,`forward`) VALUES ('29','LOC','Location','1','1');

UPDATE nt_options SET option_value='2.11' WHERE option_name='db_version';
EO_211
;
};

sub _sql_test_2_10 {
    my $r = $dbh->query( 'SELECT option_value FROM nt_options WHERE option_value="2.09"' )->list;
    return 1 if ! defined $r;   # query failed
    return 1 if $r ne '2.09';   # current db version != 2.09
    return;         # whee, time to update
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
    nt_zone_id           smallint(5) unsigned NOT NULL,
    nt_nameserver_id     smallint(5) unsigned NOT NULL
) DEFAULT CHARSET=utf8;

/* New database table, replacing nt_zone_record.type ENUM */
DROP TABLE IF EXISTS resource_record_type;
CREATE TABLE resource_record_type (
    id              smallint(2) unsigned NOT NULL AUTO_INCREMENT,
    name            varchar(10) NOT NULL,
PRIMARY KEY (`id`)
) DEFAULT CHARSET=utf8;

INSERT INTO resource_record_type VALUES (2,'NS'),(5,'CNAME'),(6,'SOA'),(12,'PTR'),(15,'MX'),(28,'AAAA'),(33,'SRV'),(99,'SPF'),(252,'AXFR'),(1,'A'),(16,'TXT'),(48,'DNSKEY'),(43,'DS'),(25,'KEY');


/* GLOBALLY change table.deleted columns from enum to tinyint(1) */
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
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns0 FROM nt_zone WHERE deleted=0 AND ns0 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns1 FROM nt_zone WHERE deleted=0 AND ns1 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns2 FROM nt_zone WHERE deleted=0 AND ns2 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns3 FROM nt_zone WHERE deleted=0 AND ns3 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns4 FROM nt_zone WHERE deleted=0 AND ns4 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns5 FROM nt_zone WHERE deleted=0 AND ns5 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns6 FROM nt_zone WHERE deleted=0 AND ns6 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns7 FROM nt_zone WHERE deleted=0 AND ns7 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns8 FROM nt_zone WHERE deleted=0 AND ns8 IS NOT NULL;
REPLACE INTO nt_zone_nameserver (nt_zone_id,nt_nameserver_id) SELECT nt_zone_id,ns9 FROM nt_zone WHERE deleted=0 AND ns9 IS NOT NULL;
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
ALTER TABLE nt_nameserver_export_log MODIFY date_start timestamp NULL DEFAULT NULL;
ALTER TABLE nt_nameserver_export_log CHANGE `date_finish` `date_end` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP  on update CURRENT_TIMESTAMP;

DROP TABLE IF EXISTS nt_nameserver_export_procstatus;

/* Convert all character encodings to UTF8 bin. */
$encode_utf8

UPDATE nt_options SET option_value='2.10' WHERE option_name='db_version';

EO_SQL_2_10
;
};

sub _sql_test_2_09 {
# the nt_options table was added in 2.09. 
    my $r = $dbh->query( 'SELECT option_id FROM nt_options LIMIT 1' );
    return 1 if ! defined $r;     # query failed
    return $r;        # result will be a positive int
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

ALTER TABLE nt_user DROP COLUMN is_admin;
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
    my $r = $dbh->query( 'SELECT priority FROM nt_zone_record LIMIT 1' )->list;
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


