extends SceneTree
## Falcon (X5) no X4: tiro carregado e Giga Attack
func mem(a): return ClassDB.class_call_static("X4Core", "mem", a, 0, 1)
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": int(OS.get_environment("FASE") if OS.get_environment("FASE") != "" else "1"), "char": 0, "armor": 1, "char_code": 1, "skin": "Falcon_X5"}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var shots := []
	for x in OS.get_environment("SHOTS").split(",", false): shots.append(int(x))
	for f in 900:
		var b := 0
		if f >= 260 and f < 420: b |= 1 << 7
		if f >= 600 and f < 603: b |= 1 << 1
		if f == 590: ClassDB.class_call_static("X4Core", "mem", 0xFFFFFF12, 0x30, -1)
		m.forced = b
		var snap: bool = f in shots
		m.step_frame(snap)
		if (f >= 418 and f < 450) or (f >= 598 and f < 800 and f % 3 == 0):
			var s := "%d pl=%d,%d,%d fly=%d rel=%d n=%d hp=%d g=%d dbg=%d" % [f, mem(13), mem(14), mem(12), mem(19), mem(23), mem(24), mem(21), mem(0xFFFFFF12), mem(25)]
			for i in mem(24): s += " [%d,%d,%x,%d]" % [mem(100+i*4), mem(101+i*4), mem(102+i*4), mem(103+i*4)]
			print(s)
		if snap:
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/fal/%d.png" % f)
	quit()
