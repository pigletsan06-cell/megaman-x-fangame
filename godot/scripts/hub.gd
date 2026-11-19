extends Control
## Hub do fangame: a tela de seleção de chefes de cada jogo (X4, X5, X6), copiada do próprio jogo.
## Primeiro escolhe o jogo (X4/X5/X6); ○/Esc volta para a escolha do jogo; setas escolhem o chefe; △ (V) abre a escolha X/Zero; L2/R2 (Q/W) troca a armadura;
## Z/Enter começa. Cada fase roda no motor original do seu jogo (scenes/fase.tscn).

const GAMES := ["x4", "x5", "x6"]
const NAMES := {
	"x4": {1: "Web Spider", 2: "Frost Walrus", 3: "Split Mushroom", 4: "Magma Dragoon",
		5: "Jet Stingray", 6: "Cyber Peacock", 7: "Storm Owl", 8: "Slash Beast"},
	"x5": {1: "Grizzly Slash", 2: "Dark Dizzy", 3: "Duff McWhalen", 4: "Mattrex",
		5: "Squid Adler", 6: "Izzy Glow", 7: "Axle the Red", 8: "The Skiver"},
	"x6": {1: "Commander Yammark", 2: "Blizzard Wolfang", 3: "Blaze Heatnix", 4: "Metal Shark Player",
		5: "Ground Scaravich", 6: "Rainy Turtloid", 7: "Shield Sheldon", 8: "Infinity Mijinion"},
}
# posição do cursor na tela original -> fase (assets/menus/<jogo>_<fase>.png é a tela com o cursor ali)
const POS_STAGE := {
	"x4": [1, 6, 7, 4, 5, 3, 8, 2],   # 2 linhas de 4 (0-3 em cima, 4-7 embaixo)
	"x5": [1, 5, 6, 3, 8, 7, 2, 4],   # 2 colunas de 4 (0-3 à esquerda, 4-7 à direita)
	"x6": [1, 6, 7, 2, 3, 8, 4, 5],   # hexágonos em volta do globo
}
# centro de cada retrato na tela (320x240), para marcar os chefes vencidos
const POS_XY := {
	"x4": [Vector2(48, 30), Vector2(122, 30), Vector2(197, 30), Vector2(268, 30),
		Vector2(48, 192), Vector2(122, 192), Vector2(197, 192), Vector2(268, 192)],
	"x5": [Vector2(48, 31), Vector2(48, 87), Vector2(48, 143), Vector2(48, 199),
		Vector2(272, 31), Vector2(272, 87), Vector2(272, 143), Vector2(272, 199)],
	"x6": [Vector2(64, 68), Vector2(122, 44), Vector2(204, 44), Vector2(262, 68),
		Vector2(64, 166), Vector2(122, 190), Vector2(204, 190), Vector2(262, 166)],
}
const ARMORS := {
	# X4: armadura montada peça por peça (C/□ abre a montagem) ou uma Ultimate inteira
	"x4": [["montada", 1, false, "*"], ["Ultimate (X4)", 1, true],
		["Ultimate (X5)", 1, false, "Ultimate_X5"], ["Ultimate (X6)", 1, false, "Ultimate_X6"]],
	"x5": [["Fourth", 1], ["Falcon", 2], ["Gaea", 3], ["Ultimate", 4], ["montada", 1, false, "*"]],
	"x6": [["sem armadura", 0], ["Falcon", 1], ["Shadow", 2], ["Blade", 3], ["Ultimate", 4], ["montada", 0, false, "*"]],
}
const ZERO_CODE := {"x4": 1, "x5": 5, "x6": 5}
# variantes do Zero (o 3º campo liga o Black Zero)
const ZERO_ARMORS := [["Zero", 0], ["Black Zero", 0, true]]
# X4: o Black Zero é montado com as peças ganhas nos desafios (ZeroDesafios)
const ZERO_ARMORS_X4 := [["Zero", 0], ["Black Zero", 0, "bz"], ["Nightmare Zero", 0, "nz"]]
# X5 e X6: Black Zero com as peças dos desafios do X4 e Nightmare Zero com as dos desafios do X6 (valem nos dois)
const ZERO_ARMORS_X6 := [["Zero", 0], ["Black Zero", 0, "bz"], ["Nightmare Zero", 0, "nz"]]
# como cada jogo liga o segredo (Ultimate X / Black Zero): X4 usa a flag do código secreto (engine_obj.unk37)
const SECRET_POKE := {"x5": [0xD1C4A, 0x10, 1], "x6": [0xCCF2F, 0x20, 1]}
# fases finais de cada jogo (liberadas depois dos 8 chefes daquele jogo): [fase, nome]
const FINALS := {
	"x4": [[10, "Space Port"], [11, "Final Weapon 1"], [12, "Final Weapon 2"]],
	"x5": [[9, "Dynamo"], [16, "Zero Space 1"], [17, "Zero Space 2"], [18, "Zero Space 3"], [12, "Zero Space 4"]],
	"x6": [[16, "Gate's Lab 1"], [17, "Gate's Lab 2"], [18, "Gate's Lab 3"], [12, "Sigma"]],
}

static var page := 0
static var in_page := false   # false: tela de escolha do jogo (ao chegar do título)
static var cursor := {"x4": 0, "x5": 0, "x6": 0}
static var is_zero := false
static var armor_idx := {"x4": 0, "x5": 0, "x6": 0}
static var zero_idx := {"x4": 0, "x5": 0, "x6": 0}

func _armors(g: String) -> Array:
	if is_zero: return ZERO_ARMORS_X4 if g == "x4" else ZERO_ARMORS_X6
	return ARMORS[g]

func _armor(g: String) -> Array:
	var a := _armors(g)
	var idx: Dictionary = zero_idx if is_zero else armor_idx
	return a[clampi(idx[g], 0, a.size() - 1)]

func _cycle_armor(g: String, d: int) -> void:
	var n := _armors(g).size()
	if is_zero: zero_idx[g] = (zero_idx[g] + n + d) % n
	else: armor_idx[g] = (armor_idx[g] + n + d) % n

var progress := {"x4": [], "x5": [], "x6": []}   # = FangameSave.cur().progress (slot em uso)
var slot_box: Control
var slot_open := false
static var slot_sel := 0
var slot_mode := ""   # "" | "apagar" (confirmação) | "copiar" (escolhendo o destino)
var slot_src := 0
var screen: TextureRect
var marks: Control
var bar: Label
var tex_cache := {}
var finals_open := false
static var final_sel := 0
var finals_box: Control
var music: AudioStreamPlayer
var music_page := -1
var flash: ColorRect
var fx: _Fx
var t_anim := 0.0
# ---- estilo dos menus (MmxUI / MmxPanel): painéis animados, barra de baixo desenhada, aviso da armadura ----
static var pad_mode := false   # último botão veio do controle (as dicas mostram os botões dele; senão as teclas)
var bar_cv: _Canvas
var bar_info := ""             # linha de cima da barra: à esquerda (jogo, chefe) e à direita (personagem, chefes)
var bar_info_r := ""
var bar_hints: Array = []      # [botão do controle, tecla, ação]
var pn_arm: MmxPanel           # menu da armadura (C / □)
var pn_status: MmxPanel
var pn_finals: MmxPanel
var pn_coop: MmxPanel
var arm_cv: _Canvas
var char_open := false         # escolha do personagem (△ / V): o aviso PERSONAGEM fica aberto e ←→ troca X / Zero
var char_open_t := 0.0
var char_t := -9.0             # relógio da última troca (brilho no cartão)
var toast_cv: _Canvas
var toast_t := -9.0; var toast_kind := ""
var arm_flash := {}            # peça -> relógio do brilho
var arm_change_t := 0.0        # relógio da última mudança (texto digitando)
var arm_full_t := -9.0
var arm_msg := ""; var arm_msg_t := -9.0
var arm_open_t := 0.0
static var arm_row := 0        # -1 = personagem (X / Zero); 0 = conjunto / variante; 1-4 = peças
var arm_launch := false        # o menu abriu ao escolher a fase: confirmar começa a fase (Esc volta para os chefes)
var arm_final := -1            # fase final escolhida (-1 = a do Maverick)
static var zero_half := 0      # Zero: 0 = a peça, 1 = a melhoria dela

func _ready() -> void:
	Opcoes.apply(get_tree()); Opcoes.menu_mode(get_tree(), true)
	var from_stage := not X4Machine.last_result.is_empty()
	_load_progress()
	size = Vector2(320, 240)
	var bg := ColorRect.new(); bg.color = Color.BLACK; bg.size = size; add_child(bg)
	screen = TextureRect.new(); screen.size = size
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.stretch_mode = TextureRect.STRETCH_SCALE; screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(screen)
	var sm := ShaderMaterial.new(); sm.shader = load("res://shaders/chefes_vencidos.gdshader"); screen.material = sm
	marks = Control.new(); add_child(marks)
	fx = _Fx.new(); fx.hub = self; fx.size = size; fx.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(fx)
	flash = ColorRect.new(); flash.visible = false; add_child(flash)   # (antigo; o brilho do cursor agora é o fx)
	music = AudioStreamPlayer.new(); add_child(music)
	theme = MmxUI.theme()
	bar = Label.new(); bar.visible = false; add_child(bar)   # (texto antigo da barra: só guarda o aviso)
	jogo_box = _GameSelect.new(); jogo_box.hub = self; jogo_box.size = size; add_child(jogo_box)
	bar_cv = _Canvas.new(); bar_cv.fn = _bar_draw; bar_cv.size = size; add_child(bar_cv)
	toast_cv = _Canvas.new(); toast_cv.fn = _toast_draw; toast_cv.size = size; add_child(toast_cv)
	pn_arm = MmxPanel.make(self, Rect2(6, 10, 308, 206), "ARMADURA", MmxUI.C_ACCENT)
	arm_cv = _Canvas.new(); arm_cv.fn = _arm_draw; arm_cv.size = pn_arm.size; pn_arm.content.add_child(arm_cv)
	pn_status = MmxPanel.make(self, Rect2(4, 8, 312, 208), "STATUS DO HUNTER", MmxUI.C_ACCENT)
	pn_finals = MmxPanel.make(self, Rect2(66, 56, 188, 118), "FASES FINAIS", MmxUI.C_GOLD)
	pn_coop = MmxPanel.make(self, Rect2(14, 16, 292, 200), "CO-OP ONLINE", MmxUI.C_ACCENT)
	if not from_stage and not in_page: jogo_open = true; jogo_sel = page
	if in_page and not jogo_open: _auto_finals(GAMES[page])
	_refresh()

func _load_progress() -> void:
	FangameSave.load_file()
	if FangameSave.slot < 0:   # sem save escolhido: vai para a tela dos saves (no título)
		TitleScreen.start_state = "saves"
		get_tree().call_deferred("change_scene_to_file", "res://scenes/title.tscn")
		return
	else:
		_use_slot()
	var r: Dictionary = X4Machine.last_result
	if not r.is_empty() and r.get("game", "") in GAMES and FangameSave.slot >= 0:
		FangameSave.apply_result(r.game, int(r.stage), r.get("won", false), r.get("save_start", {}), r.get("save_end", {}))
	if not r.is_empty() and r.has("zst6"): r["zst"] = ZeroDesafios.from_x6(r.zst6)   # X6: mesmas regras
	if not r.is_empty() and r.get("char", 0) == 1 and r.has("zst") and FangameSave.slot >= 0:   # desafio do Zero
		var k := ZeroDesafios.apply(FangameSave.cur(), r.game, int(r.stage), r.get("won", false), r.zst)
		if k != "":
			FangameSave.write()
			new_part_msg = "%s: %s liberado!" % ["Black Zero" if r.game == "x4" else "Nightmare Zero", ZeroDesafios.prize_label(r.game, k.split(":")[1])]
		else:   # venceu de Zero mas não cumpriu o desafio (e ainda não tem o prêmio): mostra o que faltou
			var c := ZeroDesafios.info(r.game, int(r.stage))
			if r.get("won", false) and not c.is_empty() and not ZeroDesafios.has(FangameSave.cur(), r.game, c[0]):
				new_part_msg = "Desafio não cumprido (%s): %s" % [ZeroDesafios.describe(r.game, int(r.stage)), ZeroDesafios.measured(c, r.zst)]
	X4Machine.last_result = {}
	if FangameSave.slot >= 0 and FangameSave.cur().has("new_part"):   # programa de armadura pego na fase
		var k: String = str(FangameSave.cur().new_part)
		FangameSave.cur().erase("new_part"); FangameSave.write()
		var a := k.split(":")
		new_part_msg = "Peça nova: %s - %s (C/□ na página do X4)" % [FangameParts.NAME.get(a[0], a[0]), FangameParts.SLOT_NAME.get(a[1], a[1])]

var new_part_msg := ""

func _use_slot() -> void:
	progress = FangameSave.cur().progress

# ---- tela dos saves (3 slots: jogar, copiar, apagar) ----
func _draw_slots() -> void:
	if slot_box: slot_box.queue_free(); slot_box = null
	if not slot_open: return
	slot_box = Panel.new(); slot_box.position = Vector2(20, 40); slot_box.size = Vector2(280, 150)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.02, 0.03, 0.1, 0.94); sb.border_color = Color(0.3, 0.8, 1); sb.set_border_width_all(2)
	slot_box.add_theme_stylebox_override("panel", sb)
	add_child(slot_box)
	var t := Label.new(); t.position = Vector2(0, 6); t.size = Vector2(280, 12)
	t.text = {"": "SAVE DO FANGAME (X4 + X5 + X6)", "apagar": "APAGAR O SAVE %d? Confirme de novo" % (slot_sel + 1),
		"copiar": "COPIAR O SAVE %d PARA QUAL?" % (slot_src + 1)}[slot_mode]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; t.add_theme_font_size_override("font_size", 8)
	if slot_mode != "": t.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
	slot_box.add_child(t)
	for i in FangameSave.SLOTS:
		var l := Label.new(); l.position = Vector2(10, 26 + i * 30); l.size = Vector2(262, 28)
		l.text = ("> " if i == slot_sel else "   ") + "SAVE %d\n      %s" % [i + 1, FangameSave.summary(i)]
		l.add_theme_font_size_override("font_size", 8)
		if i == slot_sel: l.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		slot_box.add_child(l)
	var h := Label.new(); h.position = Vector2(0, 122); h.size = Vector2(280, 24)
	h.text = "Z/Start: jogar   C/□: copiar   Del/△: apagar\nVida máxima e sub tanks valem nos 3 jogos"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; h.add_theme_font_size_override("font_size", 7)
	slot_box.add_child(h)

func _slot_input(e: InputEvent) -> void:
	var n: int = FangameSave.SLOTS
	if _key(e, KEY_UP) or _joy(e, JOY_BUTTON_DPAD_UP): slot_sel = (slot_sel + n - 1) % n
	elif _key(e, KEY_DOWN) or _joy(e, JOY_BUTTON_DPAD_DOWN): slot_sel = (slot_sel + 1) % n
	elif _key(e, KEY_DELETE) or _key(e, KEY_V) or _joy(e, JOY_BUTTON_Y):
		if slot_mode == "apagar": FangameSave.erase(slot_sel); slot_mode = ""
		else: slot_mode = "apagar"
	elif _key(e, KEY_C) or _key(e, KEY_X) or _joy(e, JOY_BUTTON_X):
		if slot_mode == "copiar":
			if slot_sel != slot_src: FangameSave.copy(slot_src, slot_sel)
			slot_mode = ""
		else: slot_mode = "copiar"; slot_src = slot_sel
	elif _key(e, KEY_ESCAPE) or _joy(e, JOY_BUTTON_B):
		if slot_mode != "": slot_mode = ""
		elif FangameSave.slot >= 0: slot_open = false
	elif e.is_action_pressed("jump") or _key(e, KEY_ENTER) or _joy(e, JOY_BUTTON_START) or _joy(e, JOY_BUTTON_A):
		if slot_mode == "copiar":
			if slot_sel != slot_src: FangameSave.copy(slot_src, slot_sel)
			slot_mode = ""
		elif slot_mode == "apagar": slot_mode = ""
		else:
			FangameSave.select(slot_sel); _use_slot(); slot_open = false
	else: return
	if slot_mode == "apagar" and not (_key(e, KEY_DELETE) or _key(e, KEY_V) or _joy(e, JOY_BUTTON_Y)): slot_mode = ""
	get_viewport().set_input_as_handled()
	_refresh()

func _tex(name: String) -> Texture2D:
	if not tex_cache.has(name):
		var path := ProjectSettings.globalize_path("res://assets/menus/%s.png" % name)
		var img := Image.new()
		tex_cache[name] = ImageTexture.create_from_image(img) if FileAccess.file_exists(path) and img.load(path) == OK else null
	return tex_cache[name]

var _jogo_seen := false
func _refresh() -> void:
	if jogo_open != _jogo_seen:   # a escolha do jogo apareceu: os cartões entram de novo
		_jogo_seen = jogo_open
		if jogo_open: jogo_box.t_open = 0.0
	var g: String = GAMES[page]
	MmxUI.set_skin(GAMES[clampi(jogo_sel, 0, 2)] if jogo_open else g)   # os menus com o visual do menu de pausa do jogo
	var pos: int = cursor[g]
	var stage: int = POS_STAGE[g][pos]
	jogo_box.visible = jogo_open
	jogo_box.queue_redraw()
	if jogo_open:
		if music_page != -2: _play_title_music()
		bar.text = ""; bar_info = ""; bar_info_r = ""
		screen.visible = false; fx.visible = false
		_draw_status(); _draw_slots()
		return
	screen.visible = true; fx.visible = true
	screen.texture = _tex("%s_%d" % [g, stage]) if intro_t < 0.0 else screen.texture
	var vm := 0
	for p in 8:
		if POS_STAGE[g][p] in progress[g]: vm |= 1 << p
	var sm: ShaderMaterial = screen.material
	sm.set_shader_parameter("donos", _tex("donos/%s_%d" % [g, pos]))
	sm.set_shader_parameter("vencidos", 0 if intro_t >= 0.0 else vm)
	if music_page != page: _play_music(g)
	for c in marks.get_children(): c.queue_free()
	var who: String = _armor(g)[0] if is_zero else "X: %s" % _armor(g)[0]
	if is_zero and FangameSave.slot >= 0:   # Black Zero (peças do X4) / Nightmare Zero (peças do X6): quantas peças
		var ztag := str(_armor(g)[2]) if _armor(g).size() > 2 else ""
		if ztag == "bz": who = "Black Zero %d/4" % ZeroDesafios.count(FangameSave.cur(), "x4")
		if ztag == "nz": who = "Nightmare Zero %d/4" % ZeroDesafios.count(FangameSave.cur(), "x6")
	if not is_zero and _armor(g).size() > 3 and _armor(g)[3] == "*":
		var fs := FangameParts.full_set(FangameSave.cur().parts)
		who = "X: %s" % (FangameParts.NAME.get(fs, fs) if fs != "" else "montada")
	var total := 0
	for k in GAMES: total += progress[k].filter(func(v): return v >= 1 and v <= 8).size()
	bar.text = ""
	bar_info = "%s · %s" % [g.to_upper(), str(NAMES[g][stage]).to_upper()]
	bar_info_r = "%s    %d/24" % [who, total]
	if is_zero and (g == "x4" or g == "x6") and FangameSave.slot >= 0:   # desafio do Zero nesta fase
		var c := ZeroDesafios.info(g, stage)
		var sv := FangameSave.cur()
		if not c.is_empty():
			var ok := ZeroDesafios.has(sv, g, c[0])
			bar_info_r = "%s  desafio: %s → %s%s" % [who, ZeroDesafios.describe(g, stage), ZeroDesafios.prize_label(g, c[0]), " ✓" if ok else ""]
	if Coop.on(): bar_info = "CO-OP %s · " % ("P1" if Coop.is_host() else "P2") + bar_info
	if new_part_msg != "": bar.text = new_part_msg
	_draw_finals()
	_draw_build()
	_draw_status()
	_draw_slots()

# ---- tela de status (Tab / R3): armaduras pegas, onde estão as que faltam, corações, sub tanks, chefes ----
const STATUS_ARMORS := ["Fourth_X4", "Fourth_X5", "Falcon_X5", "Gaea_X5", "Falcon_X6", "Blade_X6", "Shadow_X6"]
# onde fica a cápsula de cada peça (X4: nome da fase do chefe)
const X4_CAP_STAGE := {"helmet": 6, "body": 4, "arms": 7, "legs": 1}
var status_open := false
static var status_sel := 0
var status_box: Control

func _status_input(e: InputEvent) -> void:
	var nst := STATUS_ARMORS.size() + 2   # + Black Zero e Nightmare Zero
	if _key(e, KEY_LEFT) or _joy(e, JOY_BUTTON_DPAD_LEFT): status_sel = (status_sel + nst - 1) % nst; _sfx("menu_move")
	elif _key(e, KEY_RIGHT) or _joy(e, JOY_BUTTON_DPAD_RIGHT): status_sel = (status_sel + 1) % nst; _sfx("menu_move")
	elif _key(e, KEY_TAB) or _key(e, KEY_I) or _key(e, KEY_ESCAPE) or _key(e, KEY_ENTER) or e.is_action_pressed("jump") or _joy(e, JOY_BUTTON_B) \
			or _joy(e, JOY_BUTTON_A) or _joy(e, JOY_BUTTON_START) or _joy(e, JOY_BUTTON_RIGHT_STICK) or _joy(e, JOY_BUTTON_LEFT_STICK):
		status_open = false; _sfx("menu_close")
	else: return
	get_viewport().set_input_as_handled()
	_refresh()

func _part_where(sk: String, slot: String) -> String:   # de onde vem a peça
	if sk in FangameParts.START_UNLOCKED: return "liberada desde o começo"
	if sk == "Fourth_X4": return "cápsula na fase do %s (X4)" % NAMES.x4[X4_CAP_STAGE[slot]]
	for g in ["x5", "x6"]:
		for st in FangameSave.CAPSULE[g]:
			if FangameSave.CAPSULE[g][st] == [sk, slot]: return "cápsula na fase do %s (%s)" % [NAMES[g][st], g.to_upper()]
	return "?"

func _draw_status() -> void:
	if status_open and not pn_status.shown(): pn_status.open()
	elif not status_open and pn_status.shown(): pn_status.close()
	if not status_open: return
	for c in pn_status.content.get_children(): c.queue_free()
	pn_status.title = "STATUS DO HUNTER  -  SAVE %d" % (FangameSave.slot + 1)
	var sv := FangameSave.cur()
	var cv := _Canvas.new(); cv.size = pn_status.size; cv.fn = _status_draw; pn_status.content.add_child(cv)
	# chefes vencidos: os retratos da tela de seleção de cada jogo (só com uma armadura escolhida)
	if status_sel >= STATUS_ARMORS.size(): return
	for gi in GAMES.size():
		var g: String = GAMES[gi]
		for pos in 8:
			var stg: int = POS_STAGE[g][pos]
			var won: bool = stg in sv.progress[g]
			var tex := _tex("mini/%s_%d%s" % [g, stg, "_cinza" if won else ""])   # vencido = cinza (igual à seleção e aos saves)
			if tex == null: continue
			var tr := TextureRect.new(); tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture = tex; tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			tr.position = Vector2(30 + (stg - 1) * 30, 150 + gi * 17); tr.size = Vector2(27, 15)
			pn_status.content.add_child(tr)

func _status_draw(ci: Control) -> void:
	if FangameSave.slot < 0: return
	var sv := FangameSave.cur()
	var n_all := STATUS_ARMORS.size() + 2
	for i in n_all:
		var r := Rect2(6 + i * 33.5, 12, 31, 60).abs()
		r.position = r.position.round()
		var on := i == status_sel
		var cols := {}; var n := 0; var full := false; var label := ""; var fk := ""
		if i < STATUS_ARMORS.size():
			var sk: String = STATUS_ARMORS[i]
			var cc: Array = ARM_COL.get(sk, ARM_COL[""])
			for p in FangameParts.SLOTS:
				var ok: bool = FangameParts.is_unlocked(sv, sk, p) or (sk == "Fourth_X4" and p == "arms" and FangameParts.is_unlocked(sv, "Fourth_X4P", p))
				if ok: n += 1
				cols[p] = [cc[0], cc[1], ok]
			full = n == 4; label = "%d/4" % n
			if full: fk = sk
		else:
			var gz: String = ["x4", "x6"][i - STATUS_ARMORS.size()]
			var zk := "bz" if gz == "x4" else "nz"
			var nup := 0
			for p in ZeroDesafios.SLOTS:
				var ok := ZeroDesafios.has(sv, gz, p)
				if ok: n += 1
				if ZeroDesafios.has(sv, gz, p + "+"): nup += 1
				cols[p] = [ARM_COL[zk][0], ARM_COL[zk][1], ok]
			full = n == 4 and nup == 4; label = "%d+%d" % [n, nup]
			if n == 4: fk = zk
		MmxUI.inset(ci, r, MmxUI.C_SEL if on else (MmxUI.C_GOLD if full else MmxUI.C_EDGE_LO))
		if on: ci.draw_rect(r.grow(1), Color(1, 0.86, 0.3, 0.35 + 0.25 * sin(t_anim * TAU * 1.5)), false, 1.0)
		var bglow := (0.5 + 0.5 * sin(t_anim * TAU * 1.1)) if fk != "" else 0.0
		MmxUI.badge(ci, Vector2(r.get_center().x, r.position.y + 25), 12.0, cols, fk, bglow)
		MmxUI.text(ci, Vector2(r.position.x, r.end.y - 2), label, MmxUI.C_GOLD if full else MmxUI.C_TEXT, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# detalhes do cartão escolhido
	var y := 84.0
	if status_sel < STATUS_ARMORS.size():
		var sk0: String = STATUS_ARMORS[status_sel]
		var title := str(FangameParts.NAME.get(sk0, sk0)).to_upper()
		if FangameParts.GIGA.has(sk0) and _status_full(sv, sk0): title += "   COMPLETA · Giga: %s" % FangameParts.GIGA[sk0]
		MmxUI.text(ci, Vector2(8, y), title, MmxUI.C_SEL)
		for pi in FangameParts.SLOTS.size():
			var p: String = FangameParts.SLOTS[pi]
			var ok: bool = FangameParts.is_unlocked(sv, sk0, p) or (sk0 == "Fourth_X4" and p == "arms" and FangameParts.is_unlocked(sv, "Fourth_X4P", p))
			var yy := y + 11 + pi * 10
			MmxUI.text(ci, Vector2(10, yy), "✓" if ok else "·", MmxUI.C_GOOD if ok else MmxUI.C_DIM)
			MmxUI.text(ci, Vector2(20, yy), str(FangameParts.SLOT_NAME[p]), MmxUI.C_TEXT)
			MmxUI.text(ci, Vector2(70, yy), MmxUI.fit("pega" if ok else _part_where(sk0, p), 230), MmxUI.C_GOOD if ok else MmxUI.C_DIM)
		var falta := FangameSave.hearts_to_next(sv)
		var stn := FangameSave.st_found(sv)
		MmxUI.text(ci, Vector2(8, 138), "Heart tanks %d/%d (%s)   Sub tanks %d/%d (%d%%)   Vida máx. %d" % [mini(int(sv.hearts), FangameSave.MAX_HEARTS),
			FangameSave.MAX_HEARTS, ("faltam %d p/ +vida" % falta) if falta > 0 else "vida no máximo", stn, FangameSave.MAX_SUBTANKS, FangameSave.ST_PCT[stn], FangameSave.max_hp(sv)], MmxUI.C_TEXT)
		for gi in GAMES.size():
			var g: String = GAMES[gi]
			MmxUI.text(ci, Vector2(8, 161 + gi * 17), g.to_upper(), MmxUI.C_ACCENT)
			MmxUI.text(ci, Vector2(272, 161 + gi * 17), "%d/8" % _bosses_done(g), MmxUI.C_GOOD if _bosses_done(g) == 8 else MmxUI.C_TEXT)
	else:
		var gz: String = ["x4", "x6"][status_sel - STATUS_ARMORS.size()]
		var nbz := ZeroDesafios.count(sv, gz)
		var head := ("BLACK ZERO  (jogando de Zero no X4, X5 e X6)%s" % ("   COMPLETO · Giga: baixo + R2" if nbz == 4 else "")) if gz == "x4" \
			else "NIGHTMARE ZERO  (Zero no X4, X5 e X6)  %s" % ("COMPLETO · Giga: baixo + R2 no Pesadelo" if nbz == 4 else "peças de alto risco")
		MmxUI.text(ci, Vector2(8, y), MmxUI.fit(head, 296), MmxUI.C_SEL)
		var row := 0
		for prize in ["helmet", "body", "arms", "legs", "helmet+", "body+", "arms+", "legs+"]:
			var stg := 0
			var tb := ZeroDesafios.table(gz)
			for k in tb: if tb[k][0] == prize: stg = k
			var ok := ZeroDesafios.has(sv, gz, prize)
			var col := MmxUI.C_GOLD if ok else MmxUI.C_DIM
			var yy := y + 12 + row * 13
			MmxUI.text(ci, Vector2(8, yy), ("✓ " if ok else "· ") + MmxUI.fit(ZeroDesafios.prize_label(gz, prize), 92), col)
			MmxUI.text(ci, Vector2(104, yy), MmxUI.fit(str(NAMES[gz][stg]) if stg > 0 else "-", 66), MmxUI.C_TEXT if ok else MmxUI.C_DIM)
			MmxUI.text(ci, Vector2(172, yy), MmxUI.fit(ZeroDesafios.describe(gz, stg), 132), col)
			row += 1

func _status_full(sv: Dictionary, sk: String) -> bool:
	for p in FangameParts.SLOTS:
		if not FangameParts.is_unlocked(sv, sk, p): return false
	return true

# ---- tela de montagem da armadura (X4): cada peça de uma armadura ----
var build_open := false
static var build_row := 0
var build_box: Control

func _build_choices(slot: String) -> Array:   # armaduras liberadas para esta peça
	var s := FangameSave.cur()
	return FangameParts.CHOICES[slot].filter(func(k): return FangameParts.is_unlocked(s, k, slot))

func _build_input(e: InputEvent) -> void:
	var g: String = GAMES[page]
	var nrows := 1 if is_zero and _zero_variant(g) == "zero" else 5
	if arm_row >= nrows: arm_row = 0
	var r0 := -1 if arm_launch else 0   # na hora de jogar, a 1ª linha é o personagem
	var up := _key(e, KEY_UP) or _joy(e, JOY_BUTTON_DPAD_UP)
	var dn := _key(e, KEY_DOWN) or _joy(e, JOY_BUTTON_DPAD_DOWN)
	var lf := _key(e, KEY_LEFT) or _joy(e, JOY_BUTTON_DPAD_LEFT)
	var rt := _key(e, KEY_RIGHT) or _joy(e, JOY_BUTTON_DPAD_RIGHT)
	if up or dn:
		var n := nrows - r0
		if n > 1:
			arm_row = r0 + (arm_row - r0 + (n - 1 if up else 1)) % n; arm_change_t = t_anim; _sfx("menu_move")
	elif _key(e, KEY_Q) or _key(e, KEY_W):
		_arm_cycle_preset(g, -1 if _key(e, KEY_Q) else 1)
	elif lf or rt:
		var d := -1 if lf else 1
		if arm_row < 0:   # X <-> Zero
			is_zero = not is_zero; char_t = t_anim; arm_change_t = t_anim
			for p in FangameParts.SLOTS: arm_flash[p] = t_anim
			_sfx("menu_equip")
		elif arm_row == 0: _arm_cycle_preset(g, d)
		elif is_zero: zero_half = 1 - zero_half; arm_change_t = t_anim; _sfx("menu_move")   # peça <-> melhoria
		else: _arm_change_piece(g, arm_row - 1, d)
	elif _key(e, KEY_ESCAPE) or _joy(e, JOY_BUTTON_B):
		build_open = false; arm_launch = false; _sfx("menu_back")
	elif _key(e, KEY_C) or _key(e, KEY_X) or _key(e, KEY_ENTER) or e.is_action_pressed("jump") \
			or _joy(e, JOY_BUTTON_X) or _joy(e, JOY_BUTTON_A) or _joy(e, JOY_BUTTON_START):
		build_open = false
		if arm_launch and not (_key(e, KEY_C) or _joy(e, JOY_BUTTON_X)):   # pronto: começa a fase
			arm_launch = false; _sfx("menu_ok"); get_viewport().set_input_as_handled(); _start(arm_final); return
		arm_launch = false; _sfx("menu_ok")
	else: return
	get_viewport().set_input_as_handled()
	_refresh()

## abre o menu da armadura para jogar a fase escolhida (personagem, conjunto e peças; confirmar começa)
func _abre_missao(final_stage := -1) -> void:
	build_open = true; arm_launch = true; arm_final = final_stage; arm_row = -1
	_sfx("menu_open")

# ---- escolha do personagem (△ / V): o aviso PERSONAGEM fica aberto, ←→ troca X / Zero ----
func _char_input(e: InputEvent) -> void:
	var lf := _key(e, KEY_LEFT) or _joy(e, JOY_BUTTON_DPAD_LEFT)
	var rt := _key(e, KEY_RIGHT) or _joy(e, JOY_BUTTON_DPAD_RIGHT)
	if lf or rt:
		is_zero = not is_zero; char_t = t_anim
		_sfx("menu_move")
	elif _key(e, KEY_V) or _joy(e, JOY_BUTTON_Y) or _key(e, KEY_ESCAPE) or _joy(e, JOY_BUTTON_B) or _key(e, KEY_ENTER) \
			or _key(e, KEY_C) or e.is_action_pressed("jump") or _joy(e, JOY_BUTTON_A) or _joy(e, JOY_BUTTON_X) or _joy(e, JOY_BUTTON_START):
		char_open = false; toast_t = t_anim - 1.5; toast_kind = "char"   # o aviso sai deslizando
		_sfx("menu_ok")
	else: return
	_refresh()

func _draw_build() -> void:   # (o menu é desenhado a cada quadro em _arm_draw; aqui só abre/fecha)
	pn_arm.title = "MISSÃO" if arm_launch else "ARMADURA"
	if build_open and not pn_arm.shown(): pn_arm.open(); arm_open_t = t_anim; arm_change_t = t_anim + 0.35
	elif not build_open and pn_arm.shown(): pn_arm.close()

# ---- menu da armadura (C / □): conjunto (as armaduras do jogo, L2/R2) e, na "montada", peça por peça; holograma
# (boneco genérico de peças geométricas, desenho original) com as cores de cada peça ----
const ARM_COL := MmxUI.ARM_COL
const ARM_NAME := {"Ultimate_X4": "Ultimate (X4)", "Ultimate_X5": "Ultimate (X5)", "Ultimate_X6": "Ultimate (X6)"}
const ARM_GIGA := {"Ultimate_X4": "Nova Strike", "Ultimate_X5": "Nova Strike", "Ultimate_X6": "Nova Strike"}

func _arm_is_custom(g: String) -> bool:
	var a := _armor(g)
	return not is_zero and a.size() > 3 and str(a[3]) == "*"

# armadura de um conjunto (todas as peças iguais)
func _arm_preset_key(g: String, a: Array) -> String:
	if a.size() > 3 and str(a[3]) != "*": return str(a[3])
	if g == "x4": return "Ultimate_X4" if a.size() > 2 and a[2] is bool and a[2] else ""
	if g == "x5": return str({1: "Fourth_X5", 2: "Falcon_X5", 3: "Gaea_X5", 4: "Ultimate_X5"}.get(int(a[1]), ""))
	return str({1: "Falcon_X6", 2: "Shadow_X6", 3: "Blade_X6", 4: "Ultimate_X6"}.get(int(a[1]), ""))

func _arm_parts(g: String) -> Dictionary:
	if _arm_is_custom(g): return FangameSave.cur().parts
	var k := _arm_preset_key(g, _armor(g))
	return {"helmet": k, "body": k, "arms": k, "legs": k}

func _arm_key_name(k: String) -> String:
	return str(ARM_NAME.get(k, FangameParts.NAME.get(k, k)))

func _arm_preset_name(g: String) -> String:
	var a := _armor(g)
	if _arm_is_custom(g): return "Montada"
	return str(a[0])

func _arm_giga(g: String) -> String:
	if is_zero: return ""
	var parts := _arm_parts(g)
	if _arm_is_custom(g): return FangameParts.giga_name(parts)
	var k := str(parts.helmet)
	return str(ARM_GIGA.get(k, FangameParts.GIGA.get(k, "")))

func _arm_cycle_preset(g: String, d: int) -> void:
	_cycle_armor(g, d)
	if is_zero and _zero_variant(g) == "zero": arm_row = 0
	_sfx("menu_equip")
	for p in FangameParts.SLOTS: arm_flash[p] = t_anim
	arm_change_t = t_anim
	toast_t = t_anim; toast_kind = "armor"

func _arm_change_piece(g: String, i: int, d: int) -> void:
	var slot: String = FangameParts.SLOTS[i]
	if not _arm_is_custom(g):
		_sfx("menu_error"); arm_msg = "Escolha MONTADA no conjunto para trocar peça por peça"; arm_msg_t = t_anim; return
	var ch := _build_choices(slot)
	if ch.size() <= 1:
		_sfx("menu_error"); arm_msg = "Só tem esta peça: pegue as cápsulas nas fases"; arm_msg_t = t_anim; return
	var parts: Dictionary = FangameSave.cur().parts
	var was := FangameParts.full_set(parts)
	var j := ch.find(str(parts[slot]))
	parts[slot] = ch[(maxi(j, 0) + d + ch.size()) % ch.size()]
	FangameSave.write()
	arm_flash[slot] = t_anim; arm_change_t = t_anim
	var now := FangameParts.full_set(parts)
	if now != "" and now != was: _sfx("menu_full"); arm_full_t = t_anim
	else: _sfx("menu_equip")

func _arm_draw(ci: Control) -> void:
	_arm_draw_lista(ci)

func _zero_variant(g: String) -> String:   # "zero", "bz" (Black Zero) ou "nz" (Nightmare Zero)
	var a := _armor(g)
	var zt := str(a[2]) if a.size() > 2 else ""
	return "nz" if zt == "nz" else ("bz" if zt == "bz" or (a.size() > 2 and a[2] is bool) else "zero")

# descrição completa de cada peça do Zero (o que o x4core / a recompilação fazem)
const ZERO_DESC := {
	"bz": {"helmet": "Cura ao matar: cada inimigo destruído com o sabre devolve 1 de vida.",
		"helmet+": "Cura no chefe: a cada 5 golpes de sabre no chefe, recupera 1 de vida.",
		"body": "Leva só 3/4 do dano e não é empurrado pelos golpes.",
		"body+": "Leva só metade do dano (e continua sem ser empurrado).",
		"arms": "Sabre mais forte: +1 de dano em cada golpe e corta inimigos com escudo.",
		"arms+": "O 3º golpe do combo solta uma onda que atravessa os inimigos (some na parede).",
		"legs": "Até 2 dashes no ar.",
		"legs+": "Pulo extra no ar, sem perder o embalo do dash."},
	"nz": {"helmet": "Frenesi: cada inimigo destruído sem levar dano soma +1 de dano em todo golpe (até +3). Levar um golpe zera o bônus e esse golpe tira 1 a mais.",
		"helmet+": "O Frenesi vai até +5.",
		"body": "Sobrecarga: a vida não passa da metade. Cada acerto enche a barra do Pesadelo (20 acertos); cheia, dá 3 s invencível com dano dobrado.",
		"body+": "A barra do Pesadelo enche com 12 acertos e o modo dura 5 s.",
		"arms": "Eco do pesadelo: o golpe de sabre que acertou se repete meio segundo depois, no mesmo lugar, com metade do dano.",
		"arms+": "O eco tira o dano inteiro.",
		"legs": "Esquiva no limite: golpe logo no começo do dash não tira vida e um clone corta ali (4 de dano). Golpe no resto do dash tira 1 a mais.",
		"legs+": "A janela da esquiva fica maior e o clone tira 8."},
}

func _zero_prize_text(zv: String, prize: String) -> String:
	var gz := "x6" if zv == "nz" else "x4"
	var tb := ZeroDesafios.table(gz)
	var how := ""
	for st in tb:
		if str(tb[st][0]) == prize: how = " Desafio: %s (fase do %s, %s)." % [ZeroDesafios.describe(gz, st), NAMES[gz][st], gz.to_upper()]
	var got := ZeroDesafios.has(FangameSave.cur(), gz, prize)
	return str(ZERO_DESC[zv][prize]) + how + (" Ganha!" if got else "")

# o que cada peça do Zero faz (Black Zero: desafios do X4; Nightmare Zero: do X6)
const ZERO_TXT := {
	"bz": {"helmet": "cura ao matar", "helmet+": "cura no chefe", "body": "dano x3/4", "body+": "dano pela metade",
		"arms": "sabre +1 de dano", "arms+": "onda no 3º golpe", "legs": "2 dashes no ar", "legs+": "pulo extra no ar"},
	"nz": {"helmet": "Frenesi", "helmet+": "frenesi até +5", "body": "Sobrecarga", "body+": "pesadelo mais longo",
		"arms": "Eco do pesadelo", "arms+": "eco com dano inteiro", "legs": "Esquiva no limite", "legs+": "esquiva maior"},
}
var _re_tag := RegEx.create_from_string("^(.*?) \\((X\\d)\\)(.*)$")

# nome sem o "(X5)" + a etiqueta do jogo: ["Fourth Plasma", "X4"]
func _arm_name_tag(nm: String) -> Array:
	var m := _re_tag.search(nm)
	if m: return [(m.get_string(1) + m.get_string(3)).strip_edges(), m.get_string(2)]
	return [nm, ""]

func _arm_grad(ci: Control, pts: PackedVector2Array, r: Rect2, c0: Color, c1: Color, mid := 1.0) -> void:
	var cols := PackedColorArray()
	for v in pts: cols.append(c0.lerp(c1, clampf((v.x - r.position.x) / (r.size.x * mid), 0.0, 1.0)))
	ci.draw_polygon(pts, cols)

# hexágono com as duas cores da armadura (vazio = sem armadura; on = false: apagado)
func _arm_hex_icon(ci: Control, c: Vector2, r: float, key: String, on: bool, pop := 0.0) -> void:
	var rr := r * (1.0 + 0.25 * pop)
	var hx := MmxUI.hexagon(c, rr, PI / 6.0)
	var hl := hx.duplicate(); hl.append(hx[0])
	ci.draw_colored_polygon(hx, Color(0.02, 0.04, 0.1, 0.95))
	if key == "":
		ci.draw_polyline(hl, MmxUI.C_EDGE_LO, 1.0)
		ci.draw_line(c + Vector2(-3, 0), c + Vector2(3, 0), MmxUI.C_DIM, 1.0)
		return
	var cc: Array = ARM_COL.get(key, ARM_COL[""])
	var prim: Color = cc[0]; var sec: Color = cc[1]
	if not on:   # ainda não ganha: as cores apagadas
		MmxUI.color_chip(ci, c, rr * 0.8, prim.lerp(Color(0.1, 0.14, 0.24), 0.75), sec.lerp(Color(0.1, 0.14, 0.24), 0.75))
		ci.draw_polyline(hl, MmxUI.C_EDGE_LO, 1.0)
		return
	MmxUI.color_chip(ci, c, rr * 0.8, prim, sec)
	ci.draw_polyline(hl, sec if sec.get_luminance() > 0.3 else sec.lightened(0.35), 1.0)
	if pop > 0.0: ci.draw_polyline(hl, Color(1, 1, 1, pop), 2.0)

# etiqueta pequena (X4/X5/X6, GIGA...) e devolve a largura
func _arm_pill(ci: Control, pos: Vector2, txt: String, col: Color, filled := false) -> float:
	var w := MmxUI.text_width(txt) + 6.0
	var r := Rect2(pos, Vector2(w, 10))
	ci.draw_rect(r, Color(col, 0.9) if filled else Color(col, 0.16))
	ci.draw_rect(r, col, false, 1.0)
	MmxUI.text(ci, pos + Vector2(3, 8), txt, Color(0.02, 0.05, 0.14) if filled else col)
	return w

func _arm_draw_lista(ci: Control) -> void:
	var g: String = GAMES[page]
	if FangameSave.slot < 0: return
	var sv := FangameSave.cur()
	var custom := _arm_is_custom(g)
	var parts := _arm_parts(g)
	var app := clampf((t_anim - arm_open_t - 0.22) / 0.5, 0.0, 1.0)
	var giga := _arm_giga(g)
	var full_key := ""
	if not is_zero: full_key = FangameParts.full_set(parts) if custom else str(parts.helmet)
	var zv := _zero_variant(g) if is_zero else ""
	var row := arm_row if arm_row < 0 else (0 if zv == "zero" else arm_row)
	var bob := roundf(1.0 + 1.0 * sin(t_anim * TAU * 2.0))
	# ---- fundo: riscas diagonais andando ----
	var x := -220.0 + fmod(t_anim * 6.0, 14.0)
	while x < 310.0:
		ci.draw_line(Vector2(x, 204), Vector2(x + 200, 4), Color(0.4, 0.75, 1.0, 0.03), 1.0)
		x += 14.0
	# ---- conjunto / variante: faixa grande em cima ----
	var s0 := roundf((1.0 - MmxUI.ease_out(app * 1.5)) * 50.0)
	var r0 := Rect2(8 + s0, 8, 292, 38)
	var sel0 := row == 0
	var lst := _armors(g); var idx: int = (zero_idx if is_zero else armor_idx)[g]
	var hk := zv if is_zero else (full_key if full_key != "" else ("" if custom else _arm_preset_key(g, _armor(g))))
	var hc: Array = ARM_COL.get(hk, ARM_COL[""])
	var hcol: Color = hc[0] if hk != "" else MmxUI.C_ACCENT.darkened(0.45)
	if hcol.get_luminance() < 0.25: hcol = hcol.lightened(0.25)
	var p0 := MmxUI.shape(r0, 9.0)
	_arm_grad(ci, p0, r0, Color(hcol, 0.6), Color(0.0, 0.02, 0.08, 0.88), 0.7)
	var sw := fmod(t_anim, 3.4) / 0.9   # brilho passando
	if sw < 1.0:
		var sx := r0.position.x + lerpf(-30.0, r0.size.x + 30.0, sw)
		var shine := PackedVector2Array([Vector2(maxf(sx, r0.position.x + 9), r0.position.y + 1), Vector2(minf(sx + 14, r0.end.x), r0.position.y + 1),
			Vector2(clampf(sx + 4, r0.position.x, r0.end.x), r0.end.y - 1), Vector2(clampf(sx - 10, r0.position.x, r0.end.x), r0.end.y - 1)])
		# nas pontas o brilho achata (pontos repetidos): sem desenhar (o Godot reclamava no log a cada quadro)
		if not Geometry2D.triangulate_polygon(shine).is_empty(): ci.draw_colored_polygon(shine, Color(1, 1, 1, 0.08 * sin(sw * PI)))
	MmxUI.frame(ci, r0, MmxUI.C_GOLD if sel0 else MmxUI.C_ACCENT, 9.0, false)
	if sel0:
		var pl0 := MmxUI.shape(r0.grow(1.0), 10.0); pl0.append(pl0[0])
		ci.draw_polyline(pl0, Color(1, 0.86, 0.35, 0.35 + 0.35 * sin(t_anim * TAU * 1.4)), 1.0)
	var bc := Vector2(r0.position.x + 22, r0.get_center().y)
	if is_zero:
		_arm_hex_icon(ci, bc, 14.0, zv, true)
	else:
		var bcols := {}
		for slot in FangameParts.SLOTS:
			var kk := FangameParts.asset(str(parts.get(slot, "")))
			var c2: Array = ARM_COL.get(kk, ARM_COL[""])
			bcols[slot] = [c2[0], c2[1], kk != ""]
		MmxUI.badge(ci, bc, 14.0, bcols, full_key, clampf(1.0 - (t_anim - arm_full_t) / 0.8, 0.0, 1.0))
	var tx := r0.position.x + 44.0
	MmxUI.text(ci, Vector2(tx, r0.position.y + 12), "VARIANTE" if is_zero else "CONJUNTO", Color(0.75, 0.85, 1.0))
	var pn: Array = _arm_name_tag(_arm_preset_name(g))
	var pname := str(pn[0]).to_upper()
	var nx := tx + (13.0 if sel0 else 0.0)
	if sel0:
		MmxUI.text(ci, Vector2(tx - bob, r0.position.y + 32), "◀", MmxUI.C_SEL)
		MmxUI.text(ci, Vector2(nx + MmxUI.text_width(pname, 18) + 4 + bob, r0.position.y + 32), "▶", MmxUI.C_SEL)
	MmxUI.text(ci, Vector2(nx, r0.position.y + 34), pname, MmxUI.C_SEL if sel0 else Color.WHITE, 18)
	if str(pn[1]) != "": _arm_pill(ci, Vector2(nx + MmxUI.text_width(pname, 18) + (16 if sel0 else 6), r0.position.y + 23), str(pn[1]), Color(hc[1]))
	for i in lst.size():   # posição na lista
		var on := i == clampi(idx, 0, lst.size() - 1)
		ci.draw_rect(Rect2(r0.end.x - 12 - (lst.size() - 1 - i) * 7, r0.position.y + 6, 4, 4), MmxUI.C_SEL if on else MmxUI.C_EDGE_LO)
	if full_key != "":
		var bst := clampf(1.0 - (t_anim - arm_full_t) / 0.8, 0.0, 1.0)
		var gc := MmxUI.C_GOLD.lerp(Color.WHITE, bst * 0.7)
		var cr := Rect2(r0.end.x - 74, r0.end.y - 16, 64, 11)
		ci.draw_rect(cr, Color(gc, 0.14 + 0.1 * sin(t_anim * TAU * 1.2)))
		ci.draw_rect(cr, gc, false, 1.0)
		MmxUI.text(ci, Vector2(cr.position.x, cr.position.y + 9), "COMPLETA", gc, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	var pvr := Rect2(8 + roundf((1.0 - MmxUI.ease_out(app * 1.4)) * -40.0), 50, ARM_LX - 12, 98)
	_arm_draw_preview(ci, pvr, parts, zv)
	if arm_launch:   # personagem: em cima da prévia, ←→ troca X / Zero
		var pr := Rect2(pvr.position.x, pvr.end.y + 2, pvr.size.x, 13)   # logo embaixo da prévia
		var on := row < 0
		MmxUI.inset(ci, pr)
		if on: MmxUI.sel_bar(ci, pr, t_anim, MmxUI.C_ACCENT, false)
		var nm := "ZERO" if is_zero else "X"
		var nw := MmxUI.text_width(nm)
		var cx := pr.get_center().x
		MmxUI.text(ci, Vector2(cx - nw * 0.5, pr.position.y + 10), nm, MmxUI.C_SEL if on else Color.WHITE)
		if on:
			MmxUI.text(ci, Vector2(pr.position.x + 3 - bob, pr.position.y + 10), "◀", MmxUI.C_SEL)
			MmxUI.text(ci, Vector2(pr.end.x - 9 + bob, pr.position.y + 10), "▶", MmxUI.C_SEL)
		var pl := MmxUI.shape(pvr, 7.0); pl.append(pl[0])
		ci.draw_polyline(pl, MmxUI.C_GOLD if on else Color(MmxUI.C_EDGE_LO, 0.9), 1.0)
	# ---- peças do X ----
	if not is_zero:
		for i in 4:
			var slot: String = FangameParts.SLOTS[i]
			var sl := roundf((1.0 - MmxUI.ease_out(app * 1.6 - (i + 1) * 0.12)) * 60.0)
			var r := Rect2(ARM_LX + sl, 50 + i * 25, 300 - ARM_LX, 23)
			var on_row := arm_row == i + 1
			var pk := str(parts.get(slot, ""))
			var key := FangameParts.asset(pk)
			var cc: Array = ARM_COL.get(key, ARM_COL[""])
			var rp := MmxUI.shape(r, 6.0)
			ci.draw_colored_polygon(rp, Color(0.0, 0.02, 0.08, 0.8))
			if key != "":
				var pc: Color = cc[0]
				if pc.get_luminance() < 0.25: pc = pc.lightened(0.3)
				_arm_grad(ci, rp, r, Color(pc, 0.45 if on_row else 0.28), Color(pc, 0.0), 0.6)
			if on_row: MmxUI.sel_bar(ci, r, t_anim)
			var rl := rp.duplicate(); rl.append(rp[0])
			ci.draw_polyline(rl, MmxUI.C_GOLD if on_row else Color(MmxUI.C_EDGE_LO, 0.9), 1.0)
			var fl := clampf(1.0 - (t_anim - float(arm_flash.get(slot, -9.0))) / 0.35, 0.0, 1.0)
			if fl > 0.0: ci.draw_colored_polygon(rp, Color(1, 1, 1, 0.3 * fl))
			_arm_hex_icon(ci, Vector2(r.position.x + 14, r.get_center().y), 8.5, key, true, fl)
			MmxUI.text(ci, Vector2(r.position.x + 28, r.position.y + 9), str(FangameParts.SLOT_NAME[slot]).to_upper(), Color(0.6, 0.7, 0.88))
			var nt: Array = _arm_name_tag(_arm_key_name(pk))
			var nm := str(nt[0])
			var ncol := (MmxUI.C_SEL if on_row else Color.WHITE) if custom else Color(0.72, 0.78, 0.9)
			var ax := r.position.x + 28.0
			if on_row and custom:
				MmxUI.text(ci, Vector2(ax - bob, r.position.y + 20), "◀", MmxUI.C_SEL)
				ax += 9.0
			MmxUI.text(ci, Vector2(ax, r.position.y + 20), nm, ncol)
			var ex := ax + MmxUI.text_width(nm) + 4.0
			if str(nt[1]) != "": ex += _arm_pill(ci, Vector2(ex, r.position.y + 12), str(nt[1]), Color(cc[1]).lightened(0.2) if Color(cc[1]).get_luminance() < 0.3 else Color(cc[1])) + 3.0
			if on_row and custom: MmxUI.text(ci, Vector2(ex + bob, r.position.y + 20), "▶", MmxUI.C_SEL)
			if not custom:
				MmxUI.text(ci, Vector2(r.position.x, r.position.y + 15), "do conjunto", MmxUI.C_DIM, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8)
			else:   # liberadas: um segmento por armadura (dourado = a escolhida)
				var ch: Array = FangameParts.CHOICES[slot]
				var unl := _build_choices(slot)
				var tot := ch.size() - 1
				var j := 0
				for k in ch:
					if str(k) == "": continue
					var cur: bool = str(k) == pk
					var lit: bool = k in unl
					var sr := Rect2(r.end.x - 10 - (tot - j) * 5, r.position.y + 6, 3, 11)
					ci.draw_rect(sr, MmxUI.C_SEL if cur else (MmxUI.C_ACCENT if lit else Color(0.07, 0.13, 0.26)))
					j += 1
				MmxUI.text(ci, Vector2(r.end.x - 12 - tot * 5 - 40, r.position.y + 15), "%d/%d" % [unl.size() - 1, tot], MmxUI.C_DIM, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, 36)
	# ---- peças do Black / Nightmare Zero ----
	elif zv == "zero":
		MmxUI.text(ci, Vector2(ARM_LX + 6, 66), "O Zero deste jogo, sem as peças", MmxUI.C_DIM)
		MmxUI.text(ci, Vector2(ARM_LX + 6, 78), "dos desafios.", MmxUI.C_DIM)
	else:
		var gz := "x6" if zv == "nz" else "x4"
		var zc: Array = ARM_COL.get(zv, ARM_COL[""])
		var zcol: Color = zc[0]
		if zcol.get_luminance() < 0.25: zcol = Color(zc[1])
		for i in 4:   # cada linha: a peça (esquerda) e a melhoria dela (direita)
			var slot: String = FangameParts.SLOTS[i]
			var sl2 := roundf((1.0 - MmxUI.ease_out(app * 1.6 - (i + 1) * 0.12)) * 60.0)
			var r2 := Rect2(ARM_LX + sl2, 50 + i * 25, 300 - ARM_LX, 23)
			var on_row := row == i + 1
			var zp := MmxUI.shape(r2, 6.0)
			ci.draw_colored_polygon(zp, Color(0.0, 0.02, 0.08, 0.8))
			for h in 2:
				var prize := slot + ("+" if h == 1 else "")
				var ok := ZeroDesafios.has(sv, gz, prize)
				var hw := r2.size.x / 2.0
				var hr := Rect2(r2.position.x + h * hw, r2.position.y, hw, r2.size.y)
				if ok: _arm_grad(ci, PackedVector2Array([hr.position, Vector2(hr.end.x, hr.position.y), hr.end, Vector2(hr.position.x, hr.end.y)]), hr, Color(zcol, 0.3), Color(zcol, 0.0), 0.8)
				if on_row and zero_half == h: MmxUI.sel_bar(ci, hr.grow_individual(-1, -1, -1, -1), t_anim, MmxUI.C_ACCENT, h == 0)
				_arm_hex_icon(ci, Vector2(hr.position.x + 11, hr.get_center().y), 7.0 if h == 0 else 6.0, zv, ok)
				var lab := str(ZeroDesafios.SLOT_NAME[slot]).to_upper() if h == 0 else "MELHORIA"
				MmxUI.text(ci, Vector2(hr.position.x + 21, hr.position.y + 9), lab, Color(0.6, 0.7, 0.88))
				if ok: MmxUI.text(ci, Vector2(hr.end.x - 10, hr.position.y + 9), "✓", MmxUI.C_GOLD)
				MmxUI.text(ci, Vector2(hr.position.x + 21, hr.position.y + 20), MmxUI.fit(str(ZERO_TXT[zv][prize]), hw - 24), (MmxUI.C_SEL if on_row and zero_half == h else Color.WHITE) if ok else MmxUI.C_DIM)
			ci.draw_line(Vector2(r2.position.x + r2.size.x / 2.0, r2.position.y + 4), Vector2(r2.position.x + r2.size.x / 2.0, r2.end.y - 4), Color(MmxUI.C_EDGE_LO, 0.8), 1.0)
			var zl := zp.duplicate(); zl.append(zp[0])
			ci.draw_polyline(zl, MmxUI.C_GOLD if on_row else Color(MmxUI.C_EDGE_LO, 0.9), 1.0)
	# ---- Giga ----
	var gy := 151.0
	var gx := ARM_LX if arm_launch else 10.0   # na missão, à esquerda fica o personagem
	if giga != "":
		var gon := full_key != ""
		var gw := _arm_pill(ci, Vector2(gx, gy), "GIGA", MmxUI.C_GOLD if gon else MmxUI.C_DIM, gon)
		MmxUI.text(ci, Vector2(gx + 4 + gw, gy + 8), giga, MmxUI.C_GOLD if gon else MmxUI.C_DIM)
	elif not is_zero:
		MmxUI.text(ci, Vector2(gx, gy + 8), "Giga: 4 peças da mesma armadura", MmxUI.C_DIM)
	elif zv != "zero":
		MmxUI.text(ci, Vector2(gx, gy + 8), "↑↓ peça   ←→ peça / melhoria", MmxUI.C_DIM)
	# ---- descrição (embaixo), digitando ----
	var dr := Rect2(8, 166, 292, 35)
	MmxUI.frame(ci, dr, MmxUI.C_ACCENT, 6.0)
	var desc := ""
	if row < 0:
		desc = ("Zero: o espadachim. Com as peças dos desafios vira Black Zero ou Nightmare Zero (desça para escolher)." if is_zero
			else "X: com a armadura deste jogo ou montada peça por peça (desça para escolher).") + " Confirme para jogar."
	elif is_zero and row > 0:
		desc = _zero_prize_text(zv, FangameParts.SLOTS[row - 1] + ("+" if zero_half == 1 else ""))
	elif is_zero:
		if zv == "nz":
			desc = "Nightmare Zero: peças de alto risco ganhas nos desafios do Zero no X6 (valem nos 3 jogos). %d/4 peças." % ZeroDesafios.count(sv, "x6")
		elif zv == "bz":
			desc = "Black Zero: peças ganhas nos desafios do Zero no X4 (valem nos 3 jogos). %d/4 peças." % ZeroDesafios.count(sv, "x4")
		else:
			desc = "Zero: o espadachim, sem as peças dos desafios."
	elif row == 0:
		if custom: desc = "Montada: cada peça de uma armadura (as liberadas nas cápsulas das fases). Desça para escolher peça por peça."
		elif str(parts.helmet) == "": desc = "Sem armadura: o X sem nenhuma peça."
		else: desc = "%s inteira, com as habilidades dela neste jogo.%s" % [_arm_key_name(str(parts.helmet)), (" Giga: %s." % giga) if giga != "" else ""]
	else:
		var slot3: String = FangameParts.SLOTS[arm_row - 1]
		var pk3 := str(parts.get(slot3, ""))
		desc = "%s: %s" % [_arm_key_name(pk3), FangameParts.desc(pk3, slot3) if custom else "a peça do conjunto. Escolha MONTADA para trocar."]
	var shown := int(maxf(0.0, t_anim - arm_change_t) * 150.0)
	var lines := MmxUI.wrap(desc, dr.size.x - 14)
	var n := 0
	var cur_pos := Vector2(-1, -1)
	for li in mini(lines.size(), 3):
		var ln: String = lines[li]
		var vis := clampi(shown - n, 0, ln.length())
		n += ln.length() + 1
		if vis > 0:
			var pos := Vector2(dr.position.x + 7, dr.position.y + 11 + li * 10)
			MmxUI.text(ci, pos, ln.substr(0, vis), MmxUI.C_TEXT)
			cur_pos = pos + Vector2(MmxUI.text_width(ln.substr(0, vis)) + 1, -7)
	if cur_pos.x >= 0.0 and fmod(t_anim, 0.8) < 0.45:   # cursor piscando
		ci.draw_rect(Rect2(cur_pos, Vector2(4, 7)), Color(MmxUI.C_ACCENT, 0.85))
	if t_anim - arm_msg_t < 2.2:   # aviso (peça travada etc.)
		var ma := clampf((2.2 - (t_anim - arm_msg_t)) / 0.4, 0.0, 1.0)
		var mr := Rect2(dr.position.x + 10, dr.position.y - 15, dr.size.x - 20, 12)
		ci.draw_rect(mr, Color(0.25, 0.04, 0.02, 0.92 * ma)); ci.draw_rect(mr, Color(1, 0.5, 0.3, ma), false, 1.0)
		MmxUI.text(ci, Vector2(mr.position.x, mr.position.y + 9), arm_msg, Color(1, 0.75, 0.55, ma), MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, mr.size.x)

# ---- prévia (esquerda): o sprite do X com as peças escolhidas, parado e respirando como no jogo; a peça trocada pisca ----
const ARM_LX := 96.0           # onde começam as linhas das peças (a prévia fica antes)
const ARM_PREV_SCALE := 2.0
var _pv_atl := {}
# o X parado, respirando: a animação 0 do jogo ([quadros de duração, quadro do atlas]), em laço
const PV_IDLE := [[11, 0], [13, 115], [11, 0], [13, 116], [11, 0], [13, 115], [11, 0], [13, 116], [11, 0], [4, 115], [5, 115], [4, 115], [11, 0], [13, 116]]

func _pv_frame() -> int:
	var tot := 0
	for st in PV_IDLE: tot += int(st[0])
	var q := int(t_anim * 60.0) % tot
	for st in PV_IDLE:
		q -= int(st[0])
		if q < 0: return int(st[1])
	return 0

func _pv_atlas(dir: String, variants := []) -> SpriteAtlas:
	var k := dir + str(variants)
	if not _pv_atl.has(k):
		var a: SpriteAtlas = SpriteAtlas.load_from(dir) if FileAccess.file_exists(dir + "/frames.json") else null
		if a and variants.size() > 0: a.load_variants(variants)
		_pv_atl[k] = a
	return _pv_atl[k]

# x da origem para o quadro (virado para a direita) ficar centralizado em cx
func _pv_center_x(a: SpriteAtlas, f: int, cx: float, sc: float) -> float:
	if not a.has_frame(f): return cx
	var fr: Dictionary = a.frames[f]
	return roundf(cx - (2.0 * float(fr["ox"]) - float(fr["w"])) / 2.0 * sc)

func _arm_draw_preview(ci: Control, r: Rect2, parts: Dictionary, zv: String) -> void:
	# fundo: caixa escura com grade de holograma e uma plataforma em baixo
	var rp := MmxUI.shape(r, 7.0)
	ci.draw_colored_polygon(rp, Color(0.0, 0.03, 0.1, 0.85))
	var gy := r.position.y + 6.0
	while gy < r.end.y - 4.0:
		ci.draw_line(Vector2(r.position.x + 3, gy), Vector2(r.end.x - 3, gy), Color(0.4, 0.75, 1.0, 0.05), 1.0)
		gy += 4.0
	var scan := r.position.y + fmod(t_anim * 40.0, r.size.y)
	ci.draw_line(Vector2(r.position.x + 3, scan), Vector2(r.end.x - 3, scan), Color(0.5, 0.85, 1.0, 0.12), 1.0)
	var foot := Vector2(r.get_center().x, r.end.y - 3.0)
	var glow := 0.5 + 0.2 * sin(t_anim * TAU * 0.8)
	for k in 3:
		var w := 30.0 - k * 7.0
		ci.draw_rect(Rect2(foot.x - w, foot.y + 1 + k, w * 2.0, 1), Color(0.35, 0.8, 1.0, glow * (0.35 - k * 0.1)))
	var rl := rp.duplicate(); rl.append(rp[0])
	ci.draw_polyline(rl, Color(MmxUI.C_EDGE_LO, 0.9), 1.0)
	# personagem (os sprites olham para a esquerda: vira para a direita)
	var sc := ARM_PREV_SCALE
	if is_zero:
		var g: String = GAMES[page]
		var dir := "res://assets/zero/x5" if g == "x5" else "res://assets/zero/x6"
		var za := _pv_atlas(dir, [dir + "/atlas_bz.png", dir + "/atlas_nz.png"])
		if za == null: return
		var f := 0   # parado (os quadros deste atlas não seguem a tabela de animação do X4)
		var pos := Vector2(_pv_center_x(za, f, foot.x, sc), foot.y - za.bottom_of(f) * sc)
		za.draw(ci, f, pos, true, Color.WHITE, {"bz": 1, "nz": 2}.get(zv, 0), sc)
		return
	var base := _pv_atlas("res://assets/x/parts/body")
	if base == null: return
	var fx := _pv_frame()
	if not base.has_frame(fx): fx = 0
	var pos := Vector2(_pv_center_x(base, 0, foot.x, sc), foot.y - base.bottom_of(fx) * sc)
	var sel_slot := ""
	if arm_row > 0 and _arm_is_custom(GAMES[page]): sel_slot = FangameParts.SLOTS[arm_row - 1]
	base.draw(ci, fx, pos, true, Color.WHITE, 0, sc)
	for p in ["legs", "body", "arms", "helmet"]:   # mesma ordem do jogo
		var s := FangameParts.asset(str(parts.get(p, "")))
		if s == "": continue
		var a := _pv_atlas("res://assets/x/parts/%s/%s" % [s, p])
		if a == null or not a.has_frame(fx): continue
		a.draw(ci, fx, pos, true, Color.WHITE, 0, sc)
		var fl := clampf(1.0 - (t_anim - float(arm_flash.get(p, -9.0))) / 0.35, 0.0, 1.0)
		if fl > 0.0: a.draw(ci, fx, pos, true, Color(3, 3, 3, fl), 0, sc)   # a peça que acabou de trocar brilha
		elif p == sel_slot: a.draw(ci, fx, pos, true, Color(1.6, 1.6, 1.6, 0.25 + 0.2 * sin(t_anim * TAU * 1.5)), 0, sc)

class _BuildPreview extends Control:
	var parts := {}
	var dim_base := false
	static var atl := {}
	func _atlas(sk: String, nm: String) -> SpriteAtlas:
		var k := sk + "/" + nm
		if not atl.has(k):
			var dir := "res://assets/x/parts/%s" % nm if sk == "" else "res://assets/x/parts/%s/%s" % [sk, nm]
			atl[k] = SpriteAtlas.load_from(dir) if FileAccess.file_exists(dir + "/frames.json") else null
		return atl[k]
	func _draw() -> void:
		var base := _atlas("", "body")
		var pos := Vector2(size.x / 2, size.y - (base.bottom_of(0) if base else 8.0) - 1)   # pés no fundo
		if base: base.draw(self, 0, pos, false, Color(0.35, 0.4, 0.55, 0.8) if dim_base else Color.WHITE)
		for p in ["legs", "body", "arms", "helmet"]:
			var s := FangameParts.asset(str(parts.get(p, "")))
			if s == "": continue
			var a := _atlas(s, p)
			if a and a.has_frame(0): a.draw(self, 0, pos, false)

# com os 8 Mavericks vencidos e alguma fase final faltando, as fases finais já aparecem abertas na próxima que falta
# (voltando de uma fase ou entrando no jogo); B fecha e volta para os Mavericks, Select abre de novo
func _auto_finals(g: String) -> void:
	if not FINALS.has(g) or _bosses_done(g) < 8: return
	for i in FINALS[g].size():
		if not int(FINALS[g][i][0]) in progress[g]:
			finals_open = true; final_sel = i; return

func _bosses_done(g: String) -> int:
	return progress[g].filter(func(v): return v >= 1 and v <= 8).size()

func _draw_finals() -> void:
	if finals_open and not pn_finals.shown():
		pn_finals.open()
		if pn_finals.content.get_child_count() == 0:
			var cv := _Canvas.new(); cv.size = pn_finals.size; cv.fn = _finals_draw; pn_finals.content.add_child(cv)
	elif not finals_open and pn_finals.shown(): pn_finals.close()
	pn_finals.title = "FASES FINAIS - " + str(GAMES[page]).to_upper()

func _finals_draw(ci: Control) -> void:
	var g: String = GAMES[page]
	if _bosses_done(g) < 8:
		MmxUI.text(ci, Vector2(0, 42), "Vença os 8 chefes do %s" % g.to_upper(), MmxUI.C_TEXT, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, ci.size.x)
		MmxUI.text(ci, Vector2(0, 54), "para liberar.", MmxUI.C_TEXT, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, ci.size.x)
		var r := Rect2(34, 70, ci.size.x - 68, 8)
		ci.draw_rect(r, Color(0, 0.03, 0.1)); ci.draw_rect(Rect2(r.position, Vector2(r.size.x * _bosses_done(g) / 8.0, r.size.y)), MmxUI.C_GOLD)
		ci.draw_rect(r, MmxUI.C_EDGE_LO, false, 1.0)
		MmxUI.text(ci, Vector2(0, 92), "%d de 8" % _bosses_done(g), MmxUI.C_DIM, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, ci.size.x)
		return
	var list: Array = FINALS[g]
	final_sel = clampi(final_sel, 0, list.size() - 1)
	for i in list.size():
		var r := Rect2(14, 16 + i * 18, ci.size.x - 28, 15)
		if i == final_sel: MmxUI.sel_bar(ci, r, t_anim, MmxUI.C_GOLD)
		var done: bool = int(list[i][0]) in progress[g]
		MmxUI.text(ci, Vector2(r.position.x + 4, r.position.y + 11), str(list[i][1]), MmxUI.C_SEL if i == final_sel else MmxUI.C_TEXT)
		if done: MmxUI.text(ci, Vector2(r.position.x, r.position.y + 11), "✓", MmxUI.C_GOOD, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4)

func _play_title_music() -> void:
	music_page = -2
	var st := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path("res://assets/musica/titulo.ogg"))
	if st == null: return
	st.loop = true; st.loop_offset = 0.0
	music.stream = st; music.volume_db = Opcoes.music_db(); music.play()

func _play_music(g: String) -> void:
	music_page = page
	var path := ProjectSettings.globalize_path("res://assets/musica/%s_selecao.ogg" % g)
	if not FileAccess.file_exists(path): music.stop(); return
	var st := AudioStreamOggVorbis.load_from_file(path)
	if st == null: return
	st.loop = true
	music.stream = st; music.volume_db = Opcoes.music_db(); music.play()

func _move(dir: Vector2i) -> void:
	var g: String = GAMES[page]
	var p: int = cursor[g]
	match g:
		"x4":   # 2 linhas de 4
			if dir.x != 0: p = (p / 4) * 4 + (p % 4 + dir.x + 4) % 4
			if dir.y != 0: p = (p + 4) % 8
		"x5":   # 2 colunas de 4
			if dir.y != 0: p = (p / 4) * 4 + (p % 4 + dir.y + 4) % 4
			if dir.x != 0: p = (p + 4) % 8
		"x6":   # anel: 0 1 2 3 / 4 5 6 7 (em cima / embaixo)
			var ring := [0, 1, 2, 3, 7, 6, 5, 4]
			if dir.x != 0:
				var i := ring.find(p)
				# na metade de baixo o anel anda ao contrário, para a seta seguir a tela
				var step: int = dir.x if p < 4 else -dir.x
				p = ring[(i + step + 8) % 8]
			if dir.y != 0: p = (p + 4) % 8
	cursor[g] = p

func _input(e: InputEvent) -> void:   # Tab chega aqui antes da navegação de foco do Godot
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.6): pad_mode = true
	elif e is InputEventKey: pad_mode = false
	if e is InputEventKey and e.is_pressed() and not e.is_echo() and e.keycode == KEY_TAB and not slot_open and not build_open and not finals_open and not char_open:
		_unhandled_input(e)

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey or e is InputEventJoypadButton) or not e.is_pressed() or e.is_echo(): return
	if trans_layer: get_viewport().set_input_as_handled(); return   # durante a transição
	if new_part_msg != "": new_part_msg = ""; _refresh()
	if slot_open: _slot_input(e); return
	if build_open: _build_input(e); return
	if status_open: _status_input(e); return
	if coop_open: _coop_input(e); get_viewport().set_input_as_handled(); return
	if char_open: _char_input(e); get_viewport().set_input_as_handled(); return
	if (_key(e, KEY_O) or _joy(e, JOY_BUTTON_LEFT_SHOULDER)) and intro_t < 0.0:
		coop_open = true; coop_sel = 0; _sfx("menu_open"); get_viewport().set_input_as_handled(); _coop_panel(); _refresh(); return
	if _key(e, KEY_F10) and FangameSave.slot >= 0:   # TESTE: libera todas as peças e melhorias do Black Zero neste save
		var sv := FangameSave.cur(); sv["zero"] = []
		for gz in ["x4", "x6"]:
			for p in ZeroDesafios.SLOTS: sv.zero.append(ZeroDesafios.key(gz, p)); sv.zero.append(ZeroDesafios.key(gz, p + "+"))
		FangameSave.write(); new_part_msg = "TESTE: Black Zero e Nightmare Zero com todas as peças e melhorias"
		get_viewport().set_input_as_handled(); _refresh(); return
	if intro_t >= 0.0:   # qualquer botão pula a abertura
		get_viewport().set_input_as_handled(); _intro_end(); return
	if _key(e, KEY_TAB) or _key(e, KEY_I) or _joy(e, JOY_BUTTON_RIGHT_STICK) or _joy(e, JOY_BUTTON_LEFT_STICK):
		status_open = true; _sfx("menu_open"); get_viewport().set_input_as_handled(); _refresh(); return
	if jogo_open: _jogo_input(e); return
	var g: String = GAMES[page]
	if not finals_open and (_key(e, KEY_ESCAPE) or _joy(e, JOY_BUTTON_B)):   # volta para a escolha do jogo
		get_viewport().set_input_as_handled()
		_sfx("menu_back")
		_transicao(func() -> void: jogo_open = true; in_page = false; jogo_sel = page; _refresh())
		return
	if (_key(e, KEY_C) or _joy(e, JOY_BUTTON_X)) and not finals_open and (g == "x4" or g == "x5" or g == "x6"):
		build_open = true; arm_row = 0 if is_zero else arm_row; _sfx("menu_open")
		get_viewport().set_input_as_handled(); _refresh(); return
	if _key(e, KEY_BACKSPACE) or _joy(e, JOY_BUTTON_BACK):
		finals_open = not finals_open; final_sel = 0; _sfx("menu_open" if finals_open else "menu_close")
		if finals_open: _auto_finals(g)
		get_viewport().set_input_as_handled(); _refresh(); return
	if finals_open:
		var nf: int = FINALS[g].size()
		if _key(e, KEY_UP) or _joy(e, JOY_BUTTON_DPAD_UP): final_sel = (final_sel + nf - 1) % nf; _sfx("menu_move")
		elif _key(e, KEY_DOWN) or _joy(e, JOY_BUTTON_DPAD_DOWN): final_sel = (final_sel + 1) % nf; _sfx("menu_move")
		elif _key(e, KEY_ESCAPE) or _joy(e, JOY_BUTTON_B): finals_open = false; _sfx("menu_close")
		elif e.is_action_pressed("jump") or _key(e, KEY_ENTER) or _joy(e, JOY_BUTTON_START):
			if _bosses_done(g) < 8: _sfx("menu_error")
			elif Coop.on() and not Coop.is_host():
				_sfx("menu_error"); new_part_msg = "CO-OP: o P1 escolhe a fase (você vai junto)"; get_viewport().set_input_as_handled(); _refresh(); return
			else: _abre_missao(int(FINALS[g][clampi(final_sel, 0, FINALS[g].size() - 1)][0]))
		else: return
		get_viewport().set_input_as_handled(); _refresh(); return
	var c0: int = cursor[g]
	if _key(e, KEY_LEFT) or _joy(e, JOY_BUTTON_DPAD_LEFT): _move(Vector2i(-1, 0))
	elif _key(e, KEY_RIGHT) or _joy(e, JOY_BUTTON_DPAD_RIGHT): _move(Vector2i(1, 0))
	elif _key(e, KEY_UP) or _joy(e, JOY_BUTTON_DPAD_UP): _move(Vector2i(0, -1))
	elif _key(e, KEY_DOWN) or _joy(e, JOY_BUTTON_DPAD_DOWN): _move(Vector2i(0, 1))
	elif _key(e, KEY_V) or _joy(e, JOY_BUTTON_Y): char_open = true; char_open_t = t_anim; char_t = -9.0; _sfx("menu_ok")
	elif _key(e, KEY_Q): _cycle_armor(g, -1); _sfx("menu_equip"); toast_t = t_anim; toast_kind = "armor"
	elif _key(e, KEY_W): _cycle_armor(g, 1); _sfx("menu_equip"); toast_t = t_anim; toast_kind = "armor"
	elif e.is_action_pressed("jump") or _key(e, KEY_ENTER) or _joy(e, JOY_BUTTON_START):
		if Coop.on() and not Coop.is_host():
			_sfx("menu_error"); new_part_msg = "CO-OP: o P1 escolhe a fase (você vai junto)"; get_viewport().set_input_as_handled(); _refresh(); return
		_abre_missao(); get_viewport().set_input_as_handled(); _refresh(); return
	elif _key(e, KEY_4) or _key(e, KEY_5) or _key(e, KEY_6):   # jogo original completo
		X4Machine.launch = {}
		for k in ["MMX4_ORACLE_SCENE", "MMX4_DIRECT_STAGE", "MMX4_DIRECT_CHARACTER", "MMX4_DIRECT_LOADOUT", "MMX4_DIRECT_SECRET", "MMX4_DIRECT_ARMOR", "MMX4_DIRECT_SKILL", "MMX4_SAVE", "MMX4_VOZ_X6"]: X4R.env.erase(k)
		get_tree().change_scene_to_file("res://scenes/%s_original.tscn" % {KEY_4: "x4", KEY_5: "x5", KEY_6: "x6"}[e.keycode]); return
	else: return
	if cursor[g] != c0: _sfx("menu_move"); fx.t_move = 0.0
	get_viewport().set_input_as_handled()
	_refresh()

func _process(_dt: float) -> void:
	_coop_hub_step()
	_preload_step(_dt)
	t_anim += _dt
	if intro_t >= 0.0: _intro_step(_dt)
	if fx.visible: fx.queue_redraw()
	if jogo_open: jogo_box.queue_redraw()
	# gatilhos L2/R2 do controle (são eixos)
	var t := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5
	var u := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	var g: String = GAMES[page]
	var free := not (status_open or finals_open or coop_open or jogo_open or slot_open) and intro_t < 0.0
	for k in 2:
		if [t, u][k] and not _trig[k] and free:
			pad_mode = true
			if build_open: _arm_cycle_preset(g, -1 if k == 0 else 1)
			else: _cycle_armor(g, -1 if k == 0 else 1); _sfx("menu_equip"); toast_t = t_anim; toast_kind = "armor"
			_refresh()
	_trig = [t, u]
	bar_cv.queue_redraw(); toast_cv.queue_redraw()
	if pn_arm.visible: arm_cv.queue_redraw()
	if pn_status.visible or pn_finals.visible or pn_coop.visible:
		for pn: MmxPanel in [pn_status, pn_finals, pn_coop]:
			if pn.visible:
				for c in pn.content.get_children(): if c is _Canvas: (c as CanvasItem).queue_redraw()
var _trig := [false, false]

func _key(e: InputEvent, k: int) -> bool:
	return e is InputEventKey and e.keycode == k

func _joy(e: InputEvent, b: int) -> bool:
	return e is InputEventJoypadButton and e.button_index == b

func _build_launch(final_stage := -1) -> Dictionary:
	var g: String = GAMES[page]
	var stage: int = POS_STAGE[g][cursor[g]] if final_stage < 0 else final_stage
	var a := _armor(g)
	var armor: int = a[1]
	var secret: bool = a.size() > 2 and a[2] is bool and a[2]
	var bz := 0
	if a.size() > 2 and str(a[2]) == "bz" and FangameSave.slot >= 0:   # Black Zero: peças dos desafios do X4 (valem nos 3 jogos)
		bz = ZeroDesafios.mask(FangameSave.cur(), "x4")
		if g == "x4": secret = ZeroDesafios.count(FangameSave.cur(), "x4") == 4   # X4: a cor preta do jogo com as 4 (X5/X6: a recompilação pinta)
	var skin: String = a[3] if a.size() > 3 and not is_zero else ""
	var l := {"game": g, "stage": stage, "char": 1 if is_zero else 0, "armor": armor, "secret": secret, "skin": skin}
	if skin == "*":   # armadura montada (save)
		l.skin = ""; l["parts"] = FangameSave.cur().parts.duplicate()
		if g == "x6":   # o X6 carrega uma armadura dele (a do braço do X6, senão a das pernas; FangameParts.x6_native); cada peça ganha a habilidade dela
			armor = FangameParts.x6_native(l.parts); l["armor"] = armor
		elif g == "x5":   # o X5 também: a armadura do X5 das pernas (senão braço, corpo, capacete)
			armor = FangameParts.x5_native(l.parts); l["armor"] = armor
	l["char_code"] = ZERO_CODE[g] if is_zero else armor
	if bz: l["bz"] = bz
	if a.size() > 2 and str(a[2]) == "nz" and FangameSave.slot >= 0: l["nz"] = ZeroDesafios.mask(FangameSave.cur(), "x6")
	if g == "x4" and is_zero: l["armor"] = 1   # Zero com vida e armas cheias
	if g != "x4": l["pokes"] = [SECRET_POKE[g].duplicate()]
	if g != "x4" and not secret: l["pokes"][0][1] = 0
	if FangameSave.slot >= 0: l["save"] = FangameSave.launch_info(g, stage)   # save único: vida, armas, itens, sub tanks
	return l

func _start(final_stage := -1) -> void:
	var l := _build_launch(final_stage)
	if Coop.on() and Coop.is_host(): Coop.me.send_launch({"game": l.game, "stage": int(l.stage), "ms": Time.get_unix_time_from_system()})
	X4Machine.handoff = {}
	# o hub já estava preparando esta mesma fase: entrega o núcleo do jeito que está
	if pre_node: pre_node.stop_preload()   # para a linha de preparo antes de passar o núcleo adiante
	if pre_node and pre_key == X4Machine.launch_key(l) and pre_node.booted and pre_node.launch_phase == 1:
		X4Machine.handoff = {"key": pre_key, "lf": pre_node.lf, "snap_done": pre_node.snap_done}
	X4Machine.launch = l
	get_tree().change_scene_to_file("res://scenes/fase.tscn")

# ---- pré-carregamento: com o cursor parado num chefe do X5/X6, a fase vai sendo preparada escondida ----
var pre_node: X4Machine
var pre_key := ""
var pre_label: Label
var idle_key := ""
var idle_t := 0.0

func _preload_step(dt: float) -> void:
	var g: String = GAMES[page]
	var want := {}
	if g != "x4" and not slot_open and not jogo_open:
		if not finals_open: want = _build_launch()
		elif _bosses_done(g) >= 8: want = _build_launch(int(FINALS[g][clampi(final_sel, 0, FINALS[g].size() - 1)][0]))
	var k := X4Machine.launch_key(want) if not want.is_empty() else ""
	if k != idle_key: idle_key = k; idle_t = 0.0
	idle_t += dt
	var ready := k != "" and FileAccess.file_exists(X4Machine.stage_snap_file(want))
	if pre_node and (pre_key != k or pre_node.preload_done or not pre_node.is_processing()):
		var done := pre_node.preload_done and pre_key == k
		pre_node.queue_free(); pre_node = null; pre_key = ""
		if done: ready = true
	if k != "" and not ready and pre_node == null and idle_t > 0.15 and ClassDB.class_exists("PsxCore"):
		pre_node = X4Machine.new(); pre_node.preload_mode = true; pre_node.L = want; pre_node.visible = false
		pre_key = k; add_child(pre_node)
	if pre_label == null:
		pre_label = Label.new(); pre_label.position = Vector2(232, 2); pre_label.size = Vector2(86, 12)
		pre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pre_label.add_theme_font_size_override("font_size", 8)
		pre_label.add_theme_color_override("font_outline_color", Color.BLACK); pre_label.add_theme_constant_override("outline_size", 3)
		add_child(pre_label)
	if k == "": pre_label.text = ""
	elif ready or (pre_node and pre_node.preload_done): pre_label.text = "fase pronta"; pre_label.modulate = Color(0.5, 1, 0.5)
	elif pre_node: pre_label.text = "preparando a fase..."; pre_label.modulate = Color(1, 1, 0.6)
	else: pre_label.text = ""


# ---- sons dos menus ----
var sfx_p := {}
func _sfx(nm: String) -> void:
	nm = str(MmxUI.SFX.get(nm, nm))
	if not sfx_p.has(nm):
		var p := AudioStreamPlayer.new(); add_child(p)
		p.stream = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://assets/sfx/%s.wav" % nm))
		sfx_p[nm] = p
	sfx_p[nm].play()

# ---- escolha do jogo (X4 / X5 / X6) ----
var jogo_open := false
var jogo_sel := 0
var jogo_box: Control

# ---- transição: a tela "Now Loading" de um dos jogos (sorteada) entre a seleção de chefes e a escolha do jogo ----
var trans_layer: CanvasLayer
func _transicao(meio: Callable) -> void:
	var telas := []
	for g in GAMES:
		if ResourceLoader.exists("res://assets/menus/loading/%s_a.png" % g) and ResourceLoader.exists("res://assets/menus/loading/%s_b.png" % g): telas.append(g)
	if telas.is_empty(): meio.call(); return
	var g: String = telas[randi() % telas.size()]
	var ta: Texture2D = load("res://assets/menus/loading/%s_a.png" % g)
	var tb: Texture2D = load("res://assets/menus/loading/%s_b.png" % g)
	trans_layer = CanvasLayer.new(); trans_layer.layer = 120; add_child(trans_layer)
	var raiz := Control.new(); raiz.size = Vector2(320, 240); raiz.modulate.a = 0.0; trans_layer.add_child(raiz)
	var bg := ColorRect.new(); bg.color = Color.BLACK; bg.size = Vector2(320, 240); raiz.add_child(bg)
	var tr := TextureRect.new(); tr.size = Vector2(320, 240); tr.texture = ta; tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; raiz.add_child(tr)
	var tm := Timer.new(); tm.wait_time = 0.25; tm.autostart = true; raiz.add_child(tm)   # o texto pisca como no jogo
	tm.timeout.connect(func() -> void: tr.texture = tb if tr.texture == ta else ta)
	var tw := create_tween()
	tw.tween_property(raiz, "modulate:a", 1.0, 0.15)
	tw.tween_callback(meio)
	tw.tween_interval(0.7)
	tw.tween_property(raiz, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void: trans_layer.queue_free(); trans_layer = null)

func _jogo_input(e: InputEvent) -> void:
	if _key(e, KEY_LEFT) or _joy(e, JOY_BUTTON_DPAD_LEFT) or _key(e, KEY_A) or _joy(e, JOY_BUTTON_LEFT_SHOULDER):
		jogo_sel = (jogo_sel + 2) % 3; _sfx("menu_move"); jogo_box.t_sel = 0.0
	elif _key(e, KEY_RIGHT) or _joy(e, JOY_BUTTON_DPAD_RIGHT) or _key(e, KEY_S) or _joy(e, JOY_BUTTON_RIGHT_SHOULDER):
		jogo_sel = (jogo_sel + 1) % 3; _sfx("menu_move"); jogo_box.t_sel = 0.0
	elif e.is_action_pressed("jump") or _key(e, KEY_ENTER) or _joy(e, JOY_BUTTON_START) or _joy(e, JOY_BUTTON_A):
		_sfx("menu_ok")
		page = jogo_sel; jogo_open = false; in_page = true
		_intro_start(GAMES[page])
	elif _key(e, KEY_ESCAPE) or _joy(e, JOY_BUTTON_B):   # volta para a tela dos saves (trocar/copiar/apagar)
		_sfx("menu_back")
		get_viewport().set_input_as_handled()
		TitleScreen.start_state = "saves"; get_tree().change_scene_to_file("res://scenes/title.tscn"); return
	else: return
	get_viewport().set_input_as_handled()
	_refresh()

# ---- abertura da tela de seleção (gravada do jogo original) ----
static var intro_cache := {}
const INTRO_DIR := {"x4": "x4_curta"}   # X4: só o fim da descida da câmera e os painéis (~3 s)
var intro_t := -1.0
var intro_frames: Array = []

func _intro_start(g: String) -> void:
	if not intro_cache.has(g):
		var arr: Array = []
		var i := 0
		while true:
			var path := ProjectSettings.globalize_path("res://assets/menus/intro/%s/%03d.webp" % [INTRO_DIR.get(g, g), i])
			if not FileAccess.file_exists(path): break
			var img := Image.new()
			if img.load(path) != OK: break
			arr.append(ImageTexture.create_from_image(img)); i += 1
		intro_cache[g] = arr
	intro_frames = intro_cache[g]
	if intro_frames.is_empty(): return
	intro_t = 0.0
	if music_page != page: _play_music(g)
	_intro_step(0.0)

func _intro_step(dt: float) -> void:
	intro_t += dt
	var i := int(intro_t * 30.0)
	if i >= intro_frames.size(): _intro_end(); return
	screen.texture = intro_frames[i]
	screen.modulate = Color(1, 1, 1, 1) * clampf(intro_t * 4.0, 0.0, 1.0) if GAMES[page] == "x4" else Color.WHITE
	screen.modulate.a = 1.0
	bar.visible = false; fx.visible = false

func _intro_end() -> void:
	intro_t = -1.0; screen.modulate = Color.WHITE; bar.visible = true
	fx.t_move = 0.0
	if in_page and not jogo_open: _auto_finals(GAMES[page])
	_refresh()

# ---- vida nas telas: brilho do cursor no formato do retrato + efeitos do X5/X6 ----
static var masks := {}
static func mask(g: String, p: int) -> PackedVector2Array:
	if masks.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://assets/menus/mascaras.json"))
		for k in j:
			masks[k] = []
			for poly in j[k]:
				var pv := PackedVector2Array()
				for q in poly: pv.append(Vector2(q[0], q[1]))
				masks[k].append(pv)
	return masks[g][p]

class _Fx extends Control:
	var hub
	var t_move := 9.0
	func _draw() -> void:
		var t: float = hub.t_anim
		t_move += get_process_delta_time()
		var g: String = GAMES[hub.page]
		if hub.finals_open: return
		var poly: PackedVector2Array = hub.mask(g, hub.cursor[g])
		# cursor: pisca no formato do retrato (mais forte logo depois de mover)
		var a := 0.16 * maxf(0.0, sin(t * TAU * 2.0)) + 0.35 * maxf(0.0, 1.0 - t_move * 4.0)
		if a > 0.01: draw_colored_polygon(poly, Color(1, 1, 1, a))
		if g == "x5":
			# holograma roxo do centro: linhas de varredura e chiado
			var r := Rect2(129, 64, 63, 48)
			var y := r.position.y + fmod(t * 40.0, r.size.y)
			draw_rect(Rect2(r.position.x, y, r.size.x, 2), Color(1, 0.7, 1, 0.22))
			for k in 4:
				var yy := r.position.y + fmod(t * 23.0 + k * 13.0, r.size.y)
				draw_rect(Rect2(r.position.x, yy, r.size.x, 1), Color(0.8, 0.5, 1, 0.10))
			if fmod(t, 2.3) < 0.08: draw_rect(r, Color(1, 0.8, 1, 0.12))
			_sweep(Vector2(155, 72), Vector2(58, 62), t, 3.2, Color(0.6, 0.9, 1, 0.13))
		elif g == "x6":
			_sweep(Vector2(160, 106), Vector2(73, 37), t, 2.6, Color(0.7, 1, 0.8, 0.14))
	# faixa de luz que atravessa o globo
	func _sweep(c: Vector2, r: Vector2, t: float, per: float, col: Color) -> void:
		var u := fmod(t, per) / per * 2.6 - 1.3
		for w: float in [9.0, 4.0]:
			var x0 := c.x + (u * r.x) - w
			var x1 := x0 + 2.0 * w
			x0 = maxf(x0, c.x - r.x); x1 = minf(x1, c.x + r.x)
			if x1 - x0 < 1.0: return
			var top := PackedVector2Array(); var bot := PackedVector2Array()
			for k in 7:
				var x := lerpf(x0, x1, k / 6.0)
				var h := r.y * sqrt(maxf(0.0, 1.0 - pow((x - c.x) / r.x, 2)))
				top.append(Vector2(x, c.y - h)); bot.insert(0, Vector2(x, c.y + h))
			var pts := top + bot
			draw_colored_polygon(pts, col)

# ---- desenho da escolha do jogo ----
class _GameSelect extends Control:
	var hub
	var t_sel := 9.0
	static var tex := {}
	static func _t(nm: String) -> Texture2D:
		if not tex.has(nm):
			var img := Image.new()
			var path := ProjectSettings.globalize_path("res://assets/menus/%s.png" % nm)
			tex[nm] = ImageTexture.create_from_image(img) if FileAccess.file_exists(path) and img.load(path) == OK else null
		return tex[nm]
	var t_open := 0.0
	func _draw() -> void:
		t_sel += get_process_delta_time()
		t_open += get_process_delta_time()
		var sel: int = hub.jogo_sel
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		var bg := _t("titulo_" + GAMES[sel])
		if bg: draw_texture_rect(bg, Rect2(Vector2.ZERO, size), false, Color(0.13, 0.14, 0.2))
		# título com riscas dos lados
		var ta := MmxUI.ease_out(t_open / 0.35)
		draw_rect(Rect2(0, 0, 320, 24), Color(0, 0.02, 0.07, 0.7 * ta))
		draw_line(Vector2(0, 24), Vector2(320, 24), Color(MmxUI.C_ACCENT.r, MmxUI.C_ACCENT.g, MmxUI.C_ACCENT.b, 0.5 * ta), 1.0)
		MmxUI.text(self, Vector2(0, 18 - (1.0 - ta) * 10.0), "ESCOLHA O JOGO", Color(MmxUI.C_GOLD.r, MmxUI.C_GOLD.g, MmxUI.C_GOLD.b, ta), 18, HORIZONTAL_ALIGNMENT_CENTER, 320)
		for k in 5:
			var x := 52.0 - k * 6.0
			draw_line(Vector2(x, 16), Vector2(x + 5, 6), Color(MmxUI.C_ACCENT.r, MmxUI.C_ACCENT.g, MmxUI.C_ACCENT.b, (0.6 - k * 0.1) * ta), 1.0)
			draw_line(Vector2(320 - x - 5, 16), Vector2(320 - x, 6), Color(MmxUI.C_ACCENT.r, MmxUI.C_ACCENT.g, MmxUI.C_ACCENT.b, (0.6 - k * 0.1) * ta), 1.0)
		var total := 0
		for gi in 3:
			var g: String = GAMES[gi]
			var prog: Array = hub.progress[g]
			var won := 0
			for s in range(1, 9): if s in prog: won += 1
			total += won
			var on := gi == sel
			var w := 96.0; var h := 176.0
			var r := Rect2(8 + gi * 104, 32, w, h)
			var ap := MmxUI.ease_out((t_open - 0.08 - gi * 0.07) / 0.3)   # os cartões sobem um depois do outro
			if ap <= 0.0: continue
			r.position.y += roundf((1.0 - ap) * 40.0)
			if on:
				var k2 := clampf(t_sel * 6.0, 0.0, 1.0)
				r = r.grow(3.0 * k2); r.position.y -= 3.0 * k2
			var dim := Color(1, 1, 1, ap) if on else Color(0.5, 0.5, 0.58, ap)
			MmxUI.frame(self, r, MmxUI.C_GOLD if on else MmxUI.C_EDGE_LO, 8.0)
			# capa: o logo do título
			var tt := _t("titulo_" + g)
			if tt:
				var src := Rect2(20, 8, 290, 132) if g == "x4" else Rect2(30, 40, 285, 105)
				var dh := (r.size.x - 6) * src.size.y / src.size.x
				draw_texture_rect_region(tt, Rect2(r.position + Vector2(3, 4), Vector2(r.size.x - 6, dh)), src, dim)
			# os 8 chefes (vencidos em cinza), 2 colunas x 4 linhas
			var cell := Vector2((r.size.x - 6) / 2.0, 26.0)
			var y0 := r.position.y + 48.0
			for s in range(1, 9):
				var m := _t("mini/%s_%d%s" % [g, s, "_cinza" if s in prog else ""])
				if m == null: continue
				var cr := Rect2(Vector2(r.position.x + 3 + ((s - 1) % 2) * cell.x, y0 + ((s - 1) / 2) * cell.y), cell).grow(-2.0)
				var sc := minf(cr.size.x / m.get_width(), cr.size.y / m.get_height())
				var ds := Vector2(m.get_width(), m.get_height()) * sc
				draw_texture_rect(m, Rect2(cr.position + (cr.size - ds) / 2.0, ds), false, dim)
			# barra de progresso e texto
			var pr := Rect2(r.position.x + 8, r.end.y - 20, r.size.x - 16, 4)
			draw_rect(pr, Color(0, 0.03, 0.1, ap)); draw_rect(Rect2(pr.position, Vector2(pr.size.x * won / 8.0, pr.size.y)), Color(MmxUI.C_GOOD.r, MmxUI.C_GOOD.g, MmxUI.C_GOOD.b, ap) if won == 8 else Color(MmxUI.C_ACCENT.r, MmxUI.C_ACCENT.g, MmxUI.C_ACCENT.b, ap))
			MmxUI.text(self, Vector2(r.position.x, r.end.y - 6), "%d / 8 chefes" % won, Color(MmxUI.C_GOOD.r, MmxUI.C_GOOD.g, MmxUI.C_GOOD.b, ap) if won == 8 else (Color(1, 1, 1, ap) if on else Color(0.6, 0.65, 0.78, ap)), MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			if on:   # brilho pulsando na borda
				var pul := 0.35 + 0.35 * sin(hub.t_anim * TAU * 1.5)
				var pts := MmxUI.shape(r.grow(1.0), 9.0); pts.append(pts[0])
				draw_polyline(pts, Color(1, 0.86, 0.35, pul), 1.0)
		MmxUI.text(self, Vector2(0, 216), "Chefes vencidos: %d / 24" % total, MmxUI.C_TEXT, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, 320)

# ---- co-op online (Coop): O / L1 abre; o P1 cria a sala, o P2 entra pelo IP; o P1 escolhe a fase e o P2 vai junto ----
var coop_open := false
var coop_sel := 0
var coop_box: Control
var coop_ip: LineEdit
var coop_items: Array = []
var coop_info: Label
var coop_last := ""
static var coop_ip_text := ""

func _coop_list() -> Array:
	var c := Coop.me
	if c and c.role != "": return [["Sair da sala", "sair"], ["Fechar", "fechar"]]
	return [["Criar sala (você é o P1)", "criar"], ["Entrar numa sala: IP", "entrar"], ["Fechar", "fechar"]]

func _coop_input(e: InputEvent) -> void:
	if coop_ip and coop_ip.has_focus():
		if _key(e, KEY_ESCAPE): coop_ip.release_focus()
		return
	var n := _coop_list().size()
	if _key(e, KEY_UP) or _joy(e, JOY_BUTTON_DPAD_UP): coop_sel = (coop_sel + n - 1) % n; _sfx("menu_move")
	elif _key(e, KEY_DOWN) or _joy(e, JOY_BUTTON_DPAD_DOWN): coop_sel = (coop_sel + 1) % n; _sfx("menu_move")
	elif _key(e, KEY_ESCAPE) or _key(e, KEY_O) or _joy(e, JOY_BUTTON_B) or _joy(e, JOY_BUTTON_LEFT_SHOULDER):
		coop_open = false; _sfx("menu_close")
	elif e.is_action_pressed("jump") or _key(e, KEY_ENTER) or _joy(e, JOY_BUTTON_A) or _joy(e, JOY_BUTTON_START):
		var act := str(_coop_list()[clampi(coop_sel, 0, n - 1)][1])
		_sfx("menu_close" if act == "fechar" else "menu_ok")
		match act:
			"criar": Coop.node().host()
			"entrar":
				if coop_ip: coop_ip.grab_focus(); coop_ip.caret_column = coop_ip.text.length()
			"sair": Coop.node().leave(); coop_sel = 0
			"fechar": coop_open = false
	_coop_panel()

func _coop_join(t: String) -> void:
	_sfx("menu_ok")
	coop_ip_text = t
	coop_ip.release_focus()
	Coop.node().join(t)
	coop_sel = 0
	_coop_panel()

func _coop_hub_step() -> void:
	var c := Coop.me
	if c and c.role == "client" and c.peer_id != 0 and not c.launch_req.is_empty():   # o P1 começou uma fase: vai junto
		var r: Dictionary = c.launch_req; c.launch_req = {}
		var g := str(r.get("game", ""))
		if g in GAMES and Time.get_unix_time_from_system() - float(r.get("ms", 0.0)) < 20.0:
			slot_open = false; build_open = false; status_open = false; finals_open = false; coop_open = false; jogo_open = false
			page = GAMES.find(g); in_page = true
			print("co-op: o P1 começou %s fase %d" % [g, int(r.get("stage", 1))])
			_start(int(r.get("stage", 1)))
			return
	if coop_open:
		var key := "%s|%s|%s|%d|%s" % [c.status if c else "", c.role if c else "", c.ext_ip if c else "", c.peer_id if c else 0, coop_sel]
		if key != coop_last: _coop_panel()
	elif pn_coop and pn_coop.shown(): pn_coop.close()
	var on := Coop.on()
	if on != coop_was_on: coop_was_on = on; _refresh()
var coop_was_on := false

func _coop_panel() -> void:
	var c := Coop.node()
	if coop_box == null:
		coop_box = _Canvas.new(); coop_box.size = pn_coop.size; (coop_box as _Canvas).fn = _coop_draw; pn_coop.content.add_child(coop_box)
		coop_ip = LineEdit.new(); coop_ip.position = Vector2(150, 40); coop_ip.size = Vector2(130, 12)
		coop_ip.placeholder_text = "ex.: 177.10.20.30"; coop_ip.text = coop_ip_text; coop_ip.max_length = 40
		coop_ip.text_submitted.connect(_coop_join); pn_coop.content.add_child(coop_ip)
		coop_ip.size = Vector2(130, 12)   # (de novo: antes de entrar na árvore o tamanho mínimo era o da fonte padrão)
		coop_info = Label.new(); coop_info.position = Vector2(12, 78); coop_info.size = Vector2(268, 116); coop_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pn_coop.content.add_child(coop_info)
	if coop_open and not pn_coop.shown(): pn_coop.open()
	elif not coop_open and pn_coop.shown(): pn_coop.close(); coop_ip.release_focus()
	if not coop_open: return
	var items := _coop_list()
	coop_sel = clampi(coop_sel, 0, items.size() - 1)
	coop_items = items
	coop_ip.visible = c.role == ""
	var tx := ""
	if c.status != "": tx += c.status + "\n\n"
	if c.role == "host":
		var eip := c.ext_ip if c.ext_ip != "" else ("procurando..." if not c.upnp_done else "não achei sozinho (veja num site como meuip.com.br)")
		tx += "Passe para o parceiro o seu IP: %s  (porta %d, UDP)\n" % [eip, Coop.PORT]
		if not c.lan_ips.is_empty(): tx += "Na mesma rede / Radmin / ZeroTier: %s\n" % ", ".join(c.lan_ips)
		tx += "\n"
	tx += "Cada um joga no próprio PC, com o próprio save. O P1 escolhe a fase e o P2 vai junto; o chefe tem a mesma vida para os dois."
	coop_info.text = tx
	coop_last = "%s|%s|%s|%d|%s" % [c.status, c.role, c.ext_ip, c.peer_id, coop_sel]

func _coop_draw(ci: Control) -> void:
	for i in coop_items.size():
		var r := Rect2(14, 14 + i * 13, 128 if i == 1 and Coop.me and Coop.me.role == "" else 264, 12)
		if i == coop_sel: MmxUI.sel_bar(ci, r, t_anim)
		MmxUI.text(ci, Vector2(r.position.x + 4, r.position.y + 9), str(coop_items[i][0]), MmxUI.C_SEL if i == coop_sel else MmxUI.C_TEXT)
	ci.draw_line(Vector2(12, 68), Vector2(ci.size.x - 12, 68), Color(MmxUI.C_ACCENT.r, MmxUI.C_ACCENT.g, MmxUI.C_ACCENT.b, 0.35), 1.0)

# ---- barra de baixo: informação (jogo, chefe, personagem) e as dicas do controle ou do teclado ----
func _bar_draw(ci: Control) -> void:
	if intro_t >= 0.0: return
	var y0 := 219.0
	ci.draw_polygon(PackedVector2Array([Vector2(0, y0 - 8), Vector2(320, y0 - 8), Vector2(320, 240), Vector2(0, 240)]),
		PackedColorArray([Color(0, 0.02, 0.07, 0.0), Color(0, 0.02, 0.07, 0.0), Color(0, 0.02, 0.07, 0.95), Color(0, 0.02, 0.07, 0.95)]))
	ci.draw_line(Vector2(0, y0), Vector2(320, y0), Color(MmxUI.C_ACCENT.r, MmxUI.C_ACCENT.g, MmxUI.C_ACCENT.b, 0.45), 1.0)
	ci.draw_line(Vector2(0, y0 + 1), Vector2(320, y0 + 1), Color(0, 0, 0, 0.6), 1.0)
	var msg := bar.text if new_part_msg != "" else ""
	if msg != "":
		MmxUI.text(ci, Vector2(4, y0 + 10), MmxUI.fit(msg, 312), MmxUI.C_SEL)
	else:
		var lw := MmxUI.text_width(bar_info)
		MmxUI.text(ci, Vector2(4, y0 + 10), bar_info, MmxUI.C_GOLD)
		MmxUI.text(ci, Vector2(0, y0 + 10), MmxUI.fit(bar_info_r, 308 - lw - 10), MmxUI.C_TEXT, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, 316)
	var hs: Array
	if jogo_open: hs = [["←→", "←→", "jogo"], ["✕", "Z", "entrar"], ["○", "Esc", "saves"], ["R3", "Tab", "status"], ["L1", "O", "co-op"]]
	elif build_open and arm_launch: hs = [["↑↓", "↑↓", "escolher"], ["←→", "←→", "trocar"], ["✕", "Z", "jogar"], ["○", "Esc", "voltar"]]
	elif build_open: hs = [["↑↓", "↑↓", "escolher"], ["←→", "←→", "trocar"], ["L2 R2", "Q W", "conjunto"], ["✕", "Z", "pronto"]]
	elif status_open: hs = [["←→", "←→", "armadura"], ["R3", "Tab", "fechar"]]
	elif finals_open: hs = [["↑↓", "↑↓", "fase"], ["✕", "Z", "jogar"], ["SEL", "Bksp", "fechar"]]
	elif coop_open: hs = [["↑↓", "↑↓", "escolher"], ["✕", "Enter", "confirmar"], ["○", "Esc", "fechar"]]
	elif char_open: hs = [["←→", "←→", "trocar X / Zero"], ["△", "V", "fechar"], ["✕", "Z", "pronto"]]
	else: hs = [["✕", "Z", "escolher fase"], ["○", "Esc", "jogos"], ["SEL", "Bksp", "finais"], ["R3", "Tab", "status"], ["L1", "O", "co-op"]]
	var tot := 0.0
	for h in hs: tot += MmxUI.text_width(str(h[0] if pad_mode else h[1])) + 2.0 + MmxUI.text_width(str(h[2])) + 8.0
	var x := maxf(4.0, (320.0 - tot + 8.0) * 0.5)
	for h in hs:
		var k := str(h[0] if pad_mode else h[1])
		MmxUI.text(ci, Vector2(x, y0 + 20), k, MmxUI.C_SEL); x += MmxUI.text_width(k) + 2.0
		MmxUI.text(ci, Vector2(x, y0 + 20), str(h[2]), MmxUI.C_TEXT); x += MmxUI.text_width(str(h[2])) + 8.0

# ---- aviso que desliza ao trocar a armadura (L2/R2) ou o personagem (△) na tela dos chefes ----
func _toast_draw(ci: Control) -> void:
	if jogo_open or intro_t >= 0.0 or build_open or status_open or coop_open or finals_open: return
	var kind := toast_kind
	var k := 0.0
	if char_open:   # escolhendo o personagem: fica aberto
		kind = "char"; k = MmxUI.ease_out((t_anim - char_open_t) / 0.2)
	else:
		var dt := t_anim - toast_t
		if dt > 1.9 or dt < 0.0: return
		k = MmxUI.ease_out(dt / 0.2) * (1.0 - MmxUI.ease_out((dt - 1.5) / 0.35))
	var g: String = GAMES[page]
	var nm := ("Zero" if is_zero else "X") if kind == "char" else _arm_preset_name(g)
	var w := maxf(118.0, MmxUI.text_width("◀ " + nm + " ▶") + 60.0)
	var r := Rect2(roundf(320.0 - (w + 6.0) * k), 178, w, 30)
	MmxUI.frame(ci, r, MmxUI.C_GOLD if char_open else MmxUI.C_ACCENT, 5.0)
	MmxUI.text(ci, r.position + Vector2(7, 11), "PERSONAGEM" if kind == "char" else ("VARIANTE" if is_zero else "ARMADURA"), MmxUI.C_DIM)
	if char_open:   # setas balançando e brilho ao trocar
		var bob := roundf(1.0 + 1.0 * sin(t_anim * TAU * 2.0))
		MmxUI.text(ci, r.position + Vector2(7 - bob, 23), "◀", MmxUI.C_SEL)
		MmxUI.text(ci, r.position + Vector2(17, 23), nm, MmxUI.C_SEL)
		MmxUI.text(ci, r.position + Vector2(21 + MmxUI.text_width(nm) + bob, 23), "▶", MmxUI.C_SEL)
		var fl := clampf(1.0 - (t_anim - char_t) / 0.3, 0.0, 1.0)
		if fl > 0.0: ci.draw_colored_polygon(MmxUI.shape(r, 5.0), Color(1, 1, 1, 0.3 * fl))
		MmxUI.text(ci, Vector2(r.position.x, r.position.y + 23), "←→", MmxUI.C_DIM, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6)
	else:
		MmxUI.text(ci, r.position + Vector2(7, 23), "◀ " + nm + " ▶", MmxUI.C_SEL)
	if kind != "char" and not is_zero:   # as 4 peças (cores)
		var parts := _arm_parts(g)
		for i in 4:
			var kk := FangameParts.asset(str(parts.get(FangameParts.SLOTS[i], "")))
			var cc: Array = ARM_COL.get(kk, ARM_COL[""])
			var q := Rect2(r.end.x - 50 + i * 11, r.position.y + 7, 9, 9)
			ci.draw_rect(q, cc[0] if kk != "" else Color(0.08, 0.16, 0.3)); ci.draw_rect(q, cc[1] if kk != "" else MmxUI.C_EDGE_LO, false, 1.0)
	var lst := _armors(g); var idx: int = (zero_idx if is_zero else armor_idx)[g]
	if kind != "char": MmxUI.text(ci, Vector2(r.position.x, r.position.y + 23), "%d/%d" % [clampi(idx, 0, lst.size() - 1) + 1, lst.size()], MmxUI.C_DIM, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6)

class _Canvas extends Control:
	var fn: Callable
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if fn.is_valid(): fn.call(self)
