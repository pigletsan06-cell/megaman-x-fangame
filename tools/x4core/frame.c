// Ponto de entrada para o Godot: o corpo do laço principal (2824.c func_80012024) quadro a quadro.
#include "common.h"
#include "main/2824.h"
extern void func_8001213C(void);
extern void tile_effect_nop(void);
extern void mmx4_pc_finish_cd_load(void);
extern void mmx4_pc_complete_scheduled_cd_load(int);
extern void func_800168D8(void);
extern s32 func_800169D8(void);
extern void func_80012328(void);
extern void func_80012600(void);
extern void func_80014780(void);
extern void func_80012454(void);
extern void load_palette(void);
extern void load_vram_rect_ptrs(void);
extern void clear_vram_rect_ptrs(void);

void godot_boot(void)
{
    tile_effect_nop();
    func_8001213C();
}

void godot_frame(void)
{
    mmx4_pc_finish_cd_load();
    PutDispEnv(&cur_draw_info->dispenv);
    PutDrawEnv(&cur_draw_info->drawenv);
    DrawOTag(&cur_draw_info->ordering_table.end);
    SP_DRAW_BUFFER ^= 1;
    cur_draw_info = &draw_infos[SP_DRAW_BUFFER];
    ClearOTagR(&cur_draw_info->ordering_table.start, 0xC);
    func_800168D8();
    func_800169D8();
    func_80012328();
    clear_vram_rect_ptrs();
    main_bss_state.frame_counter++;
    func_80012600();
    func_80014780();
    load_vram_rect_ptrs();
    load_palette();
    func_80012454();
    mmx4_pc_complete_scheduled_cd_load(0);
}
