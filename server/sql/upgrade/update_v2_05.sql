
ALTER TABLE nt_zone_record     MODIFY type enum('A','AAAA','MX','PTR','NS','TXT','CNAME','SRV');
ALTER TABLE nt_zone_record     ADD priority SMALLINT UNSIGNED DEFAULT 0 AFTER weight;
ALTER TABLE nt_zone_record     ADD other    SMALLINT UNSIGNED DEFAULT 0 AFTER priority;

ALTER TABLE nt_zone_record_log MODIFY type enum('A','AAAA','MX','PTR','NS','TXT','CNAME','SRV');
ALTER TABLE nt_zone_record_log ADD priority SMALLINT UNSIGNED DEFAULT 0 AFTER weight;
ALTER TABLE nt_zone_record_log ADD other    SMALLINT UNSIGNED DEFAULT 0 AFTER priority;

