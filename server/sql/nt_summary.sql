#
# vim: set expandtab:
#
# $Id: nt_summary.sql,v 1.3 2004/10/05 00:09:26 matt Exp $
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


# note - no 'general' summary for groups, as its keyed on group_id
DROP TABLE IF EXISTS nt_group_summary;
CREATE TABLE nt_group_summary(
    sid                 INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_group_id         SMALLINT UNSIGNED NOT NULL,
    period              INT UNSIGNED NOT NULL,
    children            INT UNSIGNED,
    additions           INT UNSIGNED,
    modifications       INT UNSIGNED,
    deletions           INT UNSIGNED,
    child_additions     INT UNSIGNED,
    child_modifications INT UNSIGNED,
    child_deletions     INT UNSIGNED
);

DROP TABLE IF EXISTS nt_group_current_summary;
CREATE TABLE nt_group_current_summary(
    nt_group_id         SMALLINT UNSIGNED NOT NULL PRIMARY KEY,
    period              INT UNSIGNED NOT NULL,
    children            INT UNSIGNED,
    additions           INT UNSIGNED,
    modifications       INT UNSIGNED,
    deletions           INT UNSIGNED,
    child_additions     INT UNSIGNED,
    child_modifications INT UNSIGNED,
    child_deletions     INT UNSIGNED
);

DROP TABLE IF EXISTS nt_nameserver_general_summary; 
CREATE TABLE nt_nameserver_general_summary(
    sid                 INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_group_id         INT UNSIGNED NOT NULL,
    period              INT UNSIGNED NOT NULL,
    nameservers         INT UNSIGNED,
    children            INT UNSIGNED,
    additions           INT UNSIGNED,
    modifications       INT UNSIGNED,
    deletions           INT UNSIGNED,
    child_additions     INT UNSIGNED,
    child_modifications INT UNSIGNED,
    child_deletions     INT UNSIGNED,
    queries_nozone      INT UNSIGNED,
    queries_norecord     INT UNSIGNED,
    queries_successful  INT UNSIGNED,
    child_queries_nozone     INT UNSIGNED,
    child_queries_norecord   INT UNSIGNED,
    child_queries_successful INT UNSIGNED,
    total_zones             INT UNSIGNED,
    total_records           INT UNSIGNED,
    child_total_zones       INT UNSIGNED,
    child_total_records     INT UNSIGNED
);

DROP TABLE IF EXISTS nt_nameserver_summary;
CREATE TABLE nt_nameserver_summary(
    sid                 INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    period              INT UNSIGNED NOT NULL,
    nt_nameserver_id    SMALLINT UNSIGNED NOT NULL,
    queries_nozone      INT UNSIGNED,
    queries_norecord    INT UNSIGNED,
    queries_successful  INT UNSIGNED,
    total_zones         INT UNSIGNED,
    total_records       INT UNSIGNED
);

DROP TABLE IF EXISTS nt_nameserver_current_summary;
CREATE TABLE nt_nameserver_current_summary(
    nt_nameserver_id    SMALLINT UNSIGNED UNIQUE NOT NULL PRIMARY KEY,
    period              INT UNSIGNED NOT NULL,
    queries_nozone      INT UNSIGNED,
    queries_norecord    INT UNSIGNED,
    queries_successful  INT UNSIGNED,
    total_zones         INT UNSIGNED,
    total_records       INT UNSIGNED
);


DROP TABLE IF EXISTS nt_user_general_summary;
CREATE TABLE nt_user_general_summary(
    sid                    INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_group_id            INT UNSIGNED NOT NULL,
    period                 INT UNSIGNED NOT NULL,
    users                  INT UNSIGNED,
    children               INT UNSIGNED,
    additions              INT UNSIGNED,
    modifications          INT UNSIGNED,
    deletions              INT UNSIGNED,
    logins                 INT UNSIGNED,
    logouts                INT UNSIGNED,
    timeouts               INT UNSIGNED,
    child_logins           INT UNSIGNED,
    child_logouts          INT UNSIGNED,
    child_timeouts         INT UNSIGNED,
    child_additions        INT UNSIGNED,
    child_modifications    INT UNSIGNED,
    child_deletions        INT UNSIGNED
);

DROP TABLE IF EXISTS nt_user_summary;
CREATE TABLE nt_user_summary(
    sid                 INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    period              INT UNSIGNED NOT NULL,
    nt_user_id          INT UNSIGNED NOT NULL,
    logins              INT UNSIGNED,
    logouts             INT UNSIGNED,
    timeouts            INT UNSIGNED
);

DROP TABLE IF EXISTS nt_user_current_summary;
CREATE TABLE nt_user_current_summary(
    nt_user_id          INT UNSIGNED UNIQUE NOT NULL PRIMARY KEY,
    period              INT UNSIGNED NOT NULL,
    logins              INT UNSIGNED,
    logouts             INT UNSIGNED,
    timeouts            INT UNSIGNED
);


DROP TABLE IF EXISTS nt_zone_general_summary;
CREATE TABLE nt_zone_general_summary(
    sid                             INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_group_id                     INT UNSIGNED NOT NULL,
    period                          INT UNSIGNED NOT NULL,
    zones                           INT UNSIGNED,
    children                        INT UNSIGNED,
    additions                       INT UNSIGNED,
    modifications                   INT UNSIGNED,
    deletions                       INT UNSIGNED,
    child_additions                 INT UNSIGNED,
    child_modifications             INT UNSIGNED,
    child_deletions                 INT UNSIGNED,
    zone_records                    INT UNSIGNED,
    zone_record_modifications       INT UNSIGNED,
    zone_record_additions           INT UNSIGNED,
    zone_record_deletions           INT UNSIGNED,
    child_zone_records              INT UNSIGNED,
    child_zone_record_modifications INT UNSIGNED,
    child_zone_record_additions     INT UNSIGNED,
    child_zone_record_deletions     INT UNSIGNED,
    queries_norecord                INT UNSIGNED,
    queries_successful              INT UNSIGNED,
    child_queries_norecord          INT UNSIGNED,
    child_queries_successful        INT UNSIGNED
);

DROP TABLE IF EXISTS nt_zone_summary;
CREATE TABLE nt_zone_summary(
    sid                             INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    period                          INT UNSIGNED NOT NULL,
    nt_zone_id                      INT UNSIGNED NOT NULL,
    queries_norecord                INT UNSIGNED,
    queries_successful              INT UNSIGNED,
    zone_records                    INT UNSIGNED,
    zone_record_modifications       INT UNSIGNED,
    zone_record_additions           INT UNSIGNED,
    zone_record_deletions           INT UNSIGNED,
    ns0_queries_norecord            INT UNSIGNED,
    ns0_queries_successful          INT UNSIGNED,
    ns1_queries_norecord            INT UNSIGNED,
    ns1_queries_successful          INT UNSIGNED,
    ns2_queries_norecord            INT UNSIGNED,
    ns2_queries_successful          INT UNSIGNED,
    ns3_queries_norecord            INT UNSIGNED,
    ns3_queries_successful          INT UNSIGNED,
    ns4_queries_norecord            INT UNSIGNED,
    ns4_queries_successful          INT UNSIGNED,
    ns5_queries_norecord            INT UNSIGNED,
    ns5_queries_successful          INT UNSIGNED,
    ns6_queries_norecord            INT UNSIGNED,
    ns6_queries_successful          INT UNSIGNED,
    ns7_queries_norecord            INT UNSIGNED,
    ns7_queries_successful          INT UNSIGNED,
    ns8_queries_norecord            INT UNSIGNED,
    ns8_queries_successful          INT UNSIGNED,
    ns9_queries_norecord            INT UNSIGNED,
    ns9_queries_successful          INT UNSIGNED
);

# TODO - this nsX_queries stuff is gross

DROP TABLE IF EXISTS nt_zone_current_summary;
CREATE TABLE nt_zone_current_summary(
    nt_zone_id                      INT UNSIGNED NOT NULL UNIQUE PRIMARY KEY,
    period                          INT UNSIGNED NOT NULL,
    queries_norecord                INT UNSIGNED,
    queries_successful              INT UNSIGNED,
    zone_records                    INT UNSIGNED,
    zone_record_modifications       INT UNSIGNED,
    zone_record_additions           INT UNSIGNED,
    zone_record_deletions           INT UNSIGNED,
    ns0_queries_norecord            INT UNSIGNED,
    ns0_queries_successful          INT UNSIGNED,
    ns1_queries_norecord            INT UNSIGNED,
    ns1_queries_successful          INT UNSIGNED,
    ns2_queries_norecord            INT UNSIGNED,
    ns2_queries_successful          INT UNSIGNED,
    ns3_queries_norecord            INT UNSIGNED,
    ns3_queries_successful          INT UNSIGNED,
    ns4_queries_norecord            INT UNSIGNED,
    ns4_queries_successful          INT UNSIGNED,
    ns5_queries_norecord            INT UNSIGNED,
    ns5_queries_successful          INT UNSIGNED,
    ns6_queries_norecord            INT UNSIGNED,
    ns6_queries_successful          INT UNSIGNED,
    ns7_queries_norecord            INT UNSIGNED,
    ns7_queries_successful          INT UNSIGNED,
    ns8_queries_norecord            INT UNSIGNED,
    ns8_queries_successful          INT UNSIGNED,
    ns9_queries_norecord            INT UNSIGNED,
    ns9_queries_successful          INT UNSIGNED
);

DROP TABLE IF EXISTS nt_zone_record_summary;
CREATE TABLE nt_zone_record_summary(
    sid                             INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    period                          INT UNSIGNED NOT NULL,
    nt_zone_record_id               INT UNSIGNED NOT NULL,
    queries                         INT UNSIGNED
);

DROP TABLE IF EXISTS nt_zone_record_current_summary;
CREATE TABLE nt_zone_record_current_summary(
    nt_zone_record_id               INT UNSIGNED NOT NULL UNIQUE PRIMARY KEY,
    period                          INT UNSIGNED NOT NULL,
    queries                         INT UNSIGNED
);
