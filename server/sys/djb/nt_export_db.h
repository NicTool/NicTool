/*
 *
 * $Id: nt_export_db.h 615 2008-07-01 15:28:56Z rob@bsdfreaks.nl $
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

int db_init(void);
int db_build_nameservers(void);
int db_do_zone_query(char *ns_id);
int db_dump_zones(int, int);
int db_print_error(char * msg);
int db_cleanup(void);

int nt_export_db_init(void);
int nt_export_db_print_error(const char *msg);
