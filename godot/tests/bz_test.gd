extends SceneTree
## Nightmare Zero / Black Zero (BZ=1) (X5/X6 em GAME, padrão x6; Zero): NZKEYS="helmet,body,arms,legs,helmet+,..." (padrão: todas), SEQ (botões do Godot), POKE.
## Registra o estado em /tmp/nz_godot.txt e grava /tmp/nz_NNN.png quando há eco/clone/modo Pesadelo (ou SAVE/SAVEFROM).
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	var keys := OS.get_environment("NZKEYS")
	var ks: Array = ["helmet", "body", "arms", "legs", "helmet+", "body+", "arms+", "legs+"] if keys == "" else Array(keys.split(","))
	var sv := FangameSave.cur()
	var bzt := OS.get_environment("BZ") != ""
	var pre := ZeroDesafios.key("x4", "helmet").split(":")[0] + ":" if bzt else "NZ:"
	sv["zero"] = (sv.get("zero", []) as Array).filter(func(k): return not str(k).begins_with(pre))
	for k in ks: if k != "-": sv.zero.append(pre + k)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	var g := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "x6"
	var P := 0x9A0A0 if g == "x5" else 0x970A0
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find(g); h.is_zero = true
	h.zero_idx[g] = 1 if bzt else 2
	if OS.get_environment("STAGE") != "": h.cursor[g] = h.POS_STAGE[g].find(int(OS.get_environment("STAGE")))
	var l: Dictionary = h._build_launch()
	print("launch ", l)
	X4Machine.launch = l; X4Machine.handoff = {}
	change_scene_to_file("res://scenes/fase.tscn")
	for f in 3000:
		await process_frame
		if current_scene and current_scene.get("launch_phase") == 2: break
	var m = current_scene
	for f in int(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 300: await process_frame
	var seq := [[60, 0]]
	if OS.get_environment("SEQ") != "":   # "quadros:botões(hex, ordem do Godot)" separados por vírgula
		seq = []
		for it in OS.get_environment("SEQ").split(","):
			var p := it.split(":"); seq.append([int(p[0]), p[1].hex_to_int()])
	var n := 0
	var shots := 0
	var lg := FileAccess.open("/tmp/nz_godot.txt", FileAccess.WRITE)
	var pk := OS.get_environment("POKE")   # "passo:endereço_hex:valor:tamanho"
	for st in seq:
		for i in st[0]:
			if pk != "":
				for it in pk.split(";"):
					var q := it.split(":")
					if q.size() == 4 and int(q[0]) == n: ClassDB.class_call_static(m.core, "mem", q[1].hex_to_int(), int(q[2]), -int(q[3]))
			m.forced = st[1]
			await process_frame
			n += 1
			var mm := func(a: int, s: int) -> int: return int(ClassDB.class_call_static(m.core, "mem", a, 0, s))
			var e: Array = m.nz_hist[m.nz_hist.size() - 1] if m.get("nz_hist") and m.nz_hist.size() > 0 else []
			var nobj: int = (e[5] as Array).size() if e.size() > 5 else 0
			var line := "%d nz %d st %s | hp %d/%d max %d act %d x %d y %d | obj %d %s" % [n, m.nz, str(m.nz_st), mm.call(P + 0x5C, 1) & 0x7F, mm.call(P + 0x5D, 1),
				mm.call(P + 0x5E, 1) & 0x7F, mm.call(P + 5, 1), mm.call(P + 0xA, 2), mm.call(P + 0xE, 2), nobj, str(e[5]) if nobj > 0 else ""]
			lg.store_line(line)
			var want := (nobj > 0 or (e.size() > 4 and int(e[4]) > 0)) and shots < int(OS.get_environment("MAXSHOTS") if OS.get_environment("MAXSHOTS") != "" else "40") and n % 2 == 0
			if OS.get_environment("SAVE") != "" and n >= int(OS.get_environment("SAVEFROM")) and n % maxi(1, int(OS.get_environment("SAVE"))) == 0: want = true
			if n % 200 == 100: want = true
			if want:
				root.get_texture().get_image().save_png("/tmp/nz_%04d.png" % n); shots += 1
	lg.close()
	quit()
