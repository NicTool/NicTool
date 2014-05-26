#
# Copyright 2001 Dajoba, LLC - <info@dajoba.com>

DROP TABLE IF EXISTS nt_nameserver;
CREATE TABLE nt_nameserver(
    nt_nameserver_id    SMALLINT UNSIGNED AUTO_INCREMENT NOT NULL,
    nt_group_id         INT UNSIGNED NOT NULL,
    name                VARCHAR(127) NOT NULL,
    ttl                 INT UNSIGNED,
    description         VARCHAR(255),
    address             VARCHAR(127) NOT NULL,
    logdir              VARCHAR(255),
    datadir             VARCHAR(255),
    export_format       VARCHAR(12) DEFAULT '' NOT NULL,
    export_interval     SMALLINT UNSIGNED,
    export_serials      tinyint(1) UNSIGNED NOT NULL DEFAULT '1',
    export_status       varchar(255) NULL DEFAULT NULL,
    deleted             TINYINT(1) UNSIGNED DEFAULT 0 NOT NULL,
    PRIMARY KEY (`nt_nameserver_id`),
    KEY `nt_nameserver_idx1` (`name`),
    KEY `nt_nameserver_idx2` (`deleted`),
    KEY `nt_group_id` (`nt_group_id`)
    /* CONSTRAINT `nt_nameserver_ibfk_1` FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE */
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


DROP TABLE IF EXISTS nt_nameserver_log;
CREATE TABLE nt_nameserver_log(
    nt_nameserver_log_id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nt_group_id         INT UNSIGNED NOT NULL,
    nt_user_id          INT UNSIGNED NOT NULL,
    action              ENUM('added','modified','deleted','moved') NOT NULL,
    timestamp           INT UNSIGNED NOT NULL,
    nt_nameserver_id    SMALLINT UNSIGNED NOT NULL,
    name                VARCHAR(127),
    ttl                 INT UNSIGNED,
    description         VARCHAR(255),
    address             VARCHAR(127),
    logdir              VARCHAR(255),
    datadir             VARCHAR(255),
    export_format       VARCHAR(12) DEFAULT '' NOT NULL,
    export_interval     SMALLINT UNSIGNED,
    export_serials      tinyint(1) UNSIGNED NOT NULL DEFAULT '1',
    PRIMARY KEY (`nt_nameserver_log_id`),
    KEY `nt_nameserver_log_idx1` (`nt_nameserver_id`),
    KEY `nt_nameserver_log_idx2` (`timestamp`)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;


DROP TABLE IF EXISTS nt_nameserver_export_types;
CREATE TABLE nt_nameserver_export_types (
   id tinyint(3) unsigned NOT NULL AUTO_INCREMENT,
   type varchar(12) NOT NULL DEFAULT '',
   PRIMARY KEY (`id`)
) DEFAULT CHARSET=utf8;

INSERT INTO `nt_nameserver_export_types` (`id`, `type`)
VALUES (1,'tinydns'), (2,'bind'), (3,'maradns'), (4,'powerdns');

INSERT INTO nt_nameserver(nt_group_id, name, ttl, description, address, 
  export_format, logdir, datadir, export_interval) values (1,'ns1.example.com.',86400,'ns east',
  '198.93.97.188','tinydns','/etc/tinydns-ns1/log/main/',
  '/etc/tinydns-ns1/root/',120);
INSERT INTO nt_nameserver(nt_group_id, name, ttl, description, address,
  export_format, logdir, datadir, export_interval) values (1,'ns2.example.com.',86400,'ns west',
  '216.133.235.6','tinydns','/etc/tinydns-ns2/log/main/','/etc/tinydns-ns2/root/',120);
INSERT INTO nt_nameserver(nt_group_id, name, ttl, description, address, 
  export_format, logdir, datadir, export_interval) values (1,'ns3.example.com.',86400,'ns test',
  '127.0.0.1','bind','/var/log', '/etc/namedb/master/',120);
INSERT INTO nt_nameserver_log(nt_group_id,nt_user_id, action, timestamp, nt_nameserver_id) VALUES (1,1,'added',UNIX_TIMESTAMP(), 1);
INSERT INTO nt_nameserver_log(nt_group_id,nt_user_id, action, timestamp, nt_nameserver_id) VALUES (1,1,'added',UNIX_TIMESTAMP(), 2);
INSERT INTO nt_nameserver_log(nt_group_id,nt_user_id, action, timestamp, nt_nameserver_id) VALUES (1,1,'added',UNIX_TIMESTAMP(), 3);


DROP TABLE IF EXISTS nt_nameserver_qlog;
CREATE TABLE nt_nameserver_qlog(
    nt_nameserver_qlog_id   INT UNSIGNED AUTO_INCREMENT NOT NULL,
    nt_nameserver_id        SMALLINT UNSIGNED NOT NULL,
    nt_zone_id              INT UNSIGNED NOT NULL,
    nt_zone_record_id       INT UNSIGNED,
    timestamp               INT UNSIGNED NOT NULL,
    ip                      VARCHAR(15),
    port                    SMALLINT UNSIGNED,
    qid                     SMALLINT UNSIGNED,
    flag                    CHAR(1),
    qtype                   ENUM('a','ns','cname','soa','ptr','hinfo','mx','txt','rp','sig','key','aaaa','axfr','any','unknown'), 
    query                   VARCHAR(255) NOT NULL,
    r_size                  SMALLINT UNSIGNED,
    q_size                  SMALLINT UNSIGNED,
    PRIMARY KEY (`nt_nameserver_qlog_id`),
    KEY `nt_nameserver_qlog_idx1` (`query`),
    KEY `nt_nameserver_qlog_idx2` (`nt_zone_id`),
    KEY `nt_nameserver_qlog_idx3` (`nt_zone_record_id`),
    KEY `nt_nameserver_qlog_idx4` (`timestamp`)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;

DROP TABLE IF EXISTS nt_nameserver_qlogfile;
CREATE TABLE nt_nameserver_qlogfile(
    nt_nameserver_qlogfile_id      INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_nameserver_id               INT UNSIGNED NOT NULL,
    filename                    VARCHAR(30) NOT NULL,
    processed                   INT UNSIGNED,
    line_count                  INT UNSIGNED,
    insert_count                INT UNSIGNED,
    took                        SMALLINT UNSIGNED,
    KEY `nt_nameserver_qlogfile_idx1` (`filename`),
    KEY `nt_nameserver_qlogfile_idx2` (`nt_nameserver_id`)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;

DROP TABLE IF EXISTS nt_nameserver_export_log;
CREATE TABLE nt_nameserver_export_log(
    nt_nameserver_export_log_id     INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_nameserver_id                SMALLINT UNSIGNED NOT NULL,
    date_start                      timestamp NULL DEFAULT NULL,
    date_end                        timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP  on update CURRENT_TIMESTAMP,
    copied                          tinyint(1) UNSIGNED NOT NULL DEFAULT 0,
    message                         VARCHAR(256) NULL DEFAULT NULL,
    success                         tinyint(1) UNSIGNED NULL DEFAULT NULL,
    partial                         tinyint(1) UNSIGNED NOT NULL DEFAULT 0,
    KEY `nt_nameserver_export_log_idx1` (`nt_nameserver_id`)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin ROW_FORMAT=COMPRESSED;
