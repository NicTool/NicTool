/*
 *
 * $Id: nt_export_conf.h,v 1.3 2004/10/05 00:09:26 matt Exp $
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
 * config.h header for config module
 *
 */

#include "generic_conf.h"

#ifndef CONF_PATH
#define CONF_PATH "nt_export.conf"
#endif


int load_config_file(char *filename);

/*
* struct to hold all the config data.
*/
struct nt_export_conf{
	char *host_name;
	char *user_name;
	char *password;
	char *db_name;
	char *db_type;
	long int max_zones;
	long int max_nameservers;
} ;

