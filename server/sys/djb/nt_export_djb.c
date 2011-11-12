/* vim:set ts=4 sts=4 sw=4:
 *
 * NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
 * NicTool v2.01 Copyright 2004 The Network People, Inc.
 
 * NicTool is free software; you can redistribute it and/or modify it under
 * the terms of the Affero General Public License as published by Affero, 
 * Inc.; either version 1 of the License, or any later version.
 
 * NicTool is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
 * or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
 
 * You should have received a copy of the Affero General Public License
 * along with this program; if not, write to Affero Inc., 521 Third St,
 * Suite 225, San Francisco, CA 94107, USA
 *
 */

/* nt_export_djb.c - export data from NicTool DB into tinydns-data readable form */

#include <stdio.h>
#include <stdlib.h>
#include <mysql.h>
#include <string.h>
#include <sys/time.h>
#include "nt_export_db.h"

int main(int argc, char *argv[])
{
	char *ns_id;
    //char *conf_file;
    float qtime;
    float dtime;
    struct timeval tstart;
    struct timeval now;
	int append_db_ids = 0;
	int print_serials = 0;

	if (argc != 2) {
		printf("usage: %s [nt_nameserver_id]\n", argv[0]);
		exit(111);
    }
    
    ns_id = argv[1];

	if(getenv("NT_DB_HOST_NAME")==NULL){
		fprintf(stderr,"NT_DB_HOST_NAME not set\n");
		exit(2);
	} 

	if(getenv("NT_DB_HOST_PORT")==NULL){
		fprintf(stderr,"NT_DB_HOST_PORT not set\n");
		exit(2);
	} 

	if(getenv("NT_DB_USER_NAME")==NULL){
		fprintf(stderr,"NT_DB_USER_NAME not set\n");
		exit(2);
	}

	if(getenv("NT_DB_PASSWORD")==NULL){
		fprintf(stderr,"NT_DB_PASSWORD not set\n");
		exit(2);
	}

	if(getenv("NT_DB_NAME")==NULL){
		fprintf(stderr,"NT_DB_NAME not set\n");
		exit(2);
	}

	if(getenv("NT_DB_TYPE")==NULL){
		fprintf(stderr,"NT_DB_TYPE not set\n");
		exit(2);	
	}

	if (getenv("NT_APPEND_DB_IDS"))
		append_db_ids = 1;

	if (getenv("NT_PRINT_SERIALS"))
		print_serials = 1;

	if(nt_export_db_init() < 0) {/* initialize db access module */
		fprintf(stderr,"Error initializing database module\n");
		exit(2);	
    }
    
    gettimeofday(&tstart, NULL);

    /* init db stuff */
	if (db_init() < 0) {
		db_cleanup();
		exit(2);
    }

    /* build nameserver list */
	if (db_build_nameservers() < 0) {
		db_cleanup();
		exit(2);
	}

    /* zone query */
	if (db_do_zone_query(ns_id) < 0) {
		fprintf(stderr, "db_do_zone_query() failed");
		db_cleanup();
		exit(2);
    }

    gettimeofday(&now, NULL);
    qtime = (now.tv_usec / 1e6 - tstart.tv_usec / 1e6)
	+ (float) (now.tv_sec - tstart.tv_sec);
    
    /* dump zones */
    
    gettimeofday(&tstart, NULL);
    if(db_dump_zones(append_db_ids, print_serials) < 0){
		db_cleanup();
		exit(2);	
    }
    gettimeofday(&now, NULL);
    
    dtime = (now.tv_usec / 1e6 - tstart.tv_usec / 1e6) 
	+ (float) (now.tv_sec - tstart.tv_sec);
    
    db_cleanup();

    /* printf("%.3f %.3f\n", qtime, dtime); */

    exit(0);
}
