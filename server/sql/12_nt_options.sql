
DROP TABLE IF EXISTS nt_options;
CREATE TABLE nt_options (
  option_id int(11) unsigned NOT NULL auto_increment,
  option_name varchar(64) NOT NULL default '',
  option_value text NOT NULL,
  PRIMARY KEY  (`option_id`),
  UNIQUE KEY `option_name` (`option_name`)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

INSERT INTO `nt_options`
VALUES (1,'db_version','2.27'),
       (2,'session_timeout','45'),
       (3,'default_group','NicTool')
       ;
