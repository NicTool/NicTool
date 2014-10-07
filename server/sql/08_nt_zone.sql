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
    nt_zone_id          INT UNSIGNED AUTO_INCREMENT NOT NULL,
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
    location            VARCHAR(2) DEFAULT NULL,
    last_modified       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
    last_publish        TIMESTAMP DEFAULT 0,
    deleted             TINYINT(1) UNSIGNED DEFAULT 0 NOT NULL,
    PRIMARY KEY (`nt_zone_id`),
    KEY `nt_zone_idx1` (`nt_group_id`),
    KEY `nt_zone_idx2` (`deleted`),
    KEY `nt_zone_idx3` (`zone`)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;


DROP TABLE IF EXISTS nt_zone_log;
CREATE TABLE nt_zone_log(
    nt_zone_log_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
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
    ttl                 INT UNSIGNED,
    PRIMARY KEY (`nt_zone_log_id`),
    KEY `nt_zone_log_idx1` (`timestamp`),
    KEY `nt_zone_log_idx2` (`nt_zone_id`),
    KEY `nt_zone_log_idx3` (`action`),
    KEY `nt_group_id` (`nt_group_id`),
    KEY `nt_user_id` (`nt_user_id`)
    /* CONSTRAINT `nt_zone_log_ibfk_3` FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    ** CONSTRAINT `nt_zone_log_ibfk_1` FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    ** CONSTRAINT `nt_zone_log_ibfk_2` FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE */
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;


CREATE TABLE nt_zone_nameserver (
    nt_zone_id           int(10) unsigned NOT NULL,
    nt_nameserver_id     smallint(5) unsigned NOT NULL,
    UNIQUE KEY `zone_ns_id` (`nt_zone_id`,`nt_nameserver_id`)
) DEFAULT CHARSET=utf8;
