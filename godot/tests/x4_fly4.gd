extends SceneTree
## voo da Falcon (X5): pula, aperta pulo de novo no ar, voa para a direita, para cima, para baixo e solta
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": 1, "char": 0, "armor": 1, "char_code": 1, "skin": "Falcon_X5"}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var log := []
	for f in 500:
		var b := 0
		if f >= 300 and f <= 310: b |= 1 << 6
		if f >= 325 and f <= 327: b |= 1 << 6
		if f >= 375 and f <= 405: b |= 1 << 13
		if f >= 405 and f <= 425: b |= 1 << 15
		if f >= 425 and f <= 445: b |= 1 << 12
		if f >= 445 and f <= 465: b |= 1 << 14
		m.forced = b
		var shot := f >= 320 and f < 500
		m.step_frame(shot)
		if f >= 320 and f < 520:
			log.append("%d:%d,%d,%d" % [f, ClassDB.class_call_static("X4Core", "mem", 19, 0, 1), ClassDB.class_call_static("X4Core", "mem", 13, 0, 1), ClassDB.class_call_static("X4Core", "mem", 14, 0, 1)])
		if shot:
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/fly4/x4_%d.png" % f)
	print("LOG ", " ".join(log))
	quit()
