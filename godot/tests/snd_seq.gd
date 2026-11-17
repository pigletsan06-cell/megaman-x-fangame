extends SceneTree
## toca SEQ="10D@0,10B@20" e grava (WAV em /tmp/snd/seq_<TAG>.wav)
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": 1, "char": 0, "armor": 1, "char_code": 1, "skin": ""}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	for f in 430: m.forced = 0; m.step_frame(false); ClassDB.class_call_static("X4Core", "audio", 735)
	var ev := {}
	for e in OS.get_environment("SEQ").split(",", false):
		var a := e.split("@"); ev[int(a[1])] = a[0].hex_to_int()
	var data := PackedByteArray()
	for f in 90:
		if ev.has(f): ClassDB.class_call_static("X4Core", "mem", 0xFFFFFF13, ev[f], -1)
		m.step_frame(false)
		var buf: PackedVector2Array = ClassDB.class_call_static("X4Core", "audio", 735)
		for s in buf:
			data.append_array(PackedByteArray([0,0,0,0]))
			data.encode_s16(data.size() - 4, int(clampf(s.x, -1, 1) * 32767)); data.encode_s16(data.size() - 2, int(clampf(s.y, -1, 1) * 32767))
	var w := AudioStreamWAV.new(); w.format = AudioStreamWAV.FORMAT_16_BITS; w.stereo = true; w.mix_rate = 44100; w.data = data
	w.save_to_wav("/tmp/snd/seq_%s.wav" % OS.get_environment("TAG"))
	quit()
