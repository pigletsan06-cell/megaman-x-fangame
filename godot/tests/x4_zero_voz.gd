extends SceneTree
## Shadow (X6) no X4: shuriken, Engetsurin no chão e no ar, pulo alto, Giga
func mem(a): return ClassDB.class_call_static("X4Core", "mem", a, 0, 1)
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": int(OS.get_environment("STG") if OS.get_environment("STG") != "" else "1"), "char": 1, "armor": 1, "char_code": 1, "skin": ""}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var shots := []
	for x in OS.get_environment("SHOTS").split(",", false): shots.append(int(x))
	for f in 1130:
		var b := 0
		if f in [320, 321, 330, 331, 340, 341]: b |= 1 << 7
		if f >= 360 and f < 460: b |= 1 << 7
		if f >= 500 and f < 603: b |= 1 << 7
		if f >= 598 and f < 606: b |= 1 << 6
		if f >= 646 and f < 660: b |= 1 << 12
		if f >= 650 and f < 653: b |= 1 << 6
		if f >= 690 and f < 720: b |= 1 << 5
		if f >= 690 and f < 720: b |= 1 << 13
		if f == 880: ClassDB.class_call_static("X4Core", "mem", 0xFFFFFF12, 0x30, -1)
		if f >= 890 and f < 893: b |= 1 << 1
		m.forced = b
		var snap: bool = f in shots
		m.step_frame(snap)
		if f >= 318 and f < 960 and (f < 880 or f % 5 == 0):
			var s := "%d pl=%d,%d fly=%d gfx=%d fl=%d dbg=%d n=%d" % [f, mem(13), mem(14), mem(19), mem(26), mem(27), mem(25), mem(24)]
			for i in mem(24): s += " [%d,%d,%x,%d]" % [mem(100+i*4), mem(101+i*4), mem(102+i*4), mem(103+i*4)]
			print(s)
		if snap:
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/sha/%d.png" % f)
	quit()
