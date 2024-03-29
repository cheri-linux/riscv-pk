// See LICENSE for license details.

#include "bits.h"
#include "string.h"
#include <stdint.h>

#if defined(__GNUC__) && !defined(__clang__)
// Don't let GCC pattern-match these functions' bodies into self-calls
#pragma GCC optimize ("no-tree-loop-distribute-patterns")
#endif

void* (memcpy)(void* dest, const void* src, size_t len)
{
  const char* s = src;
  char *d = dest;

#if __has_feature(capabilities)
  if (((__cheri_addr long)dest ^ (__cheri_addr long)src) %
      sizeof(uintptr_t) == 0) {
    int tocopy = (-(__cheri_addr size_t)dest) % sizeof(uintptr_t);
    if (tocopy > len)
      tocopy = len;
    len -= tocopy;
    for (; tocopy; tocopy--)
      *d++ = *s++;
    dest = d;
#else
  if ((((uintptr_t)dest | (uintptr_t)src) & (sizeof(uintptr_t)-1)) == 0) {
#endif
    while ((void*)d < (dest + len - (sizeof(uintptr_t)-1))) {
      *(uintptr_t*)d = *(const uintptr_t*)s;
      d += sizeof(uintptr_t);
      s += sizeof(uintptr_t);
    }
  }

  while (d < (char*)(dest + len))
    *d++ = *s++;

  return dest;
}

void* (memset)(void* dest, int byte, size_t len)
{
  if ((((uintptr_t)dest | len) & (sizeof(long)-1)) == 0) {
    unsigned long word = byte & 0xFF;
    word |= word << 8;
    word |= word << 16;
    word |= word << 16 << 16;

    unsigned long *d = dest;
    while (d < (unsigned long*)(dest + len))
      *d++ = word;
  } else {
    char *d = dest;
    while (d < (char*)(dest + len))
      *d++ = byte;
  }
  return dest;
}

size_t (strlen)(const char *s)
{
  const char *p = s;
  while (*p)
    p++;
  return p - s;
}

int (strcmp)(const char* s1, const char* s2)
{
  unsigned char c1, c2;

  do {
    c1 = *s1++;
    c2 = *s2++;
  } while (c1 != 0 && c1 == c2);

  return c1 - c2;
}

char* (strcpy)(char* dest, const char* src)
{
  char* d = dest;
  while ((*d++ = *src++))
    ;
  return dest;
}

long atol(const char* str)
{
  long res = 0;
  int sign = 0;

  while (*str == ' ')
    str++;

  if (*str == '-' || *str == '+') {
    sign = *str == '-';
    str++;
  }

  while (*str) {
    res *= 10;
    res += *str++ - '0';
  }

  return sign ? -res : res;
}
