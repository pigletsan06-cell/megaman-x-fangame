extends SceneTree
## Ultimate (X6) no X4: tiro, Plasma, flutuar, Nova Strike sem barra
func mem(a): return ClassDB.class_call_static("X4Core", "mem", a, 0, 1)
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": 1, "char": 0, "armor": 1, "char_code": 8, "skin": "Ultimate_X6"}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var shots := []
	for x in OS.get_environment("SHOTS").split(",", false): shots.append(int(x))
	for f in 860:
		var b := 0
		if f in [320, 321]: b |= 1 << 7
		if f >= 340 and f < 440: b |= 1 << 7
		if f >= 500 and f < 505: b |= 1 << 6
		if f >= 515 and f < 520: b |= 1 << 6
		if f >= 720 and f < 723: b |= 1 << 1
		if f >= 830 and f < 833: b |= 1 << 1
		m.forced = b
		var snap: bool = f in shots
		m.step_frame(snap)
		if f >= 318:
			var s := "%d pl=%d,%d fly=%d fl=%d cfx=%d n=%d" % [f, mem(13), mem(14), mem(19), mem(27), mem(28), mem(24)]
			for i in mem(24): s += " [%d,%d,%x,%d]" % [mem(100+i*4), mem(101+i*4), mem(102+i*4), mem(103+i*4)]
			print(s)
		if snap:
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/sha/u%d.png" % f)
	quit()
