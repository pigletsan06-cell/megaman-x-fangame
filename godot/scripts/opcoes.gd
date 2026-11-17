class_name Opcoes
## Opções do fangame (user://opcoes.json): volume, música dos menus, modo de tela/escala, voz das falas e botões.

const FILE := "user://opcoes.json"
# ações que podem ser trocadas: [nome na tela, tecla padrão, botão padrão do controle]
const ACTIONS := {
	"jump": ["Pulo", KEY_Z, JOY_BUTTON_A],
	"shoot": ["Tiro", KEY_X, JOY_BUTTON_X],
	"dash": ["Dash", KEY_C, JOY_BUTTON_RIGHT_SHOULDER],   # como antes (RB fazia dash e R1)
	"special": ["Arma especial (△)", KEY_V, JOY_BUTTON_Y],
	"weapon_prev": ["Arma anterior (L1)", KEY_A, JOY_BUTTON_LEFT_SHOULDER],
	"weapon_next": ["Próxima arma (R1)", KEY_S, JOY_BUTTON_RIGHT_SHOULDER],
}
static var data := {}

static func defaults() -> Dictionary:
	var b := {}
	for a in ACTIONS: b[a] = {"key": ACTIONS[a][1], "joy": ACTIONS[a][2]}
	return {"volume": 8, "musica": 8, "modo": "janela", "res": 4, "ajuste": "preencher", "voz": "x6", "botoes": b}

# tamanhos de janela
const RES := [[960, 720], [1280, 720], [1280, 960], [1600, 900], [1920, 1080], [2560, 1440]]

static func load_file() -> void:
	if not data.is_empty(): return
	data = defaults()
	if FileAccess.file_exists(FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary:
			for k in d: data[k] = d[k]
			if d.has("tela_cheia") and not d.has("modo"): data.modo = "tela_cheia" if d.tela_cheia else "janela"
			data.erase("tela_cheia")
			var b: Dictionary = defaults().botoes
			for a in b:
				if not data.botoes.has(a): data.botoes[a] = b[a]
	for a in data.botoes:
		data.botoes[a].key = int(data.botoes[a].key); data.botoes[a].joy = int(data.botoes[a].joy)

static func save_file() -> void:
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data, "\t")); f.close()

static func db(v) -> float:   # 0..10 -> dB
	return -80.0 if int(v) <= 0 else linear_to_db(float(v) / 10.0)

static func music_db() -> float:
	load_file()
	return db(data.musica) - 4.0

# aplica tudo (chamado ao abrir o jogo e ao mudar uma opção)
static func apply(tree: SceneTree = null) -> void:
	load_file()
	AudioServer.set_bus_volume_db(0, db(data.volume))
	for a in ACTIONS:
		if not InputMap.has_action(a): InputMap.add_action(a, 0.5)
		InputMap.action_erase_events(a)
		var k := InputEventKey.new(); k.physical_keycode = int(data.botoes[a].key); InputMap.action_add_event(a, k)
		var j := InputEventJoypadButton.new(); j.button_index = int(data.botoes[a].joy); InputMap.action_add_event(a, j)
	if tree:
		# nítido: só múltiplos inteiros de 320x240 (sobra borda); preencher: a imagem 4:3 ocupa a altura toda
		tree.root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if str(data.ajuste) == "nitido" else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if tree and not Engine.is_embedded_in_editor() and str(tree.root.get_meta("opcoes_janela", "")) != str([data.modo, data.res]):
		tree.root.set_meta("opcoes_janela", [data.modo, data.res])
		match str(data.modo):
			"tela_cheia":   # tela cheia exclusiva (muda o monitor só pro jogo)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			"sem_borda":    # janela sem borda do tamanho do monitor (alt+tab rápido)
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			_:              # janela normal, com borda
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				var r: Array = RES[clampi(int(data.res), 0, RES.size() - 1)]
				var sz := Vector2i(r[0], r[1])
				var sc := DisplayServer.screen_get_usable_rect()
				sz = Vector2i(mini(sz.x, sc.size.x), mini(sz.y, sc.size.y))
				DisplayServer.window_set_size(sz)
				DisplayServer.window_set_position(sc.position + (sc.size - sz) / 2)

# menus (título, hub): desenhados na resolução da janela (retratos e textos nítidos);
# fases: a imagem do PS1 em 320x240 ampliada inteira
static func menu_mode(tree: SceneTree, on: bool) -> void:
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if on else Window.CONTENT_SCALE_MODE_VIEWPORT

static func key_name(a: String) -> String:
	load_file()
	return OS.get_keycode_string(int(data.botoes[a].key))

static func joy_name(a: String) -> String:
	load_file()
	var n := {JOY_BUTTON_A: "A / ✕", JOY_BUTTON_B: "B / ○", JOY_BUTTON_X: "X / □", JOY_BUTTON_Y: "Y / △",
		JOY_BUTTON_LEFT_SHOULDER: "LB / L1", JOY_BUTTON_RIGHT_SHOULDER: "RB / R1", JOY_BUTTON_LEFT_STICK: "L3",
		JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "Select", JOY_BUTTON_START: "Start"}
	return n.get(int(data.botoes[a].joy), "botão %d" % int(data.botoes[a].joy))
