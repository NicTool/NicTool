/*
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


/*
* nt_export_conf.c  
* This file holds the information for what data is in the config file.
* see nt_export_conf.h for the structure to hold that config info once it is
* parsed.
*
* To modify the way the config file works, modify the config_info_t array
* (called config_info) down below, as well as the nt_export_conf structure in
* nt_export_conf.h.
* 
* See generic_conf.h for more details about the config_info_t structure.
*/

#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include "nt_export_conf.h"

/* struct for config data */
struct nt_export_conf config;

/* default values.  need to declare and define them because we
   need a pointer to them. */
const char * db_type_default = "mysql";
int max_zones_default=500000;
int max_nameservers_default=100;

int config_info_count=5;

struct _config_info_t config_info[] = {
	/* IMPORTANT: if you modify this array,
	be sure to reflect the change in the config_info_count variable */
	{"db_host_name",	/* name */
		'a',			/* type	*/
		1,				/* required */
		NULL,			/* default */
		&config.host_name	/* storage */
	},
	{"db_user_name", 
		'a', 
		1, 
		NULL, 
		&config.user_name},
	{"db_password", 
		'a', 
		1, 
		NULL,
	       	&config.password },
	{"db_name", 
		'a', 
		1, 
		NULL, 
		&config.db_name},
	{"db_type", 
		'a', 
		0, 
		&db_type_default,
		&config.db_type}
};

/* reads the configuration file. -1 for error, >0 if successful */
int load_config_file(const char *configfile)
{
    int fd;
    if (configfile == NULL)
	configfile=CONF_PATH;
    fd = open(configfile, O_RDONLY);
    if (fd < 0) {
	perror("load_config_file");
	return (-1);
    }
    if(_load_config_info(config_info, config_info_count, fd)<0){
	fprintf(stderr,"Error loading config file\n");
	return -1;
    }
    close(fd);
    return 1;
}

void print_config_info(){
	printf("host_name: '%s'\n",config.host_name);
	printf("user_name: '%s'\n",config.user_name);
	printf("password: '%s'\n", config.password);
	printf("db_name: '%s'\n", config.db_name);
	printf("db_type: '%s'\n",config.db_type);
}

