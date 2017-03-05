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

DROP TABLE IF EXISTS nt_zone_record;
CREATE TABLE nt_zone_record(
    nt_zone_record_id   INT UNSIGNED AUTO_INCREMENT NOT NULL,
    nt_zone_id          INT UNSIGNED NOT NULL,
    name                VARCHAR(255) NOT NULL,
    ttl                 INT UNSIGNED NOT NULL DEFAULT 0,
    description         VARCHAR(255),
    type_id             SMALLINT(2) UNSIGNED NOT NULL,
    address             VARCHAR(512) NOT NULL,
    weight              SMALLINT UNSIGNED,
    priority            SMALLINT UNSIGNED,
    other               VARCHAR(255),
    location            VARCHAR(2) DEFAULT NULL,
    timestamp           timestamp NULL DEFAULT NULL,
    deleted             TINYINT(1) UNSIGNED DEFAULT 0 NOT NULL,
    PRIMARY KEY (`nt_zone_record_id`),
    KEY `nt_zone_record_idx1` (`name`),
    KEY `nt_zone_record_idx3` (`nt_zone_id`),
    KEY `nt_zone_record_idx4` (`deleted`)
    /* CONSTRAINT `nt_zone_record_ibfk_1` FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE */
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;


DROP TABLE IF EXISTS nt_zone_record_log;
CREATE TABLE nt_zone_record_log(
    nt_zone_record_log_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nt_zone_id          INT UNSIGNED NOT NULL,
    nt_user_id          INT UNSIGNED NOT NULL,
    action              ENUM('added','modified','deleted','recovered') NOT NULL,
    timestamp           INT UNSIGNED NOT NULL,
    nt_zone_record_id   INT UNSIGNED NOT NULL,
    name                VARCHAR(255),
    ttl                 INT UNSIGNED,
    description         VARCHAR(255),
    type_id             SMALLINT(2) UNSIGNED NOT NULL,
    address             VARCHAR(512),
    weight              SMALLINT UNSIGNED,
    priority            SMALLINT UNSIGNED,
    other               VARCHAR(255),
    location            VARCHAR(2) DEFAULT NULL,
    PRIMARY KEY (`nt_zone_record_log_id`),
    KEY `nt_zone_record_log_idx1` (`timestamp`),
    KEY `nt_zone_record_log_idx2` (`nt_zone_record_id`),
    KEY `nt_zone_record_log_idx3` (`nt_zone_id`),
    KEY `nt_zone_record_log_idx4` (`action`),
    KEY `nt_user_id` (`nt_user_id`)
    /* CONSTRAINT `nt_zone_record_log_ibfk_3` FOREIGN KEY (`nt_zone_record_id`) REFERENCES `nt_zone_record` (`nt_zone_record_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    ** CONSTRAINT `nt_zone_record_log_ibfk_1` FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    ** CONSTRAINT `nt_zone_record_log_ibfk_2` FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE */
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;

