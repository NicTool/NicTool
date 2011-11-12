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

/**
* Generic config method.  Use an array of structs which define what each field
* in the config file should be.
*
* _config_info_t struct for config file elements: 
* field_name: keyword to look for in the config file
* field_type: type of the data:
* 	'a': character data (string)
* 	'i'; integer
* 	'f': float
* field_flags: 1:required, 0:optional
* union for default values of different types
* union for different pointer types for where to store the data
*  
*/


#ifndef _CONFIG_INFO
#define _CONFIG_INFO
#define _CONFIG_BUFF_SIZE 2048

struct _config_info_t{
	const char *field_name;
	const char field_type;
	int field_flags;
	void * field_default;
/*	union {
		long int field_default_int;
		char * field_default_str;
		float field_default_float;
	}; */
	void * field_loc;
/*	union{
		long int * field_loc_int;
		char ** field_loc_str;
		float * field_loc_float;
	}; */
};
#endif

int _load_config_info(struct _config_info_t desc[], int desc_size, int fd);

