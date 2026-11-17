extends SceneTree
## habilidades novas (escudo / marca): MONTADA="capacete,corpo,braço,pernas", SEQ, GAME. Registra o estado em /tmp/hab_godot.txt
## e grava /tmp/hab_NNN.png quando a marca ou o escudo mudam
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	var gm := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "x6"
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find(gm); h.is_zero = false
	var mp := OS.get_environment("MONTADA").split(",")
	FangameSave.cur().parts = {"helmet": mp[0], "body": mp[1], "arms": mp[2], "legs": mp[3]}
	h.armor_idx[gm] = int(OS.get_environment("ARMIDX")) if OS.get_environment("ARMIDX") != "" else h.ARMORS[gm].size() - 1
	if OS.get_environment("STAGE") != "": h.cursor[gm] = h.POS_STAGE[gm].find(int(OS.get_environment("STAGE")))
	var l: Dictionary = h._build_launch()
	X4Machine.launch = l; X4Machine.handoff = {}
	if OS.get_environment("TESTCEIL") != "": X4R.env["MMX4_TEST_CEIL"] = "1"   # X4: finge teto em cima do pulo alto da Shadow
	change_scene_to_file("res://scenes/fase.tscn")
	for f in 3000:
		await process_frame
		if current_scene and current_scene.get("launch_phase") == 2: break
	var m = current_scene
	for f in 300: await process_frame
	var seq := [[6, 1 << 13], [8, (1 << 13) | (1 << 6)], [4, 1 << 13], [10, (1 << 13) | (1 << 5)], [30, 1 << 13], [30, 0]]
	if OS.get_environment("SEQ") != "":   # "quadros:botões(hex, ordem do Godot)" separados por vírgula
		seq = []
		for it in OS.get_environment("SEQ").split(","):
			var p := it.split(":"); seq.append([int(p[0]), p[1].hex_to_int()])
	var n := 0
	var lg := FileAccess.open("/tmp/hab_godot.txt", FileAccess.WRITE)
	var pk := OS.get_environment("POKE")   # "passo:endereço_hex:valor:tamanho" (escreve na memória do jogo nesse passo)
	for st in seq:
		for i in st[0]:
			if pk != "":
				for it in pk.split(";"):
					var q := it.split(":")
					if q.size() == 4 and int(q[0]) == n: ClassDB.class_call_static(m.core, "mem", q[1].hex_to_int(), int(q[2]), -int(q[3]))
			m.forced = st[1]
			await process_frame
			n += 1
			var mm := func(a: int) -> int: return int(ClassDB.class_call_static(m.core, "mem", a, 0, 4))
			var line := "%d esc %d/%d marca %d,%d out %d in %d | desenho esc %d marca %s x %s | x4 ct %d cs %d w %d stock %d | prot %s soc %d dp %d/%d act %d sg %s" % [n, mm.call(0x1F900702), mm.call(0x1F900703), mm.call(0x1F900704), mm.call(0x1F900705), mm.call(0x1F900709), mm.call(0x1F900708), m.hab_shield, str(m.hab_mark), str(m.hab_x), mm.call(80), mm.call(81), mm.call(82), mm.call(83), str(m.hab_prot), m.hab_soc, mm.call(0x1F900707), mm.call(85), mm.call(54), str(m.skin_group.self_modulate.a if m.skin_group else -1.0)]
			if OS.get_environment("GAME") == "x5": line += " | g6 %d/%d/%d x %d,%d act %d 7a %d" % [mm.call(0x1F900005), mm.call(0x1F900003), mm.call(0x1F900004), mm.call(0x9A0AA) & 0xFFFF, mm.call(0x9A0AE) & 0xFFFF, mm.call(0x9A0A5) & 0xFF, mm.call(0x9A11A) & 0xFF]
			lg.store_line(line)
			if (m.hab_mark.x > -50000 and n % 4 == 0) or n % 100 == 50 or (OS.get_environment("SAVE") != "" and n >= int(OS.get_environment("SAVEFROM")) and n % maxi(1, int(OS.get_environment("SAVE"))) == 0): root.get_texture().get_image().save_png("/tmp/hab_%03d.png" % n)
	lg.close()
	quit()
