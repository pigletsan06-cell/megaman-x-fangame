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
	if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
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
## (3º campo: os números de série do Ogg de cada arquivo do PC do dono; com o nosso ffmpeg.exe o .ogv sai igual byte a byte)
const VIDEOS := {
	"x4": [["STR/CAPCOM20.STR", "CAPCOM20", "5f05b523,befd6c3c"], ["STR/OP_U.STR", "OP_U", "0a306f2f,1c85628f"],
		["STR/X1_U.STR", "X1_U", "f7c1bb59,a40bbd34"], ["STR/X2_U.STR", "X2_U", "7344ab1b,997b79eb"],
		["STR/X3_U.STR", "X3_U", "1ba0b7c6,6c77f5fd"], ["STR/X4_U.STR", "X4_U", "1f8318fd,ce04d88c"],
		["STR/Z1_U.STR", "Z1_U", "3c48578c,87e242ed"], ["STR/Z2_U.STR", "Z2_U", "be14ccce,bf0255e7"],
		["STR/Z3_U.STR", "Z3_U", "22a12f53,0ce37c41"], ["STR/Z4_U.STR", "Z4_U", "4247c1b8,a4de5a63"],
		["STR/Z5_U.STR", "Z5_U", "a9b4586c,c5648be4"]],
	"x5": [["STR/CAPLOGO.STR", "x5_CAPLOGO", "8f17d718,d3c4e88a"], ["STR/X5OP.STR", "x5_X5OP", "d085a1e9,8ad317f8"]],
	"x6": [["STR/CAPLOGO.STR", "x6_CAPLOGO", "6b877f25,d4f4090f"], ["STR/X6OP.STR", "x6_X6OP", "1b590aad,3196b4ff"]],
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
		OS.set_environment("FUSION_OGG_SERIAIS", str(lista[i][2]) if lista[i].size() > 2 else "")
		OS.execute(ff, ["-nostdin", "-v", "error", "-y", "-i", src, "-c:v", "libtheora", "-q:v", "8",
			"-c:a", "libvorbis", "-q:a", "5", "-ar", "44100", dst + ".tmp.ogv"], out, true)
		OS.unset_environment("FUSION_OGG_SERIAIS")
		DirAccess.remove_absolute(src)
		# (o leitor de STR do ffmpeg reclama no fim do arquivo: normal, o vídeo sai inteiro)
		# (o arquivo aberto tem que ser fechado antes de renomear: no Windows não dá para renomear arquivo aberto)
		var fv := FileAccess.open(dst + ".tmp.ogv", FileAccess.READ)
		var tam_ok := fv != null and fv.get_length() > 0
		if fv != null: fv.close()
		fv = null
		if not tam_ok:
			printerr("ffmpeg falhou em %s (%s): %s" % [saida, ff, str(out).right(300)]); return -1
		if FileAccess.file_exists(dst): DirAccess.remove_absolute(dst)
		if DirAccess.rename_absolute(dst + ".tmp.ogv", dst) != OK:
			printerr("não consegui renomear ", dst + ".tmp.ogv"); return -1
	DirAccess.remove_absolute(tmp)
	prog.call(lista.size(), lista.size(), "vídeos prontos")
	return lista.size()

## capturas: o nosso núcleo de PS1 (captura/captura.exe) roda o disco com um roteiro de controle (roteiros/NOME.json)
## e fotografa os quadros pedidos; o Godot desenha cada foto (tests/render_dump.gd) e a imagem vai para assets/.
func opcao(k: String, env: String, padrao: String) -> String:
	if str(opcoes.get(k, "")) != "": return str(opcoes[k])
	if OS.get_environment(env) != "": return OS.get_environment(env)
	return padrao

func captura(nm: String, jogo: String, discos: Dictionary, prog: Callable) -> int:
	var r = JSON.parse_string(FileAccess.get_file_as_string("res://roteiros/%s.json" % nm))
	if not r is Dictionary: printerr("roteiro estragado: ", nm); return -1
	var cap := opcao("captura", "FUSION_CAPTURA", "captura")
	var bios := opcao("bios", "FUSION_BIOS", "")
	var render := opcao("godot_render", "FUSION_GODOT_RENDER", OS.get_executable_path())
	if OS.get_name() == "Windows" and not FileAccess.file_exists(render) and FileAccess.file_exists(opcao("godot", "FUSION_GODOT", "")):
		# cópia do Godot ao lado do desenhista por software (opengl32.dll): o desenho sai igual em qualquer placa de vídeo
		DirAccess.copy_absolute(opcao("godot", "FUSION_GODOT", ""), render)
	var d: Disco = discos[r.disco]
	var dir := jogo.path_join(".captura/" + nm)
	DirAccess.make_dir_recursive_absolute(dir)
	var fotos: Dictionary = r.fotos
	for k in ["DUMP", "DUMP_FROM", "OBJLOG", "AUDIO", "AUDIO_FROM", "AUDIO_POR", "SPUDBG", "SPUDUMP", "RWATCH"]: OS.unset_environment(k)
	var au: Dictionary = r.get("audio", {})
	if not au.is_empty():   # som do núcleo (44,1 kHz estéreo 16 bits, cru) a partir de um quadro
		OS.set_environment("AUDIO", dir.path_join("som.raw")); OS.set_environment("AUDIO_FROM", str(int(au.de)))
		if au.has("por"): OS.set_environment("AUDIO_POR", str(int(au.por)))   # amostras por quadro (padrão 735/736)
	OS.set_environment("NORAM", "1"); OS.set_environment("DUMPDIR", dir)
	if r.has("spu"): OS.set_environment("SPUDUMP", str(int(r.spu)))   # RAM do SPU (sons) fotografada neste quadro
	var quadros := fotos.keys()
	for sp in r.get("sprites", []):
		if not str(int(sp.quadro)) in quadros: quadros.append(str(int(sp.quadro)))
	OS.set_environment("DUMP_LIST", ",".join(quadros)); OS.set_environment("POKE", str(r.get("poke", "")))
	prog.call(0, 3, "rodando o %s" % str(r.jogo).to_upper())
	var out := []
	var code := 0
	if str(r.get("motor", "")) == "x4core":
		# X4 pelo x4core (código do X4 compilado neste PC): o próprio jogo roda o roteiro e grava as fotos
		var x4env := []
		for k in r.get("x4env", {}): x4env.append("%s=%s" % [k, r.x4env[k]])
		OS.set_environment("X4ENV", ";".join(x4env)); OS.set_environment("X4_SEM_VIDEO", "1")
		OS.set_environment("SAIDA", dir); OS.set_environment("QUADROS", ",".join(quadros))
		OS.set_environment("TOTAL", str(int(r.quadros))); OS.set_environment("BOTOES", str(r.botoes))
		OS.set_environment("MEM", str(r.get("mem", ""))); OS.set_environment("X4_BIN", d.caminho)
		if au.get("sem_musica", false): OS.set_environment("AUDIO_SEM_XA", "1")
		code = OS.execute(opcao("godot", "FUSION_GODOT", OS.get_executable_path()),
			["--headless", "--path", jogo, "-s", "res://tests/x4_fotos.gd"], out, true)
		for k in ["X4ENV", "X4_SEM_VIDEO", "SAIDA", "QUADROS", "TOTAL", "BOTOES", "MEM", "X4_BIN", "AUDIO_SEM_XA"]: OS.unset_environment(k)
	else:
		code = OS.execute(cap, ["x", bios, "DISC=" + d.caminho, str(int(r.quadros)), str(r.botoes)], out, true)
	for k in quadros:
		if not FileAccess.file_exists(dir.path_join("v_%s.bin" % k)):
			printerr("a captura não fotografou o quadro %s (saída %d): %s" % [k, code, str(out).right(400)]); return -1
	var n := 0
	if r.has("spu"):
		var ram := FileAccess.get_file_as_bytes(dir.path_join("spu_%d.bin" % int(r.spu)))
		if ram.size() != 512 * 1024: printerr("a captura não fotografou a RAM do SPU (saída %d): %s" % [code, str(out).right(400)]); return -1
		for so in r.get("sons", []):
			if not som_da_spu(ram, int(so.addr), int(so.pitch), int(so.vl), int(so.vr), float(r.get("ganho", 1.0)), jogo.path_join(str(so.saida))):
				printerr("som não gravado: ", so.saida); return -1
			n += 1
	if au.has("cortes"):   # pedaços do som como WAV (44,1 kHz, estéreo, 16 bits)
		var raw := FileAccess.get_file_as_bytes(dir.path_join("som.raw"))
		for c in au.cortes:
			var ini := int(c.inicio) * 4; var tam := int(c.amostras) * 4
			if raw.size() < ini + tam: printerr("som curto demais para ", c.saida); return -1
			if not grava_wav(jogo.path_join(str(c.saida)), raw.slice(ini, ini + tam), 44100, 2): return -1
			n += 1
	elif not au.is_empty():
		var raw := FileAccess.get_file_as_bytes(dir.path_join("som.raw"))
		var ini := int(au.inicio) * 4; var tam := int(au.amostras) * 4
		if raw.size() < ini + tam: printerr("som curto demais: %d bytes" % raw.size()); return -1
		var cut := FileAccess.open(dir.path_join("laco.raw"), FileAccess.WRITE); cut.store_buffer(raw.slice(ini, ini + tam)); cut.close()
		var dst := jogo.path_join(str(au.saida))
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var ff := opcao("ffmpeg", "FUSION_FFMPEG", "ffmpeg")
		var o2 := []
		# (o Ogg do PC do dono: número de série e os textos do ffmpeg que o fez; com o nosso ffmpeg.exe sai igual byte a byte)
		OS.set_environment("FUSION_OGG_SERIAIS", str(au.get("serial", ""))); OS.set_environment("FUSION_OGG_VENDOR", str(au.get("vendor", "")))
		var meta := ["-metadata:s:a", "encoder=" + str(au.codificador)] if au.has("codificador") else []
		OS.execute(ff, ["-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", "44100", "-ac", "2", "-i", dir.path_join("laco.raw"),
			"-c:a", "libvorbis", "-q:a", str(au.get("qualidade", 5))] + meta + [dst + ".tmp.ogg"], o2, true)
		OS.unset_environment("FUSION_OGG_SERIAIS"); OS.unset_environment("FUSION_OGG_VENDOR")
		if not FileAccess.file_exists(dst + ".tmp.ogg"): printerr("ffmpeg falhou no som: ", str(o2).right(300)); return -1
		if FileAccess.file_exists(dst): DirAccess.remove_absolute(dst)
		if DirAccess.rename_absolute(dst + ".tmp.ogg", dst) != OK: printerr("não consegui renomear ", dst + ".tmp.ogg"); return -1
		n += 1
	for sp in r.get("sprites", []):
		if not sprite_da_vram(dir, int(sp.quadro), int(sp.linha), int(sp.clut), jogo.path_join(str(sp.saida))): return -1
		n += 1
	if r.has("fusion"):
		if not monta_fusion(dir, str(r.fusion.spec), jogo.path_join(str(r.fusion.saida))): return -1
		n += 1
	if fotos.is_empty():
		for f in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir); DirAccess.remove_absolute(jogo.path_join(".captura"))
		return n
	prog.call(1, 3, "desenhando %d telas" % fotos.size())
	var bases := []
	for k in fotos: bases.append(dir.path_join(k))
	OS.set_environment("JOGO", str(r.jogo)); OS.set_environment("DUMPS", ",".join(bases))
	out = []
	var args := ["--path", jogo, "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3", "-s", "res://tests/render_dump.gd"]
	code = OS.execute(render, args, out, true)
	var faltou := false
	for k in fotos: faltou = faltou or not FileAccess.file_exists(dir.path_join("tela_%s.png" % k))
	var gd := opcao("godot", "FUSION_GODOT", OS.get_executable_path())
	if faltou and gd != render and FileAccess.file_exists(gd):
		# o desenhista por software não abriu neste PC: desenha com a placa de vídeo (pode mudar algum ponto)
		printerr("o desenho por software falhou (saída %d): %s — tentando pela placa de vídeo" % [code, str(out).right(300)])
		out = []
		code = OS.execute(gd, args, out, true)
	for k in fotos:
		var t := dir.path_join("tela_%s.png" % k)
		if not FileAccess.file_exists(t): printerr("não desenhou o quadro %s (saída %d): %s" % [k, code, str(out).right(400)]); return -1
		var dsts: Array = fotos[k] if fotos[k] is Array else [fotos[k]]   # o mesmo quadro pode virar mais de uma imagem
		for dd in dsts:
			var dst := jogo.path_join(str(dd))
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			if str(r.get("cores", "")) == "" and str(r.get("formato", "")) in ["", "png"]:
				DirAccess.copy_absolute(t, dst); n += 1
				continue
			n += salva_foto(r, t, dst)
	prog.call(2, 3, "limpando")
	for f in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir); DirAccess.remove_absolute(jogo.path_join(".captura"))
	prog.call(3, 3, "pronto")
	return n

## grava a foto desenhada com a conversão do roteiro (cores de 5 bits, RGB, WebP)
func salva_foto(r: Dictionary, t: String, dst: String) -> int:
	var im := Image.load_from_file(t)
	im.convert(Image.FORMAT_RGBA8)
	var px := im.get_data()
	if str(r.get("cores", "")) == "5bits":   # cores do desenho antigo: 5 bits por canal << 3 (em vez de *255/31)
		for i in px.size():
			if i % 4 != 3: px[i] = int(round(px[i] * 31.0 / 255.0)) << 3
	im = Image.create_from_data(im.get_width(), im.get_height(), false, Image.FORMAT_RGBA8, px)
	if str(r.get("formato", "")) in ["rgb", "webp"]: im.convert(Image.FORMAT_RGB8)
	if str(r.get("formato", "")) == "webp":
		# o webpenc do fangame (libwebp 1.6.0 pelo mesmo caminho do Pillow) dá o arquivo igual ao do PC do dono
		var we := opcao("webpenc", "FUSION_WEBPENC", "")
		if r.has("webp") and we != "" and FileAccess.file_exists(we):
			var cru := dst + ".rgb"
			var fc := FileAccess.open(cru, FileAccess.WRITE)
			if fc == null: return 0
			fc.store_buffer(im.get_data()); fc.close()
			var o := []
			var cod := OS.execute(we, [cru, str(im.get_width()), str(im.get_height()), str(r.webp.qualidade), str(r.webp.metodo), dst + ".tmp"], o, true)
			DirAccess.remove_absolute(cru)
			if cod != 0 or not FileAccess.file_exists(dst + ".tmp"): printerr("webpenc falhou em %s: %s" % [dst, str(o).right(300)]); return 0
			if FileAccess.file_exists(dst): DirAccess.remove_absolute(dst)
			return 1 if DirAccess.rename_absolute(dst + ".tmp", dst) == OK else 0
		return 1 if im.save_webp(dst, true, float(r.get("qualidade", 0.83))) == OK else 0
	return 1 if im.save_png(dst) == OK else 0

## miniaturas dos chefes: recorte da tela de seleção com a máscara do retrato (tools/extrator/mini, nossa) + versão cinza
## (mesma conta do hub_masks.py: cinza do PIL (R*19595+G*38470+B*7471+0x8000)>>16, vezes 0,55 truncado)
func miniaturas(jg: String, jogo: String, prog: Callable) -> int:
	var lista = JSON.parse_string(FileAccess.get_file_as_string("res://mini/mini.json"))
	var ks := []
	for k in lista:
		if str(k).begins_with(jg + "_"): ks.append(k)
	var n := 0
	for k in ks:
		var e: Dictionary = lista[k]
		var tela := Image.load_from_file(jogo.path_join("assets/menus/" + str(e.tela)))
		if tela == null: printerr("falta a tela ", e.tela); return -1
		tela.convert(Image.FORMAT_RGBA8)
		var mk := Image.load_from_file(ProjectSettings.globalize_path("res://mini/%s.png" % k))
		mk.convert(Image.FORMAT_L8)
		var w := mk.get_width(); var h := mk.get_height()
		var cr := tela.get_region(Rect2i(int(e.x), int(e.y), w, h))
		var px := cr.get_data(); var al := mk.get_data()
		var cz := px.duplicate()
		for i in w * h:
			px[i * 4 + 3] = al[i]
			var l := (px[i * 4] * 19595 + px[i * 4 + 1] * 38470 + px[i * 4 + 2] * 7471 + 0x8000) >> 16
			var v := int(l * 0.55)
			cz[i * 4] = v; cz[i * 4 + 1] = v; cz[i * 4 + 2] = v; cz[i * 4 + 3] = al[i]
		DirAccess.make_dir_recursive_absolute(jogo.path_join("assets/menus/mini"))
		Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px).save_png(jogo.path_join("assets/menus/mini/%s.png" % k))
		Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, cz).save_png(jogo.path_join("assets/menus/mini/%s_cinza.png" % k))
		n += 2
		prog.call(n, ks.size() * 2, "miniaturas do " + jg.to_upper())
	return n

# ---------------- código do X4: decompilação pública (sozud/mmx4) + nossas mudanças, compilada aqui ----------------
const MMX4_COMMIT := "4e16dfc7c06597fd5719dd112654d8cf85d343c2"
const PSYZ_COMMIT := "da55621adf3b293a1f9693d401dc21aab5ef971d"   # submódulo tools/psyz (sozud/psyz, ramo mmx4)

func pasta_x4core() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../x4core").simplify_path()

## baixa um arquivo por HTTPS seguindo redirecionamentos (o GitHub manda para codeload.github.com)
func baixa(url: String, destino: String) -> bool:
	for tentativa in 5:
		var u := url.trim_prefix("https://")
		var host := u.get_slice("/", 0); var caminho := u.substr(host.length())
		var c := HTTPClient.new()
		if c.connect_to_host(host, 443, TLSOptions.client()) != OK: return false
		while c.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]: c.poll(); OS.delay_msec(20)
		if c.get_status() != HTTPClient.STATUS_CONNECTED: printerr("sem conexão com ", host); return false
		c.request(HTTPClient.METHOD_GET, caminho, ["User-Agent: MegaManXFusion"])
		while c.get_status() == HTTPClient.STATUS_REQUESTING: c.poll(); OS.delay_msec(20)
		var cod := c.get_response_code()
		if cod in [301, 302, 303, 307, 308]:
			url = str(c.get_response_headers_as_dictionary().get("Location", c.get_response_headers_as_dictionary().get("location", "")))
			continue
		if cod != 200: printerr("baixar %s: erro %d" % [url, cod]); return false
		var f := FileAccess.open(destino, FileAccess.WRITE)
		while c.get_status() == HTTPClient.STATUS_BODY:
			c.poll()
			var ch := c.read_response_body_chunk()
			if ch.size() > 0: f.store_buffer(ch)
			else: OS.delay_msec(5)
		f.close()
		return true
	return false

## extrai um zip do GitHub (tira a pasta de cima) em pasta
func extrai(zip: String, pasta: String) -> bool:
	var z := ZIPReader.new()
	if z.open(zip) != OK: return false
	for f in z.get_files():
		var rel := f.substr(f.find("/") + 1)
		if rel == "" or rel.ends_with("/"): continue
		var dst := pasta.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var w := FileAccess.open(dst, FileAccess.WRITE)
		if w: w.store_buffer(z.read_file(f))
	z.close()
	return true

## aplica um "git diff" (as nossas mudanças) numa árvore de fontes
func aplica_patch(raiz: String, texto: String) -> bool:
	var ls := texto.split("\n")
	if ls.size() > 0 and ls[ls.size() - 1] == "": ls.remove_at(ls.size() - 1)
	var i := 0
	while i < ls.size():
		if not ls[i].begins_with("--- "): i += 1; continue
		var alvo := ls[i + 1].substr(6)   # "+++ b/caminho"
		i += 2
		var arq := raiz.path_join(alvo)
		var orig := FileAccess.get_file_as_string(arq).split("\n") if FileAccess.file_exists(arq) else PackedStringArray()
		var linhas := Array(orig)
		var desloc := 0
		while i < ls.size() and ls[i].begins_with("@@"):
			var ini := int(ls[i].get_slice(" ", 1).get_slice(",", 0).substr(1)) - 1
			i += 1
			var velhas := []; var novas := []
			while i < ls.size() and not ls[i].begins_with("@@") and not ls[i].begins_with("diff --git"):
				var l: String = ls[i]
				if l.begins_with(" "): velhas.append(l.substr(1)); novas.append(l.substr(1))
				elif l.begins_with("-"): velhas.append(l.substr(1))
				elif l.begins_with("+"): novas.append(l.substr(1))
				i += 1
			var pos := -1
			for d in range(0, 200):
				for p2 in [ini + desloc + d, ini + desloc - d]:
					if p2 < 0 or p2 + velhas.size() > linhas.size(): continue
					if linhas.slice(p2, p2 + velhas.size()) == velhas: pos = p2; break
				if pos >= 0: break
			if pos < 0: printerr("o patch não encaixou em ", alvo); return false
			linhas = linhas.slice(0, pos) + novas + linhas.slice(pos + velhas.size())
			desloc += novas.size() - velhas.size()
		var w := FileAccess.open(arq, FileAccess.WRITE)
		w.store_string("\n".join(PackedStringArray(linhas)))
		w.close()
	return true

func codigo_x4(jogo: String, prog: Callable) -> int:
	var x4 := pasta_x4core()
	var base := opcao("fontes", "FUSION_FONTES", jogo.path_join("../gerado/fontes")).simplify_path()
	var src := base.path_join("mmx4")
	if not FileAccess.file_exists(src.path_join(".pronto")):
		prog.call(0, 10, "baixando a decompilação do X4 (pública)")
		DirAccess.make_dir_recursive_absolute(base)
		var zm := opcao("zip_mmx4", "", base.path_join("mmx4.zip")); var zp := opcao("zip_psyz", "", base.path_join("psyz.zip"))
		if not FileAccess.file_exists(zm) and not baixa("https://github.com/sozud/mmx4/archive/%s.zip" % MMX4_COMMIT, zm): return -1
		if not FileAccess.file_exists(zp) and not baixa("https://github.com/sozud/psyz/archive/%s.zip" % PSYZ_COMMIT, zp): return -1
		if not extrai(zm, src) or not extrai(zp, src.path_join("tools/psyz")): printerr("zip estragado"); return -1
		if not aplica_patch(src, FileAccess.get_file_as_string(x4.path_join("mmx4.patch"))): return -1
		if not aplica_patch(src.path_join("tools/psyz"), FileAccess.get_file_as_string(x4.path_join("psyz.patch"))): return -1
		DirAccess.make_dir_recursive_absolute(src.path_join("src/godot"))
		DirAccess.copy_absolute(x4.path_join("frame.c"), src.path_join("src/godot/frame.c"))
		FileAccess.open(src.path_join(".pronto"), FileAccess.WRITE).store_string(MMX4_COMMIT)
	# compila (mesmas opções do build.sh do PC do dono)
	var cc := opcao("clang", "FUSION_CLANG", "clang")
	var ld := opcao("lld", "FUSION_LLD", "ld.lld")
	var win := opcao("alvo", "", "windows" if OS.get_name() == "Windows" else "linux") == "windows"
	var out := []
	OS.execute(cc, ["-print-resource-dir"], out)
	var cinc := str(out[0]).strip_edges().path_join("include")
	var fl := ["-O2", "-w", "-std=gnu11", "-ffreestanding", "-fno-strict-aliasing", "-fno-stack-protector", "-fno-exceptions",
		"-fno-asynchronous-unwind-tables", "-nostdinc", "-isystem", cinc, "-isystem", x4.path_join("sysroot"), "-DMMX4_PC=1", "-D__psyz=1",
		"-DSKIP_MDEC=1", "-DVERSION_US=1", "-DX4CORE=1", "-Wno-error=incompatible-function-pointer-types", "-Wno-error=int-conversion",
		"-Wno-error=implicit-function-declaration", "-Wno-error=implicit-int", "-Wno-error=return-type",
		"-Wno-error=incompatible-pointer-types"]   # (o clang novo trata estes avisos da decompilação como erro)
	fl += ["--target=x86_64-pc-windows-msvc", "-mno-stack-arg-probe", "-fms-extensions"] if win else ["--target=x86_64-linux-gnu", "-fPIC", "-fvisibility=hidden"]
	var inc := ["-I" + src.path_join("include"), "-I" + src.path_join("tools/psyz/psyz/include")]
	var ainc := ["-I" + src.path_join("tools/psyz/psyz/include"), "-I" + src.path_join("tools/psyz/decomp/include")]
	var lista := []   # [fonte, opções]
	for l in FileAccess.get_file_as_string(x4.path_join("srclist.txt")).split("\n", false):
		var extra := ["-Dfunc_80018000=func_80018000_original"] if l.ends_with("/55C4.c") else []
		lista.append([src.path_join(l), fl + inc + extra])
	for f in ["marca_inicio.c", "marca_fim.c", "runtime.c", "fangame.c", "stubs_gen.c", "gdext.c", "memcard_x4.c"]:
		lista.append([x4.path_join(f), fl + inc + ["-I" + x4, "-I" + src.path_join("src")]])
	for l in FileAccess.get_file_as_string(x4.path_join("audio_srcs.txt")).split("\n", false):
		lista.append([src.path_join(l), fl + ainc])
	var obj := base.path_join("obj_" + ("win" if win else "linux"))
	DirAccess.make_dir_recursive_absolute(obj)
	var erros := []; var feitos := [0]; var mx := Mutex.new()
	var trabalho := func(ini: int, passo: int) -> void:
		for k in range(ini, lista.size(), passo):
			var f: String = lista[k][0]
			var o := obj.path_join(f.trim_prefix(src).trim_prefix(x4).replace("/", "_").replace("\\", "_") + ".o")
			var r := []
			var cod := OS.execute(cc, lista[k][1] + ["-c", f, "-o", o], r, true)
			mx.lock(); feitos[0] += 1
			if cod != 0: erros.append(f + ": " + str(r).left(300))
			mx.unlock()
	var ths := []
	var n := maxi(2, OS.get_processor_count())
	for t in n:
		var th := Thread.new(); th.start(trabalho.bind(t, n)); ths.append(th)
	while true:
		var vivos := 0
		for th in ths: if th.is_alive(): vivos += 1
		prog.call(1 + int(8.0 * feitos[0] / lista.size()), 10, "compilando o X4 (%d/%d)" % [feitos[0], lista.size()])
		if vivos == 0: break
		OS.delay_msec(250)
	for th in ths: th.wait_to_finish()
	if not erros.is_empty(): printerr("erros ao compilar:\n", "\n".join(erros.slice(0, 5))); return -1
	prog.call(9, 10, "juntando")
	var objs := []
	for k in lista:
		var f: String = k[0]
		objs.append(obj.path_join(f.trim_prefix(src).trim_prefix(x4).replace("/", "_").replace("\\", "_") + ".o"))
	# gdext primeiro e as marcas em volta (o estado salvo usa o intervalo entre marca_inicio e marca_fim)
	var gd: String = objs.filter(func(o): return o.ends_with("_gdext.c.o"))[0]
	var mi: String = objs.filter(func(o): return o.ends_with("_marca_inicio.c.o"))[0]
	var mf: String = objs.filter(func(o): return o.ends_with("_marca_fim.c.o"))[0]
	var meio := objs.filter(func(o): return o != gd and o != mi and o != mf)
	var ordem := [gd, mi] + meio + [mf]
	DirAccess.make_dir_recursive_absolute(jogo.path_join("bin"))
	var r2 := []
	var cod2: int
	# a lista de objetos vai num arquivo de resposta (@arquivo): no Windows a linha de comando tem limite de 32 mil letras
	var rsp := lista_resposta(obj.path_join("objetos.rsp"), ordem)
	if win:
		cod2 = OS.execute(ld, ["-flavor", "link", "/dll", "/noentry", "/nodefaultlib", "/out:" + jogo.path_join("bin/x4core.dll"),
			"/base:0x10000000", "/dynamicbase:no", "/opt:ref", "@" + rsp, "/export:x4core_init"], r2, true)
	else:
		cod2 = OS.execute(ld, ["-shared", "-o", jogo.path_join("bin/libx4core.so"), "@" + rsp, "--gc-sections", "-z", "defs"], r2, true)
	if cod2 != 0: printerr("erro ao juntar: ", str(r2).left(800)); return -1
	var ge := FileAccess.open(jogo.path_join("bin/x4core.gdextension"), FileAccess.WRITE)
	ge.store_string('[configuration]\nentry_symbol = "x4core_init"\ncompatibility_minimum = "4.4"\n\n[libraries]\nwindows.x86_64 = "res://bin/x4core.dll"\nlinux.x86_64 = "res://bin/libx4core.so"\n')
	ge.close()
	prog.call(10, 10, "pronto")
	return 1

## som da RAM do SPU (ADPCM do PS1) como WAV estéreo de 16 bits: altura = a do key-on (44100 * pitch / 4096, arredondado
## como o Python), volume de cada lado = vol / 0x3FFF vezes o ganho, cortado para o zero (mesmas contas do spu_render.py)
const ADPCM_F := [[0, 0], [60, 0], [115, -52], [98, -55], [122, -60]]
func som_da_spu(ram: PackedByteArray, addr: int, pitch: int, vl: int, vr: int, ganho: float, saida: String) -> bool:
	var amostras := PackedInt32Array()
	var h1 := 0; var h2 := 0; var a := addr
	for n in 20000:
		var hdr := ram[a]; var flags := ram[a + 1]
		var sh := hdr & 15; var filt := (hdr >> 4) & 7
		var f: Array = ADPCM_F[filt if filt < 5 else 0]
		for i in 28:
			var nib := (ram[a + 2 + i / 2] >> ((i & 1) * 4)) & 15
			if nib >= 8: nib -= 16
			var v := ((nib << 12) >> sh) + ((h1 * int(f[0]) + h2 * int(f[1]) + 32) >> 6)
			v = clampi(v, -32768, 32767); h2 = h1; h1 = v
			amostras.append(v)
		if flags & 1: break
		a = (a + 16) & 0x7FFFF
	var x := 44100.0 * pitch / 4096.0
	var taxa := int(floor(x)); var fr: float = x - floor(x)
	if fr > 0.5 or (fr == 0.5 and taxa % 2 == 1): taxa += 1   # round() do Python: empate vai para o par
	var gl := (vl if vl < 0x4000 else 0) / float(0x3FFF); var gr := (vr if vr < 0x4000 else 0) / float(0x3FFF)
	var dados := PackedByteArray(); dados.resize(amostras.size() * 4)
	for i in amostras.size():
		var s := float(amostras[i])
		dados.encode_s16(i * 4, int(clampf(s * gl * ganho, -32768.0, 32767.0)))
		dados.encode_s16(i * 4 + 2, int(clampf(s * gr * ganho, -32768.0, 32767.0)))
	var cab := PackedByteArray(); cab.resize(44)
	cab.encode_u32(0, 0x46464952); cab.encode_u32(4, 36 + dados.size()); cab.encode_u32(8, 0x45564157)   # RIFF ... WAVE
	cab.encode_u32(12, 0x20746d66); cab.encode_u32(16, 16); cab.encode_u16(20, 1); cab.encode_u16(22, 2)  # "fmt " PCM estéreo
	cab.encode_u32(24, taxa); cab.encode_u32(28, taxa * 4); cab.encode_u16(32, 4); cab.encode_u16(34, 16)
	cab.encode_u32(36, 0x61746164); cab.encode_u32(40, dados.size())   # "data"
	DirAccess.make_dir_recursive_absolute(saida.get_base_dir())
	var w := FileAccess.open(saida, FileAccess.WRITE)
	if w == null: return false
	w.store_buffer(cab); w.store_buffer(dados); w.close()
	return true

# ---------------- recompilação do X5/X6 (psxrecomp): o código do jogo é gerado do disco e compilado AQUI ----------------
## kit (ferramentas/recomp, montado por tools/recomp/kit.py): objetos do runtime já compilados, bibliotecas, recompilador.
## 1) tira o executável do disco (bin/recomp_xN/mmxN/SLUS_...), 2) o recompilador gera o C, 3) o clang compila,
## 4) o ld.lld junta tudo na DLL bin/xNrecomp.dll (mesma lista e ordem da DLL do PC do dono), 5) a extensão do Godot.
func codigo_recomp(g: String, jogo: String, discos: Dictionary, prog: Callable) -> int:
	if OS.get_name() != "Windows" and opcao("forcar", "", "") == "":
		print("%s: a recompilação só é montada no Windows (aqui o jogo usa o núcleo de PS1)" % g); return 0
	var kit := opcao("kit", "FUSION_KIT_RECOMP", "").simplify_path()
	var kj = JSON.parse_string(FileAccess.get_file_as_string(kit.path_join(g + "/kit.json")))
	if not kj is Dictionary: printerr("kit da recompilação não encontrado em ", kit); return -1
	var k: Dictionary = kj
	var cc := opcao("clang", "FUSION_CLANG", "clang"); var ld := opcao("lld", "FUSION_LLD", "ld.lld")
	var trab := opcao("fontes", "FUSION_FONTES", jogo.path_join("../gerado/fontes")).simplify_path().path_join("recomp_" + g)
	var gen := trab.path_join("generated")
	DirAccess.make_dir_recursive_absolute(gen)
	# 1) executável do jogo, de dentro do disco
	prog.call(0, 10, "lendo o disco")
	var d: Disco = discos[g]
	var arqs := d.arquivos()
	if not arqs.has(str(k.exe)): printerr("o disco não tem ", k.exe); return -1
	var e: Array = arqs[str(k.exe)]
	var exe_bytes := d.dados(int(e[0]), (int(e[1]) + 2047) / 2048).slice(0, int(e[1]))
	var rt := jogo.path_join("bin/recomp_" + g)
	if not escreve(jogo, "bin/recomp_%s/%s/%s" % [g, k.pasta, k.exe], exe_bytes): return -1
	# 2) recompilador (configuração do projeto com os nossos ganchos; caminhos absolutos: o recompilador roda daqui)
	prog.call(1, 10, "gerando o código do jogo")
	var cfg := FileAccess.get_file_as_string(kit.path_join(g + "/recompilar/game.toml"))
	var rc := kit.path_join(g + "/recompilar")
	var linhas := []
	for ln in cfg.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("exe ="): ln = 'exe = "%s"' % rt.path_join("%s/%s" % [k.pasta, k.exe])
		elif t.begins_with("seeds ="): ln = 'seeds = "%s"' % rc.path_join("seeds/ghidra_funcs.txt")
		elif t.begins_with("bios_config ="): ln = 'bios_config = "%s"' % rc.path_join("bios/SCPH1001.toml")
		elif t.begins_with("out_dir ="): ln = 'out_dir = "%s"' % gen
		linhas.append(ln)
	var cfg_tmp := trab.path_join("game.toml")
	var fc := FileAccess.open(cfg_tmp, FileAccess.WRITE); fc.store_string("\n".join(linhas)); fc.close()
	var out := []
	var cod := OS.execute(kit.path_join("psxrecomp-game.exe"), ["--config", cfg_tmp], out, true)
	for f in k.gerados:
		if not FileAccess.file_exists(gen.path_join(str(f))): printerr("o recompilador não gerou %s (saída %d): %s" % [f, cod, str(out).right(500)]); return -1
	# 3) compila o código gerado (mesmas definições e otimização da DLL do PC do dono)
	var fl := ["--target=x86_64-w64-mingw32", "-nostdinc", "-isystem", kit.path_join("sysinc/clang"), "-isystem", kit.path_join("sysinc/mingw"),
		"-I" + kit.path_join(g + "/include"), "-I" + gen, "-w"] + Array(k.defines) + Array(k.flags)
	var lista := []
	for f in k.gerados: lista.append([gen.path_join(str(f)), fl])
	var objs := compila(lista, trab.path_join("obj"), cc, func(a: int, b: int, t := "") -> void: prog.call(2 + a * 6 / 10, 10, t), "compilando o " + g.to_upper())
	if objs.is_empty(): return -1
	# 4) junta (a ordem é a da DLL do PC do dono: objetos de antes, o código do jogo, objetos de depois, os nossos)
	prog.call(9, 10, "juntando")
	var lib := kit.path_join("lib"); var kg := kit.path_join(g)
	var args: Array = Array(k.inicio) + ["-o", jogo.path_join("bin/%srecomp.dll" % g), lib.path_join("dllcrt2.o"), lib.path_join("crtbegin.o"),
		"-L" + lib] + Array(k.pilha)
	for r in k.res: args.append(kg.path_join("res/" + str(r)))
	args += ["--whole-archive", kg.path_join("antes.a"), "--no-whole-archive"] + objs
	args += ["--whole-archive", kg.path_join("depois.a"), "--no-whole-archive"]
	for o in k.emb: args.append(kg.path_join(str(o)))
	for a in k.ligar:
		var s2 := str(a)
		if s2.begins_with("deps/"): args.append(kg.path_join(s2))
		elif s2.begins_with("lib/"): args.append(kit.path_join(s2))
		else: args.append(s2)
	var rsp := lista_resposta(trab.path_join("ligar.rsp"), args)
	var r2 := []
	if OS.execute(ld, ["@" + rsp], r2, true) != 0: printerr("erro ao juntar a recompilação: ", str(r2).left(1500)); return -1
	# 5) extensão do Godot e a pasta de execução (configuração, BIOS)
	var ge := FileAccess.open(jogo.path_join("bin/recomp_%s.gdextension" % g), FileAccess.WRITE)
	ge.store_string('[configuration]\nentry_symbol = "recomp_%s_init"\ncompatibility_minimum = "4.4"\n\n[libraries]\nwindows.x86_64 = "res://bin/%srecomp.dll"\n' % [g, g])
	ge.close()
	DirAccess.make_dir_recursive_absolute(rt.path_join("bios"))
	DirAccess.copy_absolute(kg.path_join("execucao/game.toml"), rt.path_join("game.toml"))
	for f in ["openbios.bin", "OpenBIOS.LICENSE"]: DirAccess.copy_absolute(kg.path_join("execucao/bios/" + f), rt.path_join("bios/" + f))
	# o código gerado e os objetos (uns 150 MB, saídos do disco) não precisam ficar: a DLL já está pronta
	for sub in ["generated", "obj"]:
		for f in DirAccess.get_files_at(trab.path_join(sub)): DirAccess.remove_absolute(trab.path_join(sub).path_join(f))
		DirAccess.remove_absolute(trab.path_join(sub))
	prog.call(10, 10, "pronto")
	return 1

## WAV PCM de 16 bits (o mesmo cabeçalho de 44 bytes do módulo wave do Python)
func grava_wav(saida: String, dados: PackedByteArray, taxa: int, canais: int) -> bool:
	var cab := PackedByteArray(); cab.resize(44)
	cab.encode_u32(0, 0x46464952); cab.encode_u32(4, 36 + dados.size()); cab.encode_u32(8, 0x45564157)
	cab.encode_u32(12, 0x20746d66); cab.encode_u32(16, 16); cab.encode_u16(20, 1); cab.encode_u16(22, canais)
	cab.encode_u32(24, taxa); cab.encode_u32(28, taxa * 2 * canais); cab.encode_u16(32, 2 * canais); cab.encode_u16(34, 16)
	cab.encode_u32(36, 0x61746164); cab.encode_u32(40, dados.size())
	DirAccess.make_dir_recursive_absolute(saida.get_base_dir())
	var w := FileAccess.open(saida, FileAccess.WRITE)
	if w == null: printerr("não consegui escrever ", saida); return false
	w.store_buffer(cab); w.store_buffer(dados); w.close()
	return true

## arquivo de resposta do ligador: um caminho por linha, entre aspas (os caminhos podem ter espaços)
func lista_resposta(caminho: String, objs: Array) -> String:
	var f := FileAccess.open(caminho, FileAccess.WRITE)
	for o in objs: f.store_string('"%s"\n' % str(o).replace("\\", "/"))
	f.close()
	return caminho

## sprites 16x16 de uma linha da tela, direto da VRAM fotografada (sem desenhar): página de 4 bits, uma CLUT,
## cor 0 = transparente, cores 5 bits << 3; recorta nos pontos opacos
func sprite_da_vram(dir: String, q: int, linha: int, clut_alvo: int, saida: String) -> bool:
	var vb := FileAccess.get_file_as_bytes(dir.path_join("v_%d.bin" % q))
	var w := FileAccess.get_file_as_bytes(dir.path_join("p_%d.bin" % q)).to_int32_array()
	if vb.size() != 1024 * 512 * 2: printerr("VRAM do quadro %d faltando" % q); return false
	var v := vb.to_int32_array()   # 2 pontos de 16 bits por inteiro
	var vram := func(x: int, y: int) -> int:
		var k := (y & 511) * 1024 + (x & 1023)
		return (v[k >> 1] >> ((k & 1) * 16)) & 0xFFFF
	var img := PackedByteArray(); img.resize(320 * 240 * 4)
	var ip := 0; var tpx := 0; var tpy := 0; var tdep := 0
	var x0 := 320; var y0 := 240; var x1 := -1; var y1 := -1
	while ip < w.size():
		var ws: int = w[ip]; var o := ip + 1; ip += ws + 1
		if ws <= 0: break
		var w0: int = w[o]; var cmd := (w0 >> 24) & 0xFF
		if cmd == 0xE1: tpx = (w0 & 15) * 64; tpy = ((w0 >> 4) & 1) * 256; tdep = (w0 >> 7) & 3; continue
		if cmd < 0x7C or cmd > 0x7F: continue
		var xy: int = w[o + 1]; var x := xy & 0x7FF; var y := (xy >> 16) & 0x7FF
		var uv: int = w[o + 2]; var clut := (uv >> 16) & 0xFFFF
		if y != linha or clut != clut_alvo or tdep != 0: continue
		var u := uv & 0xFF; var vv := (uv >> 8) & 0xFF
		var cx := (clut & 0x3F) * 16; var cy := (clut >> 6) & 0x1FF
		for j in 16:
			for i in 16:
				var tu := (u + i) & 255; var tv := (vv + j) & 255
				var wd: int = vram.call(tpx + (tu >> 2), tpy + tv)
				var c: int = vram.call(cx + ((wd >> ((tu & 3) * 4)) & 15), cy)
				var X := x + i; var Y := y + j
				if c == 0 or X < 0 or X >= 320 or Y < 0 or Y >= 240: continue
				var k := (Y * 320 + X) * 4
				img[k] = (c & 31) << 3; img[k + 1] = ((c >> 5) & 31) << 3; img[k + 2] = ((c >> 10) & 31) << 3; img[k + 3] = 255
				x0 = mini(x0, X); y0 = mini(y0, Y); x1 = maxi(x1, X); y1 = maxi(y1, Y)
	if x1 < 0: printerr("nenhum sprite na linha %d com a CLUT %x no quadro %d" % [linha, clut_alvo, q]); return false
	var im := Image.create_from_data(320, 240, false, Image.FORMAT_RGBA8, img).get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
	DirAccess.make_dir_recursive_absolute(saida.get_base_dir())
	return im.save_png(saida) == OK

## FUSION do título: letras da página de texto do menu do X5 (do disco) + o nosso retoque (fusion.json)
func monta_fusion(dir: String, spec_path: String, saida: String) -> bool:
	var sp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	var v := FileAccess.get_file_as_bytes(dir.path_join("v_%d.bin" % int(sp.quadro))).to_int32_array()
	if v.size() != 1024 * 512 / 2: printerr("VRAM do quadro %d faltando" % int(sp.quadro)); return false
	var vram := func(x: int, y: int) -> int:
		var k := (y & 511) * 1024 + (x & 1023)
		return (v[k >> 1] >> ((k & 1) * 16)) & 0xFFFF
	var pgx := int(sp.pagina[0]); var pgy := int(sp.pagina[1]); var clut := int(sp.clut)
	var cx := (clut & 0x3F) * 16; var cy := (clut >> 6) & 0x1FF
	var W := int(sp.largura); var H := int(sp.altura); var l0 := int(sp.linha)
	var img := PackedByteArray(); img.resize(W * H * 4)
	for le in sp.letras:
		for x in range(maxi(0, int(le.de)), mini(W, int(le.ate))):
			var tu := x + int(le.desloc)
			if tu < 0 or tu > 255: continue
			for y in H:
				var wd: int = vram.call(pgx + (tu >> 2), pgy + l0 + y)
				var c: int = vram.call(cx + ((wd >> ((tu & 3) * 4)) & 15), cy)
				if c == 0: continue
				var k := (y * W + x) * 4
				img[k] = (c & 31) << 3; img[k + 1] = ((c >> 5) & 31) << 3; img[k + 2] = ((c >> 10) & 31) << 3; img[k + 3] = 255
	for rt in sp.retoque:   # [y, x, r, g, b, a]: o nosso retoque
		var k := (int(rt[0]) * W + int(rt[1])) * 4
		for c in 4: img[k + c] = int(rt[2 + c])
	DirAccess.make_dir_recursive_absolute(saida.get_base_dir())
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, img).save_png(saida) == OK

## compila uma lista [[fonte, opções], ...] em paralelo; devolve os .o na mesma ordem (ou [] se der erro)
func compila(lista: Array, obj: String, cc: String, prog: Callable, rotulo: String) -> Array:
	DirAccess.make_dir_recursive_absolute(obj)
	var saidas := []
	for k in lista.size(): saidas.append(obj.path_join("%03d_%s.o" % [k, str(lista[k][0]).get_file()]))
	var erros := []; var feitos := [0]; var mx := Mutex.new()
	var trabalho := func(ini: int, passo: int) -> void:
		for k in range(ini, lista.size(), passo):
			var r := []
			var cod := OS.execute(cc, lista[k][1] + ["-c", lista[k][0], "-o", saidas[k]], r, true)
			mx.lock(); feitos[0] += 1
			if cod != 0: erros.append(str(lista[k][0]) + ": " + str(r).left(300))
			mx.unlock()
	var ths := []
	var n := maxi(2, OS.get_processor_count())
	for t in n:
		var th := Thread.new(); th.start(trabalho.bind(t, n)); ths.append(th)
	while true:
		var vivos := 0
		for th in ths: if th.is_alive(): vivos += 1
		prog.call(1 + int(8.0 * feitos[0] / maxi(1, lista.size())), 10, "%s (%d/%d)" % [rotulo, feitos[0], lista.size()])
		if vivos == 0: break
		OS.delay_msec(250)
	for th in ths: th.wait_to_finish()
	if not erros.is_empty(): printerr("erros ao compilar:\n", "\n".join(erros.slice(0, 5))); return []
	return saidas

## núcleo de PS1 (nosso: tools/psxcore) como extensão do Godot; o SPU vem do psyz baixado junto com a decompilação do X4
func codigo_psx(jogo: String, prog: Callable) -> int:
	var x4 := pasta_x4core(); var px := x4.path_join("../psxcore").simplify_path()
	var base := opcao("fontes", "FUSION_FONTES", jogo.path_join("../gerado/fontes")).simplify_path()
	var ps := base.path_join("mmx4/tools/psyz")
	if not FileAccess.file_exists(ps.path_join("psyz/src/psyz/libspu.c")): printerr("falta o psyz (rode o código do X4 antes)"); return -1
	var cc := opcao("clang", "FUSION_CLANG", "clang")
	var ld := opcao("lld", "FUSION_LLD", "ld.lld")
	var win := opcao("alvo", "", "windows" if OS.get_name() == "Windows" else "linux") == "windows"
	var out := []
	OS.execute(cc, ["-print-resource-dir"], out)
	var cinc := str(out[0]).strip_edges().path_join("include")
	var fl := ["-O2", "-w", "-std=gnu11", "-ffreestanding", "-fno-strict-aliasing", "-fno-stack-protector", "-fno-exceptions",
		"-fno-asynchronous-unwind-tables", "-nostdinc", "-isystem", cinc, "-isystem", x4.path_join("sysroot")]
	fl += ["--target=x86_64-pc-windows-msvc", "-mno-stack-arg-probe", "-fms-extensions"] if win else ["--target=x86_64-linux-gnu", "-fPIC", "-fvisibility=hidden"]
	# as definições com aspas vão num cabeçalho (aspas na linha de comando se perdem no caminho até o compilador)
	DirAccess.make_dir_recursive_absolute(base)
	var hdef := base.path_join("psxcore_def.h")
	var fh := FileAccess.open(hdef, FileAccess.WRITE)
	fh.store_string('#define GDEXT_CLASS "PsxCore"\n#define GDEXT_ENTRY psxcore_init\n#define PSXCORE 1\n'); fh.close()
	var lista := [[x4.path_join("gdext.c"), fl + ["-I" + x4, "-include", hdef]],
		[x4.path_join("marca_inicio.c"), fl + ["-I" + px]]]
	for f in ["cpu.c", "gte.c", "hw.c", "api.c"]: lista.append([px.path_join(f), fl + ["-I" + px]])
	for f in ["psyz/src/psyz/psyz_spu.c", "psyz/src/psyz/libspu.c"]:
		lista.append([ps.path_join(f), fl + ["-D__psyz=1", "-I" + ps.path_join("psyz/include"), "-I" + ps.path_join("decomp/include")]])
	lista.append([x4.path_join("marca_fim.c"), fl + ["-I" + px]])
	var objs := compila(lista, base.path_join("obj_psx_" + ("win" if win else "linux")), cc, prog, "compilando o núcleo de PS1")
	if objs.is_empty(): return -1
	prog.call(9, 10, "juntando")
	DirAccess.make_dir_recursive_absolute(jogo.path_join("bin"))
	var r := []; var cod: int
	if win:
		var k32 := opcao("kernel32", "", cc.get_base_dir().path_join("../x86_64-w64-mingw32/lib/libkernel32.a").simplify_path())
		cod = OS.execute(ld, ["-flavor", "link", "/dll", "/noentry", "/nodefaultlib", "/out:" + jogo.path_join("bin/psxcore.dll"), "/opt:ref",
			"@" + lista_resposta(base.path_join("objetos_psx.rsp"), objs + [k32]), "/export:psxcore_init"], r, true)
	else:
		cod = OS.execute(ld, ["-shared", "-o", jogo.path_join("bin/libpsxcore.so"), "@" + lista_resposta(base.path_join("objetos_psx.rsp"), objs), "--gc-sections"], r, true)
	if cod != 0: printerr("erro ao juntar: ", str(r).left(800)); return -1
	var ge := FileAccess.open(jogo.path_join("bin/psxcore.gdextension"), FileAccess.WRITE)
	ge.store_string('[configuration]\nentry_symbol = "psxcore_init"\ncompatibility_minimum = "4.4"\n\n[libraries]\nwindows.x86_64 = "res://bin/psxcore.dll"\nlinux.x86_64 = "res://bin/libpsxcore.so"\n')
	ge.close()
	var cap := x4.path_join("../captura").simplify_path()
	DirAccess.copy_absolute(cap.path_join("openbios.bin"), jogo.path_join("bin/openbios.bin"))
	DirAccess.copy_absolute(cap.path_join("OpenBIOS.LICENSE.txt"), jogo.path_join("bin/OpenBIOS.LICENSE.txt"))
	prog.call(10, 10, "pronto")
	return 1

## compilador para o PC do jogador (Windows): llvm-mingw (GitHub mstorsjo/llvm-mingw), só o que precisamos dele
const LLVM_MINGW := "20261104"
func ferramentas(prog: Callable) -> int:
	var cl := opcao("clang", "FUSION_CLANG", "")
	if (OS.get_name() != "Windows" and opcao("forcar", "", "") == "") or cl == "" or FileAccess.file_exists(cl): return 0
	var pasta := cl.get_base_dir().get_base_dir()   # .../ferramentas/llvm
	var zip := opcao("zip_llvm", "", pasta + ".zip")
	if not FileAccess.file_exists(zip):
		prog.call(0, 10, "baixando o compilador (llvm-mingw, ~190 MB)")
		var nome := "llvm-mingw-%s-ucrt-x86_64.zip" % LLVM_MINGW
		if not baixa("https://github.com/mstorsjo/llvm-mingw/releases/download/%s/%s" % [LLVM_MINGW, nome], zip): return -1
	prog.call(5, 10, "abrindo o compilador")
	var z := ZIPReader.new()
	if z.open(zip) != OK: printerr("zip do compilador estragado"); return -1
	var n := 0
	for f in z.get_files():
		var rel := f.substr(f.find("/") + 1)
		var quer := rel in ["bin/clang.exe", "bin/clang-23.exe", "bin/ld.lld.exe", "x86_64-w64-mingw32/lib/libkernel32.a"]
		quer = quer or (rel.begins_with("bin/") and rel.ends_with(".dll") and not "python" in rel and not "lldb" in rel)
		quer = quer or (rel.begins_with("lib/clang/") and "/include/" in rel and not rel.ends_with("/"))
		if not quer: continue
		var dst := pasta.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var w := FileAccess.open(dst, FileAccess.WRITE)
		if w: w.store_buffer(z.read_file(f)); w.close(); n += 1
	z.close()
	if opcao("zip_llvm", "", "") == "": DirAccess.remove_absolute(zip)
	prog.call(10, 10, "pronto")
	return n

const GRUPOS := {
	"x4_arc": {"discos": ["x4"]},
	"videos_x4": {"discos": ["x4"]}, "videos_x5": {"discos": ["x5"]}, "videos_x6": {"discos": ["x6"]},
	"menus_x5": {"discos": ["x5"], "captura": true},
	"menus_x6": {"discos": ["x6"], "captura": true},
	"titulo_x4": {"discos": ["x4"], "captura": true}, "titulo_x5": {"discos": ["x5"], "captura": true}, "titulo_x6": {"discos": ["x6"], "captura": true},
	"textos_x5": {"discos": ["x5"], "captura": true},
	"loading_x5": {"discos": ["x5"], "captura": true}, "loading_x6": {"discos": ["x6"], "captura": true},
	"intro_x5": {"discos": ["x5"], "captura": true}, "intro_x6": {"discos": ["x6"], "captura": true},
	"musica_x5": {"discos": ["x5"], "captura": true},
	"menus_x4": {"discos": ["x4"], "captura": true}, "intro_x4": {"discos": ["x4"], "captura": true},
	"musica_x4": {"discos": ["x4"], "captura": true}, "musica_x6": {"discos": ["x6"], "captura": true},
	"musica_titulo": {"discos": ["x5"], "captura": true}, "sons_x4": {"discos": ["x4"], "captura": true},
	"sons_x5": {"discos": ["x5"], "roteiros": ["sons_x5_x", "sons_x5_a2", "sons_x5_a3"]},
	"sons_x6": {"discos": ["x6"], "roteiros": ["sons_x6_x", "sons_x6_zero", "sons_x6_a1", "sons_x6_a2", "sons_x6_a3"]},
	"mini_x4": {"discos": []}, "mini_x5": {"discos": []}, "mini_x6": {"discos": []},
	"codigo_x4": {"discos": []}, "codigo_psx": {"discos": []}, "ferramentas": {"discos": []},
	"recomp_x5": {"discos": ["x5"]}, "recomp_x6": {"discos": ["x6"]},
	"pecas_x": {"discos": ["x4", "x5", "x6"]}, "efeitos_x": {"discos": ["x5", "x6"]}, "dash_x6": {"discos": ["x6"]},
}
func roda_grupo(nm: String, jogo: String, discos: Dictionary, prog: Callable) -> int:
	if GRUPOS.get(nm, {}).get("captura", false): return captura(nm, jogo, discos, prog)
	if GRUPOS.get(nm, {}).has("roteiros"):   # vários roteiros de captura em seguida
		var tot := 0
		var rs: Array = GRUPOS[nm].roteiros
		for i in rs.size():
			var pr := func(a: int, b: int, texto := "") -> void: prog.call(i * 10 + int(10.0 * a / maxf(1.0, b)), rs.size() * 10, texto)
			var k := captura(rs[i], jogo, discos, pr)
			if k < 0: return -1
			tot += k
		return tot
	if nm.begins_with("mini_"): return miniaturas(nm.substr(5), jogo, prog)
	if nm == "ferramentas": return ferramentas(prog)
	if nm == "codigo_x4": return codigo_x4(jogo, prog)
	if nm == "codigo_psx": return codigo_psx(jogo, prog)
	if nm.begins_with("recomp_"): return codigo_recomp(nm.substr(7), jogo, discos, prog)
	if nm == "pecas_x": return load("res://pecas.gd").new(discos).roda(jogo, ProjectSettings.globalize_path("res://pecas"), prog)
	if nm == "dash_x6": return load("res://dash.gd").new(opcoes).roda(jogo, ProjectSettings.globalize_path("res://pecas"), prog)
	if nm == "efeitos_x":
		var pc = load("res://pecas.gd").new(discos)
		return load("res://efeitos.gd").new(opcoes, discos, pc).roda(jogo, ProjectSettings.globalize_path("res://pecas"), prog)
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
