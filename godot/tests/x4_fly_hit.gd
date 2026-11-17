extends SceneTree
## voa pela fase do X4 com a Falcon (X5) e anota vida do X e inimigos ativos
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": int(OS.get_environment("FASE") if OS.get_environment("FASE") != "" else "1"), "char": 0, "armor": 1, "char_code": 1, "skin": OS.get_environment("SKIN") if OS.get_environment("SKIN") != "" else "Falcon_X5"}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var log := []
	for f in 1500:
		var b := 0
		var c := (f - 250) % 220
		if f >= 250:
			if c < 8: b |= 1 << 6
			if c >= 20 and c < 23: b |= 1 << 6
			if c >= 30 and c < 200: b |= 1 << 13
		m.forced = b
		var shot := f % 20 == 0
		m.step_frame(shot)
		if f % 10 == 0: log.append("%d:%d,%d,%d" % [f, ClassDB.class_call_static("X4Core", "mem", 21, 0, 1), ClassDB.class_call_static("X4Core", "mem", 22, 0, 1), ClassDB.class_call_static("X4Core", "mem", 19, 0, 1)])
		if shot:
			await process_frame
			root.get_texture().get_image().save_png("/tmp/fhit/%d.png" % f)
	print("LOG ", " ".join(log))
	quit()
