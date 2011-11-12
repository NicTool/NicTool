
DROP TABLE IF EXISTS `resource_record_type`;
CREATE TABLE `resource_record_type` (
  `id` smallint(2) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(5) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;


INSERT INTO `resource_record_type` VALUES (2,'NS'),(5,'CNAME'),(6,'SOA'),(12,'PTR'),(15,'MX'),(28,'AAAA'),(33,'SRV'),(99,'SPF'),(252,'AXFR'),(1,'A'),(16,'TXT');

