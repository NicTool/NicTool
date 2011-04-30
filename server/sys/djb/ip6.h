#ifndef IP6_H
#define IP6_H

extern unsigned int ip6_scan(const char *,char *);
extern unsigned int ip6_fmt(char *,const char *);

extern unsigned int ip6_scan_flat(const char *,char *);
extern unsigned int ip6_fmt_flat(char *,char *);

/*
 ip6 address syntax: (h = hex digit), no leading '0' required
   1. hhhh:hhhh:hhhh:hhhh:hhhh:hhhh:hhhh:hhhh
   2. any number of 0000 may be abbreviated as "::", but only once
 flat ip6 address syntax:
   hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh
 */

#define IP6_FMT 40

const static unsigned char V4mappedprefix[12]={0,0,0,0,0,0,0,0,0,0,0xff,0xff};
const static unsigned char V6loopback[16]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1};
const static unsigned char V6any[16]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};

#define ip6_isv4mapped(ip) (byte_equal(ip,12,V4mappedprefix))

const static char ip4loopback[4] = {127,0,0,1};

#endif


