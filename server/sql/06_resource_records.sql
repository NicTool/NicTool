
DROP TABLE IF EXISTS resource_record_type;
CREATE TABLE resource_record_type (
    id              smallint(2) unsigned NOT NULL AUTO_INCREMENT,
    name            varchar(10) NOT NULL,
    description     varchar(55) NULL DEFAULT NULL,
    reverse         tinyint(1) UNSIGNED NOT NULL DEFAULT 1,
    forward         tinyint(1) UNSIGNED NOT NULL DEFAULT 1,
PRIMARY KEY (`id`),
UNIQUE `name` (`name`)
) DEFAULT CHARSET=utf8;

INSERT INTO `resource_record_type` VALUES (2,'NS','Name Server',1,1),(5,'CNAME','Canonical Name',1,1),(6,'SOA',NULL,0,0),(12,'PTR','Pointer',1,0),(15,'MX','Mail Exchanger',0,1),(28,'AAAA','Address IPv6',0,1),(33,'SRV','Service',0,1),(99,'SPF','Sender Policy Framework',0,1),(252,'AXFR',NULL,0,1),(1,'A','Address',0,1),(16,'TXT','Text',1,1),(48,'DNSKEY',NULL,0,1),(43,'DS',NULL,0,1),(25,'KEY',NULL,0,1),(29,'LOC','Location',0,0);


