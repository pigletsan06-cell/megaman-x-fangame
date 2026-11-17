extends SceneTree
## Co-op online com 2 Godot no mesmo PC: ROLE=host|client, GAME (x4|x5|x6), STAGE (id da fase), ZERO=1 (Zero), NZKEYS/BZ
## como no nz_test, WAIT, SEQ (botões do Godot), SAVE (quadros entre fotos) -> /tmp/coop_<role>_NNNN.png e /tmp/coop_<role>.txt
func _init() -> void:
	var role := OS.get_environment("ROLE")
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	var g := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "x6"
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find(g)
	h.is_zero = OS.get_environment("ZERO") != ""
	if h.is_zero and OS.get_environment("ZIDX") != "": h.zero_idx[g] = int(OS.get_environment("ZIDX"))
	if OS.get_environment("ARMOR") != "": h.armor_idx[g] = int(OS.get_environment("ARMOR"))
	var c := Coop.node()
	for i in 3: await process_frame
	if role == "host": c.host()
	else: c.join(OS.get_environment("IP") if OS.get_environment("IP") != "" else "127.0.0.1")
	var lg := FileAccess.open("/tmp/coop_%s.txt" % role, FileAccess.WRITE)
	for f in 1200:
		await process_frame
		if Coop.on() and not c.partner.is_empty(): break
	lg.store_line("conectado: %s | %s" % [Coop.on(), c.status]); lg.flush()
	if role == "host":
		for i in 30: await process_frame
		var st := int(OS.get_environment("STAGE")) if OS.get_environment("STAGE") != "" else -1
		h._start(st)
	for f in 3000:
		await process_frame
		if f % 300 == 0: lg.store_line("esperando a fase: %s %s" % [current_scene, current_scene.get("launch_phase") if current_scene else "-"]); lg.flush()
		if current_scene and current_scene.get("launch_phase") == 2 and current_scene.get("lf") != null: break
	var m = current_scene
	if m == null or not m.has_method("_coop_local"):
		lg.store_line("sem fase: %s" % [m]); lg.close(); c.leave(); quit(); return
	lg.store_line("fase: %s" % [m.get("L") if m else "?"]); lg.flush()
	for f in int(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 300: await process_frame
	var seq := [[300, 0]]
	if OS.get_environment("SEQ") != "":
		seq = []
		for it in OS.get_environment("SEQ").split(","):
			var p := it.split(":"); seq.append([int(p[0]), p[1].hex_to_int()])
	var n := 0
	var every := int(OS.get_environment("SAVE")) if OS.get_environment("SAVE") != "" else 30
	for stp in seq:
		for i in stp[0]:
			if m and is_instance_valid(m): m.forced = stp[1]
			if n == 5: print("passo 5: POKE=[%s] HPOKE=[%s] CPOKE=[%s]" % [OS.get_environment("POKE"), OS.get_environment("HPOKE"), OS.get_environment("CPOKE")])
			for pk: String in [OS.get_environment("POKE"), OS.get_environment("HPOKE") if role == "host" else OS.get_environment("CPOKE")]:
				for it: String in pk.split(";"):   # "passo:endereço_hex:valor:tamanho"
					var q: PackedStringArray = it.split(":")
					if q.size() == 4 and int(q[0]) == n: print("poke ", it, " -> ", ClassDB.class_call_static(m.core, "mem", q[1].hex_to_int(), int(q[2]), -int(q[3])))
			await process_frame
			n += 1
			if OS.get_environment("DUMPW") != "" and n % 2 == 0 and m and is_instance_valid(m) and m.game == "x4":   # golpes daqui (X4)
				var at: PackedInt32Array = m._coop_attacks()
				var parts4 := []
				for k in at.size() / 6:
					parts4.append("id%x hid%x r%d (%d,%d) box%08x f%x" % [at[k * 6] & 0xFF, (at[k * 6] >> 8) & 0xFF, (at[k * 6] >> 16) & 1, at[k * 6 + 1], at[k * 6 + 2], at[k * 6 + 3] & 0xFFFFFFFF, at[k * 6 + 5]])
				if not parts4.is_empty(): lg.store_line("A%d %s" % [n, " | ".join(parts4)])
			if OS.get_environment("DUMPW") != "" and n % 4 == 0 and m and is_instance_valid(m) and m.game != "x4":   # banco de tiros do X5/X6
				var base := 0x98120 if m.game == "x5" else 0x950A0
				var stp2 := 0x9C if m.game == "x5" else 0xA0
				var parts := []
				for k in 32:
					var a := base + k * stp2
					if int(ClassDB.class_call_static(m.core, "mem", a, 0, 1)) == 0: continue
					var rd := func(o: int, sz: int) -> int: return int(ClassDB.class_call_static(m.core, "mem", a + o, 0, sz))
					parts.append("%d:id%x st%x b50=%x b68=%x bk=%x f%d own=%x" % [k, rd.call(1, 1), rd.call(0, 1), rd.call(0x50, 4), rd.call(0x68, 4), rd.call(0x3C, 4), rd.call(0x47, 1), rd.call(0x7C, 4)])
				lg.store_line("W%d %s" % [n, " | ".join(parts)])
			if n % 10 == 0:
				lg.store_line("%d on %s (id %d papel %s mesmo %s) parceiro %s | eu %s" % [n, Coop.on(), c.peer_id, c.role, Coop.me == c, str(c.st), str(m._coop_local()) if m and is_instance_valid(m) and m.has_method("_coop_local") else "-"])
				if m and is_instance_valid(m) and m.has_method("_coop_local"):   # golpes: daqui (quantos), acertos do parceiro aqui, fantasmas
					lg.store_line("   golpes daqui %d, acertos do parceiro aqui %d, fantasmas %s" % [ClassDB.class_call_static(m.core, "mem", 0x1F900910, 0, 4), ClassDB.class_call_static(m.core, "mem", 0x1F90090E, 0, 4), str(m.coop_ghost_on)])
				lg.flush()
			if n % every == 0: root.get_texture().get_image().save_png("/tmp/coop_%s_%04d.png" % [role, n])
	if OS.get_environment("DUMPTOP") != "" and m and is_instance_valid(m) and m.game != "x4":   # (teste) topo da RAM: bytes usados
		for blk in range(0x1FF000, 0x200000, 0x100):
			var nz := 0; var last := -1
			for o in range(0, 0x100, 4):
				var v := int(ClassDB.class_call_static(m.core, "mem", blk + o, 0, 4))
				if v != 0: nz += 1; last = blk + o
			lg.store_line("TOP %x: %d palavras usadas, última %x" % [blk, nz, last])
	lg.close()
	c.leave()
	quit()
