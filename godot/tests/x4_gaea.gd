extends SceneTree
## Gaea (X5) no X4: tiro normal, tiro ao soltar, Gaea Shot e Giga
func mem(a): return ClassDB.class_call_static("X4Core", "mem", a, 0, 1)
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": 1, "char": 0, "armor": 1, "char_code": 2, "skin": "Gaea_X5"}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var shots := []
	for x in OS.get_environment("SHOTS").split(",", false): shots.append(int(x))
	for f in 900:
		var b := 0
		if f >= 320 and f < 323: b |= 1 << 7
		if f >= 360 and f < 375: b |= 1 << 7
		if f >= 420 and f < 460: b |= 1 << 7
		if f >= 600 and f < 603: b |= 1 << 1
		if f == 590: ClassDB.class_call_static("X4Core", "mem", 0xFFFFFF12, 0x30, -1)
		m.forced = b
		var snap: bool = f in shots
		m.step_frame(snap)
		if (f >= 318 and f < 500) or (f >= 598 and f < 820 and f % 10 == 0):
			var s := "%d pl=%d,%d fly=%d rel=%d gfx=%d n=%d" % [f, mem(13), mem(14), mem(19), mem(23), mem(26), mem(24)]
			for i in mem(24): s += " [%d,%d,%x,%d]" % [mem(100+i*4), mem(101+i*4), mem(102+i*4), mem(103+i*4)]
			print(s)
		if snap:
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/gae/%d.png" % f)
	quit()
