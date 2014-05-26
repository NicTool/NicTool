#
# Copyright 2001 Dajoba, LLC - <info@dajoba.com>

DROP TABLE IF EXISTS nt_group;
CREATE TABLE `nt_group` (
    nt_group_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    parent_group_id   INT UNSIGNED NOT NULL DEFAULT 0,
    name              varchar(255) NOT NULL,
    deleted           tinyint(1) unsigned NOT NULL DEFAULT 0,
    PRIMARY KEY (`nt_group_id`),
    KEY `nt_group_idx1` (`parent_group_id`),
    KEY `nt_group_idx2` (`name`),
    KEY `nt_group_idx3` (`deleted`)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


DROP TABLE IF EXISTS nt_group_log;
CREATE TABLE nt_group_log(
    nt_group_log_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nt_group_id         INT UNSIGNED NOT NULL,
    nt_user_id          INT UNSIGNED NOT NULL,
    action              ENUM('added','modified','deleted','moved') NOT NULL,
    timestamp           INT UNSIGNED NOT NULL,
    modified_group_id   INT UNSIGNED NOT NULL,
    parent_group_id     INT UNSIGNED,
    name                VARCHAR(255),
    PRIMARY KEY (`nt_group_log_id`),
    KEY `nt_group_log_idx1` (`nt_group_id`),
    KEY `nt_group_log_idx2` (`timestamp`)
    /* CONSTRAINT `nt_group_log_ibfk_1` FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE */
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;


DROP TABLE IF EXISTS nt_group_subgroups;
CREATE TABLE nt_group_subgroups(
    nt_group_id         INT UNSIGNED NOT NULL,
    nt_subgroup_id      INT UNSIGNED NOT NULL,
    rank                INT UNSIGNED NOT NULL,
    KEY `nt_group_subgroups_idx1` (`nt_group_id`),
    KEY `nt_group_subgroups_idx2` (`nt_subgroup_id`)
    /* CONSTRAINT `nt_group_subgroups_ibfk_1` FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE */
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

INSERT INTO nt_group(nt_group_id, name) VALUES (1, 'NicTool');
INSERT INTO nt_group_log(nt_group_id, nt_user_id, action, timestamp, modified_group_id, parent_group_id) VALUES (1, 1, 'added', UNIX_TIMESTAMP(), 1, 0);
