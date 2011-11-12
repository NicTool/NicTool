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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <ctype.h>
#include "generic_conf.h"

int _valid(struct _config_info_t inf[], int inf_size, int seen[]);

void _set_missing_defaults(struct _config_info_t inf[], int size,
			   int seen[]);

void _dump_config_errs(FILE * fd, struct _config_info_t inf[], int size,
		       int seen[]);
void _dump_config_entry(FILE * fd, struct _config_info_t inf, int seen);

/* 
* reads the configuration file.   -1 for error, >0 if successful 
*/
int _load_config_info(struct _config_info_t desc[], int desc_size, int fd)
{
    char *cur, *buff, *mark, *mark2, *pos;
    int x, size;
    //done = 0;
    int seen[desc_size];

    for (x = 0; x < desc_size; x++)
	seen[x] = 0;

    buff = (char *) malloc(_CONFIG_BUFF_SIZE);
    size = read(fd, buff, _CONFIG_BUFF_SIZE - 1);

    if (size < 0) {
	perror("load_config_file");
	free(buff);
	return -1;
    }
    buff[size - 1] = 0;
    pos = buff;
    /*
     * config file format is:
     * #line starts with '#' for a comment
     * \s*([^:\s]+)\s*:\s*(.+)
     */

    while ((pos - buff) < size) {
	cur = pos;
	/* skip any leading whitespace, or blank lines */
	while (isspace(*cur))
	    cur++;
	/* null terminate the line */
	if ((mark = (char *) strchr(cur, '\n'))
	    /* || (mark = (char *) strchr(cur, '\r')) */
	    ) {
	    *mark = 0;
	    pos = mark + 1;
	} else {
	    pos = cur + strlen(cur) + 1;
	    mark = cur + strlen(cur) + 1;
	}
	/* skip comments */
	if (*cur == '#')
	    continue;
	/* strip trailing whitespace */
	while (isspace(*--mark)) {
	    *mark = 0;
	}
	/* strip a final double quote */
	if (*mark == '"') {
	    *mark = 0;
	    mark--;
	}
	/* locate field keyword */
	if (mark = (char *) strchr(cur, ':')) {
	    mark2 = mark;
	    *mark = 0;
	    /* strip whitespace between keyword and ':' */
	    while (isspace(*--mark)) {
		*mark = 0;
	    }
	    /* strip leading whitespace from value */
	    while (isspace(*++mark2)) {
		*mark2 = 0;
	    }
	    /* strip a leading double quote */
	    if (*mark2 == '"') {
		*mark2 = 0;
		mark2++;
	    }
	    /* compare keyword to list */
	    for (x = 0; x < desc_size; x++) {
		if (strcmp(cur, desc[x].field_name) == 0) {
		    if (!seen[x]) {
			switch (desc[x].field_type) {
			case 'a':
			    *((char **) desc[x].field_loc) =
				(char *) malloc(strlen(mark2) + 1);
			    strcpy(*(char **) desc[x].field_loc, mark2);
			    seen[x] = 1;
			    break;
			case 'i':
			    *((long int *) desc[x].field_loc) =
				atol(mark2);
			    seen[x] = 1;
			    break;
			case 'f':
			    *((float *) desc[x].field_loc) = atof(mark2);
			    seen[x] = 1;
			    break;
			default:
			    fprintf(stderr,
				    "Unsupported field type in config file description: '%c'\n",
				    desc[x].field_type);
			    return -1;
			}
		    }
		    if (seen[x])
			break;
		}
	    }
	} else {
	    continue;
	}
    }
    /* check for requirements, and set defaults */
    if (!_valid(desc, desc_size, seen)) {
	fprintf(stderr, "Config file is not valid:\n");
	_dump_config_errs(stderr, desc, desc_size, seen);
	return -1;
    }
    _set_missing_defaults(desc, desc_size, seen);

    free(buff);
#ifdef DEBUG
    print_conf_info();
#endif
    return 1;
}

void
_dump_config_errs(FILE * fd, struct _config_info_t inf[], int size,
		  int seen[])
{
    int i;
    for (i = 0; i < size; i++) {
	if (inf[i].field_flags && !seen[i]) {
	    _dump_config_entry(fd, inf[i], seen[i]);
	}
    }
}

void _dump_config_entry(FILE * fd, struct _config_info_t inf, int seen)
{
    fprintf(fd, "Field: '%s'", inf.field_name);
    switch (inf.field_type) {
    case 'a':
	fprintf(fd, "(string)");
	break;
    case 'i':
	fprintf(fd, "(int)");
	break;
    case 'f':
	fprintf(fd, "(float)");
	break;
    default:
	fprintf(fd, "(INVALID: '%c')", inf.field_type);
    }

    if (inf.field_flags) {
	fprintf(fd, " Required");
    } else {
	fprintf(fd, " Optional [default ");
	switch (inf.field_type) {
	case 'a':
	    fprintf(fd, "'%s']", *(char **) inf.field_default);
	    break;
	case 'i':
	    fprintf(fd, "%d]", *(int *) inf.field_default);
	    break;
	case 'f':
	    fprintf(fd, "%f]", *(float *) inf.field_default);
	    break;
	default:
	    fprintf(fd, "XXXX]");
	}
    }

    if (seen) {
	fprintf(fd, ": ");
	switch (inf.field_type) {
	case 'a':
	    fprintf(fd, "'%s'", *(char **) inf.field_loc);
	    break;
	case 'i':
	    fprintf(fd, "%ld", *(long int *) inf.field_loc);
	    break;
	case 'f':
	    fprintf(fd, "%f", *(float *) inf.field_loc);
	    break;
	default:
	    fprintf(fd, "XXXX");
	}
    } else if (inf.field_flags)
	fprintf(fd, ": **MISSING**");
    else
	fprintf(fd, ": missing, default value used");
    fprintf(fd, "\n");
}

int _valid(struct _config_info_t inf[], int size, int seen[])
{
    int x;
    int good = 1;
    for (x = 0; x < size; x++) {
	if (inf[x].field_flags == 1)
	    if (!seen[x])
		good = 0;
    }
    return good;
}

void
_set_missing_defaults(struct _config_info_t inf[], int size, int seen[])
{
    int x;
    for (x = 0; x < size; x++) {
	if (!seen[x] && inf[x].field_flags == 0) {
	    switch (inf[x].field_type) {
	    case 'a':
		*((char **) inf[x].field_loc) =
		    *(char **) inf[x].field_default;
		break;
	    case 'i':
		*((long int *) inf[x].field_loc) =
		    *(long int *) inf[x].field_default;
		break;
	    case 'f':
		*((float *) inf[x].field_loc) =
		    *(float *) inf[x].field_default;
		break;

	    }
	}
    }

}
