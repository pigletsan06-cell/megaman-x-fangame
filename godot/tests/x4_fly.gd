extends SceneTree
## voo da Falcon: pula, dash no ar segurando para cima; grava a altura do X
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": 1, "char": 0, "armor": 1, "char_code": 1, "skin": OS.get_environment("SKIN")}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var ys := []
	for f in 420:
		var b := 0
		if f >= 250 and f < 300: b |= 1 << 13
		if f >= 300 and f < 312: b |= (1 << 6) | (1 << 13)
		if f >= 312 and f < 400: b |= (1 << 5) | (1 << 12) | (1 << 13)
		m.forced = b
		m.step_frame(f == 340 or f == 370)
		if f >= 296: ys.append(int(ClassDB.class_call_static("X4Core", "mem", 14, 0, 1)))
		if f == 340 or f == 370:
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/fly_%s_%d.png" % [OS.get_environment("SKIN"), f])
	print("Y ", OS.get_environment("SKIN"), " ", ys)
	quit()
