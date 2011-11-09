
ALTER TABLE nt_zone ADD column `last_modified` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `deleted`;
ALTER TABLE `nt_nameserver` DROP column `service_type`;
ALTER TABLE `nt_nameserver_export_log` ADD `result_id` int NULL DEFAULT NULL  AFTER `date_finish`;
ALTER TABLE `nt_nameserver_export_log` ADD `message` varchar(256) NULL DEFAULT NULL  AFTER `result_id`;
ALTER TABLE `nt_nameserver_export_log` ADD `success` tinyint(3) UNSIGNED NULL DEFAULT NULL  AFTER `message`;
ALTER TABLE `nt_nameserver_export_log` ADD `partial` tinyint(3) UNSIGNED NOT NULL DEFAULT '0'  AFTER `success`;
ALTER TABLE `nt_nameserver_export_log` CHANGE `date_start` `date_start` timestamp(10) NULL DEFAULT NULL;
ALTER TABLE `nt_nameserver_export_log` CHANGE `date_finish` `date_end` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP  on update CURRENT_TIMESTAMP;


/* Convert all character encodings to UTF8 bin. */
ALTER TABLE `nt_delegate` CHARACTER SET = utf8;
ALTER TABLE `nt_delegate` COLLATE = utf8_bin;

ALTER TABLE `nt_delegate_log` CHARACTER SET = utf8;
ALTER TABLE `nt_delegate_log` COLLATE = utf8_bin;

ALTER TABLE `nt_group` CHARACTER SET = utf8;
ALTER TABLE `nt_group` COLLATE = utf8_bin;

ALTER TABLE `nt_group_log` CHARACTER SET = utf8;
ALTER TABLE `nt_group_log` COLLATE = utf8_bin;

ALTER TABLE `nt_group_subgroups` CHARACTER SET = utf8;
ALTER TABLE `nt_group_subgroups` COLLATE = utf8_bin;

ALTER TABLE `nt_nameserver` CHARACTER SET = utf8;
ALTER TABLE `nt_nameserver` COLLATE = utf8_bin;

ALTER TABLE `nt_nameserver_log` CHARACTER SET = utf8;
ALTER TABLE `nt_nameserver_log` COLLATE = utf8_bin;

ALTER TABLE `nt_nameserver_export_log` CHARACTER SET = utf8;
ALTER TABLE `nt_nameserver_export_log` COLLATE = utf8_bin;

ALTER TABLE `nt_nameserver_qlog` CHARACTER SET = utf8;
ALTER TABLE `nt_nameserver_qlog` COLLATE = utf8_bin;

ALTER TABLE `nt_nameserver_qlogfile` CHARACTER SET = utf8;
ALTER TABLE `nt_nameserver_qlogfile` COLLATE = utf8_bin;

ALTER TABLE `nt_options` CHARACTER SET = utf8;
ALTER TABLE `nt_options` COLLATE = utf8_bin;

ALTER TABLE `nt_perm` CHARACTER SET = utf8;
ALTER TABLE `nt_perm` COLLATE = utf8_bin;

ALTER TABLE `nt_user` CHARACTER SET = utf8;
ALTER TABLE `nt_user` COLLATE = utf8_bin;

ALTER TABLE `nt_user_log` CHARACTER SET = utf8;
ALTER TABLE `nt_user_log` COLLATE = utf8_bin;

ALTER TABLE `nt_user_global_log` CHARACTER SET = utf8;
ALTER TABLE `nt_user_global_log` COLLATE = utf8_bin;

ALTER TABLE `nt_user_session` CHARACTER SET = utf8;
ALTER TABLE `nt_user_session` COLLATE = utf8_bin;

ALTER TABLE `nt_user_session_log` CHARACTER SET = utf8;
ALTER TABLE `nt_user_session_log` COLLATE = utf8_bin;

ALTER TABLE `nt_zone` CHARACTER SET = utf8;
ALTER TABLE `nt_zone` COLLATE = utf8_bin;

ALTER TABLE `nt_zone_log` CHARACTER SET = utf8;
ALTER TABLE `nt_zone_log` COLLATE = utf8_bin;

ALTER TABLE `nt_zone_record` CHARACTER SET = utf8;
ALTER TABLE `nt_zone_record` COLLATE = utf8_bin;

ALTER TABLE `nt_zone_record_log` CHARACTER SET = utf8;
ALTER TABLE `nt_zone_record_log` COLLATE = utf8_bin;

UPDATE nt_options SET option_value='2.10' WHERE option_name='db_version';

/* 
CREATE TABLE `nt_nameserver_export_result` (id INT(10) UNSIGNED NOT NULL AUTO_INCREMENT, PRIMARY KEY (`id`) ) DEFAULT CHARACTER SET `utf8`; */


/* Converting to InnoDB brings us foreign key constraints. It's also the
** default database format in mysql 5.5. */

/*
ALTER TABLE `nt_delegate` TYPE = InnoDB;
ALTER TABLE `nt_delegate_log` TYPE = InnoDB;
ALTER TABLE `nt_group` TYPE = InnoDB;
ALTER TABLE `nt_group_log` TYPE = InnoDB;
ALTER TABLE `nt_group_subgroups` TYPE = InnoDB;
ALTER TABLE `nt_nameserver` TYPE = InnoDB;
ALTER TABLE `nt_nameserver_log` TYPE = InnoDB;
ALTER TABLE `nt_nameserver_export_log` TYPE = InnoDB;
ALTER TABLE `nt_nameserver_qlog` TYPE = InnoDB;
ALTER TABLE `nt_nameserver_qlogfile` TYPE = InnoDB;
ALTER TABLE `nt_options` TYPE = InnoDB;
ALTER TABLE `nt_perm` TYPE = InnoDB;
ALTER TABLE `nt_user` TYPE = InnoDB;
ALTER TABLE `nt_user_log` TYPE = InnoDB;
ALTER TABLE `nt_user_global_log` TYPE = InnoDB;
ALTER TABLE `nt_user_session` TYPE = InnoDB;
ALTER TABLE `nt_user_session_log` TYPE = InnoDB;
ALTER TABLE `nt_zone` TYPE = InnoDB;
ALTER TABLE `nt_zone_log` TYPE = InnoDB;
ALTER TABLE `nt_zone_record` TYPE = InnoDB;
ALTER TABLE `nt_zone_record_log` TYPE = InnoDB;
*/

/* these constraints aren't enforced, but it may prove beneficial to 
   in the future. Lets see how many blow up. */

/*
ALTER TABLE `nt_nameserver_export_log` ADD FOREIGN KEY (`result_id`) REFERENCES `nt_nameserver_export_result` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION;
ALTER TABLE `nt_zone_log` ADD FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_log` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_log` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_record` ADD FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_record_log` ADD FOREIGN KEY (`nt_zone_id`) REFERENCES `nt_zone` (`nt_zone_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_record_log` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_zone_record_log` ADD FOREIGN KEY (`nt_zone_record_id`) REFERENCES `nt_zone_record` (`nt_zone_record_id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `nt_user_session_log` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_user_session_log` ADD FOREIGN KEY (`nt_user_session_id`) REFERENCES `nt_user_session` (`nt_user_session_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_user_session` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_user_global_log` ADD FOREIGN KEY (`nt_user_id`) REFERENCES `nt_user` (`nt_user_id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `nt_nameserver_export_log` ADD FOREIGN KEY (`result_id`) REFERENCES `nt_nameserver_export_result` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION;
ALTER TABLE `nt_nameserver` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `nt_group_subgroups` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `nt_group_log` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `nt_delegate` ADD FOREIGN KEY (`nt_group_id`) REFERENCES `nt_group` (`nt_group_id`) ON DELETE CASCADE ON UPDATE CASCADE;

*/
