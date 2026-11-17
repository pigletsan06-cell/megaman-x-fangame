extends SceneTree
## Falcon (X5) no X4: anda atirando carregado; anota vida e inimigos
func mem(a): return ClassDB.class_call_static("X4Core", "mem", a, 0, 1)
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": 1, "char": 0, "armor": 1, "char_code": 1, "skin": "Falcon_X5"}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var log := []
	for f in 2400:
		var b := 0
		if f >= 300:
			var c := (f - 300) % 130
			if c < 110: b |= 1 << 7
			if (f / 200) % 3 != 2: b |= 1 << 13
			if c == 60 or c == 61: b |= 1 << 6
		if f == 1500: ClassDB.class_call_static("X4Core", "mem", 0xFFFFFF12, 0x30, -1)
		if f >= 1510 and f < 1513: b |= 1 << 1
		m.forced = b
		m.step_frame(false)
		if f % 20 == 0: log.append("%d:%d,%d,%d,g%d" % [f, mem(21), mem(22), mem(24), mem(0xFFFFFF12)])
	print("LOG ", " ".join(log))
	quit()
