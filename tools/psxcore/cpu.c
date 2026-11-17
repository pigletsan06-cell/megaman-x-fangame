// CPU R3000A interpretada + barramento de memória
#include "psx.h"

u8 psx_ram[2 * 1024 * 1024];
u32 trail[64][2]; int trail_i; static int zero_run;
u8 psx_scratch[1024];
u8 psx_bios[512 * 1024];
Cpu cpu;
static u32 cache_ctrl;

static inline u32 rd32(const u8* p) { return p[0] | p[1] << 8 | p[2] << 16 | (u32)p[3] << 24; }
static inline void wr32(u8* p, u32 v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }

u32 idle_writes;   // muda a cada escrita/acesso ao hardware: um laço sem mudanças é espera ociosa
u32 bus_read(u32 addr, int size)
{
    if (addr == 0xFFFE0130) return cache_ctrl;
    u32 a = addr & 0x1FFFFFFF;
    const u8* p;
    if (a < 0x00800000) { p = psx_ram + (a & 0x1FFFFF);
        { extern u32 rw_lo, rw_hi, rw_on; if (rw_on && (a & 0x1FFFFF) >= rw_lo && (a & 0x1FFFFF) < rw_hi) { extern u32 rw_pc(void); psx_log("[le %x pc=%x]\n", a & 0x1FFFFF, rw_pc()); } } }
    else if (a >= 0x1FC00000 && a < 0x1FC80000) p = psx_bios + (a & 0x7FFFF);
    else if (a >= 0x1F800000 && a < 0x1F800400) p = psx_scratch + (a & 0x3FF);
    else if (a >= 0x1F801000 && a < 0x1F803000) {
        if (a != 0x1F801814 && a != 0x1F801070 && a != 0x1F8010F4) idle_writes++;
        return hw_read(a, size);
    }
    else if (a >= 0x1F000000 && a < 0x1F800000) return size == 4 ? 0xFFFFFFFF : size == 2 ? 0xFFFF : 0xFF;
    else return 0;
    if (size == 4) return rd32(p);
    if (size == 2) return p[0] | p[1] << 8;
    return p[0];
}

u32 watch_addr, trace_pc;
u32 rw_lo, rw_hi, rw_on;
u32 rw_pc(void) { return cpu.pc; }
u32 idle_writes_unused;   // muda a cada escrita/acesso ao hardware: um laço sem mudanças é espera ociosa
void bus_write(u32 addr, u32 v, int size)
{
    idle_writes++;
    if (addr == 0xFFFE0130) { cache_ctrl = v; return; }
    if (cpu.cop0[12] & 0x10000) return;   // cache isolada (BIOS limpando o cache)
    u32 a = addr & 0x1FFFFFFF;
    u8* p;
    if (a < 0x00800000) {
        p = psx_ram + (a & 0x1FFFFF);
        { extern u32 watch_addr; if (watch_addr && ((a & 0x1FFFFC) == watch_addr || (a & 0x1FFFFC) == (watch_addr | 0x200000))) psx_log("[escrita %x = %x pc=%x ra=%x a0=%x a1=%x a2=%x a3=%x sp=%x]\n", a, v, cpu.pc, cpu.r[31], cpu.r[4], cpu.r[5], cpu.r[6], cpu.r[7], cpu.r[29]); }
    }
    else if (a >= 0x1F800000 && a < 0x1F800400) p = psx_scratch + (a & 0x3FF);
    else if (a >= 0x1F801000 && a < 0x1F803000) { hw_write(a, v, size); return; }
    else return;
    if (size == 4) wr32(p, v);
    else if (size == 2) { p[0] = v; p[1] = v >> 8; }
    else p[0] = v;
}

static inline u32 fetch(u32 addr)
{
    u32 a = addr & 0x1FFFFFFF;
    if (a < 0x00800000) return rd32(psx_ram + (a & 0x1FFFFF));
    if (a >= 0x1FC00000 && a < 0x1FC80000) return rd32(psx_bios + (a & 0x7FFFF));
    return bus_read(addr, 4);
}

void cpu_reset(void)
{
    memset(&cpu, 0, sizeof(cpu));
    memset(psx_ram, 0, sizeof(psx_ram)); memset(psx_scratch, 0, sizeof(psx_scratch));
    cache_ctrl = 0; zero_run = 0;
    cpu.pc = 0xBFC00000;
    cpu.next_pc = cpu.pc + 4;
    cpu.cop0[15] = 2;
}

static int wrote_reg;
static inline void set_reg(int r, u32 v) { cpu.r[r] = v; wrote_reg = r; cpu.r[0] = 0; }
static inline void set_load(int r, u32 v) { cpu.load_reg = r; cpu.load_val = v; }

static int exc_logged;
void cpu_exception(u32 code)
{
    if (code != 0 && code != 8 && exc_logged < 6) {
        exc_logged++;
        psx_log("[exceção %d em %x badv=%x ra=%x sp=%x]\n", code, cpu.cur_pc, cpu.cop0[8], cpu.r[31], cpu.r[29]);
        for (int k = 0; k < 10; k++) { int j = (trail_i - 10 + k) & 63; psx_log("   %x -> %x\n", trail[j][0], trail[j][1]); }
    }
    u32 sr = cpu.cop0[12];
    u32 handler = (sr & (1 << 22)) ? 0xBFC00180 : 0x80000080;
    u32 mode = sr & 0x3F;
    cpu.cop0[12] = (sr & ~0x3F) | ((mode << 2) & 0x3F);
    cpu.cop0[13] = (cpu.cop0[13] & ~0x8000007C) | (code << 2);
    if (cpu.in_delay) {
        cpu.cop0[14] = cpu.cur_pc - 4;
        cpu.cop0[13] |= 0x80000000;
    } else {
        cpu.cop0[14] = cpu.cur_pc;
    }
    cpu.pc = handler;
    cpu.next_pc = handler + 4;
    cpu.branch_taken = 0;
}

static inline void branch(u32 target)
{
    cpu.next_pc = target;
    cpu.branch_taken = 1;
}

#define RS cpu.r[(op >> 21) & 31]
#define RT cpu.r[(op >> 16) & 31]
#define RTN ((op >> 16) & 31)
#define RDN ((op >> 11) & 31)
#define IMM ((u32)(s32)(s16)(op & 0xFFFF))
#define IMMU (op & 0xFFFF)

extern u64 next_event;
static int exc_pending;

static void exec(u32 op)
{
    u32 pend_r = cpu.load_reg, pend_v = cpu.load_val;
    cpu.load_reg = 0;
    wrote_reg = 0;
    u32 t;
    switch (op >> 26) {
    case 0x00:
        switch (op & 0x3F) {
        case 0x00: set_reg(RDN, RT << ((op >> 6) & 31)); break;
        case 0x02: set_reg(RDN, RT >> ((op >> 6) & 31)); break;
        case 0x03: set_reg(RDN, (u32)((s32)RT >> ((op >> 6) & 31))); break;
        case 0x04: set_reg(RDN, RT << (RS & 31)); break;
        case 0x06: set_reg(RDN, RT >> (RS & 31)); break;
        case 0x07: set_reg(RDN, (u32)((s32)RT >> (RS & 31))); break;
        case 0x08: branch(RS); break;
        case 0x09: t = RS; set_reg(RDN, cpu.pc + 4); branch(t); break;
        case 0x0C: cpu_exception(8); exc_pending = 1; break;
        case 0x0D: cpu_exception(9); exc_pending = 1; break;
        case 0x10: set_reg(RDN, cpu.hi); break;
        case 0x11: cpu.hi = RS; break;
        case 0x12: set_reg(RDN, cpu.lo); break;
        case 0x13: cpu.lo = RS; break;
        case 0x18: { s64 m = (s64)(s32)RS * (s64)(s32)RT; cpu.lo = (u32)m; cpu.hi = (u32)(m >> 32); break; }
        case 0x19: { u64 m = (u64)RS * (u64)RT; cpu.lo = (u32)m; cpu.hi = (u32)(m >> 32); break; }
        case 0x1A: {
            s32 n = (s32)RS, d = (s32)RT;
            if (d == 0) { cpu.hi = (u32)n; cpu.lo = n >= 0 ? 0xFFFFFFFF : 1; }
            else if ((u32)n == 0x80000000 && d == -1) { cpu.hi = 0; cpu.lo = 0x80000000; }
            else { cpu.hi = (u32)(n % d); cpu.lo = (u32)(n / d); }
            break;
        }
        case 0x1B: {
            u32 n = RS, d = RT;
            if (d == 0) { cpu.hi = n; cpu.lo = 0xFFFFFFFF; }
            else { cpu.hi = n % d; cpu.lo = n / d; }
            break;
        }
        case 0x20: {
            u32 a = RS, b = RT, r = a + b;
            if (~(a ^ b) & (a ^ r) & 0x80000000) { cpu_exception(12); exc_pending = 1; }
            else set_reg(RDN, r);
            break;
        }
        case 0x21: set_reg(RDN, RS + RT); break;
        case 0x22: {
            u32 a = RS, b = RT, r = a - b;
            if ((a ^ b) & (a ^ r) & 0x80000000) { cpu_exception(12); exc_pending = 1; }
            else set_reg(RDN, r);
            break;
        }
        case 0x23: set_reg(RDN, RS - RT); break;
        case 0x24: set_reg(RDN, RS & RT); break;
        case 0x25: set_reg(RDN, RS | RT); break;
        case 0x26: set_reg(RDN, RS ^ RT); break;
        case 0x27: set_reg(RDN, ~(RS | RT)); break;
        case 0x2A: set_reg(RDN, (s32)RS < (s32)RT); break;
        case 0x2B: set_reg(RDN, RS < RT); break;
        default: cpu_exception(10); exc_pending = 1; break;
        }
        break;
    case 0x01: {
        int rt = RTN;
        int cond = (rt & 1) ? ((s32)RS >= 0) : ((s32)RS < 0);
        if ((rt & 0x1E) == 0x10) set_reg(31, cpu.pc + 4);
        if (cond) branch(cpu.pc + (IMM << 2));
        break;
    }
    case 0x02: branch((cpu.pc & 0xF0000000) | ((op & 0x3FFFFFF) << 2)); break;
    case 0x03: set_reg(31, cpu.pc + 4); branch((cpu.pc & 0xF0000000) | ((op & 0x3FFFFFF) << 2)); break;
    case 0x04: if (RS == RT) branch(cpu.pc + (IMM << 2)); break;
    case 0x05: if (RS != RT) branch(cpu.pc + (IMM << 2)); break;
    case 0x06: if ((s32)RS <= 0) branch(cpu.pc + (IMM << 2)); break;
    case 0x07: if ((s32)RS > 0) branch(cpu.pc + (IMM << 2)); break;
    case 0x08: {
        u32 a = RS, b = IMM, r = a + b;
        if (~(a ^ b) & (a ^ r) & 0x80000000) { cpu_exception(12); exc_pending = 1; }
        else set_reg(RTN, r);
        break;
    }
    case 0x09: set_reg(RTN, RS + IMM); break;
    case 0x0A: set_reg(RTN, (s32)RS < (s32)IMM); break;
    case 0x0B: set_reg(RTN, RS < IMM); break;
    case 0x0C: set_reg(RTN, RS & IMMU); break;
    case 0x0D: set_reg(RTN, RS | IMMU); break;
    case 0x0E: set_reg(RTN, RS ^ IMMU); break;
    case 0x0F: set_reg(RTN, IMMU << 16); break;
    case 0x10: {   // COP0
        int sub = (op >> 21) & 31;
        if (sub == 0) set_load(RTN, RDN == 13 ? ((cpu.cop0[13] & ~0x400) | ((i_stat & i_mask) ? 0x400 : 0)) : cpu.cop0[RDN]);
        else if (sub == 4) {
            int rd = RDN;
            if (rd == 13) cpu.cop0[13] = (cpu.cop0[13] & ~0x300) | (RT & 0x300);
            else cpu.cop0[rd] = RT;
        } else if ((op & 0x3F) == 0x10) {   // RFE
            u32 sr = cpu.cop0[12];
            cpu.cop0[12] = (sr & ~0xF) | ((sr >> 2) & 0xF);
        }
        break;
    }
    case 0x12: {   // COP2 (GTE)
        int sub = (op >> 21) & 31;
        if (op & (1 << 25)) gte_command(op & 0x1FFFFFF);
        else if (sub == 0) set_load(RTN, gte_read_data(RDN));
        else if (sub == 2) set_load(RTN, gte_read_ctrl(RDN));
        else if (sub == 4) gte_write_data(RDN, RT);
        else if (sub == 6) gte_write_ctrl(RDN, RT);
        break;
    }
    case 0x11: case 0x13: cpu_exception(11); exc_pending = 1; break;
    case 0x20: set_load(RTN, (u32)(s32)(s8)bus_read(RS + IMM, 1)); break;
    case 0x21: {
        u32 a = RS + IMM;
        if (a & 1) { cpu.cop0[8] = a; cpu_exception(4); exc_pending = 1; break; }
        set_load(RTN, (u32)(s32)(s16)bus_read(a, 2));
        break;
    }
    case 0x22: {   // LWL
        u32 a = RS + IMM;
        u32 cur = (pend_r == RTN) ? pend_v : RT;
        u32 w = bus_read(a & ~3, 4);
        u32 v;
        switch (a & 3) {
        case 0: v = (cur & 0x00FFFFFF) | (w << 24); break;
        case 1: v = (cur & 0x0000FFFF) | (w << 16); break;
        case 2: v = (cur & 0x000000FF) | (w << 8); break;
        default: v = w; break;
        }
        set_load(RTN, v);
        break;
    }
    case 0x23: {
        u32 a = RS + IMM;
        if (a & 3) { cpu.cop0[8] = a; cpu_exception(4); exc_pending = 1; break; }
        set_load(RTN, bus_read(a, 4));
        break;
    }
    case 0x24: set_load(RTN, bus_read(RS + IMM, 1)); break;
    case 0x25: {
        u32 a = RS + IMM;
        if (a & 1) { cpu.cop0[8] = a; cpu_exception(4); exc_pending = 1; break; }
        set_load(RTN, bus_read(a, 2));
        break;
    }
    case 0x26: {   // LWR
        u32 a = RS + IMM;
        u32 cur = (pend_r == RTN) ? pend_v : RT;
        u32 w = bus_read(a & ~3, 4);
        u32 v;
        switch (a & 3) {
        case 0: v = w; break;
        case 1: v = (cur & 0xFF000000) | (w >> 8); break;
        case 2: v = (cur & 0xFFFF0000) | (w >> 16); break;
        default: v = (cur & 0xFFFFFF00) | (w >> 24); break;
        }
        set_load(RTN, v);
        break;
    }
    case 0x28: bus_write(RS + IMM, RT, 1); break;
    case 0x29: {
        u32 a = RS + IMM;
        if (a & 1) { cpu.cop0[8] = a; cpu_exception(5); exc_pending = 1; break; }
        bus_write(a, RT, 2);
        break;
    }
    case 0x2A: {   // SWL
        u32 a = RS + IMM, v = RT;
        u32 w = bus_read(a & ~3, 4);
        switch (a & 3) {
        case 0: w = (w & 0xFFFFFF00) | (v >> 24); break;
        case 1: w = (w & 0xFFFF0000) | (v >> 16); break;
        case 2: w = (w & 0xFF000000) | (v >> 8); break;
        default: w = v; break;
        }
        bus_write(a & ~3, w, 4);
        break;
    }
    case 0x2B: {
        u32 a = RS + IMM;
        if (a & 3) { cpu.cop0[8] = a; cpu_exception(5); exc_pending = 1; break; }
        bus_write(a, RT, 4);
        break;
    }
    case 0x2E: {   // SWR
        u32 a = RS + IMM, v = RT;
        u32 w = bus_read(a & ~3, 4);
        switch (a & 3) {
        case 0: w = v; break;
        case 1: w = (w & 0x000000FF) | (v << 8); break;
        case 2: w = (w & 0x0000FFFF) | (v << 16); break;
        default: w = (w & 0x00FFFFFF) | (v << 24); break;
        }
        bus_write(a & ~3, w, 4);
        break;
    }
    case 0x32: gte_write_data(RTN, bus_read(RS + IMM, 4)); break;   // LWC2
    case 0x3A: bus_write(RS + IMM, gte_read_data(RTN), 4); break;  // SWC2
    default: cpu_exception(10); exc_pending = 1; break;
    }
    if (pend_r && pend_r != (u32)wrote_reg && pend_r != cpu.load_reg) cpu.r[pend_r] = pend_v;
    cpu.r[0] = 0;
}

void psx_hook_pc(u32 pc);
int dbg_watch = 1;
int st_irqs, st_irq_delay, dbg_delay;


int no_idle, dbg_on;
void cpu_run(u64 until)
{
    extern int dbg_on;
    while (cpu.cycles < until) {
        // interrupções (o bit 0x400 da causa é calculado aqui e na leitura do COP0)
        if ((i_stat & i_mask) | (cpu.cop0[13] & 0x300)) {
            if (i_stat & i_mask) cpu.cop0[13] |= 0x400; else cpu.cop0[13] &= ~0x400;
            if (!cpu.branch_taken && (cpu.cop0[12] & 1) && (cpu.cop0[12] & cpu.cop0[13] & 0xFF00)) {   // nunca entre um desvio e seu atraso
                cpu.cur_pc = cpu.pc;
                cpu.in_delay = cpu.branch_taken;
                // instrução GTE na posição de retorno: o hardware a executa antes (peculiaridade do PS1)
                u32 nxt = fetch(cpu.pc);
                if ((nxt >> 25) == 0x25) gte_command(nxt & 0x1FFFFFF);
                if (cpu.load_reg) { cpu.r[cpu.load_reg] = cpu.load_val; cpu.load_reg = 0; cpu.r[0] = 0; }
                st_irqs++;
                cpu_exception(0);
            }
        }
        u32 pc = cpu.pc;
        if (pc < 0x100 ? (pc == 0xA0 || pc == 0xB0 || pc == 0xC0) : pc == 0x80030000) { psx_hook_pc(pc); pc = cpu.pc; }
        u32 op = fetch(pc);
        if (dbg_on) {
            extern u32 trace_pc; if (pc == trace_pc) psx_log("[pc %x a0=%x a1=%x a2=%x a3=%x t1=%x ra=%x ciclo=%llu]\n", pc, cpu.r[4], cpu.r[5], cpu.r[6], cpu.r[7], cpu.r[9], cpu.r[31], (unsigned long long)cpu.cycles);
            if (pc != cpu.cur_pc + 4) { trail[trail_i & 63][0] = cpu.cur_pc; trail[trail_i & 63][1] = pc; trail_i++; }
            if (op == 0) {
                if (++zero_run == 2000 && dbg_watch) {
                    dbg_watch = 0;
                    psx_log("[executando zeros em %x; últimos saltos:]\n", pc);
                    for (int k = 0; k < 24; k++) { int j = (trail_i - 24 + k) & 63; psx_log("  %x -> %x\n", trail[j][0], trail[j][1]); }
                }
            } else zero_run = 0;
        }
        cpu.cur_pc = pc;
        cpu.pc = cpu.next_pc;
        cpu.next_pc = cpu.pc + 4;
        cpu.in_delay = cpu.branch_taken;
        cpu.branch_taken = 0;
        exc_pending = 0;
        exec(op);
        // espera ociosa: o mesmo laço curto repetido sem escrever nada e com os mesmos registradores
        if (cpu.branch_taken && cpu.next_pc <= cpu.cur_pc && cpu.cur_pc - cpu.next_pc <= 64 && !no_idle) {
            static u32 lp_pc, lp_w, lp_regs[34]; static int lp_hits;
            if (cpu.next_pc == lp_pc && idle_writes == lp_w && !memcmp(lp_regs, cpu.r, 32 * 4) && lp_regs[32] == cpu.hi && lp_regs[33] == cpu.lo && !cpu.load_reg) {
                if (++lp_hits >= 2) {
                    extern int hw_pending; extern u32 i_stat;
                    u32 is0 = i_stat;
                    cpu.cycles += 2;
                    { int c = hw_pending + 2; hw_pending = 0; hw_tick(c); }
                    while (cpu.cycles < until && i_stat == is0) {
                        u64 n = until - cpu.cycles; if (n > 256) n = 256;
                        cpu.cycles += n; hw_tick((int)n);
                    }
                    lp_hits = 0;
                    continue;
                }
            } else {
                lp_pc = cpu.next_pc; lp_w = idle_writes; memcpy(lp_regs, cpu.r, 32 * 4); lp_regs[32] = cpu.hi; lp_regs[33] = cpu.lo; lp_hits = 0;
            }
        }
        cpu.cycles += 2;
        { extern int hw_pending; hw_pending += 2; if (hw_pending >= 128) { int c = hw_pending; hw_pending = 0; hw_tick(c); } }
    }
}
