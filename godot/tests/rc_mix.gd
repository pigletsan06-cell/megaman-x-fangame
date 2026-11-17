extends SceneTree
## X6 pela recompilação com o X montado por peças. PECAS="helmet,body,arms,legs" (armaduras), ARM=código da armadura carregada
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = 2; h.is_zero = false
	h.armor_idx["x6"] = int(OS.get_environment("ARM"))
	if OS.get_environment("MONTADA") != "":
		var mp := OS.get_environment("MONTADA").split(",")
		FangameSave.cur().parts = {"helmet": mp[0], "body": mp[1], "arms": mp[2], "legs": mp[3]}
		h.armor_idx["x6"] = h.ARMORS["x6"].size() - 1
	var l: Dictionary = h._build_launch()
	var pc := OS.get_environment("PECAS").split(",")
	if pc.size() == 4: l["parts"] = {"helmet": pc[0], "body": pc[1], "arms": pc[2], "legs": pc[3]}
	X4Machine.launch = l; X4Machine.handoff = {}
	change_scene_to_file("res://scenes/fase.tscn")
	for f in 3000:
		await process_frame
		if current_scene and current_scene.get("launch_phase") == 2: break
	var m = current_scene
	for f in 400: await process_frame
	root.get_texture().get_image().save_png("/tmp/mix_parado.png")
	var fo := FileAccess.open("/tmp/mix_info.txt", FileAccess.WRITE)
	fo.store_line("char_code=%s E7=%d CCF2E=%d" % [str(l.get("char_code")), int(ClassDB.class_call_static(m.core, "mem", 0x970A0 + 0xE7, 0, 1)), int(ClassDB.class_call_static(m.core, "mem", 0xCCF2E, 0, 1))])
	fo.close()
	m.forced = 1 << 13
	for f in 25: await process_frame
	root.get_texture().get_image().save_png("/tmp/mix_anda.png")
	m.forced = (1 << 13) | (1 << 6)   # pula andando
	for f in 12: await process_frame
	root.get_texture().get_image().save_png("/tmp/mix_pulo.png")
	m.forced = 1 << 15   # esquerda
	for f in 30: await process_frame
	m.forced = 0
	for f in 2: await process_frame
	root.get_texture().get_image().save_png("/tmp/mix_esq.png")
	quit()
