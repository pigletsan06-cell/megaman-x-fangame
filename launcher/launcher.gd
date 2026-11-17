extends Control
const MmxUI := preload("res://mmx_ui.gd")   # sem class_name (pasta nova não tem o cache de classes do Godot)
## Launcher do Mega Man X Fusion: confere os discos do jogador, prepara o jogo a partir deles (arte, sons e código,
## pela receita em tools/receita.json), procura atualizações e abre o jogo.
## Desenho original: painéis no estilo dos menus do fangame, sem personagens nem arte dos jogos.
##
## Testes automáticos (argumentos depois de "--"):
##   --auto            confere os discos, prepara o que faltar, escreve gerado/relatorio_launcher.json e fecha
##   --sem-jogo        não abre o jogo no fim (com --auto)
##   --atualizar       procura atualização e aplica antes de preparar (com --auto)
##   --foto=PREFIXO    salva fotos da tela (PREFIXO_NN_nome.png) nos momentos importantes
## Variáveis: FUSION_RAIZ (pasta do pacote), FUSION_PYTHON, FUSION_GODOT, FUSION_FFMPEG, FUSION_DISCOS (pasta dos discos)

const DISCOS := [
	{"id": "x4", "nome": "Mega Man X4", "arquivo": "Mega Man X4 (USA).bin", "sha1": "26ffe24a79384b24af7571674251ee575e889b38"},
	{"id": "x5", "nome": "Mega Man X5", "arquivo": "Mega Man X5 (USA).bin", "sha1": "10709231f857636b5ccd3cd9acebc91458dcb5fd"},
	{"id": "x6", "nome": "Mega Man X6 (v1.1)", "arquivo": "Mega Man X6 (USA) (v1.1).bin", "sha1": "d4f7e08371027a87a3bf13311db5a4c56733f4ea"},
]
const C_OK := Color(0.45, 1.0, 0.55)
const C_ERR := Color(1.0, 0.45, 0.35)

var raiz := ""                 # pasta do pacote
var estado := {}               # gerado/estado.json: discos achados, chaves das etapas feitas
var receita := {}              # tools/receita.json
var versao := {}               # versao.json
var t := 0.0
var auto := false; var sem_jogo := false; var auto_upd := false; var foto := ""; var n_foto := 0

# discos: id -> {estado: "procurando"|"ok"|"faltando"|"diferente", caminho, sha1, progresso}
var discos := {}
var disco_thread: Thread
var disco_msg := ""

# etapas: [{id, nome, estado: "pendente"|"feita"|"rodando"|"erro"|"pulada", progresso, texto}]
var etapas := []
var rodando := -1              # índice da etapa rodando
var proc := {}                 # {pid, stdio, stderr}
var ler_thread: Thread; var ler_thread2: Thread
var log_linhas: PackedStringArray = []
var mutex := Mutex.new()
var fila := []                 # linhas vindas da thread de leitura
var cancelar := false
var prep_ok := false

# atualização
var http: HTTPRequest
var upd := {"estado": "", "texto": "", "nova": 0, "asset": "", "url": ""}

var cv: Control
var btn_discos: Button; var btn_preparar: Button; var btn_jogar: Button; var btn_atualizar: Button; var btn_log: Button
var dlg: FileDialog
var sfx := {}
var abre_t := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--auto": auto = true
		elif a == "--sem-jogo": sem_jogo = true
		elif a == "--atualizar": auto_upd = true
		elif a.begins_with("--foto="): foto = a.substr(7)
		elif a.begins_with("--tela="): _tela_depois(a.substr(7))   # --tela=ARQUIVO.png@SEGUNDOS: foto da tela e fecha (testes)
	raiz = ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir()
	if OS.get_environment("FUSION_RAIZ") != "": raiz = OS.get_environment("FUSION_RAIZ")
	DirAccess.make_dir_recursive_absolute(raiz.path_join("gerado"))
	estado = _ler_json(raiz.path_join("gerado/estado.json"))
	_le_receita()
	versao = _ler_json(raiz.path_join("versao.json"))
	theme = MmxUI.theme()
	var ic := Image.load_from_file(ProjectSettings.globalize_path("res://assets/icone.png"))
	if ic: DisplayServer.set_icon(ic)
	get_window().title = "Mega Man X Fusion"
	cv = _Canvas.new(); cv.fn = _desenha; cv.size = Vector2(640, 360); add_child(cv)
	btn_discos = _botao("PROCURAR DISCOS", Rect2(30, 199, 208, 17), _escolher_pasta)
	btn_atualizar = _botao("ATUALIZAR", Rect2(30, 281, 208, 15), _baixar_atualizacao)
	btn_preparar = _botao("PREPARAR", Rect2(268, 271, 124, 32), _preparar)
	btn_jogar = _botao("JOGAR", Rect2(402, 271, 220, 32), _jogar, 18)
	btn_log = _botao("ABRIR REGISTRO", Rect2(522, 318, 96, 14), _abrir_registro)
	btn_atualizar.visible = false; btn_log.visible = false
	dlg = FileDialog.new(); dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR; dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true; dlg.title = "Pasta com os discos (.bin)"
	dlg.dir_selected.connect(_pasta_escolhida); add_child(dlg)
	http = HTTPRequest.new(); http.timeout = 20.0; add_child(http)
	for s in ["menu_open", "menu_close", "menu_back", "menu_equip", "menu_error", "menu_full", "menu_tab"]:
		var p := AudioStreamPlayer.new(); add_child(p)
		var f := "res://assets/sfx/%s.wav" % s
		if FileAccess.file_exists(f): p.stream = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(f))
		sfx[s] = p
	_monta_etapas()
	_procura_discos()
	_procurar_atualizacao()
	_atualiza_botoes()

func _botao(txt: String, r: Rect2, f: Callable, fs := MmxUI.SIZE) -> Button:
	var b := Button.new(); b.text = txt; b.clip_text = true
	b.add_theme_font_override("font", MmxUI.font()); b.add_theme_font_size_override("font_size", fs)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.03, 0.09, 0.22, 0.95), "hover": Color(0.07, 0.2, 0.42), "pressed": Color(0.12, 0.3, 0.55),
			"disabled": Color(0.02, 0.04, 0.1, 0.85), "focus": Color(0, 0, 0, 0)}[st]
		sb.border_color = {"normal": MmxUI.C_EDGE_LO, "hover": MmxUI.C_SEL, "pressed": MmxUI.C_SEL, "disabled": Color(0.1, 0.16, 0.3), "focus": MmxUI.C_SEL}[st]
		sb.set_border_width_all(1)
		sb.skew = Vector2(0.25, 0)
		sb.content_margin_left = 6; sb.content_margin_right = 6; sb.content_margin_top = 1; sb.content_margin_bottom = 1
		sb.draw_center = st != "focus"
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", MmxUI.C_TEXT)
	b.add_theme_color_override("font_hover_color", MmxUI.C_SEL)
	b.add_theme_color_override("font_focus_color", MmxUI.C_SEL)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.3, 0.38, 0.55))
	b.pressed.connect(func(): _som("menu_open"); f.call())
	b.mouse_entered.connect(func(): if not b.disabled: _som("menu_tab"))
	b.focus_entered.connect(func(): _som("menu_tab"))
	add_child(b)
	# tamanho só depois da fonte e das bordas: antes disso o Godot usa a fonte padrão e o botão fica alto demais
	b.custom_minimum_size = r.size; b.position = r.position; b.size = r.size
	return b

func _som(nm: String) -> void:
	var p: AudioStreamPlayer = sfx.get(nm)
	if p and p.stream: p.play()

# ---------------- arquivos ----------------
func _ler_json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p): return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}

var receita_msg := ""          # por que não tem etapas (receita faltando ou quebrada)
func _le_receita() -> void:
	var p := raiz.path_join("tools/receita.json")
	receita = _ler_json(p)
	receita_msg = ""
	if not FileAccess.file_exists(p): receita_msg = "Receita não encontrada (tools/receita.json)."
	elif receita.is_empty(): receita_msg = "Receita quebrada (tools/receita.json não é um JSON válido)."

func _grava_estado() -> void:
	var f := FileAccess.open(raiz.path_join("gerado/estado.json"), FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(estado, " "))

func _log(s: String) -> void:
	for ln in s.split("\n"):
		if ln.strip_edges() == "": continue
		log_linhas.append(ln)
	while log_linhas.size() > 400: log_linhas.remove_at(0)
	var f := FileAccess.open(raiz.path_join("gerado/launcher.log"), FileAccess.READ_WRITE if FileAccess.file_exists(raiz.path_join("gerado/launcher.log")) else FileAccess.WRITE)
	if f:
		f.seek_end(); f.store_line("[%s] %s" % [Time.get_time_string_from_system(), s])

# ---------------- discos ----------------
func _procura_discos() -> void:
	if disco_thread and disco_thread.is_alive(): return
	for d in DISCOS: discos[d.id] = {"estado": "procurando", "caminho": "", "sha1": "", "progresso": 0.0}
	disco_msg = "Procurando os discos..."
	var pastas := []
	if OS.get_environment("FUSION_DISCOS") != "": pastas.append(OS.get_environment("FUSION_DISCOS"))
	if str(estado.get("pasta_discos", "")) != "": pastas.append(str(estado.pasta_discos))
	pastas.append_array([raiz.path_join("discos"), raiz, raiz.get_base_dir()])
	disco_thread = Thread.new()
	disco_thread.start(_procura_thread.bind(pastas, estado.get("discos", {}).duplicate(true)))

func _procura_thread(pastas: Array, cache: Dictionary) -> void:
	var novo_cache := {}
	for d in DISCOS:
		var achado := ""
		var cands := []
		for p in pastas:   # primeiro pelo nome exato, depois qualquer .bin do mesmo tamanho
			var c: String = str(p).path_join(d.arquivo)
			if FileAccess.file_exists(c): cands.append(c)
		for p in pastas:
			var da := DirAccess.open(str(p))
			if da == null: continue
			for fn in da.get_files():
				if fn.to_lower().ends_with(".bin"): cands.append(str(p).path_join(fn))
		var visto := {}
		var diferente := ""   # arquivo com o nome ou o tamanho do disco, mas outro conteúdo
		for c in cands:
			if visto.has(c): continue
			visto[c] = true
			var sz := _tamanho(c)
			var mt := FileAccess.get_modified_time(c)
			var sha := ""
			var ck: Dictionary = cache.get(c, {})
			if ck.get("tamanho", -1) == sz and ck.get("data", -1) == mt: sha = str(ck.sha1)
			elif d.arquivo != c.get_file() and not _tamanho_bate(d.id, sz): continue
			else: sha = _sha1(c, d.id)
			novo_cache[c] = {"tamanho": sz, "data": mt, "sha1": sha}
			if sha == d.sha1:
				achado = c; break
			elif diferente == "": diferente = c
		if achado != "": call_deferred("_disco_resultado", d.id, "ok", achado, d.sha1)
		elif diferente != "": call_deferred("_disco_resultado", d.id, "diferente", diferente, "")
		else: call_deferred("_disco_resultado", d.id, "faltando", "", "")
	call_deferred("_discos_fim", novo_cache)

const TAMANHOS := {"x4": 592217136, "x5": 582954960, "x6": 599985792}
func _tamanho_bate(id: String, sz: int) -> bool:
	return int(TAMANHOS.get(id, -1)) == sz

func _tamanho(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_length() if f else -1

func _sha1(p: String, id: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null: return ""
	var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_SHA1)
	var n := f.get_length(); var lido := 0
	while lido < n:
		var b := f.get_buffer(8 << 20)
		if b.is_empty(): break
		ctx.update(b); lido += b.size()
		call_deferred("_disco_progresso", id, float(lido) / float(n))
	return ctx.finish().hex_encode()

func _disco_progresso(id: String, k: float) -> void:
	discos[id].progresso = k

func _disco_resultado(id: String, st: String, caminho: String, sha: String) -> void:
	if discos[id].estado == "ok" and st != "ok": return
	discos[id] = {"estado": st, "caminho": caminho, "sha1": sha, "progresso": 1.0}

func _discos_fim(cache: Dictionary) -> void:
	disco_thread.wait_to_finish()
	var c: Dictionary = estado.get("discos", {})
	c.merge(cache, true)
	estado["discos"] = c
	var faltam := []; var errados := []
	for d in DISCOS:
		if discos[d.id].estado == "diferente": errados.append("%s (%s)" % [d.nome, str(discos[d.id].caminho).get_file()])
		elif discos[d.id].estado != "ok": faltam.append(d.nome)
	if faltam.is_empty() and errados.is_empty():
		disco_msg = "Os 3 discos conferem."
		estado["pasta_discos"] = discos.x5.caminho.get_base_dir()
		_som("menu_equip")
	else:
		var partes := []
		if not faltam.is_empty(): partes.append("Falta: " + ", ".join(faltam))
		if not errados.is_empty(): partes.append("Não é o disco certo: " + ", ".join(errados))
		disco_msg = ". ".join(partes)
		faltam.append_array(errados)
		_som("menu_error")
	_grava_estado()
	_log(disco_msg)
	_avalia_etapas()
	_atualiza_botoes()
	_foto("discos")
	if auto:
		if not faltam.is_empty(): _fim_auto(false, disco_msg)
		elif etapas.is_empty(): _fim_auto(false, receita_msg)
		elif auto_upd and upd.estado == "disponivel": _baixar_atualizacao()
		elif auto_upd and upd.estado in ["", "procurando"]: pass   # espera a resposta da atualização
		else: _preparar()

func _escolher_pasta() -> void:
	dlg.popup_centered_ratio(0.6)

func _pasta_escolhida(p: String) -> void:
	estado["pasta_discos"] = p; _grava_estado()
	_procura_discos()

# ---------------- etapas (tools/receita.json) ----------------
func _monta_etapas() -> void:
	etapas.clear()
	for e in receita.get("etapas", []):
		etapas.append({"id": str(e.id), "nome": str(e.nome), "estado": "pendente", "progresso": 0.0, "texto": "", "def": e})
	if etapas.is_empty() and receita_msg == "": receita_msg = "Receita sem etapas (tools/receita.json)."
	if receita_msg != "": _log(receita_msg)

func _vars() -> Dictionary:
	var py := raiz.path_join("python/python.exe") if OS.get_name() == "Windows" else "python3"
	if OS.get_environment("FUSION_PYTHON") != "": py = OS.get_environment("FUSION_PYTHON")
	var gd := OS.get_executable_path()
	if OS.get_environment("FUSION_GODOT") != "": gd = OS.get_environment("FUSION_GODOT")
	var ff := raiz.path_join("ferramentas/ffmpeg.exe") if OS.get_name() == "Windows" else "ffmpeg"
	if OS.get_environment("FUSION_FFMPEG") != "": ff = OS.get_environment("FUSION_FFMPEG")
	var cap := raiz.path_join("ferramentas/captura.exe") if OS.get_name() == "Windows" else raiz.path_join("ferramentas/captura")
	if OS.get_environment("FUSION_CAPTURA") != "": cap = OS.get_environment("FUSION_CAPTURA")
	# desenho das capturas: no Windows, uma cópia do Godot com o desenhista por software (Mesa llvmpipe) do lado
	var gr := raiz.path_join("ferramentas/render/godot.exe") if OS.get_name() == "Windows" else gd
	if OS.get_environment("FUSION_GODOT_RENDER") != "": gr = OS.get_environment("FUSION_GODOT_RENDER")
	# compilador do código do X4 (llvm-mingw no Windows; no Linux o clang do sistema ou FUSION_CLANG)
	var cl := raiz.path_join("ferramentas/llvm/bin/clang.exe") if OS.get_name() == "Windows" else "clang"
	var ll := raiz.path_join("ferramentas/llvm/bin/ld.lld.exe") if OS.get_name() == "Windows" else "ld.lld"
	if OS.get_environment("FUSION_CLANG") != "": cl = OS.get_environment("FUSION_CLANG")
	if OS.get_environment("FUSION_LLD") != "": ll = OS.get_environment("FUSION_LLD")
	var v := {"python": py, "godot": gd, "ffmpeg": ff, "captura": cap, "godot_render": gr, "clang": cl, "lld": ll, "raiz": raiz, "tools": raiz.path_join("tools"), "jogo": raiz.path_join("godot"),
		"gerado": raiz.path_join("gerado"), "so": OS.get_name()}
	for d in DISCOS: v["disco_" + d.id] = str(discos.get(d.id, {}).get("caminho", ""))
	return v

func _expande(s: String, v: Dictionary) -> String:
	for k in v: s = s.replace("{%s}" % k, str(v[k]))
	return s

# chave de uma etapa: discos que ela usa + conteúdo dos arquivos dela + chaves das etapas de antes de que depende
func _chave(e: Dictionary, v: Dictionary) -> String:
	var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_SHA1)
	var _u := func(b: PackedByteArray) -> void:
		if not b.is_empty(): ctx.update(b)
	_u.call(("%s|%s|" % [receita.get("versao_receita", 0), JSON.stringify(e.get("cmd", []))]).to_utf8_buffer())
	for id in e.get("discos", []):
		_u.call(("disco:" + str(discos.get(id, {}).get("sha1", ""))).to_utf8_buffer())
	for a in e.get("arquivos", []):
		for f in _lista_arquivos(_expande(str(a), v)):
			_u.call(f.trim_prefix(raiz).to_utf8_buffer())
			_u.call(FileAccess.get_file_as_bytes(f))
	var feitas: Dictionary = estado.get("etapas", {})
	for dep in e.get("depois_de", []):
		_u.call(("dep:" + str(feitas.get(dep, ""))).to_utf8_buffer())
	return ctx.finish().hex_encode()

func _lista_arquivos(p: String) -> PackedStringArray:
	var out := PackedStringArray()
	if FileAccess.file_exists(p): out.append(p); return out
	var da := DirAccess.open(p)
	if da == null: return out
	var subs := []
	for fn in da.get_files():
		if fn.ends_with(".import") or fn.ends_with(".uid") or fn.ends_with(".pyc"): continue
		out.append(p.path_join(fn))
	for dn in da.get_directories():
		if dn.begins_with(".") or dn == "__pycache__": continue
		subs.append(p.path_join(dn))
	subs.sort()
	for s in subs: out.append_array(_lista_arquivos(s))
	return out

func _avalia_etapas() -> void:
	var v := _vars()
	var feitas: Dictionary = estado.get("etapas", {})
	prep_ok = true
	for e in etapas:
		if e.estado == "rodando": continue
		var ch := _chave(e.def, v)
		e["chave"] = ch
		if feitas.get(e.id, "") == ch: e.estado = "feita"; e.progresso = 1.0
		else:
			e.estado = "pendente" if e.estado != "erro" else "erro"; e.progresso = 0.0
			prep_ok = false
	if etapas.is_empty(): prep_ok = false

func _discos_ok() -> bool:
	for d in DISCOS:
		if discos.get(d.id, {}).get("estado", "") != "ok": return false
	return true

func _preparar() -> void:
	if rodando >= 0 or not _discos_ok(): return
	cancelar = false
	_avalia_etapas()
	for e in etapas:
		if e.estado == "erro": e.estado = "pendente"
	_proxima_etapa()

func _proxima_etapa() -> void:
	var v := _vars()
	var feitas: Dictionary = estado.get("etapas", {})
	for i in etapas.size():
		var e: Dictionary = etapas[i]
		e["chave"] = _chave(e.def, v)   # sempre de novo: as etapas de antes podem ter mudado a chave desta
		if feitas.get(e.id, "") == e.chave: e.estado = "feita"; e.progresso = 1.0; continue
		_roda_etapa(i, v)
		return
	rodando = -1
	_avalia_etapas()
	_atualiza_botoes()
	if prep_ok:
		_som("menu_full"); _log("Tudo pronto!"); _foto("pronto")
		if auto: _fim_auto(true, "pronto")
	elif auto: _fim_auto(false, "etapas pendentes depois de preparar")

func _roda_etapa(i: int, v: Dictionary) -> void:
	var e: Dictionary = etapas[i]
	var cmd: Array = e.def.get("cmd", [])
	var exe := _expande(str(cmd[0]), v)
	var args := PackedStringArray()
	for a in cmd.slice(1): args.append(_expande(str(a), v))
	rodando = i; e.estado = "rodando"; e.progresso = 0.0; e.texto = "começando..."
	e["t0"] = Time.get_ticks_msec()
	_log("== %s: %s %s" % [e.nome, exe, " ".join(args)])
	var info := OS.execute_with_pipe(exe, args, true)
	if info.is_empty():
		_etapa_erro(i, "não consegui rodar: " + exe); return
	proc = info
	ler_thread = Thread.new(); ler_thread.start(_le_pipe.bind(info.stdio))
	ler_thread2 = Thread.new(); ler_thread2.start(_le_pipe.bind(info.stderr))
	_atualiza_botoes()
	_foto("etapa_" + e.id)

func _le_pipe(pipe: FileAccess) -> void:
	while pipe.is_open():
		var ln := pipe.get_line()
		if pipe.get_error() != OK and ln == "": break
		mutex.lock(); fila.append(ln); mutex.unlock()

func _processa_saida() -> void:
	mutex.lock(); var ls := fila.duplicate(); fila.clear(); mutex.unlock()
	if rodando < 0: return
	var e: Dictionary = etapas[rodando]
	for ln: String in ls:
		if ln.begins_with("@progresso "):   # "@progresso 12/40 texto"
			var r := ln.substr(11)
			var sp := r.find(" ")
			var fr := r.substr(0, sp) if sp >= 0 else r
			var ab := fr.split("/")
			if ab.size() == 2 and float(ab[1]) > 0.0: e.progresso = clampf(float(ab[0]) / float(ab[1]), 0.0, 1.0)
			if sp >= 0: e.texto = r.substr(sp + 1)
		elif ln.strip_edges() != "":
			_log(ln)

func _etapa_erro(i: int, msg: String) -> void:
	var e: Dictionary = etapas[i]
	e.estado = "erro"; e.texto = msg
	rodando = -1; proc = {}
	_log("ERRO em %s: %s" % [e.nome, msg])
	_som("menu_error")
	_atualiza_botoes()
	_foto("erro_" + e.id)
	if auto: _fim_auto(false, "%s: %s" % [e.nome, msg])

func _confere_processo() -> void:
	if rodando < 0 or proc.is_empty(): return
	var pid: int = proc.pid
	if OS.is_process_running(pid):
		if cancelar: OS.kill(pid)
		return
	# acabou: espera as threads de leitura esvaziarem os canos
	if ler_thread and ler_thread.is_started(): ler_thread.wait_to_finish()
	if ler_thread2 and ler_thread2.is_started(): ler_thread2.wait_to_finish()
	_processa_saida()
	var code := OS.get_process_exit_code(pid)
	var e: Dictionary = etapas[rodando]
	proc = {}
	if cancelar:
		_etapa_erro(rodando, "cancelada"); return
	if code != 0:
		var ult := log_linhas.slice(maxi(0, log_linhas.size() - 3))
		_etapa_erro(rodando, "saiu com erro %d (%s)" % [code, " / ".join(ult)]); return
	e.estado = "feita"; e.progresso = 1.0; e.texto = "%.1f s" % ((Time.get_ticks_msec() - int(e.t0)) / 1000.0)
	var feitas: Dictionary = estado.get("etapas", {})
	feitas[e.id] = e.chave
	estado["etapas"] = feitas
	_grava_estado()
	_log("ok: %s (%s)" % [e.nome, e.texto])
	_som("menu_equip")
	rodando = -1
	_proxima_etapa()

func _atualiza_botoes() -> void:
	var dok := _discos_ok()
	btn_discos.disabled = rodando >= 0 or (disco_thread != null and disco_thread.is_alive())
	btn_preparar.disabled = rodando >= 0 or not dok or prep_ok
	btn_preparar.text = "PREPARANDO..." if rodando >= 0 else ("TUDO PRONTO" if prep_ok else "PREPARAR")
	btn_jogar.disabled = not (dok and prep_ok) or rodando >= 0 or upd.estado == "baixando"
	btn_atualizar.visible = upd.estado == "disponivel"
	btn_atualizar.disabled = rodando >= 0
	var tem_erro := false
	for e in etapas:
		if e.estado == "erro": tem_erro = true
	btn_log.visible = tem_erro
	for b in [btn_discos, btn_preparar, btn_jogar, btn_atualizar]:
		if b.disabled and b.has_focus(): b.release_focus()
	if not btn_jogar.disabled and not btn_jogar.has_focus() and not auto: btn_jogar.grab_focus()
	elif btn_jogar.disabled and not btn_preparar.disabled and not btn_preparar.has_focus(): btn_preparar.grab_focus()

func _abrir_registro() -> void:
	OS.shell_open(raiz.path_join("gerado/launcher.log"))

func _jogar() -> void:
	if btn_jogar.disabled: return
	var v := _vars()
	var pid := OS.create_process(v.godot, PackedStringArray(["--path", v.jogo]))
	_log("abrindo o jogo (pid %d)" % pid)
	if pid > 0:
		await get_tree().create_timer(0.6).timeout
		get_tree().quit()

# ---------------- atualização (GitHub Releases) ----------------
## chave de leitura do repositório: chave.txt (só no pacote do jogador, as atualizações não mexem) ou versao.json
func _chave_repo() -> String:
	var c := raiz.path_join("chave.txt")
	if FileAccess.file_exists(c): return FileAccess.get_file_as_string(c).strip_edges()
	return str(versao.get("token", ""))

func _hdr(token: String, acc := "application/vnd.github+json") -> PackedStringArray:
	var h := PackedStringArray(["Accept: " + acc, "User-Agent: MegaManXFusion-Launcher", "X-GitHub-Api-Version: 2022-11-28"])
	if token != "": h.append("Authorization: Bearer " + token)
	return h

func _procurar_atualizacao() -> void:
	var repo := str(versao.get("repo", ""))
	if repo == "": upd.estado = "sem_config"; upd.texto = "Atualização automática desligada"; return
	upd.estado = "procurando"; upd.texto = "Procurando atualização..."
	var api := str(versao.get("api", "https://api.github.com"))
	if http.request_completed.is_connected(_resp_versao): http.request_completed.disconnect(_resp_versao)
	http.request_completed.connect(_resp_versao, CONNECT_ONE_SHOT)
	http.max_redirects = 8; http.download_file = ""
	if http.request(api + "/repos/%s/releases/latest" % repo, _hdr(_chave_repo())) != OK:
		upd.estado = "erro"; upd.texto = "Sem conexão para procurar atualização"

func _resp_versao(res: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if res != HTTPRequest.RESULT_SUCCESS or code != 200:
		upd.estado = "erro"
		if res != HTTPRequest.RESULT_SUCCESS: upd.texto = "Sem internet: não deu para procurar atualização"
		elif code == 401: upd.texto = "Chave de atualização inválida ou vencida (chave.txt)"
		elif code == 404: upd.estado = "em_dia"; upd.texto = "Nenhuma versão nova publicada"
		elif code == 403 or code == 429: upd.texto = "O GitHub pediu para esperar; tente mais tarde"
		else: upd.texto = "Não deu para procurar atualização (erro %d)" % code
		_log(upd.texto)
		if auto and auto_upd and not discos.is_empty() and disco_thread and not disco_thread.is_alive(): _preparar()
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary: upd.estado = "erro"; upd.texto = "Resposta estranha da atualização"; return
	var nova := int(str(d.get("tag_name", "v0")).trim_prefix("v"))
	var atual := int(versao.get("versao", 0))
	upd.nova = nova
	if nova > atual:
		for a in d.get("assets", []):
			if str(a.get("name", "")) == "atualizacao.zip": upd.url = str(a.get("url", ""))
		if upd.url == "": upd.estado = "erro"; upd.texto = "Versão %d sem o arquivo de atualização" % nova; return
		upd.estado = "disponivel"; upd.texto = "Nova versão %d disponível (você tem a %d)" % [nova, atual]
		_som("menu_full")
	else:
		upd.estado = "em_dia"; upd.texto = "Você está na versão mais nova (%d)" % atual
	_log(upd.texto)
	_atualiza_botoes()
	if auto and auto_upd and disco_thread and not disco_thread.is_alive() and _discos_ok():
		if upd.estado == "disponivel": _baixar_atualizacao()
		else: _preparar()

func _baixar_atualizacao() -> void:
	if upd.estado != "disponivel" or rodando >= 0: return
	upd.estado = "baixando"; upd.texto = "Baixando a versão %d..." % upd.nova
	_atualiza_botoes()
	var zip := raiz.path_join("gerado/atualizacao.zip")
	if FileAccess.file_exists(zip): DirAccess.remove_absolute(zip)
	# o GitHub responde com um redirecionamento para o arquivo: o segundo pedido vai sem a chave
	http.max_redirects = 0
	http.download_file = zip
	http.request_completed.connect(_resp_download.bind(0), CONNECT_ONE_SHOT)
	http.request(upd.url, _hdr(_chave_repo(), "application/octet-stream"))

func _resp_download(res: int, code: int, headers: PackedStringArray, _b: PackedByteArray, passo: int) -> void:
	var zip := raiz.path_join("gerado/atualizacao.zip")
	if code in [301, 302, 303, 307, 308] and passo < 3:
		var loc := ""
		for h in headers:
			if h.to_lower().begins_with("location:"): loc = h.substr(9).strip_edges()
		http.download_file = zip
		http.request_completed.connect(_resp_download.bind(passo + 1), CONNECT_ONE_SHOT)
		http.request(loc, PackedStringArray(["User-Agent: MegaManXFusion-Launcher"]))
		return
	http.download_file = ""
	if res != HTTPRequest.RESULT_SUCCESS or code != 200 or not FileAccess.file_exists(zip):
		upd.estado = "disponivel"; upd.texto = "Falhou o download (%d/%d). Tente de novo." % [res, code]
		_som("menu_error"); _log(upd.texto); _atualiza_botoes()
		if auto: _fim_auto(false, upd.texto)
		return
	_aplica_atualizacao(zip)

func _aplica_atualizacao(zip: String) -> void:
	var zr := ZIPReader.new()
	if zr.open(zip) != OK:
		upd.estado = "disponivel"; upd.texto = "Arquivo de atualização estragado"; _atualiza_botoes(); return
	var mudou_launcher := false
	var n := 0
	for f in zr.get_files():
		if f.ends_with("/") or f.begins_with("/") or ".." in f or ":" in f: continue
		if f == "chave.txt": continue
		var dst := raiz.path_join(f)
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var bytes := zr.read_file(f)
		if f == "versao.json":   # mantém repositório e chave daqui se a versão nova não trouxer
			var novo = JSON.parse_string(bytes.get_string_from_utf8())
			if novo is Dictionary:
				for k in ["repo", "api", "token"]:
					if not novo.has(k) and versao.has(k): novo[k] = versao[k]
				novo["versao"] = int(novo.get("versao", 0))
				bytes = JSON.stringify(novo, " ").to_utf8_buffer()
		if f.begins_with("launcher/") and FileAccess.file_exists(dst) and FileAccess.get_file_as_bytes(dst) != bytes: mudou_launcher = true
		var w := FileAccess.open(dst, FileAccess.WRITE)
		if w: w.store_buffer(bytes); n += 1
	# arquivos que saíram do jogo nesta versão
	var rem := zr.read_file("remover.txt").get_string_from_utf8() if "remover.txt" in zr.get_files() else ""
	zr.close()
	for ln in rem.split("\n"):
		var r := ln.strip_edges()
		if r == "" or ".." in r or r.begins_with("/"): continue
		if FileAccess.file_exists(raiz.path_join(r)): DirAccess.remove_absolute(raiz.path_join(r))
	versao = _ler_json(raiz.path_join("versao.json"))
	_le_receita()
	_log("atualização aplicada: %d arquivos, agora versão %d" % [n, int(versao.get("versao", 0))])
	upd.estado = "em_dia"; upd.texto = "Atualizado para a versão %d" % int(versao.get("versao", 0))
	_som("menu_full")
	if mudou_launcher and not auto:   # o próprio launcher mudou: abre de novo
		OS.create_process(_vars().godot, PackedStringArray(["--path", raiz.path_join("launcher")]))
		get_tree().quit(); return
	_monta_etapas(); _avalia_etapas(); _atualiza_botoes()
	_foto("atualizado")
	_preparar()

# ---------------- teste automático ----------------
func _tela_depois(arg: String) -> void:
	var at := arg.rfind("@")
	var arq := arg.substr(0, at) if at > 0 else arg
	var seg := float(arg.substr(at + 1)) if at > 0 else 3.0
	await get_tree().create_timer(seg).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(arq)
	get_tree().quit()

func _foto(nm: String) -> void:
	if foto == "": return
	await get_tree().process_frame; await get_tree().process_frame
	n_foto += 1
	get_viewport().get_texture().get_image().save_png("%s_%02d_%s.png" % [foto, n_foto, nm])

func _fim_auto(ok: bool, msg: String) -> void:
	var rel := {"ok": ok, "mensagem": msg, "discos": discos, "atualizacao": upd, "etapas": []}
	for e in etapas: rel.etapas.append({"id": e.id, "estado": e.estado, "texto": e.texto})
	var f := FileAccess.open(raiz.path_join("gerado/relatorio_launcher.json"), FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(rel, " "))
	await _foto("fim")
	if ok and not sem_jogo: _jogar(); return
	get_tree().quit(0 if ok else 1)

# ---------------- quadro a quadro ----------------
func _process(dt: float) -> void:
	t += dt
	_processa_saida()
	_confere_processo()
	cv.queue_redraw()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and rodando >= 0:
		cancelar = true; _log("cancelando..."); get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if not proc.is_empty() and OS.is_process_running(proc.pid): OS.kill(proc.pid)
	if disco_thread and disco_thread.is_started(): disco_thread.wait_to_finish()

# ---------------- desenho (original: grade, linhas de varredura, painéis) ----------------
func _desenha(ci: Control) -> void:
	# fundo: degradê, grade em perspectiva andando, faixa de luz e partículas
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(640, 0), Vector2(640, 360), Vector2(0, 360)]),
		PackedColorArray([Color(0.02, 0.05, 0.14), Color(0.02, 0.05, 0.14), Color(0.0, 0.01, 0.04), Color(0.0, 0.01, 0.04)]))
	var hz := 250.0
	for i in 15:
		var x := 320.0 + (i - 7) * 46.0
		ci.draw_line(Vector2(320 + (x - 320) * 0.15, hz), Vector2(x * 1.0 + (x - 320) * 1.6, 360), Color(0.2, 0.55, 1.0, 0.1), 1.0)
	for i in 8:
		var k := fmod(i / 8.0 + t * 0.08, 1.0)
		var y := hz + (360.0 - hz) * k * k
		ci.draw_line(Vector2(0, y), Vector2(640, y), Color(0.2, 0.55, 1.0, 0.04 + 0.1 * k), 1.0)
	var sw := fmod(t * 0.12, 1.6) - 0.3
	ci.draw_colored_polygon(PackedVector2Array([Vector2(sw * 640 - 40, 0), Vector2(sw * 640 + 20, 0), Vector2(sw * 640 - 80, 360), Vector2(sw * 640 - 140, 360)]), Color(0.4, 0.7, 1.0, 0.035))
	for i in 24:
		var ph := fmod(t * (0.03 + (i % 5) * 0.01) + i * 0.137, 1.0)
		ci.draw_rect(Rect2(fmod(i * 97.3, 640.0), 360.0 - ph * 380.0, 1.5, 1.5), Color(0.5, 0.8, 1.0, 0.35 * sin(ph * PI)))
	var ab := MmxUI.ease_out(t / 0.6)
	_titulo(ci, ab)
	MmxUI.text(ci, Vector2(22, 50), "LAUNCHER  ·  X4  X5  X6", Color(0.6, 0.75, 1.0, ab))
	MmxUI.text(ci, Vector2(0, 26), "versão %d" % int(versao.get("versao", 0)), Color(0.6, 0.75, 1.0, ab), MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, 620)
	ci.draw_line(Vector2(16, 56), Vector2(16 + 608 * ab, 56), Color(0.3, 0.84, 1.0, 0.5), 1.0)
	_painel_discos(ci, Rect2(16, 64, 236, 164), ab)
	_painel_atualizacao(ci, Rect2(16, 236, 236, 68), ab)
	_painel_etapas(ci, Rect2(264, 64, 360, 198), ab)
	_rodape(ci, ab)
	# brilho no JOGAR quando pronto
	if not btn_jogar.disabled:
		var r := Rect2(btn_jogar.position, btn_jogar.size).grow(2)
		var a := 0.3 + 0.3 * sin(t * TAU * 1.1)
		var sk := r.size.y * 0.25 * 0.5
		ci.draw_polyline(PackedVector2Array([r.position + Vector2(sk, 0), Vector2(r.end.x + sk, r.position.y), r.end - Vector2(sk, 0), Vector2(r.position.x - sk, r.end.y), r.position + Vector2(sk, 0)]), Color(1, 0.86, 0.35, a), 1.0)

## título com um brilho passando pelas letras
func _titulo(ci: Control, ab: float) -> void:
	var s := "MEGA MAN X FUSION"
	var f := MmxUI.font()
	var x := 20.0 - (1.0 - ab) * 30.0
	var sw := fmod(t * 0.35, 1.8) * 360.0 - 60.0   # posição do brilho
	for ch in s:
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
		var g := clampf(1.0 - absf(x + w * 0.5 - 20.0 - sw) / 26.0, 0.0, 1.0)
		var col := Color(1, 0.86, 0.35).lerp(Color(1, 1, 0.92), g * 0.85)
		col.a = ab
		MmxUI.text(ci, Vector2(x, 38), ch, col, 27)
		x += w

## texto do rodapé: o que está acontecendo, em palavras de gente
func _status() -> Array:   # [texto, cor]
	if disco_thread and disco_thread.is_alive():
		for d in DISCOS:
			var st: Dictionary = discos.get(d.id, {})
			if st.get("estado", "") == "procurando" and float(st.get("progresso", 0.0)) > 0.0:
				return ["Conferindo os discos... (%s %d%%)" % [d.nome, int(float(st.progresso) * 100.0)], MmxUI.C_ACCENT]
		return ["Procurando os discos...", MmxUI.C_ACCENT]
	if upd.estado == "baixando": return ["Baixando a versão %d..." % int(upd.nova), MmxUI.C_ACCENT]
	for d in DISCOS:
		var st: Dictionary = discos.get(d.id, {})
		if st.get("estado", "") == "diferente":
			return ["\"%s\" não é o %s certo (precisa ser a versão americana: %s)." % [str(st.caminho).get_file(), d.nome, d.arquivo], C_ERR]
	if not _discos_ok():
		return ["Coloque os discos (.bin) na pasta \"discos\" ou clique em PROCURAR DISCOS.", C_ERR]
	if receita_msg != "": return [receita_msg, C_ERR]
	if rodando >= 0:
		var e: Dictionary = etapas[rodando]
		return ["Preparando: %s%s   ·   ESC cancela" % [e.nome, (" — " + str(e.texto)) if str(e.texto) != "" else ""], MmxUI.C_TEXT]
	for e in etapas:
		if e.estado == "erro": return ["Deu erro em \"%s\". O registro está em gerado/launcher.log." % e.nome, C_ERR]
	if upd.estado == "disponivel": return ["Tem versão nova (%d): clique em ATUALIZAR." % int(upd.nova), MmxUI.C_SEL]
	if prep_ok: return ["Tudo pronto! Clique em JOGAR.", C_OK]
	return ["Clique em PREPARAR (só na primeira vez e depois de atualizar; pode levar alguns minutos).", MmxUI.C_TEXT]

func _rodape(ci: Control, ab: float) -> void:
	var r := Rect2(16, 314, 608, 22)
	ci.draw_rect(r, Color(0.0, 0.03, 0.1, 0.8 * ab))
	ci.draw_rect(r, Color(0.13, 0.32, 0.66, 0.8 * ab), false, 1.0)
	var st := _status()
	var col: Color = st[1]
	ci.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), col)
	var w := r.size.x - 20 - (104.0 if btn_log.visible else 0.0)
	MmxUI.text(ci, r.position + Vector2(10, 14), MmxUI.fit(str(st[0]), w), col)
	var x := 18.0
	x += MmxUI.hint(ci, Vector2(x, 352), "ENTER", "jogar")
	x += MmxUI.hint(ci, Vector2(x + 6, 352), "ESC", "cancelar")
	MmxUI.text(ci, Vector2(0, 352), "fangame sem fins lucrativos  ·  usa os seus próprios discos", Color(0.36, 0.44, 0.62), MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, 622)

## disquinho desenhado (só um CD genérico, na cor do jogo); gira enquanto confere
func _disco_icone(ci: Control, c: Vector2, col: Color, girando: bool, ok: bool) -> void:
	ci.draw_circle(c, 10.0, Color(0.05, 0.1, 0.22))
	ci.draw_arc(c, 9.5, 0, TAU, 32, Color(col.r, col.g, col.b, 0.9), 1.0)
	ci.draw_arc(c, 6.5, 0, TAU, 24, Color(col.r, col.g, col.b, 0.35), 3.0)
	var a0 := t * 7.0 if girando else 0.9
	ci.draw_arc(c, 7.0, a0, a0 + 1.1, 10, Color(1, 1, 1, 0.55 if girando else 0.25), 2.0)
	ci.draw_circle(c, 2.6, Color(0.0, 0.02, 0.06))
	ci.draw_arc(c, 2.6, 0, TAU, 12, Color(col.r, col.g, col.b, 0.8), 1.0)
	if ok:
		ci.draw_circle(c + Vector2(7, 6), 4.0, Color(0.05, 0.25, 0.1))
		ci.draw_polyline(PackedVector2Array([c + Vector2(5, 6), c + Vector2(6.5, 7.5), c + Vector2(9.5, 4.5)]), C_OK, 1.2)

const COR_JOGO := {"x4": Color(0.35, 0.65, 1.0), "x5": Color(1.0, 0.55, 0.3), "x6": Color(0.75, 0.5, 1.0)}

func _painel_discos(ci: Control, r: Rect2, ab: float) -> void:
	MmxUI.frame(ci, Rect2(r.position + Vector2((1.0 - ab) * -40, 0), r.size), MmxUI.C_ACCENT, 7.0)
	MmxUI.title_tab(ci, r, "DISCOS")
	var y := r.position.y + 14
	for d in DISCOS:
		var st: Dictionary = discos.get(d.id, {})
		var s := str(st.get("estado", ""))
		var row := Rect2(r.position.x + 8, y, r.size.x - 16, 34)
		ci.draw_rect(row, Color(0.0, 0.03, 0.1, 0.7))
		ci.draw_rect(row, Color(0.13, 0.32, 0.66, 0.7), false, 1.0)
		var col: Color = C_OK if s == "ok" else (C_ERR if s in ["faltando", "diferente"] else MmxUI.C_ACCENT)
		ci.draw_rect(Rect2(row.position, Vector2(3, row.size.y)), col)
		_disco_icone(ci, row.position + Vector2(20, 17), COR_JOGO[d.id], s == "procurando", s == "ok")
		MmxUI.text(ci, row.position + Vector2(36, 14), str(d.nome).to_upper(), MmxUI.C_TEXT)
		var sub := ""
		match s:
			"ok": sub = "disco certo"
			"faltando": sub = "não encontrado"
			"diferente": sub = "não é este disco"
			_: sub = "conferindo... %d%%" % int(float(st.get("progresso", 0.0)) * 100.0)
		MmxUI.text(ci, row.position + Vector2(36, 26), sub, col)
		if s in ["ok", "diferente"]:
			MmxUI.text(ci, Vector2(row.position.x, row.position.y + 26), MmxUI.fit(str(st.get("caminho", "")).get_file(), 104), MmxUI.C_DIM, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 6)
		if s == "procurando":
			var k := float(st.get("progresso", 0.0))
			ci.draw_rect(Rect2(row.position.x + 3, row.end.y - 2, (row.size.x - 3) * k, 2), MmxUI.C_ACCENT)
		y += 38

func _painel_atualizacao(ci: Control, r: Rect2, ab: float) -> void:
	MmxUI.frame(ci, Rect2(r.position + Vector2((1.0 - ab) * -40, 0), r.size), MmxUI.C_ACCENT, 7.0)
	MmxUI.title_tab(ci, r, "ATUALIZAÇÃO")
	var col := MmxUI.C_DIM
	match str(upd.estado):
		"em_dia": col = C_OK
		"disponivel": col = MmxUI.C_SEL
		"erro": col = C_ERR
		"baixando", "procurando": col = MmxUI.C_ACCENT
	var ls := MmxUI.wrap(str(upd.texto), r.size.x - 20)
	var n := 1 if upd.estado in ["disponivel", "baixando"] else 2
	for i in mini(ls.size(), n):
		MmxUI.text(ci, r.position + Vector2(10, 22 + i * 11), ls[i], col)
	if not upd.estado in ["disponivel", "baixando"]:
		var info := "Você tem a versão %d." % int(versao.get("versao", 0))
		if upd.estado == "sem_config": info = "Sem versao.json com o repositório."
		MmxUI.text(ci, r.position + Vector2(10, r.size.y - 12), info, Color(0.36, 0.44, 0.62))
	if upd.estado == "baixando":
		var k := 0.0
		if http.get_body_size() > 0: k = float(http.get_downloaded_bytes()) / float(http.get_body_size())
		_barra(ci, Rect2(r.position.x + 12, r.end.y - 22, r.size.x - 24, 8), k)

func _painel_etapas(ci: Control, r: Rect2, ab: float) -> void:
	MmxUI.frame(ci, Rect2(r.position + Vector2((1.0 - ab) * 40, 0), r.size), MmxUI.C_ACCENT, 7.0)
	MmxUI.title_tab(ci, r, "PREPARAÇÃO")
	if etapas.is_empty():
		for i in MmxUI.wrap(receita_msg, r.size.x - 24).size():
			MmxUI.text(ci, r.position + Vector2(12, 30 + i * 11), MmxUI.wrap(receita_msg, r.size.x - 24)[i], C_ERR)
		return
	var y := r.position.y + 14
	var h := minf(24.0, (r.size.y - 58.0) / etapas.size())
	var tot := 0.0
	for i in etapas.size():
		var e: Dictionary = etapas[i]
		var s := str(e.estado)
		var row := Rect2(r.position.x + 8, y, r.size.x - 16, h - 3)
		var on := i == rodando
		ci.draw_rect(row, Color(0.0, 0.03, 0.1, 0.7) if not on else Color(0.05, 0.15, 0.32, 0.9))
		if on: MmxUI.sel_bar(ci, row, t, MmxUI.C_ACCENT, false)
		var col: Color = C_OK if s == "feita" else (C_ERR if s == "erro" else (MmxUI.C_SEL if on else MmxUI.C_DIM))
		var ic := "✓" if s == "feita" else ("✗" if s == "erro" else ("▶" if on else "·"))
		var ty := row.position.y + 9 + (row.size.y - 10) * 0.5
		MmxUI.text(ci, Vector2(row.position.x + 5, ty), ic, col)
		MmxUI.text(ci, Vector2(row.position.x + 16, ty), str(e.nome), MmxUI.C_TEXT if s != "pendente" else Color(0.6, 0.68, 0.85))
		var bar := Rect2(row.end.x - 118, row.position.y + (row.size.y - 6) * 0.5, 112, 6)
		_barra(ci, bar, float(e.progresso), col if s != "pendente" else MmxUI.C_EDGE_LO)
		var dica := ""
		if on: dica = str(e.texto)
		elif s == "feita" and str(e.texto) != "": dica = str(e.texto)
		elif s == "erro": dica = "deu erro"
		if dica != "":
			MmxUI.text(ci, Vector2(row.position.x, ty), MmxUI.fit(dica, 92), C_ERR if s == "erro" else MmxUI.C_DIM, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 124)
		tot += float(e.progresso)
		y += h
	# barra geral
	var k := tot / maxf(1.0, etapas.size())
	var gr := Rect2(r.position.x + 10, r.end.y - 22, r.size.x - 20, 10)
	_barra(ci, gr, k, MmxUI.C_SEL if prep_ok else MmxUI.C_ACCENT, true)
	MmxUI.text(ci, Vector2(gr.position.x, gr.position.y - 3), "TOTAL", MmxUI.C_DIM)
	MmxUI.text(ci, Vector2(gr.position.x, gr.position.y - 3), "%d%%" % int(k * 100.0), MmxUI.C_TEXT, MmxUI.SIZE, HORIZONTAL_ALIGNMENT_RIGHT, gr.size.x)

## barra de segmentos (estilo barra de energia)
func _barra(ci: Control, r: Rect2, k: float, col := MmxUI.C_ACCENT, grande := false) -> void:
	ci.draw_rect(r, Color(0.0, 0.02, 0.06, 0.9))
	var seg := 4.0 if not grande else 6.0
	var n := int(r.size.x / seg)
	var on := int(round(clampf(k, 0.0, 1.0) * n))
	for i in n:
		var c := col if i < on else Color(0.08, 0.14, 0.28)
		if i < on and i == on - 1 and k < 1.0: c = c.lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 12.0))
		ci.draw_rect(Rect2(r.position.x + i * seg + 1, r.position.y + 1, seg - 1, r.size.y - 2), c)
	ci.draw_rect(r, Color(0.13, 0.32, 0.66, 0.8), false, 1.0)

class _Canvas extends Control:
	var fn: Callable
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if fn.is_valid(): fn.call(self)
