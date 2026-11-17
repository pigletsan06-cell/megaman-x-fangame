#include <stdio.h>
#include <stdlib.h>
// Fangame: habilidades das armaduras de outros jogos no X do X4 (portadas da lógica original)
#include "common.h"
#include "main/objects.h"
#include "main/player.h"
#include "main/player_common.h"
#include "main/player_special.h"
#include "main/player_weapon.h"
#include "main/player_check.h"
#include "main/player_enter.h"
// habilidades novas, lote 3 (estado usado pelos objetos nossos em fg_weapon_update)
static int dive_on, dive_t;     // Mergulho (capacete Falcon X6)
int fg_dive_t = -1;             // Godot: quadros do mergulho (-1 = não está mergulhando)
static int hab_orb_req, hab_orb_x, hab_orb_y; static s8 hab_orb_bg;   // Plasma reativo: 4 bolas pedidas (posição do X)
#define HAB_ORB_LIFE 90         // bola de plasma: 90 quadros, 1 de dano a cada 6 quadros, caixa 32x32
#define HAB_BOOM_LIFE 24        // explosão da Reação em cadeia: 24 quadros, 2 de dano a cada 8 quadros, caixa 64x64
#define HAB_DIVE_MAX 40         // Mergulho: até 40 quadros, 6 px/quadro para a frente e para baixo, 4 de dano a cada 8
static struct WeaponObj* hab_box_spawn(int kind, int x, int y, s8 bg, const struct Unk_unk68* box);
extern struct Unk_unk68 fg_orb_box[];
static void fg_dive(struct PlayerObj* self);

extern int fg_armor;

// ---- voo da Falcon Armor (Mega Man X5) ----
// SLUS_013.34: func_8003F154 (início: pulo no ar), estado 0x23 func_80040350 -> sub-estados D_80074D10:
// func_80040FF4 (animação de início), func_8004103C/func_80041090 (voo), func_8003FE6C (direção/velocidade),
// func_80040B6C (fim: 180 quadros ou pulo de novo). Velocidade = 1,5 x andar (2,0) = 3,0; diagonal x 0xB5/256.
int fg_fly_on, fg_fly_frame = -1, fg_fly_fx = -1;   // fx: jato (objeto do X5 que acompanha o X, ciclo de 15 quadros)
// ---- sons do X5/X6: o x4core só põe o número na fila; o Godot toca assets/sfx/<nome>.wav (ordem em x4_machine.gd FG_SFX)
enum { SFX_X5_SHOT, SFX_X5_CHARGE, SFX_X5_SEMI, SFX_X5_CHARGED, SFX_X5_FLY, SFX_X5_HOVER, SFX_X5_FALCON_GIGA, SFX_X5_GAEA_GIGA1,
    SFX_X5_GAEA_GIGA2, SFX_X5_NOVA, SFX_X6_SHOT, SFX_X6_CHARGE, SFX_X6_SEMI, SFX_X6_CHARGED, SFX_X6_DASH, SFX_X6_JUMP, SFX_X6_GRAB,
    SFX_X6_ENGETSURIN, SFX_X6_GIGA_DASH, SFX_X6_BLADE_GIGA, SFX_X6_SHADOW_GIGA, SFX_X6_HOVER };
#define SFX_STOP 0x100
static int sfx_q[16], sfx_n;
static void fg_sfx(int id) { if (sfx_n < 16) sfx_q[sfx_n++] = id; }
int fg_sfx_pop(void)
{
    int v;
    if (sfx_n == 0) return -1;
    v = sfx_q[0];
    for (int i = 1; i < sfx_n; i++) sfx_q[i - 1] = sfx_q[i];
    sfx_n--;
    return v;
}
extern int fg_armor;
// peças combináveis: armadura de cada peça (0 = sem peça / do X4 puro, 1..8 = armaduras do X5/X6, 9 = peça do X4).
// fg_armor = armadura completa (as 4 peças iguais) ou 0: só ela dá o Giga Attack.
int fg_head, fg_body, fg_arm, fg_legs;
static int fus(int c) { return c >= 1 && c <= 8; }
static int x6c(int c) { return c >= 5 && c <= 8; }
static int fg_any(void) { return fus(fg_head) || fus(fg_body) || fus(fg_arm) || fus(fg_legs); }
static int fg_x6(void) { return x6c(fg_arm); }
// func_8001540C do X4: os sons do X (tiro, carga, tiro carregado, flutuar, Nova) viram os do jogo da armadura
// falas do X e do Zero (banco 3, mesma numeração no X4 e no X6): as do X6, se o hub pediu (MMX4_VOZ_X6=1)
#define SFX_VOZ_X 22
#define SFX_VOZ_Z 34
static int voz_x6 = -1;
int fg_sound_hook(int kind, int id)
{
    int x6 = fg_x6();
    if ((kind & 0x7F) == 3) {
        if (voz_x6 < 0) { const char* e = getenv("MMX4_VOZ_X6"); voz_x6 = (e != NULL && e[0] == '1'); }
        // a fala 11 do X6 é o grito de morte (no X4 a 11 é o aviso de vida baixa e a 12 é a morte)
        if (voz_x6 && id == 12) { fg_sfx((g_Player.unk2 ? SFX_VOZ_Z : SFX_VOZ_X) + 11); return 1; }
        if (voz_x6 && id == 11) return 1;   // vida baixa: o X6 não tem fala para isso
        if (voz_x6 && id >= 0 && id < 12) { fg_sfx((g_Player.unk2 ? SFX_VOZ_Z : SFX_VOZ_X) + id); return 1; }
        return 0;
    }
    if (!fg_any() || g_Player.unk2 != 0) return 0;
    if ((kind & 0x7F) == 1) {
        switch (id) {
        case 8: if (!fus(fg_arm)) return 0; fg_sfx(x6 ? SFX_X6_SHOT : SFX_X5_SHOT); return 1;
        case 7: if (!fus(fg_arm)) return 0; fg_sfx(x6 ? SFX_X6_CHARGE : SFX_X5_CHARGE); return 1;
        case 9: if (!fus(fg_arm)) return 0; fg_sfx(x6 ? SFX_X6_SEMI : SFX_X5_SEMI); return 1;
        case 0x0A: if (!fus(fg_arm)) return 0; fg_sfx(fg_arm == 7 ? SFX_X6_ENGETSURIN : x6 ? SFX_X6_CHARGED : SFX_X5_CHARGED); return 1;
        case 5: if ((fg_body == 4 || fg_body == 8) && g_Player.unk5 == PLAYER_NOVA_STRIKE) return 1;   // o Nova do X5/X6 não toca o do dash
            return 0;
        }
        return 0;
    }
    if ((kind & 0x7F) == 0) {
        if (id == 0x1F && (fg_legs == 3 || fg_legs == 4 || fg_legs == 8)) { fg_sfx(x6c(fg_legs) ? SFX_X6_HOVER : SFX_X5_HOVER); return 1; }   // flutuar (a cada 9 quadros)
        if (id == 0x20 && (fg_body == 4 || fg_body == 8)) { fg_sfx(fg_body == 8 ? SFX_X6_GIGA_DASH : SFX_X5_NOVA); return 1; }
    }
    return 0;
}
void fg_sound_stop(int kind, int id)
{
    if (fus(fg_arm) && kind == 1 && id == 7) { fg_sfx(SFX_STOP | SFX_X5_CHARGE); fg_sfx(SFX_STOP | SFX_X6_CHARGE); }
}

static int fly_t, fly_snd;
static int fly_sub, fly_timer, fly_bob, fly_anim, fly_step, fly_tick;
static const s8 fly_bob_tbl[16] = { 0, 1, 0, 1, 1, 0, 1, 0, 0, -1, 0, -1, -1, 0, -1, 0 };
static const u8 fly_start[4] = { 47, 48, 49, 50 };
// 0 parado (anim 0xAA), 1 lado (0xAB: mesmos números, outra imagem -> +100), 2 cima (0xAC), 3 baixo (0xAD)
static const u8 fly_loop[4][5] = { { 51, 52, 53, 54, 55 }, { 151, 152, 153, 154, 155 }, { 56, 57, 58, 59, 60 }, { 61, 62, 63, 64, 65 } };
static const u8 fly_dur[5] = { 2, 3, 2, 2, 3 };

static void fly_anim_step(void)
{
    if (fly_anim < 0) {   // início: 4 quadros de 2
        fg_fly_frame = fly_start[fly_step];
        if (++fly_tick >= 2) { fly_tick = 0; fly_step++; }
        return;
    }
    fg_fly_frame = fly_loop[fly_anim][fly_step];
    if (++fly_tick >= fly_dur[fly_step]) { fly_tick = 0; fly_step = (fly_step + 1) % 5; }
}

s32 fg_falcon_enter(struct PlayerObj* self)
{
    if (!(self->pressed_input & PLAYER_INPUT_JUMP)) return 0;
    self->air_action = 4;
    self->x_vel.val = 0; self->y_vel.val = 0; self->unk28 = 0; self->unk2C = 0;
    self->dash_momentum = 0; self->afterimage = 0;
    player_set_animation(self, 0x15);   // animação qualquer do X4 (o desenho vem do X5)
    self->unk5 = PLAYER_HOVER; self->unk6 = 0;
    fg_fly_on = 1; fly_sub = 0; fly_timer = 180; fly_bob = 0;
    fly_anim = -1; fly_step = 0; fly_tick = 0; fg_fly_fx = -1; fly_t = 0; fly_snd = 1;
    // X5: 0x7A = 2 (mesmo campo do spike_immune do X4: não leva dano de contato nem de espinho) e
    // a arma 0x17 (caixa de 50x50 que acompanha o X e bate a cada 5 quadros) -> no X4, a caixa do Nova Strike (arma 22)
    self->spike_immune = 2;
    player_spawn_weapon(1, 0x16, 0, NULL);
    fly_anim_step();   // o quadro de entrada já conta (47 fica 2 quadros, como no X5)
    return 1;
}

// func_8003FE6C: 0 = parado (balança), 1 = lado, 2 = cima, 3 = baixo
static int fly_dir(struct PlayerObj* self)
{
    u16 h = self->input.buttons.held;
    u8 col = self->unk88.bytes.collision_flags;
    s32 v = FIXED(2.0) + FIXED(2.0) / 2, a;
    self->x_vel.val = 0; self->y_vel.val = 0;
    if (!(h & 0xF)) {
        self->y_pos.i.hi += fly_bob_tbl[fly_bob];
        fly_bob = (fly_bob + 1) & 0xF;
        return 0;
    }
    if (h & PLAYER_INPUT_LEFT) self->unk15 = 0;
    else if (h & PLAYER_INPUT_RIGHT) self->unk15 = PLAYER_FACING_RIGHT;
    a = (v >> 8) * 0xB5;
    if (h & PLAYER_INPUT_UP) {
        if (h & PLAYER_INPUT_RIGHT) { if (col & 5) return 0; self->x_vel.val = a; self->y_vel.val = a; }
        else if (h & PLAYER_INPUT_LEFT) { if (col & 6) return 0; self->x_vel.val = -a; self->y_vel.val = a; }
        else { if (col & 4) return 0; self->y_vel.val = v; }
        return 2;
    }
    if (h & PLAYER_INPUT_DOWN) {
        if (h & PLAYER_INPUT_RIGHT) { if (col & 9) return 0; self->x_vel.val = a; self->y_vel.val = -a; }
        else if (h & PLAYER_INPUT_LEFT) { if (col & 0xA) return 0; self->x_vel.val = -a; self->y_vel.val = -a; }
        else { if (col & 8) return 0; self->y_vel.val = -v; }
        return 3;
    }
    if (h & PLAYER_INPUT_RIGHT) { if (col & 1) return 0; self->x_vel.val = v; }
    else { if (col & 2) return 0; self->x_vel.val = -v; }
    return 1;
}

// ---- voo da Falcon Armor do X6 (dash no ar): 8 quadros parado, depois 18 quadros na horizontal a 6,5 px perdendo
// 0,1875 por quadro até 4,125; sem controle de altura; apertar o lado contrário encerra; ataca (arma 0x17, 50x50) mas não é
// invencível. Desenho: atlas "flight" 300+t (X + rastro + jato do X6, por quadro desde o início)
static int fly6, fly6_t;
static s32 fly6_v;
static void falcon6_start(struct PlayerObj* self, s32 v0)
{
    self->air_action = 3;
    self->x_vel.val = 0; self->y_vel.val = 0; self->unk28 = 0; self->unk2C = 0;
    self->dash_momentum = -1; self->afterimage = 0;
    player_clear_attack(self);
    player_set_animation(self, 0x12);
    self->unk5 = PLAYER_HOVER; self->unk6 = 0;
    fg_fly_on = 1; fly6 = 1; fly6_t = 0; fly6_v = v0;
    fg_fly_frame = 300; fg_fly_fx = -1;
    player_spawn_weapon(1, 0x16, 0, NULL);
}
// dash no ar: começa a 6,5; pulo no ar: começa parado e vai para 4,125 (X6: os dois entram no voo)
void fg_falcon6_enter(struct PlayerObj* self) { falcon6_start(self, FIXED(6.5)); }
s32 fg_falcon6_jump(struct PlayerObj* self)
{
    if (!(self->pressed_input & PLAYER_INPUT_JUMP)) return 0;
    if (self->air_action == 3 || self->air_action == 4) return 0;   // uma vez por pulo
    falcon6_start(self, 0);
    return 1;
}
static void fly6_end(struct PlayerObj* self)
{
    fg_fly_on = 0; fly6 = 0; fg_fly_frame = -1; fg_fly_fx = -1;
    self->x_vel.val = 0; self->y_vel.val = 0;
    player_enter_fall(self);
}
static void fg_falcon6_fly(struct PlayerObj* self)
{
    u8 col = self->unk88.bytes.collision_flags;
    u16 opp = self->unk15 ? PLAYER_INPUT_LEFT : PLAYER_INPUT_RIGHT;
    fly6_t++;
    if ((self->input.buttons.held & opp) || (col & (self->unk15 ? 1 : 2))) { fly6_end(self); return; }
    if (fly6_t == 8) fg_sfx(SFX_X6_DASH);   // som do dash (X6)
    if (fly6_t >= 9) {   // o 1o quadro do avanço ainda não anda; o quadro em que termina ainda anda
        self->x_pos.val += self->unk15 ? fly6_v : -fly6_v;
        fly6_v -= FIXED(0.1875);
        if (fly6_v < FIXED(4.125)) fly6_v = FIXED(4.125);
    }
    if (fly6_t >= 26 || (col & 8)) { fly6_end(self); return; }
    fg_fly_frame = 300 + fly6_t;
}


static int blade_on;
int fg_slash_t = -1; static int slash_state, slash_x;
static const u8 blade_giga_seq[108];
static const u8 blade_slash_seq[35];
static void fg_blade_dash(struct PlayerObj* self);
static void blade_fire(struct PlayerObj* self);
static void blade_giga(struct PlayerObj* self);
static int blade_weapon(struct WeaponObj* w, int k);
int fg_slash_frame = -1;
static int sh_mode;
int fg_fly_arm(void) { return sh_mode == 2 || sh_mode == 3; }   // quadro especial vem do braço (Engetsurin)
static void sh_fly(struct PlayerObj* self);
static int shadow_weapon(struct WeaponObj* w, int k);
static void shadow_giga(struct PlayerObj* self);
static void sh_start(struct PlayerObj* self, int mode);
static void sh_kunai_dir(struct WeaponObj* w, int right);
extern int fg_fx_t;
static const u8 shadow_giga_seq[222];
extern struct Unk_unk68 fg_shadow_kunai_box[];

void fg_falcon_fly(struct PlayerObj* self)
{
    int n;
    if (dive_on) { fg_dive(self); return; }
    if (sh_mode) { sh_fly(self); return; }
    if (blade_on) { fg_blade_dash(self); return; }
    if (fly6) { fg_falcon6_fly(self); return; }
    if (fg_legs == 1 && --fly_snd <= 0) { fly_snd = 9; fg_sfx(SFX_X5_FLY); }   // jato do X5 (a cada 9 quadros)
    if (fly_sub == 0) {
        fly_anim_step();
        if (fly_step >= 4) { fly_sub = 1; fly_anim = 0; fly_step = 0; fly_tick = 0; }
        fg_fly_fx = -1;
        return;
    }
    if (--fly_timer <= 0 || (self->pressed_input & PLAYER_INPUT_JUMP)) {
        fg_fly_on = 0; fg_fly_frame = -1; fg_fly_fx = -1;
        self->spike_immune = 0;
        self->x_vel.val = 0; self->y_vel.val = 0;
        player_enter_fall(self);
        return;
    }
    n = fly_dir(self);
    if (fly_sub == 1) {
        if (n) { fly_sub = n + 1; fly_anim = n; fly_tick = 0; }
    } else if (n) {
        if (n != fly_sub - 1) { fly_sub = n + 1; fly_anim = n; fly_tick = 0; }
        else { self->x_pos.val += self->x_vel.val; self->y_pos.val -= self->y_vel.val; }
    } else {
        fly_sub = 1; fly_anim = 0; fly_step = 0; fly_tick = 0;
    }
    fly_anim_step();
    fg_fly_fx = fly_anim * 15 + (fly_t + 13) % 15;
    fly_t++;
}

// caixa de ataque do voo (X5: D_80076E50 = {-25, -25, 50, 50})
struct Unk_unk68 fg_falcon_fly_box[] = { { -25, -25, 0x32, 0x32 } };

// ================= resto da Falcon Armor (X5) =================
#include "main/object_motion.h"
#include "main/objects.h"
#include "main/55C4.h"
extern struct BackgroundObj background_objects[3];
extern struct WeaponObj weapon_objects[0x10];
void buster_shot_place_at_muzzle(struct VisualObj*, struct PlayerObj*, arg_u8);
u8 get_random();

// marca nos objetos de arma criados aqui (pad99[0]): 0xFA = lança carregada, 0xFB = raio do Giga
#define FG_KIND(w) ((u8)(w)->pad99[0])
#define FG_AGE(w) ((w)->pad99[1])
#define FG_HIT(w) ((w)->pad99[2])
#define FG_VAR(w) ((w)->pad96[0])

// tiro carregado da Falcon: X5 arma 0x13 (init 0x80045120): 10 px/quadro, caixa D_80076E54 = {-24,-8,48,16},
// atravessa inimigos, id de acerto (+0x64) sobe a cada 4 quadros; nasce 6 quadros depois do disparo
struct Unk_unk68 fg_falcon_shot_box[] = { { -24, -8, 0x30, 0x10 } };
// raio do Giga Attack: X5 arma 0x31 (init 0x80045208): caixa D_80076E5C = {-8,-24,16,48}, 12 px/quadro na vertical
// Gaea (X5): tiro normal 0x2D (caixa = a do lemon, alcance 80 px) e Gaea Shot 0x2E (D_80076E68 = {-32,-32,64,64}, 112 px);
// init 0x80045670 / update 0x800457DC: some ao bater (0x98), some na parede, no fim do alcance toca a animação de sumir
struct Unk_unk68 fg_gaea_shot_box[] = { { -32, -32, 0x40, 0x40 } };
// Giga da Gaea: arma 0x2F, caixa D_80076E70 = {-36,-36,72,72} em X+22, uma nova a cada evento (12 quadros), ficam até o fim
struct Unk_unk68 fg_gaea_giga_box[] = { { -36, -36, 0x48, 0x48 } };
struct Unk_unk68 fg_falcon_laser_box[] = { { -8, -24, 0x10, 0x30 } };

int fg_dbg = -1, fg_dbg2;
int fg_muzzle_dx = 21, fg_muzzle_dy = -9;   // X4 no quadro do disparo de pé = (14, 0); X5 = (35, -9)
int fg_rel_t = -1;            // quadro do anel de liberação da carga (X5), -1 = nada
static int shot_wait, fired_now, fire_dx, fire_dy;
int fg_giga_on, fg_giga_frame = -1;
int fg_giga_t = -1;
static const u8 falcon6_giga_seq[195];
static int giga_sub, giga_t, giga_air, giga_cnt, giga_timer, giga_var, giga_step, giga_tick;

static int fg_x5_armor(void) { return fg_any(); }   // alguma peça do X5/X6 (pisca da carga)

// ---- habilidades novas do capacete e do corpo (iguais no X5/X6: psx_embed.cpp hab_*) ----
// armadura de onde veio a peça: 1 Shadow X6, 2 Blade X6, 3 Falcon X6, 4 Falcon X5, 5 Gaea X5, 6 Fourth X5, 7 Fourth X4.
// Com elas o capacete não economiza mais energia (nem a arma carregada de graça do capacete do X4) e o corpo não corta
// mais o dano (só a Couraça da Gaea). corpo: Shadow dobro de dano e +0,5 no dano causado | Blade Contra-ataque (levou
// golpe: carga cheia) | Falcon X6 tiros no ar +50% | Gaea 1/3 do dano | Fourth X4 Escudo (segura um golpe inteiro,
// volta 600 quadros depois). capacete: Blade carga 2x (player_weapon.c) | Falcon X5 Marca da presa | Gaea Firmeza.
enum { HAB_SHADOW = 1, HAB_BLADE, HAB_FALCON6, HAB_FALCON5, HAB_GAEA, HAB_FOURTH5, HAB_FOURTH4 };
static int hab_of(int c)
{
    switch (c) { case 7: return HAB_SHADOW; case 6: return HAB_BLADE; case 5: return HAB_FALCON6; case 1: return HAB_FALCON5;
                 case 2: return HAB_GAEA; case 3: return HAB_FOURTH5; case 9: return HAB_FOURTH4; }
    return 0;
}
int fg_hab_h(void) { return g_Player.unk2 == 0 ? hab_of(fg_head) : 0; }
int fg_hab_b(void) { return g_Player.unk2 == 0 ? hab_of(fg_body) : 0; }
int fg_hab_on(void) { return fg_hab_h() || fg_hab_b(); }
static int hab_acc3, hab_acc_air, hab_acc_sh;      // sobras: 1/3 da Couraça, +50% no ar, +0,5 da Shadow
int fg_shield_up = 1, fg_shield_t;                  // Escudo
static int hab_absorb, hab_ca;                      // golpe segurado pelo escudo / Contra-ataque pendente
static struct MainObj* hab_mark; static s8 hab_mark_id; static const void* hab_mark_tbl;   // Marca da presa
static u8 hab_won[0x10], hab_wair[0x10];            // tiros do X: aceso / disparado no ar
static int hab_dbg_base, hab_dbg_final, hab_dbg_n;  // último dano causado (testes)
static int hab_dash_prot, hab_dash_cool, hab_dash_prev, hab_dash_set;   // dash translúcido (capacete Shadow)
int fg_socorro_t;                                    // Socorro automático: quadros do brilho depois de usar o tanque
// Aerodinâmico (corpo Falcon X5) +20% / Couraça (corpo Gaea) -20% nas velocidades de andar e de dash (player_check.c,
// player_enter.c, player_common.c: FG_GAEA_V e FG_SPD passam por aqui)
s32 fg_spd(s32 v)
{
    int hb = fg_hab_b();
    if (hb == HAB_FALCON5) return v + v / 5;
    if (hb == HAB_GAEA) return v - v / 5;
    return v;
}

// func_80031670 (dano no X): devolve o dano a tirar da vida (0 vale), ou -1 = o jogo faz como sempre
int fg_bz_reduce(int dmg);
int fg_reduce_damage(int dmg)
{
    { extern int fg_nz_reduce(int); int r = fg_nz_reduce(dmg); if (r >= 0) return r; }   // Nightmare Zero
    { int r = fg_bz_reduce(dmg); if (r >= 0) return r; }   // Black Zero: corpo
    if (fg_hab_on()) {
        int hb = fg_hab_b(), d = dmg;
        if (d <= 0) return -1;
        if (d >= 127) return d;
        if (hb == HAB_FOURTH4 && fg_shield_up) { d = 0; fg_shield_up = 0; fg_shield_t = 600; hab_absorb = 1; }
        else if (hb == HAB_SHADOW) d *= 2;
        else if (hb == HAB_GAEA) { int t = d + hab_acc3; d = t / 3; hab_acc3 = t % 3; }
        if (hb == HAB_BLADE) hab_ca = 1;
        if (d > 126) d = 126;
        // Plasma reativo (corpo Fourth X5): levou dano de verdade -> 4 bolas de plasma em volta de onde o X estava
        if (hb == HAB_FOURTH5 && d > 0) { hab_orb_req = 1; hab_orb_x = g_Player.x_pos.i.hi; hab_orb_y = g_Player.y_pos.i.hi; hab_orb_bg = g_Player.bg_offset; }
        // Socorro automático (capacete Fourth X4): o golpe ia matar e um sub tank tem energia -> usa o mais cheio sozinho;
        // o X leva o golpe (recuo normal) e fica com a vida + tanque (até o máximo). Espinho/buraco não passam aqui.
        if (fg_hab_h() == HAB_FOURTH4 && d > 0) {
            int hp = g_Player.hp & 0x7F;
            if (hp - d <= 0) {
                int k = (engine_obj.sub_tanks[1] & 0x7F) > (engine_obj.sub_tanks[0] & 0x7F) ? 1 : 0;
                int e = engine_obj.sub_tanks[k] & 0x7F, mx = (u8)engine_obj.max_hp;
                if (e > 0 && hp - d + e > 0) {
                    int nv = hp - d + e; if (nv > mx) nv = mx;
                    engine_obj.sub_tanks[k] = (s8)(engine_obj.sub_tanks[k] & 0x80);
                    g_Player.hp = (s8)(nv + 1);   // o jogo tira 1
                    fg_socorro_t = 40;
                    return 1;
                }
            }
        }
        return d;
    }
    if (!fus(fg_body) || dmg <= 0) return -1;   // (sem as habilidades novas) corpo do X5/X6: metade do dano
    dmg /= 2;
    return dmg ? dmg : 1;
}

// func_80033D54 (entrada do dano): 1 = não muda o estado do X (escudo segurou / Firmeza); fica piscando invencível
extern u8 player_hurt_invincibility[5];
int fg_hurt_skip(struct PlayerObj* p)
{
    int t = p->hurt_type;
    { extern int fg_nz_hurt_skip(struct PlayerObj*); if (fg_nz_hurt_skip(p)) return 1; }   // Esquiva do Nightmare Zero
    if (hab_absorb) { hab_absorb = 0; p->hurt_phase = -1; p->invincibility_timer = 75; return 1; }
    if (fg_hab_h() == HAB_GAEA && (t == 1 || t == 2 || t == 4)) {
        p->hurt_phase = -1; p->invincibility_timer = (s8)player_hurt_invincibility[t];
        func_8001540C(3, (get_random() & 1) ^ 1, p);   // voz de dano, como no X5/X6
        return 1;
    }
    return 0;
}

// tiro disparado no ar? (marca quando o tiro aparece; se ele bate no mesmo quadro, marca aqui)
static int hab_weapon_air(struct WeaponObj* w)
{
    int i = (int)(w - weapon_objects);
    if (i < 0 || i >= 0x10) return !(g_Player.unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND);
    if (!hab_won[i]) { hab_won[i] = 1; hab_wair[i] = !(g_Player.unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND); }
    return hab_wair[i];
}
// func_8002DE30 (tiro do X no inimigo): dano da tabela do inimigo -> dano com as habilidades
int fg_hit_damage(struct MainObj* en, struct WeaponObj* w, int d)
{
    int hh, hb;
    if (!fg_hab_on() || d <= 0 || d >= 127 || (w && FG_KIND(w) == 0xD9)) return d;   // (golpe do parceiro: sem as nossas habilidades)
    if (w && (FG_KIND(w) == 0xE9)) d = 1;                              // bola de plasma
    else if (w && FG_KIND(w) == 0xE8) d = 2;   // explosão da Reação em cadeia
    else if (w && FG_KIND(w) == 0xEA) d = 4;   // Mergulho (como um tiro carregado)
    hab_dbg_base = d;
    hh = fg_hab_h(); hb = fg_hab_b();
    if (hh == HAB_FALCON5) {
        if (hab_mark == NULL) { hab_mark = en; hab_mark_id = en->id; hab_mark_tbl = en->collision_data; }
        if (en == hab_mark) d *= 2;
    }
    if (hb == HAB_FALCON6 && hab_weapon_air(w)) { int t = d * 3 + hab_acc_air; d = t / 2; hab_acc_air = t % 2; }
    if (hb == HAB_SHADOW) { int t = d * 2 + 1 + hab_acc_sh; d = t / 2; hab_acc_sh = t % 2; }
    if (d > 126) d = 126;
    hab_dbg_n++; hab_dbg_final = d;
    return d;
}
// por quadro (fg_tick): tiros novos, marca, escudo voltando, Contra-ataque
static void hab_tick(struct PlayerObj* self)
{
    int ground, i;
    if (!fg_hab_on()) { hab_mark = NULL; fg_shield_up = 1; fg_shield_t = 0; hab_ca = 0; hab_absorb = 0; return; }
    ground = (self->unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND) != 0;
    for (i = 0; i < 0x10; i++) { int on = weapon_objects[i].active != 0; if (on && !hab_won[i]) hab_wair[i] = !ground; hab_won[i] = (u8)on; }
    if (fg_hab_h() != HAB_FALCON5) hab_mark = NULL;
    if (hab_mark && (!hab_mark->active || hab_mark->id != hab_mark_id || hab_mark->collision_data != hab_mark_tbl || hab_mark->hp <= 0)) hab_mark = NULL;
    if (fg_hab_b() == HAB_FOURTH4) { if (!fg_shield_up && --fg_shield_t <= 0) { fg_shield_up = 1; fg_shield_t = 0; } }
    else { fg_shield_up = 1; fg_shield_t = 0; }
    // Contra-ataque: assim que o X pode agir de novo, a carga fica cheia (só o estado: o próximo aperto já sai cheio)
    if (hab_ca && fg_hab_b() == HAB_BLADE && self->unk5 != 0x11 && self->hp > 0) {
        self->charge_state[0] = PLAYER_CHARGE_FULL;
        if (self->arm_type == 1) self->stock_charge = 4;
        hab_ca = 0;
    }
    if (fg_hab_b() != HAB_BLADE) hab_ca = 0;
    if (self->hp == 0 || self->hp == -0x80) { fg_shield_up = 1; fg_shield_t = 0; hab_ca = 0; hab_mark = NULL; hab_absorb = 0; }
    if (fg_socorro_t > 0) fg_socorro_t--;
    if (hab_orb_req) {   // Plasma reativo: 4 bolas em volta de onde o X levou o golpe
        static const s8 ox[4] = { -24, 24, -24, 24 }, oy[4] = { -26, -26, 22, 22 };
        int i;
        hab_orb_req = 0;
        if (fg_hab_b() == HAB_FOURTH5) for (i = 0; i < 4; i++) hab_box_spawn(0xE9, hab_orb_x + ox[i], hab_orb_y + oy[i], hab_orb_bg, fg_orb_box);
    }
    // dash translúcido (capacete Shadow): o dash que começa sem espera fica invencível (spike_immune = 1: a função de
    // dano sai na hora); acabou -> 60 quadros de espera. Dash, dash no ar, voo da Falcon X6 e dash da Blade (fangame)
    {
        int dashing = self->unk5 == PLAYER_DASH || self->unk5 == PLAYER_AIR_DASH || (self->unk5 == PLAYER_HOVER && (fly6 || blade_on));
        if (fg_hab_h() == HAB_SHADOW) {
            if (dashing && !hab_dash_prev && hab_dash_cool == 0) hab_dash_prot = 1;
            if (!dashing && hab_dash_prev && hab_dash_prot) { hab_dash_prot = 0; hab_dash_cool = 60; }
        } else hab_dash_prot = 0;
        if (hab_dash_cool > 0) hab_dash_cool--;
        hab_dash_prev = dashing;
        if (hab_dash_prot) { if (self->spike_immune == 0) { self->spike_immune = 1; hab_dash_set = 1; } }
        else if (hab_dash_set) { if (self->spike_immune == 1) self->spike_immune = 0; hab_dash_set = 0; }
    }
}
// Godot: escudo (0 sem, 1 de pé, 2 voltando), tempo, marca na tela (x, y; -100000 = nenhuma)
long long fg_hab_query(int k)
{
    switch (k) {
    case 0: return fg_hab_h();
    case 1: return fg_hab_b();
    case 2: return fg_hab_b() != HAB_FOURTH4 ? 0 : fg_shield_up ? 1 : 2;
    case 3: return fg_shield_t;
    case 4: case 5: {
        int v;
        if (hab_mark == NULL) return -100000;
        v = k == 4 ? hab_mark->x_pos.i.hi : hab_mark->y_pos.i.hi;
        if (hab_mark->bg_offset >= 0) v -= k == 4 ? background_objects[hab_mark->bg_offset].x_pos.i.hi : background_objects[hab_mark->bg_offset].y_pos.i.hi;
        return v; }
    case 6: return hab_ca;
    case 7: return hab_dbg_base;
    case 8: return hab_dbg_final;
    case 9: return hab_dbg_n;
    case 10: return g_Player.charge_timer;
    case 11: return g_Player.charge_state[0];
    case 12: { int i; for (i = 0; i < 0x10; i++) if (weapon_objects[i].active) return weapon_objects[i].id; return -1; }
    case 15: return hab_dash_prot;   // X translúcido
    case 17: return fg_dive_t;       // Mergulho (quadros; -1 = não)
    case 16: return fg_socorro_t;
    case 13: return g_Player.stock_charge;
    case 14: return g_Player.weapon_energy[0];
    }
    return 0;
}

// func_8003E6FC: armaduras do X5 gastam 2/3 da energia das armas especiais (com resto acumulado)
static int energy_frac[16];
int fg_energy_cost(int weapon, int cost)
{
    int t;
    if (fg_hab_on()) return cost;   // capacete novo: sem economia
    if (!fus(fg_head) || cost <= 0) return cost;   // capacete do X5/X6: gasta menos arma especial
    t = cost * 2 + energy_frac[weapon & 15];
    energy_frac[weapon & 15] = t % 3;
    return t / 3;
}

int fg_has_giga(void) { return fg_armor == 1 || fg_armor == 2 || fg_armor == 5 || fg_armor == 6 || fg_armor == 7; }

static void fg_despawn(struct WeaponObj* w, int count_shot)
{
    w->pad99[0] = 0; w->unk50 = 0;
    if (count_shot && g_Player.shot_count) g_Player.shot_count--;
    ZeroObjectState(OBJECT_HEADER(w));
}

static struct WeaponObj* fg_new_weapon(void)
{
    struct WeaponObj* w = find_free_weapon_obj();
    if (!w) return NULL;
    w->active = 1; w->id = 0x12; w->unk2 = 1; w->state = 1; w->on_screen = 1;
    w->bg_offset = g_Player.bg_offset; w->owner = NULL;
    w->unk3C = NULL; w->animation_table = NULL;   // desenho fica com o Godot (atlas do X5)
    w->unk28.val = 0; w->unk2C = 0; w->x_vel.val = 0; w->y_vel.val = 0;
    w->unk64 = 1; FG_HIT(w) = 1; FG_AGE(w) = 0; FG_VAR(w) = 0;
    return w;
}

// ---- habilidades novas, lote 3: Mergulho (capacete Falcon X6), Reação em cadeia (capacete Fourth X5) e Plasma reativo
// (corpo Fourth X5). Caixas nossas (arma 0x12, dano trocado em fg_hit_damage) desenhadas pelo Godot; os mesmos números
// estão no X5/X6 (psx_embed.cpp hab_*). ----
struct Unk_unk68 fg_orb_box[] = { { -16, -16, 32, 32 } };
struct Unk_unk68 fg_boom_box[] = { { -32, -32, 64, 64 } };
struct Unk_unk68 fg_dive_box[] = { { -16, -24, 32, 48 } };
static struct WeaponObj* hab_box_spawn(int kind, int x, int y, s8 bg, const struct Unk_unk68* box)
{
    struct WeaponObj* w = fg_new_weapon();
    if (!w) return NULL;
    w->pad99[0] = (s8)kind; FG_AGE(w) = 0; FG_HIT(w) = 1;
    w->x_pos.val = 0; w->y_pos.val = 0; w->x_pos.i.hi = (s16)x; w->y_pos.i.hi = (s16)y;
    w->bg_offset = bg; w->unk15 = g_Player.unk15;
    w->unk50 = (const u8*)box;
    return w;
}
// (testes: x4_mem 88 = bolas em volta do X, 89 = explosão 60 px na frente)
void fg_test_hab(int k)
{
    if (k == 0) { hab_orb_req = 1; hab_orb_x = g_Player.x_pos.i.hi; hab_orb_y = g_Player.y_pos.i.hi; hab_orb_bg = g_Player.bg_offset; }
    else hab_box_spawn(0xE8, g_Player.x_pos.i.hi + (g_Player.unk15 ? 60 : -60), g_Player.y_pos.i.hi, g_Player.bg_offset, fg_boom_box);
}
// Reação em cadeia: o inimigo destruído pelo X explode em plasma (a explosão que destrói outro faz outra explosão)
void fg_hab_kill(struct MainObj* en)
{
    if (en == NULL || fg_hab_h() != HAB_FOURTH5) return;
    hab_box_spawn(0xE8, en->x_pos.i.hi, en->y_pos.i.hi, en->bg_offset, fg_boom_box);
}
// Mergulho: no ar, baixo + dash -> o X mergulha na diagonal para baixo na pose do dash no ar (6 px/quadro para a frente
// e para baixo) até o chão ou 40 quadros; parede na frente: continua só descendo. A caixa 0xEA machuca na frente.
s32 fg_dive_try(struct PlayerObj* self)
{
    s8 a = self->unk5;
    if (fg_hab_h() != HAB_FALCON6 || dive_on || self->unk2 != 0 || self->input_locked || self->hp <= 0) return 0;
    if (!(self->input.buttons.held & PLAYER_INPUT_DOWN) || !(self->pressed_input & PLAYER_INPUT_DASH)) return 0;
    if (self->unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND) return 0;
    if (!(a == PLAYER_JUMP || a == PLAYER_FALL || a == PLAYER_WALL_JUMP || a == PLAYER_AIR_DASH || (a == PLAYER_HOVER && !fg_fly_on))) return 0;
    if (self->input.buttons.held & PLAYER_INPUT_RIGHT) self->unk15 = PLAYER_FACING_RIGHT;
    if (self->input.buttons.held & PLAYER_INPUT_LEFT) self->unk15 = 0;
    self->x_vel.val = 0; self->y_vel.val = 0; self->unk28 = 0; self->unk2C = 0;
    self->dash_momentum = 0; self->afterimage = 1; self->air_action = 3;
    player_clear_attack(self);
    player_set_animation(self, 0x12);   // pose do dash no ar
    self->unk5 = PLAYER_HOVER; self->unk6 = 0;
    fg_fly_on = 1; fg_fly_fx = -1; fg_fly_frame = -1;
    dive_on = 1; dive_t = 0; fg_dive_t = 0;
    hab_box_spawn(0xEA, self->x_pos.i.hi, self->y_pos.i.hi, self->bg_offset, fg_dive_box);
    func_8001540C(1, 5, self);   // som do dash
    return 1;
}
static void dive_end(struct PlayerObj* self)
{
    dive_on = 0; fg_dive_t = -1; fg_fly_on = 0;
    if (self->afterimage > 0) self->afterimage = -1;
    self->x_vel.val = 0; self->y_vel.val = 0; self->unk2C = 0x4200;
    if (self->unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND) player_enter_land(self);
    else player_enter_fall(self);
}
static void fg_dive(struct PlayerObj* self)
{
    u8 col = self->unk88.bytes.collision_flags;
    if ((col & PLAYER_COLLIDE_GROUND) || dive_t >= HAB_DIVE_MAX) { dive_end(self); return; }
    if (!(col & (self->unk15 ? PLAYER_COLLIDE_RIGHT : PLAYER_COLLIDE_LEFT))) self->x_pos.val += self->unk15 ? FIXED(6) : -FIXED(6);
    self->y_pos.val += FIXED(6);
    dive_t++; fg_dive_t = dive_t;
}

// player_fire_charged_buster com tiro 0x12: no X5 não há o clarão do X4, há o anel e a lança 6 quadros depois
int fg_falcon_charge_fire(struct PlayerObj* self)
{
    if (fg_arm == 6 && self->shot_type == 0x12) { blade_fire(self); return 1; }
    if (fg_arm == 7 && self->shot_type == 0x12) {   // Shadow: Engetsurin (golpe, sem projétil contado)
        sh_start(self, (self->unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND) ? 2 : 3);
        return 1;
    }
    if (!(((fg_arm == 1 || fg_arm == 2 || fg_arm == 5) && self->shot_type == 0x12) || ((fg_arm == 3 || fg_arm == 4 || fg_arm == 8) && self->shot_type == 0x14))) return 0;
    {   // cano no quadro do disparo (o X4 dá por quadro de animação; o X5 usa a pose do disparo)
        static struct WeaponObj tmp;
        tmp.unk15 = self->unk15;
        buster_shot_place_at_muzzle((struct VisualObj*)&tmp, self, 0x12);
        fire_dx = self->unk15 ? tmp.x_pos.i.hi - self->x_pos.i.hi : self->x_pos.i.hi - tmp.x_pos.i.hi;
        fire_dy = tmp.y_pos.i.hi - self->y_pos.i.hi;
        fg_dbg = fire_dx * 1000 + fire_dy;
    }
    fg_rel_t = 0;
    shot_wait = 7;   // X5: a lança aparece no 7o quadro depois do disparo
    fired_now = 1;
    func_8001540C(1, 0x0A, self);
    if (get_random() & 1) player_play_voice(self, 8);
    return 1;
}

// Fourth/Ultimate do X5: o tiro cheio é o Plasma do X4 (arma 0x14, 11 px/quadro, deixa bolas ao bater) com a caixa do X5
// (D_80076E34 = {-28,-24,62,48}; X4 = {-36,-32,78,64}); nasce no tempo/lugar do X5 e o X4 cuida da lógica
struct Unk_unk68 fg_x5_plasma_box[] = { { -28, -24, 0x3E, 0x30 } };
static void plasma_spawn(void)
{
    struct PlayerObj* p = &g_Player;
    struct WeaponObj* w = find_free_weapon_obj();
    int dx = fire_dx + fg_muzzle_dx;
    if (!w) { if (p->shot_count) p->shot_count--; return; }
    w->active = 0x21; w->id = 0x14; w->unk2 = 0; w->state = 0;
    w->bg_offset = p->bg_offset; w->unk15 = p->unk15;
    w->x_pos.val = p->x_pos.val; w->y_pos.val = p->y_pos.val;
    w->x_pos.i.lo = 0; w->y_pos.i.lo = 0;
    w->x_pos.i.hi += p->unk15 ? dx : -dx;
    w->y_pos.i.hi += fire_dy + fg_muzzle_dy;
    w->pad99[0] = 0xF9; FG_AGE(w) = 0;
}
// update do Plasma do X4 (antes da lógica dele): marca, caixa do X5, idade para o quadro do desenho
void fg_plasma_tick(struct WeaponObj* w)
{
    if (FG_KIND(w) != 0xF9) return;
    if (w->id != 0x14 || !w->active) { w->pad99[0] = 0; return; }
    if (w->state >= 1) { w->unk50 = (const u8*)fg_x5_plasma_box; FG_AGE(w)++; }
}

static void falcon_spawn_shot(void)
{
    int gaea = fg_arm == 2;
    if (fg_arm == 3 || fg_arm == 4 || fg_arm == 8) { plasma_spawn(); return; }   // Ultimate do X6 = Plasma do X5 (mesma caixa, tempo e lugar)
    struct WeaponObj* w = fg_new_weapon();
    struct PlayerObj* p = &g_Player;
    if (!w) { if (p->shot_count) p->shot_count--; return; }
    w->unk15 = p->unk15;
    // posição do X5 (de pé: X + 35, X - 9); o X4 dá o cano por quadro da animação -> usa o do X4 + diferença medida
    w->x_pos.val = p->x_pos.val; w->y_pos.val = p->y_pos.val;
    w->x_pos.i.lo = 0; w->y_pos.i.lo = 0;
    {
        int dx = fire_dx + fg_muzzle_dx;
        w->x_pos.i.hi += p->unk15 ? dx : -dx;
        w->y_pos.i.hi += fire_dy + fg_muzzle_dy;
    }
    w->x_vel.val = p->unk15 ? FIXED(10) : FIXED(-10);
    w->unk50 = (const u8*)(gaea ? fg_gaea_shot_box : fg_falcon_shot_box);
    w->unk8A = w->x_pos.i.hi;
    w->pad99[0] = gaea ? 0xFD : (fg_arm == 5 ? 0xF8 : 0xFA);
}

static void giga_spawn_laser(int var)
{
    struct WeaponObj* w = fg_new_weapon();
    struct BackgroundObj* bg = &background_objects[g_Player.bg_offset < 0 ? 0 : g_Player.bg_offset];
    if (!w) return;
    w->unk15 = 0;
    w->x_pos.val = 0; w->y_pos.val = 0;
    w->x_pos.i.hi = bg->x_pos.i.hi + 8 + (get_random() % 20) * 16;
    if (var == 0) { w->y_pos.i.hi = bg->y_pos.i.hi - 32; w->y_vel.val = FIXED(-12); }   // cai do topo
    else { w->y_pos.i.hi = bg->y_pos.i.hi + 272; w->y_vel.val = FIXED(12); }          // sobe do fundo
    w->unk50 = (const u8*)fg_falcon_laser_box;
    FG_VAR(w) = var;
    w->pad99[0] = 0xFB;
}

// chamado no começo de charge_shot_update; devolve 1 se o objeto é nosso
// tiros da Gaea: alcance, depois anima sumindo (FG_VAR = 1) sem mover; some ao bater
static int gaea_shot_update(struct WeaponObj* w, int range, int fade_len)
{
    if (FG_VAR(w)) {
        if (++FG_AGE(w) > fade_len) fg_despawn(w, 1);
        return 1;
    }
    if (w->unk98 != 0) { fg_despawn(w, 1); return 1; }
    if (FG_AGE(w)++ == 0) return 1;
    w->x_pos.val += w->x_vel.val;
    if (func_8002B1E8(BASE_OBJECT(w), 0x20, 0x14)) { fg_despawn(w, 1); return 1; }
    {
        int d = w->x_pos.i.hi - w->unk8A;
        if (d < 0) d = -d;
        if (d > range) { FG_VAR(w) = 1; FG_AGE(w) = 0; w->unk50 = 0; }
    }
    return 1;
}

struct Unk_unk68 fg_bz_col_box[] = { { -9, -48, 18, 96 } };
int fg_weapon_update(struct WeaponObj* w)
{
    int k = FG_KIND(w);
    if (w->state == 0) { w->pad99[0] = 0; return 0; }   // tiro normal do X4 (marca velha não vale)
    if (k >= 0xF4 && k <= 0xF7) return blade_weapon(w, k);
    if (k >= 0xF0 && k <= 0xF3) return shadow_weapon(w, k);
    if (k >= 0xE0 && k <= 0xE2) { w->unk98 = 0; FG_AGE(w)++; return 1; }   // eco / clone / corte do Nightmare Zero (fg_nz_*)
    if (k == 0xD9) { w->unk98 = 0; if (++FG_AGE(w) > 3) fg_despawn(w, 0); return 1; }   // co-op: golpe do parceiro (o Godot renova)
    if (k == 0xD8) {   // co-op: golpe final do parceiro no chefe (até 40 quadros: o chefe pode estar invencível um pouco)
        extern int fg_coop_boss_alive(void);
        w->unk98 = 0;
        if (++FG_AGE(w) > 40 || !fg_coop_boss_alive()) { fg_despawn(w, 0); return 1; }
        if (FG_AGE(w) % 4 == 0) w->unk64 = (s8)(0x70 + (FG_AGE(w) / 4) % 8);
        return 1;
    }
    if (k == 0xEF) {   // onda do sabre do Black Zero: atravessa inimigos, alcance ~190 px, some na parede
        if (--FG_HIT(w) <= 0) { FG_HIT(w) = 4; w->unk64++; }
        if (w->unk98 != 0) w->unk98 = 0;
        if (FG_AGE(w)++ == 0) return 1;
        w->x_pos.val += w->x_vel.val;
        if (FG_AGE(w) > 27 || func_8002B1E8(BASE_OBJECT(w), 0x20, 0x14)) fg_despawn(w, 0);
        return 1;
    }
    if (k == 0xEE) {   // coluna do Giga: espera a vez (FG_VAR), cai rápido pela tela e some
        if (--FG_HIT(w) <= 0) { FG_HIT(w) = 3; w->unk64++; }
        w->unk98 = 0;
        if (FG_VAR(w) > 0) { FG_VAR(w)--; w->unk50 = 0; return 1; }
        w->unk50 = (const u8*)fg_bz_col_box;
        FG_AGE(w)++;
        w->y_pos.val += w->y_vel.val;
        if (FG_AGE(w) > 34) fg_despawn(w, 0);
        return 1;
    }
    if (k == 0xE8 || k == 0xE9) {   // explosão da Reação em cadeia / bola do Plasma reativo: paradas, acertam de novo a cada N quadros
        w->unk98 = 0;
        if (--FG_HIT(w) <= 0) { FG_HIT(w) = k == 0xE9 ? 6 : 8; w->unk64++; }
        if (++FG_AGE(w) > (k == 0xE9 ? HAB_ORB_LIFE : HAB_BOOM_LIFE)) fg_despawn(w, 0);
        return 1;
    }
    if (k == 0xEA) {   // caixa do Mergulho: grudada no X enquanto ele mergulha
        if (!dive_on) { fg_despawn(w, 0); return 1; }
        w->unk98 = 0;
        if (--FG_HIT(w) <= 0) { FG_HIT(w) = 8; w->unk64++; }
        w->x_pos.val = g_Player.x_pos.val; w->y_pos.val = g_Player.y_pos.val; w->unk15 = g_Player.unk15;
        w->bg_offset = g_Player.bg_offset;
        return 1;
    }
    if (k < 0xF8 || k > 0xFE || k == 0xF9) return 0;
    if (--FG_HIT(w) <= 0) { FG_HIT(w) = 4; if (FG_AGE(w)) w->unk64++; }
    switch (k) {
    case 0xF8:   // lança da Falcon X6: atravessa, alcance de 80 px e some
        if (w->unk98 < 0) { fg_despawn(w, 1); return 1; }
        if (w->unk98 > 0) w->unk98 = 0;
        if (FG_AGE(w)++ == 0) return 1;
        w->x_pos.val += w->x_vel.val;
        {
            int d = w->x_pos.i.hi - w->unk8A;
            if (d < 0) d = -d;
            if (d > 80 || func_8002B1E8(BASE_OBJECT(w), 0x20, 0x14)) fg_despawn(w, 1);
        }
        return 1;
    case 0xFA:   // lança da Falcon: atravessa
        if (w->unk98 < 0) { fg_despawn(w, 1); return 1; }   // rebatido
        if (w->unk98 > 0) w->unk98 = 0;
        if (FG_AGE(w)++ == 0) return 1;   // quadro em que nasce: parado (como o init do X5)
        w->x_pos.val += w->x_vel.val;
        if (func_8002B1E8(BASE_OBJECT(w), 0x20, 0x14)) fg_despawn(w, 1);
        return 1;
    case 0xFB:   // raio do Giga da Falcon
        w->unk98 = 0;
        if (FG_AGE(w)++ == 0) return 1;
        w->y_pos.val -= w->y_vel.val;
        if (FG_AGE(w) > 31) fg_despawn(w, 0);
        return 1;
    case 0xFC: return gaea_shot_update(w, 80, 16);    // tiro normal da Gaea (sumir: 4 quadros x 4)
    case 0xFD: return gaea_shot_update(w, 112, 20);   // Gaea Shot (sumir: 4 quadros x 5)
    case 0xFE:   // caixa do Giga da Gaea: parada na frente do X
        w->unk98 = 0;
        FG_AGE(w)++;
        if (!fg_giga_on) fg_despawn(w, 0);
        return 1;
    }
    return 1;
}

// lemon do X4 com a Gaea: vira o tiro 0x2D do X5 (chamado no update do lemon depois do init)
int fg_lemon_update(struct WeaponObj* w)
{
    // shuriken das pernas Shadow (pendurado no teto: 3 para baixo) com qualquer braço: é nosso (sem isso o update do
    // lemon do X4 rodava num objeto sem animação e o jogo travava; vídeo do usuário, braço Fourth do X4)
    if (FG_KIND(w) == 0xF3 && w->state != 0) return fg_weapon_update(w);
    if (fg_arm == 7 && w->state != 0) {   // Shadow: o lemon vira o shuriken
        if (FG_KIND(w) != 0xF3) {
            w->pad99[0] = 0xF3; FG_AGE(w) = 0; FG_VAR(w) = 0; FG_HIT(w) = 1;
            w->unk3C = NULL; w->unk50 = (const u8*)fg_shadow_kunai_box;
            sh_kunai_dir(w, w->unk15 != 0);
            return 1;   // quadro em que nasce: parado
        }
        return fg_weapon_update(w);
    }
    if (fg_arm != 2 || w->state == 0) return 0;
    if (FG_KIND(w) != 0xFC) {
        w->pad99[0] = 0xFC; FG_AGE(w) = 0; FG_VAR(w) = 0; FG_HIT(w) = 1;
        w->x_pos.i.hi += w->unk15 ? 1 : -1;   // X5: nasce em X+21 (o lemon do X4 em X+20) e fica parado no 1o quadro
        w->unk8A = w->x_pos.i.hi;
        w->unk3C = NULL;   // desenho fica com o Godot
    }
    return fg_weapon_update(w);
}

// lista para o Godot: n-ésimo objeto nosso (tela x, y, tipo*256+quadro, virado)
static int fg_drawn(struct WeaponObj* w)
{
    int k = FG_KIND(w);
    return w->active && w->state != 0 && ((k >= 0xFA && k <= 0xFD) || k == 0xF8 || k == 0xF7 || k == 0xF3 || k == 0xEF || k == 0xEE || k == 0xE8 || k == 0xE9 || (k == 0xF9 && w->id == 0x14));
}
int fg_obj_query(int idx, int field)
{
    int n = 0;
    for (int i = 0; i < 0x10; i++) {
        struct WeaponObj* w = &weapon_objects[i];
        int k, fr, a;
        struct BackgroundObj* bg;
        if (!fg_drawn(w)) continue;
        if (n++ != idx) continue;
        if (field < 0) return 1;
        bg = &background_objects[w->bg_offset < 0 ? 0 : w->bg_offset];
        a = FG_AGE(w) > 0 ? FG_AGE(w) - 1 : 0;
        switch (FG_KIND(w)) {
        case 0xFA: k = 1; fr = (a / 3) % 4; break;
        case 0xFB: k = 2; fr = (a / 3) % 4 + (FG_VAR(w) ? 4 : 8); break;
        case 0xF8: k = 1; fr = (a / 3) % 3; break;
        case 0xF3: k = 7; fr = a <= 5 ? a * 2 : a <= 12 ? a + 5 : 12 + (a - 13) % 6; break;   // shuriken: atlas da Shadow (qualquer braço)
        case 0xF7: k = 1; fr = FG_VAR(w) ? 10 + (a > 13 ? 13 : a) : (a < 2 ? 0 : a < 7 ? 1 : 2); break;   // explosão: quadros 10-23 por tempo
        case 0xF9: k = 4; fr = 15 + (a / 3) % 4; break;
        case 0xEF: k = 5; fr = a; break;   // onda do sabre do Black Zero (desenhada pelo Godot)
        case 0xEE: k = 6; fr = a; break;   // coluna negra do Giga do Black Zero
        case 0xE9: k = 8; fr = a; break;   // bola do Plasma reativo (desenhada pelo Godot)
        case 0xE8: k = 9; fr = a; break;   // explosão da Reação em cadeia
        case 0xFC: k = 3; fr = FG_VAR(w) ? 20 + (a / 4 > 3 ? 3 : a / 4) : (a / 4) % 3; break;
        default:   k = 3; fr = FG_VAR(w) ? 52 + (a / 5 > 3 ? 3 : a / 5) : 32 + (a / 4) % 3; break;
        }
        switch (field) {
        case 0: return w->x_pos.i.hi - bg->x_pos.i.hi;
        case 1: return w->y_pos.i.hi - bg->y_pos.i.hi;
        case 2: return k * 256 + fr;
        default: return w->unk15 ? 1 : 0;
        }
    }
    if (field < 0) return n;
    return 0;
}

// ---- Giga Attack da Falcon (X5 func_8003E1A8 -> estado 0x24: 0x8004116C / 0x80041238 / 0x80041330) ----
static const u8 giga_start_seq[] = { 66, 68, 70 };
// Giga da Gaea (X5 estado 0x25, subtabela D_80074D44): a animação é guiada por eventos e sempre igual -> quadros do X5
// gravados (chão e ar dão a mesma sequência, o X fica parado); caixas 0x2F nascem nos quadros abaixo
static const u8 gaea_giga_seq[207] = { 47, 48, 49, 47, 48, 49, 50, 51, 52, 50, 51, 52, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 55, 53, 54, 56, 57, 58, 59, 60, 61, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 68, 68, 64, 64, 67, 67, 63, 63, 69, 69, 62, 62, 65, 65, 66, 66, 62, 62, 62, 62, 62, 62, 62, 62, 62, 62, 62, 62, 62 };
static const u8 gaea_giga_spawn[10] = { 68, 80, 92, 104, 116, 128, 140, 152, 164, 176 };

static void giga_anim(void)
{
    // quadros do X5 (atlas "flight"): no ar é +1 em 66/68/70; 72/73 iguais
    int f;
    if (giga_sub == 0) {   // 66 x3, depois 68/70 a cada 2
        if (giga_t < 3) f = 66; else f = ((giga_t - 3) / 2) % 2 ? 70 : 68;
    } else if (giga_sub == 1) {   // 68, 70, depois 72/73 a cada 2
        int s = giga_cnt / 2;
        f = s == 0 ? 68 : s == 1 ? 70 : (s % 2 ? 73 : 72);
    } else f = 66;
    if (giga_air && f <= 71) f++;
    fg_giga_frame = f;
}

s32 fg_falcon_giga_enter(struct PlayerObj* self)
{
    if (!fg_has_giga()) return 0;
    if (self->shot_cooldown) return 0;
    if (self->weapon_energy[0] != 0x30) return 0;
    if (!(self->pressed_input & PLAYER_INPUT_GIGA)) return 0;
    player_set_animation(self, 0x15);
    player_clear_attack(self);
    player_reset_weapon(self);
    self->dash_momentum = 0; self->air_action = 5; self->afterimage = 0;
    self->invincibility_timer = 0; self->hurt_phase = 0;
    if (engine_obj.unk37 == 0) self->weapon_energy[0] = 0;
    self->spike_immune = 2;
    self->nova_strike_active = 1;
    self->x_vel.val = 0; self->y_vel.val = 0; self->unk28 = 0; self->unk2C = 0;
    giga_air = !(self->unk88.bytes.collision_flags & 8);
    self->air_state = giga_air;
    self->unk5 = PLAYER_NOVA_STRIKE; self->unk6 = 0;
    fg_giga_on = 1; giga_sub = 0; giga_t = 0; giga_cnt = 0;
    fg_giga_t = (fg_armor == 2 || fg_armor == 6 || fg_armor == 7) ? 0 : -1;
    fg_fly_on = 0; fg_fly_frame = -1; fg_fly_fx = -1;
    if (fg_armor == 2) fg_giga_frame = gaea_giga_seq[0]; else if (fg_armor == 7) fg_giga_frame = shadow_giga_seq[0]; else if (fg_armor == 6) fg_giga_frame = blade_giga_seq[0]; else if (fg_armor == 5) fg_giga_frame = falcon6_giga_seq[0]; else giga_anim();
    return 1;
}

static void giga_end(struct PlayerObj* self)
{
    fg_giga_on = 0; fg_giga_frame = -1; fg_giga_t = -1;
    self->spike_immune = 0;
    self->nova_strike_active = 0;
    player_enter_land_or_fall(self);
}

// chamado no lugar de player_nova_strike enquanto fg_giga_on
// Giga da Falcon X6: igual ao do X5 (raios 0x31), mas a preparação dura 66 quadros; quadros do X6 gravados
static const u8 falcon6_giga_seq[195] = { 85, 85, 85, 85, 85, 87, 87, 87, 87, 89, 89, 89, 89, 87, 87, 87, 87, 89, 89, 89, 89, 87, 87, 87, 87, 89, 89, 89, 89, 87, 87, 87, 89, 89, 87, 87, 89, 89, 87, 87, 89, 89, 87, 87, 89, 89, 87, 87, 89, 89, 87, 87, 89, 89, 87, 87, 89, 89, 87, 87, 89, 89, 87, 87, 89, 89, 87, 87, 87, 87, 89, 89, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 91, 91, 92, 92, 92, 91, 91, 91, 92, 92, 91, 85, 85, 85, 85 };

static void gaea_giga(struct PlayerObj* self)
{
    int t = fg_giga_t;
    for (int i = 0; i < (int)sizeof(gaea_giga_spawn); i++)
        if (gaea_giga_spawn[i] == t) {
            struct WeaponObj* w = fg_new_weapon();
            if (w) {
                w->unk15 = self->unk15;
                w->x_pos.val = self->x_pos.val; w->y_pos.val = self->y_pos.val;
                w->x_pos.i.hi += self->unk15 ? 22 : -22;
                w->unk50 = (const u8*)fg_gaea_giga_box;
                w->pad99[0] = 0xFE;
            }
        }
    if (t == 13) fg_sfx(SFX_X5_GAEA_GIGA1);   // X5: sons do Giga da Gaea
    if (t == 64) fg_sfx(SFX_X5_GAEA_GIGA2);
    if (t + 1 >= (int)sizeof(gaea_giga_seq)) { giga_end(self); return; }
    fg_giga_t = t + 1;
    fg_giga_frame = gaea_giga_seq[fg_giga_t];
}

void fg_falcon_giga(struct PlayerObj* self)
{
    if (self->input_locked) { giga_end(self); return; }
    self->x_vel.val = 0; self->y_vel.val = 0;
    if (fg_armor == 2) { gaea_giga(self); return; }
    if (fg_armor == 6) { blade_giga(self); return; }
    if (fg_armor == 7) { shadow_giga(self); return; }
    if (giga_sub == 0) {
        giga_t++;
        if (giga_t >= (fg_armor == 5 ? 66 : 51)) {
            giga_sub = 1; giga_cnt = 0; giga_var = 0;
            giga_timer = get_random() % 3 + 3;
            fg_sfx(fg_armor == 5 ? SFX_X6_GIGA_DASH : SFX_X5_FALCON_GIGA);
        }
    } else if (giga_sub == 1) {
        if (--giga_timer <= 0) {
            giga_timer = get_random() % 3 + 3;
            giga_spawn_laser(giga_var);
            giga_var ^= 1;
        }
        if (++giga_cnt >= 121) { giga_sub = 2; giga_t = 0; }
    } else {
        if (++giga_t >= 4) { giga_end(self); return; }
    }
    if (fg_armor == 5) {   // quadros do X6 pelo tempo desde o início
        int t = giga_sub == 0 ? giga_t : giga_sub == 1 ? 66 + giga_cnt : 191 + giga_t;
        if (t >= (int)sizeof(falcon6_giga_seq)) t = sizeof(falcon6_giga_seq) - 1;
        fg_giga_frame = falcon6_giga_seq[t];
        return;
    }
    giga_anim();
}

// todo quadro (player_update_charge): anel de liberação e lança atrasada
int fg_prev_charge;
// X do X5 piscando (paletas tiradas da VRAM do X5): 1 = disparo, 2 = meia carga, 3 = carga cheia; liga 2 quadros, desliga 2
int fg_flash;
// contador próprio: o charge_timer do X4 para de contar na carga cheia (o pisca congelava)
static int charge_t = -1;
int fg_charge_fx = -1;   // partículas de carga do X5 (atlas charge_fx: 0-9 meia carga, 10-19 cheia; ciclo de 10)
static void flash_update(struct PlayerObj* self)
{
    int charging = self->charge_state[0] != PLAYER_CHARGE_NONE || self->charge_state[1] != PLAYER_CHARGE_NONE;
    int full = self->charge_state[0] == PLAYER_CHARGE_FULL || self->charge_state[1] == PLAYER_CHARGE_FULL;
    fg_flash = 0; fg_charge_fx = -1;
    if (!fg_x5_armor() || self->unk2 != 0) { charge_t = -1; return; }
    if (charging) {
        charge_t++;
        if ((charge_t / 2) % 2 == 0) fg_flash = full ? 3 : 2;
        fg_charge_fx = charge_t % 10 + (full ? 10 : 0);
    } else {
        charge_t = -1;
        if (self->shot_palette_timer > 1) fg_flash = 1;
    }
}
// Nova Strike do Ultimate X5 (estado 0x22): subida 213x3, 215x3, 216...; pausa 214x3, 217; avanço 217-220 a cada quadro
int fg_nova_frame = -1;
static int nova_sub = -1, nova_t;
static void nova_update(struct PlayerObj* self)
{
    int b = fg_body == 8 ? -26 : 0;   // Ultimate do X6: mesmos tempos, quadros 187-194 (X5: 213-220)
    if ((fg_body != 4 && fg_body != 8) || self->unk5 != PLAYER_NOVA_STRIKE || fg_giga_on) { fg_nova_frame = -1; nova_sub = -1; return; }
    if (self->unk6 != nova_sub) { nova_sub = self->unk6; nova_t = 0; } else nova_t++;
    if (nova_sub == 0) fg_nova_frame = b + (nova_t < 3 ? 213 : nova_t < 6 ? 215 : 216);
    else if (nova_sub == 1) fg_nova_frame = b + (nova_t < 3 ? 214 : 217);
    else fg_nova_frame = b + 217 + nova_t % 4;
}
void fg_tick(struct PlayerObj* self)
{
    hab_tick(self);
    if (dive_on && self->unk5 != PLAYER_HOVER) { dive_on = 0; fg_dive_t = -1; fg_fly_on = 0; }   // levou dano etc.
    else if (!dive_on) { extern s32 fg_dive_try(struct PlayerObj*); fg_dive_try(self); }
    fg_prev_charge = self->charge_timer;
    if (engine_obj.max_hp > 0x30) engine_obj.max_hp = 0x30;   // save único: vida máxima compartilhada já pode estar cheia
    if (sh_mode && self->unk5 != PLAYER_HOVER) { sh_mode = 0; fg_fly_on = 0; fg_fx_t = -1; }
    flash_update(self);
    nova_update(self);
    if (fg_slash_t >= 0) {   // pose do golpe de sabre da Blade enquanto o X não sai do lugar/estado
        if (fg_slash_t >= (int)sizeof(blade_slash_seq) || self->unk5 != slash_state || self->x_pos.i.hi != slash_x) { fg_slash_t = -1; fg_slash_frame = -1; }
        else fg_slash_frame = blade_slash_seq[fg_slash_t++];
    } else fg_slash_frame = -1;
    if (fg_arm == 2 && self->weapon != 0) { self->weapon = 0; player_reset_charge_and_weapon(self); }   // X5: Gaea não usa armas especiais
    if (fired_now) { fired_now = 0; return; }   // o disparo deste quadro já conta como o quadro 0
    if (fg_rel_t >= 0 && ++fg_rel_t > 9) fg_rel_t = -1;
    if (shot_wait > 0 && --shot_wait == 0) falcon_spawn_shot();
    if (fg_giga_on && self->unk5 != PLAYER_NOVA_STRIKE) { fg_giga_on = 0; fg_giga_frame = -1; }
}
int fg_is_x5(void) { return fus(fg_arm); }   // armaduras com efeito de carga capturado


// ---- Blade Armor do X6 (fg_armor 6) ----
// Dash no ar (estado 0x4A do X6): entra com dash ou pulo no ar (uma vez por pulo); fica parado (quadros 66/67) enquanto
// o botão estiver apertado (mínimo 9 quadros pelo pulo, 10 pelo dash); depois dispara a 8,25 px/quadro: para frente
// 15 quadros, para cima (segurando cima) 10, para baixo até o chão. Nos 8 primeiros quadros é invencível e tem a caixa
// do golpe (arma 0x20, 50x50 em X+32). Desenho: atlas flight 400+t (parado), 420+t frente, 440+t cima, 460+t baixo.
static int blade_t, blade_sub, blade_dir, blade_btn, blade_min;
struct Unk_unk68 fg_blade_dash_box[] = { { -25, -25, 0x32, 0x32 } };
static struct WeaponObj* blade_box;
static void blade_start(struct PlayerObj* self, int btn, int minf)
{
    self->air_action = 3;
    self->x_vel.val = 0; self->y_vel.val = 0; self->unk28 = 0; self->unk2C = 0;
    self->dash_momentum = -1; self->afterimage = 0;
    player_clear_attack(self);
    player_set_animation(self, 0x12);
    self->unk5 = PLAYER_HOVER; self->unk6 = 0;
    fg_fly_on = 1; blade_on = 1; blade_t = 0; blade_sub = 0; blade_btn = btn; blade_min = minf;
    fg_fly_frame = 400; fg_fly_fx = -1; blade_box = NULL;
}
static void blade_end(struct PlayerObj* self)
{
    fg_fly_on = 0; blade_on = 0; fg_fly_frame = -1;
    if (self->spike_immune == 2) self->spike_immune = 0;
    self->x_vel.val = 0; self->y_vel.val = 0;
    player_enter_fall(self);
}
static void fg_blade_dash(struct PlayerObj* self)
{
    u8 col = self->unk88.bytes.collision_flags;
    blade_t++;
    if (blade_sub == 0) {
        if (blade_t >= blade_min && !(self->input.buttons.held & blade_btn)) {
            u16 h = self->input.buttons.held;
            blade_sub = 1; blade_t = 0;
            blade_dir = (h & PLAYER_INPUT_UP) ? 1 : (h & PLAYER_INPUT_DOWN) ? 2 : 0;
            self->spike_immune = 2;
            fg_sfx(SFX_X6_DASH);   // som do dash (X6)
            blade_box = fg_new_weapon();
            if (blade_box) { blade_box->unk50 = (const u8*)fg_blade_dash_box; blade_box->pad99[0] = 0xF5; blade_box->unk15 = self->unk15; }
            fg_fly_frame = blade_dir == 0 ? 420 : blade_dir == 1 ? 440 : 460;
            return;
        }
        fg_fly_frame = 400 + (blade_t > 14 ? 14 : blade_t);
        return;
    }
    // avanço
    if (blade_dir == 0) {
        if (col & (self->unk15 ? 1 : 2)) { blade_end(self); return; }
        self->x_pos.val += self->unk15 ? FIXED(8.25) : -FIXED(8.25);
    } else if (blade_dir == 1) {
        if (col & 4) { blade_end(self); return; }
        self->y_pos.val -= FIXED(8.25);
    } else {
        self->y_pos.val += FIXED(8.25);
    }
    if (blade_t >= 8 && self->spike_immune == 2) self->spike_immune = 0;
    if ((blade_dir == 0 && blade_t >= 15) || (blade_dir == 1 && blade_t >= 10) || (blade_dir == 2 && (col & 8)) || blade_t >= 40) { blade_end(self); return; }
    fg_fly_frame = (blade_dir == 0 ? 420 : blade_dir == 1 ? 440 : 460) + (blade_dir == 2 ? (blade_t > 4 ? 4 : blade_t) : blade_dir == 1 ? (blade_t > 9 ? 9 : blade_t) : (blade_t > 14 ? 14 : blade_t));
}
void fg_blade_enter(struct PlayerObj* self) { blade_start(self, PLAYER_INPUT_DASH, 10); }
s32 fg_blade_jump(struct PlayerObj* self)
{
    if (!(self->pressed_input & PLAYER_INPUT_JUMP)) return 0;
    if (self->air_action == 3 || self->air_action == 4) return 0;
    blade_start(self, PLAYER_INPUT_JUMP, 9);
    return 1;
}

// Tiro carregado da Blade (arma 0x2B do X6): sai na hora do disparo em X+21, 10 px/quadro por 10 quadros (caixa
// -16,-6,16,12), depois explode parado (quadros 3-6) e some; o X faz o golpe de sabre (quadros 85-92 do X6)
static const u8 blade_slash_seq[35] = { 85, 85, 86, 86, 86, 86, 86, 88, 88, 88, 89, 89, 89, 89, 89, 89, 89, 89, 90, 90, 90, 90, 90, 90, 90, 91, 91, 91, 91, 91, 92, 92, 92, 92, 92 };
struct Unk_unk68 fg_blade_shot_box[] = { { -16, -6, 0x10, 0x0C } };
static void blade_fire(struct PlayerObj* self)
{
    struct WeaponObj* w = fg_new_weapon();
    if (!w) { if (self->shot_count) self->shot_count--; }
    else {
        w->unk15 = self->unk15;
        w->x_pos.val = self->x_pos.val; w->y_pos.val = self->y_pos.val; w->x_pos.i.lo = 0; w->y_pos.i.lo = 0;
        w->x_pos.i.hi += self->unk15 ? 21 : -21; w->y_pos.i.hi -= 9;
        w->x_vel.val = self->unk15 ? FIXED(10) : FIXED(-10);
        w->unk50 = (const u8*)fg_blade_shot_box;
        w->pad99[0] = 0xF7; FG_AGE(w) = 1;
    }
    fg_sfx(SFX_X6_CHARGED);
    fg_slash_t = 0; slash_state = self->unk5; slash_x = self->x_pos.i.hi;
}

// Giga da Blade (estado 0x4D do X6): 66 quadros de preparação, golpe de sabre com caixa grudada no X (arma 0x32, caixa
// trocando a cada 3 quadros) e 2 ondas (arma 0x39, 6 px/quadro, caixa -16,-48,32,96, 19 quadros) em t = 75 e 81
static const u8 blade_giga_seq[108] = { 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 48, 49, 50, 50, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 52, 52, 52, 52, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53 };
struct Unk_unk68 fg_blade_giga_boxes[] = { { -9, -39, 33, 23 }, { -75, -41, 51, 54 }, { -81, -40, 65, 70 }, { -81, -24, 65, 54 }, { -78, 11, 61, 20 }, { -49, 13, 30, 18 } };
struct Unk_unk68 fg_blade_wave_box[] = { { -16, -48, 0x20, 0x60 } };
static int blade_giga_box(int t)
{
    if (t < 73 || t > 87) return -1;
    if (t < 75) return 0;
    if (t == 87) return 5;
    return 1 + (t - 75) / 3;
}

static int blade_weapon(struct WeaponObj* w, int k)
{
    struct PlayerObj* p = &g_Player;
    if (k != 0xF7 && --FG_HIT(w) <= 0) { FG_HIT(w) = 4; w->unk64++; }
    switch (k) {
    case 0xF7: {  // tiro carregado: 10 quadros andando, depois explode parado (sem caixa); ao acertar explode na hora
        s32* hitp = (s32*)&w->unk80;   // a colisão do X4 escreve o ponto de contato aqui
        if (FG_VAR(w)) {   // explodindo: se parou num inimigo, continua acertando (id novo a cada 4 quadros)
            w->unk98 = 0;
            if (w->unk50 && --FG_HIT(w) <= 0) { FG_HIT(w) = 4; w->unk64++; }
            if (++FG_AGE(w) > 14) fg_despawn(w, 1);
            return 1;
        }
        if (w->unk98 != 0 || (FG_AGE(w) > 1 && ((u32)*hitp >> 16) != 0x7FFF)   /* y do contato: só é escrito quando as caixas se cruzam */) {
            FG_VAR(w) = 1; FG_AGE(w) = 0; FG_HIT(w) = 4; w->unk98 = 0;   // para no inimigo e fica com a caixa
            return 1;
        }
        *hitp = 0x7FFF7FFF;
        w->x_pos.val += w->x_vel.val;
        if (++FG_AGE(w) > 10) { FG_VAR(w) = 1; FG_AGE(w) = 0; w->unk50 = 0; }
        if (func_8002B1E8(BASE_OBJECT(w), 0x20, 0x14)) fg_despawn(w, 1);
        return 1; }
    case 0xF5:   // caixa do dash: X+32, 8 quadros
        w->unk98 = 0;
        w->unk15 = p->unk15;
        w->x_pos.val = p->x_pos.val; w->y_pos.val = p->y_pos.val;
        w->x_pos.i.hi += p->unk15 ? 32 : -32;
        if (++FG_AGE(w) > 8 || !blade_on) fg_despawn(w, 0);
        return 1;
    case 0xF6: {  // caixa do golpe do Giga, grudada no X
        int b = blade_giga_box(fg_giga_t);
        w->unk98 = 0;
        w->x_pos.val = p->x_pos.val; w->y_pos.val = p->y_pos.val; w->unk15 = p->unk15;
        if (!fg_giga_on || fg_giga_t > 87) { fg_despawn(w, 0); return 1; }
        if (b < 0) w->unk50 = 0;
        else { if (w->unk50 != (const u8*)&fg_blade_giga_boxes[b]) w->unk64++; w->unk50 = (const u8*)&fg_blade_giga_boxes[b]; }
        return 1; }
    case 0xF4:   // onda do Giga
        w->unk98 = 0;
        w->x_pos.val += w->x_vel.val;
        if (++FG_AGE(w) > 19) fg_despawn(w, 0);
        return 1;
    }
    return 1;
}

static void blade_giga(struct PlayerObj* self)
{
    int t = fg_giga_t;
    if (t == 71) {
        struct WeaponObj* w = fg_new_weapon();
        if (w) { w->pad99[0] = 0xF6; w->unk50 = 0; w->unk15 = self->unk15; }
    }
    if (t == 75 || t == 81) {
        struct WeaponObj* w = fg_new_weapon();
        fg_sfx(SFX_X6_BLADE_GIGA);
        if (w) {
            w->unk15 = self->unk15;
            w->x_pos.val = self->x_pos.val; w->y_pos.val = self->y_pos.val;
            w->x_pos.i.hi += self->unk15 ? 80 : -80;
            w->x_vel.val = self->unk15 ? FIXED(6) : FIXED(-6);
            w->unk50 = (const u8*)fg_blade_wave_box;
            w->pad99[0] = 0xF4;
        }
    }
    if (t + 1 >= (int)sizeof(blade_giga_seq)) { giga_end(self); return; }
    fg_giga_t = t + 1;
    fg_giga_frame = blade_giga_seq[fg_giga_t];
}

// ---- Shadow Armor do X6 (fg_armor 7) ----
// Tiro normal = shuriken (arma 0x2D do X6, init 0x801ED7C8): 8 px/quadro num ângulo sorteado (rand&15 <5: 1/32 de
// volta para baixo, <11: reto, senão para cima), caixa {-6,-6,12,12}, some ao bater ou sair da tela.
// Cima + pulo no chão = pulo alto (estado 0x1F): sobe 11,625 px/quadro até 144 px; se encostar no teto, gruda
// (quadros 66-69) e fica pendurado até 180 quadros (baixo solta); pendurado: atira 3 shurikens para baixo,
// vira com esquerda/direita e dá um dash pelo teto (6,5 px/quadro freando até 4,125, 18 quadros).
// Tiro carregado = Engetsurin (estado 0x26): golpe com caixa grudada (arma 0x32/0x33) e lua crescente parada na
// frente (arma 0x2E: +64 no chão, +32 no ar). Giga (estado 0x25): 2 luas girando em volta do X (arma 0x2F, raio 48).
static const u8 shadow_giga_seq[222] = { 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 48, 49, 50, 50, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 52, 52, 52, 52, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53 };
static const s8 shadow_orb[146][2] = { { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 47, -4 }, { 47, -9 }, { 46, -13 }, { 44, -17 }, { 42, -21 }, { 40, -25 }, { 37, -29 }, { 34, -33 }, { 31, -36 }, { 27, -39 }, { 24, -41 }, { 19, -43 }, { 15, -45 }, { 11, -46 }, { 6, -47 }, { 2, -47 }, { -2, -47 }, { -6, -47 }, { -11, -46 }, { -15, -45 }, { -19, -43 }, { -23, -41 }, { -27, -39 }, { -31, -36 }, { -34, -33 }, { -37, -29 }, { -40, -25 }, { -42, -22 }, { -44, -17 }, { -46, -13 }, { -47, -9 }, { -47, -4 }, { -48, 0 }, { -47, 4 }, { -47, 9 }, { -46, 13 }, { -44, 17 }, { -42, 21 }, { -40, 25 }, { -37, 29 }, { -34, 33 }, { -31, 36 }, { -27, 39 }, { -24, 41 }, { -19, 43 }, { -15, 45 }, { -11, 46 }, { -6, 47 }, { -2, 47 }, { 2, 47 }, { 6, 47 }, { 11, 46 }, { 15, 45 }, { 19, 43 }, { 23, 41 }, { 27, 39 }, { 31, 36 }, { 34, 33 }, { 37, 29 }, { 40, 25 }, { 42, 22 }, { 44, 17 }, { 46, 13 }, { 47, 9 }, { 47, 4 }, { 48, 0 }, { 47, -4 }, { 47, -9 }, { 46, -13 }, { 44, -17 }, { 42, -21 }, { 40, -25 }, { 37, -29 }, { 34, -33 }, { 31, -36 }, { 27, -39 }, { 24, -41 }, { 19, -43 }, { 15, -45 }, { 11, -46 }, { 6, -47 }, { 2, -47 }, { -2, -47 }, { -6, -47 }, { -11, -46 }, { -15, -45 }, { -19, -43 }, { -23, -41 }, { -27, -39 }, { -31, -36 }, { -34, -33 }, { -37, -29 }, { -40, -25 }, { -42, -22 }, { -44, -17 }, { -46, -13 }, { -47, -9 }, { -47, -4 }, { -48, 0 }, { -47, 4 }, { -47, 9 }, { -46, 13 }, { -44, 17 }, { -42, 21 }, { -40, 25 }, { -37, 29 }, { -34, 33 }, { -31, 36 }, { -27, 39 }, { -24, 41 }, { -19, 43 }, { -15, 45 }, { -11, 46 }, { -6, 47 }, { -2, 47 }, { 2, 47 }, { 6, 47 }, { 11, 46 }, { 15, 45 }, { 19, 43 }, { 23, 41 }, { 27, 39 }, { 31, 36 }, { 34, 33 }, { 37, 29 }, { 40, 25 }, { 42, 22 }, { 44, 17 }, { 46, 13 }, { 47, 9 }, { 47, 4 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 }, { 48, 0 } };
static const u8 shadow_slash_seq[33] = { 47, 47, 48, 49, 50, 50, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 52, 52, 52, 52, 53, 53, 53, 53 };
static const u8 sh_throw_seq[20] = { 72, 72, 72, 72, 73, 73, 73, 73, 73, 73, 73, 73, 73, 73, 71, 71, 71, 71, 70, 70 };
static const u8 sh_air_seq[13] = { 54, 54, 55, 56, 56, 57, 57, 58, 58, 59, 60, 61, 61 };
struct Unk_unk68 fg_shadow_kunai_box[] = { { -6, -6, 0x0C, 0x0C } };
struct Unk_unk68 fg_shadow_kunai_terrain[] = { { 0, 0, 3, 3 } };   // centro, meia largura, meia altura
void func_8002C808(struct PlayerObj*);
struct Unk_unk68 fg_shadow_moon_boxes[] = { { -4, -31, 32, 8 }, { -28, -35, 57, 20 }, { -35, -38, 65, 57 }, { -40, -38, 80, 76 }, { -35, -20, 64, 56 }, { -30, 14, 59, 20 }, { -4, 23, 32, 9 } };
struct Unk_unk68 fg_shadow_air_boxes[] = { { -36, -35, 32, 29 }, { -56, -34, 67, 48 }, { -64, -24, 97, 56 }, { 17, -16, 19, 31 } };
static int sh_mode2_unused;     // (sh_mode declarado acima) 0 nada; 1 pulo alto/teto; 2 Engetsurin no chão; 3 Engetsurin no ar
static int sh_sub, sh_t, sh_timer, sh_throw = -1, sh_v;
int fg_fx_t = -1;       // efeito desenhado em volta do X fora do Giga (atlas giga_fx: 300+t no chão, 400+t no ar)

static struct WeaponObj* sh_kunai(struct PlayerObj* p, int dx, int dy, s32 vx, s32 vy, int extra)
{
    struct WeaponObj* w = fg_new_weapon();
    if (!w) return NULL;
    w->id = 0;   // dano do tiro normal (lemon)
    w->unk15 = vx > 0 ? PLAYER_FACING_RIGHT : vx < 0 ? 0 : p->unk15;
    w->x_pos.val = p->x_pos.val; w->y_pos.val = p->y_pos.val; w->x_pos.i.lo = 0; w->y_pos.i.lo = 0;
    w->x_pos.i.hi += dx; w->y_pos.i.hi += dy;
    w->x_vel.val = vx; w->y_vel.val = vy;
    w->unk50 = (const u8*)fg_shadow_kunai_box;
    w->pad99[0] = 0xF3; FG_VAR(w) = extra;
    return w;
}
static void sh_kunai_dir(struct WeaponObj* w, int right)
{
    int r = get_random() & 15;
    w->x_vel.val = right ? FIXED(7.84619140625) : -FIXED(7.84619140625);
    w->y_vel.val = r < 5 ? FIXED(1.5606689453125) : r < 11 ? 0 : -FIXED(1.5606689453125);
    if (r >= 5 && r < 11) w->x_vel.val = right ? FIXED(8) : -FIXED(8);
}

static void sh_end(struct PlayerObj* self)
{
    sh_mode = 0; fg_fly_on = 0; fg_fly_frame = -1; fg_fx_t = -1; sh_throw = -1;
    self->x_vel.val = 0; self->y_vel.val = 0;
    if (self->unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND) player_enter_land(self);
    else player_enter_fall(self);
}
static void sh_start(struct PlayerObj* self, int mode)
{
    self->x_vel.val = 0; self->y_vel.val = 0; self->unk28 = 0; self->unk2C = 0;
    self->dash_momentum = 0; self->afterimage = 0; self->air_action = 3;
    player_clear_attack(self);
    self->unk5 = PLAYER_HOVER; self->unk6 = 0;
    fg_fly_on = 1; fg_fly_fx = -1; sh_mode = mode; sh_sub = 0; sh_t = 0; sh_throw = -1; fg_fx_t = -1;
}

s32 fg_shadow_hijump(struct PlayerObj* self)
{
    if (fg_legs != 7 || !(self->input.buttons.held & PLAYER_INPUT_UP) || !(self->unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND)) return 0;
    player_set_animation(self, 0xA);
    sh_start(self, 1);
    fg_sfx(SFX_X6_JUMP);
    self->air_state = 1;
    fg_fly_frame = 33;
    return 1;
}

static int sh_test_ceil = -1;   // (testes: MMX4_TEST_CEIL=1 finge que tem teto em cima do pulo alto)
static void sh_hang(struct PlayerObj* self)
{
    u8 col = self->unk88.bytes.collision_flags;
    if (sh_test_ceil < 0) { const char* e = getenv("MMX4_TEST_CEIL"); sh_test_ceil = (e != NULL && e[0] == '1'); }
    if (sh_test_ceil) col |= PLAYER_COLLIDE_CEILING;
    u16 h = self->input.buttons.held;
    if (sh_sub == 0) {   // subindo
        if (col & PLAYER_COLLIDE_CEILING) {
            sh_sub = 2; sh_t = 0; sh_timer = 180; fg_fly_frame = 66;
            fg_sfx(SFX_X6_GRAB);
            return;
        }
        sh_t++;
        self->y_pos.val -= FIXED(11.625);
        fg_fly_frame = sh_t < 2 ? 33 : sh_t < 6 ? 35 : 37;
        if (sh_t >= 13) { sh_sub = 1; sh_t = 0; fg_fly_frame = 41; }
        return;
    }
    if (sh_sub == 1) {   // topo sem teto
        if (++sh_t >= 5) sh_end(self);
        return;
    }
    if (sh_sub >= 2 && sh_sub <= 3) self->y_pos.val -= FIXED(1);   // continua encostado (o X4 empurra para fora e marca o teto)
    if (sh_sub == 2) {   // agarrando
        sh_t++;
        fg_fly_frame = sh_t < 4 ? 66 : sh_t < 8 ? 67 : sh_t < 12 ? 68 : 69;
        if (sh_t >= 15) { sh_sub = 3; sh_t = 0; }
        return;
    }
    if (sh_sub == 3) {   // pendurado
        if (h & PLAYER_INPUT_RIGHT) self->unk15 = PLAYER_FACING_RIGHT;
        if (h & PLAYER_INPUT_LEFT) self->unk15 = 0;
        if (self->pressed_input & PLAYER_INPUT_DASH) { sh_sub = 4; sh_t = 0; fg_fly_frame = 92; sh_throw = -1; return; }
        if ((h & PLAYER_INPUT_DOWN) || (self->pressed_input & PLAYER_INPUT_JUMP) || (sh_t > 1 && !(col & PLAYER_COLLIDE_CEILING))) sh_timer = 0;
        sh_t++;
        if (sh_timer > 0) {
            sh_timer--;
            if (self->pressed_input & PLAYER_INPUT_SHOOT) {   // 3 shurikens para baixo (ângulos 22, 24 e 26 de 32)
                sh_kunai(self, 0, 24, 0, FIXED(8), 1);
                sh_kunai(self, 0, 24, -FIXED(3.0614013671875), FIXED(7.39111328125), 1);
                sh_kunai(self, 0, 24, FIXED(3.0614013671875), FIXED(7.39111328125), 1);
                fg_sfx(SFX_X6_SHOT);
                sh_throw = 0;
            }
        }
        if (sh_throw >= 0) {
            fg_fly_frame = sh_throw_seq[sh_throw];
            if (++sh_throw >= (int)sizeof(sh_throw_seq)) sh_throw = -1;
        } else fg_fly_frame = 69;
        if (sh_timer == 0 && sh_throw < 0) sh_end(self);
        return;
    }
    if (sh_sub == 4) {   // começo do dash no teto
        self->y_pos.val -= FIXED(1);
        sh_t++;
        fg_fly_frame = sh_t < 3 ? 92 : 93;
        if (sh_t >= 4) { sh_sub = 5; sh_t = 0; sh_v = FIXED(6.5); fg_sfx(SFX_X6_DASH); self->afterimage = 1; }
        return;
    }
    if (sh_sub == 5) {   // dash no teto: continua enquanto segura o dash ou para a frente
        int fwd = self->unk15 ? PLAYER_INPUT_RIGHT : PLAYER_INPUT_LEFT;
        if ((col & (self->unk15 ? PLAYER_COLLIDE_RIGHT : PLAYER_COLLIDE_LEFT)) || !(h & (PLAYER_INPUT_DASH | fwd)) || sh_t >= 18) {
            sh_sub = 6; sh_t = 0; sh_v = 0; self->afterimage = 0;
            fg_fly_frame = 94;
            return;
        }
        self->y_pos.val -= FIXED(1);
        self->x_pos.val += self->unk15 ? sh_v : -sh_v;
        sh_v -= FIXED(0.1875); if (sh_v < FIXED(4.125)) sh_v = FIXED(4.125);
        fg_fly_frame = sh_t % 3 == 0 ? 78 : sh_t % 3 == 1 ? 82 : 80;
        sh_t++;
        return;
    }
    // fim do dash: cai com gravidade (quadros 94, 93) e depois queda normal
    if (col & PLAYER_COLLIDE_GROUND) { sh_end(self); return; }
    sh_v += FIXED(0.2578125);
    self->y_pos.val += sh_v;
    fg_fly_frame = sh_t < 3 ? 94 : 93;
    if (++sh_t >= 7) sh_end(self);
}

// Engetsurin: caixa grudada no X + lua crescente parada na frente
static int sh_slash_box(int t)    // caixas da arma 0x32 (= as do golpe do Giga da Blade)
{
    if (t < 3 || t > 12) return -1;
    return t == 3 ? 0 : (t - 2) / 2;
}
static int sh_moon_box(int t)
{
    if (t < 6 || t > 28) return -1;
    return t < 9 ? t - 6 : t < 20 ? 3 : t < 23 ? 4 : t < 26 ? 5 : 6;
}
static void sh_slash(struct PlayerObj* self)
{
    int t = sh_t, air = sh_mode == 3;
    if (t == 0) { func_8001540C(1, 0x0A, self); if (self->shot_count) self->shot_count--; }   // o X4 conta o disparo depois de chamar o tiro: o golpe não é projétil
    if (t == 2) {   // caixa grudada (F2) e lua (F1)
        struct WeaponObj* w = fg_new_weapon();
        if (w) { w->pad99[0] = 0xF2; w->unk50 = 0; w->unk15 = self->unk15; FG_VAR(w) = air; }
    }
    if ((!air && t == 6) || (air && t == 5)) {
        struct WeaponObj* w = fg_new_weapon();
        if (w) {
            int d = air ? 32 : 64;
            w->unk15 = self->unk15;
            w->x_pos.val = self->x_pos.val; w->y_pos.val = self->y_pos.val;
            w->x_pos.i.hi += self->unk15 ? d : -d;
            w->pad99[0] = 0xF1; FG_VAR(w) = air; w->unk50 = (const u8*)&fg_shadow_moon_boxes[0];
        }
    }
    fg_fly_frame = air ? sh_air_seq[t] : shadow_slash_seq[t];
    fg_fx_t = (air ? 400 : 300) + t;
    sh_t = t + 1;
    if (sh_t >= (air ? (int)sizeof(sh_air_seq) : (int)sizeof(shadow_slash_seq))) sh_end(self);
}

static void sh_fly(struct PlayerObj* self)
{
    if (sh_mode == 1) sh_hang(self); else sh_slash(self);
}

static int shadow_weapon(struct WeaponObj* w, int k)
{
    struct PlayerObj* p = &g_Player;
    switch (k) {
    case 0xF3:   // shuriken
        if (w->unk98 != 0) { fg_despawn(w, !FG_VAR(w)); return 1; }
        FG_AGE(w)++;
        w->x_pos.val += w->x_vel.val; w->y_pos.val += w->y_vel.val;
        if (func_8002B1E8(BASE_OBJECT(w), 0x10, 0x10)) { fg_despawn(w, !FG_VAR(w)); return 1; }
        w->unk68 = fg_shadow_kunai_terrain;   // X6 (0x801EEC48): bate no cenário e some
        func_8002C808((struct PlayerObj*)w);
        if (w->unk70 & 0xF) fg_despawn(w, !FG_VAR(w));
        return 1;
    case 0xF2: {  // caixa grudada do golpe (chão: arma 0x32; ar: 0x33; Giga: 0x32 de t 72 a 81)
        int b;
        w->unk98 = 0;
        w->x_pos.val = p->x_pos.val; w->y_pos.val = p->y_pos.val; w->unk15 = p->unk15;
        if (FG_VAR(w) == 2) {
            if (!fg_giga_on || fg_giga_t - 1 > 81) { fg_despawn(w, 0); return 1; }
            b = sh_slash_box(fg_giga_t - 1 - 69);
            if (b < 0) w->unk50 = 0; else { if (w->unk50 != (const u8*)&fg_blade_giga_boxes[b]) w->unk64++; w->unk50 = (const u8*)&fg_blade_giga_boxes[b]; }
            return 1;
        }
        if (!sh_mode || sh_mode == 1) { fg_despawn(w, 0); return 1; }
        if (FG_VAR(w)) { int t = sh_t - 1; b = t < 3 || t > 9 ? -1 : t < 5 ? 0 : t < 7 ? 1 : t < 9 ? 2 : 3;
            if (b < 0) w->unk50 = 0; else { if (w->unk50 != (const u8*)&fg_shadow_air_boxes[b]) w->unk64++; w->unk50 = (const u8*)&fg_shadow_air_boxes[b]; } }
        else { b = sh_slash_box(sh_t - 1);
            if (b < 0) w->unk50 = 0; else { if (w->unk50 != (const u8*)&fg_blade_giga_boxes[b]) w->unk64++; w->unk50 = (const u8*)&fg_blade_giga_boxes[b]; } }
        return 1; }
    case 0xF1: {  // lua do Engetsurin (parada); no chão acerta de novo a cada 8 quadros
        int a = ++FG_AGE(w), b;
        w->unk98 = 0;
        if (FG_VAR(w)) {   // ar: some com o fim do golpe
            if (sh_mode != 3) { fg_despawn(w, 0); return 1; }
            b = a - 1 < 3 ? a - 1 : 3;
        } else {
            b = sh_moon_box(a + 5);
            if (b < 0) { fg_despawn(w, 0); return 1; }
            if (a == 10 || a == 18) w->unk64++;
        }
        w->unk50 = (const u8*)&fg_shadow_moon_boxes[b];
        return 1; }
    case 0xF0: {  // lua do Giga girando em volta do X (t 70 a 215)
        int t = fg_giga_t - 1, i = t - 70;
        w->unk98 = 0;
        if (!fg_giga_on || i < 0 || i >= (int)(sizeof(shadow_orb) / 2)) { fg_despawn(w, 0); return 1; }
        w->x_pos.val = p->x_pos.val; w->y_pos.val = p->y_pos.val;
        w->x_pos.i.hi += p->unk15 ? shadow_orb[i][0] : -shadow_orb[i][0];
        w->y_pos.i.hi += FG_VAR(w) ? -shadow_orb[i][1] : shadow_orb[i][1];
        if (t >= 75 && (t - 75) % 8 == 0) w->unk64++;
        return 1; }
    }
    return 1;
}

static void shadow_giga(struct PlayerObj* self)
{
    int t = fg_giga_t;
    if (t == 73) fg_sfx(SFX_X6_SHADOW_GIGA);
    if (t == 70) {
        for (int i = 0; i < 2; i++) {
            struct WeaponObj* w = fg_new_weapon();
            if (w) { w->pad99[0] = 0xF0; FG_VAR(w) = i; w->unk15 = self->unk15; w->unk50 = (const u8*)&fg_shadow_moon_boxes[3];
                w->x_pos.val = self->x_pos.val; w->y_pos.val = self->y_pos.val; w->x_pos.i.hi += self->unk15 ? 48 : -48; }
        }
    }
    if (t == 71) {
        struct WeaponObj* w = fg_new_weapon();
        if (w) { w->pad99[0] = 0xF2; FG_VAR(w) = 2; w->unk50 = 0; w->unk15 = self->unk15; }
    }
    if (t + 1 >= (int)sizeof(shadow_giga_seq)) { giga_end(self); return; }
    fg_giga_t = t + 1;
    fg_giga_frame = shadow_giga_seq[fg_giga_t];
}
int fg_shot_took_state(void) { return sh_mode >= 2 && g_Player.unk5 == PLAYER_HOVER; }

// MMX4_PARTS="capacete,corpo,braço,pernas" (armadura de cada peça); sem isso, MMX4_DIRECT_SKILL vale para as 4
void fg_parts_init(void)
{
    const char* p = getenv("MMX4_PARTS");
    int v[4] = { fg_armor, fg_armor, fg_armor, fg_armor }, n = 0;
    while (p != NULL && *p && n < 4) { char* e; v[n++] = (int)strtoul(p, &e, 0); p = (*e == ',') ? e + 1 : e; if (*e != ',' && *e) break; }
    fg_head = v[0]; fg_body = v[1]; fg_arm = v[2]; fg_legs = v[3];
    fg_armor = (fg_head == fg_body && fg_body == fg_arm && fg_arm == fg_legs) ? fg_head : 0;
    if (fg_armor == 9) fg_armor = 0;
}

// ---- cápsulas do Dr. Light do X4 no save do fangame (MMX4_CAPS = peças do X4 já pegas) ----
// bits: 1 capacete, 2 corpo, 4 braço Stock (cápsula 2), 0x10 braço Plasma (cápsula 3), 8 pernas
int fg_caps = -1, fg_caps_new, fg_caps_worn;
void fg_voz_reset(void) { voz_x6 = -1; }   // relê MMX4_VOZ_X6 em cada fase (Opções)
static const unsigned char fg_cap_bit[8] = { 1, 2, 4, 0x10, 8, 0, 0, 0 };
int fg_caps_mode(void)
{
    if (fg_caps < 0) { const char* c = getenv("MMX4_CAPS"); fg_caps = (c != NULL && c[0]) ? (int)strtoul(c, NULL, 0) : -2; fg_caps_new = fg_caps_worn = 0; }
    return fg_caps >= 0;
}
int fg_caps_has(int k) { return k >= 0 && k < 8 && (fg_caps & fg_cap_bit[k]) != 0; }
void fg_caps_grant(int k)
{
    if (k < 0 || k >= 5) return;
    int b = fg_cap_bit[k];
    fg_caps |= b; fg_caps_new |= b;
    int* slot = (b == 1) ? &fg_head : (b == 2) ? &fg_body : (b == 8) ? &fg_legs : &fg_arm;
    if (*slot != 0 || g_Player.unk2 != 0) return;   // o lugar já tem outra armadura: fica guardada para o hub
    *slot = 9; fg_caps_worn |= b;
    g_Player.armor_parts |= (b == 0x10) ? 4 : b;
    if (b & 0x14) { g_Player.arm_type = (b == 0x10) ? 2 : 1; engine_obj.arm_type = g_Player.arm_type; }
    engine_obj.armor_parts = g_Player.armor_parts;
}
// Nova Strike (bit 2 = corpo do X4/Ultimate): só com as 4 peças iguais (ou sem peças combinadas: jogo original)
int fg_nova_ok(void) { return fg_head == fg_body && fg_body == fg_arm && fg_arm == fg_legs; }

// ---- desafios do Zero (Black Zero): números da fase para o hub (x4_mem 40..49) ----
// st: 0 quadros jogando, 1 quadros com chefe, 2 danos levados, 3 danos no chefe, 4 mortes, 5 sub tank usado,
//     6 dash usado, 7 itens de vida pegos, 8 técnicas no chefe, 9 vida perdida no chefe
int fg_zst[10];
int fg_kill_streak, fg_kill_best;   // inimigos destruídos seguidos sem levar dano (e o melhor da fase)
void fg_kill(void) { if (engine_obj.state == 6 && ++fg_kill_streak > fg_kill_best) fg_kill_best = fg_kill_streak; }
static int z_hp = -1, z_tank = -1, z_maxhp = -1, z_lives = -1, z_boss_seen;
void fg_zero_reset(void) { fg_kill_streak = fg_kill_best = 0; for (int i = 0; i < 10; i++) fg_zst[i] = 0; z_hp = z_tank = z_maxhp = z_lives = -1; z_boss_seen = 0; }
void fg_zero_track(void)
{
    if (engine_obj.state != 6 || !g_Player.active) { z_hp = -1; return; }
    { extern int fg_bz; extern void bz_tick(void); if (fg_bz && engine_obj.cur_character == 1) bz_tick(); }
    { extern void fg_nz_tick(void); fg_nz_tick(); }   // Nightmare Zero
    // chefe: só conta com a barra de vida ativa e o chefe vivo (sem a explosão final)
    int boss = engine_obj.boss_ptr != 0 && engine_obj.enable_boss && ((struct MainObj*)engine_obj.boss_ptr)->hp > 0;
    if (boss && !z_boss_seen) { fg_zst[1] = fg_zst[3] = fg_zst[8] = fg_zst[9] = 0; }   // nova tentativa: os números do chefe recomeçam
    if (!boss && z_boss_seen && ((engine_obj.boss_ptr == 0) || !engine_obj.enable_boss)) z_boss_seen = 0;
    int a = g_Player.unk5;
    int tank = engine_obj.sub_tanks[0] + engine_obj.sub_tanks[1] + engine_obj.sub_tanks[2];
    int hp = HP_VALUE(g_Player.hp);
    if (engine_obj.gameplay_locked == 0) fg_zst[0]++;
    if (boss) { fg_zst[1]++; z_boss_seen = 1; }
    if (z_hp >= 0) {
        if (hp < z_hp) { fg_zst[2]++; fg_kill_streak = 0; if (boss) { fg_zst[3]++; fg_zst[9] += z_hp - hp; } }
    }
    if (z_tank >= 0 && tank < z_tank) fg_zst[5]++;
    if (z_lives >= 0 && engine_obj.player_lives < z_lives) fg_zst[4]++;
    if (a == PLAYER_DASH || a == PLAYER_AIR_DASH) fg_zst[6]++;
    if (boss && a >= PLAYER_ZERO_RAIJINGEKI && a <= PLAYER_ZERO_SHIPPUUGA) fg_zst[8]++;
    z_hp = hp; z_tank = tank; z_maxhp = engine_obj.max_hp; z_lives = engine_obj.player_lives;
}
int fg_bz;   // Black Zero: bits 0-3 capacete/corpo/braços/pernas, 4-7 melhorias (MMX4_BZ)
void fg_zero_start(void)
{
    extern int fg_bz_ad, fg_bz_dash_hit, fg_bz_aj, fg_bz_imp_age; fg_bz_ad = 0; fg_bz_dash_hit = 0; fg_bz_aj = 0; fg_bz_imp_age = -1;
    const char* b = getenv("MMX4_BZ");
    fg_bz = (b && b[0]) ? (int)strtoul(b, NULL, 0) : 0;
    { extern int fg_nz; extern void fg_nz_reset(void); const char* z = getenv("MMX4_NZ"); fg_nz = (z && z[0]) ? (int)strtoul(z, NULL, 0) : 0; fg_nz_reset(); }
    fg_zero_reset();
}

// ---- habilidades do Black Zero (fg_bz: 1 capacete, 2 corpo, 4 braços, 8 pernas; <<4 as melhorias) ----
int fg_bz_ad;        // dashes no ar desde que saiu do chão
int fg_bz_dash_hit;  // (antigo: dash que feria; trocado pelo pulo extra)
int fg_bz_aj;        // pulo extra no ar já usado (pernas melhoradas)
void fg_bz_air_jump(struct PlayerObj* self)
{   // como o pulo duplo do Zero (player_zero_check_double_jump), mas sem perder o embalo do dash
    // (protótipos vêm dos cabeçalhos do jogo)
    fg_bz_aj = 1;
    player_set_animation(self, 0x63);
    func_8001540C(1, 1, self);
    player_play_voice(self, 7);
    self->unk28 = 0;
    self->y_vel.val = FIXED(5.8125);
    self->unk2C = FIXED(0.2578125);
    self->air_action = 6;
    player_air_steer(self);
    self->unk5 = PLAYER_JUMP;
    self->unk6 = 0;
}
static int bz_boss_hits;
static int bz_zero_weapon(int id) { return (id >= 0x18 && id <= 0x23) || id == 0x3D || id == 0x3E; }   // (0x18/0x19: 1º e 2º golpe do combo)
static void bz_heal(int n)
{
    int hp = HP_VALUE(g_Player.hp);
    if (hp <= 0) return;
    hp += n; if (hp > engine_obj.max_hp) hp = engine_obj.max_hp;
    g_Player.hp = (u8)hp | HP_DAMAGE_FLAG(g_Player.hp);
}
// golpe do sabre num inimigo: devolve o dano a aplicar (-1 = segue o jogo normal)
int fg_bz_hit(struct MainObj* obj, int id, int dmg)
{
    if (!fg_bz || engine_obj.cur_character != 1 || !bz_zero_weapon(id)) return -1;
    if ((s8)obj->unk63 == -1) {   // defesa/escudo: só os braços cortam
        if (!(fg_bz & 4)) return -1;
        dmg = 1;
    } else if (fg_bz & 4) dmg += 1;   // sabre negro: +1 de dano
    if ((fg_bz & 0x10) && (void*)obj == (void*)engine_obj.boss_ptr && ++bz_boss_hits >= 5) { bz_boss_hits = 0; bz_heal(1); }   // capacete+: dreno no chefe (1 a cada 5 golpes)
    return dmg;
}
void fg_bz_kill(struct MainObj* obj)
{
    if (fg_bz & 1) bz_heal(1);   // capacete: dreno ao matar com o sabre (+1)
}
int fg_bz_palette(u16* dst, s32 source);
void bz_tick(void)
{
    int a = g_Player.unk5;
    if (a == PLAYER_IDLE || a == PLAYER_WALK || a == PLAYER_WALK_START || a == PLAYER_DASH || a == PLAYER_LAND || a == PLAYER_SETTLE ||
        a == PLAYER_WALL_CLING || a == PLAYER_WALL_SLIDE || a == PLAYER_LADDER_UP || a == PLAYER_LADDER_DOWN) { fg_bz_ad = 0; fg_bz_aj = 0; }
    { extern void fg_bz_giga_tick(void); fg_bz_giga_tick(); }
    {   // cor por peça: se a paleta do Zero estiver a normal do jogo, troca pela mistura (o jogo carrega a paleta sem passar pelo player_copy_palette)
        u16 tmp[16];
        u16* cur = (u16*)SP_PALETTES[0];
        if (fg_bz_palette(tmp, 0) && cur[5] == ((u16*)SP_PALETTE_BANK[0])[5]) { for (int i = 0; i < 16; i++) cur[i] = tmp[i]; need_palette_load |= 1; }
    }
}
// corpo: 25% menos dano (melhoria: 50%)
int fg_bz_reduce(int dmg)
{
    if (engine_obj.cur_character != 1 || !(fg_bz & 2) || dmg <= 0) return -1;
    dmg = (fg_bz & 0x20) ? dmg / 2 : dmg * 3 / 4;
    return dmg ? dmg : 1;
}

// braços melhorados: o 3º golpe do combo solta uma onda (chamado em func_8003A1DC, player_special.c)
struct Unk_unk68 fg_bz_wave_box[] = { { -10, -18, 20, 36 } };
void fg_bz_combo(struct PlayerObj* self)
{
    struct WeaponObj* w;
    if (engine_obj.cur_character != 1 || !(fg_bz & 0x40) || self->combo != 2) return;
    w = fg_new_weapon();
    if (!w) return;
    w->unk15 = self->unk15;
    w->x_pos.val = self->x_pos.val; w->y_pos.val = self->y_pos.val; w->x_pos.i.lo = 0; w->y_pos.i.lo = 0;
    w->x_pos.i.hi += self->unk15 ? 22 : -22;
    w->y_pos.i.hi += 12;
    w->x_vel.val = self->unk15 ? FIXED(7) : FIXED(-7);
    w->unk50 = (const u8*)fg_bz_wave_box;
    w->pad99[0] = 0xEF;
}

// Giga do Black Zero completo: 8 colunas de energia negra caem pela tela, uma atrás da outra a partir do Zero
void fg_bz_giga(struct PlayerObj* self)
{
    struct BackgroundObj* bg;
    int i, sx;
    if (self->unk2 == 0 || (fg_bz & 0xF) != 0xF) return;
    bg = &background_objects[self->bg_offset < 0 ? 0 : self->bg_offset];
    sx = self->x_pos.i.hi - bg->x_pos.i.hi;   // posição do Zero na tela
    for (i = 0; i < 8; i++) {
        struct WeaponObj* w = fg_new_weapon();
        int col = (i / 2) * 40 + 30, x;
        if (!w) return;
        x = (i & 1) ? sx + col : sx - col;   // alternando para os dois lados, de perto para longe
        w->unk15 = 0;
        w->x_pos.val = 0; w->y_pos.val = 0;
        w->x_pos.i.hi = bg->x_pos.i.hi + x;
        w->y_pos.i.hi = bg->y_pos.i.hi - 50;
        w->y_vel.val = FIXED(9);
        FG_VAR(w) = (i / 2) * 5;
        w->unk50 = 0;
        w->pad99[0] = 0xEE;
    }
}

// Giga do Black Zero completo (baixo + Giga): o Zero salta alto, crava o sabre no chão e as colunas negras caem
static int bz_giga_phase;   // 0 nada, 1 subindo, 2 caindo com o sabre para baixo
static int bz_giga_t;
int fg_bz_imp_age = -1, fg_bz_imp_x, fg_bz_imp_y;   // impacto do Giga (para o efeito no Godot)
static void bz_giga_dive(struct PlayerObj* self)
{
    fg_sfx(SFX_X5_NOVA);   // mergulho
    player_set_animation(self, 0x61);
    self->unk5 = PLAYER_ZERO_HYOURETSUZAN; self->unk6 = 0;
    self->attacking = 1;
    bz_giga_phase = 2;
}
int fg_bz_giga_check(struct PlayerObj* self)
{
    if (self->unk2 == 0 || (fg_bz & 0xF) != 0xF || bz_giga_phase) return 0;
    if (!(self->input.buttons.held & PLAYER_INPUT_DOWN) || !(self->pressed_input & PLAYER_INPUT_GIGA)) return 0;
    if (self->weapon_energy[0] < 0xC || self->attacking) return 0;
    self->weapon_energy[0] -= 0xC;
    player_zero_begin_attack(self);
    player_play_voice(self, 0xA);
    fg_sfx(SFX_X6_GIGA_DASH);   // arrancada
    self->invincibility_timer = 0x5A; self->hurt_phase = 0; self->spike_immune = 1;
    if (self->unk88.bytes.collision_flags & PLAYER_COLLIDE_GROUND) {   // no chão: salto alto girando
        player_set_animation(self, 0x63);
        self->x_vel.val = 0; self->unk28 = 0;
        self->y_vel.val = FIXED(7.5); self->unk2C = FIXED(0.2578125);
        self->air_state = 1; self->air_action = 6; self->dash_momentum = 0;
        self->unk5 = PLAYER_JUMP; self->unk6 = 0;
        self->y_pos.i.hi -= 2; self->unk88.bytes.collision_flags &= ~PLAYER_COLLIDE_GROUND;   // sai do chão
        bz_giga_phase = 1; bz_giga_t = 0;
    } else bz_giga_dive(self);
    return 1;
}
int fg_bz_giga_land(struct PlayerObj* self)
{
    if (bz_giga_phase != 2) return 0;
    bz_giga_phase = 0;
    self->air_state = 0; self->dash_momentum = 0; self->air_action = 0; self->afterimage = 0; self->spike_immune = 0;
    func_8001540C(0, 0x2C, self);   // estouro
    fg_sfx(SFX_X6_SHADOW_GIGA);
    fg_bz_imp_age = 0; fg_bz_imp_x = self->x_pos.i.hi; fg_bz_imp_y = self->y_pos.i.hi;
    fg_bz_giga(self);
    return 1;
}
void fg_bz_giga_tick(void)
{
    struct PlayerObj* self = &g_Player;
    if (fg_bz_imp_age >= 0 && ++fg_bz_imp_age > 40) fg_bz_imp_age = -1;
    if (bz_giga_phase == 1) {
        if (self->unk5 != PLAYER_JUMP && self->unk5 != PLAYER_FALL) { bz_giga_phase = 0; return; }   // algo interrompeu
        if (++bz_giga_t > 3 && self->y_vel.val <= 0) bz_giga_dive(self);   // no alto: crava o sabre
    } else if (bz_giga_phase == 2 && self->unk5 != PLAYER_ZERO_HYOURETSUZAN) bz_giga_phase = 0;
}
int fg_bz_giga_rising(void) { return bz_giga_phase == 1; }
int fg_bz_giga_diving(void) { return bz_giga_phase == 2; }
int fg_bz_fx_query(int f)
{   // 0 fase (1 subindo, 2 mergulho), 1 idade do impacto (-1 nada), 2/3 Zero na tela, 4/5 impacto na tela
    struct BackgroundObj* bg = &background_objects[g_Player.bg_offset < 0 ? 0 : g_Player.bg_offset];
    switch (f) {
    case 0: return bz_giga_phase;
    case 1: return fg_bz_imp_age;
    case 2: return g_Player.x_pos.i.hi - bg->x_pos.i.hi;
    case 3: return g_Player.y_pos.i.hi - bg->y_pos.i.hi;
    case 4: return fg_bz_imp_x - bg->x_pos.i.hi;
    default: return fg_bz_imp_y - bg->y_pos.i.hi;
    }
}
int fg_zero_pal(int i) { return ((u16*)SP_PALETTE_BANK[i < 16 ? 0 : 0xD])[i & 15]; }   // depuração: paletas do Zero normal / Black Zero
// cor do Black Zero conforme as peças: as cores do Zero passam aos poucos para as do Black Zero (1/4 por peça)
int fg_bz_palette(u16* dst, s32 source)
{
    int n = (fg_bz & 1) + ((fg_bz >> 1) & 1) + ((fg_bz >> 2) & 1) + ((fg_bz >> 3) & 1);
    const u16 *a, *b;
    if (source != 0 || n == 0 || n >= 4) return 0;   // só a paleta normal do Zero; com 4 peças o jogo já usa a do Black Zero
    a = (const u16*)SP_PALETTE_BANK[0]; b = (const u16*)SP_PALETTE_BANK[0xD];
    for (int i = 0; i < 16; i++) {
        int c = 0;
        for (int sh = 0; sh < 15; sh += 5) {
            int x = (a[i] >> sh) & 31, y = (b[i] >> sh) & 31;
            static const int W[4] = { 0, 40, 65, 85 };   // quanto do Black Zero com 1, 2, 3 peças (em %)
            c |= ((x * (100 - W[n]) + y * W[n] + 50) / 100) << sh;
        }
        dst[i] = (u16)(c | (a[i] & 0x8000));
    }
    return 1;
}

// ---- Nightmare Zero no X4 (jogando de Zero): peças dos desafios do X6 (MMX4_NZ: bits 0-3 capacete, corpo, braços,
// pernas; 4-7 as melhorias), com as mesmas regras do X5/X6 (psx_embed.cpp nz_*): o motor do X4 é o mesmo (ações 12/13
// dash, 17 golpe, 48 combo; o objeto de arma tem +0x47 quadro, +0x50 caixa, +0x64 número do golpe) e os quadros do
// Zero são os mesmos do X5 (atlas idêntico): 3º golpe 105-127, guardar 130-134. O Godot desenha com as mesmas
// consultas do X5/X6 (x4_mem 0x1F900790-0x1F9007FF; posições no mundo, câmera em 0x1F9007FC/FD).
//  capacete Frenesi: cada inimigo destruído por golpe do Zero dá +1 de dano a todo golpe dele (até +3; melhoria +5);
//          levar um golpe zera e esse golpe tira 1 a mais.
//  corpo Sobrecarga: a vida não passa da metade da máxima; cada acerto do Zero enche a barra do Pesadelo (20; melhoria
//          12; ecos/clones/Giga não contam); cheia = 180 quadros (melhoria 300) invencível com o dano dobrado.
//  braços Eco: o golpe do sabre (armas 0x18-0x23) que acertou se repete 30 quadros depois do começo dele, no mesmo
//          lugar (posição, lado, quadro, caixa de cada quadro), com caixa só nos quadros em que acertou; metade do dano
//          (melhoria: inteiro). Arma nossa 0xE0 (id 0x12 do fangame).
//  pernas Esquiva: golpe nos primeiros 8 quadros do dash (melhoria 14) não tira vida nem dá recuo e um clone corta ali
//          (caixa 64x64 na frente, 4 de dano; melhoria 8; x2 no modo); golpe no resto do dash tira 1 a mais. Arma 0xE1.
//  4 peças: Giga (baixo + Giga no modo Pesadelo, gasta o que sobra): 146 quadros como no X5/X6 — escurece (32), preto
//          (32), clarão + roxo + o golpe, o corte atravessa a tela (30 quadros, 8 px), guarda o sabre (32), volta (8).
//          O Zero fica parado, invencível, sem obedecer e o jogo não o desenha. Caixa 170x254 (arma 0xE2), 16 de dano.
int fg_nz;
#define NZ_HELM 1
#define NZ_BODY 2
#define NZ_ARMS 4
#define NZ_LEGS 8
static int nz_frenzy, nz_gauge, nz_mode_t, nz_dash_t = -1, nz_absorb, nz_hid = 0x41;
static unsigned nz_frame, nz_dbg[6];   // acertos, último id, último dano, esquivas, ecos tocados, mortes
static int nz_on(void) { return fg_nz && engine_obj.cur_character == 1 && g_Player.unk2 != 0; }
static int nz_has(int b) { return (fg_nz & b) != 0; }
static int nz_up(int b) { return (fg_nz & (b << 4)) != 0; }
static int nz_frenzy_cap(void) { return nz_up(NZ_HELM) ? 5 : 3; }
static int nz_gauge_max(void) { return nz_up(NZ_BODY) ? 12 : 20; }
static int nz_mode_len(void) { return nz_up(NZ_BODY) ? 300 : 180; }
static int nz_dodge_win(void) { return nz_up(NZ_LEGS) ? 14 : 8; }
static int nz_is_saber(int id) { return id >= 0x18 && id <= 0x23; }
static int nz_next_hid(void) { nz_hid += 2; if (nz_hid < 0x41 || nz_hid > 0x7D) nz_hid = 0x41; return nz_hid; }
#define NZ_REC 48
struct NzSwing { u8 on, live, id, hits; int start, n; s16 x[NZ_REC], y[NZ_REC]; u8 f[NZ_REC], k[NZ_REC], bk[NZ_REC], hit[NZ_REC], dmg[NZ_REC]; const void* box[NZ_REC]; s8 bg; };
static struct NzSwing nz_sw[8];
static struct WeaponObj* nz_sw_w[8];   // arma nossa que toca o eco
static s8 nz_slot_sw[16];
static u8 nz_pend_hit[16], nz_pend_dmg[16];
struct NzClone { u8 on, right; s16 x, y; int t; s8 bg; struct WeaponObj* w; };
static struct NzClone nz_cl[4];
static const u8 nz_clone_body[23] = { 105, 105, 107, 109, 111, 113, 115, 117, 119, 121, 123, 125, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127 };
static struct Unk_unk68 nz_clone_box[] = { { -32, -32, 64, 64 } };
static struct Unk_unk68 nz_cut_box[] = { { -85, -127, 170, 254 } };
// Giga
#define NZ_GG_DARK 32
#define NZ_GG_CUT 64
#define NZ_GG_SWING 12
#define NZ_GG_FLY 30
#define NZ_GG_SHEATH 32
#define NZ_GG_OUT 8
#define NZ_GG_END (NZ_GG_CUT + NZ_GG_SWING + NZ_GG_FLY + NZ_GG_SHEATH + NZ_GG_OUT)
#define NZ_GG_V 8
#define NZ_GG_POSE 105
#define NZ_GG_HOLD 127
static const u8 nz_gg_swing_body[NZ_GG_SWING] = { 107, 109, 111, 113, 115, 117, 119, 121, 123, 125, 127, 127 };
static const u8 nz_gg_swing_cut[NZ_GG_SWING] = { 0, 0, 2, 2, 3, 3, 4, 4, 5, 5, 5, 5 };
static int nz_gg_t = -1, nz_gg_req, nz_gg_dim;
static u8 nz_gg_right;
static s16 nz_gg_zx, nz_gg_zy, nz_gg_cx;
static s32 nz_gg_px, nz_gg_py;
static unsigned nz_gg_starts, nz_gg_denied;
static struct WeaponObj* nz_gg_w;
static int nz_gg_sheath_frame(int k)
{
    static const u8 fr[6] = { 130, 131, 132, 133, 134, 134 }, len[6] = { 6, 4, 6, 10, 6, 0 };
    for (int i = 0; i < 6; i++) { if (k < len[i]) return fr[i]; k -= len[i]; }
    return 0;
}
static int nz_mine(struct WeaponObj* w, int kind) { return w && w->active && w->state != 0 && FG_KIND(w) == kind; }
static struct WeaponObj* nz_box_new(int kind, int x, int y, int right)
{
    struct WeaponObj* w = fg_new_weapon();
    if (!w) return NULL;
    w->pad99[0] = (s8)kind; FG_AGE(w) = 0; FG_HIT(w) = 1; FG_VAR(w) = 0;
    w->x_pos.val = 0; w->y_pos.val = 0; w->x_pos.i.hi = (s16)x; w->y_pos.i.hi = (s16)y;
    w->unk15 = right ? PLAYER_FACING_RIGHT : 0; w->unk50 = NULL;
    return w;
}
static void nz_box_drop(struct WeaponObj** pw) { if (*pw && (*pw)->active && FG_KIND(*pw) >= 0xE0 && FG_KIND(*pw) <= 0xE2) fg_despawn(*pw, 0); *pw = NULL; }
static void nz_hp_set(int hp) { g_Player.hp = (s8)((g_Player.hp & 0x80) | (hp & 0x7F)); }
static void nz_gg_end(void)
{
    nz_gg_t = -1; nz_gg_dim = 0;
    nz_box_drop(&nz_gg_w);
}
static void nz_reset(void)
{
    nz_frenzy = nz_gauge = nz_mode_t = 0; nz_dash_t = -1; nz_absorb = 0;
    for (int j = 0; j < 8; j++) { nz_sw[j].on = 0; nz_box_drop(&nz_sw_w[j]); }
    for (int j = 0; j < 4; j++) { nz_cl[j].on = 0; nz_box_drop(&nz_cl[j].w); }
    for (int i = 0; i < 16; i++) { nz_slot_sw[i] = -1; nz_pend_hit[i] = nz_pend_dmg[i] = 0; }
    nz_gg_end(); nz_gg_req = 0;
}
static void nz_clone_spawn(void)
{
    for (int j = 0; j < 4; j++) {
        struct NzClone* c = &nz_cl[j];
        if (c->on) continue;
        c->on = 1; c->t = 0; c->x = g_Player.x_pos.i.hi; c->y = g_Player.y_pos.i.hi; c->right = g_Player.unk15 ? 1 : 0; c->bg = g_Player.bg_offset;
        c->w = nz_box_new(0xE1, c->x + (c->right ? 32 : -32), c->y - 8, c->right);
        if (c->w) c->w->bg_offset = c->bg;
        return;
    }
}
// dano no Zero (fg_reduce_damage): -1 = segue
int fg_nz_reduce(int dmg)
{
    int d = dmg, a = g_Player.unk5;
    if (!nz_on() || d <= 0 || d >= 127) return -1;
    if (nz_gg_t >= 0 || nz_mode_t > 0) { nz_absorb = 1; return 0; }   // (invencível)
    if (nz_has(NZ_LEGS) && (a == PLAYER_DASH || a == PLAYER_AIR_DASH)) {
        int dt = nz_dash_t < 0 ? 0 : nz_dash_t + 1;   // quadro do dash em que o golpe chegou
        if (dt < nz_dodge_win()) { nz_absorb = 1; nz_dbg[3]++; nz_clone_spawn(); return 0; }
        d += 1;
    }
    if (nz_has(NZ_HELM)) { d += 1; nz_frenzy = 0; }   // o golpe zera o Frenesi e tira 1 a mais
    return d > 126 ? 126 : d;
}
// golpe da Esquiva / do modo: sem recuo, pisca invencível um pouco e continua (o dash segue)
int fg_nz_hurt_skip(struct PlayerObj* p)
{
    if (!nz_absorb) return 0;
    nz_absorb = 0; p->hurt_phase = -1; p->invincibility_timer = 40;
    return 1;
}
// golpe do Zero num inimigo (func_8002DE30): dano a aplicar (-1 = segue o jogo)
int fg_nz_hit(struct MainObj* en, struct WeaponObj* w, int id, int dmg)
{
    int k, d, slot;
    if (!nz_on() || !w || FG_KIND(w) == 0xD9) return -1;   // (não no golpe do parceiro do co-op)
    if ((s8)en->unk63 == -1) return -1;   // escudo: ricocheteia (como o jogo)
    k = FG_KIND(w);
    if (k == 0xE0 || k == 0xE2) d = FG_VAR(w) ? FG_VAR(w) : 1;               // eco / corte do Giga
    else if (k == 0xE1) d = (nz_up(NZ_LEGS) ? 8 : 4) * (nz_mode_t > 0 ? 2 : 1);   // clone
    else if (nz_is_saber(id) || id == 0x3D || id == 0x3E) {
        if (dmg <= 0 || dmg >= 127) return -1;
        d = dmg;
        if (nz_has(NZ_HELM)) d += nz_frenzy;
        if (nz_mode_t > 0) d *= 2;
        slot = (int)(w - weapon_objects);
        if (nz_has(NZ_ARMS) && nz_is_saber(id) && slot >= 0 && slot < 16 && !nz_pend_hit[slot]) { nz_pend_hit[slot] = 1; nz_pend_dmg[slot] = (u8)(d > 126 ? 126 : d); }
        // Sobrecarga: cada acerto do Zero enche a barra (fora do modo Pesadelo)
        if (nz_has(NZ_BODY) && nz_mode_t <= 0 && ++nz_gauge >= nz_gauge_max()) { nz_gauge = 0; nz_mode_t = nz_mode_len(); fg_sfx(SFX_X6_SHADOW_GIGA); }
        nz_dbg[1] = (unsigned)id;
    } else return -1;
    if (d > 126) d = 126;
    nz_dbg[0]++; nz_dbg[2] = (unsigned)d;
    return d;
}
void fg_nz_kill(struct MainObj* en)
{
    (void)en;
    if (nz_has(NZ_HELM) && nz_frenzy < nz_frenzy_cap()) nz_frenzy++;
    nz_dbg[5]++;
}
// eco: grava os golpes do sabre e toca de novo os que acertaram
static void nz_echo_step(void)
{
    for (int slot = 0; slot < 16; slot++) {
        struct WeaponObj* o = &weapon_objects[slot];
        int saber = o->active && o->state != 0 && FG_KIND(o) == 0 && nz_is_saber((s8)o->id);
        int si = nz_slot_sw[slot];
        if (si >= 0 && (!saber || (u8)o->id != nz_sw[si].id)) { nz_sw[si].live = 0; nz_slot_sw[slot] = -1; si = -1; }
        if (saber && si < 0) {
            for (int j = 0; j < 8; j++) if (!nz_sw[j].on) { si = j; break; }
            if (si >= 0) {
                struct NzSwing* s = &nz_sw[si];
                s->on = 1; s->live = 1; s->id = (u8)o->id; s->hits = 0; s->start = (int)nz_frame; s->n = 0; s->bg = o->bg_offset;
                nz_slot_sw[slot] = (s8)si;
            }
        }
        if (si >= 0) {
            struct NzSwing* s = &nz_sw[si];
            if (s->n < NZ_REC) {
                int i = s->n++;
                s->x[i] = o->x_pos.i.hi; s->y[i] = o->y_pos.i.hi; s->f[i] = o->unk15 ? 1 : 0;
                s->k[i] = o->animation_step.fields.frame_index; s->box[i] = o->unk50;
                s->bk[i] = (const void*)o->unk3C == (const void*)SP_ARCHIVE_ENTRY(SP_SPRITE_FRAMES, 5);   // 2º banco do Zero (parede, golpes no ar)
                s->hit[i] = nz_pend_hit[slot]; s->dmg[i] = nz_pend_dmg[slot];
                if (s->hit[i]) s->hits++;
            }
        }
        nz_pend_hit[slot] = nz_pend_dmg[slot] = 0;
    }
    for (int j = 0; j < 8; j++) {
        struct NzSwing* s = &nz_sw[j];
        int i;
        if (!s->on) continue;
        if (!s->hits) { if (!s->live) s->on = 0; continue; }   // não acertou nada: sem eco
        i = (int)nz_frame - (s->start + 30);
        if (i >= -3 && !nz_mine(nz_sw_w[j], 0xE0)) { nz_sw_w[j] = nz_box_new(0xE0, s->x[0], s->y[0], s->f[0]); if (nz_sw_w[j]) nz_sw_w[j]->bg_offset = s->bg; }
        if (i < 0 || !nz_sw_w[j]) continue;
        if (i >= s->n) { if (!s->live) { nz_box_drop(&nz_sw_w[j]); s->on = 0; } else nz_sw_w[j]->unk50 = NULL; continue; }
        if (i == 0) nz_dbg[4]++;
        {
            struct WeaponObj* w = nz_sw_w[j];
            w->x_pos.i.hi = s->x[i]; w->y_pos.i.hi = s->y[i]; w->unk15 = s->f[i] ? PLAYER_FACING_RIGHT : 0;
            if (s->hit[i] && s->box[i]) {
                int dd = nz_up(NZ_ARMS) ? s->dmg[i] : (s->dmg[i] + 1) / 2;
                w->unk50 = s->box[i]; w->unk64 = (s8)nz_next_hid(); FG_VAR(w) = (s8)(dd < 1 ? 1 : dd);
            } else w->unk50 = NULL;
        }
    }
}
static void nz_clone_step(void)
{
    for (int j = 0; j < 4; j++) {
        struct NzClone* c = &nz_cl[j];
        if (!c->on) continue;
        if (++c->t >= (int)sizeof(nz_clone_body)) { c->on = 0; nz_box_drop(&c->w); continue; }
        if (!nz_mine(c->w, 0xE1)) continue;
        if (c->t == 3) { c->w->unk50 = nz_clone_box; c->w->unk64 = (s8)nz_next_hid(); } else c->w->unk50 = NULL;
    }
}
// Giga: baixo + Giga (chamado onde o jogo confere o Rakuhouha / Hyouretsuzan: consome o aperto)
int fg_nz_giga_check(struct PlayerObj* self)
{
    if (!nz_on() || (fg_nz & 0xF) != 0xF || nz_gg_t >= 0) return 0;
    if (!(self->input.buttons.held & PLAYER_INPUT_DOWN) || !(self->pressed_input & PLAYER_INPUT_GIGA)) return 0;
    nz_gg_req = 10;
    return 1;
}
static void nz_giga_step(void)
{
    struct PlayerObj* p = &g_Player;
    int dir, t, s, out0;
    if (nz_gg_req > 0 && nz_gg_t < 0 && (fg_nz & 0xF) == 0xF && nz_mode_t > 0 && p->unk5 != PLAYER_HURT && p->unk5 != PLAYER_SCRIPT_WAIT && HP_VALUE(p->hp) > 0) {
        nz_gg_t = 0; nz_gg_right = p->unk15 ? 1 : 0;
        nz_gg_px = p->x_pos.val; nz_gg_py = p->y_pos.val;
        nz_gg_zx = p->x_pos.i.hi; nz_gg_zy = p->y_pos.i.hi; nz_gg_cx = nz_gg_zx;
        nz_mode_t = 0;   // o Giga gasta o modo Pesadelo
        fg_sfx(SFX_X6_GIGA_DASH);
        nz_gg_req = 0; nz_gg_starts++;
    }
    if (nz_gg_req > 0 && --nz_gg_req == 0 && nz_gg_t < 0 && nz_mode_t <= 0) nz_gg_denied++;
    if (nz_gg_t < 0) return;
    dir = nz_gg_right ? 1 : -1;
    t = nz_gg_t;
    p->x_pos.val = nz_gg_px; p->y_pos.val = nz_gg_py;
    p->x_vel.val = 0; p->y_vel.val = 0; p->unk28 = 0; p->unk2C = 0;
    p->invincibility_timer = 2;
    out0 = NZ_GG_END - NZ_GG_OUT;
    nz_gg_dim = 31;
    if (t < NZ_GG_DARK) nz_gg_dim = t + 1 > 31 ? 31 : t + 1;
    else if (t >= out0) { nz_gg_dim = 31 - (t - out0 + 1) * 4; if (nz_gg_dim < 0) nz_gg_dim = 0; }
    if (t == NZ_GG_CUT) fg_sfx(SFX_X6_SHADOW_GIGA);
    s = t - NZ_GG_CUT;
    if (s == 6) {
        nz_gg_w = nz_box_new(0xE2, nz_gg_cx + dir * 120, nz_gg_zy - 75, nz_gg_right);
        if (nz_gg_w) { nz_gg_w->bg_offset = p->bg_offset; nz_gg_w->unk50 = nz_cut_box; nz_gg_w->unk64 = (s8)nz_next_hid(); FG_VAR(nz_gg_w) = 16; }
    }
    if (s == NZ_GG_SWING) fg_sfx(SFX_X6_BLADE_GIGA);
    if (s >= NZ_GG_SWING && s < NZ_GG_SWING + NZ_GG_FLY) nz_gg_cx = (s16)(nz_gg_cx + dir * NZ_GG_V);
    if (s >= 6 && s < NZ_GG_SWING + NZ_GG_FLY && nz_mine(nz_gg_w, 0xE2)) { nz_gg_w->x_pos.i.hi = (s16)(nz_gg_cx + dir * 120); nz_gg_w->y_pos.i.hi = (s16)(nz_gg_zy - 75); }
    if (s == NZ_GG_SWING + NZ_GG_FLY) nz_box_drop(&nz_gg_w);
    if (t + 1 >= NZ_GG_END) { nz_gg_end(); p->invincibility_timer = 0; } else nz_gg_t++;
}
int fg_nz_hide_player(void) { return nz_gg_t >= 0; }   // placeholder.c: o Godot desenha o Zero no Giga
int fg_nz_block_input(void) { return nz_gg_t >= 0; }    // runtime.c x4_frame: o Zero não obedece no Giga
// cor: as cores do Zero Nightmare do X6 (paleta da luta, na ordem de índices do Zero: o desenho é o mesmo) misturadas
// com a normal conforme as peças (40/65/85/100%), como o Black Zero; só troca a paleta normal que o jogo pôs
static const u16 nz_pal16[16] = { 0x0000, 0xBB66, 0xBB66, 0xBB66, 0xE657, 0xDDB3, 0xD90F, 0xC88B,
                                  0xEF1C, 0xF30C, 0xDDCB, 0xC88B, 0xE69A, 0xE1D8, 0xD575, 0xE238 };
static void nz_palette_step(void)
{
    static const int W[5] = { 0, 40, 65, 85, 100 };
    int n = (fg_nz & 1) + ((fg_nz >> 1) & 1) + ((fg_nz >> 2) & 1) + ((fg_nz >> 3) & 1);
    u16* cur = (u16*)SP_PALETTES[0];
    const u16* a = (const u16*)SP_PALETTE_BANK[0];
    if (!n || cur[5] != a[5]) return;
    for (int i = 0; i < 16; i++) {
        int c = 0;
        for (int sh = 0; sh < 15; sh += 5) {
            int x = (a[i] >> sh) & 31, y = (nz_pal16[i] >> sh) & 31;
            c |= ((x * (100 - W[n]) + y * W[n] + 50) / 100) << sh;
        }
        cur[i] = (u16)(c | (a[i] & 0x8000));
    }
    need_palette_load |= 1;
}
static void nz_tick(void)
{
    struct PlayerObj* p = &g_Player;
    int a = p->unk5, hp, mx, cap;
    nz_frame++;
    if (!nz_on()) { if (nz_frenzy || nz_gauge || nz_mode_t || nz_dash_t >= 0 || nz_gg_t >= 0) nz_reset(); return; }
    if (HP_VALUE(p->hp) == 0 || !p->active) { nz_reset(); return; }   // morreu: tudo volta a zero
    nz_palette_step();
    nz_dash_t = (a == PLAYER_DASH || a == PLAYER_AIR_DASH) ? nz_dash_t + 1 : -1;
    // Sobrecarga: vida até a metade da máxima; modo Pesadelo invencível (sem piscar: o tempo fica em 2)
    if (nz_has(NZ_BODY)) {
        mx = (u8)engine_obj.max_hp; cap = mx / 2; hp = HP_VALUE(p->hp);
        if (cap > 0 && hp > cap) nz_hp_set(cap);
    }
    if (nz_mode_t > 0) {
        if (p->invincibility_timer < 2 && p->hurt_phase == 0) p->invincibility_timer = 2;
        if (--nz_mode_t == 0 && p->hurt_phase == 0) p->invincibility_timer = 0;
    }
    if (nz_has(NZ_ARMS)) nz_echo_step();
    nz_clone_step();
    nz_giga_step();
}
// clarão branco do começo do fundo roxo (0-255) | 0x100 roxo | 0x200 rolando para a direita
static int nz_gg_flash(void)
{
    static const u8 fa[4] = { 255, 255, 170, 80 };
    int r;
    if (nz_gg_t < 0) return 0;
    r = nz_gg_t >= NZ_GG_CUT && nz_gg_t < NZ_GG_CUT + 4 ? fa[nz_gg_t - NZ_GG_CUT] : 0;
    if (nz_gg_t >= NZ_GG_CUT && nz_gg_t < NZ_GG_END - NZ_GG_OUT) r |= 0x100 | (nz_gg_right ? 0x200 : 0);
    return r;
}
// objetos para o Godot: [x, y, quadro do atlas do Zero, bandeiras] no mundo (como psx_embed.cpp nz_obj)
static long long nz_obj(int idx, int field)
{
    int n = 0;
    for (int j = 0; j < 8; j++) {
        struct NzSwing* s = &nz_sw[j];
        int i, a;
        if (!s->on || !s->hits) continue;
        i = (int)nz_frame - (s->start + 30);
        if (i < 0 || i >= s->n) continue;
        if (n++ != idx) continue;
        a = 220 - (i * 140) / (s->n > 1 ? s->n : 1);
        switch (field) { case 0: return s->x[i]; case 1: return s->y[i]; case 2: return s->k[i] + (s->bk[i] ? 1000 : 0);
                         default: return s->f[i] | (1 << 1) | (a << 8); }
    }
    for (int j = 0; j < 4; j++) {
        struct NzClone* c = &nz_cl[j];
        int body, a;
        if (!c->on) continue;
        body = nz_clone_body[c->t < (int)sizeof(nz_clone_body) ? c->t : (int)sizeof(nz_clone_body) - 1];
        a = c->t < 11 ? 230 : 230 - (c->t - 11) * 18;
        for (int part = 0; part < 2; part++) {
            if (n++ != idx) continue;
            switch (field) { case 0: return c->x; case 1: return c->y; case 2: return body + part;
                             default: return c->right | ((part ? 3 : 2) << 1) | ((a < 0 ? 0 : a) << 8); }
        }
    }
    if (nz_gg_t >= 0) {
        int t = nz_gg_t, s = t - NZ_GG_CUT, dir = nz_gg_right ? 1 : -1, zf = NZ_GG_POSE, glow, kinds[3] = { 4, 0, 0 }, nk = 1;
        if (s >= 0 && s < NZ_GG_SWING) zf = nz_gg_swing_body[s];
        else if (s >= NZ_GG_SWING && s < NZ_GG_SWING + NZ_GG_FLY) zf = NZ_GG_HOLD;
        else if (s >= NZ_GG_SWING + NZ_GG_FLY) zf = nz_gg_sheath_frame(s - NZ_GG_SWING - NZ_GG_FLY);
        glow = t < NZ_GG_CUT ? 70 + ((t * 23) % 110) + t * 2 : 0;
        if (t < NZ_GG_CUT) kinds[nk++] = 7;
        else if (s < NZ_GG_SWING) kinds[nk++] = 5;
        else if (s < NZ_GG_SWING + NZ_GG_FLY) kinds[nk++] = 6;
        for (int k = 0; k < nk; k++) {
            int kd = kinds[k], cut = kd == 5 || kd == 6;
            if (n++ != idx) continue;
            switch (field) { case 0: return cut ? (kd == 6 ? nz_gg_cx : nz_gg_zx) - dir * 32 : nz_gg_zx;
                             case 1: return cut ? nz_gg_zy - 64 : nz_gg_zy;
                             case 2: return kd == 5 ? nz_gg_swing_cut[s] : kd == 6 ? 5 : zf;
                             default: return nz_gg_right | (kd << 1) | ((kd == 7 ? (glow > 255 ? 255 : glow) : 255) << 8); }
        }
    }
    return idx < 0 ? n : 0;
}
// x4_mem 0x1F900790-0x1F9007FF (as do X5/X6): +0 máscara, +1 frenesi, +2 barra, +3 barra cheia, +4 modo, +5 duração,
// +6 máximo do frenesi, +7 ligado, +8.. contadores; 0x1F9007A0 objetos; F8/F9 Gigas feitos/negados; FA clarão; FB
// quadro do Giga; FC/FD câmera (mundo); FE escurecer (0-31, paletas da linha >= 483 = cenário); FF banco do sprite do Zero
long long fg_nz_query(unsigned addr, long long value, int size)
{
    struct BackgroundObj* bg = &background_objects[g_Player.bg_offset < 0 ? 0 : g_Player.bg_offset];
    if ((addr & 0xFFFFFFF0u) == 0x1F900790u) {
        unsigned o = addr & 0xF;
        if (size < 0 && o == 0) { if ((int)(u8)value != fg_nz) { fg_nz = (u8)value; nz_reset(); } }
        if (size < 0 && o == 2) nz_gauge = (int)value;                   // (testes)
        if (size < 0 && o == 3 && nz_on()) nz_clone_spawn();             // (testes)
        if (size < 0 && o == 4 && nz_on()) nz_mode_t = (int)value;       // (testes)
        if (size < 0 && o == 15) {   // (testes) traz o 1º inimigo vivo para x do Zero + valor (mesmo y), parado
            for (int i = 0; i < 0x30; i++) {
                struct MainObj* m = &main_objects[i];
                if (!m->active || (s8)m->hp <= 0 || !m->collision_data || !m->hurt_box) continue;
                m->x_pos.i.hi = (s16)(g_Player.x_pos.i.hi + (int)value); m->y_pos.i.hi = g_Player.y_pos.i.hi;
                return i | (m->id << 8) | ((u8)m->hp << 16);   // (teste: índice | id << 8 | vida << 16)
            }
            return -1;
        }
        switch (o) {
        case 0: return fg_nz;
        case 1: return nz_frenzy;
        case 2: return nz_gauge;
        case 3: return nz_gauge_max();
        case 4: return nz_mode_t;
        case 5: return nz_mode_len();
        case 6: return nz_frenzy_cap();
        case 7: return nz_on();
        default: return o < 14 ? nz_dbg[o - 8] : 0;
        }
    }
    switch (addr) {
    case 0x1F9007F8u: return nz_gg_starts;
    case 0x1F9007F9u: return nz_gg_denied;
    case 0x1F9007FAu: return nz_gg_flash();
    case 0x1F9007FBu: return nz_gg_t;
    case 0x1F9007FCu: return bg->x_pos.i.hi;
    case 0x1F9007FDu: return bg->y_pos.i.hi;
    case 0x1F9007FEu: return nz_gg_t >= 0 ? nz_gg_dim : 0;
    case 0x1F9007FFu: { extern u8 D_8011AF60[]; return g_Player.unk2 != 0 && D_8011AF60[(u8)g_Player.unk17] ? 1 : 0; }
    }
    if (addr == 0x1F9007A0u) return nz_obj(-1, 0);
    if (addr > 0x1F9007A0u && addr < 0x1F9007F8u) return nz_obj((int)(addr - 0x1F9007A1u) / 4, (int)(addr - 0x1F9007A1u) % 4);
    return 0;
}
void fg_nz_reset(void) { nz_reset(); }
void fg_nz_tick(void) { if (engine_obj.state != 6 || !g_Player.active) return; nz_tick(); }

// ---- co-op online (x4_mem 0x1F900900-0x1F90090F): o chefe tem a vida dos dois PCs (o Godot manda a menor) e, quando o
// parceiro vence o chefe dele, um golpe nosso derruba o daqui pelo caminho normal do jogo (morte, explosões, fim da fase).
// +0 leitura: tipo << 8 | vida do chefe (-1 = sem chefe); escrita: vida (só abaixa, mínimo 1). +1 escrita: golpe final.
static struct Unk_unk68 coop_kill_box[] = { { -48, -64, 96, 128 } };
static struct MainObj* coop_boss(void)
{
    struct MainObj* b = (struct MainObj*)engine_obj.boss_ptr;
    return (b && engine_obj.enable_boss && b->active) ? b : NULL;
}
int fg_coop_boss_alive(void) { struct MainObj* b = coop_boss(); return b && b->hp > 0; }
static unsigned coop_ghost_hits;   // (teste) acertos dos golpes do parceiro aqui
static struct WeaponObj* coop_gw[8];
static int coop_gkey[8] = { -1, -1, -1, -1, -1, -1, -1, -1 };   // golpe do parceiro em cada fantasma (vaga dele << 8 | id)
static u8 coop_gspent[8];   // golpe sem número (+0x64 = 0, ex. limão) que já acertou aqui: não acerta mais (lá ele sumiria)
int fg_coop_hit(struct MainObj* en, struct WeaponObj* w)   // 1E1BC.c func_8002DE30: -1 = não é nosso; -2 = não acerta
{
    if (w && FG_KIND(w) == 0xD9) {
        coop_ghost_hits++;
        if (!w->unk64) { for (int i = 0; i < 8; i++) if (coop_gw[i] == w) coop_gspent[i] = 1; w->unk50 = NULL; }
        return -1;
    }
    if (!w || FG_KIND(w) != 0xD8) return -1;
    return en == coop_boss() ? 127 : -2;
}
// golpes do jogador daqui (para o parceiro) e os do parceiro aqui (fantasmas): objetos nossos (0xD9, id 0x12: a rotina é a
// nossa) com a posição, o lado, a caixa e o número do golpe dele; o id da arma dele fica em FG_VAR e vale no func_8002DE30
// (imunidade, guarda e dano da tabela do inimigo como se fosse a arma dele; faísca/som do acerto também: o id dele fica no
// objeto durante o func_8002DE30). x4_mem 0x1F900910 quantos golpes daqui; 0x1F900911 + i*8 + campo: 0 id | golpe << 8 |
// direita << 16 | vaga << 24; 1 x; 2 y; 3 e 4 caixa (bytes); 5 quadro | desenho << 16 | banco << 17 (1 do jogador, 2 o 2º do
// Zero, 3 tiros do X). 0x1F900990.. campos do fantasma (0 id, 1 golpe, 2 direita, 3 x, 4 y, 5 caixa, 7 vaga dele);
// 0x1F900980 + i: 1 põe/renova (some sem renovar em 3 quadros), 0 tira. Golpe sem número (limão) acerta 1 vez.
static int coop_atk[8], coop_atk_n;
static struct Unk_unk68 coop_gbox[8];
static long long coop_st[8];
int fg_coop_ghost_id(struct WeaponObj* w) { return (w && FG_KIND(w) == 0xD9) ? (u8)FG_VAR(w) : -1; }
static void coop_atk_scan(void)
{
    coop_atk_n = 0;
    for (int i = 0; i < 0x10 && coop_atk_n < 8; i++) {
        struct WeaponObj* w = &weapon_objects[i];
        if (!w->active || w->state == 0 || FG_KIND(w) != 0 || !w->unk50) continue;
        coop_atk[coop_atk_n++] = i;
    }
}
static long long coop_atk_field(int n, int f)
{
    struct WeaponObj* w;
    const struct Unk_unk68* b;
    if (n < 0 || n >= coop_atk_n) return 0;
    w = &weapon_objects[coop_atk[n]];
    b = (const struct Unk_unk68*)w->unk50;
    switch (f) {
    case 0: return (u8)w->id | ((long long)(u8)w->unk64 << 8) | ((long long)(w->unk15 ? 1 : 0) << 16) | ((long long)coop_atk[n] << 24);
    case 1: return w->x_pos.i.hi;
    case 2: return w->y_pos.i.hi;
    case 3: case 4: return b ? ((u8)b->unk0 | ((u8)b->unk1 << 8) | (b->unk2 << 16) | ((long long)b->unk3 << 24)) : 0;
    case 5: {   // quadro | 1 << 16 com desenho | banco << 17 (1 o do jogador, 2 o 2º do Zero, 3 os tiros do X)
        const void* bk = (const void*)w->unk3C;
        int c = !bk ? 0 : bk == (const void*)SP_ARCHIVE_ENTRY(SP_SPRITE_FRAMES, 0) ? 1 : bk == (const void*)SP_ARCHIVE_ENTRY(SP_SPRITE_FRAMES, 5) ? 2 :
                bk == (const void*)SP_ARCHIVE_ENTRY(SP_SPRITE_FRAMES, 1) ? 3 : 0;
        return (long long)w->animation_step.fields.frame_index | ((long long)(bk && w->on_screen ? 1 : 0) << 16) | ((long long)c << 17);
    }
    }
    return 0;
}
static void coop_ghost_set(int i, int on)
{
    struct WeaponObj* w = coop_gw[i];
    long long bx = coop_st[5];
    int key = (int)(((coop_st[7] & 0xFF) << 8) | (coop_st[0] & 0xFF));
    if (w && (!w->active || FG_KIND(w) != 0xD9)) w = coop_gw[i] = NULL;
    if (!on || engine_obj.state != 6) { if (w) fg_despawn(w, 0); coop_gw[i] = NULL; coop_gkey[i] = -1; return; }
    if (key != coop_gkey[i]) { coop_gkey[i] = key; coop_gspent[i] = 0; }
    if (!w) { w = fg_new_weapon(); if (!w) return; w->pad99[0] = (s8)0xD9; coop_gw[i] = w; }
    FG_AGE(w) = 0; FG_VAR(w) = (s8)coop_st[0];
    w->x_pos.val = 0; w->y_pos.val = 0; w->x_pos.i.hi = (s16)coop_st[3]; w->y_pos.i.hi = (s16)coop_st[4];
    w->unk15 = coop_st[2] ? PLAYER_FACING_RIGHT : 0;
    coop_gbox[i].unk0 = (s8)(bx & 0xFF); coop_gbox[i].unk1 = (s8)((bx >> 8) & 0xFF);
    coop_gbox[i].unk2 = (u8)((bx >> 16) & 0xFF); coop_gbox[i].unk3 = (u8)((bx >> 24) & 0xFF);
    w->unk50 = coop_gspent[i] ? NULL : &coop_gbox[i];
    w->unk64 = coop_st[1] ? (s8)(0x60 + (coop_st[1] & 0x1F)) : 0;
    w->bg_offset = g_Player.bg_offset;
}
long long fg_coop_query(unsigned addr, long long value, int size)
{
    struct MainObj* b = coop_boss();
    unsigned o = addr - 0x1F900900u;
    if (o == 0x10) { coop_atk_scan(); return coop_atk_n; }                           // golpes daqui: quantos
    if (o > 0x10 && o < 0x10 + 1 + 8 * 8) return coop_atk_field((int)(o - 0x11) / 8, (int)(o - 0x11) % 8);
    if (o >= 0x80 && o < 0x88) { if (size < 0) coop_ghost_set((int)(o - 0x80), value != 0); return coop_gw[o - 0x80] != NULL; }
    if (o >= 0x90 && o < 0x98) { if (size < 0) coop_st[o - 0x90] = value; return coop_st[o - 0x90]; }
    if (o >= 0x10) return 0;
    switch (addr & 0xF) {
    case 0:
        if (!b) return -1;
        if (size < 0 && value >= 1 && value < b->hp) b->hp = (s8)value;
        return ((u8)b->id << 8) | (u8)(b->hp < 0 ? 0 : b->hp);
    case 14: return coop_ghost_hits;   // (teste) acertos dos golpes do parceiro aqui
    case 15:   // (teste) chefe de mentira: o inimigo main_objects[valor]
        if (size < 0 && value >= 0 && value < 0x30) { engine_obj.boss_ptr = (void*)&main_objects[value]; engine_obj.enable_boss = 1; }
        return 0;
    case 1:
        if (size < 0 && b && b->hp > 0) {
            struct WeaponObj* w = fg_new_weapon();
            if (!w) return 0;
            w->pad99[0] = (s8)0xD8; FG_AGE(w) = 0; FG_HIT(w) = 1; FG_VAR(w) = 0;
            w->x_pos.val = b->x_pos.val; w->y_pos.val = b->y_pos.val; w->bg_offset = b->bg_offset;
            w->unk15 = 0; w->unk50 = coop_kill_box; w->unk64 = 0x7D;
            return 1;
        }
        return 0;
    }
    return 0;
}
