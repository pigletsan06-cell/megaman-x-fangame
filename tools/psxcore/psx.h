// Núcleo de PS1 enxuto para rodar Mega Man X5/X6 dentro do Godot.
// CPU interpretada (R3000A + GTE), BIOS livre (OpenBIOS), GPU em alto nível
// (as primitivas vão para o shader do Godot), CD, DMA, timers, controle, SPU (psyz).
#ifndef PSX_H
#define PSX_H
#include <stdint.h>
#include <stddef.h>

#ifdef _WIN32
#define PSXAPI __declspec(dllexport)
#else
#define PSXAPI __attribute__((visibility("default")))
#endif

typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
typedef int8_t s8; typedef int16_t s16; typedef int32_t s32; typedef int64_t s64;

// memória
extern u8 psx_ram[2 * 1024 * 1024];
extern u8 psx_scratch[1024];
extern u8 psx_bios[512 * 1024];
u32 bus_read(u32 addr, int size);
void bus_write(u32 addr, u32 value, int size);

// cpu
typedef struct {
    u32 r[32], hi, lo, pc, next_pc, cur_pc;
    u32 cop0[32];
    int in_delay, branch_taken;
    int load_reg; u32 load_val;
    u64 cycles;
} Cpu;
extern Cpu cpu;
void cpu_reset(void);
void cpu_run(u64 until);
void cpu_exception(u32 code);

// gte
u32 gte_read_data(int r);
void gte_write_data(int r, u32 v);
u32 gte_read_ctrl(int r);
void gte_write_ctrl(int r, u32 v);
void gte_command(u32 op);

// interrupções
void irq_raise(int n);
extern u32 i_stat, i_mask;

// hardware
u32 hw_read(u32 addr, int size);
void hw_write(u32 addr, u32 value, int size);
void hw_tick(int cycles);
void gpu_gp0(u32 w);
void gpu_gp1(u32 w);
u32 gpu_read(void);
u32 gpu_stat(void);
void gpu_frame_begin(void);
void gpu_vram_snapshot(void);
void cd_tick(int cycles);
void timers_tick(int cycles);
void sio_tick(int cycles);
void dma_write(u32 addr, u32 v);
u32 dma_read(u32 addr);

// disco
int disc_read_sector(int lba, u8* out2352);
extern int disc_sectors;

// log
void psx_log(const char* fmt, ...);
void* memcpy(void*, const void*, size_t);
void* memset(void*, int, size_t);
int memcmp(const void*, const void*, size_t);
size_t strlen(const char*);

// estado exportado para o Godot
extern u32 prim_stream[1 << 18];
extern int prim_len;
extern u16 vram[1024 * 512];
extern u16 vram_draw[1024 * 512];
extern int vram_draw_dirty;
extern unsigned pad_buttons;
#endif
