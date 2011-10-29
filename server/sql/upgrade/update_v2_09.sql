

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

DROP TABLE IF EXISTS nt_zone_ns_log;
