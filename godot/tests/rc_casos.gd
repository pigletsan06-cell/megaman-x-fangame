extends SceneTree
## Entra em várias fases do X5/X6 pelo hub (save 0) e confere personagem/armadura. CASOS="x6:0:0,x6:0:2,x6:1:0,x5:0:1"
## (jogo:zero:índice da armadura). Resultado em /tmp/rc_casos.txt e fotos /tmp/rc_<caso>.png
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	var out := FileAccess.open("/tmp/rc_casos.txt", FileAccess.WRITE)
	for caso in OS.get_environment("CASOS").split(","):
		var p := caso.split(":")
		var g := p[0]
		change_scene_to_file("res://scenes/hub.tscn")
		for i in 5: await process_frame
		var h = current_scene
		h.jogo_open = false; h.in_page = true
		h.page = ["x4", "x5", "x6"].find(g)
		h.is_zero = p[1] == "1"
		if h.is_zero: h.zero_idx[g] = int(p[2])
		else: h.armor_idx[g] = int(p[2])
		var l: Dictionary = h._build_launch()
		X4Machine.launch = l
		X4Machine.handoff = {}
		change_scene_to_file("res://scenes/fase.tscn")
		var t0 := Time.get_ticks_msec()
		var ok := false
		for f in 3000:
			await process_frame
			var m = current_scene
			if m and m.get("launch_phase") == 2:
				ok = true
				break
		var t_load := Time.get_ticks_msec() - t0
		for f in 240: await process_frame
		var m = current_scene
		var info := ""
		if ok:
			var mem := func(a: int, n: int) -> int: return int(ClassDB.class_call_static(m.core, "mem", a, 0, n))
			if g == "x6": info = "estado=%d armadura(E7)=%d personagem=%d vida=%d" % [mem.call(0xCCED0, 1), mem.call(0x970A0 + 0xE7, 1), mem.call(0xCCF2E, 1), mem.call(0x970FC, 1) & 0x7F]
			else: info = "estado=%d personagem/armadura=%d corpo=%02x" % [mem.call(0xD1C00, 1), mem.call(0xD1C49, 1), mem.call(0x9A0A0 + 2, 1)]
		root.get_texture().get_image().save_png("/tmp/rc_%s.png" % caso.replace(":", "_"))
		out.store_line("%s fase=%d core=%s ok=%s carregou em %d ms  %s" % [caso, int(l.stage), m.core if m else "?", ok, t_load, info])
		out.flush()
	out.close()
	quit()
