/*
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "nt_export_db.h"
#include "db_mysql.h"


int (*_db_init)(void);
int (*_db_build_nameservers)(void);
int (*_db_do_zone_query)(char *ns_id);
int (*_db_dump_zones)(int, int);
int (*_db_print_error)(const char *);
int (*_db_cleanup)(void);

int nt_export_db_init(void){
	if(strncmp("mysql",getenv("NT_DB_TYPE"),5)==0){
		_db_init = db_mysql_init;
		_db_build_nameservers = db_mysql_build_nameservers;
		_db_do_zone_query = db_mysql_do_zone_query;
		_db_dump_zones = db_mysql_dump_zones;
		_db_print_error =  db_mysql_print_error;
		_db_cleanup = db_mysql_cleanup;
		return 1;
	}
	/* include other db funcs here */
	else{
		fprintf(stderr, "Unknown database type: %s\n",getenv("NT_DB_TYPE"));
		return -1;
	}
}

int nt_export_db_print_error(const char * msg){
	fprintf(stderr,"nt_export_djb: ERROR: %s\n",msg);
	return 1;
}

int db_init(void){
	if(_db_init==NULL){
		fprintf(stderr,"_db_init not set");
		return -1;
	}
	return (*_db_init)();
}
int db_build_nameservers(void){
	if(_db_build_nameservers==NULL){
		fprintf(stderr,"_db_build_nameservers not set");
		return -1;
	}
	return (*_db_build_nameservers)();
}

int db_do_zone_query(char *ns_id){
	if(_db_do_zone_query==NULL){
		fprintf(stderr,"_db_do_zone_query not set");
		return -1;
	}
	return (*_db_do_zone_query)(ns_id);
}

int db_dump_zones(int opt1, int opt2){
	if(_db_dump_zones==NULL){
		fprintf(stderr,"_db_dump_zones not set");
		return -1;
	}
	return (*_db_dump_zones)(opt1, opt2);
}
int db_print_error(char *msg){
	if(_db_print_error==NULL){
		fprintf(stderr,"_db_print_error not set");
		return -1;
	}
	return (*_db_print_error)(msg);
}

int db_cleanup(void){
	if(_db_cleanup==NULL){
		fprintf(stderr,"_db_cleanup not set");
		return -1;
	}
	return (*_db_cleanup)();
}








