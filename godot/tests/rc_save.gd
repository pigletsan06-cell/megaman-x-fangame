extends SceneTree
## Save na recompilação: entra numa fase pelo hub (slot 2, cópia do 0), confere os valores do save no jogo,
## simula pegar a cápsula + um coração, vence e volta ao hub; confere o save. JOGOS="x6:1,x5:2" (jogo:fase)
func _init() -> void:
	var out := FileAccess.open("/tmp/rc_save.txt", FileAccess.WRITE)
	for item in OS.get_environment("JOGOS").split(","):
		var g := item.split(":")[0]; var stage := int(item.split(":")[1])
		FangameSave.load_file(); FangameSave.copy(0, 2); FangameSave.select(2)
		if OS.get_environment("RICO") != "":
			var sc: Dictionary = FangameSave.cur()
			sc.hearts = 4; sc.tanks = [20, 10]; sc.progress[g] = [2, 3]; sc.used = true; FangameSave.write()
		var s0: Dictionary = JSON.parse_string(JSON.stringify(FangameSave.cur()))
		change_scene_to_file("res://scenes/hub.tscn")
		for i in 5: await process_frame
		var h = current_scene
		h.jogo_open = false; h.in_page = true
		h.page = ["x4", "x5", "x6"].find(g); h.is_zero = false
		h.cursor[g] = Array(h.POS_STAGE[g]).find(stage)
		var l: Dictionary = h._build_launch()
		X4Machine.launch = l; X4Machine.handoff = {}
		change_scene_to_file("res://scenes/fase.tscn")
		var ok := false
		for f in 3000:
			await process_frame
			if current_scene and current_scene.get("launch_phase") == 2: ok = true; break
		for f in 420: await process_frame
		var m = current_scene
		var a: Dictionary = FangameSave.PSX[g]
		var mem := func(ad: int, n: int) -> int: return int(ClassDB.class_call_static(m.core, "mem", ad, 0, n))
		var info: Dictionary = l.save
		out.store_line("%s fase %d (core %s, ok=%s): vida %d/%d  chefes %x/%x  itens %x/%x  tanques %x,%x/%s  programas %x/%x" % [g, stage, m.core, ok,
			mem.call(a.hp[0], 1), info.hp, mem.call(a.bosses, 1), info.bosses, mem.call(a.upg, 2), info.upg,
			mem.call(a.tanks[0], 1), mem.call(a.tanks[1], 1), str(info.tanks), mem.call(a.parts, 2), info.parts])
		# simula: pegou a cápsula desta fase (bit novo nos programas) e um coração (+2 de vida máxima)
		var p0: int = mem.call(a.parts, 2)
		ClassDB.class_call_static(m.core, "mem", a.parts, p0 | 0x8000, -2)
		for ad in a.hp: ClassDB.class_call_static(m.core, "mem", ad, int(info.hp) + 2, -1)
		m.won = true
		m._back_to_hub()
		for i in 30: await process_frame
		FangameSave.load_file()
		var s1: Dictionary = FangameSave.cur()
		out.store_line("   save: corações %d -> %d   progresso %s -> %s   peças novas %s   (new_part=%s)" % [int(s0.hearts), int(s1.hearts),
			str(s0.progress[g]), str(s1.progress[g]), str(Array(s1.unlocked).filter(func(k): return not k in Array(s0.unlocked))), str(s1.get("new_part", ""))])
		out.flush()
	out.close()
	quit()
