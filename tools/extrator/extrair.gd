extends SceneTree
## Extrator do Mega Man X Fusion: gera no PC do jogador, a partir dos discos DELE, os arquivos que o jogo usa.
## Roda dentro do próprio Godot (o mesmo que abre o jogo): não precisa de Python no PC do jogador.
##
## uso: godot --headless --path tools/extrator --script res://extrair.gd -- PASTA_DO_JOGO GRUPO [GRUPO...]
##        disco_x4=CAMINHO disco_x5=CAMINHO disco_x6=CAMINHO [ffmpeg=CAMINHO]
## Cada grupo escreve seus arquivos em PASTA_DO_JOGO/assets. O launcher lê as linhas "@progresso a/b texto".
## Nada dos discos fica guardado aqui: só onde ler e como converter.

const SETOR := 2352

var opcoes := {}

# ---------------- disco de PS1 em .bin (MODE2/2352, uma trilha) ----------------
class Disco:
	var f: FileAccess
	var caminho := ""
	var _arquivos := {}

	func _init(c: String) -> void:
		caminho = c
		f = FileAccess.open(c, FileAccess.READ)

	## os 2048 bytes de dados (modo 2 forma 1) de n setores a partir do lba
	func dados(lba: int, n := 1) -> PackedByteArray:
		var out := PackedByteArray()
		for i in n:
			f.seek((lba + i) * SETOR + 24)
			out.append_array(f.get_buffer(2048))
		return out

	## os 2352 bytes inteiros de cada setor
	func bruto(lba: int, n := 1) -> PackedByteArray:
		f.seek(lba * SETOR)
		return f.get_buffer(SETOR * n)

	## {CAMINHO/NOME: [lba, tamanho]} de todos os arquivos do disco (ISO9660)
	func arquivos() -> Dictionary:
		if _arquivos.is_empty():
			var pvd := dados(16)
			_le_dir(pvd.decode_u32(156 + 2), pvd.decode_u32(156 + 10), "")
		return _arquivos

	func _le_dir(lba: int, tam: int, pref: String) -> void:
		var d := dados(lba, (tam + 2047) / 2048)
		var i := 0
		while i < tam:
			var n := d[i]
			if n == 0:   # resto do setor vazio
				i = (i / 2048 + 1) * 2048
				continue
			var l2 := d.decode_u32(i + 2)
			var t2 := d.decode_u32(i + 10)
			var flags := d[i + 25]
			var nl := d[i + 32]
			var nome := d.slice(i + 33, i + 33 + nl)
			if not (nl == 1 and nome[0] <= 1):
				var nm := nome.get_string_from_ascii().split(";")[0]
				if flags & 2: _le_dir(l2, t2, pref + nm + "/")
				else: _arquivos[pref + nm] = [l2, t2]
			i += n

# ---------------- saída ----------------
func progresso(a: int, b: int, texto := "") -> void:
	print("@progresso %d/%d %s" % [a, b, texto])

func escreve(jogo: String, rel: String, bytes: PackedByteArray) -> bool:
	var p := jogo.path_join(rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var w := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if w == null: printerr("não consegui escrever ", p); return false
	w.store_buffer(bytes); w.close()
	return DirAccess.rename_absolute(p + ".tmp", p) == OK

# ---------------- grupos ----------------
## X4: os dados do disco que o núcleo do X4 lê (os primeiros 12947 setores, só a parte de dados)
const X4_ARC_SETORES := 12947
func x4_arc(jogo: String, discos: Dictionary, prog: Callable) -> int:
	var d: Disco = discos.x4
	var tudo := PackedByteArray()
	var bloco := 512
	for i in range(0, X4_ARC_SETORES, bloco):
		var n := mini(bloco, X4_ARC_SETORES - i)
		tudo.append_array(d.dados(i, n))
		prog.call(i + n, X4_ARC_SETORES, "dados do disco do X4")
	return 1 if escreve(jogo, "assets/x4c_disc_arc.sec", tudo) else -1

## vídeos: os .STR do disco convertidos para Theora/Vorbis (.ogv), que o Godot toca
## mesmos ajustes da conversão original: vídeo -q:v 8, som -q:a 5 a 44100 Hz (320x240, 15 quadros/s)
const VIDEOS := {
	"x4": [["STR/CAPCOM20.STR", "CAPCOM20"], ["STR/OP_U.STR", "OP_U"], ["STR/X1_U.STR", "X1_U"], ["STR/X2_U.STR", "X2_U"],
		["STR/X3_U.STR", "X3_U"], ["STR/X4_U.STR", "X4_U"], ["STR/Z1_U.STR", "Z1_U"], ["STR/Z2_U.STR", "Z2_U"],
		["STR/Z3_U.STR", "Z3_U"], ["STR/Z4_U.STR", "Z4_U"], ["STR/Z5_U.STR", "Z5_U"]],
	"x5": [["STR/CAPLOGO.STR", "x5_CAPLOGO"], ["STR/X5OP.STR", "x5_X5OP"]],
	"x6": [["STR/CAPLOGO.STR", "x6_CAPLOGO"], ["STR/X6OP.STR", "x6_X6OP"]],
}
func videos(jg: String, jogo: String, discos: Dictionary, prog: Callable) -> int:
	var d: Disco = discos[jg]
	var lista: Array = VIDEOS[jg]
	var ff := str(opcoes.get("ffmpeg", ""))
	if ff == "": ff = OS.get_environment("FUSION_FFMPEG") if OS.get_environment("FUSION_FFMPEG") != "" else "ffmpeg"
	var tmp := jogo.path_join("assets/movies/.tmp_str")
	DirAccess.make_dir_recursive_absolute(tmp)
	for i in lista.size():
		var nome: String = lista[i][0]; var saida: String = lista[i][1]
		prog.call(i, lista.size(), "vídeo " + saida)
		if not d.arquivos().has(nome): printerr("o disco não tem ", nome); return -1
		var lba: int = d.arquivos()[nome][0]; var tam: int = d.arquivos()[nome][1]
		var n := (tam + 2047) / 2048
		var src := tmp.path_join(saida + ".STR")
		var w := FileAccess.open(src, FileAccess.WRITE)   # o .STR precisa dos setores inteiros (vídeo + som XA)
		for k in range(0, n, 256): w.store_buffer(d.bruto(lba + k, mini(256, n - k)))
		w.close()
		var dst := jogo.path_join("assets/movies/" + saida + ".ogv")
		var out := []
		OS.execute(ff, ["-nostdin", "-v", "error", "-y", "-i", src, "-c:v", "libtheora", "-q:v", "8",
			"-c:a", "libvorbis", "-q:a", "5", "-ar", "44100", dst + ".tmp.ogv"], out, true)
		DirAccess.remove_absolute(src)
		# (o leitor de STR do ffmpeg reclama no fim do arquivo: normal, o vídeo sai inteiro)
		if not FileAccess.file_exists(dst + ".tmp.ogv") or FileAccess.open(dst + ".tmp.ogv", FileAccess.READ).get_length() == 0:
			printerr("ffmpeg falhou em %s (%s): %s" % [saida, ff, str(out).right(300)]); return -1
		DirAccess.rename_absolute(dst + ".tmp.ogv", dst)
	DirAccess.remove_absolute(tmp)
	prog.call(lista.size(), lista.size(), "vídeos prontos")
	return lista.size()

const GRUPOS := {
	"x4_arc": {"discos": ["x4"]},
	"videos_x4": {"discos": ["x4"]}, "videos_x5": {"discos": ["x5"]}, "videos_x6": {"discos": ["x6"]},
}
func roda_grupo(nm: String, jogo: String, discos: Dictionary, prog: Callable) -> int:
	match nm:
		"x4_arc": return x4_arc(jogo, discos, prog)
		"videos_x4": return videos("x4", jogo, discos, prog)
		"videos_x5": return videos("x5", jogo, discos, prog)
		"videos_x6": return videos("x6", jogo, discos, prog)
	return -1

# ---------------- principal ----------------
func _init() -> void:
	var pos := []
	for a in OS.get_cmdline_user_args():
		if "=" in a: opcoes[a.get_slice("=", 0)] = a.substr(a.find("=") + 1)
		else: pos.append(a)
	if pos.size() < 2:
		printerr("uso: extrair.gd PASTA_DO_JOGO GRUPO [GRUPO...] disco_x4=... disco_x5=... disco_x6=... [ffmpeg=...]")
		quit(2); return
	var jogo: String = pos[0]
	var nomes: Array = pos.slice(1)
	var discos := {}
	for jg in ["x4", "x5", "x6"]:
		var c := str(opcoes.get("disco_" + jg, ""))
		if c != "" and FileAccess.file_exists(c): discos[jg] = Disco.new(c)
	var total := nomes.size()
	for i in total:
		var nm: String = nomes[i]
		if not GRUPOS.has(nm): printerr("grupo desconhecido: ", nm); quit(2); return
		var falta := []
		for d in GRUPOS[nm].discos:
			if not discos.has(d): falta.append(d)
		if not falta.is_empty(): printerr("%s: falta o disco %s" % [nm, ", ".join(falta)]); quit(3); return
		var t0 := Time.get_ticks_msec()
		# progresso do grupo dentro do total desta etapa
		var prog := func(a: int, b: int, texto := "") -> void: progresso(i * 1000 + int(1000.0 * a / maxf(1.0, b)), total * 1000, texto if texto != "" else nm)
		prog.call(0, 1, nm)
		var n := roda_grupo(nm, jogo, discos, prog)
		if n < 0: printerr(nm, ": falhou"); quit(1); return
		print("%s: %d arquivo(s) em %.1f s" % [nm, n, (Time.get_ticks_msec() - t0) / 1000.0])
	progresso(total, total, "pronto")
	quit(0)
