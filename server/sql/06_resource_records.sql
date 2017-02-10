
DROP TABLE IF EXISTS resource_record_type;
CREATE TABLE resource_record_type (
    id              smallint(2) unsigned NOT NULL,
    name            varchar(10) NOT NULL,
    description     varchar(55) NULL DEFAULT NULL,
    reverse         tinyint(1) UNSIGNED NOT NULL DEFAULT 1,
    forward         tinyint(1) UNSIGNED NOT NULL DEFAULT 1,
    obsolete        tinyint(1) NOT NULL DEFAULT '0',
    PRIMARY KEY (`id`),
    UNIQUE `name` (`name`)
) DEFAULT CHARSET=utf8;

INSERT INTO `resource_record_type` (`id`, `name`, `description`, `reverse`, `forward`, `obsolete`)
VALUES
    (1,'A','Address',0,1,0),
    (2,'NS','Name Server',1,1,0),
    (5,'CNAME','Canonical Name',1,1,0),
    (6,'SOA','Start Of Authority',0,0,0),
    (12,'PTR','Pointer',1,0,0),
    (13,'HINFO','Host Info',0,0,1),
    (15,'MX','Mail Exchanger',0,1,0),
    (16,'TXT','Text',1,1,0),
    (24,'SIG','Signature',0,0,0),
    (25,'KEY','Key',0,0,0),
    (28,'AAAA','Address IPv6',0,1,0),
    (29,'LOC','Location',0,1,0),
    (30,'NXT','Next',0,0,1),
    (33,'SRV','Service',0,1,0),
    (35,'NAPTR','Naming Authority Pointer',1,1,0),
    (39,'DNAME','Delegation Name',0,0,0),
    (43,'DS','Delegation Signer',1,1,0),
    (44,'SSHFP','Secure Shell Key Fingerprints',0,1,0),
    (46,'RRSIG','Resource Record Signature',0,1,0),
    (47,'NSEC','Next Secure',0,1,0),
    (48,'DNSKEY','DNS Public Key',0,1,0),
    (50,'NSEC3','Next Secure v3',0,0,0),
    (51,'NSEC3PARAM','NSEC3 Parameters',0,0,0),
    (99,'SPF','Sender Policy Framework',0,1,0),
    (250,'TSIG','Transaction Signature',0,0,0),
    (252,'AXFR',NULL,0,0,0);
