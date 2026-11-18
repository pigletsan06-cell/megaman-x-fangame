extends SceneTree
## Menu de pausa original de cada jogo: GAME=x4|x5|x6 -> /tmp/pausa_<jogo>_NN.png + /tmp/pausa_<jogo>_vram.bin (1024x512, 16 bits)
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	var gm := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "x4"
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find(gm); h.is_zero = false
	var l: Dictionary = h._build_launch()
	X4Machine.launch = l; X4Machine.handoff = {}
	change_scene_to_file("res://scenes/fase.tscn")
	for f in 4000:
		await process_frame
		if current_scene and current_scene.get("launch_phase") == 2: break
	var m = current_scene
	for f in int(OS.get_environment("ESPERA") if OS.get_environment("ESPERA") != "" else "400"):
		m.forced = (1 << 6) if OS.get_environment("PULA") != "" and f % 16 < 3 else 0   # PULA: aperta X para passar as falas
		await process_frame
	m.forced = 0
	for f in 60: await process_frame
	root.get_texture().get_image().save_png("/tmp/pausa_%s_00_fase.png" % gm)
	var seq := [[4, 1 << 11], [90, 0], [4, 1 << 14], [30, 0], [4, 1 << 13], [40, 0], [4, 1 << 13], [40, 0]]
	var n := 0
	for st in seq:
		for i in st[0]:
			m.forced = st[1]; await process_frame
		n += 1
		root.get_texture().get_image().save_png("/tmp/pausa_%s_%02d.png" % [gm, n])
		if n == 2:
			var v: PackedByteArray = X4R.vram_draw if X4R.vram_draw.size() > 0 else X4R.vram
			var f := FileAccess.open("/tmp/pausa_%s_vram.bin" % gm, FileAccess.WRITE); f.store_buffer(v); f.close()
			var fp := FileAccess.open("/tmp/pausa_%s_prims.bin" % gm, FileAccess.WRITE); fp.store_buffer((m.stream as PackedInt32Array).to_byte_array()); fp.close()
	quit()
