#
# Copyright 2001 Dajoba, LLC - <info@dajoba.com>

DROP TABLE IF EXISTS nt_nameserver;
CREATE TABLE nt_nameserver(
    nt_nameserver_id    SMALLINT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_group_id         INT UNSIGNED NOT NULL,
    name                VARCHAR(127) NOT NULL,
    ttl                 INT UNSIGNED,
    description         VARCHAR(255),
    address             VARCHAR(127) NOT NULL,
    logdir              VARCHAR(255),
    datadir             VARCHAR(255),
    export_format       enum('djb','bind') NOT NULL,
    export_interval     SMALLINT UNSIGNED,
    export_serials      tinyint(1) UNSIGNED NOT NULL DEFAULT '1',
    deleted             TINYINT(1) UNSIGNED DEFAULT 0 NOT NULL
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
CREATE INDEX nt_nameserver_idx1 on nt_nameserver(name);
CREATE INDEX nt_nameserver_idx2 on nt_nameserver(deleted);

DROP TABLE IF EXISTS nt_nameserver_log;
CREATE TABLE nt_nameserver_log(
    nt_nameserver_log_id    INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
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
    export_format       enum('djb','bind'),
    export_interval     SMALLINT UNSIGNED,
    export_serials      tinyint(1) UNSIGNED NOT NULL DEFAULT '1'
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
CREATE INDEX nt_nameserver_log_idx1 on nt_nameserver_log(nt_nameserver_id);
CREATE INDEX nt_nameserver_log_idx2 on nt_nameserver_log(timestamp);

INSERT INTO nt_nameserver(nt_group_id, name, ttl, description, address,
  export_format, logdir, datadir, export_interval) values (1,'ns2.nictool.com.',86400,'ns west',
  '216.133.235.6','djb','/etc/tinydns-ns2/log/main/','/etc/tinydns-ns2/root/',120);
INSERT INTO nt_nameserver(nt_group_id, name, ttl, description, address, 
  export_format, logdir, datadir, export_interval) values (1,'ns1.nictool.com.',86400,'ns east',
  '198.93.97.188','djb','/etc/tinydns-ns1/log/main/',
  '/etc/tinydns-ns1/root/',120);
INSERT INTO nt_nameserver_log(nt_group_id,nt_user_id, action, timestamp, nt_nameserver_id) VALUES (1,1,'added',UNIX_TIMESTAMP(), 1);
INSERT INTO nt_nameserver_log(nt_group_id,nt_user_id, action, timestamp, nt_nameserver_id) VALUES (1,1,'added',UNIX_TIMESTAMP(), 2);


DROP TABLE IF EXISTS nt_nameserver_qlog;
CREATE TABLE nt_nameserver_qlog(
    nt_nameserver_qlog_id   INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_nameserver_id        SMALLINT UNSIGNED NOT NULL,
    nt_zone_id              INT UNSIGNED NOT NULL,
    nt_zone_record_id       INT UNSIGNED,
    timestamp               INT UNSIGNED NOT NULL,
    ip                      VARCHAR(15),
    port                    SMALLINT UNSIGNED, # remote port query came from
    qid                     SMALLINT UNSIGNED, # query ID passed by remote side
    flag                    CHAR(1), # - means did not provide an answer, + means provided answer (this should always be true)
    qtype                   ENUM('a','ns','cname','soa','ptr','hinfo','mx','txt','rp','sig','key','aaaa','axfr','any','unknown'), 
    query                   VARCHAR(255) NOT NULL, # what they asked for
    r_size                  SMALLINT UNSIGNED,
    q_size                  SMALLINT UNSIGNED
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
CREATE INDEX nt_nameserver_qlog_idx1 on nt_nameserver_qlog(query); # for searching
CREATE INDEX nt_nameserver_qlog_idx2 on nt_nameserver_qlog(nt_zone_id); # for search as well
CREATE INDEX nt_nameserver_qlog_idx3 on nt_nameserver_qlog(nt_zone_record_id); # for searching ..
CREATE INDEX nt_nameserver_qlog_idx4 on nt_nameserver_qlog(timestamp); 

DROP TABLE IF EXISTS nt_nameserver_qlogfile;
CREATE TABLE nt_nameserver_qlogfile(
    nt_nameserver_qlogfile_id      INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_nameserver_id               INT UNSIGNED NOT NULL,
    filename                    VARCHAR(30) NOT NULL,
    processed                   INT UNSIGNED,
    line_count                  INT UNSIGNED,
    insert_count                INT UNSIGNED,
    took                        SMALLINT UNSIGNED
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
CREATE INDEX nt_nameserver_qlogfile_idx1 on nt_nameserver_qlogfile(filename); # for search from grab_logs.pl
CREATE INDEX nt_nameserver_qlogfile_idx2 on nt_nameserver_qlogfile(nt_nameserver_id); # for searching

DROP TABLE IF EXISTS nt_nameserver_export_log;
CREATE TABLE nt_nameserver_export_log(
    nt_nameserver_export_log_id     INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_nameserver_id                SMALLINT UNSIGNED NOT NULL,
    date_start                      timestamp(10) NULL DEFAULT NULL,
    date_end                        timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP  on update CURRENT_TIMESTAMP,
    result_id                       int NULL DEFAULT NULL,
    message                         VARCHAR(256) NULL DEFAULT NULL,
    success                         tinyint(1) UNSIGNED NULL DEFAULT NULL,
    partial                         tinyint(1) UNSIGNED NOT NULL DEFAULT 0
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
CREATE INDEX nt_nameserver_export_log_idx1 on nt_nameserver_export_log(nt_nameserver_id);

DROP TABLE IF EXISTS nt_nameserver_export_procstatus;
CREATE TABLE nt_nameserver_export_procstatus(
    nt_nameserver_id                SMALLINT UNSIGNED NOT NULL PRIMARY KEY,
    timestamp                       INT UNSIGNED NOT NULL,
    status                          VARCHAR(255)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

