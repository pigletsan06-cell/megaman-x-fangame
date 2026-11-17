#ifndef X4_UNISTD_H
#define X4_UNISTD_H
#include <sys/types.h>
ssize_t read(int, void*, size_t);
ssize_t write(int, const void*, size_t);
int close(int);
int usleep(unsigned);
#endif
