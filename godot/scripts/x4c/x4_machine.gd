class_name X4Machine
extends Node2D
## Roda o Mega Man X4 original (código do decomp traduzido em scripts/x4c/gen) quadro a quadro
## e desenha as primitivas do GPU do PS1 com a VRAM numa textura.

var pool: Array = []
var used := 0
var mats := {}
var vram_img: Image
var vram_tex: ImageTexture
var vram_texs: Array = []   # duas texturas alternadas: enviar a VRAM nova não espera a placa terminar de usar a anterior
var vram_k := 0
var booted := false
var frame_us := 0
var up_us := 0
var up_n := 0
var forced := 0
@export var game := "x4"   # x4: jogo compilado; x5/x6: núcleo de PS1 (PsxCore)
var core := "X4Core"
var force_gdscript := false
var native := false        # true: jogo compilado (bin/x4core), false: tradução em GDScript
var recomp := false        # X5/X6 pela recompilação (bin/recomp_x5|x6) em vez do emulador PsxCore
var tela: Sprite2D         # imagem da tela pronta (recompilação)
var tela_img: Image
var tela_tex: ImageTexture
var stream := PackedInt32Array()

# ---- hub do fangame: a fase escolhida no hub (vazio = jogo normal) ----
static var launch := {}      # {"game": "x5", "stage": 5, "char": 0, "armor": 1}
var L := {}                  # a fase deste nó (= launch, ou a do pré-carregamento)
var preload_mode := false    # hub: prepara a fase escondido enquanto o cursor está parado no chefe
var preload_done := false
var pre_task := -1
var pre_stop := false

func _preload_loop() -> void:
	while launch_phase == 1 and not pre_stop:
		step_frame(false)

func stop_preload() -> void:
	if pre_task >= 0:
		pre_stop = true; WorkerThreadPool.wait_for_task_completion(pre_task); pre_task = -1

func _exit_tree() -> void:   # o hub trocou de chefe ou começou a fase: o preparo para antes do núcleo ser usado de novo
	if mix6 == 1: _mix6_log_flush()
	if not preload_mode: Engine.max_fps = 0   # menus voltam ao normal
	if pre_task >= 0:
		pre_stop = true; WorkerThreadPool.wait_for_task_completion(pre_task); pre_task = -1
static var handoff := {}     # pré-carregamento entregue à tela da fase: {"key", "lf", "snap_done"} (o núcleo segue rodando)
static var render_only := false   # testes: só desenha um fluxo/VRAM gravados
static var last_result := {} # resultado da última fase: {"game", "stage", "won"}
var won := false
var hub_mode := false
var launch_phase := 0        # 1: preparando (rápido, sem desenho), 2: jogando
var lf := 0                  # quadros do núcleo desde o início
var seen_play := false
var lf_play := 0
# estados salvos do núcleo de PS1 no "Now Loading" (fase ainda não escolhida): a próxima entrada começa dali
const SNAP_VERSION := 6   # aumentar quando o núcleo de PS1 mudar (o estado salvo antigo deixa de servir)
static var snapshots := {}
var snap_done := false
var out_frames := 0
var load_layer: CanvasLayer
# endereços (X5/X6) e roteiro de botões até a fase (quadro, botões) — determinístico, sem cartão de memória
const PSX_ADDR := {"x5": {"state": 0xD1C00, "stage": 0xD1C0C, "char": 0xD1C49},
	"x6": {"state": 0xCCED0, "stage": 0xCCEDC, "char": 0xCCF2E}}
const B_START := 1 << 11
const B_CROSS := 1 << 6
const B_DOWN := 1 << 14
const PSX_SCRIPT := {
	# X5: título -> TRAINING -> escolha do personagem -> carregando (troca a fase)
	"x5": [[700, 710, B_START], [830, 835, B_DOWN], [870, 875, B_DOWN], [910, 915, B_DOWN], [960, 966, B_CROSS], [1210, 1216, B_CROSS]],
	# X6: título -> GAME START -> pula a conversa -> carregando (troca a fase)
	"x6": [[900, 905, B_START], [1000, 1006, B_CROSS], [1400, 1403, B_START], [1460, 1463, B_START]],
}
# recompilação (os vídeos tocam no jogo): o roteiro segue a tela do jogo, não a contagem de quadros
const X5_MENU_CURSOR := 0xD1F2A   # cursor do menu do título do X5 (3 = TRAINING)
var rc_sel_t := -1                # quadro em que a escolha de personagem do X5 apareceu

func _ready() -> void:
	if not preload_mode and is_inside_tree() and get_parent() == get_tree().root: Opcoes.menu_mode(get_tree(), false)   # fase: imagem 320x240 ampliada
	if not preload_mode: Engine.max_fps = 60   # monitor de 120/144 Hz: a fase anda certinha a 60 (sem quadros repetidos fora de ordem)
	# opções na linha de comando (depois de --): fase=N subfase=N ponto=N zero
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		match kv[0]:
			"fase": X4R.env["MMX4_ORACLE_SCENE"] = "initial-stage"; X4R.env["MMX4_DIRECT_STAGE"] = kv[1]
			"subfase": X4R.env["MMX4_DIRECT_SUBSTAGE"] = kv[1]
			"ponto": X4R.env["MMX4_DIRECT_CHECKPOINT"] = kv[1]
			"zero": X4R.env["MMX4_DIRECT_CHARACTER"] = "1"
			"gdscript": force_gdscript = true
			"jogo": game = kv[1]
	if not preload_mode: L = launch
	if not L.is_empty():
		hub_mode = true
		game = L.get("game", "x4")
		if game == "x4":
			X4R.env["MMX4_ORACLE_SCENE"] = "initial-stage"
			X4R.env["MMX4_DIRECT_STAGE"] = str(L.get("stage", 1))
			X4R.env["MMX4_DIRECT_CHARACTER"] = str(L.get("char", 0))
			X4R.env["MMX4_DIRECT_LOADOUT"] = str(L.get("armor", 0))
			X4R.env["MMX4_DIRECT_SECRET"] = "1" if L.get("secret", false) else "0"
			skin = L.get("skin", "")
			parts = L.get("parts", {})
			if parts.is_empty() and skin != "":   # armadura inteira (Ultimate etc.)
				for p in SKIN_PARTS: parts[p] = skin
			# armadura de outro jogo: peças do X4 que dão as habilidades parecidas + código das habilidades novas (x4core fg_armor)
			for k in ["MMX4_DIRECT_ARMOR", "MMX4_DIRECT_SKILL", "MMX4_PARTS", "MMX4_ARMTYPE", "MMX4_CAPS"]: X4R.env.erase(k)
			X4R.env["MMX4_BZ"] = str(L.get("bz", 0))   # peças/melhorias do Black Zero (x4core fg_bz)
			X4R.env["MMX4_NZ"] = str(L.get("nz", 0))   # peças/melhorias do Nightmare Zero (x4core fg_nz)
			if skin != "" and SKIN_INFO.has(skin):
				X4R.env["MMX4_DIRECT_ARMOR"] = str(SKIN_INFO[skin][0]); X4R.env["MMX4_DIRECT_SKILL"] = str(SKIN_INFO[skin][1])
			elif not parts.is_empty() and int(L.get("char", 0)) == 0:   # montada no hub, peça por peça
				var ce := FangameParts.core_env(parts)
				for k in ce: X4R.env["MMX4_" + ("DIRECT_" if k in ["ARMOR", "SKILL"] else "") + k] = ce[k]
				skin = FangameParts.full_set(parts) if FangameParts.needs_skin(parts) else ""
				if not FangameParts.needs_skin(parts): parts = {}
			if L.get("save", {}).has("caps"): X4R.env["MMX4_CAPS"] = str(L.save.caps)   # cápsulas do X4 já pegas (as outras aparecem na fase)
			if skin.begins_with("Ultimate"): X4R.env["MMX4_DIRECT_SECRET"] = "1"
			Opcoes.load_file()
			if str(Opcoes.data.voz) == "x6": X4R.env["MMX4_VOZ_X6"] = "1"   # falas do X e do Zero do X6 (Opções)
			else: X4R.env.erase("MMX4_VOZ_X6")
			if L.has("save"): X4R.env["MMX4_SAVE"] = L.save.env   # save único do fangame
			else: X4R.env.erase("MMX4_SAVE")
			if L.has("save") and L.save.has("tanks_env"): X4R.env["MMX4_TANKS"] = L.save.tanks_env   # sub tanks (eficácia)
			else: X4R.env.erase("MMX4_TANKS")
			launch_phase = 2
		else:
			launch_phase = 1
	if game != "x4":
		core = "PsxCore"
		if use_recomp(game): core = recomp_class(game); recomp = true
	native = ClassDB.class_exists(core) and OS.get_environment("X4_GDSCRIPT") == "" and not force_gdscript
	if not native:
		X4R.init()
	X4R.gpu_init()
	var sh: Shader = load("res://scripts/x4c/psx_gpu.gdshader")
	vram_img = Image.create_from_data(1024, 512, false, Image.FORMAT_RG8, X4R.vram)
	vram_tex = ImageTexture.create_from_image(vram_img)
	vram_texs = [vram_tex, ImageTexture.create_from_image(vram_img)]
	# -1: normal; 10+n: pontos opacos de um desenho semitransparente; 20+n: pontos com mistura n do PS1
	var blends := {0: "blend_mix", 1: "blend_add", 2: "blend_sub", 3: "blend_add"}
	mats[-1] = _mat(sh, 0)
	for mode in 4:
		mats[10 + mode] = _mat(sh, 1)
		var s2 := Shader.new()
		s2.code = sh.code.replace("render_mode unshaded;", "render_mode unshaded, %s;" % blends[mode])
		var m := _mat(s2, 2)
		match mode:
			0: m.set_shader_parameter("semi_alpha", 0.5)
			3: m.set_shader_parameter("semi_scale", 0.25)
		mats[20 + mode] = m
	if not preload_mode: _video_init()
	if render_only: return
	if native and core != "X4Core":
		_start_psx()
		return
	if not native and core != "X4Core":
		print("X4: PsxCore não carregou (bin/psxcore)")
		return
	if native and not X4R.env.has("MMX4_ORACLE_SCENE") and _play_movie(0, true):
		return   # o jogo começa depois do logo da Capcom
	_start_game()

func _disc_path() -> String:
	return disc_file(game)

# discos conferidos pelo launcher (SHA-1 certo): godot/discos.json {"x4": {"caminho": ...}, "x5": ..., "x6": ...}
static func discos_launcher() -> Dictionary:
	var p := ProjectSettings.globalize_path("res://discos.json")
	if not FileAccess.file_exists(p): return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}

# aceita os nomes comuns do disco (o X6 pode ser a versão 1.1)
static func disc_file(g: String) -> String:
	var names := {"x4": ["Mega Man X4 (USA).bin", "Mega Man X4.bin"], "x5": ["Mega Man X5 (USA).bin", "Mega Man X5.bin"],
		"x6": ["Mega Man X6 (USA).bin", "Mega Man X6 (USA) (v1.1).bin", "Mega Man X6 (USA) (v1.0).bin", "Mega Man X6.bin"]}
	var disc := OS.get_environment("PSX_BIN")
	if disc != "": return disc
	var dl: Dictionary = discos_launcher().get(g, {})
	if FileAccess.file_exists(str(dl.get("caminho", ""))): return str(dl.caminho)
	var base := ProjectSettings.globalize_path("res://").path_join("..")
	var lista: Array = names.get(g, [])
	for n in lista:
		if FileAccess.file_exists(base.path_join(n)): return base.path_join(n)
	return base.path_join(lista[0] if not lista.is_empty() else "")

# estados salvos de um disco não servem para outra versão do disco: o nome do arquivo entra na marca
static func disc_tag(g: String) -> String:
	if g != "x5" and g != "x6": return ""
	var n := disc_file(g).get_file()
	if discos_launcher().has(g): n = "Mega Man %s (USA).bin" % g.to_upper()   # o launcher conferiu o SHA-1: é o disco certo
	var t := "" if n == "Mega Man %s (USA).bin" % g.to_upper() else "_d%x" % (n.hash() & 0xFFFF)
	if use_recomp(g): t += "_rc"   # estados da recompilação não servem para o emulador (e vice-versa)
	return t

# recompilação do X5/X6 (bin/recomp_xN): usada quando a biblioteca existe (X4_PSXCORE=1 volta ao emulador)
static func recomp_class(g: String) -> String:
	return "Recomp" + g.to_upper()

static func use_recomp(g: String) -> bool:
	return (g == "x5" or g == "x6") and OS.get_environment("X4_PSXCORE") == "" and ClassDB.class_exists(recomp_class(g))

func _start_env() -> String:
	if not recomp: return "DISC=" + _disc_path()
	var dir := ProjectSettings.globalize_path("res://bin/recomp_" + game)
	if OS.get_environment("RC_GAMEDIR_" + game.to_upper()) != "": dir = OS.get_environment("RC_GAMEDIR_" + game.to_upper())   # (teste: 2 Godot no mesmo PC)
	var cards := ProjectSettings.globalize_path("user://recomp_" + game)
	DirAccess.make_dir_recursive_absolute(cards)
	return "DISC=%s;GAMEDIR=%s;CARDDIR=%s" % [_disc_path(), dir, cards]

static func launch_key(l: Dictionary) -> String:
	return "%s_%d_%d_%d_%d_%s" % [l.get("game", ""), int(l.get("stage", 1)), int(l.get("char", 0)), int(l.get("char_code", 0)), 1 if l.get("secret", false) else 0, l.get("save", {}).get("key", "")]

func _start_psx() -> void:
	if not preload_mode and hub_mode and handoff.get("key", "") == launch_key(L):
		# o hub já estava preparando esta fase: o núcleo continua de onde parou
		lf = int(handoff.lf); snap_done = handoff.snap_done; handoff = {}
		print("hub: continuando o pré-carregamento (quadro ", lf, ")")
		_audio_init_psx(); booted = true
		if perf_label == null: _perf_init()
		return
	handoff = {}
	var disc := _disc_path()
	var bios := FileAccess.get_file_as_bytes("res://bin/openbios.bin")
	# cartão de memória salvo deste jogo (user://x5_cartao0.mcr / user://x6_cartao0.mcr)
	var cp := "user://%s_cartao0.mcr" % game
	if FileAccess.file_exists(cp) and not hub_mode and not recomp:
		ClassDB.class_call_static(core, "card_set", 0, FileAccess.get_file_as_bytes(cp))
	var r: int = ClassDB.class_call_static(core, "start", bios, _start_env())
	print("X4: núcleo de PS1 (", game, ") iniciado: ", r, " disco ", disc)
	var lg: String = ClassDB.class_call_static(core, "log")
	if lg != "": print(lg)
	if not preload_mode: _audio_init_psx()
	if hub_mode and not _stage_snap_restore(): _snapshot_restore()
	booted = true
	if preload_mode: return
	if perf_label == null: _perf_init()

func _audio_init_psx() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 44100
	gen.buffer_length = 0.07 if recomp else 0.12   # recompilação: o som chega quadro a quadro, reservatório menor = menos atraso
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = gen
	add_child(audio_player)
	audio_player.play()
	playback = audio_player.get_stream_playback()

func _start_game() -> void:
	if native:
		var envs := PackedStringArray()
		for k in X4R.env: envs.append("%s=%s" % [k, X4R.env[k]])
		# cartão de memória salvo (user://x4_cartao0.mcr)
		for port in 2:
			var cp := "user://x4_cartao%d.mcr" % port
			if FileAccess.file_exists(cp) and not hub_mode:
				ClassDB.class_call_static(core, "card_set", port, FileAccess.get_file_as_bytes(cp))
		var disc := FileAccess.get_file_as_bytes("res://assets/x4c_disc_arc.sec")
		var r: int = ClassDB.class_call_static(core, "start", disc, ";".join(envs))
		print("X4: jogo compilado (nativo) iniciado: ", r)
		_audio_init()
	else:
		print("X4: usando a tradução em GDScript (mais lenta)")
		_gdscript_x4().c_godot_boot()
	booted = true
	if perf_label == null: _perf_init()

# ------------------------------------------------------------------ vídeos (STR do disco convertidos para .ogv)
const MOVIES := ["CAPCOM20", "OP_U", "X1_U", "X2_U", "X3_U", "X4_U", "Z1_U", "Z2_U", "Z3_U", "Z4_U", "Z5_U"]
# X5/X6: vídeos .STR do disco em ordem de posição (o núcleo de PS1 pede pelo índice)
const MOVIES_PSX := {"x5": ["x5_CAPLOGO", "x5_X5OP"], "x6": ["x6_CAPLOGO", "x6_X6OP"]}
var video: VideoStreamPlayer
var movie_on := false
var movie_boot := false
var movie_t := 0.0

# tradução antiga do X4 em GDScript (scripts/x4c/gen, fora do projeto normal): só se a DLL do X4 faltar
func _gdscript_x4() -> Variant:
	return load("res://scripts/x4c/gen/X4M_godot_frame.gd")

func _video_init() -> void:
	var cl := CanvasLayer.new(); cl.layer = 50; add_child(cl)
	var bg := ColorRect.new(); bg.color = Color.BLACK; bg.size = Vector2(320, 240); bg.visible = false
	cl.add_child(bg)
	video = VideoStreamPlayer.new()
	video.size = Vector2(320, 240); video.expand = true; video.visible = false
	cl.add_child(video)
	video.set_meta("bg", bg)

func _play_movie(idx: int, boot := false) -> bool:
	var names: Array = MOVIES_PSX.get(game, MOVIES)
	if idx < 0 or idx >= names.size(): return false
	var path := "res://assets/movies/%s.ogv" % names[idx]
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path): return false
	var st = load(path)
	if st == null:
		st = VideoStreamTheora.new(); st.file = path
	video.stream = st
	video.visible = true; video.get_meta("bg").visible = true
	video.play()
	movie_on = true; movie_boot = boot; movie_t = 0.0
	return true

func _movie_step(dt: float) -> void:
	movie_t += dt
	var skip := movie_t > 0.5 and (Input.is_key_pressed(KEY_ENTER) or Input.is_action_just_pressed("jump") or Input.is_joy_button_pressed(0, JOY_BUTTON_START))
	if skip or (movie_t > 0.5 and not video.is_playing()):
		video.stop(); video.visible = false; video.get_meta("bg").visible = false
		movie_on = false
		if movie_boot:
			movie_boot = false
			_start_game()
		elif native:
			ClassDB.class_call_static(core, "movie_done")

func _read_input() -> int:
	if not InputMap.has_action("special"): Opcoes.apply()
	var b := 0
	if Input.is_action_pressed("move_left"): b |= 1 << 15
	if Input.is_action_pressed("move_right"): b |= 1 << 13
	if Input.is_key_pressed(KEY_UP): b |= 1 << 12
	if Input.is_key_pressed(KEY_DOWN): b |= 1 << 14
	for jd in Input.get_connected_joypads():   # qualquer controle ligado (não só o 0)
		if Input.is_joy_button_pressed(jd, JOY_BUTTON_DPAD_UP): b |= 1 << 12
		if Input.is_joy_button_pressed(jd, JOY_BUTTON_DPAD_DOWN): b |= 1 << 14
		if Input.is_joy_button_pressed(jd, JOY_BUTTON_START): b |= 1 << 11
		if Input.is_joy_button_pressed(jd, JOY_BUTTON_BACK): b |= 1 << 8
		if Input.get_joy_axis(jd, JOY_AXIS_TRIGGER_LEFT) > 0.5: b |= 1 << 0
		if Input.get_joy_axis(jd, JOY_AXIS_TRIGGER_RIGHT) > 0.5: b |= 1 << 1
	if Input.is_action_pressed("weapon_prev"): b |= 1 << 2   # L1 (Opções)
	if Input.is_action_pressed("special"): b |= 1 << 4      # triângulo (Opções)
	if Input.is_action_pressed("jump"): b |= 1 << 6        # X (cruz) = pulo
	if Input.is_action_pressed("shoot"): b |= 1 << 7       # quadrado = tiro
	if Input.is_action_pressed("dash"): b |= 1 << 5        # círculo = dash
	if Input.is_key_pressed(KEY_ENTER): b |= 1 << 11       # start
	if Input.is_key_pressed(KEY_BACKSPACE): b |= 1 << 8    # select
	if Input.is_key_pressed(KEY_Q): b |= 1 << 0           # L2
	if Input.is_key_pressed(KEY_W): b |= 1 << 1           # R2
	if Input.is_action_pressed("weapon_next"): b |= 1 << 3   # R1 (Opções)
	return b

# ---- sons do X5/X6 tirados dos jogos (assets/sfx): o x4core avisa qual tocar (mem 34); cada som tem o seu
# canal, como uma voz do SPU (tocar de novo corta o anterior)
const FG_SFX := ["x5_shot", "x5_charge", "x5_semi", "x5_charged", "x5_fly", "x5_hover", "x5_falcon_giga", "x5_gaea_giga1",
	"x5_gaea_giga2", "x5_nova", "x6_shot", "x6_charge", "x6_semi", "x6_charged", "x6_dash", "x6_jump", "x6_grab",
	"x6_engetsurin", "x6_giga_dash", "x6_blade_giga", "x6_shadow_giga", "x6_hover",
	"vx_0", "vx_1", "vx_2", "vx_3", "vx_4", "vx_5", "vx_6", "vx_7", "vx_8", "vx_9", "vx_10", "vx_11",
	"vz_0", "vz_1", "vz_2", "vz_3", "vz_4", "vz_5", "vz_6", "vz_7", "vz_8", "vz_9", "vz_10", "vz_11"]
const FG_VOZ := 22   # a partir daqui são falas: todas no mesmo canal (uma voz do SPU), a nova corta a anterior
var sfx_players := {}
var sfx_meta := {}

var voz_player: AudioStreamPlayer
func _sfx_player(id: int) -> AudioStreamPlayer:
	if id >= FG_VOZ:
		if voz_player == null: voz_player = AudioStreamPlayer.new(); add_child(voz_player)
		voz_player.stream = _sfx_stream(id)
		return voz_player
	if sfx_players.has(id): return sfx_players[id]
	var p := AudioStreamPlayer.new()
	p.stream = _sfx_stream(id)
	add_child(p)
	sfx_players[id] = p
	return p

var sfx_streams := {}
func _sfx_stream(id: int) -> AudioStream:
	if sfx_streams.has(id): return sfx_streams[id]
	var nm: String = FG_SFX[id]
	if sfx_meta.is_empty() and FileAccess.file_exists("res://assets/sfx/meta.json"):
		sfx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sfx/meta.json"))
	var st = load("res://assets/sfx/%s.wav" % nm)
	if st is AudioStreamWAV:
		st = st.duplicate()
		var lp: int = int(sfx_meta.get(nm, {}).get("loop", -1))
		if lp >= 0:   # carga: repete do ponto de laço do SPU até soltar
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = lp; st.loop_end = int(sfx_meta[nm].len)
		else:
			st.loop_mode = AudioStreamWAV.LOOP_DISABLED
	sfx_streams[id] = st
	return st

func _sfx_poll() -> void:
	for i in 16:
		var v: int = ClassDB.class_call_static(core, "mem", 34, 0, 1)
		if v < 0 or v > 0xFFFF: break
		var id := v & 0xFF
		if id >= FG_SFX.size(): continue
		if v & 0x100:
			if sfx_players.has(id): sfx_players[id].stop()
			if OS.get_environment("SFXLOG") != "": print("para ", lf, " ", FG_SFX[id])
		else:
			_sfx_player(id).play()
			if OS.get_environment("SFXLOG") != "": print("som ", lf, " ", FG_SFX[id])

func step_frame(draw := true) -> void:
	var t0 := Time.get_ticks_usec()
	X4R.buttons = 0 if preload_mode else (_read_input() | forced)
	X4R.vsync_count += 1
	if hub_mode and native: _launch_step()
	if native:
		var bt: int = X4R.buttons
		if core != "X4Core": bt = ((bt >> 8) & 0xFF) | ((bt & 0xFF) << 8)
		ClassDB.class_call_static(core, "frame", bt)
		frame_us = Time.get_ticks_usec() - t0
		if core == "X4Core":
			_sfx_poll()
			if launch_phase == 2: _nz_step(); _coop_step()   # Nightmare Zero no X4 (o escurecer do Giga vale para as primitivas deste quadro); co-op
		if preload_mode and launch_phase == 1:   # preparando escondido: não precisa da imagem
			if ClassDB.class_call_static(core, "movie_request") >= 0: ClassDB.class_call_static(core, "movie_done")
			return
		stream = ClassDB.class_call_static(core, "prims")
		var mv: int = ClassDB.class_call_static(core, "movie_request")
		if mv >= 0 and (launch_phase == 1 or OS.get_environment("X4_SEM_VIDEO") != ""):
			ClassDB.class_call_static(core, "movie_done")   # preparando a fase: pula os vídeos
		elif mv >= 0 and not movie_on and not _play_movie(mv):
			ClassDB.class_call_static(core, "movie_done")
		if X4R.vsync_count % 30 == 0 and not hub_mode:
			for port in 2:
				var cd: PackedByteArray = ClassDB.class_call_static(core, "card_get", port)
				if not cd.is_empty():
					var fc := FileAccess.open("user://%s_cartao%d.mcr" % [game, port], FileAccess.WRITE)
					if fc: fc.store_buffer(cd); fc.close(); print("X4: jogo salvo no cartão ", port)
		if recomp and not preload_mode:
			_tela_update()
			if launch_phase == 2: _mix6_step(); _nz_step(); _bz_step(); _coop_step(); _rc_fade_step()
		var v: PackedByteArray = PackedByteArray() if recomp else ClassDB.class_call_static(core, "vram")
		if not v.is_empty():
			X4R.vram_draw = v
			X4R.vram_draw_dirty = true
	else:
		X4R.prims.clear()
		X4R.xa_tick()
		_gdscript_x4().c_godot_frame()
		frame_us = Time.get_ticks_usec() - t0
		stream = PackedInt32Array()
		for w: PackedInt32Array in X4R.prims:
			stream.append(w.size()); stream.append_array(w)
	if preload_mode: return
	if draw: _render()
	_perf(frame_us, Time.get_ticks_usec() - t0 - frame_us)

# ------------------------------------------------------------------ som (SPU + música XA lida do .bin do jogo)
var audio_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var bin: FileAccess

func _audio_init() -> void:
	var cands := [OS.get_environment("X4_BIN"),
		disc_file("x4"),
		ProjectSettings.globalize_path("res://").path_join("assets/x4.bin")]
	for c in cands:
		if c != "" and FileAccess.file_exists(c):
			bin = FileAccess.open(c, FileAccess.READ)
			if bin: print("X4: músicas de ", c); break
	if bin == null:
		print("X4: .bin do jogo não encontrado: sem músicas (efeitos sonoros funcionam)")
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 44100
	gen.buffer_length = 0.12
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = gen
	add_child(audio_player)
	audio_player.play()
	playback = audio_player.get_stream_playback()

func _audio_step() -> void:
	if playback == null: return
	if bin:
		for i in 96:
			var lba: int = ClassDB.class_call_static(core, "xa_need")
			if lba < 0: break
			bin.seek(lba * 2352)
			ClassDB.class_call_static(core, "xa_feed", bin.get_buffer(2352))
	var n := playback.get_frames_available()
	if recomp: n = mini(n, int(ClassDB.class_call_static(core, "audio_available")))
	if n > 0:
		var buf: PackedVector2Array = ClassDB.class_call_static(core, "audio", mini(n, 4096))
		playback.push_buffer(buf)

# um quadro do jogo por quadro da tela quando a tela é de ~60 Hz (sem tremedeira);
# em telas de outra frequência, acumula o tempo e roda no máximo 2 quadros de uma vez
var acc := 0.0
func _process(dt: float) -> void:
	if movie_on: _movie_step(dt)
	if not booted: return
	if preload_mode:
		# o preparo roda numa linha de execução separada, a toda velocidade (o hub continua liso)
		if pre_task < 0 and launch_phase == 1: pre_stop = false; pre_task = WorkerThreadPool.add_task(_preload_loop)
		if pre_task >= 0 and WorkerThreadPool.is_task_completed(pre_task):
			WorkerThreadPool.wait_for_task_completion(pre_task); pre_task = -1
		if launch_phase != 1 and pre_task < 0: preload_done = launch_phase == 2; set_process(false)
		return
	if launch_phase == 1:
		var t_end := Time.get_ticks_usec() + (80000 if recomp else 25000)   # tela de carregamento parada: pode cair de fps
		while launch_phase == 1 and Time.get_ticks_usec() < t_end:
			step_frame(false)
		if launch_phase != 1: _render()
		return
	if native: _audio_step()
	if absf(dt - 1.0 / 60.0) < 0.0035:
		acc = 0.0
		step_frame()
		return
	acc = minf(acc + dt, 3.0 / 60.0)
	var n := 0
	while acc >= 1.0 / 60.0 and n < 2:
		acc -= 1.0 / 60.0; n += 1
		step_frame(false)
	if n > 0:
		var t := Time.get_ticks_usec()
		_render()
		pf_draw += Time.get_ticks_usec() - t

# ------------------------------------------------------------------ medição (F3 mostra na tela)
var perf_label: Label
var pf_logic := 0; var pf_draw := 0; var pf_n := 0; var pf_slow := 0; var pf_worst := 0
var pf_t0 := 0
var pf_wl := 0; var pf_wd := 0
var pf_file: FileAccess

func _perf_init() -> void:
	var cl := CanvasLayer.new(); cl.layer = 100; add_child(cl)
	perf_label = Label.new(); perf_label.position = Vector2(60, 2); perf_label.visible = false
	perf_label.add_theme_font_size_override("font_size", 8)
	perf_label.add_theme_color_override("font_outline_color", Color.BLACK)
	perf_label.add_theme_constant_override("outline_size", 2)
	cl.add_child(perf_label)
	pf_file = FileAccess.open("res://x4_desempenho.txt", FileAccess.WRITE)
	if pf_file == null: pf_file = FileAccess.open("user://x4_desempenho.txt", FileAccess.WRITE)
	if pf_file: pf_file.store_line("CPU: %s  núcleos: %d  build: %s" % [OS.get_processor_name(), OS.get_processor_count(), "debug" if OS.is_debug_build() else "release"])
	pf_t0 = Time.get_ticks_msec()

# ---- hub: prepara a fase escolhida e volta ao hub quando a fase termina ----
func _launch_step() -> void:
	lf += 1
	if launch_phase == 1:
		if load_layer == null and not preload_mode: _show_loading(true)
		var bt := 0
		var st0 := 0
		if recomp:
			# recompilação: os vídeos tocam no jogo; Start em pulsos pula vídeos, título, menu e conversa até carregar
			st0 = int(ClassDB.class_call_static(core, "mem", PSX_ADDR[game].state, 0, 1))
			if game == "x6":
				# X6: Start em pulsos pula vídeos, título, menu (GAME START) e a conversa até carregar
				if lf > 60 and lf % 40 < 6 and st0 != 7 and st0 != 8: bt |= B_START
			elif st0 == 0:
				# X5: vídeos e título com Start; o cursor do menu fica em TRAINING (o Start confirma o treino)
				ClassDB.class_call_static(core, "mem", X5_MENU_CURSOR, 3, -1)
				if lf > 60 and lf % 40 < 6: bt |= B_START
			elif st0 == 1:
				# X5: escolha do personagem (seta para a direita = Zero), depois confirma
				if rc_sel_t < 0: rc_sel_t = lf
				var dt := lf - rc_sel_t
				if int(L.get("char", 0)) == 1 and dt >= 120 and dt < 126: bt |= 1 << 13
				if dt >= 200 and dt % 40 < 6: bt |= B_CROSS
		else:
			for st in PSX_SCRIPT.get(game, []):
				if lf >= st[0] and lf <= st[1]: bt |= st[2]
		# X6: o Zero vem do byte de jogador (0x800CCF08), que precisa estar certo desde o GAME START
		if game == "x6" and int(L.get("char", 0)) == 1 and (lf >= 1010 if not recomp else (st0 >= 19 or st0 == 7 or st0 == 8)):
			ClassDB.class_call_static(core, "mem", 0xCCF08, 1, -1)
		# X5: o Zero também vem do byte de jogador (0x800D1C44 = 1), garantido desde a escolha do personagem
		if game == "x5" and int(L.get("char", 0)) == 1 and recomp and st0 >= 1:
			ClassDB.class_call_static(core, "mem", 0xD1C44, 1, -1)
		# X5: a armadura do X precisa estar certa antes de carregar a fase (os gráficos/animações dela vêm junto)
		if game == "x5" and int(L.get("char", 0)) == 0 and (lf >= 1000 if not recomp else rc_sel_t >= 0):
			ClassDB.class_call_static(core, "mem", PSX_ADDR.x5.char, int(L.get("char_code", 0)), -1)
		# X5: Zero é escolhido na tela de personagem (seta para a direita antes de confirmar)
		if game == "x5" and int(L.get("char", 0)) == 1 and not recomp and lf >= 1150 and lf <= 1156: bt |= 1 << 13
		X4R.buttons = bt   # nada do jogador enquanto prepara
		var ad: Dictionary = PSX_ADDR[game]
		var state: int = ClassDB.class_call_static(core, "mem", ad.state, 0, 1)
		if OS.get_environment("HUBDBG") != "" and lf % 30 == 0: print("lf=", lf, " estado=", state, " fase=", ClassDB.class_call_static(core, "mem", ad.stage, 0, 2))
		if state == 7 or state == 8:   # carregando: troca a fase e o personagem/armadura
			ClassDB.class_call_static(core, "mem", ad.stage, int(L.get("stage", 1)), -2)
			if int(L.get("char", 0)) == 0 or game == "x5":
				ClassDB.class_call_static(core, "mem", ad.char, int(L.get("char_code", 0)), -1)
			for pk in L.get("pokes", []):   # [endereço, valor, tamanho]
				ClassDB.class_call_static(core, "mem", int(pk[0]), int(pk[1]), -int(pk[2]))
			for pk in L.get("save", {}).get("pokes", []):   # save único do fangame
				ClassDB.class_call_static(core, "mem", int(pk[0]), int(pk[1]), -int(pk[2]))
			# estado do "Now Loading" (as próximas entradas começam daqui). Depois de trocar fase e armadura:
			# na recompilação salvar anda 1 quadro, e o X6 já carrega a armadura nesse quadro
			if not snap_done: _snapshot_save()
		elif state == 10 and lf > 300:
			launch_phase = 2
			_stage_snap_save()
			_show_loading(false)
		elif lf > 6000:
			push_warning("hub: a fase não carregou")
			if preload_mode: launch_phase = 0   # (linha separada: o _process para sozinho)
			else: _back_to_hub()
		return
	# X6: a armadura precisa ser mantida no começo da fase (o jogo a recalcula ao entrar)
	if game != "x4" and lf_play < 400:
		lf_play += 1
		if lf_play == 300:
			blk_start = _blk_read()   # para achar onde o jogo guarda as cápsulas (capsulas_debug.txt)
			if FangameSave.PSX.has(game): parts0 = int(ClassDB.class_call_static(core, "mem", FangameSave.PSX[game].parts, 0, 2))
		if game == "x6" and int(L.get("char", 0)) == 0:
			ClassDB.class_call_static(core, "mem", PSX_ADDR.x6.char, int(L.get("char_code", 0)), -1)
		for pk in L.get("pokes", []):
			ClassDB.class_call_static(core, "mem", int(pk[0]), int(pk[1]), -int(pk[2]))
	if game != "x4" and L.has("save"):
		for ad in FangameSave.PSX[game].hp:
			if int(ClassDB.class_call_static(core, "mem", ad, 0, 1)) > 0x30: ClassDB.class_call_static(core, "mem", ad, 0x30, -1)
		var stc := int(L.save.get("st_cap", 0x20))   # sub tanks: a energia não passa da eficácia (X5/X6 guardam até 32)
		for ad in FangameSave.PSX[game].tanks:
			var tv := int(ClassDB.class_call_static(core, "mem", ad, 0, 1))
			if tv & 0x80 and (tv & 0x7F) > stc: ClassDB.class_call_static(core, "mem", ad, (tv & 0x80) | stc, -1)
		_wpn_step()
	if L.has("save") and seen_play: _hearts_step()
	# jogando: volta ao hub quando a fase acaba (vitória, fim de jogo ou saída)
	var st2 := 0
	var ok := []
	if game == "x4":
		# estados do X4 (decomp: func_800200D4): 7 arma nova, 9 menu SALVAR/CONTINUAR do X4, 10 Final Weapon passando para
		# a 2a parte (vídeo do Zero e carrega: a fase continua), 11 final do jogo
		st2 = ClassDB.class_call_static(core, "mem", 0, 0, 1); ok = [4, 5, 6, 10]
		if st2 == 6: seen_play = true
		if seen_play and st2 in [7, 9, 11]: won = true
		if seen_play and st2 == 9 and not preload_mode:   # fase terminada: o save é o do fangame, sem o menu de salvar do X4
			_back_to_hub(); return
	else:
		st2 = ClassDB.class_call_static(core, "mem", PSX_ADDR[game].state, 0, 1); ok = [7, 8, 9, 10]
		if st2 == 10: seen_play = true
		if seen_play and st2 == 12: won = true   # 12: fase concluída (chefe vencido)
		if game == "x6" and st2 == 10 and int(L.get("char", 0)) == 1: _zst6_step()   # desafios do Nightmare Zero
	out_frames = out_frames + 1 if (seen_play and not st2 in ok) else 0
	if out_frames > (240 if won else 180): _back_to_hub()

# ---- Nightmare Zero (X5 e X6, jogando de Zero): peças ganhas nos desafios do X6 (psx_embed.cpp nz_*) ----
# A recompilação faz as habilidades; aqui: a máscara das peças (x4_mem 0x1F900790), a barra do Pesadelo e o Frenesi no
# HUD, a vida travada na metade (Sobrecarga), o Zero roxo no modo Pesadelo, os ecos do sabre e os clones da Esquiva
# (atlas do Zero do jogo, assets/zero/x5 ou x6: o quadro do jogo +0x47 é o índice do atlas), com o atraso da tela (2 quadros).
# X5 e X6 têm o mesmo motor: mudam o objeto do Zero, a câmera e o estado do jogo (barra de vida no mesmo lugar).
var nz := 0                      # 0 não decidido, 1 ligado, -1 desligado
var nz_node: Node2D              # Zero roxo e corpos dos clones
var nz_add: Node2D               # arcos do sabre (ecos e clones), somados à tela
var nz_hud: Node2D
var nz_gg: Node2D                # Giga: o Zero (o jogo não desenha), o corte e a onda do Zero Nightmare (cores originais)
var nz_atl: SpriteAtlas
var nz_gg_atl: SpriteAtlas       # assets/zero/x6/giga: 0-20 corte, 21-24 onda (já em 3x, Scale3x)
var nz_fx: Node2D                # Giga: clarão branco (por cima de tudo)
var nz_tela_mat: ShaderMaterial  # Giga: o fundo roxo no lugar do preto da tela (fundo.png rolando)
var nz_hist := []                # [posição, quadro, virado, câmera, modo Pesadelo, objetos, visível (sem pausa)]
var nz_gg_cnt := [0, 0]          # Giga: quantos saíram, pedidos sem o modo Pesadelo (x4_mem 0x1F9007F8/F9)
var nz_gg_deny := 0              # quadros piscando a barra do Pesadelo (pediu o Giga fora do modo)
var nz_gg_bt := 0                # botões e modo Pesadelo do quadro anterior (registro do baixo + R2)
var nz_gg_mode := 0
var nz_st := []                  # [frenesi, máximo, barra, barra cheia, modo, duração, vida máxima, peças]
var nz_atl1: SpriteAtlas         # X4: 2º banco de quadros do Zero (parede, golpes no ar...)
var nz_dim := 0                  # X4: escurecer do Giga (0-31) nas primitivas do cenário (paleta da linha >= 483)
var nz_bg: Node2D                # X4: fundo roxo do Giga embaixo de tudo
var nz_bg_tex: Texture2D
func _nz_init() -> void:
	nz = -1
	var x4c := game == "x4" and core == "X4Core"
	if not x4c and (not recomp or not (game == "x6" or game == "x5")): return
	var mask := int(L.get("nz", 0)) if int(L.get("char", 0)) == 1 else 0
	ClassDB.class_call_static(core, "mem", 0x1F900790, mask, -1)
	if mask == 0: return
	# (X4: o atlas do Zero do X4 é igual ao do X5; quadros do 2º banco, parede etc., em assets/zero/bank1)
	nz_atl = SpriteAtlas.load_from("res://assets/zero" if x4c else "res://assets/zero/" + game)
	if x4c: nz_atl1 = SpriteAtlas.load_from("res://assets/zero/bank1")
	# cores do Nightmare Zero (as 4 peças) para o Zero que o Godot desenha no Giga (o X4 usa o atlas do X5: idêntico)
	nz_atl.load_variants([("res://assets/zero/x5" if x4c else "res://assets/zero/" + game) + "/atlas_nz.png"])
	nz_node = Node2D.new(); nz_node.z_index = 1; add_child(nz_node); nz_node.draw.connect(_nz_draw)
	nz_add = Node2D.new(); nz_add.z_index = 1; add_child(nz_add); nz_add.draw.connect(_nz_draw_add)
	# a cor passada no desenho vira a tinta: o brilho do quadro (Zero/arco do sabre) vira tons dela
	nz_node.material = _nz_tint_mat(false, 0.2, 1.05); nz_add.material = _nz_tint_mat(true, 0.3, 1.0)
	nz_hud = Node2D.new(); nz_hud.z_index = 3; add_child(nz_hud); nz_hud.draw.connect(_nz_hud_draw)
	if (mask & 0xF) == 0xF:   # Giga (as 4 peças)
		nz_gg_atl = SpriteAtlas.load_from("res://assets/zero/x6/giga")
		nz_gg = Node2D.new(); nz_gg.z_index = 1; add_child(nz_gg); nz_gg.draw.connect(_nz_draw_gg)
		move_child(nz_gg, nz_add.get_index())   # embaixo do brilho somado
		nz_fx = Node2D.new(); nz_fx.z_index = 5; add_child(nz_fx); nz_fx.draw.connect(_nz_draw_fx)
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform sampler2D bg_tex : repeat_enable, filter_nearest;\nuniform float on = 0.0;\nuniform float off = 0.0;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tif (on > 0.5 && max(c.r, max(c.g, c.b)) < 0.002) {\n\t\tvec2 px = UV * vec2(320.0, 240.0);\n\t\tc = texture(bg_tex, vec2((px.x - off) / 64.0, px.y / 240.0));\n\t}\n\tCOLOR = c;\n}\n"
		nz_tela_mat = ShaderMaterial.new(); nz_tela_mat.shader = sh
		nz_tela_mat.set_shader_parameter("bg_tex", SpriteAtlas._load_png("res://assets/zero/x6/giga/fundo.png"))
		if x4c:   # X4: o fundo roxo vai embaixo de tudo (o cenário some no preto: _nz_dim nas primitivas)
			nz_bg_tex = SpriteAtlas._load_png("res://assets/zero/x6/giga/fundo.png")
			nz_bg = Node2D.new(); nz_bg.z_index = -1; add_child(nz_bg); nz_bg.draw.connect(_nz_draw_bg)
	nz = 1
	print("%s: Nightmare Zero, peças %d" % [game.to_upper(), mask])

func _nz_step() -> void:
	if nz == 0: _nz_init()
	if nz != 1: return
	var m := func(a: int, n: int) -> int: return int(ClassDB.class_call_static(core, "mem", a, 0, n))
	var x4c := game == "x4"
	var x5 := game == "x5"
	var P := 0x9A0A0 if x5 else X6_P
	var cam: Vector2; var world: Vector2; var zf: int; var zflip: bool; var vis: bool; var mxhp: int; var is_z: bool
	if x4c:   # núcleo do X4: campos do jogo (51/52 posição, 11/12 quadro/lado desenhados, 0 estado, 30 vida máxima, 4 personagem)
		cam = Vector2(_s32(m.call(0x1F9007FC, 4)), _s32(m.call(0x1F9007FD, 4)))
		world = Vector2(_s16(m.call(51, 4) & 0xFFFF), _s16(m.call(52, 4) & 0xFFFF))
		zf = m.call(11, 4) + (1000 if m.call(0x1F9007FF, 4) else 0); zflip = m.call(12, 4) != 0
		vis = m.call(0, 1) == 6 and m.call(1, 1) != 2; mxhp = m.call(30, 1); is_z = m.call(4, 1) == 1
		if m.call(18, 1) == 0: zf = -1   # o Zero não foi desenhado neste quadro (piscando, Giga): sem o roxo do modo
		nz_dim = _s32(m.call(0x1F9007FE, 4))
	else:
		var bo: int = m.call(P + 0x14, 1); var cam_ad := (0x9A1F8 if x5 else 0x971F8) + bo * 0x54
		cam = Vector2(_s16(m.call(cam_ad + 0xA, 2)), _s16(m.call(cam_ad + 0xE, 2)))
		world = Vector2(_s16(m.call(P + 0xA, 2)), _s16(m.call(P + 0xE, 2)))
		var gst0: int = m.call(0xD1C00 if x5 else 0xCCED0, 2)   # byte 0: 10 jogando; byte 1: 2 = menu de pausa (some tudo)
		zf = m.call(P + 0x47, 1); zflip = (m.call(P + 0x15, 1) & 0x40) != 0
		vis = (gst0 & 0xFF) == 10 and (gst0 >> 8) != 2; mxhp = m.call(P + 0x5E, 1) & 0x7F; is_z = m.call(P + 2, 1) == 1
	var mode := _s32(m.call(0x1F900794, 4))
	var objs := []
	for i in mini(_s32(m.call(0x1F9007A0, 4)), 20):
		objs.append([_s32(m.call(0x1F9007A1 + i * 4, 4)), _s32(m.call(0x1F9007A2 + i * 4, 4)), _s32(m.call(0x1F9007A3 + i * 4, 4)), _s32(m.call(0x1F9007A4 + i * 4, 4))])
	nz_hist.append([world, zf, zflip, cam, mode, objs, vis,
		_s32(m.call(0x1F9007FA, 4)), _s32(m.call(0x1F9007FB, 4))])   # Giga: clarão | roxo | lado; quadro do Giga
	if nz_hist.size() > 4: nz_hist.pop_front()
	nz_st = [_s32(m.call(0x1F900791, 4)), _s32(m.call(0x1F900796, 4)), _s32(m.call(0x1F900792, 4)), _s32(m.call(0x1F900793, 4)),
		mode, _s32(m.call(0x1F900795, 4)), mxhp, _s32(m.call(0x1F900790, 4)), is_z]
	nz_node.queue_redraw(); nz_add.queue_redraw(); nz_hud.queue_redraw()
	if not x4c: _rc_sfx_poll()   # (X4: sons pela fila do núcleo, _sfx_poll)
	if nz_bg: nz_bg.queue_redraw()
	if nz_gg:
		nz_gg.queue_redraw(); nz_fx.queue_redraw()
		var ge := _nz_entry()
		var gfl: int = int(ge[7]) if ge.size() > 8 else 0
		if not x4c and tela and gfl & 0x100:
			if tela.material != nz_tela_mat: tela.material = nz_tela_mat
			var gdir := 1.0 if gfl & 0x200 else -1.0
			nz_tela_mat.set_shader_parameter("on", 1.0)
			nz_tela_mat.set_shader_parameter("off", fposmod(float(int(ge[8]) - 64) * 8.0 * gdir, 64.0))
		elif nz_tela_mat: nz_tela_mat.set_shader_parameter("on", 0.0)
		var bt: int = X4R.buttons
		if (bt & 0x4002) == 0x4002 and (bt & ~nz_gg_bt & 0x4002) != 0:
			print("NZ Giga: baixo + R2 (modo %d, barra %d/%d, ação %d)" % [nz_gg_mode, nz_st[2], nz_st[3], m.call(54, 1) if x4c else m.call(P + 5, 1)])
		elif (bt & ~nz_gg_bt & 2) != 0:
			print("NZ Giga: R2 sem baixo (botões %x)" % bt)
		nz_gg_bt = bt; nz_gg_mode = mode
		var cnt := [_s32(m.call(0x1F9007F8, 4)), _s32(m.call(0x1F9007F9, 4))]
		if cnt[0] > nz_gg_cnt[0]: print("NZ Giga: saiu o corte")
		if cnt[1] > nz_gg_cnt[1]:
			nz_gg_deny = 60
			print("NZ Giga: sem o modo Pesadelo (encha a barra roxa com golpes do sabre)")
		nz_gg_cnt = cnt
		if nz_gg_deny > 0 and vis: nz_gg_deny -= 1

# sons pedidos pela recompilação (Gigas e modo Pesadelo do Zero): fila x4_mem 0x1F900300 (fora do modo de mistura do X)
func _rc_sfx_poll() -> void:
	if mix6_gaea or mix6_giga_atl or x6s_on: return
	for i in 8:
		var v := int(ClassDB.class_call_static(core, "mem", 0x1F900300, 0, 4))
		if v < 0: break
		if v & 0x100:
			if sfx_players.has(v & 0xFF): sfx_players[v & 0xFF].stop()
		elif v < FG_SFX.size():
			_sfx_player(v).play()
			if OS.get_environment("SFXLOG") != "": print("som ", FG_SFX[v])

func _nz_tint_mat(add: bool, base: float, k: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\n%s\nvarying vec4 vcol;\nvoid vertex() { vcol = COLOR; }\nvoid fragment() {\n\tvec4 t = texture(TEXTURE, UV);\n\tfloat l = max(t.r, max(t.g, t.b));\n\tCOLOR = vec4(vcol.rgb * (%f + %f * l), t.a * vcol.a);\n}\n" % ["render_mode blend_add;" if add else "", base, k]
	var mat := ShaderMaterial.new(); mat.shader = sh
	return mat

func _s16(v: int) -> int:
	return v - 0x10000 if v > 0x7FFF else v

func _nz_entry() -> Array:
	if game == "x4": return nz_hist[nz_hist.size() - 1] if nz_hist.size() >= 1 else []   # (X4: a imagem é deste quadro)
	return nz_hist[nz_hist.size() - 3] if nz_hist.size() >= 3 else []

func _nz_draw() -> void:
	var e := _nz_entry()
	if e.is_empty() or nz_atl == null or not e[6]: return
	var cam: Vector2 = e[3]
	for o in e[5]:   # corpos dos clones: Zero escuro, roxo
		var fl: int = o[3]
		if ((fl >> 1) & 7) != 2 or not nz_atl.has_frame(o[2]): continue
		nz_atl.draw(nz_node, o[2], Vector2(o[0], o[1]) - cam, (fl & 1) != 0, Color(0.34, 0.11, 0.52, ((fl >> 8) & 0xFF) / 255.0))
	var za: SpriteAtlas = nz_atl1 if int(e[1]) >= 1000 and nz_atl1 else nz_atl
	var zfr: int = int(e[1]) % 1000
	var gg_on: bool = e.size() > 8 and int(e[8]) >= 0
	if e[4] > 0 and not gg_on and za.has_frame(zfr):   # modo Pesadelo: o Zero do jogo fica roxo, pulsando
		var a := 0.45 + 0.2 * sin(Engine.get_process_frames() * 0.45)
		za.draw(nz_node, zfr, (e[0] as Vector2) - cam, e[2], Color(0.6, 0.15, 0.95, a))

func _nz_draw_add() -> void:
	var e := _nz_entry()
	if e.is_empty() or nz_atl == null or not e[6]: return
	var cam: Vector2 = e[3]
	for o in e[5]:   # arcos do sabre: eco (1) e clone (3), brilho roxo; 7 = brilho da carga do Giga (o Zero somado)
		var fl: int = o[3]
		var kd := (fl >> 1) & 7
		var oa: SpriteAtlas = nz_atl1 if int(o[2]) >= 1000 and nz_atl1 else nz_atl   # (X4: quadro + 1000 = 2º banco)
		var of: int = int(o[2]) % 1000
		if (kd != 1 and kd != 3 and kd != 7) or not oa.has_frame(of): continue
		var a := ((fl >> 8) & 0xFF) / 255.0
		oa.draw(nz_add, of, Vector2(o[0], o[1]) - cam, (fl & 1) != 0, Color(0.75, 0.3, 1.0, a))

# Giga: o Zero do atlas do X6 (4), o corte (5) e a onda (6) do Zero Nightmare (atlas já em 2x), virados como o Zero
func _nz_draw_gg() -> void:
	var e := _nz_entry()
	if e.is_empty() or nz_atl == null or not e[6]: return
	var cam: Vector2 = e[3]
	for o in e[5]:
		var fl: int = o[3]
		var kd := (fl >> 1) & 7
		var pos := Vector2(o[0], o[1]) - cam
		var flip := (fl & 1) != 0
		if kd == 4 and nz_atl.has_frame(o[2]): nz_atl.draw(nz_gg, o[2], pos, flip, Color.WHITE, 1)   # (cores do Nightmare Zero)
		elif (kd == 5 or kd == 6) and nz_gg_atl != null: nz_gg_atl.draw(nz_gg, o[2], pos, flip)

# X4: as primitivas do jogo usam z 1..used; o Nightmare Zero vai por cima de tudo (como no X5/X6, por cima da tela)
func _nz_x4_z() -> void:
	for nd in [nz_node, nz_gg, nz_add]:
		if nd: (nd as Node2D).z_index = used + 1
	nz_hud.z_index = used + 2
	if nz_fx: nz_fx.z_index = used + 3

# X4: fundo roxo do Giga (fundo.png 64x240 rolando 8 px/quadro para o lado do Zero) embaixo das primitivas
func _nz_draw_bg() -> void:
	var e := _nz_entry()
	if e.size() < 9 or not e[6] or nz_bg_tex == null: return
	if nz_dim >= 31: nz_bg.draw_rect(Rect2(0, 0, 320, 240), Color.BLACK)   # cenário apagado: tela preta (como no X5/X6)
	var fl := int(e[7])
	if not (fl & 0x100): return
	var gdir := 1.0 if fl & 0x200 else -1.0
	var off := fposmod(float(int(e[8]) - 64) * 8.0 * gdir, 64.0)
	for k in range(-1, 6): nz_bg.draw_texture(nz_bg_tex, Vector2(off + k * 64.0, 0))

# Giga: clarão branco por cima de tudo (o fundo roxo entra no lugar do preto da tela: nz_tela_mat)
func _nz_draw_fx() -> void:
	var e := _nz_entry()
	if e.size() < 9 or not e[6]: return
	var a := (int(e[7]) & 0xFF) / 255.0
	if a > 0.0: nz_fx.draw_rect(Rect2(0, 0, 320, 240), Color(1, 1, 1, a))

# HUD: barra da vida do X5/X6 em x 22-24, 1 px por ponto de vida, de baixo (y 79) para cima (topo 80 - máximo);
# X4 em x 22-26, de y 78 para cima (topo 79 - máximo)
func _nz_hud_draw() -> void:
	var e := _nz_entry()
	if nz_st.size() < 9 or not nz_st[8] or e.is_empty() or not e[6]: return
	var mx: int = maxi(int(nz_st[6]), 1)
	# barra de vida: X5/X6 x 22-24 (3 px) com a base em 79; X4 x 22-26 (5 px) com a base em 78
	var bw := 5 if game == "x4" else 3
	var bot := 79 if game == "x4" else 80
	var nx := 29 if game == "x4" else 28   # (X4: entre a vida, borda em 28, e a barra da arma, borda em 34)
	var top := bot - mx
	var mask: int = nz_st[7]
	if mask & 2:
		# Sobrecarga: a metade de cima da barra fica travada (roxa escura)
		var cap := mx / 2
		nz_hud.draw_rect(Rect2(22, top, bw, mx - cap), Color(0.3, 0.05, 0.42, 0.9))
		for yy in range(top, top + mx - cap, 2): nz_hud.draw_rect(Rect2(22, yy, bw, 1), Color(0.14, 0.02, 0.2, 0.95))
		# barra do Pesadelo ao lado da vida
		nz_hud.draw_rect(Rect2(nx, top - 1, 5, mx + 2), Color(0.38, 0.38, 0.38))
		nz_hud.draw_rect(Rect2(nx + 1, top, 3, mx), Color(0.12, 0.04, 0.16))
		var mode: int = nz_st[4]
		var fill := 0.0
		var col := Color(0.62, 0.22, 0.95)
		if mode > 0:
			fill = float(mode) / maxf(1.0, float(nz_st[5]))
			col = Color(0.95, 0.35, 1.0).lerp(Color.WHITE, 0.25 + 0.25 * sin(Engine.get_process_frames() * 0.6))
		else:
			fill = float(nz_st[2]) / maxf(1.0, float(nz_st[3]))
		var h := roundi(clampf(fill, 0.0, 1.0) * mx)
		if h > 0: nz_hud.draw_rect(Rect2(nx + 1, bot - h, 3, h), col)
		if nz_gg_deny > 0 and (nz_gg_deny / 6) % 2 == 0:   # Giga pedido fora do modo Pesadelo: a moldura pisca
			nz_hud.draw_rect(Rect2(nx - 0.5, top - 1.5, 6, mx + 3), Color(1, 0.3, 0.45), false, 1.0)
	if mask & 1:
		# Frenesi: losangos acima da barra (acesos = bônus atual)
		var n: int = nz_st[1]
		for i in n:
			var c := Vector2(22.0 + bw / 2.0 + (i - (n - 1) / 2.0) * 6.0, top - 6)
			var on: bool = i < int(nz_st[0])
			var pts := PackedVector2Array([c + Vector2(0, -2.5), c + Vector2(2.5, 0), c + Vector2(0, 2.5), c + Vector2(-2.5, 0)])
			nz_hud.draw_colored_polygon(pts, Color(0.95, 0.35, 1.0) if on else Color(0.22, 0.08, 0.3))
			pts.append(pts[0]); nz_hud.draw_polyline(pts, Color(0.85, 0.7, 1.0, 0.9) if on else Color(0.45, 0.3, 0.55, 0.9), 1.0)

# ---- Black Zero (X5 e X6, jogando de Zero): peças ganhas nos desafios do X4 (psx_embed.cpp bz_*) ----
# A recompilação faz as habilidades e a cor (paletas do Zero na VRAM); aqui: a máscara (x4_mem 0x1F900800) e os
# desenhos, os mesmos do X4: onda do sabre, colunas negras, aura e impacto do Giga, e o Zero no salto/mergulho do Giga
# (o jogo não desenha: atlas do Zero do jogo com as cores do Black Zero, atlas_bz.png), com o atraso da tela (2 quadros).
var bz := 0                      # 0 não decidido, 1 ligado, -1 desligado
var bz_node: Node2D
var bz_atl: SpriteAtlas
var bz_hist := []                # [câmera, objetos, fase do Giga, idade do impacto, impacto (mundo), Zero (mundo), visível]
var bz_gg_cnt := [0, 0]
func _bz_init() -> void:
	bz = -1
	if not recomp or not (game == "x6" or game == "x5"): return
	var mask := int(L.get("bz", 0)) if int(L.get("char", 0)) == 1 else 0
	ClassDB.class_call_static(core, "mem", 0x1F900800, mask, -1)
	if mask == 0: return
	bz_atl = SpriteAtlas.load_from("res://assets/zero/" + game)
	bz_atl.load_variants(["res://assets/zero/%s/atlas_bz.png" % game])
	bz_node = Node2D.new(); bz_node.z_index = 1; add_child(bz_node); bz_node.draw.connect(_bz_rc_draw)
	if (mask & 0xF) == 0xF:   # Giga: aura e impacto por cima
		bz_fx_node = Node2D.new(); bz_fx_node.z_index = 2; add_child(bz_fx_node); bz_fx_node.draw.connect(_bz_fx_draw)
	bz = 1
	print("%s: Black Zero, peças %d" % [game.to_upper(), mask])

func _bz_step() -> void:
	if bz == 0: _bz_init()
	if bz != 1: return
	var m := func(a: int, n: int) -> int: return int(ClassDB.class_call_static(core, "mem", a, 0, n))
	var x5 := game == "x5"
	var P := 0x9A0A0 if x5 else X6_P
	var bo: int = m.call(P + 0x14, 1); var cam_ad := (0x9A1F8 if x5 else 0x971F8) + bo * 0x54
	var cam := Vector2(_s16(m.call(cam_ad + 0xA, 2)), _s16(m.call(cam_ad + 0xE, 2)))
	var objs := []
	for i in mini(_s32(m.call(0x1F90081F, 4)), 16):
		objs.append([_s32(m.call(0x1F900820 + i * 4, 4)), _s32(m.call(0x1F900821 + i * 4, 4)), _s32(m.call(0x1F900822 + i * 4, 4)), _s32(m.call(0x1F900823 + i * 4, 4))])
	var gst: int = m.call(0xD1C00 if x5 else 0xCCED0, 2)   # byte 0: 10 jogando; byte 1: 2 = menu de pausa
	bz_hist.append([cam, objs, _s32(m.call(0x1F900801, 4)), _s32(m.call(0x1F900802, 4)),
		Vector2(_s32(m.call(0x1F900803, 4)), _s32(m.call(0x1F900804, 4))), Vector2(_s16(m.call(P + 0xA, 2)), _s16(m.call(P + 0xE, 2))),
		(gst & 0xFF) == 10 and (gst >> 8) != 2])
	if bz_hist.size() > 4: bz_hist.pop_front()
	bz_node.queue_redraw()
	if nz != 1: _rc_sfx_poll()
	var e := _bz_entry()
	if bz_fx_node and not e.is_empty():
		var cam_e: Vector2 = e[0]
		var z: Vector2 = (e[5] as Vector2) - cam_e
		var im: Vector2 = (e[4] as Vector2) - cam_e
		bz_fx = [e[2], e[3], int(z.x), int(z.y), int(im.x), int(im.y)]
		bz_fx_node.visible = e[6] and (int(e[2]) > 0 or int(e[3]) >= 0)
		if bz_fx_node.visible: bz_fx_t += 1; bz_fx_node.queue_redraw()
	var cnt := [_s32(m.call(0x1F900805, 4)), _s32(m.call(0x1F900806, 4))]
	if cnt[0] > bz_gg_cnt[0]: print("BZ Giga: saiu")
	if cnt[1] > bz_gg_cnt[1]: print("BZ Giga: sem barra do Giga (precisa de 3/8 da barra)")
	bz_gg_cnt = cnt

func _bz_entry() -> Array:
	return bz_hist[bz_hist.size() - 3] if bz_hist.size() >= 3 else []

# X5/X6: o Zero no salto/mergulho do Giga (4: quadro do atlas, cores do Black Zero), a onda (5) e as colunas (6)
func _bz_rc_draw() -> void:
	var e := _bz_entry()
	if e.is_empty() or not e[6]: return
	var cam: Vector2 = e[0]
	for o in e[1]:
		var kind: int = o[2] >> 8
		var fr: int = o[2] & 0xFF
		var pos := Vector2(o[0], o[1]) - cam
		if kind == 4 and bz_atl and bz_atl.has_frame(fr): bz_atl.draw(bz_node, fr, pos, o[3] != 0, Color.WHITE, 1)
		elif kind == 5: _bz_wave_draw(bz_node, pos, fr, o[3] != 0)
		elif kind == 6: _bz_col_draw(bz_node, pos, fr)

# ---- desafios do Zero no X6 (Nightmare Zero): medidos na RAM do X6 (corpo do jogador em 0x800970A0) ----
# zst6: 0 quadros jogando, 1 golpes levados, 2 mortes, 3 sub tank usado, 4 quadros de dash, 5 itens de vida, 6 quadros de técnica,
#       7 vida no fim, 8 vida máxima
var zst6 := [0, 0, 0, 0, 0, 0, 0, 0, 0]
var z6_hp := -1; var z6_tank := -1; var z6_rise := false
func _zst6_step() -> void:
	var m := func(a: int, n: int) -> int: return int(ClassDB.class_call_static(core, "mem", a, 0, n))
	var hp: int = m.call(0x970FC, 1) & 0x7F
	var act: int = m.call(0x970A5, 1)
	var tank: int = (m.call(0xCCF33, 1) & 0x7F) + (m.call(0xCCF34, 1) & 0x7F)
	zst6[0] += 1
	if z6_hp >= 0:
		if hp < z6_hp:
			zst6[1] += 1
			if hp == 0: zst6[2] += 1
		var up := hp > z6_hp and tank == z6_tank and z6_hp > 0
		if up and not z6_rise: zst6[5] += 1   # vida subindo sem sub tank: item de vida (conta uma vez por enchida)
		z6_rise = up
	if z6_tank >= 0 and tank < z6_tank: zst6[3] += 1
	if act == 12 or act == 13: zst6[4] += 1
	if act >= 0x35 and act <= 0x4F: zst6[6] += 1
	zst6[7] = hp
	zst6[8] = maxi(zst6[8], hp)
	z6_hp = hp; z6_tank = tank

func _snap_key() -> String:
	if game == "x5" and int(L.get("char", 0)) == 0: return "x5_0_%d" % int(L.get("char_code", 0))   # cada armadura carrega a sua
	# X6 na recompilação: o jogo carrega a armadura no começo do "Now Loading" (estado salvo por armadura)
	if game == "x6" and recomp and int(L.get("char", 0)) == 0: return "x6_0_%d" % int(L.get("char_code", 0))
	return "%s_%d" % [game, int(L.get("char", 0))]

func _snap_path() -> String:
	return "user://estado_%s_v%d%s.bin" % [_snap_key(), SNAP_VERSION, disc_tag(game)]

func _snapshot_save() -> void:
	snap_done = true
	if snapshots.has(_snap_key()): return
	var st: PackedByteArray = ClassDB.class_call_static(core, "state_save")
	if st.is_empty(): return
	snapshots[_snap_key()] = {"lf": lf, "data": st}
	var f := FileAccess.open_compressed(_snap_path(), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f: f.store_32(lf); f.store_32(st.size()); f.store_buffer(st); f.close()
	print("hub: estado salvo (", _snap_key(), ", quadro ", lf, ")")

func _snapshot_restore() -> void:
	var k := _snap_key()
	if not snapshots.has(k) and FileAccess.file_exists(_snap_path()):
		var f := FileAccess.open_compressed(_snap_path(), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if f:
			var l := f.get_32(); var n := f.get_32()
			var d := f.get_buffer(n); f.close()
			if d.size() == n: snapshots[k] = {"lf": l, "data": d}
	if not snapshots.has(k): return
	var r: int = ClassDB.class_call_static(core, "state_load", snapshots[k].data)
	if r != 0:
		snapshots.erase(k); DirAccess.remove_absolute(ProjectSettings.globalize_path(_snap_path()))
		print("hub: estado salvo não serve (outra versão do núcleo); preparando do começo")
		ClassDB.class_call_static(core, "start", FileAccess.get_file_as_bytes("res://bin/openbios.bin"), _start_env())
		return
	lf = int(snapshots[k].lf)
	print("hub: começando do estado salvo (", k, ", quadro ", lf, ")")

# estado salvo com a fase já carregada (por jogo, fase, personagem e armadura): relançar é instantâneo
func _stage_snap_path() -> String:
	return stage_snap_file(L)

static func stage_snap_file(l: Dictionary) -> String:
	return "user://fase_%s_%d_%d_%d_%d_v%d%s_%s.bin" % [l.get("game", ""), int(l.get("stage", 1)), int(l.get("char", 0)),
		int(l.get("char_code", 0)), 1 if l.get("secret", false) else 0, SNAP_VERSION, disc_tag(str(l.get("game", ""))), l.get("save", {}).get("key", "")]

func _stage_snap_save() -> void:
	if FileAccess.file_exists(_stage_snap_path()): return
	# a mesma fase com o save antigo (outra vida máxima/armas) não serve mais: apaga
	var nm := _stage_snap_path().get_file()
	var pre := nm.substr(0, nm.rfind("_") + 1)
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with(pre) and f != nm: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))
	var st: PackedByteArray = ClassDB.class_call_static(core, "state_save")
	if st.is_empty(): return
	var f := FileAccess.open_compressed(_stage_snap_path(), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f: f.store_32(lf); f.store_32(st.size()); f.store_buffer(st); f.close()

func _stage_snap_restore() -> bool:
	if not FileAccess.file_exists(_stage_snap_path()): return false
	var f := FileAccess.open_compressed(_stage_snap_path(), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null: return false
	var l := f.get_32(); var n := f.get_32(); var d := f.get_buffer(n); f.close()
	if d.size() != n or int(ClassDB.class_call_static(core, "state_load", d)) != 0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_stage_snap_path()))
		ClassDB.class_call_static(core, "start", FileAccess.get_file_as_bytes("res://bin/openbios.bin"), _start_env())
		return false
	lf = l; launch_phase = 2; snap_done = true
	print("hub: fase pronta do estado salvo")
	return true

func _show_loading(on: bool) -> void:
	if on:
		load_layer = CanvasLayer.new(); load_layer.layer = 90; add_child(load_layer)
		var bg := ColorRect.new(); bg.color = Color.BLACK; bg.size = Vector2(320, 240); load_layer.add_child(bg)
		var ta := "res://assets/menus/loading/%s_a.png" % game
		if ResourceLoader.exists(ta):
			# a tela "Now Loading..." do próprio jogo (o texto pisca como no original)
			var tr := TextureRect.new(); tr.size = Vector2(320, 240); tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var tex_a: Texture2D = load(ta); var tex_b: Texture2D = load("res://assets/menus/loading/%s_b.png" % game)
			tr.texture = tex_a; load_layer.add_child(tr)
			var tm := Timer.new(); tm.wait_time = 0.5; tm.autostart = true; load_layer.add_child(tm)
			tm.timeout.connect(func() -> void: tr.texture = tex_b if tr.texture == tex_a else tex_a)
		else:
			var lb := Label.new(); lb.text = "Carregando a fase..."; lb.position = Vector2(0, 110); lb.size = Vector2(320, 20)
			lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lb.add_theme_font_size_override("font_size", 10)
			load_layer.add_child(lb)
	elif load_layer:
		load_layer.queue_free(); load_layer = null

# bloco de progresso do X5/X6: o que mudou durante a fase vai para user://capsulas_debug.txt
var blk_start := PackedByteArray()
var parts0 := -1
const BLK := {"x5": [0xD1C00, 0x100], "x6": [0xCCED0, 0x120]}
func _blk_read() -> PackedByteArray:
	var b := PackedByteArray()
	if not BLK.has(game): return b
	for i in BLK[game][1]: b.append(int(ClassDB.class_call_static(core, "mem", BLK[game][0] + i, 0, 1)))
	return b

func _blk_log(e: PackedByteArray) -> void:
	var txt := "%s fase %d venceu=%s:" % [game, int(L.get("stage", 0)), str(won)]
	for i in mini(e.size(), blk_start.size()):
		if e[i] != blk_start[i]: txt += " %X:%02X>%02X" % [BLK[game][0] + i, blk_start[i], e[i]]
	var f := FileAccess.open("user://capsulas_debug.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://capsulas_debug.txt") else FileAccess.WRITE)
	if f: f.seek_end(); f.store_line(txt); f.close()

# heart tanks (save único): cada um conta no save, mas a vida máxima só sobe a cada 3 (FangameSave.HEARTS_PER_UP).
# O jogo sobe a vida máxima 2 ao pegar um; aqui conta e volta para a vida que o total dá (e a vida atual não passa dela).
var hearts_got := 0
var hp_cap := -1
const HP_ATUAL := {"x5": 0x9A0FC, "x6": 0x970FC}   # vida do X (objeto do jogador +0x5C; bit 7 = levou golpe)

# X5/X6: voltando a uma fase já vencida o chefe aparece de novo (a fase fica fora da máscara de chefes), mas a arma
# dele precisa continuar: o jogo copia a máscara para o X (+0xC9, as armas disponíveis) ao entrar e ao renascer
func _wpn_step() -> void:
	var stg := int(L.get("stage", 0))
	if stg < 1 or stg > 8 or not stg in FangameSave.cur().progress.get(game, []): return
	var ad := int(FangameSave.PSX[game].wpn)
	var v := int(ClassDB.class_call_static(core, "mem", ad, 0, 1))
	var bit := 1 << (stg - 1)
	if v & bit == 0: ClassDB.class_call_static(core, "mem", ad, v | bit, -1)

func _hearts_step() -> void:
	if hp_cap < 0: hp_cap = int(L.save.get("hp", 0))
	var ads: Array = [30] if game == "x4" else FangameSave.PSX[game].hp
	var m := int(ClassDB.class_call_static(core, "mem", int(ads[0]), 0, 1))
	if m <= hp_cap: return
	hearts_got += maxi(1, (m - hp_cap) / 2)
	hp_cap = FangameSave.hp_for(int(L.save.get("hearts", 0)) + hearts_got)
	for ad in ads: ClassDB.class_call_static(core, "mem", int(ad), hp_cap, -1)
	var ha: int = 21 if game == "x4" else int(HP_ATUAL.get(game, -1))
	if ha < 0: return
	var v := int(ClassDB.class_call_static(core, "mem", ha, 0, 1)) & 0xFF
	if (v & 0x7F) > hp_cap: ClassDB.class_call_static(core, "mem", ha, (v & 0x80) | hp_cap, -1)
	print("heart tank: %d nesta fase, vida máxima %d" % [hearts_got, hp_cap])

func _back_to_hub() -> void:
	if Coop.on() and not preload_mode: Coop.me.send_event({"e": "saiu"})
	last_result = {"game": game, "stage": int(L.get("stage", 0)), "won": won, "char": int(L.get("char", 0))}
	if game == "x6" and int(L.get("char", 0)) == 1: last_result["zst6"] = zst6.duplicate()
	if game == "x4" and booted:   # números dos desafios do Zero (x4core fg_zero_track)
		var z := []
		for i in 10: z.append(int(ClassDB.class_call_static(core, "mem", 40 + i, 0, 1)))
		z.append(int(ClassDB.class_call_static(core, "mem", 63, 0, 1)))   # 10: melhor sequência de inimigos sem levar dano
		last_result["zst"] = z
	if L.has("save") and booted and (game == "x4" or lf_play > 0):
		last_result["save_start"] = L.save
		last_result["save_end"] = FangameSave.read_game(game, core)
		last_result["save_end"]["hearts_got"] = hearts_got
		if game != "x4" and not blk_start.is_empty(): _blk_log(_blk_read())
		if parts0 >= 0: last_result["save_end"]["parts0"] = parts0   # programas de armadura no começo da fase
	launch = {}
	hub_mode = false; launch_phase = 0
	set_process(false)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/hub.tscn")

func _unhandled_key_input(e: InputEvent) -> void:
	if hub_mode and not preload_mode and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		_back_to_hub(); return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F9 and game == "x4" and native:   # TESTE: posição do Zero/X na fase
		if pos_label == null:
			var cl := CanvasLayer.new(); cl.layer = 101; add_child(cl)
			pos_label = Label.new(); pos_label.position = Vector2(4, 200); pos_label.add_theme_font_size_override("font_size", 8)
			pos_label.add_theme_color_override("font_outline_color", Color.BLACK); pos_label.add_theme_constant_override("outline_size", 3)
			cl.add_child(pos_label)
		else: pos_label.visible = not pos_label.visible
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3 and perf_label:
		perf_label.visible = not perf_label.visible

var pos_label: Label
func _pos_update() -> void:
	if pos_label and pos_label.visible:
		pos_label.text = "fase %d.%d   x %d   y %d" % [ClassDB.class_call_static(core, "mem", 2, 0, 1), ClassDB.class_call_static(core, "mem", 3, 0, 1),
			ClassDB.class_call_static(core, "mem", 51, 0, 1), ClassDB.class_call_static(core, "mem", 52, 0, 1)]

func _perf(logic_us: int, draw_us: int) -> void:
	pf_logic += logic_us; pf_draw += draw_us; pf_n += 1
	if logic_us + draw_us > 16000: pf_slow += 1
	pf_worst = maxi(pf_worst, logic_us + draw_us)
	pf_wl = maxi(pf_wl, logic_us); pf_wd = maxi(pf_wd, draw_us)
	if pf_n < 60: return
	var real := (Time.get_ticks_msec() - pf_t0) / 1000.0
	var txt := "jogo %.1fms  desenho %.1fms  pior %.1fms (jogo %.0f / desenho %.0f)  lentos %d/60  %.0f quadros/s  fps %d" % [pf_logic / 60000.0, pf_draw / 60000.0, pf_worst / 1000.0, pf_wl / 1000.0, pf_wd / 1000.0, pf_slow, 60.0 / real, Engine.get_frames_per_second()]
	perf_label.text = txt
	if pf_file: pf_file.store_line(txt); pf_file.flush()
	pf_logic = 0; pf_draw = 0; pf_n = 0; pf_slow = 0; pf_worst = 0; pf_wl = 0; pf_wd = 0; pf_t0 = Time.get_ticks_msec()

# ------------------------------------------------------------------ desenho
var tpx := 0; var tpy := 0; var tdepth := 0; var tabr := 0
var V := PackedVector2Array(); var U := PackedVector2Array(); var C := PackedColorArray()
var C0 := PackedFloat32Array(); var I := PackedInt32Array()

func _render() -> void:
	var tu := Time.get_ticks_usec()
	if X4R.vram_draw_dirty and X4R.vram_draw.size() > 0:
		up_n += 1
		vram_img.set_data(1024, 512, false, Image.FORMAT_RG8, X4R.vram_draw)
		vram_k = 1 - vram_k
		vram_tex = vram_texs[vram_k]
		vram_tex.update(vram_img)
		for k in mats: (mats[k] as ShaderMaterial).set_shader_parameter("vram", vram_tex)
		X4R.vram_draw_dirty = false
	up_us += Time.get_ticks_usec() - tu
	used = 0
	var run_mode := -2
	_clear()
	_skin_prepare()
	var px := PackedInt32Array(); px.resize(4)
	var py := PackedInt32Array(); py.resize(4)
	var pu := PackedInt32Array(); pu.resize(4)
	var pv := PackedInt32Array(); pv.resize(4)
	var pc := PackedInt32Array(); pc.resize(4)
	var w := stream
	var ip := 0
	var total := w.size()
	while ip < total:
		var ws: int = w[ip]
		var o := ip + 1
		ip += ws + 1
		if ws <= 0 or ip > total:
			break
		var w0: int = w[o]
		var cmd: int = (w0 >> 24) & 0xFF
		if cmd == 0xE1:
			tpx = (w0 & 15) * 64; tpy = ((w0 >> 4) & 1) * 256
			tabr = (w0 >> 5) & 3; tdepth = (w0 >> 7) & 3
			continue
		var n := 0
		var absolute := false
		var tex := (cmd & 4) != 0
		var pgx := tpx; var pgy := tpy; var dep := tdepth; var abr := tabr
		var clut := 0
		if cmd >= 0x20 and cmd < 0x40:
			var gour := (cmd & 0x10) != 0
			n = 4 if (cmd & 8) != 0 else 3
			var i := 1
			var c := w0 & 0xFFFFFF
			for k in n:
				if k > 0 and gour:
					if i >= ws: n = 0; break
					c = w[o + i] & 0xFFFFFF; i += 1
				if i >= ws: n = 0; break
				var xy: int = w[o + i]; i += 1
				var x := xy & 0x7FF; var y := (xy >> 16) & 0x7FF
				if x >= 0x400: x -= 0x800
				if y >= 0x400: y -= 0x800
				px[k] = x; py[k] = y; pc[k] = c
				if tex:
					if i >= ws: n = 0; break
					var uvw: int = w[o + i]; i += 1
					pu[k] = uvw & 0xFF; pv[k] = (uvw >> 8) & 0xFF
					if k == 0: clut = (uvw >> 16) & 0xFFFF
					elif k == 1:
						var page := (uvw >> 16) & 0xFFFF
						pgx = (page & 15) * 64; pgy = ((page >> 4) & 1) * 256
						dep = (page >> 7) & 3; abr = (page >> 5) & 3
				else:
					pu[k] = 0; pv[k] = 0
		elif cmd >= 0x60 and cmd < 0x80:
			if ws < 2: continue
			var xy: int = w[o + 1]
			var x := xy & 0x7FF; var y := (xy >> 16) & 0x7FF
			if x >= 0x400: x -= 0x800
			if y >= 0x400: y -= 0x800
			var u0 := 0; var v0 := 0; var i2 := 2
			if tex:
				if ws < 3: continue
				u0 = w[o + 2] & 0xFF; v0 = (w[o + 2] >> 8) & 0xFF; clut = (w[o + 2] >> 16) & 0xFFFF; i2 = 3
			var ww := 1; var hh := 1
			match (cmd >> 3) & 3:
				0:
					if i2 >= ws: continue
					ww = w[o + i2] & 0xFFFF; hh = (w[o + i2] >> 16) & 0xFFFF
				2: ww = 8; hh = 8
				3: ww = 16; hh = 16
			n = 4
			px[0] = x; py[0] = y; px[1] = x + ww; py[1] = y; px[2] = x; py[2] = y + hh; px[3] = x + ww; py[3] = y + hh
			pu[0] = u0; pv[0] = v0; pu[1] = u0 + ww; pv[1] = v0; pu[2] = u0; pv[2] = v0 + hh; pu[3] = u0 + ww; pv[3] = v0 + hh
			var c2 := w0 & 0xFFFFFF
			pc[0] = c2; pc[1] = c2; pc[2] = c2; pc[3] = c2
		elif cmd == 0x02:
			if ws < 3: continue
			var ww3: int = ((w[o + 2] & 0x3FF) + 15) & ~15; var hh3: int = (w[o + 2] >> 16) & 0x1FF
			n = 4; tex = false
			px[0] = 0; py[0] = 0; px[1] = ww3; py[1] = 0; px[2] = 0; py[2] = hh3; px[3] = ww3; py[3] = hh3
			var c3 := w0 & 0xFFFFFF
			for k in 4: pu[k] = 0; pv[k] = 0; pc[k] = c3
			cmd = 0x60
		elif cmd == 0xF1:   # tamanho da tela do jogo (núcleo de PS1)
			if ws >= 2:
				var sw: int = w[o + 1] & 0xFFFF; var sh: int = (w[o + 1] >> 16) & 0xFFFF
				if sw > 0 and sh > 0: scale = Vector2(320.0 / sw, 240.0 / sh)
			continue
		elif cmd == 0xF0:   # tela direto da VRAM (núcleo de PS1: vídeos e imagens sem desenho)
			if ws < 3: continue
			var dw: int = w[o + 2] & 0xFFFF; var dh: int = (w[o + 2] >> 16) & 0xFFFF
			pgx = w[o + 1] & 0x3FF; pgy = (w[o + 1] >> 16) & 0x1FF
			dep = 3 if (w0 & 1) else 2
			n = 4; tex = true; absolute = true
			px[0] = 0; py[0] = 0; px[1] = 320; py[1] = 0; px[2] = 0; py[2] = 240; px[3] = 320; py[3] = 240
			pu[0] = 0; pv[0] = 0; pu[1] = dw; pv[1] = 0; pu[2] = 0; pv[2] = dh; pu[3] = dw; pv[3] = dh
			for k in 4: pc[k] = 0x808080
			cmd = 0x65
		else:
			continue
		if n == 0: continue
		if skin_on and tex and pgx == 320 and pgy == 0 and (clut == 0x7800 or ((clut == 0x7843 or clut == 0x7844) and absf(px[0] - skin_pos.x) < 64 and absf(py[0] - skin_pos.y) < 64)):
			# sprite do X (tiles do jogador na VRAM 320,0 com a paleta do jogador): a armadura nova é desenhada no lugar
			if not skin_placed:
				if V.size() > 0: _flush(run_mode)
				run_mode = -2
				var ph := _inst(); ph.visible = false   # ocupa uma posição na ordem de desenho
				skin_group.z_index = used; skin_node.visible = true; skin_placed = true
				skin_node.queue_redraw()
			continue
		if hab_prot and tex and pgx == 320 and pgy == 0 and clut == 0x7800 and Engine.get_process_frames() % 2 == 0:
			continue   # dash translúcido num quadro que as peças não têm (fica o X original do X4): ele pisca
		var raw_tex := (cmd & 1) != 0
		var shade := 1.0
		if nz_dim > 0 and tex and not absolute and ((clut >> 6) & 511) >= 483:   # Giga do Nightmare Zero: o cenário escurece
			if nz_dim >= 31: continue
			shade = 1.0 - nz_dim * 4.0 / 128.0
			if raw_tex:
				raw_tex = false
				for k in n: pc[k] = 0x808080
		var semi := (cmd & 2) != 0
		var mode := abr if semi else -1
		if mode != run_mode and V.size() > 0:
			_flush(run_mode)
		run_mode = mode
		# bandeiras no alfa da cor: profundidade | texturizado<<2 | cru<<3 | semi<<4
		var fl := dep | (4 if tex and not absolute else 0) | (8 if raw_tex else 0) | (16 if semi else 0) | (32 if absolute else 0)
		var fa := fl / 255.0
		var base := V.size()
		var cx := float(clut & 63) * 16.0; var cy := float((clut >> 6) & 511)
		for k in n:
			V.append(Vector2(px[k], py[k])); U.append(Vector2(pu[k], pv[k]))
			var cc: int = pc[k]
			C.append(Color((cc & 0xFF) / 255.0 * shade, ((cc >> 8) & 0xFF) / 255.0 * shade, ((cc >> 16) & 0xFF) / 255.0 * shade, fa))
			C0.append(pgx); C0.append(pgy); C0.append(cx); C0.append(cy)
		I.append(base); I.append(base + 1); I.append(base + 2)
		if n == 4:
			I.append(base + 1); I.append(base + 3); I.append(base + 2)
	if V.size() > 0:
		_flush(run_mode)
	for i in range(used, pool.size()):
		pool[i].visible = false
	if skin_node and not skin_placed: skin_node.visible = false
	_fg_fx_update()
	_hab_x4_update()
	_pos_update()
	if nz == 1 and game == "x4": _nz_x4_z()
	if coop_node and game == "x4": coop_node.z_index = used + 5

# ---- armadura de outro jogo no X do X4 (fusão): desenha as peças por cima da posição do X ----
var skin := ""                 # armadura completa, ex.: "Falcon_X5" ("" = montada ou X original)
var parts := {}                # peça -> pasta dos sprites ("" = sem armadura); vazio = sprites do próprio X4
var skin_on := false
const SKIN_FALLBACK := {17: 19, 75: 71, 76: 72}   # andar (17) e dash (75/76, 3º quadro do X4) -> quadro parecido que o X6 tem
var skin_placed := false
var skin_node: Node2D
var skin_group: CanvasGroup
var skin_atl := {}             # "body" e as peças da armadura
var skin_map := {}             # quadro do X4 -> quadro canônico
var skin_f := -1; var skin_flip := false; var skin_pos := Vector2.ZERO; var skin_fly := -1; var skin_fx := -1
const SKIN_PARTS := ["legs", "body", "arms", "helmet"]
# armadura -> [peças do X4 (1 capacete, 2 corpo/Nova Strike, 4 braço/tiro carregado, 8 pernas/dash no ar), código no x4core]
const SKIN_INFO := {"Falcon_X5": [4, 1], "Gaea_X5": [0, 2], "Fourth_X5": [14, 3], "Ultimate_X5": [14, 4],
	"Falcon_X6": [12, 5], "Blade_X6": [12, 6], "Shadow_X6": [7, 7], "Ultimate_X6": [15, 8]}

var atl_cache := {}
func _atl(sk: String, nm: String) -> SpriteAtlas:   # atlas de uma armadura (null se não existe)
	sk = FangameParts.asset(sk)
	var key := sk + "/" + nm
	if not atl_cache.has(key):
		var d := "res://assets/x/parts/%s/%s" % [sk, nm]
		var a: SpriteAtlas = null
		if sk != "" and FileAccess.file_exists(d + "/frames.json"):
			a = SpriteAtlas.load_from(d)
			if nm in SKIN_PARTS or nm == "flight": a.load_variants([1, 2, 3].map(func(n): return "%s/atlas_c%d.png" % [d, n]))
		atl_cache[key] = a
	return atl_cache[key]

func _src_skin(p: String) -> String:   # armadura de uma peça
	return str(parts.get(p, ""))

func _skin_load() -> void:
	# o X sem armadura; as cores do X piscando (carga) vêm da armadura do braço (ou de outra peça que tenha)
	skin_atl["base"] = SpriteAtlas.load_from("res://assets/x/parts/body")
	var bs := ""
	for p in ["arms", "body", "helmet", "legs"]:
		var s0 := FangameParts.asset(_src_skin(p))
		if s0 != "" and FileAccess.file_exists("res://assets/x/parts/%s/base_c1.png" % s0): bs = s0; break
	skin_atl["base"].load_variants([1, 2, 3].map(func(n): return "res://assets/x/parts/%s/base_c%d.png" % [bs, n]))
	for p in SKIN_PARTS:
		var a := _atl(_src_skin(p), p)
		if a: skin_atl[p] = a
	var cj = JSON.parse_string(FileAccess.get_file_as_string("res://assets/x/parts/canonical.json"))
	for k in cj["game_to_canonical"]["x4"]: skin_map[int(k)] = int(cj["game_to_canonical"]["x4"][k])
	# dentro de um CanvasGroup: no dash translúcido o X inteiro fica meio transparente por igual (sem ver as peças umas
	# através das outras)
	skin_group = CanvasGroup.new(); add_child(skin_group)
	skin_node = Node2D.new(); skin_node.visible = false; skin_group.add_child(skin_node)
	skin_node.draw.connect(_skin_draw)
	# efeitos do jogo original: anel da carga, tiro carregado e raios do Giga (vêm da armadura do braço)
	for nm in ["charge_release", "shot", "giga_laser", "giga_fx", "plasma", "charge_fx"]:
		var a := _atl(skin if skin != "" else _src_skin("arms"), nm)
		if a: skin_atl[nm] = a
	# shurikens da Shadow (x4core tipo 7): tiro do braço Shadow ou os 3 jogados do teto pelas pernas Shadow, com qualquer braço
	if "Shadow_X6" in [skin, FangameParts.asset(_src_skin("legs")), FangameParts.asset(_src_skin("arms"))]:
		var ka := _atl("Shadow_X6", "shot")
		if ka: skin_atl["kunai"] = ka
	_skin_special()
	fg_node = Node2D.new(); fg_node.visible = false; add_child(fg_node)
	fg_node.draw.connect(_fg_draw)

# quadros especiais tirados do jogo original (voo da Falcon, Engetsurin, Nova...): de qual peça vêm (x4core mem 35)
var skin_sp_src := -1
var skin_fly_skin := ""
var fly_match := {}   # quadro do voo -> [pose do X, dx, dy, nota] (para vestir as peças de outras armaduras)
var skin_fly_mix := false
var skin_fly_prev := -1
var skin_white := 0
var swap_player: AudioStreamPlayer
func _swap_sound(on: bool) -> void:   # som da troca de armadura: teletransporte do X4 (chegada ao vestir o golpe, saída ao voltar)
	# gravados do próprio X4 (assets/sfx/fg_tele_in/out.wav); tocados aqui num canal próprio para o jogo não cortar
	if swap_player == null:
		swap_player = AudioStreamPlayer.new(); add_child(swap_player)
	var st := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://assets/sfx/fg_tele_%s.wav" % ("in" if on else "out")))
	if st: swap_player.stream = st; swap_player.play()
const SKIN_WIPE := 10   # quadros da animação de troca de armadura
var skin_fly_off := Vector2.ZERO
func _skin_special(src := 0) -> void:
	if src == skin_sp_src: return
	skin_sp_src = src
	var sk := skin if skin != "" else _src_skin(["legs", "arms", "body"][clampi(src, 0, 2)])
	skin_atl.erase("flight"); skin_atl.erase("flight_fx")
	var a := _atl(sk, "flight")
	if a: skin_atl["flight"] = a
	skin_fly_skin = FangameParts.asset(sk)
	skin_atl.erase("flight_trail")
	a = _atl(sk, "flight_trail")
	if a: skin_atl["flight_trail"] = a
	var mp := "res://assets/x/parts/%s/flight/match.json" % skin_fly_skin
	var mj = JSON.parse_string(FileAccess.get_file_as_string(mp)) if FileAccess.file_exists(mp) else null
	fly_match = mj if mj is Dictionary else {}
	a = _atl(sk, "flight_fx")
	if a: skin_atl["flight_fx"] = a

# cápsula do X4 pega no meio da fase, num lugar sem armadura: a peça aparece na hora
func _caps_poll() -> void:
	if game != "x4" or not native or not hub_mode: return
	var w := (int(ClassDB.class_call_static(core, "mem", 36, 0, 1)) >> 8) & 0xFF
	if w == caps_worn: return
	var novo := w & ~caps_worn
	caps_worn = w
	if parts.is_empty(): return   # sprites do próprio X4: o jogo já desenha a peça
	for p in SKIN_PARTS:
		if novo & FangameParts.X4_CAP[p] or (p == "arms" and novo & FangameParts.X4_CAP_PLASMA):
			parts[p] = "Fourth_X4"
			var a := _atl("Fourth_X4", p)
			if a: skin_atl[p] = a
var caps_worn := 0
var skin_bare := false

var skin_pf := {}   # quadro de cada peça (quando uma peça usa outro quadro que as demais)
var skin_pd := {}   # deslocamento dessa peça
var hover_x6 := {}

func _fr_ctr(a: SpriteAtlas, i: int) -> Vector2:
	var fr: Dictionary = a.frames[i]
	return Vector2(float(fr["w"]) / 2.0 - float(fr["ox"]), float(fr["h"]) / 2.0 - float(fr["oy"]))

func _part_ok(p: String, c: int) -> bool:   # a peça vestida tem o quadro c de verdade
	if not skin_atl.has(p): return true
	if not skin_atl[p].has_frame(c): return false
	# o X6 não tem Hover: os quadros 202-221 das armaduras do X6 são só cópias recoloridas do X5 (ficam erradas)
	if c >= 202 and c <= 221 and FangameParts.asset(_src_skin(p)).ends_with("_X6"): return false
	return true

func _mixed_parts() -> bool:   # peças de mais de uma armadura (ou alguma sem armadura)
	var a := FangameParts.asset(_src_skin("legs"))
	for p in SKIN_PARTS:
		if FangameParts.asset(_src_skin(p)) != a: return true
	return a == ""

func _skin_all(c: int) -> bool:   # todas as peças vestidas (e o X por baixo) têm o quadro c
	if c < 0 or not skin_atl["base"].has_frame(c): return false
	for p in SKIN_PARTS:
		if not _part_ok(p, c): return false
	return true

func _skin_prepare() -> void:
	skin_on = false; skin_placed = false
	if fg_node == null and game == "x4" and native and (int(L.get("bz", 0)) & 0x40 or int(L.get("bz", 0)) & 0xF == 0xF):   # Black Zero: onda do sabre / Giga
		fg_node = Node2D.new(); fg_node.visible = false; add_child(fg_node)
		fg_node.draw.connect(_fg_draw)
	if bz_fx_node == null and game == "x4" and native and int(L.get("bz", 0)) & 0xF == 0xF:   # aura e impacto do Giga
		bz_fx_node = Node2D.new(); add_child(bz_fx_node)
		bz_fx_node.draw.connect(_bz_fx_draw)
	if bz_fx_node and game == "x4":   # (X5/X6: _bz_step)
		bz_fx = []
		for i in 6:
			var v: int = ClassDB.class_call_static(core, "mem", 56 + i, 0, 1)
			if v > 0x7FFFFFFF: v -= 0x100000000
			bz_fx.append(v)
		bz_fx_node.visible = bz_fx[0] > 0 or bz_fx[1] >= 0
		if bz_fx_node.visible: bz_fx_t += 1; bz_fx_node.queue_redraw()
	if parts.is_empty() or game != "x4" or not native: return
	if skin_node == null: _skin_load()
	_caps_poll()
	if int(ClassDB.class_call_static(core, "mem", 4, 0, 1)) != 0: return   # só o X
	if int(ClassDB.class_call_static(core, "mem", 18, 0, 1)) == 0: return   # o X não foi desenhado neste quadro
	var f: int = ClassDB.class_call_static(core, "mem", 11, 0, 1)
	skin_fly = -1
	var fly: int = ClassDB.class_call_static(core, "mem", 19, 0, 1)
	if fly >= 0: _skin_special(int(ClassDB.class_call_static(core, "mem", 35, 0, 1)))
	if fly >= 0 and skin_atl.has("flight") and skin_atl["flight"].has_frame(fly): skin_fly = fly
	skin_fx = int(ClassDB.class_call_static(core, "mem", 20, 0, 1)) if skin_fly >= 0 else -1
	var c: int = skin_map.get(f, -1)
	if skin_fly >= 0: c = 0
	skin_fly_mix = false
	# troca peças misturadas <-> armadura inteira do golpe: clarão branco rápido
	var was_fly := skin_fly_prev >= 0
	if (skin_fly >= 0) != was_fly and _mixed_parts():
		skin_white = SKIN_WIPE
		_swap_sound(skin_fly >= 0)
	skin_fly_prev = skin_fly
	if skin_white > 0: skin_white -= 1
	if skin_fly >= 0 and skin_atl.has("flight_trail"):
		# voo/dash com peças de outras armaduras: o X vai numa pose parecida com as peças vestidas
		# e do quadro original ficam só os efeitos (jato, rastro)
		var mixed := false
		for p in SKIN_PARTS:
			if FangameParts.asset(_src_skin(p)) != skin_fly_skin: mixed = true
		var e: Array = fly_match.get(str(skin_fly), [])
		if false and mixed and e.size() >= 4 and e[0] != null and float(e[3]) >= 0.05 and _skin_all(int(e[0])):   # (desligado: golpe especial mostra a armadura do golpe inteira)
			skin_fly_mix = true; c = int(e[0]); skin_fly_off = Vector2(e[1], e[2])
	if c < 0: return
	# quadros do X4 que as peças do X6 não têm (o X6 tem menos quadros no andar e no dash): o X inteiro usa o quadro
	# parecido (senão aparecia o X original do X4 nesses quadros)
	if SKIN_FALLBACK.has(c) and not _skin_all(c) and _skin_all(SKIN_FALLBACK[c]): c = SKIN_FALLBACK[c]
	# chegada na fase (120-136): raio e o X se formando só com o X por baixo; nos quadros em que a armadura
	# aparece (132-136), as peças entram se todas tiverem esse quadro de verdade. Sem o pisca da carga.
	var arrive := c >= 120 and c <= 136
	skin_bare = arrive and (c <= 131 or not _skin_all(c))
	skin_pf.clear(); skin_pd.clear()
	if not skin_bare and not _skin_all(c):
		if c < 202 or c > 221 or not skin_atl["base"].has_frame(c): return   # (outros quadros sem armadura): fica o original
		# Hover com peça do X6 (o X6 não tem Hover, não há desenho): a peça usa o quadro dela de pose mais
		# parecida, no lugar certo (tabela assets/x/parts/hover_x6.json, feita comparando as silhuetas da Fourth do X5)
		if hover_x6.is_empty():
			var hj = JSON.parse_string(FileAccess.get_file_as_string("res://assets/x/parts/hover_x6.json"))
			hover_x6 = hj if hj is Dictionary else {"_": 1}
		for p in SKIN_PARTS:
			if _part_ok(p, c): continue
			var e: Array = hover_x6.get(p, {}).get(str(c), [])
			if e.size() < 3 or not _part_ok(p, int(e[0])): return
			skin_pf[p] = int(e[0]); skin_pd[p] = Vector2(e[1], e[2])
	if skin_bare and not skin_atl["base"].has_frame(c): return
	skin_f = c
	skin_flip = int(ClassDB.class_call_static(core, "mem", 12, 0, 1)) != 0   # os sprites originais olham para a esquerda
	var sx: int = ClassDB.class_call_static(core, "mem", 13, 0, 1)
	var sy: int = ClassDB.class_call_static(core, "mem", 14, 0, 1)
	if sx > 32767: sx -= 65536
	if sy > 32767: sy -= 65536
	skin_pos = Vector2(sx, sy)
	skin_flash = 0 if arrive else int(ClassDB.class_call_static(core, "mem", 27, 0, 1))
	skin_on = true

var fg_node: Node2D
var fg_rel := -1; var fg_rel_pos := Vector2.ZERO; var fg_rel_flip := false
var fg_objs := []
var fg_giga := -1
var fg_cfx := -1

func _fg_fx_update() -> void:
	if fg_node == null: return
	fg_objs.clear()
	fg_rel = int(ClassDB.class_call_static(core, "mem", 23, 0, 1))
	if skin_on: fg_rel_pos = skin_pos; fg_rel_flip = skin_flip
	var n: int = ClassDB.class_call_static(core, "mem", 24, 0, 1)
	for i in mini(n, 16):
		var o := []
		for k in 4:
			var v: int = ClassDB.class_call_static(core, "mem", 100 + i * 4 + k, 0, 1)
			if v > 0x7FFFFFFF: v -= 0x100000000
			o.append(v)
		fg_objs.append(o)
	fg_giga = int(ClassDB.class_call_static(core, "mem", 26, 0, 1))
	fg_cfx = int(ClassDB.class_call_static(core, "mem", 28, 0, 1)) if skin_on else -1
	if fg_giga >= 0 and skin_on: fg_rel_pos = skin_pos; fg_rel_flip = skin_flip
	var vis := fg_rel >= 0 or fg_objs.size() > 0 or fg_giga >= 0 or fg_cfx >= 0
	fg_node.visible = vis
	if vis:
		fg_node.z_index = skin_group.z_index if skin_placed else used + 1
		fg_node.queue_redraw()

func _fg_draw() -> void:
	for o in fg_objs:
		var kind: int = o[2] >> 8
		var fr: int = o[2] & 0xFF
		if kind == 5: _bz_wave_draw(fg_node, Vector2(o[0], o[1]), fr, o[3] != 0); continue
		if kind == 6: _bz_col_draw(fg_node, Vector2(o[0], o[1]), fr); continue
		if kind == 8: _plasma_orb_draw(fg_node, Vector2(o[0], o[1]), fr); continue    # Plasma reativo
		if kind == 9: _plasma_boom_draw(fg_node, Vector2(o[0], o[1]), fr); continue   # Reação em cadeia
		var a: String = "giga_laser" if kind == 2 else ("plasma" if kind == 4 else ("kunai" if kind == 7 else "shot"))
		if skin_atl.has(a): skin_atl[a].draw(fg_node, fr, Vector2(o[0], o[1]), o[3] != 0)
	if fg_cfx >= 0 and skin_atl.has("charge_fx"):
		skin_atl["charge_fx"].draw(fg_node, fg_cfx, skin_pos, skin_flip)
	if fg_giga >= 0 and skin_atl.has("giga_fx"):
		skin_atl["giga_fx"].draw(fg_node, fg_giga, fg_rel_pos, fg_rel_flip)
	if fg_rel >= 0 and skin_atl.has("charge_release"):
		skin_atl["charge_release"].draw(fg_node, fg_rel, fg_rel_pos, fg_rel_flip)

# onda do sabre do Black Zero: meia-lua de energia escura com borda clara (desenhada aqui, não há sprite no X4)
func _bz_wave_draw(ci: CanvasItem, c: Vector2, age: int, right: bool) -> void:
	var dir := 1.0 if right else -1.0
	var grow := clampf(age / 4.0, 0.4, 1.0)
	var fade := clampf((28.0 - age) / 8.0, 0.0, 1.0)
	var h := 22.0 * grow
	for layer in 3:
		var w: float = [10.0, 7.0, 3.5][layer] * grow
		var col: Color = [Color(0.25, 0.0, 0.35, 0.55 * fade), Color(0.55, 0.15, 0.85, 0.85 * fade), Color(0.95, 0.85, 1.0, fade)][layer]
		var pts := PackedVector2Array()
		for k in 9:   # borda de fora
			var t := -1.0 + k / 4.0
			pts.append(c + Vector2(dir * (w + 6.0) * sqrt(1.0 - t * t), t * h))
		for k in 9:   # borda de dentro (volta)
			var t := 1.0 - k / 4.0
			pts.append(c + Vector2(dir * (6.0 - w * 0.2) * sqrt(1.0 - t * t) - dir * w * 0.6, t * h * 0.82))
		ci.draw_colored_polygon(pts, col)
	if age % 4 < 2:   # rastro
		ci.draw_rect(Rect2(c.x - dir * 14.0 - 2.0, c.y - 1.0, 4.0, 2.0), Color(0.8, 0.6, 1.0, 0.6 * fade))

var bz_fx_node: Node2D
var bz_fx := []
var bz_fx_t := 0
# Giga do Black Zero: aura escura em volta do Zero (subida/mergulho) e o impacto (tela escurece, clarão, anel)
func _bz_fx_draw() -> void:
	if not recomp: bz_fx_node.z_index = used + 3
	var ph: int = bz_fx[0]; var age: int = bz_fx[1]
	var z := Vector2(bz_fx[2], bz_fx[3] - 16)
	if ph > 0:
		var r := 20.0 + 3.0 * sin(bz_fx_t * 0.9)
		bz_fx_node.draw_circle(z, r + 6, Color(0.3, 0.0, 0.45, 0.22))
		bz_fx_node.draw_circle(z, r, Color(0.08, 0.0, 0.15, 0.35))
		for k in 6:   # faíscas girando
			var a := bz_fx_t * 0.35 + k * TAU / 6.0
			bz_fx_node.draw_rect(Rect2(z + Vector2(cos(a), sin(a)) * (r + 2) - Vector2(1, 1), Vector2(2, 2)), Color(0.9, 0.6, 1, 0.9))
		if ph == 2:   # linhas de velocidade no mergulho
			for k in 5:
				var x := z.x - 12 + k * 6 + (bz_fx_t * 3 + k * 5) % 4
				bz_fx_node.draw_line(Vector2(x, z.y - 40 - (k * 7) % 16), Vector2(x, z.y - 14), Color(0.8, 0.6, 1, 0.6), 1.0)
	if age >= 0:
		var c := Vector2(bz_fx[4], bz_fx[5] - 4)
		var dark := clampf(1.0 - age / 36.0, 0.0, 1.0)
		bz_fx_node.draw_rect(Rect2(0, 0, 320, 240), Color(0.12, 0.0, 0.2, 0.45 * dark))   # tela escurece
		if age < 4: bz_fx_node.draw_rect(Rect2(0, 0, 320, 240), Color(1, 0.9, 1, 0.55 * (1.0 - age / 4.0)))   # clarão
		for k in 2:   # anéis de choque
			var rr := (age - k * 5) * 9.0
			if rr > 0: bz_fx_node.draw_arc(c, rr, 0, TAU, 40, Color(0.75, 0.4, 1, dark * (0.9 - k * 0.3)), 3.0 - k)
		if age < 16:   # coluna de luz no ponto do impacto
			bz_fx_node.draw_rect(Rect2(c.x - 6 + age * 0.3, 0, 12 - age * 0.6, c.y), Color(0.9, 0.7, 1, 0.5 * (1.0 - age / 16.0)))

# coluna negra do Giga do Black Zero (cai do alto da tela)
func _bz_col_draw(ci: CanvasItem, c: Vector2, age: int) -> void:
	if age <= 0: return
	var fade := clampf((36.0 - age) / 6.0, 0.0, 1.0)
	var tail := minf(age * 9.0, 120.0)   # rastro até o alto
	var top := c.y - 48.0 - tail
	var bot := c.y + 48.0
	ci.draw_rect(Rect2(c.x - 11, top, 22, bot - top), Color(0.35, 0.05, 0.5, 0.35 * fade))
	ci.draw_rect(Rect2(c.x - 7, top + 10, 14, bot - top - 10), Color(0.05, 0.0, 0.1, 0.85 * fade))
	ci.draw_rect(Rect2(c.x - 3, top + 18, 6, bot - top - 18), Color(0.6, 0.2, 0.9, 0.9 * fade))
	ci.draw_rect(Rect2(c.x - 1, top + 24, 2, bot - top - 24), Color(1, 0.9, 1, fade))
	for k in 3:   # faíscas na ponta
		var sx := c.x + float((age * 7 + k * 11) % 23) - 11.0
		var sy := bot - float((age * 5 + k * 13) % 10)
		ci.draw_rect(Rect2(sx, sy, 2, 2), Color(0.9, 0.7, 1, fade))

var skin_flash := 0
# o que está vestido agora, desenhado só entre y0 e y1 (mod = cor; troca de armadura usa branco)
func _skin_draw_body(mod: Color, y0: float, y1: float) -> void:
	var fv := skin_flash
	if skin_fly >= 0:
		skin_atl["flight"].draw_clip(skin_node, skin_fly, skin_pos, skin_flip, mod, fv, y0, y1)
		return
	skin_atl["base"].draw_clip(skin_node, skin_f, skin_pos, skin_flip, mod, fv, y0, y1)
	if skin_bare: return
	for p in SKIN_PARTS:
		if not skin_atl.has(p): continue
		var d: Vector2 = skin_pd.get(p, Vector2.ZERO)
		if skin_flip: d.x = -d.x
		skin_atl[p].draw_clip(skin_node, skin_pf.get(p, skin_f), skin_pos + d, skin_flip, mod, fv, y0, y1)

func _skin_draw() -> void:
	skin_node.modulate = Color.WHITE
	var big := 1e6
	if skin_white <= 0:
		_skin_draw_body(Color.WHITE, -big, big)
		if skin_fly >= 0 and skin_fx >= 0 and skin_atl.has("flight_fx"): skin_atl["flight_fx"].draw(skin_node, skin_fx, skin_pos, skin_flip)   # jato por cima, como no X5
		return
	# troca de armadura: a armadura nova "baixa" da cabeça aos pés como um escaneamento (o resto fica branco brilhando),
	# com uma faixa de luz na frente e faíscas
	var r: Rect2 = skin_atl["flight"].bounds(skin_fly, skin_pos) if skin_fly >= 0 else skin_atl["base"].bounds(skin_f, skin_pos)
	r = r.grow_individual(0, 2, 0, 2)
	var t := 1.0 - float(skin_white) / float(SKIN_WIPE)
	var edge := r.position.y + t * r.size.y
	_skin_draw_body(Color.WHITE, -big, edge)
	_skin_draw_body(Color(6, 6, 7), edge, big)
	var w := r.size.x + 10.0
	skin_node.draw_rect(Rect2(r.position.x - 5, edge - 2, w, 4), Color(0.55, 0.85, 1.0, 0.55))
	skin_node.draw_rect(Rect2(r.position.x - 5, edge - 1, w, 1), Color(1, 1, 1, 0.95))
	for k in 4:   # faíscas em volta da faixa
		var sx := r.position.x - 4 + fmod(float(k * 37 + skin_white * 23), w + 8)
		var sy := edge + (float((k * 13 + skin_white * 7) % 9) - 4.0)
		var sz := 2.0 if (k + skin_white) % 2 == 0 else 1.0
		skin_node.draw_rect(Rect2(sx - sz, sy, sz * 2 + 1, 1), Color.WHITE)
		skin_node.draw_rect(Rect2(sx, sy - sz, 1, sz * 2 + 1), Color.WHITE)

# ---- habilidades novas do capacete e do corpo: escudo da Fourth X4 em volta do X e alvo da Marca da presa (Falcon X5) ----
# o jogo diz o estado (X4: x4core mem 72-75; X5/X6: x4_mem 0x1F900702-0x1F900705) e o fangame desenha por cima
var hab_node: Node2D
var hab_shield := 0; var hab_shield_t := 0      # escudo: 0 sem, 1 de pé, 2 voltando (quadros que faltam)
var hab_break := -1                               # quadros desde que o escudo quebrou (anel abrindo)
var hab_x := Vector2.ZERO; var hab_x_on := false
var hab_mark := Vector2(-99999, -99999)
var hab_tick := 0
var hab_prot := false   # dash translúcido (capacete Shadow): o X fica meio transparente enquanto está invencível
var hab_soc := 0        # Socorro automático (capacete Fourth X4): quadros que faltam do brilho verde
const HAB_SOC_T := 40
const HAB_PROT_A := 0.5   # transparência do X no dash translúcido
var hab_dive := -1      # Mergulho (capacete Falcon X6): quadros do mergulho (-1 = não)
var hab_objs: Array = []   # X5/X6: [posição na tela, tipo (8 bola, 9 explosão), idade]
var hab_right := false  # X olhando para a direita (direção do mergulho)
const HAB_DIVE_ANG := 0.55   # inclinação do X no mergulho (rad, ~32 graus: nariz para baixo)
# Mergulho: o X (pose do dash no ar) inclinado com o nariz para baixo, girando em volta da posição dele
func _hab_dive_tilt(g: CanvasItem, pos: Vector2, right: bool, on: bool) -> void:
	if on: g.transform = Transform2D(HAB_DIVE_ANG * (1.0 if right else -1.0), pos) * Transform2D(0.0, -pos)
	elif g.transform != Transform2D.IDENTITY: g.transform = Transform2D.IDENTITY
# bola de plasma (Plasma reativo) e explosão de plasma (Reação em cadeia): desenhadas aqui nos 3 jogos
func _plasma_orb_draw(n: CanvasItem, c: Vector2, age: int) -> void:
	var fade := clampf((90.0 - age) / 12.0, 0.0, 1.0) * clampf((age + 1) / 3.0, 0.35, 1.0)
	var pulse := 1.0 + 0.12 * sin(age * 0.6)
	n.draw_circle(c, 14.0 * pulse, Color(0.2, 0.5, 1.0, 0.22 * fade))
	n.draw_circle(c, 9.5 * pulse, Color(0.35, 0.8, 1.0, 0.5 * fade))
	n.draw_circle(c, 5.0, Color(0.92, 1.0, 1.0, 0.95 * fade))
	for k in 3:   # faíscas girando em volta
		var ang := age * 0.35 + k * TAU / 3.0
		var p := c + Vector2(cos(ang), sin(ang)) * 11.0 * pulse
		n.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(0.85, 1.0, 1.0, fade))
func _plasma_boom_draw(n: CanvasItem, c: Vector2, age: int) -> void:
	var t := clampf(age / 24.0, 0.0, 1.0)
	var r := 8.0 + 26.0 * t
	var a := 1.0 - t * t
	n.draw_circle(c, r, Color(0.25, 0.55, 1.0, 0.3 * a))
	n.draw_circle(c, r * 0.6, Color(0.55, 0.9, 1.0, 0.45 * a))
	n.draw_circle(c, maxf(2.0, 7.0 * (1.0 - t)), Color(1, 1, 1, a))
	n.draw_arc(c, r, 0, TAU, 32, Color(0.85, 1.0, 1.0, a), 2.0)
	for k in 8:   # raios saindo
		var ang := k * TAU / 8.0 + age * 0.08
		var d := Vector2(cos(ang), sin(ang))
		n.draw_line(c + d * r * 0.55, c + d * (r + 7.0), Color(0.8, 0.95, 1.0, a), 1.0)
func _hab_set(shield: int, st: int, xpos: Vector2, xon: bool, mark: Vector2, prot := false, soc := 0, dive := -1, right := false) -> void:
	if hab_node == null:
		hab_node = Node2D.new(); hab_node.z_index = 4000; add_child(hab_node)
		hab_node.draw.connect(_hab_draw)
	if hab_shield == 1 and shield == 2: hab_break = 0
	elif hab_break >= 0:
		hab_break += 1
		if hab_break > 12: hab_break = -1
	hab_shield = shield; hab_shield_t = st; hab_x = xpos; hab_x_on = xon; hab_mark = mark
	hab_prot = prot; hab_soc = soc; hab_dive = dive; hab_right = right
	hab_tick += 1
	hab_node.visible = shield != 0 or mark.x > -50000 or hab_break >= 0 or soc > 0 or dive >= 0 or not hab_objs.is_empty()
	if hab_node.visible: hab_node.queue_redraw()
func _hab_x4_update() -> void:
	if not native or game != "x4": return
	var q := func(a: int) -> int:
		var v := int(ClassDB.class_call_static(core, "mem", a, 0, 1))
		return v
	var sh: int = q.call(72)
	var mx: int = q.call(74)
	var pr: bool = q.call(85) != 0   # dash translúcido
	var so: int = q.call(86)          # Socorro automático (brilho)
	var dv: int = q.call(87)          # Mergulho (quadros, -1 = não)
	if dv > 0x7FFFFFFF: dv -= 0x100000000
	if skin_group:
		skin_group.self_modulate = Color(1, 1, 1, HAB_PROT_A) if pr else Color.WHITE
		_hab_dive_tilt(skin_group, skin_pos, skin_flip, dv >= 0 and skin_on)
	if sh == 0 and mx < -50000 and so <= 0 and dv < 0 and hab_node == null: return
	var sx: int = q.call(13); var sy: int = q.call(14)
	if sx > 32767: sx -= 65536
	if sy > 32767: sy -= 65536
	_hab_set(sh, q.call(73), Vector2(sx, sy), q.call(16) != 0, Vector2(mx, q.call(75)) if mx > -50000 else Vector2(-99999, -99999), pr, so, dv, skin_flip)
func _hab_draw() -> void:
	var t := float(hab_tick)
	var c := hab_x + Vector2(0, -2)
	# escudo: bolha azul clara; no último segundo antes de voltar pisca
	if hab_x_on and (hab_shield == 1 or (hab_shield == 2 and hab_shield_t < 60 and (hab_tick / 4) % 2 == 0)):
		var a := 0.2 + 0.06 * sin(t * 0.15)
		hab_node.draw_circle(c, 24.0, Color(0.35, 0.75, 1.0, a if hab_shield == 1 else a * 0.5))
		hab_node.draw_arc(c, 24.0, 0, TAU, 40, Color(0.75, 0.95, 1.0, 0.85 if hab_shield == 1 else 0.4), 1.0)
		hab_node.draw_arc(c, 21.0, t * 0.08, t * 0.08 + 1.2, 12, Color(1, 1, 1, 0.65), 1.0)
	if hab_break >= 0 and hab_x_on:   # quebrou: anel abrindo e sumindo
		hab_node.draw_arc(c, 24.0 + hab_break * 2.0, 0, TAU, 40, Color(0.75, 0.95, 1.0, 1.0 - hab_break / 12.0), 2.0)
	for o in hab_objs:   # X5/X6: bolas do Plasma reativo e explosões da Reação em cadeia (X4: fg_node)
		if o[1] == 8: _plasma_orb_draw(hab_node, o[0], o[2])
		elif o[1] == 9: _plasma_boom_draw(hab_node, o[0], o[2])
	# Mergulho: riscos de velocidade atrás do X (para cima e para trás)
	if hab_dive >= 0 and hab_x_on:
		var back := Vector2(-1.0 if hab_right else 1.0, -1.0).normalized()
		var side := Vector2(-back.y, back.x)
		for k in 4:
			var off := side * (float(k) - 1.5) * 7.0
			var l0 := 14.0 + float((hab_tick + k * 5) % 9)
			hab_node.draw_line(c + off + back * l0, c + off + back * (l0 + 16.0 + k * 3.0), Color(0.9, 0.95, 1.0, 0.55), 1.0)
	# Socorro automático: o Sub Tank entrou sozinho -> brilho verde em volta do X, anel abrindo e cruzinhas subindo
	if hab_soc > 0 and hab_x_on:
		var k := float(HAB_SOC_T - hab_soc)
		var a2 := clampf(float(hab_soc) / float(HAB_SOC_T), 0.0, 1.0)
		hab_node.draw_circle(c, 20.0, Color(0.45, 1.0, 0.55, 0.22 * a2))
		hab_node.draw_arc(c, 10.0 + k * 0.8, 0, TAU, 36, Color(0.55, 1.0, 0.6, a2), 2.0)
		for j in 6:
			var px := c.x + float((j * 11 + 4) % 32) - 16.0
			var py := c.y + 14.0 - k * 0.9 - float((j * 7) % 14)
			var cc := Color(0.75, 1.0, 0.75, a2)
			hab_node.draw_rect(Rect2(px - 2, py, 5, 1), cc)
			hab_node.draw_rect(Rect2(px, py - 2, 1, 5), cc)
	# alvo da Marca da presa
	if hab_mark.x > -50000:
		var col := Color(1.0, 0.2, 0.15, 0.95)
		var rr := 11.0 + 1.5 * sin(t * 0.2)
		hab_node.draw_arc(hab_mark, rr + 1.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 1.0)   # contorno escuro: aparece em qualquer fundo
		hab_node.draw_arc(hab_mark, rr, 0, TAU, 32, col, 2.0)
		for k in 4:
			var ang := t * 0.05 + k * PI / 2
			var d := Vector2(cos(ang), sin(ang))
			hab_node.draw_line(hab_mark + d * (rr - 4.0), hab_mark + d * (rr + 5.0), col, 2.0)
		hab_node.draw_rect(Rect2(hab_mark - Vector2(1, 1), Vector2(3, 3)), col)

# ---- X6 pela recompilação: X montado peça por peça (o X do jogo some e as peças são desenhadas no lugar) ----
const X6_P := 0x970A0                 # objeto do X
const X6_X_CLUTS := [0x7800, 0x7843, 0x780D, 0x780E, 0x780F]   # paletas do X e do rastro do dash (0x7802 = tiro normal: fica)
var mix6 := 0                         # 0 não decidido, 1 ligado, -1 desligado
var mix6_node: Node2D
var mix6_group: CanvasGroup
var mix6_atl := {}
var mix6_g2c := {}
var mix6_f := -1; var mix6_pos := Vector2.ZERO; var mix6_flip := false
# poses extras do X6 sem peças desenhadas: usa a pose parecida que tem (dash)
# Nova Strike: as peças do X4/X5 só têm o brilho em 206 e 209 (o X4 alterna os dois); o X6 usa 206-209
const MIX6_FALLBACK := {236: 69, 237: 70, 238: 72, 239: 61, 207: 206, 208: 209}
# golpes especiais da armadura carregada (a das pernas): o X "se transforma" nela e o próprio jogo desenha (como no X4)
const MIX6_SPECIAL := [0x23, 0x4A, 0x4D, 0x4E, 0x4F, 0x25, 0x26]   # voo da Falcon, dash no ar da Blade, Giga, Giga e Engetsurin da Shadow
const MIX6_WIPE := 10     # troca de armadura igual à do X4 (SKIN_WIPE): a roupa nova desce da cabeça aos pés
var mix6_wipe := 0          # >0: troca em andamento
var mix6_wipe_to := 0       # modo que está entrando (0 peças, 1 X do jogo, 2 golpe desenhado)
var mix6_last_c := -1       # último quadro das peças que existe (o golpe do jogo às vezes não tem)
var mix6_mixed := true      # peças de armaduras diferentes da carregada (só aí há troca, como no X4)
var mix6_fly_flipinv := false   # desenho capturado da tela do X6 (olhando para a direita): espelhado ao contrário das peças
var mix6_hide_bytes := PackedByteArray()
var mix6_hide_x := PackedByteArray()
var mix6_hide_cur := PackedByteArray()
var mix6_since2 := 99          # quadros desde o último golpe desenhado por nós (o rastro dele ainda é lixo)
var mix6_log: Array = []       # registro dos últimos quadros (user://mix6_registro.txt) para achar problemas
var mix6_log_n := 0
const MIX6_LEG_ACT := {"Falcon_X6": 0x23, "Blade_X6": 0x4A}   # golpe de cada perna
# X5 montado: mesmo motor do X6 (ações, quadros, objeto e câmera no mesmo formato), outro endereço do X
const MIX5_SPECIAL := [0x23, 0x24, 0x25]   # voo da Falcon, Giga da Falcon, Giga da Gaea (sempre da armadura carregada)
var mix6_p := X6_P          # objeto do X (X6 0x970A0, X5 0x9A0A0)
var mix6_cam := 0x971F8     # câmeras (X6 0x971F8, X5 0x9A1F8)
var mix6_special: Array = MIX6_SPECIAL
var mix6_fly_atl: SpriteAtlas = null   # desenho completo do golpe da perna (assets/x/parts/<perna>/flight)
var mix6_fly_act := -1; var mix6_fly_kind := ""; var mix6_fly_hide := PackedByteArray()
var mix6_mode := 0          # 0 peças, 1 X do jogo (golpe da armadura carregada), 2 golpe da perna desenhado por nós
var mix6_fly_t := 0; var mix6_fly_phase := -1; var mix6_fly_prev := Vector2.ZERO
var mix6_fly_f := -1
var mix6_fly_fx: SpriteAtlas = null   # jato do voo da Falcon do X5 (assets/x/parts/Falcon_X5/flight_fx)
var mix6_fly_jet := -1
var mix6_f5_snd := -1
var mix6_look: Array = ["", "", "", ""]   # o que aparece em cada modo (0 peças, 1 X do jogo, 2 e 3 golpe das pernas)
# golpe de sabre do X6 (botão especial sem arma: ação 0x2D no chão, 0x2E no ar). O jogo troca a tabela de quadros do X
# (+0x3C) e os quadros 47-61 são os da tabela do sabre, não os das peças. Desenho: modo 5 = X sem armadura + pernas da
# armadura das pernas + resto (corpo, braços, capacete) da armadura do braço, tirados do próprio X6
# (assets/x/parts/sabre_x6/<armadura>/base|pernas|resto, quadro = k - 47). Peça do X4/X5 sem esse desenho (a Falcon do X5
# usa o da Falcon do X6 com as cores dela) ou atlas faltando (antes do PREPARAR): o X do jogo (modo 1).
const SABRE_ARM := ["Falcon_X6", "Blade_X6", "Shadow_X6", "Ultimate_X6", "Falcon_X5"]
const SABRE_ACT := [0x2D, 0x2E]
var mix6_sab_ok := false
var mix6_sab_base: SpriteAtlas = null; var mix6_sab_resto: SpriteAtlas = null; var mix6_sab_pernas: SpriteAtlas = null
var mix6_bank0 := 0   # tabela de quadros normal do X (vista andando/parado)
var mix6_sab_f := -1  # quadro do sabre na tela (-1 = nenhum)
var mix6_shot_atl: SpriteAtlas = null   # tiros da Gaea do X5 no X6 (assets/x/parts/Gaea_X5/shot)
var mix6_shot_node: Node2D
var mix6_shots: Array = []   # [posição na tela, quadro, direita] (o que está na tela: 2 quadros atrás)
var mix6_gaea := false
var mix6_x5gaea := false
var mix6_cfx_atl: SpriteAtlas = null; var mix6_rel_atl: SpriteAtlas = null
var mix6_charge_t := -1; var mix6_rel_t := -1
var mix6_variant := 0   # X piscando: 0 normal, 1 tiro, 2 meia carga, 3 carga cheia (variantes atlas_c1-3 das peças)
var mix6_cfx := -1; var mix6_relf := -1
# Giga do X5 no X6 (armadura completa Falcon_X5 / Gaea_X5) e do X6 no X5 (Falcon_X6 / Blade_X6 / Shadow_X6, g6_step):
# a recompilação faz o Giga (psx_embed.cpp giga5_step) e diz o
# quadro do X5 (x4_mem 0x1F900003, atlas "flight" da armadura), o efeito da Gaea (0x1F900004, atlas giga_fx) e os raios
# da Falcon (0x1F900600: [x, y, quadro do atlas giga_laser]); o fangame desenha tudo do X5
var mix6_giga_atl: SpriteAtlas = null; var mix6_giga_fx: SpriteAtlas = null; var mix6_laser_atl: SpriteAtlas = null
var mix6_giga_on := false; var mix6_giga_fxf := -1
var mix6_lasers: Array = []   # [posição na tela, quadro]
var mix6_laser_node: Node2D
func _mix6_draw_lasers() -> void:
	if mix6_laser_atl == null: return
	for o in mix6_lasers:
		if mix6_laser_atl.has_frame(o[1]): mix6_laser_atl.draw(mix6_laser_node, o[1], o[0], false)
func _mix6_draw_shots() -> void:
	for o in mix6_shots: mix6_shot_atl.draw(mix6_shot_node, o[1], o[0], o[2])
	# partículas de carga e anel de liberação do X5 (como no X4: no lugar do X, por cima)
	if mix6_cfx >= 0 and mix6_cfx_atl: mix6_cfx_atl.draw(mix6_shot_node, mix6_cfx, mix6_pos, mix6_flip)
	if mix6_relf >= 0 and mix6_rel_atl: mix6_rel_atl.draw(mix6_shot_node, mix6_relf, mix6_pos, mix6_flip)

# peças da Blade/Shadow do X6 no X5: a recompilação faz os golpes (psx_embed.cpp x6p5_*) e diz o que desenhar:
# x4_mem 0x1F900020 quadro especial do X, +1 tipo (1 Shadow pernas, 2 dash da Blade, 3 Shadow braço/Engetsurin, 4 sabre da
# Blade), +2 efeito do Engetsurin; 0x1F900080 shurikens (tipo 7) e tiro carregado da Blade (tipo 1). Modo 4 = esse desenho.
var x6s_on := false
var x6s_atl := {}
var x6s_add: SpriteAtlas = null     # rastro somado do dash da Blade (dash6_add, como no X6 montado)
var x6s_fx: SpriteAtlas = null      # efeito do Engetsurin (Shadow_X6/giga_fx: 300+t no chão, 400+t no ar)
var x6s_kunai: SpriteAtlas = null; var x6s_bshot: SpriteAtlas = null
var x6s_node: Node2D
var x6s_objs: Array = []            # [posição na tela, tipo, quadro, direita]
var x6s_kind := 0; var x6s_f := -1; var x6s_fxf := -1
const X6S_LOOK := {1: "Shadow_X6", 2: "Blade_X6", 3: "Shadow_X6", 4: "Blade_X6"}
func _x6s_draw_objs() -> void:
	for o in x6s_objs:
		var a: SpriteAtlas = x6s_kunai if o[1] == 7 else x6s_bshot
		if a and a.has_frame(o[2]): a.draw(x6s_node, o[2], o[0], o[3])
func _x6s_body(mod: Color, y0: float, y1: float) -> void:
	var a: SpriteAtlas = x6s_atl.get(x6s_kind)
	if a == null or not a.has_frame(x6s_f): return
	# (o dash da Blade foi capturado do X6 olhando para a direita; os outros olham para a esquerda como as peças)
	a.draw_clip(mix6_node, x6s_f, mix6_pos, mix6_flip != (x6s_kind == 2), mod, mix6_variant if mod == Color.WHITE else 0, y0, y1)
func _mix6_sabre_init(pp: Dictionary, x5: bool) -> void:
	mix6_sab_ok = false; mix6_sab_base = null; mix6_sab_resto = null; mix6_sab_pernas = null; mix6_bank0 = 0
	if x5: return
	var up := ""
	for p in ["arms", "body", "helmet"]:
		var a := FangameParts.asset(str(pp.get(p, "")))
		if a == "": continue
		if not a in SABRE_ARM: return   # peça sem o desenho do sabre: o X do jogo
		if up == "": up = a
	var lg := FangameParts.asset(str(pp.get("legs", "")))
	if lg != "" and not lg in SABRE_ARM: return
	var bs := up if up != "" else (lg if lg != "" else "Falcon_X6")   # X sem armadura: o da armadura de cima
	mix6_sab_base = _atl("sabre_x6", bs + "/base")
	if up != "": mix6_sab_resto = _atl("sabre_x6", up + "/resto")
	if lg != "": mix6_sab_pernas = _atl("sabre_x6", lg + "/pernas")
	mix6_sab_ok = mix6_sab_base != null and (up == "" or mix6_sab_resto != null) and (lg == "" or mix6_sab_pernas != null)
	print("X6: sabre das peças ", "resto=%s pernas=%s" % [up, lg] if mix6_sab_ok else "(X do jogo)")

func _mix6_look_of(e: Array) -> String:
	if e[4] == 5: return str(mix6_look[0])   # sabre desenhado com as peças: mesma aparência
	if e[4] == 4: return str(X6S_LOOK.get(e[11][0], "?"))
	return str(mix6_look[e[4]]) if e[4] < mix6_look.size() else "?"
func _s32(v: int) -> int:
	return v - 0x100000000 if v > 0x7FFFFFFF else v

func _mix6_init() -> void:
	mix6 = -1
	if recomp: ClassDB.class_call_static(core, "hide_cluts", PackedByteArray())   # nada escondido (sobra de outra fase)
	var pp: Dictionary = L.get("parts", {})
	if recomp and (game == "x6" or game == "x5"):
		ClassDB.class_call_static(core, "set_parts", PackedByteArray([0]))
		ClassDB.class_call_static(core, "mem", 0x1F900700, 0, -1); ClassDB.class_call_static(core, "mem", 0x1F900701, 0, -1)   # habilidades novas desligadas
	if not recomp or (game != "x6" and game != "x5") or int(L.get("char", 0)) != 0 or pp.is_empty(): return
	var x5 := game == "x5"
	mix6_p = 0x9A0A0 if x5 else X6_P
	mix6_cam = 0x9A1F8 if x5 else 0x971F8
	mix6_special = MIX5_SPECIAL if x5 else MIX6_SPECIAL
	# habilidades por peça: cada ponto do jogo que pergunta "qual armadura" recebe a armadura da peça certa
	var pc := FangameParts.x5_part_codes(pp) if x5 else FangameParts.x6_part_codes(pp)
	mix6_arms_native = pc[1] != 0 and pc[1] == int(L.get("armor", 0))
	var ok: int = ClassDB.class_call_static(core, "set_parts", PackedByteArray([1, pc[0], pc[1], pc[2], pc[3], pc[4], pc[5], pc[6] if pc.size() > 6 else 0]))
	print(game.to_upper(), ": habilidades por peça (pernas, braço, corpo, capacete, Giga, pulo alto, extras) = ", pc, " ligado=", ok)
	# habilidades novas do capacete e do corpo (psx_embed.cpp hab_*): armadura de onde veio cada peça
	var hh := FangameParts.hab_id(str(pp.get("helmet", ""))); var hbd := FangameParts.hab_id(str(pp.get("body", "")))
	ClassDB.class_call_static(core, "mem", 0x1F900700, hh, -1); ClassDB.class_call_static(core, "mem", 0x1F900701, hbd, -1)
	print(game.to_upper(), ": habilidades novas capacete=", hh, " corpo=", hbd)
	if hover_x6.is_empty():   # poses do Hover/Nova para as peças do X6 (que não têm esses quadros de verdade)
		var hj = JSON.parse_string(FileAccess.get_file_as_string("res://assets/x/parts/hover_x6.json"))
		hover_x6 = hj if hj is Dictionary else {"_": 1}
	mix6_src.clear()
	for p in SKIN_PARTS: mix6_src[p] = FangameParts.asset(str(pp.get(p, "")))
	var cj = JSON.parse_string(FileAccess.get_file_as_string("res://assets/x/parts/canonical.json"))
	mix6_g2c = cj.game_to_canonical[game]
	mix6_atl["base"] = SpriteAtlas.load_from("res://assets/x/parts/body")
	for p in SKIN_PARTS:
		var a := _atl(str(pp.get(p, "")), p)
		if a: mix6_atl[p] = a
	var b := PackedByteArray([0x05, 0xF0])   # só a folha de sprites do X (página de textura x=320): efeitos da armadura continuam
	for c in X6_X_CLUTS: b.append(c & 0xFF); b.append(c >> 8)
	mix6_hide_bytes = b   # X + rastro
	# normal: só o X some; o rastro do dash é o do próprio jogo (cópias azuis somadas à tela, como no original)
	mix6_hide_x = PackedByteArray([0x05, 0xF0, 0x00, 0x78, 0x43, 0x78])
	# golpe das pernas de outra armadura (voo da Falcon / dash no ar da Blade): o X6 só tem os desenhos da armadura
	# carregada, então o X e o jato saem errados (lixo). Nesses golpes o X do jogo e os efeitos dele na folha do X
	# somem e entra o desenho completo da armadura das pernas (o mesmo do X4: X + rastro + jato por quadro).
	mix6_fly_atl = null; mix6_fly_act = -1; mix6_fly_fx = null; mix6_fly_kind = ""
	var legs := FangameParts.asset(str(pp.get("legs", "")))
	var legs_code := 0 if x5 else int(FangameParts.X6_CODE.get(legs, 0))   # (X5: as pernas são a armadura carregada)
	if legs_code != 0 and legs_code != int(L.get("armor", 0)) and MIX6_LEG_ACT.has(legs):
		# Blade: desenho tirado do próprio X6 (assets/x/parts/Blade_X6/dash6 + dash6_add, o rastro é somado à tela)
		mix6_fly_atl = _atl(legs, "dash6" if legs == "Blade_X6" else "flight")
		mix6_fly_add = _atl(legs, "dash6_add") if legs == "Blade_X6" else null
		mix6_fly_flipinv = legs == "Blade_X6"
		if mix6_fly_atl: mix6_fly_act = MIX6_LEG_ACT[legs]; mix6_fly_kind = legs
		var b2 := b.duplicate()
		for c in [0x784A]: b2.append(c & 0xFF); b2.append(c >> 8)   # (0x7841 é o ícone do X no HUD: fica)
		mix6_fly_hide = b2
	elif x5 and legs == "Falcon_X6":
		# pernas Falcon do X6 no X5: o dash no ar da Fourth (ação 13) vira o voo da Falcon do X6 (a recompilação segura os
		# tempos do X6); desenho completo do X6 (Falcon_X6/flight, 300 + tempo, com rastro e jato)
		mix6_fly_atl = _atl(legs, "flight"); mix6_fly_add = null; mix6_fly_flipinv = false
		if mix6_fly_atl: mix6_fly_act = 13; mix6_fly_kind = legs
		mix6_fly_hide = b
	elif not x5 and legs == "Falcon_X5":
		# voo livre da Falcon do X5: entra pelo flutuar (0x21); a recompilação move o X igual ao X5 e diz o quadro do
		# desenho do X5 e o do jato (x4_mem 0x1F900000/1); o jato do flutuar do X6 se apaga sozinho nesse voo
		mix6_fly_atl = _atl(legs, "flight"); mix6_fly_add = null; mix6_fly_flipinv = false
		mix6_fly_fx = _atl(legs, "flight_fx")
		if mix6_fly_atl: mix6_fly_act = 0x21; mix6_fly_kind = legs
		mix6_fly_hide = b
	# flutuar das pernas Fourth (X4/X5): o X vira a Fourth inteira (como os outros golpes das pernas), com a troca do X4
	mix6_hover_atl.clear()
	if legs == "Fourth_X4" or legs == "Fourth_X5":
		for p in SKIN_PARTS:
			var a := _atl(legs, p)
			if a: mix6_hover_atl[p] = a
	_mix6_sabre_init(pp, x5)
	var nat := int(L.get("armor", 0))
	# X6 com a Shadow carregada (pernas Shadow): pulo alto e pendurado no teto (ação 0x1F) é golpe da armadura carregada,
	# o X vira a Shadow inteira e o próprio jogo desenha (como no X4; com as peças misturadas a animação saía errada)
	if not x5 and nat == 2: mix6_special = MIX6_SPECIAL + [0x1F]
	mix6_mixed = false
	for p in ["helmet", "body", "arms", "legs"]:
		if int((FangameParts.X5_CODE if x5 else FangameParts.X6_CODE).get(FangameParts.asset(str(pp.get(p, ""))), -1)) != nat: mix6_mixed = true
	# aparência de cada modo (a troca de armadura só acontece quando muda o que aparece): peças / armadura carregada /
	# golpe das pernas desenhado por nós / flutuar da Fourth
	var pl := ""
	for p in ["helmet", "body", "arms", "legs"]:
		var a := FangameParts.asset(str(pp.get(p, "")))
		pl = a if p == "helmet" else (pl if a == pl else "mix")
	var nat_names: Array = ["", "Fourth_X5", "Falcon_X5", "Gaea_X5", "Ultimate_X5"] if x5 else ["", "Falcon_X6", "Shadow_X6", "Blade_X6", "Ultimate_X6"]
	mix6_look = [pl, str(nat_names[nat]) if nat >= 0 and nat < nat_names.size() else "?", legs, legs, ""]
	# peças da Blade/Shadow do X6 no X5 (golpes feitos pela recompilação)
	x6s_on = false; x6s_atl.clear(); x6s_add = null; x6s_fx = null; x6s_kunai = null; x6s_bshot = null; x6s_objs.clear()
	if x5:
		var aa := FangameParts.asset(str(pp.get("arms", "")))
		if legs == "Shadow_X6" or aa == "Shadow_X6":
			var sfl := _atl("Shadow_X6", "flight")
			if sfl: x6s_atl[1] = sfl; x6s_atl[3] = sfl
			x6s_fx = _atl("Shadow_X6", "giga_fx"); x6s_kunai = _atl("Shadow_X6", "shot")
		if legs == "Blade_X6":
			var bd := _atl("Blade_X6", "dash6")
			if bd: x6s_atl[2] = bd
			x6s_add = _atl("Blade_X6", "dash6_add")
		if aa == "Blade_X6":
			var bf := _atl("Blade_X6", "flight")
			if bf: x6s_atl[4] = bf
			x6s_bshot = _atl("Blade_X6", "shot")
		x6s_on = not x6s_atl.is_empty() or x6s_kunai != null or x6s_bshot != null
		if x6s_on and x6s_node == null:
			x6s_node = Node2D.new(); x6s_node.z_index = 1; add_child(x6s_node)
			x6s_node.draw.connect(_x6s_draw_objs)
	mix6_f5_snd = -1
	# braço Gaea do X5 no X6: tiros da Gaea (a recompilação controla os tiros do X6 e diz onde desenhar)
	mix6_gaea = not x5 and FangameParts.asset(str(pp.get("arms", ""))) == "Gaea_X5"
	# X5 com a Falcon carregada (pernas Falcon) e braço Gaea: o X5 atira o tiro da Gaea dele (0x2D / Gaea Shot 0x2E,
	# tudo igual: alcance, sumir, 7 quadros, sons), só que invisível (o desenho não está na VRAM): o fangame desenha
	mix6_x5gaea = x5 and FangameParts.asset(str(pp.get("arms", ""))) == "Gaea_X5" and nat != 3
	mix6_shot_atl = _atl("Gaea_X5", "shot") if mix6_gaea or mix6_x5gaea else null
	mix6_cfx_atl = _atl("Gaea_X5", "charge_fx") if mix6_gaea else null
	mix6_rel_atl = _atl("Gaea_X5", "charge_release") if mix6_gaea else null
	mix6_charge_t = -1; mix6_rel_t = -1
	# Giga do X5 (só com as 4 peças da mesma armadura, como no X5)
	var fs := FangameParts.full_set(pp)
	mix6_giga_atl = null; mix6_giga_fx = null; mix6_laser_atl = null; mix6_giga_on = false; mix6_lasers.clear()
	if not x5 and (fs == "Falcon_X5" or fs == "Gaea_X5"):
		mix6_giga_atl = _atl(fs, "flight")
		if fs == "Gaea_X5": mix6_giga_fx = _atl(fs, "giga_fx")
		else: mix6_laser_atl = _atl(fs, "giga_laser")
	elif x5 and (fs == "Falcon_X6" or fs == "Blade_X6" or fs == "Shadow_X6"):
		# Giga do X6 no X5 (psx_embed.cpp g6_step): o X do X6 (atlas "flight"), o efeito da Blade/Shadow (giga_fx, quadro =
		# tempo do golpe: ondas, luas, sabre) e os raios da Falcon (giga_laser), nos mesmos endereços do Giga do X5 no X6
		mix6_giga_atl = _atl(fs, "flight")
		if fs == "Falcon_X6": mix6_laser_atl = _atl(fs, "giga_laser")
		else: mix6_giga_fx = _atl(fs, "giga_fx")
	if mix6_laser_atl:
		mix6_laser_node = Node2D.new(); mix6_laser_node.z_index = 1; add_child(mix6_laser_node)
		mix6_laser_node.draw.connect(_mix6_draw_lasers)
	if mix6_gaea:   # brilho do cano do X6 ao soltar a carga (folha do X, paleta 0x7802): no X5 não tem
		var g := PackedByteArray([0x05, 0xF0, 0x02, 0x78])   # (2º grupo: não conta como "o X foi desenhado")
		mix6_hide_x = mix6_hide_x + g; mix6_hide_bytes = mix6_hide_bytes + g; mix6_fly_hide = mix6_fly_hide + g
	# X piscando (carga / tiro), como no X4: cores das variantes das peças; o corpo usa as da 1ª peça que tem
	var bs := ""
	for p in ["arms", "body", "helmet", "legs"]:
		var s0 := FangameParts.asset(str(pp.get(p, "")))
		if s0 != "" and FileAccess.file_exists("res://assets/x/parts/%s/base_c1.png" % s0): bs = s0; break
	if bs != "": mix6_atl["base"].load_variants([1, 2, 3].map(func(n): return "res://assets/x/parts/%s/base_c%d.png" % [bs, n]))
	mix6_shots.clear()
	if mix6_shot_atl:
		mix6_shot_node = Node2D.new(); mix6_shot_node.z_index = 1; add_child(mix6_shot_node)
		mix6_shot_node.draw.connect(_mix6_draw_shots)
	mix6_hide_cur = mix6_hide_x
	ClassDB.class_call_static(core, "hide_cluts", mix6_hide_x)
	mix6_add_node = Node2D.new(); mix6_add_node.z_index = 1; add_child(mix6_add_node)
	var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mix6_add_node.material = mat
	mix6_add_node.draw.connect(_mix6_draw_add)
	# dentro de um CanvasGroup: no dash translúcido o X inteiro fica meio transparente por igual
	mix6_group = CanvasGroup.new(); mix6_group.z_index = 1; add_child(mix6_group)
	mix6_node = Node2D.new(); mix6_group.add_child(mix6_node)
	mix6_node.draw.connect(_mix6_draw)
	mix6 = 1
	print(game.to_upper(), ": X montado por peças ", pp)

# a imagem do PS1 mostra o que foi desenhado no quadro anterior, que por sua vez usou o estado do X de antes:
# a tela atrasa 2 quadros em relação à RAM (medido); as peças usam o estado de 2 quadros atrás
var mix6_hist: Array = []   # [quadro canônico, posição, virado], mais recente no fim
var mix6_hits_prev := 0
var mix6_boxes_prev := PackedInt32Array()
var mix6_ghosts: Array = []   # rastro do dash/voo: [deslocamento, cor]
# rastro (cópias do X com as paletas 0x780D-F) e a cor de cada cópia
const MIX6_GHOST := {2: Color(0.75, 0.9, 1.9, 0.5), 3: Color(0.75, 0.75, 1.9, 0.38), 4: Color(0.85, 0.7, 1.8, 0.28)}
func _mix6_step() -> void:
	if mix6 == 0: _mix6_init()
	if mix6 != 1: return
	var m := func(ad: int, n: int) -> int: return int(ClassDB.class_call_static(core, "mem", ad, 0, n))
	var P := mix6_p
	var k: int = m.call(P + 0x47, 1)
	var bo: int = m.call(P + 0x14, 1); var cam_ad := mix6_cam + bo * 0x54
	var world := Vector2(m.call(P + 0xA, 2), m.call(P + 0xE, 2))
	var cam := Vector2(m.call(cam_ad + 0xA, 2), m.call(cam_ad + 0xE, 2))
	var c := int(mix6_g2c.get(str(k), -1))
	if MIX6_FALLBACK.has(c): c = MIX6_FALLBACK[c]
	# golpe especial: mostra o X do jogo (a troca vale a partir dos sprites montados agora, que aparecem 2 quadros depois)
	var act: int = m.call(P + 5, 1)
	var mode := 0
	var ff := -1
	var fj := -1
	var sab := -1
	if game == "x6":
		var bank: int = m.call(P + 0x3C, 4)
		if act in [2, 3, 4, 6, 7, 8]: mix6_bank0 = bank   # parado / andando / pulando / caindo: tabela normal
		elif act in SABRE_ACT and k >= 47 and k <= 61 and mix6_bank0 != 0 and bank != mix6_bank0: sab = k - 47
	var gf := int(m.call(0x1F900003, 4)) if mix6_giga_atl else -1
	var giga := gf >= 0 and mix6_giga_atl.has_frame(gf)
	if giga:
		mode = 2; ff = gf   # Giga do X5: desenho completo da armadura (como o voo)
	elif mix6_fly_atl != null and act == mix6_fly_act and mix6_fly_kind == "Falcon_X5":
		mode = 2; ff = int(m.call(0x1F900000, 4)); fj = int(m.call(0x1F900001, 4))
		if ff < 0 or not mix6_fly_atl.has_frame(ff): mode = 0   # (voo não ligado: fica o flutuar comum)
		var sn := int(m.call(0x1F900002, 4))   # som do jato do X5 (a cada 9 quadros)
		if sn != mix6_f5_snd:
			if mix6_f5_snd >= 0 and mode == 2: _sfx_player(FG_SFX.find("x5_fly")).play()
			mix6_f5_snd = sn
	elif mix6_fly_atl != null and act == mix6_fly_act:
		mode = 2; ff = _mix6_fly_frame(world, m.call(P + 6, 1), k)
		if ff < 0: mode = 0   # dash acabou parado no chão (o jogo ainda está no estado do dash): volta às peças
	elif act == 0x21 and not mix6_hover_atl.is_empty() and c >= 0:
		mode = 3   # flutuar: a Fourth inteira desenhada pelo fangame
	elif sab >= 0:
		mode = 5 if mix6_sab_ok and mix6_sab_base.has_frame(sab) else 1   # golpe de sabre do X6
	elif act in mix6_special or c < 0:
		mode = 1
	var x6k := 0; var x6f := -1; var x6fx := -1
	if x6s_on:   # golpe das peças da Blade/Shadow do X6 no X5: desenho especial (tem prioridade)
		x6f = _s32(m.call(0x1F900020, 4)); x6k = _s32(m.call(0x1F900021, 4)); x6fx = _s32(m.call(0x1F900022, 4))
		var xa: SpriteAtlas = x6s_atl.get(x6k)
		if x6k > 0 and x6f >= 0 and xa != null and xa.has_frame(x6f): mode = 4
		else: x6k = 0
	if mode != 2: mix6_fly_phase = -1
	mix6_since2 = 0 if mode == 2 else mini(mix6_since2 + 1, 99)
	mix6_mode = mode
	var hb: PackedByteArray = mix6_hide_bytes if (giga or mode == 4) else mix6_fly_hide if mode == 2 else (PackedByteArray() if mode == 1 else
		(mix6_hide_bytes if mix6_since2 < 24 else mix6_hide_x))   # logo depois do golpe: o rastro do jogo ainda é lixo
	# dash translúcido com o X do próprio jogo à mostra (voo da armadura carregada): o fangame não desenha esse X, então
	# ele pisca (some um quadro sim, um não), que na tela parece meio transparente
	if mode == 1 and int(m.call(0x1F900707, 4)) != 0 and Engine.get_process_frames() % 2 == 0: hb = mix6_hide_x
	if hb != mix6_hide_cur:
		mix6_hide_cur = hb
		ClassDB.class_call_static(core, "hide_cluts", hb)
	_mix6_log_add([Engine.get_process_frames(), act, m.call(P + 6, 1), k, int(world.x), int(world.y), mode, ff, mix6_fly_phase, mix6_fly_t, m.call(P + 0x15, 1)])
	# histórico: [quadro canônico, posição no mundo, virado, câmera, modo, quadro do golpe]
	# carga do X (X6/X5: +0x9B/+0x9C nível 0/1 meia/2 cheia; +0xA2 tempo do clarão do tiro, 5-6 ao atirar)
	var lvl: int = maxi(m.call(P + 0x9B, 1), m.call(P + 0x9C, 1))
	mix6_charge_t = mix6_charge_t + 1 if lvl >= 1 else -1
	var fv := 0
	if mix6_charge_t >= 0:
		if (mix6_charge_t / 2) % 2 == 0: fv = 3 if lvl >= 2 else 2
	elif m.call(P + 0xA2, 1) > 1: fv = 1
	var cfx := -1
	if mix6_gaea or mix6_giga_atl or x6s_on:
		for i in 8:   # sons do X5 no lugar dos do X6 / do X6 no X5 (fila da recompilação; +0x100 = parar; Gigas do X5)
			var v := int(m.call(0x1F900300, 4))
			if v < 0: break
			if v & 0x100:
				if sfx_players.has(v & 0xFF): sfx_players[v & 0xFF].stop()
			else:
				_sfx_player(v).play()
				if v == 3: mix6_rel_t = 0   # carga cheia: anel de liberação do X5 (quadros 0-9)
		if mix6_charge_t >= 0: cfx = mix6_charge_t % 10 + (10 if lvl >= 2 else 0)
	var rel := mix6_rel_t
	if mix6_rel_t >= 0:
		mix6_rel_t += 1
		if mix6_rel_t > 9: mix6_rel_t = -1
	var sh := []
	if mix6_x5gaea:   # tiros da Gaea do X5 (banco 0x80098120, 32 x 0x9C): k 0-2 voando, 4-7 sumindo
		for i in 32:
			var ad := 0x98120 + i * 0x9C
			if m.call(ad, 1) == 0: continue
			var idv: int = m.call(ad + 1, 1)
			if idv != 0x2D and idv != 0x2E: continue
			var st: int = m.call(ad + 4, 1)
			if st != 1 and st != 2: continue   # 0 nascendo, 3 saindo
			var kk: int = m.call(ad + 0x47, 1)
			var fr := (kk if kk < 4 else kk + 16) if idv == 0x2D else (32 + kk if kk < 4 else 48 + kk)
			sh.append([m.call(ad + 0xA, 2), m.call(ad + 0xE, 2), 3 * 256 + fr, 1 if (m.call(ad + 0x15, 1) & 0x40) else 0])
	elif mix6_shot_atl:   # [x, y, tipo*256 + quadro, direita] no mundo
		for i in mini(int(m.call(0x1F900100, 4)), 16):
			var o := []
			for f in 4: o.append(int(m.call(0x1F900110 + i * 4 + f, 4)))
			sh.append(o)
	var lz := []
	if mix6_laser_atl:   # raios do Giga da Falcon do X5 (continuam depois do fim do Giga)
		for i in mini(int(m.call(0x1F900600, 4)), 24):
			lz.append([int(m.call(0x1F900610 + i * 4, 4)), int(m.call(0x1F900611 + i * 4, 4)), int(m.call(0x1F900612 + i * 4, 4))])
	var gx := [giga, int(m.call(0x1F900004, 4)) if giga else -1, lz]
	var hab := [int(m.call(0x1F900702, 4)), int(m.call(0x1F900703, 4)), int(m.call(0x1F900704, 4)), int(m.call(0x1F900705, 4)),
		int(m.call(0x1F900707, 4)), int(m.call(0x1F900710, 4)), int(m.call(0x1F900712, 4))]   # + dash translúcido, Socorro, Mergulho
	var hbl := []   # bolas do Plasma reativo / explosões da Reação em cadeia: [x, y, tipo*256 + idade] no mundo
	for i in mini(int(m.call(0x1F900740, 4)), 16):
		hbl.append([int(m.call(0x1F900741 + i * 3, 4)), int(m.call(0x1F900742 + i * 3, 4)), int(m.call(0x1F900743 + i * 3, 4))])
	hab.append(hbl)
	var xo := []   # shurikens / tiro da Blade: [x, y, tipo*256 + quadro, direita] no mundo
	if x6s_on:
		for i in mini(_s32(m.call(0x1F900080, 4)), 24):
			xo.append([_s32(m.call(0x1F900081 + i * 4, 4)), _s32(m.call(0x1F900082 + i * 4, 4)), _s32(m.call(0x1F900083 + i * 4, 4)), _s32(m.call(0x1F900084 + i * 4, 4))])
	mix6_hist.append([c, world, m.call(P + 0x15, 1) != 0, cam, mode, ff, fj, sh, [fv, cfx, rel], gx, hab, [x6k, x6f, x6fx], xo, sab])   # +0x15 != 0: virado para a esquerda
	if mix6_hist.size() > 24: mix6_hist.pop_front()
	# sprites do X desenhados no quadro anterior = o que está na tela agora (0: o X piscou/sumiu)
	var hits_now := int(ClassDB.class_call_static(core, "hidden_hits"))
	var shown := mix6_hits_prev > 0
	mix6_hits_prev = hits_now
	var bx: PackedInt32Array = (ClassDB.class_call_static(core, "hidden_boxes") as PackedByteArray).to_int32_array()
	var sb := mix6_boxes_prev
	mix6_boxes_prev = bx
	var di := mix6_hist.size() - 3   # estado que está na tela (2 quadros atrás)
	if di < 0:
		mix6_f = -1; mix6_ghosts.clear(); mix6_node.queue_redraw(); mix6_add_node.queue_redraw(); return
	var e: Array = mix6_hist[di]
	if e[0] >= 0: mix6_last_c = e[0]
	# troca de armadura (como no X4): quando o que está na tela troca entre peças, X do jogo e golpe desenhado,
	# a roupa nova desce da cabeça aos pés (o resto fica branco) com a faixa de luz e as faíscas, e o som do X4
	var prev_mode: int = mix6_hist[di - 1][4] if di > 0 else 0
	var prev_look := _mix6_look_of(mix6_hist[di - 1]) if di > 0 else str(mix6_look[0])
	if e[4] != prev_mode and _mix6_look_of(e) != prev_look:
		mix6_wipe = MIX6_WIPE; mix6_wipe_to = e[4]
		_swap_sound(e[4] != 0)
	elif mix6_wipe > 0: mix6_wipe -= 1
	mix6_flip = e[2]; mix6_pos = (e[1] as Vector2) - (e[3] as Vector2)
	x6s_kind = e[11][0] if e[4] == 4 else 0; x6s_f = e[11][1] if e[4] == 4 else -1; x6s_fxf = e[11][2] if e[4] == 4 else -1
	if x6s_node:
		x6s_objs.clear()
		for o in e[12]: x6s_objs.append([Vector2(o[0], o[1]) - (e[3] as Vector2), o[2] >> 8, o[2] & 0xFF, o[3] != 0])
		x6s_node.queue_redraw()
	mix6_fly_f = e[5] if e[4] == 2 else -1
	mix6_fly_jet = e[6] if e[4] == 2 else -1
	mix6_variant = e[8][0]
	mix6_giga_on = e[9][0] and e[4] == 2
	mix6_giga_fxf = e[9][1] if mix6_giga_on else -1
	if mix6_laser_atl:
		mix6_lasers.clear()
		for o in e[9][2]: mix6_lasers.append([Vector2(o[0], o[1]) - (e[3] as Vector2), o[2]])
		mix6_laser_node.queue_redraw()
	if mix6_shot_atl:
		mix6_shots.clear()
		for o in e[7]: mix6_shots.append([Vector2(o[0], o[1]) - (e[3] as Vector2), o[2] & 0xFF, o[3] != 0])
		mix6_cfx = e[8][1]; mix6_relf = e[8][2]
		mix6_shot_node.queue_redraw()
	mix6_f = e[0] if e[0] >= 0 else mix6_last_c
	mix6_sab_f = e[13] if e[4] == 5 else -1
	if (e[4] == 0 or e[4] == 3 or e[4] == 5) and not shown and mix6_wipe <= 0: mix6_f = -1; mix6_sab_f = -1   # o X piscou/sumiu no jogo (dano)
	# escudo (Fourth X4) em volta do X e alvo da Marca da presa no inimigo (mesmo atraso de 2 quadros da tela)
	var hb2: Array = e[10]
	var mk := Vector2(-99999, -99999) if hb2[2] < -50000 else Vector2(hb2[2], hb2[3]) - (e[3] as Vector2)
	var dv: int = hb2[6]
	if dv > 0x7FFFFFFF: dv -= 0x100000000
	hab_objs.clear()
	for o in hb2[7]: hab_objs.append([Vector2(o[0], o[1]) - (e[3] as Vector2), o[2] >> 8, o[2] & 0xFF])
	_hab_set(hb2[0], hb2[1], mix6_pos, mix6 == 1, mk, hb2[4] != 0, hb2[5], dv, not mix6_flip)
	if mix6_group:
		mix6_group.self_modulate = Color(1, 1, 1, HAB_PROT_A) if hb2[4] != 0 and e[4] != 1 else Color.WHITE
		# Mergulho: o X na pose do dash (quadro 73) inclinado com o nariz para baixo
		if dv >= 0 and e[4] == 0 and mix6_f >= 0: mix6_f = 73
		_hab_dive_tilt(mix6_group, mix6_pos, not mix6_flip, dv >= 0 and e[4] == 0)
	mix6_node.queue_redraw(); mix6_add_node.queue_redraw()

# quadro do desenho completo do golpe da perna (mesma numeração do X4):
# Falcon: voo 300+t desde o começo. Blade: parado 400+t (subestado +6 = 0), andando 420+t frente, 440+t cima,
# 460+t baixo; a direção sai do deslocamento desde que começou a andar (o jogo às vezes só anda a cada 3 quadros,
# então a velocidade de um quadro não serve). -1 = parado demais andando (fim do dash no chão).
var mix6_fly_add: SpriteAtlas = null
var mix6_arms_native := false   # braço = armadura carregada: o golpe do braço mostra o X do jogo (transforma)
var mix6_add_node: Node2D
var mix6_fly_start := Vector2.ZERO
var mix6_fly_still := 0
func _mix6_fly_frame(world: Vector2, sub: int, k: int) -> int:
	var ph := 300
	if mix6_fly_kind == "Blade_X6":
		# capturado do X6: parado 500+t, frente 520+t, cima 540+t, baixo 560+t. Direção pelo quadro do jogo:
		# cima 68/70/73, frente 69/72/75, baixo 69/71/74 (o primeiro quadro andando de frente e de baixo é igual)
		if sub == 0: ph = 500
		else:
			if mix6_fly_phase < 520: ph = 520; mix6_fly_still = 0
			else: ph = mix6_fly_phase
			if k == 68 or k == 70 or k == 73: ph = 540
			elif k == 71 or k == 74: ph = 560
			if world == mix6_fly_prev: mix6_fly_still += 1
			else: mix6_fly_still = 0
			if mix6_fly_still >= 2:   # andando mas parado (bateu em algo): o desenho capturado não serve, volta às peças
				mix6_fly_prev = world; return -1
	mix6_fly_prev = world
	if ph != mix6_fly_phase:
		var keep := mix6_fly_phase == 520 and (ph == 540 or ph == 560)   # descobriu a direção: mesmo tempo
		mix6_fly_phase = ph
		if not keep: mix6_fly_t = 0
		else: mix6_fly_t += 1
	else: mix6_fly_t += 1
	# cada fase tem os seus quadros em ph..ph+19 (capturados em sequência): nunca passa para a fase seguinte
	# (antes, segurando o botão do dash, a espera corria para os quadros do dash para frente/cima/baixo)
	var span := 20 if mix6_fly_kind == "Blade_X6" else 100   # (voo da Falcon: 300..325 numa fase só)
	var last := ph
	while last + 1 < ph + span and mix6_fly_atl.has_frame(last + 1): last += 1
	var f := ph + mix6_fly_t
	if f > last:
		# espera segurando o botão (sem limite) e dash para baixo (vai até o chão): repete os 4 últimos quadros
		if (ph == 500 or ph == 560) and last - ph >= 4: f = last - 3 + (mix6_fly_t - (last - ph) - 1) % 4
		else: f = last
	if not mix6_fly_atl.has_frame(f):
		for alt in [520, 500, 300]:
			if mix6_fly_atl.has_frame(alt): return alt
	return f

func _mix6_log_add(r: Array) -> void:
	mix6_log.append(" ".join(r.map(func(v): return str(v))))
	if mix6_log.size() > 1200: mix6_log.pop_front()   # últimos 20 s
	mix6_log_n += 1
	if mix6_log_n % 300 == 0: _mix6_log_flush()

func _mix6_log_flush() -> void:
	if mix6_log.is_empty(): return
	var f := FileAccess.open("user://mix6_registro.txt", FileAccess.WRITE)
	if f == null: return
	f.store_string("# quadro acao sub k x y modo quadro_golpe fase t virado  (acao/k em decimal; modo 0 peças, 1 X do jogo, 2 golpe desenhado)\n" + "\n".join(mix6_log) + "\n")
	f.close()

func _mix6_draw_add() -> void:   # rastro somado (como o PS1 desenha)
	var e: Array = mix6_hist[mix6_hist.size() - 3] if mix6_hist.size() >= 3 else []
	if mix6_fly_add and not e.is_empty() and e[4] == 2 and mix6_fly_f >= 0 and not mix6_giga_on:
		mix6_fly_add.draw(mix6_add_node, mix6_fly_f, mix6_pos, mix6_flip != mix6_fly_flipinv)
	if x6s_add and not e.is_empty() and e[4] == 4 and x6s_kind == 2 and x6s_f >= 0 and x6s_add.has_frame(x6s_f):
		x6s_add.draw(mix6_add_node, x6s_f, mix6_pos, not mix6_flip)   # rastro do dash da Blade (capturado olhando para a direita)

func _mix6_draw() -> void:
	var e: Array = mix6_hist[mix6_hist.size() - 3] if mix6_hist.size() >= 3 else []
	if e.is_empty(): return
	var mode: int = e[4]
	var big := 1e6
	var wiping := mix6_wipe > 0 and mix6_wipe_to == mode
	var edge := big
	var r := Rect2()
	if wiping:
		r = _mix6_rect(mode).grow_individual(0, 2, 0, 2)
		edge = r.position.y + (1.0 - float(mix6_wipe) / float(MIX6_WIPE)) * r.size.y
	if mode == 2:
		if mix6_fly_f < 0: return
		_mix6_body_fly(Color.WHITE, -big, edge)
		if wiping: _mix6_body_fly(Color(6, 6, 7), edge, big)
		elif mix6_giga_on:
			if mix6_giga_fx and mix6_giga_fxf >= 0 and mix6_giga_fx.has_frame(mix6_giga_fxf):
				mix6_giga_fx.draw(mix6_node, mix6_giga_fxf, mix6_pos, mix6_flip)   # efeito do Giga da Gaea, por cima do X
		elif mix6_fly_fx and mix6_fly_jet >= 0 and mix6_fly_fx.has_frame(mix6_fly_jet):
			mix6_fly_fx.draw(mix6_node, mix6_fly_jet, mix6_pos, mix6_flip)   # jato por cima, como no X5
	elif mode == 1:
		# X do jogo à mostra: na troca, o X branco por cima vai sumindo de cima para baixo e revela o X do jogo
		if not wiping or mix6_f < 0: return
		_mix6_body_parts(Color(6, 6, 7), edge, big)
	elif mode == 3:
		if mix6_f < 0: return
		_mix6_body_hover(Color.WHITE, -big, edge)
		if wiping: _mix6_body_hover(Color(6, 6, 7), edge, big)
	elif mode == 4:   # golpe das peças da Blade/Shadow do X6 no X5
		if x6s_f < 0: return
		_x6s_body(Color.WHITE, -big, edge)
		if wiping: _x6s_body(Color(6, 6, 7), edge, big)
		elif x6s_kind == 3 and x6s_fx and x6s_fxf >= 0 and x6s_fx.has_frame(x6s_fxf):
			x6s_fx.draw(mix6_node, x6s_fxf, mix6_pos, mix6_flip)   # lua/arco do Engetsurin por cima do X
	elif mode == 5:
		if mix6_sab_f < 0: return
		_mix6_body_sabre(Color.WHITE, -big, edge)
		if wiping: _mix6_body_sabre(Color(6, 6, 7), edge, big)
	else:
		if mix6_f < 0: return
		_mix6_body_parts(Color.WHITE, -big, edge)
		if wiping: _mix6_body_parts(Color(6, 6, 7), edge, big)
	if wiping and r.size.y > 0: _mix6_wipe_band(r, edge)

func _mix6_body_sabre(mod: Color, y0: float, y1: float) -> void:
	for a: SpriteAtlas in [mix6_sab_base, mix6_sab_pernas, mix6_sab_resto]:
		if a != null and a.has_frame(mix6_sab_f): a.draw_clip(mix6_node, mix6_sab_f, mix6_pos, mix6_flip, mod, 0, y0, y1)

# flutuar com pernas Fourth: o X sem armadura + as 4 peças da Fourth das pernas (elas têm os quadros do flutuar de verdade)
var mix6_hover_atl := {}
func _mix6_body_hover(mod: Color, y0: float, y1: float) -> void:
	var fv := mix6_variant if mod == Color.WHITE else 0
	mix6_atl["base"].draw_clip(mix6_node, mix6_f, mix6_pos, mix6_flip, mod, fv, y0, y1)
	for p in SKIN_PARTS:
		if mix6_hover_atl.has(p): mix6_hover_atl[p].draw_clip(mix6_node, mix6_f, mix6_pos, mix6_flip, mod, fv, y0, y1)

func _mix6_body_parts(mod: Color, y0: float, y1: float) -> void:
	var fv := mix6_variant if mod == Color.WHITE else 0
	mix6_atl["base"].draw_clip(mix6_node, mix6_f, mix6_pos, mix6_flip, mod, fv, y0, y1)
	for p in SKIN_PARTS:
		if not mix6_atl.has(p): continue
		var e := _mix6_part_frame(p, mix6_f)
		if e.is_empty(): continue
		var d: Vector2 = e[1]
		if mix6_flip: d.x = -d.x
		mix6_atl[p].draw_clip(mix6_node, e[0], mix6_pos + d, mix6_flip, mod, fv, y0, y1)

# quadro de uma peça: o próprio, ou (peça do X6 no Hover/Nova, que o X6 não desenhou para ela) a pose parecida da
# tabela hover_x6.json no lugar certo, igual ao X4 (_part_ok). [quadro, deslocamento] ou [] (a peça não aparece)
var mix6_src := {}
func _mix6_part_frame(p: String, f: int) -> Array:
	var a: SpriteAtlas = mix6_atl[p]
	var x6p := str(mix6_src.get(p, "")).ends_with("_X6")
	if a.has_frame(f) and not (x6p and f >= 202 and f <= 221): return [f, Vector2.ZERO]
	var e: Array = hover_x6.get(p, {}).get(str(f), [])
	if e.size() >= 3 and a.has_frame(int(e[0])): return [int(e[0]), Vector2(float(e[1]), float(e[2]))]
	return [f, Vector2.ZERO] if a.has_frame(f) else []

func _mix6_body_fly(mod: Color, y0: float, y1: float) -> void:
	if mix6_giga_on:   # Giga do X5: desenho do X5 (olha para a esquerda como as peças)
		mix6_giga_atl.draw_clip(mix6_node, mix6_fly_f, mix6_pos, mix6_flip, mod, mix6_variant if mod == Color.WHITE else 0, y0, y1)
		return
	mix6_fly_atl.draw_clip(mix6_node, mix6_fly_f, mix6_pos, mix6_flip != mix6_fly_flipinv, mod, mix6_variant if mod == Color.WHITE else 0, y0, y1)

# retângulo na tela do que está sendo desenhado (para a faixa da troca)
func _mix6_rect(mode: int) -> Rect2:
	var atl: SpriteAtlas = (mix6_giga_atl if mix6_giga_on else mix6_fly_atl) if mode == 2 else mix6_atl.get("base")
	var i := mix6_fly_f if mode == 2 else mix6_f
	var flip := (mix6_flip != (mix6_fly_flipinv and not mix6_giga_on)) if mode == 2 else mix6_flip
	if mode == 4: atl = x6s_atl.get(x6s_kind); i = x6s_f; flip = mix6_flip != (x6s_kind == 2)
	if mode == 5: atl = mix6_sab_base; i = mix6_sab_f; flip = mix6_flip
	if atl == null or not atl.has_frame(i): return Rect2()
	var fr: Dictionary = atl.frames[i]
	var x0 := mix6_pos.x - float(fr["ox"]) if not flip else mix6_pos.x + float(fr["ox"]) - float(fr["w"])
	return Rect2(x0, mix6_pos.y - float(fr["oy"]), float(fr["w"]), float(fr["h"]))

func _mix6_wipe_band(r: Rect2, edge: float) -> void:   # faixa de luz e faíscas da troca (as mesmas do X4)
	var w := r.size.x + 10.0
	mix6_node.draw_rect(Rect2(r.position.x - 5, edge - 2, w, 4), Color(0.55, 0.85, 1.0, 0.55))
	mix6_node.draw_rect(Rect2(r.position.x - 5, edge - 1, w, 1), Color(1, 1, 1, 0.95))
	for k in 4:
		var sx := r.position.x - 4 + fmod(float(k * 37 + mix6_wipe * 23), w + 8)
		var sy := edge + (float((k * 13 + mix6_wipe * 7) % 9) - 4.0)
		var sz := 2.0 if (k + mix6_wipe) % 2 == 0 else 1.0
		mix6_node.draw_rect(Rect2(sx - sz, sy, sz * 2 + 1, 1), Color.WHITE)
		mix6_node.draw_rect(Rect2(sx, sy - sz, 1, sz * 2 + 1), Color.WHITE)

# imagem pronta da recompilação (RGB8 com largura/altura na frente)
# escurecimento da tela do X5/X6 (pausa, entrar e sair das fases): o que o fangame desenha por cima (X das peças, golpes,
# habilidades, Zero) escurece junto. 0 = normal, 255 = preto (X6 0x800C885E, X5 0x800CD590: achados comparando a RAM
# quadro a quadro em volta do Start). A imagem do jogo mostra o valor de 3 quadros atrás (medido nas fotos da tela).
# O PS1 subtrai o valor de cada cor (as cores do X, ~160 de brilho, somem antes do preto total): a conta imita isso.
const RC_FADE := {"x6": 0xC885E, "x5": 0xCD590}
var rc_fade_hist := [0, 0, 0, 0]
func _rc_fade_step() -> void:
	if not RC_FADE.has(game): return
	rc_fade_hist.push_back(int(ClassDB.class_call_static(core, "mem", RC_FADE[game], 0, 1)))
	rc_fade_hist.pop_front()
	var f := clampf(1.0 - float(rc_fade_hist[0]) / 160.0, 0.0, 1.0)
	var col := Color(f, f, f, 1.0)
	for ch in get_children():
		if ch is CanvasItem and ch != tela: (ch as CanvasItem).modulate = col

func _tela_update() -> void:
	var d: PackedByteArray = ClassDB.class_call_static(core, "screen")
	if d.size() < 8: return
	var w := d[0] | (d[1] << 8); var h := d[2] | (d[3] << 8)
	if w <= 0 or h <= 0 or d.size() < 4 + w * h * 3: return
	var px := d.slice(4, 4 + w * h * 3)
	if tela == null:
		tela = Sprite2D.new(); tela.centered = false; tela.z_index = 0; add_child(tela)
		tela.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if tela_img == null or tela_img.get_width() != w or tela_img.get_height() != h:
		tela_img = Image.create_from_data(w, h, false, Image.FORMAT_RGB8, px)
		tela_tex = ImageTexture.create_from_image(tela_img)
		tela.texture = tela_tex
	else:
		tela_img.set_data(w, h, false, Image.FORMAT_RGB8, px)
		tela_tex.update(tela_img)
	tela.scale = Vector2(320.0 / w, 240.0 / h)   # 256/368/512/640 de largura: sempre ocupa a tela 320x240

func _clear() -> void:
	V = PackedVector2Array(); U = PackedVector2Array(); C = PackedColorArray(); C0 = PackedFloat32Array(); I = PackedInt32Array()

func _mat(sh: Shader, sel: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("vram", vram_tex)
	m.set_shader_parameter("pass_sel", sel)
	return m

func _inst() -> MeshInstance2D:
	if used >= pool.size():
		var mi := MeshInstance2D.new()
		add_child(mi)
		pool.append(mi)
	var inst: MeshInstance2D = pool[used]
	used += 1
	inst.visible = true
	inst.z_index = used
	return inst

func _flush(mode: int) -> void:
	var inst := _inst()
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_TEX_UV] = U; arr[Mesh.ARRAY_COLOR] = C
	arr[Mesh.ARRAY_CUSTOM0] = C0; arr[Mesh.ARRAY_INDEX] = I
	var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	_clear()
	if mode < 0:
		inst.material = mats[-1]
		inst.mesh = am
		return
	inst.material = mats[10 + mode]
	inst.mesh = am
	var i2 := _inst()
	i2.material = mats[20 + mode]
	i2.mesh = am

# ---- co-op online (scripts/coop.gd): cada PC roda o próprio jogo; o parceiro aparece por cima da imagem do jogo e o
# chefe fica com a menor vida dos dois (x4_mem 0x1F900900: leitura tipo << 8 | vida, escrita abaixa a vida; 0x1F900901
# golpe final quando o chefe do parceiro caiu). Estado mandado a cada quadro:
# [versão, jogo, área (fase * 256 + subfase, -1 fora do jogo), x, y (mundo), quadro, banco, bandeiras (1 direita,
#  2 desenhado, 4 piscando), vida, vida máxima, tipo do chefe, vida do chefe, chefe pronto, personagem, contador,
#  golpes (PackedInt32Array, 6 por golpe: id | número << 8 | direita << 16, x, y, caixa, bytes da caixa,
#  quadro | desenho << 16 | banco << 17)]
# Golpes: os do parceiro viram fantasmas aqui (x4_mem 0x1F900980: caixa dele com a arma dele, acertam os inimigos deste
# PC com o dano/fraquezas da arma dele) e são desenhados por cima (arcos do sabre do atlas do Zero, tiros do X do
# assets/x/fx, outros como brilho na caixa).
var coop_node: Node2D
var coop_base: SpriteAtlas                # X sem armadura (quadros canônicos das peças)
var coop_parts := {}                      # peça -> atlas da armadura do parceiro
var coop_zero := {}                       # banco -> atlas do Zero deste jogo
var coop_cmap := {}                       # quadro do X deste jogo -> quadro canônico
var coop_look_key := ""
var coop_mat: ShaderMaterial              # cores do Black/Nightmare Zero do parceiro (troca cor a cor da paleta normal)
var coop_cams := []                       # câmera local dos últimos quadros (a imagem da recompilação vem 2 quadros atrás)
var coop_tick := 0
var coop_look_sent := false
var coop_bhp := -1; var coop_btype := -1; var coop_brise := 0   # chefe local: vida, tipo, quando a vida subiu (enchendo)
var coop_kill_done := false
var coop_bdead := 0
var coop_msg := ""; var coop_msg_t := 0
var coop_area := -1                       # área daqui neste quadro
var coop_ghost_on := [false, false, false, false, false, false, false, false]
var coop_fxmap := {}                      # X4: quadro do banco dos tiros do X -> quadro de assets/x/fx
var coop_last_f := -1; var coop_last_b := 0; var coop_hide := 0   # último quadro desenhado do parceiro; quadros sem desenho
const COOP_NORM := [0x0000, 0xBB08, 0x95E3, 0xFE00, 0xB5BD, 0x805E, 0x8012, 0x800C, 0xFBDE, 0xE6D5, 0xC1AC, 0xA4A4, 0xCB1E, 0xB219, 0xA173, 0x9F3D]
const COOP_BZ := [0x0000, 0xCF25, 0xB5A3, 0xE16A, 0xC210, 0xA529, 0x98C6, 0x8C63, 0xFBDE, 0xE2D5, 0xBDAC, 0x9CA4, 0xCB1E, 0xB635, 0xA98F, 0xCEF9]
const COOP_NZ := [0x0000, 0xBB66, 0xBB66, 0xBB66, 0xE657, 0xDDB3, 0xD90F, 0xC88B, 0xEF1C, 0xF30C, 0xDDCB, 0xC88B, 0xE69A, 0xE1D8, 0xD575, 0xE238]
const COOP_ARMOR := {"x5": {1: "Fourth_X5", 2: "Falcon_X5", 3: "Gaea_X5", 4: "Ultimate_X5"},
	"x6": {1: "Falcon_X6", 2: "Shadow_X6", 3: "Blade_X6", 4: "Ultimate_X6"}}

func _coop_m(a: int, n: int) -> int:
	return int(ClassDB.class_call_static(core, "mem", a, 0, n))

func _coop_w(a: int, v: int) -> int:
	return int(ClassDB.class_call_static(core, "mem", a, v, -4))

func _s8(v: int) -> int:
	v &= 0xFF
	return v - 0x100 if v > 0x7F else v

# golpes daqui (objetos com caixa contra os inimigos), 6 números por golpe (fg_coop_query / coop_query 0x1F900910)
func _coop_attacks() -> PackedInt32Array:
	var r := PackedInt32Array()
	var n := mini(_coop_m(0x1F900910, 4), 8)
	for i in n:
		for f in 6: r.append(_coop_m(0x1F900911 + i * 8 + f, 4))
	return r

# golpes do parceiro aqui: fantasmas renovados a cada quadro (somem sozinhos sem renovar); X4: no máximo 5 (o banco de
# tiros tem 16 vagas e os golpes do jogador daqui vêm primeiro)
func _coop_ghosts(pa: PackedInt32Array) -> void:
	var n := mini(pa.size() / 6, 5 if game == "x4" else 8)
	for i in 8:
		if i < n:
			var b := i * 6
			var f0 := pa[b]
			_coop_w(0x1F900990, f0 & 0xFF); _coop_w(0x1F900991, (f0 >> 8) & 0xFF); _coop_w(0x1F900992, (f0 >> 16) & 1)
			_coop_w(0x1F900993, pa[b + 1]); _coop_w(0x1F900994, pa[b + 2])
			_coop_w(0x1F900995, pa[b + 3] & 0xFFFFFFFF); _coop_w(0x1F900996, pa[b + 4] & 0xFFFFFFFF); _coop_w(0x1F900997, (f0 >> 24) & 0xFF)
			coop_ghost_on[i] = _coop_w(0x1F900980 + i, 1) == 1
		elif coop_ghost_on[i]:
			_coop_w(0x1F900980 + i, 0); coop_ghost_on[i] = false

func _coop_cam() -> Vector2:
	if game == "x4": return Vector2(_s32(_coop_m(0x1F9007FC, 4)), _s32(_coop_m(0x1F9007FD, 4)))
	var x5 := game == "x5"
	var P := 0x9A0A0 if x5 else X6_P
	var ca := (0x9A1F8 if x5 else 0x971F8) + _coop_m(P + 0x14, 1) * 0x54
	return Vector2(_s16(_coop_m(ca + 0xA, 2)), _s16(_coop_m(ca + 0xE, 2)))

# estado do jogador daqui (sem o cabeçalho)
func _coop_local() -> Array:
	var bi := _coop_m(0x1F900900, 4)
	if bi > 0x7FFFFFFF: bi -= 0x100000000
	var bt := (bi >> 8) & 0xFF if bi >= 0 else -1
	var bh := bi & 0xFF if bi >= 0 else -1
	if game == "x4":
		var play := _coop_m(0, 1) == 6 and _coop_m(1, 1) != 2
		var fl := (1 if _coop_m(12, 4) != 0 else 0) | (2 if _coop_m(18, 1) == 1 else 0) | (4 if _coop_m(15, 1) > 0 else 0)
		return [_coop_m(2, 1) * 256 + _coop_m(3, 1) if play else -1, _s16(_coop_m(51, 4) & 0xFFFF), _s16(_coop_m(52, 4) & 0xFFFF),
			_coop_m(11, 4), _coop_m(0x1F9007FF, 4), fl, _coop_m(21, 1) & 0x7F, _coop_m(30, 1), bt, bh, 0, _coop_m(4, 1)]
	var x5 := game == "x5"
	var P := 0x9A0A0 if x5 else X6_P
	var gst := 0xD1C00 if x5 else 0xCCED0
	var g0 := _coop_m(gst, 2)
	var play6 := (g0 & 0xFF) == 10 and (g0 >> 8) != 2
	var hp := _coop_m(P + 0x5C, 1) & 0x7F
	var fl6 := (1 if (_coop_m(P + 0x15, 1) & 0x40) != 0 else 0) | (2 if _coop_m(P, 1) != 0 and hp > 0 and _coop_m(P + 5, 1) != 0 else 0) | (4 if _coop_m(P + 0x61, 1) > 0 else 0)
	return [_coop_m(gst + 0xC, 1) * 256 + _coop_m(gst + 0xD, 1) if play6 else -1, _s16(_coop_m(P + 0xA, 2)), _s16(_coop_m(P + 0xE, 2)),
		_coop_m(P + 0x47, 1), 0, fl6, hp, _coop_m(P + 0x5E, 1) & 0x7F, bt, bh, 0, _coop_m(P + 2, 1)]

# aparência: X com as peças (pastas canônicas) ou Zero com Black/Nightmare Zero (quantas peças)
func _coop_look() -> Dictionary:
	var ch := int(L.get("char", 0))
	var lk := {"char": ch, "game": game}
	var nbits := func(v: int) -> int: return (v & 1) + ((v >> 1) & 1) + ((v >> 2) & 1) + ((v >> 3) & 1)
	if ch == 1:
		lk["bz"] = nbits.call(int(L.get("bz", 0))); lk["nz"] = nbits.call(int(L.get("nz", 0)))
		if game == "x4" and L.get("secret", false) and lk.bz == 0: lk["bz"] = 4   # (X4: Black Zero do código secreto)
		return lk
	var pr := {}
	var lp: Dictionary = L.get("parts", {})
	if not lp.is_empty():
		for p in SKIN_PARTS: pr[p] = FangameParts.asset(str(lp.get(p, "")))
	elif game == "x4":
		var sk := str(L.get("skin", ""))
		if sk == "" and L.get("secret", false): sk = "Ultimate_X4"
		for p in SKIN_PARTS: pr[p] = sk
	else:
		var a: String = COOP_ARMOR.get(game, {}).get(int(L.get("armor", 0)), "")
		for p in SKIN_PARTS: pr[p] = a
	lk["parts"] = pr
	return lk

func _coop_step() -> void:
	if not Coop.on() or preload_mode:
		if coop_node: coop_node.visible = false
		return
	var c := Coop.me
	coop_tick += 1
	var me := _coop_local()
	coop_area = me[0]
	# chefe: pronto quando a vida parou de subir (o HUD enche a barra na chegada); depois de cair continua "vida 0" 1,5 s
	if me[8] < 0 and coop_btype >= 0 and coop_bhp == 0 and coop_bdead < 90:
		coop_bdead += 1; me[8] = coop_btype; me[9] = 0
	elif me[8] >= 0: coop_bdead = 0
	if me[8] != coop_btype: coop_btype = me[8]; coop_bhp = -1; coop_kill_done = false
	if me[9] > coop_bhp: coop_brise = coop_tick
	coop_bhp = me[9]
	me[10] = 1 if me[8] >= 0 and coop_tick - coop_brise > 45 else 0
	coop_cams.append(_coop_cam())
	if coop_cams.size() > 4: coop_cams.pop_front()
	c.send_state([Coop.VER, game] + me + [coop_tick, _coop_attacks() if me[0] >= 0 else PackedInt32Array()])
	if not coop_look_sent: c.send_look(_coop_look()); coop_look_sent = true
	# a vida do chefe: a menor das duas; o do parceiro caiu = golpe final aqui
	var ps: Array = c.st
	var same: bool = c.fresh() and ps.size() >= 15 and str(ps[1]) == game and int(ps[2]) == me[0] and me[0] >= 0
	# golpes do parceiro: só com o estado dele recente (sem renovar, somem em 3 quadros)
	var pa := PackedInt32Array()
	if same and ps.size() > 15 and ps[15] is PackedInt32Array and Time.get_ticks_msec() - c.st_ms < 150: pa = ps[15]
	_coop_ghosts(pa)
	if same:
		if me[10] == 1 and int(ps[12]) == 1 and int(ps[10]) == me[8]:
			var ph := int(ps[11])
			if ph < me[9]:
				if ph > 0: ClassDB.class_call_static(core, "mem", 0x1F900900, ph, -4)
				elif not coop_kill_done:
					coop_kill_done = int(ClassDB.class_call_static(core, "mem", 0x1F900901, 1, -4)) == 1
					if coop_kill_done: print("co-op: o parceiro venceu o chefe: golpe final aqui")
	while not c.events.is_empty():
		var ev: Dictionary = c.events.pop_front()
		if str(ev.get("e", "")) == "saiu": coop_msg = "%s voltou para o hub" % Coop.tag(not Coop.is_host()); coop_msg_t = 180
	if coop_msg_t > 0: coop_msg_t -= 1
	if coop_node == null:
		coop_node = Node2D.new(); coop_node.z_index = 2; add_child(coop_node); coop_node.draw.connect(_coop_draw)
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform vec3 src[15];\nuniform vec3 dst[15];\nuniform bool on = false;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tvec3 o = c.rgb;\n\tif (on) { for (int i = 0; i < 15; i++) { if (distance(c.rgb, src[i]) < 0.01) { o = dst[i]; break; } } }\n\tCOLOR = vec4(o, c.a) * COLOR;\n}\n"
		coop_mat = ShaderMaterial.new(); coop_mat.shader = sh
	coop_node.visible = true
	_coop_prepare(c.look)
	coop_node.queue_redraw()

# atlas do parceiro (quando a aparência dele chega/muda)
func _coop_prepare(lk: Dictionary) -> void:
	var key := str(lk)
	if key == coop_look_key: return
	coop_look_key = key
	coop_parts = {}; coop_zero = {}; coop_last_f = -1
	coop_mat.set_shader_parameter("on", false)
	coop_node.material = null
	if lk.is_empty(): return
	if int(lk.get("char", 0)) == 1:
		if game == "x4":
			coop_zero[0] = SpriteAtlas.load_from("res://assets/zero"); coop_zero[1] = SpriteAtlas.load_from("res://assets/zero/bank1")
		else: coop_zero[0] = SpriteAtlas.load_from("res://assets/zero/" + game)
		var nb := int(lk.get("bz", 0)); var nn := int(lk.get("nz", 0))
		if nb > 0 or nn > 0:
			var W: int = [0, 40, 65, 85, 100][clampi(maxi(nb, nn), 0, 4)]
			var tgt: Array = COOP_NZ if nn > 0 else COOP_BZ
			var src := PackedVector3Array(); var dst := PackedVector3Array()
			for i in range(1, 16):
				var a: int = COOP_NORM[i]; var b: int = tgt[i]; var o := 0
				for sh in [0, 5, 10]:
					o |= int((((a >> sh) & 31) * (100 - W) + ((b >> sh) & 31) * W + 50) / 100) << sh
				src.append(Vector3(((a & 31) << 3) / 255.0, (((a >> 5) & 31) << 3) / 255.0, (((a >> 10) & 31) << 3) / 255.0))
				dst.append(Vector3(((o & 31) << 3) / 255.0, (((o >> 5) & 31) << 3) / 255.0, (((o >> 10) & 31) << 3) / 255.0))
			coop_mat.set_shader_parameter("src", src); coop_mat.set_shader_parameter("dst", dst)
			coop_mat.set_shader_parameter("on", true)
			coop_node.material = coop_mat
		return
	if coop_base == null:
		coop_base = SpriteAtlas.load_from("res://assets/x/parts/body")
		var cj = JSON.parse_string(FileAccess.get_file_as_string("res://assets/x/parts/canonical.json"))
		if cj is Dictionary and cj.get("game_to_canonical", {}).has(game):
			var gm: Dictionary = cj["game_to_canonical"][game]
			for k in gm: coop_cmap[int(k)] = int(gm[k])
	var pr: Dictionary = lk.get("parts", {})
	for p in SKIN_PARTS:
		var a := str(pr.get(p, ""))
		if a == "": continue
		var at := _atl(a, p)
		if at: coop_parts[p] = at

# corpo do parceiro no quadro f (false = os atlas não têm esse quadro)
func _coop_body(f: int, bk: int, pos: Vector2, right: bool, ch: int) -> bool:
	if ch == 1:
		var za: SpriteAtlas = coop_zero.get(bk if coop_zero.has(bk) else 0)
		if za == null or not za.has_frame(f): return false
		za.draw(coop_node, f, pos, right)
		return true
	if coop_base == null or not coop_cmap.has(f): return false
	var cf: int = coop_cmap[f]
	if not coop_base.has_frame(cf): return false
	coop_base.draw(coop_node, cf, pos, right)
	for p in SKIN_PARTS:
		var at: SpriteAtlas = coop_parts.get(p)
		if at and at.has_frame(cf): at.draw(coop_node, cf, pos, right)
	return true

# golpes do parceiro: Zero = arcos do sabre (e outros golpes no banco dele) do atlas do Zero; X = limão (0), meia carga (9)
# e carga cheia (18) do assets/x/fx (X4: o quadro exato do banco dos tiros); outros = brilho na caixa
func _coop_draw_attacks(pa: PackedInt32Array, cam: Vector2, ch: int) -> void:
	if coop_fxmap.is_empty():
		Fx.atlas()
		for nm in Fx._names:
			var parts := str(nm).split("_")
			if parts.size() == 2 and parts[0] in ["lemon", "semi", "full", "glow"]: coop_fxmap[parts[1].hex_to_int()] = int(Fx._names[nm])
	var col := Color(1.0, 0.62, 0.2, 0.45) if Coop.is_host() else Color(0.35, 0.8, 1.0, 0.45)
	for i in pa.size() / 6:
		var b := i * 6
		var f5 := pa[b + 5]
		if not (f5 & 0x10000): continue   # (só caixa: o corpo dele já mostra o golpe)
		var f0 := pa[b]
		var id := f0 & 0xFF
		var right := ((f0 >> 16) & 1) != 0
		var p := Vector2(pa[b + 1], pa[b + 2]) - cam
		if p.x < -96 or p.x > 416 or p.y < -96 or p.y > 336: continue
		var fr := f5 & 0xFFFF
		var bc := (f5 >> 17) & 7
		if ch == 1 and (bc == 1 or bc == 2 or (game != "x4" and id >= 0x18 and id <= 0x1F)):
			var za: SpriteAtlas = coop_zero.get(1 if game == "x4" and bc == 2 else 0)
			if za and za.has_frame(fr): za.draw(coop_node, fr, p, right)
			continue
		if game == "x4" and bc == 3 and coop_fxmap.has(fr):
			Fx.atlas().draw(coop_node, coop_fxmap[fr], p, right)
			continue
		var seq: Array = []
		if id == 0: seq = ["lemon_5", "lemon_6", "lemon_7", "lemon_8", "lemon_9"]
		elif id == 9: seq = ["semi_7b", "semi_7c", "semi_7d", "semi_7e"]
		elif id == 0x12: seq = ["full_26", "full_28", "full_29"]
		if not seq.is_empty():
			Fx.atlas().draw(coop_node, Fx.frame_index(seq[(coop_tick / 2) % seq.size()]), p, right)
			continue
		var bx := pa[b + 4]
		var w := (bx >> 16) & 0xFF; var h := (bx >> 24) & 0xFF
		if w == 0 or h == 0: continue
		var ctr: Vector2
		if game == "x4":   # (X4: canto de cima à esquerda; virado para a direita espelha)
			var l := _s8(bx) + w * 0.5
			ctr = p + Vector2(-l if right else l, _s8(bx >> 8) + h * 0.5)
		else:
			ctr = p + Vector2(-_s8(bx) if right else _s8(bx), _s8(bx >> 8))
		coop_node.draw_set_transform(ctr, 0.0, Vector2(w * 0.5, h * 0.5))
		coop_node.draw_circle(Vector2.ZERO, 1.0, col)
		coop_node.draw_circle(Vector2.ZERO, 0.6, Color(1, 1, 1, 0.35))
		coop_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _coop_draw() -> void:
	var c := Coop.me
	if c == null: return
	var font := ThemeDB.fallback_font
	var other := Coop.tag(not Coop.is_host())
	var col := Color(1.0, 0.62, 0.2) if Coop.is_host() else Color(0.35, 0.8, 1.0)   # P2 laranja, P1 azul
	if coop_msg_t > 0:
		coop_node.draw_string_outline(font, Vector2(0, 30), coop_msg, HORIZONTAL_ALIGNMENT_CENTER, 320, 8, 3, Color.BLACK)
		coop_node.draw_string(font, Vector2(0, 30), coop_msg, HORIZONTAL_ALIGNMENT_CENTER, 320, 8, col)
	if not c.fresh() or coop_cams.is_empty(): return
	var s: Array = c.st
	if s.size() < 15 or int(s[0]) != Coop.VER or str(s[1]) != game: return
	# vida do parceiro (topo, meio da tela)
	var hp := int(s[8]); var mhp := maxi(int(s[9]), 1)
	coop_node.draw_string_outline(font, Vector2(138, 9), other, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color.BLACK)
	coop_node.draw_string(font, Vector2(138, 9), other, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
	coop_node.draw_rect(Rect2(151, 4, 34, 4), Color(0, 0, 0, 0.8))
	coop_node.draw_rect(Rect2(152, 5, 32.0 * clampf(float(hp) / mhp, 0.0, 1.0), 2), Color(0.3, 0.95, 0.4))
	if int(s[2]) < 0 or int(s[2]) != coop_area:
		coop_node.draw_string_outline(font, Vector2(188, 9), "em outra parte", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 3, Color.BLACK)
		coop_node.draw_string(font, Vector2(188, 9), "em outra parte", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.8, 0.8, 0.8))
		return
	var cam: Vector2 = coop_cams[maxi(coop_cams.size() - 3, 0)] if recomp else coop_cams[coop_cams.size() - 1]
	var pos := Vector2(int(s[3]), int(s[4])) - cam
	var fl := int(s[7])
	var right := (fl & 1) != 0
	var on_screen := pos.x > -24 and pos.x < 344 and pos.y > -8 and pos.y < 272
	# corpo: quadros que os atlas não têm (golpes especiais, voo da Falcon...) e quadros curtos sem desenho (o jogo
	# trocando o desenho do jogador) ficam com o último quadro desenhado, em vez de sumir
	var vis := (fl & 2) != 0
	coop_hide = 0 if vis else coop_hide + 1
	if on_screen and (vis or (coop_hide < 20 and hp > 0)) and not ((fl & 4) and coop_tick % 4 < 2):
		var f := int(s[5]); var bk := int(s[6])
		if vis and _coop_body(f, bk, pos, right, int(s[13])): coop_last_f = f; coop_last_b = bk
		elif coop_last_f >= 0: _coop_body(coop_last_f, coop_last_b, pos, right, int(s[13]))
	if s.size() > 15 and s[15] is PackedInt32Array: _coop_draw_attacks(s[15], cam, int(s[13]))
	# etiqueta em cima da cabeça (ou na borda, apontando, se ele está fora da tela)
	var tp := Vector2(clampf(pos.x, 10, 310), clampf(pos.y - 44, 12, 214))
	if not on_screen:
		var d := (pos - Vector2(160, 120)).normalized()
		var tip := tp + d * 6.0
		coop_node.draw_colored_polygon(PackedVector2Array([tip, tp + d.orthogonal() * 3.0, tp - d.orthogonal() * 3.0]), col)
	coop_node.draw_string_outline(font, tp + Vector2(-6, 0), other, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color.BLACK)
	coop_node.draw_string(font, tp + Vector2(-6, 0), other, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
