# vim: set expandtab:
#
# $Id: nt_zone.sql 694 2008-10-16 07:38:33Z rob@bsdfreaks.nl $
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


DROP TABLE IF EXISTS nt_zone;
CREATE TABLE nt_zone(
    nt_zone_id             INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_group_id         INT UNSIGNED NOT NULL,
    zone                VARCHAR(255) NOT NULL,
    mailaddr            VARCHAR(127),
    description         VARCHAR(255),
    serial              INT UNSIGNED NOT NULL DEFAULT '1',
    refresh             INT UNSIGNED,
    retry               INT UNSIGNED,
    expire              INT UNSIGNED,
    minimum             INT UNSIGNED,
    ttl                 INT UNSIGNED,
    ns0                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns1                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns2                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns3                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns4                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns5                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns6                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns7                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns8                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    ns9                 SMALLINT UNSIGNED NOT NULL DEFAULT '0',
    deleted             ENUM('0','1') DEFAULT '0' NOT NULL
);
CREATE INDEX nt_zone_idx1 on nt_zone(nt_group_id);
CREATE INDEX nt_zone_idx2 on nt_zone(deleted);
CREATE INDEX nt_zone_idx3 on nt_zone(zone); 
CREATE INDEX nt_zone_idxns0 on nt_zone(ns0);
CREATE INDEX nt_zone_idxns1 on nt_zone(ns1);
CREATE INDEX nt_zone_idxns2 on nt_zone(ns2);
CREATE INDEX nt_zone_idxns3 on nt_zone(ns3);
CREATE INDEX nt_zone_idxns4 on nt_zone(ns4);
CREATE INDEX nt_zone_idxns5 on nt_zone(ns5);
CREATE INDEX nt_zone_idxns6 on nt_zone(ns6);
CREATE INDEX nt_zone_idxns7 on nt_zone(ns7);
CREATE INDEX nt_zone_idxns8 on nt_zone(ns8);
CREATE INDEX nt_zone_idxns9 on nt_zone(ns9);

# show index from nt_zone
# speedup: myisamchk --sort-index --sort-records=14 nt_zone
# where 14 = the zone index or whatever order by happens most often


DROP TABLE IF EXISTS nt_zone_log;
CREATE TABLE nt_zone_log(
    nt_zone_log_id      INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nt_group_id         INT UNSIGNED NOT NULL,
    nt_user_id          INT UNSIGNED NOT NULL,
    action              ENUM('added','modified','deleted','moved','recovered') NOT NULL,
    timestamp           INT UNSIGNED NOT NULL,
    nt_zone_id          INT UNSIGNED NOT NULL,
    zone                VARCHAR(255) NOT NULL,
    mailaddr            VARCHAR(127),
    description         VARCHAR(255),
    serial              INT UNSIGNED,
    refresh             INT UNSIGNED,
    retry               INT UNSIGNED,
    expire              INT UNSIGNED,
    minimum             INT UNSIGNED,
    ttl                 INT UNSIGNED
);
CREATE INDEX nt_zone_log_idx1 on nt_zone_log(timestamp); # for update_djb
CREATE INDEX nt_zone_log_idx2 on nt_zone_log(nt_zone_id); # for update_djb
CREATE INDEX nt_zone_log_idx3 on nt_zone_log(action); # for update_djb


DROP TABLE IF EXISTS nt_zone_record;
CREATE TABLE nt_zone_record(
    nt_zone_record_id   INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_zone_id          INT UNSIGNED NOT NULL,
    name                VARCHAR(255) NOT NULL,
    ttl                 INT UNSIGNED NOT NULL DEFAULT '0',
    description         VARCHAR(255),
    type                ENUM('A','AAAA','MX','PTR','NS','TXT','CNAME','SRV'),
    address             VARCHAR(255) NOT NULL,
    weight              SMALLINT UNSIGNED,
    priority            SMALLINT UNSIGNED,
    other               VARCHAR(255),
    deleted             ENUM('0','1') DEFAULT '0' NOT NULL
);
CREATE INDEX nt_zone_record_idx1 on nt_zone_record(name); # for searching
CREATE INDEX nt_zone_record_idx2 on nt_zone_record(address); # for searching
CREATE INDEX nt_zone_record_idx3 on nt_zone_record(nt_zone_id); # for lots of backend searches..
CREATE INDEX nt_zone_record_idx4 on nt_zone_record(deleted);


DROP TABLE IF EXISTS nt_zone_record_log;
CREATE TABLE nt_zone_record_log(
    nt_zone_record_log_id   INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nt_zone_id          INT UNSIGNED NOT NULL,
    nt_user_id          INT UNSIGNED NOT NULL,
    action             ENUM('added','modified','deleted','recovered') NOT NULL,
    timestamp           INT UNSIGNED NOT NULL,
    nt_zone_record_id   INT UNSIGNED NOT NULL,
    name                VARCHAR(255),
    ttl                 INT UNSIGNED,
    description         VARCHAR(255),
    type                ENUM('A','AAAA','MX','PTR','NS','TXT','CNAME','SRV'),
    address             VARCHAR(255),
    weight              SMALLINT UNSIGNED,
    priority            SMALLINT UNSIGNED,
    other               VARCHAR(255)
);
CREATE INDEX nt_zone_record_log_idx1 on nt_zone_record_log(timestamp);
CREATE INDEX nt_zone_record_log_idx2 on nt_zone_record_log(nt_zone_record_id);
CREATE INDEX nt_zone_record_log_idx3 on nt_zone_record_log(nt_zone_id);
CREATE INDEX nt_zone_record_log_idx4 on nt_zone_record_log(action); # for update_djb

