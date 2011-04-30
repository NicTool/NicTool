/*
 *
 * $Id: db_mysql.cc 696 2008-10-16 09:11:36Z rob@bsdfreaks.nl $
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

#include <stdio.h>
#include <stdlib.h>
#include <iostream>
using namespace std;
#include <fstream>
#include <mysql.h>
#include <string.h>
#include <string>
#ifdef __GNUC__
#include <ext/hash_map>
#else
#include <hash_map>
#endif
#include "db_mysql.h"
extern "C" {
#include "fmt.h"
#include "ip6.h"
}

namespace std
{
     using namespace __gnu_cxx;
}

int _db_mysql_store_query(MYSQL * conn, const char *query);


MYSQL *conn;
MYSQL_RES *res_set;

std::hash_map<int, bool> seen_zone;

char targetip6[16];
char ip6str[IP6_FMT];

class ns_t {
	public:
    string name;
    unsigned int ttl;
    ns_t( char * namei, unsigned int ttli): name(namei), ttl(ttli){

    }
    ns_t( const ns_t &t): name(t.name),ttl(t.ttl){
    }
    ns_t(){

    }
};

//struct ns_t *nameserver;
std::hash_map<int, ns_t  > nameserver;



int _db_mysql_build_nameservers(MYSQL * conn)
{
    MYSQL_ROW row;
    //MYSQL_RES *ns_res_set;
    unsigned int ns_id;
    //i;
    if (_db_mysql_store_query(conn, NS_QUERY) < 0) {
	return -1;
    } else {
	while ((row = mysql_fetch_row(res_set)) != NULL) {
	    ns_id = (unsigned int) atoi(row[0]);
	    nameserver[ns_id]=ns_t(row[1],(unsigned int) atoi(row[2]));
	}
	mysql_free_result(res_set);
    }
    return 1;
}

int _db_mysql_store_query(MYSQL * conn, const char *query)
{

    /*printf("query: %s\n", query); */
    if (mysql_query(conn, query) != 0) {
    const char* err;
    err = "_db_mysql_store_query: Query failed";
	db_mysql_print_error(err);
	return -1;
    } else {

	if ((res_set = mysql_store_result(conn)) == NULL) {
	    db_mysql_print_error
		("_db_mysql_store_query: Store result failed");
	    return -1;
	} else {
	    return 1;
	}
    }
}

int _db_mysql_use_query(MYSQL * conn, char *query, MYSQL_RES * ns_res_set)
{

    if (mysql_query(conn, query) != 0) {
	db_mysql_print_error("_db_mysql_use_query: Query failed");
	return -1;
    } else {
	if ((ns_res_set = mysql_store_result(conn)) == NULL) {
	    db_mysql_print_error
		("_db_mysql_use_query: Store result failed");
	    return -2;
	} else
	    return 1;
    }
}

int _db_mysql_dump_zones(MYSQL * conn, MYSQL_RES * res_set, int append_db_ids, int print_serials)
{
    MYSQL_ROW row;
    unsigned int i, zone_id;
    ofstream fp("data",ios::trunc);
    
	if (!fp.is_open()) {
		cerr<<"Can't open data"<<endl;
		return -1;
    }

    string rec;
    string address;
    string ipv6address;
    //const char* null;
    string null = "";

	while ((row = mysql_fetch_row(res_set)) != NULL) 
	{
		rec="";
		address="";

		zone_id = (unsigned int) atoi(row[ZONE_ID]);

		if (!seen_zone[zone_id] ) {
			unsigned int zns;

			seen_zone[zone_id] = true;
			for (i = 0; i < 10; i++)
				if (row[i] == NULL)
					strcpy(row[i], null.c_str());

			zns = (unsigned int) atoi(row[NS0]);

			if (nameserver.find(zns)==nameserver.end()) {
				/* zns is not a valid entry */
				continue;
			} 

			fp << "Z" <<
				row[ZONE] << ":" <<
				nameserver[zns].name << ":" <<
				row[MAILADDR] << ":";

			if (print_serials) 
				fp << row[SERIAL];
			else 
				fp << "";

			fp << ":" <<
				row[REFRESH] << ":" <<
				row[RETRY] << ":" <<
				row[EXPIRE] << ":" <<
				row[MINIMUM] << ":" <<
				row[TTL] << "::";

			if (append_db_ids) 
				fp << ":" << row[ZONE_ID];

			fp << endl;
			// Z fqdn : mname : rname : ser : ref : ret : exp : min : ttl : timestamp : lo


			for (i = 9; i < 19; i++) { // NS0 to NS9
				if (row[i] == NULL)
					continue;
				if (atoi(row[i]) > 0) {
					if (nameserver.find(atoi(row[i]))==nameserver.end())
						continue;

					fp << "&" << 
						row[ZONE] << "::" <<
						nameserver[atoi(row[i])].name << ":" <<
						nameserver[atoi(row[i])].ttl << "::";

					if (append_db_ids)
						fp << ":" << row[ZONE_ID] << "-" << row[i];

					fp << endl;
				}
			}

		} // end of soa/ns record printing

		// if record not absolute, append zone 
		rec += row[ZR_NAME];
		if (row[ZR_NAME][strlen(row[ZR_NAME]) - 1] != '.') {
			rec += ".";
			rec += row[ZONE];
		}
		address += row[ZR_ADDRESS];
		if(row[ZR_ADDRESS][strlen(row[ZR_ADDRESS]) - 1] != '.') {
			address += ".";
			address += row[ZONE];
		}

		// print record
		if (strcmp(row[ZR_TYPE], "A") == 0) 
			fp << "+" << rec << ":" << row[ZR_ADDRESS] << ":" << row[ZR_TTL] << "::";
			// + fqdn : ip : ttl : timestamp : lo
  	 	else if (strcmp(row[ZR_TYPE], "AAAA") == 0){
 			const char * argv = row[ZR_ADDRESS];
 			ip6_scan(argv,targetip6);
 			ip6_fmt_flat(ip6str,targetip6);
 			fp << "3" << rec << ":" << ip6str << ":" << row[ZR_TTL] << "::";
  			// 3 fqdn : ip : ttl : timestamp : lo
 		}
		else if (strcmp(row[ZR_TYPE], "MX") == 0)
			/* fp << "@" << rec << "::" << row[ZR_ADDRESS] << ":" << row[ZR_WEIGHT] << ":" << row[ZR_TTL] << "::";  */
			fp << "@" << rec << "::" << address << ":" << row[ZR_WEIGHT] << ":" << row[ZR_TTL] << "::";
			// @ fqdn : ip : x : dist : ttl : timestamp : lo
		else if (strcmp(row[ZR_TYPE], "CNAME") == 0)
			fp << "C" << rec << ":" << row[ZR_ADDRESS] << ":" << row[ZR_TTL] << "::";
			// C fqdn : p : ttl : timestamp : lo
		else if (strcmp(row[ZR_TYPE], "PTR") == 0) 
			fp << "^" << rec << ":" << row[ZR_ADDRESS] << ":" << row[ZR_TTL] << "::";
			// ^ fqdn : p : ttl : timestamp : lo
        else if (strcmp(row[ZR_TYPE], "TXT") == 0) 
            fp << "'" << rec << ":" << row[ZR_ADDRESS] << ":" << row[ZR_TTL] << "::";
            // ' fqdn : p : ttl : timestamp : lo
		else if (strcmp(row[ZR_TYPE], "NS") == 0)
			/* fp << "&" << rec << "::" << row[ZR_ADDRESS] << ":" << row[ZR_TTL] << "::"; */
			   fp << "&" << rec << "::" << address         << ":" << row[ZR_TTL] << "::";
			// & fqdn : ip : x : ttl : timestamp : lo
		else if (strcmp(row[ZR_TYPE], "SRV") == 0)
			fp << "S" << rec << "::" << address << ":" << row[ZR_OTHER] << ":" << row[ZR_WEIGHT] << ":" << row[ZR_PRIORITY] << ":" << row[ZR_TTL] << "::";
			// S fqdn : ip : x : port : weight : priority : ttl : timestamp
			// format based upon Michael Handler's SRV patch to djbdns


		if (append_db_ids)
			fp << ":" << row[ZR_ID];

		fp << endl;

    } // end main while loop

	fp.flush();
	fp.close();

	if (mysql_errno(conn) != 0) {
		db_mysql_print_error("_db_mysql_dump_zones: Fetch row failed");
		return -1;
    }

    return 1;
}

char *_db_mysql_make_zone_query(char *ns_id)
{
    /*build up zone query string
       length is ZONE_QUERY_FORMAT length minus formatting chars
       plus ns_id length times 10
     */
    int qlen = strlen(ZONE_QUERY_FORMAT)
	- 10 * 4 + 10 * strlen(ns_id);
    char *str_build = new char[qlen + 1];
    sprintf(str_build, ZONE_QUERY_FORMAT, ns_id);
    return str_build;
}

int db_mysql_print_error(const char *message)
{
    char out[512];
    if (conn != NULL && mysql_errno(conn)!=0) {
	sprintf(out, "%s: MYSQL(%u): %s", message, mysql_errno(conn),
		mysql_error(conn));
    	nt_export_db_print_error(out);
    } else {
	nt_export_db_print_error(message);
    }
    return 1;
}

int db_mysql_init(void)
{
    int  port_number;
	port_number = (int) atoi( getenv("NT_DB_HOST_PORT") );
    conn = mysql_init(NULL);
    if (conn == NULL) {
		fprintf(stderr, "db_mysql_init: Insufficient memory\n");
		return -1;
    }
    if(mysql_real_connect(conn, 
			    getenv("NT_DB_HOST_NAME"),
			    getenv("NT_DB_USER_NAME"),
			    getenv("NT_DB_PASSWORD"), 
			    getenv("NT_DB_NAME"),
			    port_number,NULL,
			    0) == NULL){
	db_mysql_print_error("db_mysql_init: Database connection failed");
	return -1;
    }
    /* fprintf(stdout, "1 connect\n");*/
    return 1;
}

int db_mysql_build_nameservers(void)
{
    return _db_mysql_build_nameservers(conn);
}

int db_mysql_do_zone_query(char *ns_id)
{
    int r;
    char *zone_query = _db_mysql_make_zone_query(ns_id);
    if(zone_query==NULL){
	nt_export_db_print_error("db_mysql_do_zone_query: Insufficient memory");
	return -1;
    }
    r = mysql_query(conn, zone_query);
    delete[]zone_query;
    return r;
}

int db_mysql_dump_zones(int append_db_ids, int print_serials)
{
    res_set = mysql_use_result(conn);
    if (res_set == NULL) {
	db_mysql_print_error("db_mysql_dump_zones: Use result failed");
	return -1;
    }
    int i = _db_mysql_dump_zones(conn, res_set, append_db_ids, print_serials);
    return i;
}

int db_mysql_cleanup(void)
{
    mysql_close(conn);
    /* fprintf(stdout,"1 close\n"); */
    return 1;
}
