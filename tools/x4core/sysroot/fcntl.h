#ifndef X4_FCNTL_H
#define X4_FCNTL_H
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0x40
#define O_TRUNC 0x200
int open(const char*, int, ...);
#endif
