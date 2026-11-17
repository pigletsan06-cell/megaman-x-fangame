#ifndef X4_STDLIB_H
#define X4_STDLIB_H
#include <stddef.h>
void* malloc(size_t);
void* calloc(size_t, size_t);
void* realloc(void*, size_t);
void free(void*);
void abort(void) __attribute__((noreturn));
void exit(int) __attribute__((noreturn));
char* getenv(const char*);
unsigned long strtoul(const char*, char**, int);
long strtol(const char*, char**, int);
int atoi(const char*);
int abs(int);
long labs(long);
void qsort(void*, size_t, size_t, int (*)(const void*, const void*));
int rand(void);
void srand(unsigned);
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#endif
