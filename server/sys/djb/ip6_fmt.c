#include "fmt.h"
#include "byte.h"
#include "ip4.h"
#include "ip6.h"
#include <stdio.h>

extern char tohex(char num);

unsigned int ip6_fmt(char *s,const char ip[16])
{
  unsigned int len;
  unsigned int i;
  unsigned int temp;
  unsigned int compressing;
  unsigned int compressed;
  int j;

  len = 0; compressing = 0; compressed = 0;
  for (j=0; j<16; j+=2) {
    if (j==12 && ip6_isv4mapped(ip)) {
      temp=ip4_fmt(s,ip+12);
      len+=temp;
      break;
    }
    temp = ((unsigned long) (unsigned char) ip[j] << 8) +
            (unsigned long) (unsigned char) ip[j+1];
    if (temp == 0 && !compressed) {
      if (!compressing) {
	compressing=1;
	if (j==0) {
	  if (s) *s++=':'; ++len;
	}
      }
    } else {
      if (compressing) {
	compressing=0; ++compressed;
	if (s) *s++=':'; ++len;
      }
      i = fmt_xlong(s,temp); len += i; if (s) s += i;
      if (j<14) {
	if (s) *s++ = ':';
	++len;
      }
    }
  }
  if (compressing) { *s++=':'; ++len; }

/*  if (s) *s=0; */
  return len;
}

unsigned int ip6_fmt_flat(char *s,char ip[16])
{
  int i;
  for (i=0; i<16; i++) {
    *s++=tohex((unsigned char)ip[i] >> 4);
    *s++=tohex((unsigned char)ip[i] & 15);
  }
  return 32;
}
