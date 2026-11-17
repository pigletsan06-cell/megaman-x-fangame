extends SceneTree
## X6: começa com a Falcon e troca o número da armadura no meio da fase
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	await process_frame; await process_frame
	var h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = 2; h.is_zero = false; h.armor_idx["x6"] = int(OS.get_environment("A0")); h.cursor["x6"] = 0
	X4Machine.launch = h._build_launch()
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m: X4Machine = null
	var last := ""
	var t := 0
	for f in 1500:
		await process_frame
		if m == null:
			for c in current_scene.get_children(): if c is X4Machine: m = c
			if m == null and current_scene is X4Machine: m = current_scene
		if m == null or m.lf_play < 400: continue
		t += 1
		if t == 20:
			var bs := []
			for i in 0x158: bs.append(ClassDB.class_call_static("PsxCore", "mem", 0x970A0 + i, 0, 1))
			print("BODY ", bs)
			var fo := FileAccess.open("/tmp/ram6_%s.bin" % OS.get_environment("A0"), FileAccess.WRITE)
			var buf := PackedByteArray(); buf.resize(0x60000)
			for i in range(0, 0x60000, 4): buf.encode_u32(i, ClassDB.class_call_static("PsxCore", "mem", 0x100000 + i, 0, 4))
			fo.store_buffer(buf); fo.close()
		if t == 30 and OS.get_environment("A1") != "": ClassDB.class_call_static("PsxCore", "mem", 0x97187, int(OS.get_environment("A1")), -1)
		var b := 0
		var k := (t - 40) % 120
		if t > 40:
			if k < 30: b |= 1 << 6          # pulo
			if k >= 8 and k < 12: b |= 1 << 5   # dash no ar
			if k >= 60 and k < 70: b |= 1 << 5  # dash no chão
			if k >= 90 and k < 92: b |= 1 << 7  # tiro
		m.forced = b
		var s := "act=%d arm=%d" % [ClassDB.class_call_static("PsxCore", "mem", 0x970A5, 0, 1), ClassDB.class_call_static("PsxCore", "mem", 0xCCF2E, 0, 1)]
		if s != last or t % 40 == 0: print(t, " ", s, " x=", ClassDB.class_call_static("PsxCore", "mem", 0x970AA, 0, 2), " est=", ClassDB.class_call_static("PsxCore", "mem", 0xCCED0, 0, 1)); last = s
		if t in [52, 58, 110]:
			root.get_texture().get_image().save_png("/tmp/sha/arm6_%s_%d.png" % [OS.get_environment("A1"), t])
	quit()
