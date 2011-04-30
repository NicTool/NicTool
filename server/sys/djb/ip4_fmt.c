#include "fmt.h"
#include "ip4.h"

unsigned int ip4_fmt(char *s,const char ip[4])
{
  unsigned int len;
  unsigned int i;
 
  len = 0;
  i = fmt_ulong(s,(unsigned long) (unsigned char) ip[0]); len += i; if (s) s += i;
  if (s) *s++ = '.'; ++len;
  i = fmt_ulong(s,(unsigned long) (unsigned char) ip[1]); len += i; if (s) s += i;
  if (s) *s++ = '.'; ++len;
  i = fmt_ulong(s,(unsigned long) (unsigned char) ip[2]); len += i; if (s) s += i;
  if (s) *s++ = '.'; ++len;
  i = fmt_ulong(s,(unsigned long) (unsigned char) ip[3]); len += i; if (s) s += i;
  return len;
}
