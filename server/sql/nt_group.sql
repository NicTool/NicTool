#
# Copyright 2001 Dajoba, LLC - <info@dajoba.com>

DROP TABLE IF EXISTS nt_group;
CREATE TABLE nt_group (
    nt_group_id         INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    parent_group_id     INT UNSIGNED NOT NULL,
    name                VARCHAR(255) NOT NULL,
    deleted             enum('0','1') DEFAULT '0' NOT NULL
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
CREATE INDEX nt_group_idx1 on nt_group(parent_group_id); 
CREATE INDEX nt_group_idx2 on nt_group(name); # for searching
CREATE INDEX nt_group_idx3 on nt_group(deleted); 


DROP TABLE IF EXISTS nt_group_log;
CREATE TABLE nt_group_log(
    nt_group_log_id     INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nt_group_id         INT UNSIGNED NOT NULL,
    nt_user_id          INT UNSIGNED NOT NULL,
    action              ENUM('added','modified','deleted','moved') NOT NULL,
    timestamp           INT UNSIGNED NOT NULL,
    modified_group_id   INT UNSIGNED NOT NULL,
    parent_group_id     INT UNSIGNED,
    name                VARCHAR(255)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
CREATE INDEX nt_group_log_idx1 on nt_group_log(nt_group_id); 
CREATE INDEX nt_group_log_idx2 on nt_group_log(timestamp);


DROP TABLE IF EXISTS nt_group_subgroups;
CREATE TABLE nt_group_subgroups(
    nt_group_id         INT UNSIGNED NOT NULL,
    nt_subgroup_id      INT UNSIGNED NOT NULL,
    rank                INT UNSIGNED NOT NULL
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
CREATE INDEX nt_group_subgroups_idx1 on nt_group_subgroups(nt_group_id);
CREATE INDEX nt_group_subgroups_idx2 on nt_group_subgroups(nt_subgroup_id);

INSERT INTO nt_group(nt_group_id, name) VALUES (0, 'NicTool');
INSERT INTO nt_group_log(nt_group_id, nt_user_id, action, timestamp, modified_group_id, parent_group_id) VALUES (1, 1, 'added', UNIX_TIMESTAMP(), 1, 0);

