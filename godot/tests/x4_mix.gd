extends SceneTree
## armadura montada: cada peça de uma armadura
func mem(a): return ClassDB.class_call_static("X4Core", "mem", a, 0, 1)
func _init() -> void:
	var parts := {"helmet": "Falcon_X6", "body": "Gaea_X5", "arms": "Shadow_X6", "legs": "Falcon_X5"}
	for kv in OS.get_environment("PARTS").split(",", false):
		var a := kv.split("="); parts[a[0]] = a[1]
	X4Machine.launch = {"game": "x4", "stage": int(OS.get_environment("STAGE")) if OS.get_environment("STAGE") != "" else 1, "char": 0, "armor": 1, "char_code": 1, "skin": "", "parts": parts,
		"save": {"env": "32,0,0,0,0,0", "caps": int(OS.get_environment("CAPS"))}}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	print("env: ", X4R.env.get("MMX4_PARTS"), " armor ", X4R.env.get("MMX4_DIRECT_ARMOR"), " skill ", X4R.env.get("MMX4_DIRECT_SKILL"), " parts ", m.parts)
	var shots := [618, 619, 620, 621, 622, 623, 624, 626, 640, 641, 642, 643, 644, 645]
	for k in range(150, 260, 3): shots.append(k)
	for k in range(600, 700, 6): shots.append(k)
	for k in range(186, 260, 3): pass
	for f in 800:
		var b := 0
		if f >= 320 and f < 323: b |= 1 << 7
		if f >= 380 and f < 480: b |= 1 << 7
		if f >= 600 and f < 612: b |= (1 << 6) | (1 << 13)
		if f >= 618 and f < 640: b |= (1 << 6) | (1 << 12) | (1 << 13)
		if f >= 640 and f < 700: b |= (1 << 6) | (1 << 15)
		if f >= 640 and f < 650: b |= 1 << 7
		m.forced = b
		var snap: bool = f in shots
		m.step_frame(snap)
		if snap: print("%d pl=%d,%d fly=%d f=%d c=%d fl=%d" % [f, mem(13), mem(14), mem(19), mem(11), m.skin_map.get(mem(11), -1), mem(27)])
		if snap:
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/mix/%d.png" % f)
	quit()
