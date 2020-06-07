// See LICENSE for license details.
#include <stdarg.h>
#include <stddef.h>

#define memcpy(dest, src, len) __builtin_memcpy(dest, src, len)
#define memset(dest, byte, len) __builtin_memset(dest, byte, len)
#define strlen(s) __builtin_strlen(s)
#define strcmp(s1, s2) __builtin_strcmp(s1, s2)
#define strcpy(dest, src) __builtin_strcpy(dest, src)

int snprintf(char* out, size_t n, const char* s, ...);
int vsnprintf(char* out, size_t n, const char* s, va_list vl);

long atol(const char* str);
