extends SceneTree
## Liga o X4 original traduzido e tira fotos
func _init() -> void:
	for k in ["MMX4_ORACLE_SCENE", "MMX4_DIRECT_STAGE", "MMX4_DIRECT_SUBSTAGE", "MMX4_DIRECT_CHECKPOINT", "MMX4_DIRECT_CHARACTER", "MMX4_DIRECT_STORY", "MMX4_DIRECT_LOADOUT", "MMX4_DIRECT_SECRET", "X4_DEBUG"]:
		if OS.get_environment(k) != "": X4R.env[k] = OS.get_environment(k)
	X4R.pf.resize(8000); X4R.pb.resize(8000)
	var m := X4Machine.new()
	if OS.get_environment("JOGO") != "": m.game = OS.get_environment("JOGO")
	root.add_child(m)
	await process_frame
	var n := int(OS.get_environment("FRAMES") if OS.get_environment("FRAMES") != "" else "300")
	var keys := OS.get_environment("KEYS")   # ex.: "200:start,400:start"
	var press := {}
	for k in keys.split(",", false):
		var p := k.split(":"); press[int(p[0])] = p[1]
	var tot := 0
	var wav_on := OS.get_environment("AUDIO_WAV") != ""
	var wav := PackedByteArray()
	var rt := 0
	for f in n:
		if press.has(f): X4R.buttons = 0
		m.set_physics_process(false); m.set_process(false)
		var force := 0
		for d in range(0, 6):
			if press.get(f - d, "") == "start": force = 1 << 11
			if press.get(f - d, "") == "cross": force = 1 << 6
		var hold := 0
		for h in OS.get_environment("HOLD").split(",", false):
			var q := h.split(":"); var r := q[1].split("-")
			if f >= int(r[0]) and f <= int(r[1]):
				hold |= {"l1": 1 << 2, "r2": 1 << 1, "l2": 1 << 0, "r1": 1 << 3, "square": 1 << 7, "cross": 1 << 6, "right": 1 << 13, "left": 1 << 15, "jump": 1 << 6, "shoot": 1 << 7, "dash": 1 << 5, "start": 1 << 11, "up": 1 << 12, "down": 1 << 14}[q[0]]
		m.forced = force | hold
		var tr := Time.get_ticks_usec()
		var se0 := int(OS.get_environment("SHOT")) if OS.get_environment("SHOT") != "" else 30
		# POKE="d1c0c:5:2:100-200,...": escreve na RAM do núcleo (endereço hex, valor hex, tamanho, quadros)
		for pk in OS.get_environment("POKE").split(",", false):
			var q := pk.split(":"); var r := q[3].split("-")
			if f >= int(r[0]) and f <= int(r[1]): ClassDB.class_call_static(m.core, "mem", q[0].hex_to_int(), q[1].hex_to_int(), -int(q[2]))
		if m.movie_on: m.video.stop(); m._movie_step(1.0)   # testes: pula vídeos
		m.step_frame(OS.get_environment("DESENHA_TUDO") != "" or f % se0 == 0)
		if wav_on:
			if m.bin:
				for i in 96:
					var lba: int = ClassDB.class_call_static("X4Core", "xa_need")
					if lba < 0: break
					m.bin.seek(lba * 2352)
					ClassDB.class_call_static("X4Core", "xa_feed", m.bin.get_buffer(2352))
			var ab: PackedVector2Array = ClassDB.class_call_static("X4Core", "audio", 735)
			for v in ab:
				var l := clampi(int(v.x * 32767.0), -32768, 32767); var r := clampi(int(v.y * 32767.0), -32768, 32767)
				wav.append(l & 0xFF); wav.append((l >> 8) & 0xFF); wav.append(r & 0xFF); wav.append((r >> 8) & 0xFF)
		rt += Time.get_ticks_usec() - tr - m.frame_us
		tot += m.frame_us
		if f == int(OS.get_environment("DUMP") if OS.get_environment("DUMP") != "" else "-1"):
			var fv := FileAccess.open("/tmp/vram.bin", FileAccess.WRITE); fv.store_buffer(X4R.vram); fv.close()
			var arr := []
			for w in X4R.prims: arr.append(Array(w))
			var fp := FileAccess.open("/tmp/prims.json", FileAccess.WRITE); fp.store_string(JSON.stringify(arr)); fp.close()
		var se := int(OS.get_environment("SHOT")) if OS.get_environment("SHOT") != "" else 30
		if ClassDB.class_exists("X4Core") and f % 30 == 0:
			var lg: String = ClassDB.class_call_static("X4Core", "log")
			if lg != "": printraw(lg)
		if f % se == 0 and f >= int(OS.get_environment("SHOT0") if OS.get_environment("SHOT0") != "" else "0"):
			print(f, " ms/quadro=", m.frame_us / 1000.0, " prims=", X4R.prims.size(), " fluxo=", m.stream.size(), " estado=%x" % X4R.ld32(X4R.addr("game_info")) if X4R.addr("game_info") else "")
			await process_frame
			root.get_texture().get_image().save_png((OS.get_environment("SHOTDIR") if OS.get_environment("SHOTDIR") != "" else "/tmp") + "/boot_%d.png" % f)
	if OS.get_environment("PROF") != "":
		var fp2 := FileAccess.open("/tmp/prof.json", FileAccess.WRITE); fp2.store_string(JSON.stringify([Array(X4R.pf), Array(X4R.pb)])); fp2.close()
	if wav_on:
		var hdr := PackedByteArray(); hdr.resize(44)
		hdr.encode_u32(0, 0x46464952); hdr.encode_u32(4, 36 + wav.size()); hdr.encode_u32(8, 0x45564157)
		hdr.encode_u32(12, 0x20746d66); hdr.encode_u32(16, 16); hdr.encode_u16(20, 1); hdr.encode_u16(22, 2)
		hdr.encode_u32(24, 44100); hdr.encode_u32(28, 44100 * 4); hdr.encode_u16(32, 4); hdr.encode_u16(34, 16)
		hdr.encode_u32(36, 0x61746164); hdr.encode_u32(40, wav.size())
		var fw := FileAccess.open(OS.get_environment("AUDIO_WAV"), FileAccess.WRITE); fw.store_buffer(hdr); fw.store_buffer(wav); fw.close()
	print("desenho ms/quadro: ", rt / n / 1000.0, " vram: ", m.up_us / n / 1000.0, " envios: ", m.up_n)
	print("média ms/quadro: ", tot / n / 1000.0, "  faltando: ", X4R.missing.keys().slice(0, 20))
	quit()
