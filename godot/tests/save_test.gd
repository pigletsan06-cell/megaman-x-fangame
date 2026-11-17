extends SceneTree
## save único: injeta um slot de teste numa fase (GAME=x4/x5/x6) e confere a RAM do jogo e a volta para o slot
func _init() -> void:
	var g := OS.get_environment("GAME")
	FangameSave.data = {"slots": [FangameSave.empty_slot(), FangameSave.empty_slot(), FangameSave.empty_slot()], "last": 0}
	FangameSave.slot = 0
	var s := FangameSave.cur()
	s.hearts = 3; s.tanks = [0x10]; s.progress[g] = [2, 3]; s.used = true
	var stage := 1
	var l := {"game": g, "stage": stage, "char": 0, "armor": 1 if g == "x4" else (1 if g == "x5" else 0), "secret": false, "skin": ""}
	l["char_code"] = l.armor
	if g != "x4": l["pokes"] = [[0xD1C4A if g == "x5" else 0xCCF2F, 0, 1]]
	l["save"] = FangameSave.launch_info(g, stage)
	print("save: ", l.save)
	X4Machine.launch = l
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var core := "X4Core" if g == "x4" else "PsxCore"
	var n := 0
	for f in 9000:
		m.forced = (1 << 11) if (n >= 200 and n < 210) else ((1 << 14) if (n >= 260 and n < 262) else 0)
		m.step_frame(f % 4 == 0 or n >= 295)
		var pl: bool = m.launch_phase == 2 and (g == "x4" or m.lf_play > 30)
		if pl: n += 1
		if n == 200:
			print("lido: ", FangameSave.read_game(g, core))
		if n == 300:
			print("lido: ", FangameSave.read_game(g, core))
			if g == "x6": print("cap ", ClassDB.class_call_static(core, "mem", 0x970A0 + 330, 0, 2), " en ", ClassDB.class_call_static(core, "mem", 0x970A0 + 0xA8, 0, 2), " x jogador boss_flags ", ClassDB.class_call_static(core, "mem", 0x970A0 + 201, 0, 1), " hp ", ClassDB.class_call_static(core, "mem", 0x970A0 + 0x5C, 0, 1))
			if g == "x4": print("x4 hp ", ClassDB.class_call_static(core, "mem", 21, 0, 1))
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/sha/save_%s.png" % g)
			break
	quit()
