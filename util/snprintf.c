// See LICENSE for license details.

#include <stdint.h>
#include <stdarg.h>
#include <stdbool.h>
#include "string.h"

int vsnprintf(char* out, size_t n, const char* s, va_list vl)
{
  bool format = false;
  bool longarg = false;
  bool longlongarg = false;
  bool uintptrarg = false;
  const char* fmtstart;
  size_t pos = 0;
  for( ; *s; s++)
  {
    if(format)
    {
      switch(*s)
      {
        case 'l':
          if (s[1] == 'l') {
              longlongarg = true;
              s++;
          }
          else
              longarg = true;
          break;
        case 'p':
          uintptrarg = true;
          if (++pos < n) out[pos-1] = '0';
          if (++pos < n) out[pos-1] = 'x';
        case 'x':
        {
          long num = uintptrarg ? va_arg(vl, uintptr_t) : (longarg ? va_arg(vl, long) : va_arg(vl, int));
          for(int i = 2*((uintptrarg || longarg) ? sizeof(long) : sizeof(int))-1; i >= 0; i--) {
            int d = (num >> (4*i)) & 0xF;
            if (++pos < n) out[pos-1] = (d < 10 ? '0'+d : 'a'+d-10);
          }
          uintptrarg = false;
          longarg = false;
          format = false;
          uintptrarg = false;
          break;
        }
        case 'd':
        {
          long long num;
          if (longarg)
              num = va_arg(vl, long);
          else if (longlongarg)
              num = va_arg(vl, long long);
          else
              num = va_arg(vl, int);
          if (num < 0) {
            num = -num;
            if (++pos < n) out[pos-1] = '-';
          }
          long digits = 1;
          for (long long nn = num; nn /= 10; digits++)
            ;
          for (int i = digits-1; i >= 0; i--) {
            if (pos + i + 1 < n) out[pos + i] = '0' + (num % 10);
            num /= 10;
          }
          pos += digits;
          longarg = false;
          longlongarg = false;
          format = false;
          break;
        }
        case 's':
        {
          const char* s2 = va_arg(vl, const char*);
          while (*s2) {
            if (++pos < n)
              out[pos-1] = *s2;
            s2++;
          }
          longarg = false;
          format = false;
          break;
        }
        case 'c':
        {
          if (++pos < n) out[pos-1] = (char)va_arg(vl,int);
          longarg = false;
          format = false;
          break;
        }
        default:
          for (const char* badfmt = fmtstart; badfmt <= s; badfmt++) {
            if (++pos < n)
              out[pos - 1] = *badfmt;
          }
          format = false;
          longarg = false;
          longlongarg = false;
          uintptrarg = false;
          fmtstart = NULL;
          continue;
      }
    }
    else if(*s == '%') {
      format = true;
      fmtstart = s;
    } else {
      if (++pos < n)
        out[pos - 1] = *s;
    }
  }
  if (pos < n)
    out[pos] = 0;
  else if (n)
    out[n-1] = 0;
  return pos;
}

int snprintf(char* out, size_t n, const char* s, ...)
{
  va_list vl;
  va_start(vl, s);
  int res = vsnprintf(out, n, s, vl);
  va_end(vl);
  return res;
}
