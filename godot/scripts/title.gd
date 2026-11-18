extends Control
class_name TitleScreen
## Tela de título do Mega Man X Fusion: as telas de título originais do X4, X5 e X6 se alternando,
## com "FUSION" por baixo do logo. PRESS START BUTTON -> menu do X5 (GAME START / CONTINUE / OPTION).
## Os textos são os sprites originais do menu do X5 (assets/menus/press_start.png, menu_*_on/off.png).

const TITLES := ["titulo_x4", "titulo_x5", "titulo_x6"]
const HOLD := 4.0    # segundos em cada jogo
const FADE := 1.0
const ITEMS := ["game_start", "continue", "option"]
var bgs: Array[TextureRect] = []
var logo: TextureRect
var press: TextureRect
var items: Array[TextureRect] = []
var tex_on := {}
var tex_off := {}
var t := 0.0
var leaving := -1.0
var go_scene := ""
var music: AudioStreamPlayer
var flash: ColorRect
static var start_state := ""   # "saves": abre direto na tela dos saves (vindo do hub)
var state := "press"    # press | menu | opcoes | saves
var sel := 0
var opt_box: Control
var opt_pn: MmxPanel
var opt_cv: Control
var saves_t := 0.0     # relógio quando a tela dos saves abriu (cartões entrando)

func _tex(name: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/menus/%s.png" % name))
	return ImageTexture.create_from_image(img) if img else null

func _sprite(tex: Texture2D, sc := 1.0) -> TextureRect:
	var r := TextureRect.new(); r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.size = tex.get_size() * sc
	return r

func _ready() -> void:
	Opcoes.apply(get_tree()); Opcoes.menu_mode(get_tree(), true)
	size = Vector2(320, 240)
	MmxUI.set_skin("x5")   # título: o visual do menu do X5 (o mesmo do "FUSION")
	theme = MmxUI.theme()
	var bg := ColorRect.new(); bg.color = Color.BLACK; bg.size = size; add_child(bg)
	for n in TITLES:
		var r := TextureRect.new(); r.texture = _tex(n); r.size = size
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; r.stretch_mode = TextureRect.STRETCH_SCALE
		r.modulate.a = 0.0; add_child(r); bgs.append(r)
	# faixa escura embaixo (cobre o copyright) para o FUSION e o menu
	var band := TextureRect.new()
	var gt := GradientTexture2D.new(); var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0)); gr.set_color(1, Color(0, 0.01, 0.05, 0.95)); gr.add_point(0.3, Color(0, 0.01, 0.05, 0.9))
	gt.gradient = gr; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 4; gt.height = 64
	band.texture = gt; band.position = Vector2(0, 140); band.size = Vector2(320, 100)
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; band.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(band)
	# FUSION: letras da fonte do menu do X5, o F feito a partir do E; 3x sem suavizar
	logo = _sprite(_tex("titulo_fusion"), 3.0)
	logo.position = Vector2(round((320 - logo.size.x) / 2), 150)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float pos = -1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = abs((UV.x + UV.y * 0.35) - pos);
	c.rgb += vec3(smoothstep(0.06, 0.0, d)) * 0.8 * c.a;
	COLOR = c;
}"""
	var mat := ShaderMaterial.new(); mat.shader = sh; logo.material = mat
	add_child(logo)
	press = _sprite(_tex("press_start"))
	press.position = Vector2(round((320 - press.size.x) / 2), 210)
	add_child(press)
	for i in ITEMS.size():
		tex_on[ITEMS[i]] = _tex("menu_%s_on" % ITEMS[i]); tex_off[ITEMS[i]] = _tex("menu_%s_off" % ITEMS[i])
		var r := _sprite(tex_off[ITEMS[i]])
		r.position = Vector2(round((320 - r.size.x) / 2), 192 + i * 14); r.visible = false
		add_child(r); items.append(r)
	opt_pn = MmxPanel.make(self, Rect2(18, 18, 284, 200), "OPÇÕES", MmxUI.C_GOLD)
	opt_cv = Control.new(); opt_cv.size = opt_pn.size; opt_cv.mouse_filter = Control.MOUSE_FILTER_IGNORE; opt_cv.draw.connect(_opt_draw)
	opt_pn.content.add_child(opt_cv)
	flash = ColorRect.new(); flash.color = Color(1, 1, 1, 0); flash.size = size; flash.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(flash)
	music = AudioStreamPlayer.new(); add_child(music)
	var mp := ProjectSettings.globalize_path("res://assets/musica/titulo.ogg")
	if FileAccess.file_exists(mp):
		var st := AudioStreamOggVorbis.load_from_file(mp)
		if st: st.loop = true; music.stream = st; music.volume_db = Opcoes.music_db(); music.play()   # tema do título do X5 (laço de 53 s)
	if start_state == "saves":
		start_state = ""; t = 2.0; _open_saves("carregar")
	_update(0.0)

var sfx_p := {}
func _sfx(nm: String) -> void:   # sons do menu de pausa do X4 (gravados do jogo): menu_move / menu_ok
	nm = str(MmxUI.SFX.get(nm, nm))
	if not sfx_p.has(nm):
		var p := AudioStreamPlayer.new(); add_child(p)
		p.stream = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://assets/sfx/%s.wav" % nm))
		sfx_p[nm] = p
	sfx_p[nm].play()

func _can_continue() -> bool:
	FangameSave.load_file()
	for s in FangameSave.data.slots:
		if s.used: return true
	return false

func _process(dt: float) -> void:
	t += dt
	_update(dt)
	if opt_pn and opt_pn.visible: opt_cv.queue_redraw()
	if save_box:
		for c in save_box.get_children(): (c as CanvasItem).queue_redraw()
	if leaving >= 0.0:
		leaving += dt
		flash.color.a = clampf(leaving / 0.35, 0.0, 1.0)
		music.volume_db = Opcoes.music_db() + linear_to_db(maxf(0.001, 1.0 - leaving / 0.35))
		if leaving > 0.45: get_tree().change_scene_to_file(go_scene)

func _update(_dt: float) -> void:
	var cyc := HOLD * TITLES.size()
	var tt := fmod(t, cyc)
	for i in bgs.size():
		# cada título aparece por HOLD segundos, com FADE de transição (imagem parada)
		var start := i * HOLD
		var d := fmod(tt - start + cyc, cyc)
		var a := 0.0
		if d < FADE: a = d / FADE
		elif d < HOLD: a = 1.0
		elif d < HOLD + FADE: a = 1.0 - (d - HOLD) / FADE
		if t < cyc and t < start: a = 0.0   # primeira volta: ainda não chegou a vez dele
		if t < FADE and i == 0: a = t / FADE   # entrada
		bgs[i].modulate.a = a
	# FUSION: entra de baixo no começo
	var e := clampf((t - 0.6) / 0.7, 0.0, 1.0)
	logo.modulate.a = e
	logo.position.y = (150 if state != "press" else 160) + (1.0 - e) * 30.0
	logo.visible = state != "saves"
	var s := fmod(t, 3.0)
	(logo.material as ShaderMaterial).set_shader_parameter("pos", -0.2 + s / 0.7 * 1.6 if t > 1.5 and s < 0.7 else -1.0)
	press.visible = state == "press" and t > 1.4 and fmod(t, 1.0) < 0.6
	var cont := _can_continue()
	for i in items.size():
		items[i].visible = state == "menu"
		items[i].texture = tex_on[ITEMS[i]] if i == sel else tex_off[ITEMS[i]]
		items[i].modulate = Color(1, 1, 1, 0.35) if ITEMS[i] == "continue" and not cont else Color.WHITE

func _ok(e: InputEvent) -> bool:
	return e.is_action_pressed("jump") or (e is InputEventKey and e.keycode in [KEY_ENTER, KEY_Z, KEY_SPACE]) \
		or (e is InputEventJoypadButton and e.button_index in [JOY_BUTTON_START, JOY_BUTTON_A])

func _back(e: InputEvent) -> bool:
	return (e is InputEventKey and e.keycode in [KEY_ESCAPE, KEY_BACKSPACE]) or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B)

func _dir(e: InputEvent) -> Vector2i:
	if e is InputEventKey:
		match e.keycode:
			KEY_UP: return Vector2i(0, -1)
			KEY_DOWN: return Vector2i(0, 1)
			KEY_LEFT: return Vector2i(-1, 0)
			KEY_RIGHT: return Vector2i(1, 0)
	if e is InputEventJoypadButton:
		match e.button_index:
			JOY_BUTTON_DPAD_UP: return Vector2i(0, -1)
			JOY_BUTTON_DPAD_DOWN: return Vector2i(0, 1)
			JOY_BUTTON_DPAD_LEFT: return Vector2i(-1, 0)
			JOY_BUTTON_DPAD_RIGHT: return Vector2i(1, 0)
	return Vector2i.ZERO

func _input(e: InputEvent) -> void:
	if state == "opcoes" and wait_bind != "": _bind_input(e)

func _unhandled_input(e: InputEvent) -> void:
	if leaving >= 0.0: return
	if not (e is InputEventKey or e is InputEventJoypadButton) or not e.is_pressed() or e.is_echo(): return
	get_viewport().set_input_as_handled()
	match state:
		"press":
			if _ok(e):
				if t < 1.4: t = 1.4   # pula a entrada
				state = "menu"; sel = 1 if _can_continue() else 0; _sfx("menu_ok")
		"menu":
			var d := _dir(e)
			if d.y != 0:
				sel = (sel + d.y + ITEMS.size()) % ITEMS.size()
				if ITEMS[sel] == "continue" and not _can_continue(): sel = (sel + d.y + ITEMS.size()) % ITEMS.size()
				_sfx("menu_move")
			elif _back(e): state = "press"; _sfx("menu_back")
			elif _ok(e):
				_sfx("menu_ok")
				match ITEMS[sel]:
					"game_start": _open_saves("novo")      # escolhe onde começar
					"continue": _open_saves("carregar")    # escolhe qual save continuar
					"option":
						state = "opcoes"; opt_sel = 0; opt_page = "geral"; _sfx("menu_open"); _draw_options()
		"opcoes":
			_options_input(e)
		"saves":
			_saves_input(e)
	_update(0.0)

# ---- opções ----
var opt_sel := 0
var opt_page := "geral"    # geral | botoes
var wait_bind := ""        # ação esperando tecla/botão
var bind_armed := false
const GERAL := ["volume", "musica", "modo", "res", "ajuste", "voz", "botoes", "padrao", "voltar"]

func _bar(v: int) -> String:
	return "■".repeat(v) + "□".repeat(10 - v)

func _opt_text(k: String) -> String:
	var d: Dictionary = Opcoes.data
	match k:
		"volume": return "Volume geral          < %s >" % _bar(int(d.volume))
		"musica": return "Música dos menus      < %s >" % _bar(int(d.musica))
		"modo":
			if Engine.is_embedded_in_editor(): return "Modo de tela          < só fora da aba Game >"
			return "Modo de tela          < %s >" % {"janela": "Janela", "sem_borda": "Sem borda", "tela_cheia": "Tela cheia"}.get(str(d.modo), "Janela")
		"res":
			if str(d.modo) != "janela": return "Tamanho da janela     < monitor >"
			return "Tamanho da janela     < %dx%d >" % Opcoes.RES[clampi(int(d.res), 0, Opcoes.RES.size() - 1)]
		"ajuste": return "Imagem                < %s >" % ("Nítida (sem esticar)" if str(d.ajuste) == "nitido" else "Tela toda")
		"voz": return "Falas do X e do Zero  < %s >" % ("X6" if str(d.voz) == "x6" else "X4 (inglês)")
		"botoes": return "Configurar botões..."
		"padrao": return "Restaurar o padrão"
		"voltar": return "Voltar"
	return k

func _rows() -> Array:
	return GERAL if opt_page == "geral" else Opcoes.ACTIONS.keys() + ["voltar"]

func _draw_options() -> void:
	if state == "opcoes" and not opt_pn.shown(): opt_pn.open()
	elif state != "opcoes" and opt_pn.shown(): opt_pn.close()
	for c in opt_pn.content.get_children():
		if c != opt_cv: c.queue_free()
	if state != "opcoes": return
	opt_pn.title = "OPÇÕES" if opt_page == "geral" else "BOTÕES"
	var rows := _rows()
	var rh := 18 if opt_page == "geral" else 16
	for i in rows.size():
		var k: String = rows[i]
		var cols: Array = []   # [texto, x]
		if opt_page == "geral":
			var tx := _opt_text(k)
			if "  <" in tx: cols = [[tx.split("  <")[0].strip_edges(), 14], ["<" + tx.split("  <")[1], 142]]
			else: cols = [[tx, 14]]
		elif k == "voltar": cols = [["Voltar", 14]]
		elif wait_bind == k: cols = [[Opcoes.ACTIONS[k][0], 14], ["aperte a tecla ou o botão novo...", 120]]
		else: cols = [[Opcoes.ACTIONS[k][0], 14], [Opcoes.key_name(k), 130], [Opcoes.joy_name(k), 196]]
		for c in cols:
			var l := Label.new(); l.position = Vector2(c[1], 12 + i * rh); l.size = Vector2(270 - c[1], rh); l.text = c[0]
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			if i == opt_sel: l.add_theme_color_override("font_color", MmxUI.C_SEL)
			opt_pn.content.add_child(l)
	opt_cv.queue_redraw()

func _opt_draw() -> void:
	if state != "opcoes": return
	var rh := 18 if opt_page == "geral" else 16
	MmxUI.sel_bar(opt_cv, Rect2(10, 12 + opt_sel * rh + 2, opt_pn.size.x - 20, rh - 3), t, MmxUI.C_GOLD)
	var hs := "↑↓ escolher   ←→ mudar   Z confirmar   Esc voltar" if opt_page == "geral" else "Z trocar   Esc voltar"
	MmxUI.text(opt_cv, Vector2(0, opt_pn.size.y - 6), hs, MmxUI.C_DIM, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, opt_pn.size.x)

func _options_input(e: InputEvent) -> void:
	var d: Dictionary = Opcoes.data
	var dir := _dir(e)
	var rows := _rows()
	if dir.y != 0: opt_sel = (opt_sel + dir.y + rows.size()) % rows.size(); _sfx("menu_move")
	elif _back(e):
		if opt_page == "botoes": opt_page = "geral"; opt_sel = GERAL.find("botoes"); _sfx("menu_back")
		else: state = "menu"; _sfx("menu_close")
	elif opt_page == "geral":
		var k: String = rows[opt_sel]
		var step := dir.x
		if step == 0 and _ok(e): step = 1
		if step != 0:
			match k:
				"volume": d.volume = clampi(int(d.volume) + step, 0, 10)
				"musica": d.musica = clampi(int(d.musica) + step, 0, 10)
				"modo":
					var m := ["janela", "sem_borda", "tela_cheia"]
					d.modo = m[(maxi(m.find(str(d.modo)), 0) + step + 3) % 3]
				"res": if str(d.modo) == "janela": d.res = (int(d.res) + step + Opcoes.RES.size()) % Opcoes.RES.size()
				"ajuste": d.ajuste = "nitido" if str(d.ajuste) != "nitido" else "preencher"
				"voz": d.voz = "x4" if str(d.voz) == "x6" else "x6"
				"botoes": if _ok(e): opt_page = "botoes"; opt_sel = 0
				"padrao": if _ok(e): Opcoes.data = Opcoes.defaults()
				"voltar": if _ok(e): state = "menu"; _sfx("menu_close")
			Opcoes.save_file(); Opcoes.apply(get_tree())
			music.volume_db = Opcoes.music_db()
			_sfx("menu_move" if dir.x != 0 else "menu_ok")
	elif _ok(e):
		var k: String = rows[opt_sel]
		if k == "voltar": opt_page = "geral"; opt_sel = GERAL.find("botoes")
		else: wait_bind = k; bind_armed = false
	_draw_options()

func _bind_input(e: InputEvent) -> void:
	# espera soltar o botão de confirmar antes de aceitar o novo
	if not (e is InputEventKey or e is InputEventJoypadButton): return
	get_viewport().set_input_as_handled()
	if not e.is_pressed():
		bind_armed = true; return
	if not bind_armed or e.is_echo(): return
	if e is InputEventKey and e.keycode == KEY_ESCAPE:
		wait_bind = ""; _draw_options(); return
	if e is InputEventKey: Opcoes.data.botoes[wait_bind].key = int(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
	else: Opcoes.data.botoes[wait_bind].joy = int(e.button_index)
	wait_bind = ""
	Opcoes.save_file(); Opcoes.apply(get_tree())
	_draw_options()


# ---- tela dos saves (3 saves; jogar, copiar, apagar) ----
var save_mode := "carregar"    # novo (GAME START) | carregar (CONTINUE / vindo do hub)
var save_sel := 0
var save_ask := ""             # "" | apagar | sobrescrever | copiar
var save_src := 0
var save_box: Control

func _open_saves(mode: String) -> void:
	FangameSave.load_file()
	state = "saves"; save_mode = mode; save_ask = ""; saves_t = t
	save_sel = int(FangameSave.data.get("last", 0))
	if mode == "novo":   # GAME START: começa no primeiro save vazio, se houver
		for i in FangameSave.SLOTS:
			if not FangameSave.data.slots[i].used: save_sel = i; break
	_draw_saves()

func _saves_input(e: InputEvent) -> void:
	var n: int = FangameSave.SLOTS
	var d := _dir(e)
	var slot: Dictionary = FangameSave.data.slots[save_sel]
	var del: bool = (e is InputEventKey and e.keycode in [KEY_DELETE, KEY_V]) or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y)
	var cpy: bool = (e is InputEventKey and e.keycode == KEY_C) or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X)
	if d.y != 0 and save_ask in ["", "copiar"]:
		save_sel = (save_sel + d.y + n) % n; _sfx("menu_move")
	elif _back(e):
		_sfx("menu_back")
		if save_ask != "": save_ask = ""
		else: state = "menu"
	elif save_ask == "apagar":
		if del or _ok(e): FangameSave.erase(save_sel)
		save_ask = ""
	elif save_ask == "copiar":
		if _ok(e) or cpy:
			if save_sel != save_src: FangameSave.copy(save_src, save_sel)
			save_ask = ""
	elif save_ask == "sobrescrever":
		if _ok(e): FangameSave.erase(save_sel); _start_save(save_sel)
		else: save_ask = ""
	elif del and slot.used: save_ask = "apagar"; _sfx("menu_error")
	elif cpy and slot.used: save_ask = "copiar"; save_src = save_sel; _sfx("menu_tab")
	elif (del or cpy) and not slot.used: _sfx("menu_error")
	elif _ok(e):
		if save_mode == "novo" and slot.used: save_ask = "sobrescrever"; _sfx("menu_error")
		else: _start_save(save_sel)
	_draw_saves()

func _start_save(i: int) -> void:
	_sfx("menu_ok")
	FangameSave.select(i)
	go_scene = "res://scenes/hub.tscn"; leaving = 0.0

func _draw_saves() -> void:
	if save_box: save_box.queue_free(); save_box = null
	if state != "saves": return
	save_box = Control.new(); save_box.size = Vector2(320, 240); save_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(save_box); move_child(save_box, flash.get_index())
	var dim := ColorRect.new(); dim.color = Color(0, 0.01, 0.05, 0.6); dim.size = save_box.size; save_box.add_child(dim)
	var head := _SaveHead.new(); head.title = self; head.size = Vector2(320, 240); save_box.add_child(head)
	for i in FangameSave.SLOTS:
		var card := _SaveCard.new(); card.slot = FangameSave.data.slots[i]; card.index = i; card.title = self
		card.selected = i == save_sel; card.copying = save_ask == "copiar" and i == save_src
		card.position = Vector2(12 + (6 if i == save_sel else 0), 28 + i * 62); card.size = Vector2(290, 58)
		save_box.add_child(card)

# título e dicas da tela dos saves (desenho)
class _SaveHead extends Control:
	var title
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var tt: float = title.t - title.saves_t
		var a := MmxUI.ease_out(tt / 0.3)
		var txt := "NOVO JOGO" if title.save_mode == "novo" else "CONTINUAR"
		MmxUI.text(self, Vector2(0, 19 - (1.0 - a) * 8.0), txt, Color(MmxUI.C_GOLD.r, MmxUI.C_GOLD.g, MmxUI.C_GOLD.b, a), 18, HORIZONTAL_ALIGNMENT_CENTER, 320)
		draw_line(Vector2(40, 23), Vector2(280, 23), Color(MmxUI.C_ACCENT.r, MmxUI.C_ACCENT.g, MmxUI.C_ACCENT.b, 0.4 * a), 1.0)
		var col := MmxUI.C_TEXT; var h := ""
		match str(title.save_ask):
			"apagar": h = "APAGAR O SAVE %d?   Del/△ ou Z: apagar    Esc: não" % (title.save_sel + 1); col = MmxUI.C_WARN
			"sobrescrever": h = "O SAVE %d JÁ TEM PROGRESSO. Começar do zero?  Z: sim  Esc: não" % (title.save_sel + 1); col = MmxUI.C_WARN
			"copiar": h = "COPIAR O SAVE %d PARA QUAL?   ↑↓ escolher   Z: copiar   Esc: cancelar" % (title.save_src + 1); col = MmxUI.C_ACCENT
			_: h = "Z/Start: %s    C/□: copiar    Del/△: apagar    Esc: voltar" % ("começar" if title.save_mode == "novo" else "jogar")
		draw_rect(Rect2(0, 218, 320, 22), Color(0, 0.02, 0.07, 0.85))
		draw_line(Vector2(0, 218), Vector2(320, 218), Color(MmxUI.C_ACCENT.r, MmxUI.C_ACCENT.g, MmxUI.C_ACCENT.b, 0.45), 1.0)
		MmxUI.text(self, Vector2(0, 232), MmxUI.fit(h, 316), col, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_CENTER, 320)

# um save: o boneco do holograma com as cores das peças montadas e os retratos dos 24 chefes (apagados = já vencidos)
const HubScript := preload("res://scripts/hub.gd")
class _SaveCard extends Control:
	var slot := {}
	var index := 0
	var selected := false
	var copying := false
	var title
	static var menus := {}
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _menu(nm: String) -> Texture2D:
		if not menus.has(nm):
			var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/menus/%s.png" % nm))
			menus[nm] = ImageTexture.create_from_image(img) if img else null
		return menus[nm]
	func _draw() -> void:
		var tt: float = title.t - title.saves_t
		var ap := MmxUI.ease_out((tt - 0.05 - index * 0.08) / 0.3)   # entram da esquerda, um depois do outro
		if ap <= 0.0: return
		var dx := roundf(-(1.0 - ap) * 60.0)
		draw_set_transform(Vector2(dx, 0), 0.0, Vector2.ONE)
		var r := Rect2(Vector2.ZERO, size)
		MmxUI.frame(self, r, MmxUI.C_ACCENT if copying else (MmxUI.C_GOLD if selected else MmxUI.C_EDGE_LO), 7.0)
		if selected:
			var pul := 0.35 + 0.35 * sin(float(title.t) * TAU * 1.5)
			var pts := MmxUI.shape(r.grow(1.0), 8.0); pts.append(pts[0]); draw_polyline(pts, Color(1, 0.86, 0.35, pul), 1.0)
		var used: bool = slot.get("used", false)
		MmxUI.text(self, Vector2(6, 12), "SAVE %d" % (index + 1), MmxUI.C_SEL if selected else MmxUI.C_DIM)
		# distintivo da armadura montada do save (as 4 cores; emblema com o conjunto completo)
		var cols := {}
		for p in FangameParts.SLOTS:
			var k := FangameParts.asset(str(slot.get("parts", {}).get(p, ""))) if used else ""
			var cc: Array = MmxUI.ARM_COL.get(k, MmxUI.ARM_COL[""])
			cols[p] = [cc[0], cc[1], k != ""]
		var fk := FangameParts.full_set(slot.get("parts", {})) if used else ""
		MmxUI.badge(self, Vector2(26, 34), 15.0, cols, fk, (0.5 + 0.5 * sin(float(title.t) * TAU * 1.1)) if fk != "" else 0.0)
		if not used:
			MmxUI.text(self, Vector2(60, 34), "vazio  -  novo jogo", MmxUI.C_DIM)
			return
		# retratos dos chefes de cada jogo, na ordem das fases; os vencidos ficam apagados
		for gi in 3:
			var g: String = ["x4", "x5", "x6"][gi]
			var prog: Array = slot.progress.get(g, [])
			var y := 4 + gi * 18
			MmxUI.text(self, Vector2(52, y + 12), g.to_upper(), MmxUI.C_ACCENT)
			for pos_i in 8:
				var stg: int = HubScript.POS_STAGE[g][pos_i]
				var won: bool = stg in prog
				var tex := _menu("mini/%s_%d%s" % [g, stg, "_cinza" if won else ""])   # retrato recortado; vencido = cinza
				if tex == null: continue
				var cr := Rect2(68 + (stg - 1) * 27, y, 25, 16)
				var sc := minf(cr.size.x / tex.get_width(), cr.size.y / tex.get_height())
				var ds := Vector2(tex.get_width(), tex.get_height()) * sc
				draw_texture_rect(tex, Rect2(cr.position + (cr.size - ds) / 2.0, ds), false)
