extends SceneTree
## X6 montado: pulo + dash no ar com perna de outra armadura. MONTADA="capacete,corpo,braço,pernas". Grava /tmp/fly_NN.png
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	var gm := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "x6"
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find(gm); h.is_zero = false
	var mp := OS.get_environment("MONTADA").split(",")
	FangameSave.cur().parts = {"helmet": mp[0], "body": mp[1], "arms": mp[2], "legs": mp[3]}
	h.armor_idx[gm] = h.ARMORS[gm].size() - 1
	var l: Dictionary = h._build_launch()
	X4Machine.launch = l; X4Machine.handoff = {}
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
			root.get_texture().get_image().save_png("/tmp/fly_%03d.png" % Engine.get_process_frames())
	for f in 150: await process_frame
	m._mix6_log_flush()
	quit()
