#
# $Id: Makefile 615 2008-07-01 15:28:56Z rob@bsdfreaks.nl $
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under 
# the terms of the Affero General Public License as published by Affero, 
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT 
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#


CC = g++
GCC = gcc
CFLAGS= -Wall -O2  -Wno-deprecated
CFLAGS_GCC = -Wall -O2  
INCLUDES = -I/usr/include/mysql -I/usr/local/include/mysql
LIBS = -L/usr/local/lib/mysql -lmysqlclient -lz

all: nt_export_djb copytosampledir

copytosampledir: nt_export_djb
	cp -f nt_export_djb nameserver/sample
	cp -f nt_export_djb.pl nameserver/sample

nt_export_djb.o: nt_export_djb.c
	$(CC) -c $(INCLUDES) $(CFLAGS) nt_export_djb.c

nt_export_djb: nt_export_djb.o nt_export_conf.o generic_conf.o byte_diff.o ip4_scan.o scan_xlong.o scan_ulong.o ip6_scan.o ip6_fmt.o ip4_fmt.o fmt_ulong.o fmt_xlong.o db_mysql.o nt_export_db.o
	$(CC) -o nt_export_djb nt_export_db.o db_mysql.o nt_export_conf.o generic_conf.o byte_diff.o scan_xlong.o scan_ulong.o ip4_scan.o ip6_scan.o ip6_fmt.o ip4_fmt.o fmt_ulong.o fmt_xlong.o nt_export_djb.o $(LIBS)

nt_export_conf.o: nt_export_conf.c
	$(CC) -c  $(CFLAGS) nt_export_conf.c
generic_conf.o: generic_conf.c
	$(CC) -c  $(CFLAGS) generic_conf.c
ip6_scan.o: ip6_scan.c scan.h ip6.h
	$(GCC) -c  $(CFLAGS_GCC) ip6_scan.c
byte_diff.o: byte_diff.c byte.h
	$(GCC) -c  $(CFLAGS_GCC) byte_diff.c
ip4_scan.o: ip4_scan.c scan.h ip4.h
	$(GCC) -c  $(CFLAGS_GCC) ip4_scan.c
scan_xlong.o: scan_xlong.c scan.h
	$(GCC) -c  $(CFLAGS_GCC) scan_xlong.c
scan_ulong.o: scan_ulong.c scan.h
	$(GCC) -c  $(CFLAGS_GCC) scan_ulong.c
ip6_fmt.o: ip6_fmt.c fmt.h ip6.h
	$(GCC) -c  $(CFLAGS_GCC) ip6_fmt.c
ip4_fmt.o: ip4_fmt.c fmt.h ip4.h
	$(GCC) -c  $(CFLAGS_GCC) ip4_fmt.c
fmt_ulong.o: fmt_ulong.c fmt.h
	$(GCC) -c  $(CFLAGS_GCC) fmt_ulong.c
fmt_xlong.o: fmt_xlong.c scan.h
	$(GCC) -c  $(CFLAGS_GCC) fmt_xlong.c

db_mysql.o: db_mysql.cc db_mysql.h
	$(CC) -c $(INCLUDES)  $(CFLAGS) db_mysql.cc
nt_export_db.o: nt_export_db.c nt_export_db.h
	$(CC) -c $(INCLUDES)  $(CFLAGS) nt_export_db.c

clean:
	rm -rf nt_export_djb *.o
	rm nameserver/sample/nt_export_djb
	rm nameserver/sample/nt_export_djb.pl

install:
	cp nt_export_djb /usr/local/bin/nt_export_djb
	cp nt_export_djb.pl /usr/local/sbin/nt_export_djb.pl
