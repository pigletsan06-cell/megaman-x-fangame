#ifndef X4_STDIO_H
#define X4_STDIO_H
#include <stddef.h>
#include <stdarg.h>
typedef struct X4FILE FILE;
extern FILE* stderr;
extern FILE* stdout;
#define EOF (-1)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
int fprintf(FILE*, const char*, ...);
int printf(const char*, ...);
int sprintf(char*, const char*, ...);
int snprintf(char*, size_t, const char*, ...);
int vsnprintf(char*, size_t, const char*, va_list);
int vfprintf(FILE*, const char*, va_list);
FILE* fopen(const char*, const char*);
int fclose(FILE*);
size_t fwrite(const void*, size_t, size_t, FILE*);
size_t fread(void*, size_t, size_t, FILE*);
int fflush(FILE*);
int fseek(FILE*, long, int);
long ftell(FILE*);
int puts(const char*);
int fputs(const char*, FILE*);
int putchar(int);
int remove(const char*);
int rename(const char*, const char*);
#endif
