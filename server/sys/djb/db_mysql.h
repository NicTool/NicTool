/*
 *
 * $Id: db_mysql.h 615 2008-07-01 15:28:56Z rob@bsdfreaks.nl $
 *
 * NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
 * NicTool v2.01 Copyright 2004 The Network People, Inc.
 *
 * NicTool is free software; you can redistribute it and/or modify it under
 * the terms of the Affero General Public License as published by Affero, 
 * Inc.; either version 1 of the License, or any later version.
 *
 * NicTool is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
 * or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
 *
 * You should have received a copy of the Affero General Public License
 * along with this program; if not, write to Affero Inc., 521 Third St,
 * Suite 225, San Francisco, CA 94107, USA
 *
 */

#include "nt_export_db.h"


#define NS_QUERY        "SELECT nt_nameserver_id, name, ttl FROM nt_nameserver where deleted!='1'"

#define ZONE_QUERY_FORMAT "SELECT z.nt_zone_id,z.zone,z.mailaddr,z.serial,z.refresh,z.retry,z.expire,z.minimum,z.ttl,z.ns0,z.ns1,z.ns2,z.ns3,z.ns4,z.ns5,z.ns6,z.ns7,z.ns8,z.ns9,r.nt_zone_record_id,r.name,r.ttl,r.type,r.address,r.weight,r.priority,r.other FROM nt_zone z,nt_zone_record r WHERE z.nt_zone_id = r.nt_zone_id AND (ns0 = %1$s OR ns1 = %1$s OR ns2 = %1$s OR ns3 = %1$s OR ns4 = %1$s OR ns5 = %1$s OR ns6 = %1$s OR ns7 = %1$s OR ns8 = %1$s OR ns9 = %1$s) AND (z.deleted !='1') AND (r.deleted != '1')"


// for simple 'keyed' access to rows returned from the above query
#define ZONE_ID 0
#define ZONE 1
#define MAILADDR 2
#define SERIAL 3
#define REFRESH 4
#define RETRY 5
#define EXPIRE 6
#define MINIMUM 7
#define TTL 8
#define NS0 9
#define NS1 10
#define NS2 11
#define NS3 12
#define NS4 13
#define NS5 14
#define NS6 15
#define NS7 16
#define NS8 17
#define NS9 18
#define ZR_ID 19
#define ZR_NAME 20
#define ZR_TTL 21
#define ZR_TYPE 22
#define ZR_ADDRESS 23
#define ZR_WEIGHT 24
#define ZR_PRIORITY 25
#define ZR_OTHER 26

int db_mysql_init(void);
int db_mysql_build_nameservers(void);
int db_mysql_do_zone_query( char *ns_id);
int db_mysql_dump_zones(int, int);
int db_mysql_cleanup(void);

int db_mysql_print_error(const char *message);
