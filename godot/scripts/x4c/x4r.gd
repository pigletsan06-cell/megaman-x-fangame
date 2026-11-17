class_name X4R
extends X4RStubs
## Runtime do código do X4 traduzido (tools/ir2gd.py): memória plana igual à do programa C
## (endereços do executável linkado em /tmp/x4img.elf, base 0x400000) e as funções da plataforma.

const BASE := 0x400000
const STACK_TOP := 0x900000
const HEAP_BASE := 0x900000
const RAM_END := 0x1400000

static var ram := PackedByteArray()
static var pf := PackedInt64Array()
static var pb := PackedInt64Array()
static var sp := STACK_TOP
static var heap := HEAP_BASE
static var funcs := {}          # endereço -> [script, nome]
static var scripts := {}
static var syms := {}
static var ready := false
static var missing := {}

static func init() -> void:
	if ready:
		return
	var f := FileAccess.open("res://assets/x4c/ram.bin", FileAccess.READ)
	ram = f.get_buffer(f.get_length())
	ram.resize(RAM_END - BASE)
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/x4c/funcs.json"))
	for k in j["funcs"]:
		funcs[int(k)] = j["funcs"][k]
	syms = JSON.parse_string(FileAccess.get_file_as_string("res://assets/x4c/symbols.json"))
	# variáveis de arquivos do PC que não foram traduzidos (threads.c etc.)
	for n in ["D_801F8300", "mmx4_pc_hide_background", "stderr", "temp1", "mmx4_pc_sfx_frames", "mmx4_pc_sfx_group", "mmx4_pc_sfx_index", "mmx4_pc_sfx_raw"]:
		ext_vars[n] = c_malloc(16)
	st32(ext_vars["mmx4_pc_sfx_group"], 0xFFFFFFFF)
	if not syms.has("pc_archive_arena"):
		ext_vars["pc_archive_arena"] = c_malloc(0x88000)
	threads_init()
	ready = true

static func addr(name: String) -> int:
	return int(syms[name][0]) if syms.has(name) else 0

# ------------------------------------------------------------------ memória
static var bad_count := 0
static func _bad(a: int) -> void:
	bad_count += 1
	if bad_count <= 3:
		printerr("X4R: acesso fora da memória %x" % a)
		print_stack()

static func ld8(a: int) -> int:
	if wd_limit:
		wd += 1
		if wd % wd_limit == 0:
			printerr("X4R: vigia8 ", wd)
			print_stack()
	if a < BASE or a >= RAM_END: _bad(a); return 0
	return ram.decode_u8(a - BASE)
static func ld16(a: int) -> int:
	if wd_limit:
		wd += 1
		if wd % wd_limit == 0:
			printerr("X4R: vigia16 ", wd)
			print_stack()
	if a < BASE or a >= RAM_END: _bad(a); return 0
	return ram.decode_u16(a - BASE)
static var wd := 0
static var wd_limit := 0
static func ld32(a: int) -> int:
	if wd_limit:
		wd += 1
		if wd % wd_limit == 0:
			printerr("X4R: vigia ", wd)
			print_stack()
	if a < BASE or a >= RAM_END: _bad(a); return 0
	return ram.decode_u32(a - BASE)
static func ld64(a: int) -> int:
	if wd_limit:
		wd += 1
		if wd % wd_limit == 0:
			printerr("X4R: vigia ld64 ", wd)
			print_stack()
	if a < BASE or a >= RAM_END: _bad(a); return 0
	return ram.decode_s64(a - BASE)
static func st8(a: int, v: int) -> void:
	if wd_limit:
		wd += 1
		if wd % wd_limit == 0:
			printerr("X4R: vigia st8 ", wd)
			print_stack()
	if a < BASE or a >= RAM_END: _bad(a); return
	ram.encode_u8(a - BASE, v & 0xFF)
static func st16(a: int, v: int) -> void:
	if wd_limit:
		wd += 1
		if wd % wd_limit == 0:
			printerr("X4R: vigia st16 ", wd)
			print_stack()
	if a < BASE or a >= RAM_END: _bad(a); return
	ram.encode_u16(a - BASE, v & 0xFFFF)
static func st32(a: int, v: int) -> void:
	if wd_limit:
		wd += 1
		if wd % wd_limit == 0:
			printerr("X4R: vigia st32 ", wd)
			print_stack()
	if a < BASE or a >= RAM_END: _bad(a); return
	ram.encode_u32(a - BASE, v & 0xFFFFFFFF)
static func st64(a: int, v: int) -> void:
	if wd_limit:
		wd += 1
		if wd % wd_limit == 0:
			printerr("X4R: vigia st64 ", wd)
			print_stack()
	if a < BASE or a >= RAM_END: _bad(a); return
	ram.encode_s64(a - BASE, v)
static func s8(a: int) -> int: return ram.decode_s8(a - BASE)
static func s16(a: int) -> int: return ram.decode_s16(a - BASE)
static func s32(a: int) -> int: return ram.decode_s32(a - BASE)

static func memcpy(d: int, s: int, n: int) -> int:
	if n > 0x100000: printerr("memcpy grande ", n); print_stack()
	if n <= 0: return d
	var tmp := ram.slice(s - BASE, s - BASE + n)
	for i in n: ram[d - BASE + i] = tmp[i]
	return d

static func memset(d: int, v: int, n: int) -> int:
	if n > 0x100000: printerr("memset grande ", n); print_stack()
	for i in n: ram[d - BASE + i] = v & 0xFF
	return d

static func alloca(size: int, align: int) -> int:
	sp -= size
	sp -= sp % align
	return sp

static func u64(v: int) -> float:
	return float(v) + (18446744073709551616.0 if v < 0 else 0.0)

static func lshr64(v: int, n: int) -> int:
	if n == 0: return v
	return (v >> n) & ((1 << (64 - n)) - 1)

static var ext_vars := {}
static func extaddr(n: String) -> int:
	if ext_vars.has(n): return ext_vars[n]
	if not missing.has("@" + n):
		missing["@" + n] = true
		printerr("X4R: endereço externo " + n)
	return 0

static func untranslated(n: String) -> void:
	if not missing.has(n):
		missing[n] = true
		printerr("X4R: função não traduzida " + n)

# ------------------------------------------------------------------ chamadas indiretas
static func icall(a: int, args: Array) -> int:
	var e = funcs.get(a)
	if e == null:
		if not missing.has(a):
			missing[a] = true
			printerr("X4R: ponteiro de função desconhecido %x" % a)
		return 0
	var scr = scripts.get(e[0])
	if scr == null:
		scr = load("res://scripts/x4c/gen/%s.gd" % e[0])
		scripts[e[0]] = scr
	return scr.callv(e[1], args)

# ------------------------------------------------------------------ libc
static func c_memcpy(d = 0, s = 0, n = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0): return memcpy(d, s, n)
static func c_memset(d = 0, v = 0, n = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0): return memset(d, v, n)
static func c_abs(v = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0): return absi(((v & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000) & 0xFFFFFFFF
static func c_malloc(n = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var a := heap
	heap += (n + 15) & ~15
	return a
static func c_calloc(n = 0, m = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var a = c_malloc(n * m)
	memset(a, 0, n * m)
	return a
static var env := {"MMX4_PC_STUB_CONTINUE": "1"}
static var env_ptrs := {}
static func cstr(a: int) -> String:
	var b := PackedByteArray()
	while a != 0 and ld8(a) != 0 and b.size() < 4096:
		b.append(ld8(a)); a += 1
	return b.get_string_from_ascii()
static func put_cstr(t: String) -> int:
	var b := t.to_ascii_buffer()
	var a = c_malloc(b.size() + 1)
	for i in b.size(): st8(a + i, b[i])
	st8(a + b.size(), 0)
	return a
static func c_getenv(name = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var n := cstr(name)
	if not env.has(n): return 0
	if not env_ptrs.has(n): env_ptrs[n] = put_cstr(str(env[n]))
	return env_ptrs[n]
static func c_strcmp(a = 0, b = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var x := cstr(a); var y := cstr(b)
	return 0 if x == y else (0xFFFFFFFF if x < y else 1)
static func c_strtoul(sa = 0, endp = 0, base = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var t := cstr(sa).strip_edges()
	var v := 0
	if t.begins_with("0x") or t.begins_with("0X"): v = t.substr(2).hex_to_int()
	else: v = t.to_int()
	if endp != 0: st64(endp, sa + cstr(sa).length())
	return v

# ------------------------------------------------------------------ intrínsecas do LLVM
static func fshl(a: int, b: int, c: int, bits: int) -> int:
	var m := (1 << bits) - 1
	var s := c % bits
	if s == 0: return a
	return ((a << s) | (b >> (bits - s))) & m

static func fshr(a: int, b: int, c: int, bits: int) -> int:
	var m := (1 << bits) - 1
	var s := c % bits
	if s == 0: return b
	return ((a << (bits - s)) | (b >> s)) & m

static func bswap(v: int, bits: int) -> int:
	var r := 0
	for i in bits / 8:
		r = (r << 8) | ((v >> (8 * i)) & 0xFF)
	return r

static func ctlz(v: int, bits: int) -> int:
	var n := 0
	for i in range(bits - 1, -1, -1):
		if (v >> i) & 1: break
		n += 1
	return n


# ------------------------------------------------------------------ threads do jogo (threads.c) como corrotinas
class ThreadBox:
	signal resume
	signal never
	var entry := 0
	var running := false
	var restart := false
	var gen := 0
	var sp := 0

static var th: Array = []
static var game_threads := 0          # struct GameThread[4]
static var current_thread := -1
static var sched_sp := 0

static func threads_init() -> void:
	th.clear()
	game_threads = c_malloc(4 * 128)
	for i in 4:
		var b := ThreadBox.new()
		b.sp = STACK_TOP - 0x8000 - i * 0x10000
		th.append(b)
	st64(ext_vars["D_801F8300"], game_threads)

static func c_mmx4_pc_threads_init(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	for i in 4:
		st16(game_threads + i * 128, 0)
		th[i].entry = 0; th[i].running = false; th[i].restart = false
	st64(ext_vars["D_801F8300"], game_threads)
	return 0

static func c_mmx4_pc_thread_slot(slot = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	return game_threads + slot * 128

static func c_mmx4_pc_thread_create(slot = 0, entry = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	th[slot].entry = entry
	th[slot].running = false
	th[slot].gen += 1
	st16(game_threads + slot * 128, 2)
	return 0

static func _thread_main(slot: int, gen: int) -> void:
	var b: ThreadBox = th[slot]
	await icall_a(b.entry, [])
	if b.gen == gen:
		st16(game_threads + slot * 128, 0)
		b.running = false
		current_thread = -1

static func c_mmx4_pc_thread_run(slot = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var b: ThreadBox = th[slot]
	if b.entry == 0 or ld16(game_threads + slot * 128) == 0:
		return 0
	current_thread = slot
	st64(ext_vars["D_801F8300"], game_threads + slot * 128)
	sched_sp = sp
	sp = b.sp
	if not b.running or b.restart:
		b.running = true; b.restart = false; b.gen += 1
		sp = STACK_TOP - 0x8000 - slot * 0x10000
		_thread_main(slot, b.gen)
	else:
		b.resume.emit()
	if current_thread == slot or current_thread == -1:
		b.sp = sp
	sp = sched_sp
	current_thread = -1
	return 0

static func c_mmx4_pc_thread_yield(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var slot := current_thread
	var b: ThreadBox = th[slot]
	b.sp = sp
	current_thread = -1
	await b.resume
	current_thread = slot
	return 0

static func c_mmx4_pc_thread_close(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var slot := current_thread
	th[slot].running = false
	th[slot].gen += 1
	current_thread = -1
	await th[slot].never
	return 0

static func c_mmx4_pc_thread_replace(entry = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var slot := current_thread
	th[slot].entry = entry
	th[slot].restart = true
	th[slot].gen += 1
	st16(game_threads + slot * 128, 2)
	current_thread = -1
	await th[slot].never
	return 0

static func icall_a(a: int, args: Array):
	var e = funcs.get(a)
	if e == null:
		return icall(a, args)
	var scr = scripts.get(e[0])
	if scr == null:
		scr = load("res://scripts/x4c/gen/%s.gd" % e[0])
		scripts[e[0]] = scr
	return await scr.callv(e[1], args)

# ------------------------------------------------------------------ CD (lê setores do arquivo de dados do disco)
static var disc: FileAccess = null
static var cd_lba := 0
static var cd_reading := false
static var cd_last := 0
static var cd_ready_cb := 0
static var cd_data_cb := 0

static func _disc() -> FileAccess:
	if disc == null:
		for p in ["res://assets/x4c_disc_arc.sec"]:
			disc = FileAccess.open(p, FileAccess.READ)
			if disc != null: break
	return disc

static func _bcd(v: int) -> int: return (v / 10) * 16 + v % 10
static func _unbcd(v: int) -> int: return (v >> 4) * 10 + (v & 15)

static func c_CdIntToPos(i = 0, p = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var n: int = ((i ^ 0x80000000) - 0x80000000) + 150
	st8(p, _bcd(n / 4500)); st8(p + 1, _bcd((n / 75) % 60)); st8(p + 2, _bcd(n % 75)); st8(p + 3, 0)
	return p

static func c_CdPosToInt(p = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	return (_unbcd(ld8(p)) * 4500 + _unbcd(ld8(p + 1)) * 75 + _unbcd(ld8(p + 2)) - 150) & 0xFFFFFFFF

static var xa_playing := false
static var xa_lba := 0
static var xa_pos2 := 0
static func c_CdSync(mode = 0, result = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	if result != 0:
		if cd_last == 0x11:   # CdlGetlocP: posição atual da música
			var n := xa_pos2 / 2 + 150
			for k in [2, 5]:
				st8(result + k, _bcd(n / 4500)); st8(result + k + 1, _bcd((n / 75) % 60)); st8(result + k + 2, _bcd(n % 75))
		else:
			st8(result, 0x02)
	return 2
static func c_CdLastCom(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	return cd_last
static func c_mmx4_pc_replay_xa_start_ready(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	return 1
static func _cd_command(com: int, param: int) -> void:
	cd_last = com
	if (com == 2 or com == 0x15 or com == 0x16) and param != 0:   # CdlSetloc / SeekL / SeekP
		cd_lba = c_CdPosToInt(param)
	elif com == 6:                 # CdlReadN: dados
		if param != 0: cd_lba = c_CdPosToInt(param)
		cd_reading = true
		xa_playing = false
	elif com == 0x1B:              # CdlReadS: música XA (vai direto pro som)
		if param != 0: cd_lba = c_CdPosToInt(param)
		xa_playing = true
		xa_lba = cd_lba
		xa_pos2 = cd_lba * 2
	elif com == 9 or com == 8:     # Pause / Stop
		cd_reading = false
		xa_playing = false

static func c_CdControl(com = 0, param = 0, result = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	_cd_command(com, param); return 1
static func c_CdControlB(com = 0, param = 0, result = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	_cd_command(com, param); return 1
static func c_CdControlF(com = 0, param = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	_cd_command(com, param); return 1
static var cd_buf := PackedByteArray()
static var cd_cur := 0
static func c_CdReady(mode = 0, result = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	if not cd_reading:
		return 0
	# próximo setor: cabeçalho (posição BCD + modo) + subcabeçalho + 2048 bytes de dados
	cd_buf = PackedByteArray(); cd_buf.resize(12 + 2048 + 280)
	var n := cd_lba + 150
	cd_buf[0] = _bcd(n / 4500); cd_buf[1] = _bcd((n / 75) % 60); cd_buf[2] = _bcd(n % 75); cd_buf[3] = 2
	cd_buf[6] = 8; cd_buf[10] = 8
	var d := _disc()
	if d != null and cd_lba * 2048 + 2048 <= d.get_length():
		d.seek(cd_lba * 2048)
		var b := d.get_buffer(2048)
		for i in 2048: cd_buf[12 + i] = b[i]
	cd_lba += 1
	cd_cur = 0
	return 1
static func c_CdReadyCallback(fn = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var old := cd_ready_cb; cd_ready_cb = fn; return old
static func c_CdDataCallback(fn = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var old := cd_data_cb; cd_data_cb = fn; return old
static func c_CdInit(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0): return 1
static func c_CdReset(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0): return 1
static func c_CdGetSector(buf = 0, words = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var n: int = words * 4
	for i in n:
		var v := cd_buf[cd_cur + i] if cd_cur + i < cd_buf.size() else 0
		ram[buf - BASE + i] = v
	cd_cur += n
	return 1

# ------------------------------------------------------------------ tempo
static var vsync_count := 0
static func xa_tick() -> void:
	if xa_playing: xa_pos2 += 5
static func c_VSync(mode = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	return vsync_count

# ------------------------------------------------------------------ controle
static var buttons := 0
static func c_mmx4_pc_input_update(buf = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	st8(buf, 0); st8(buf + 1, 0x41)
	st8(buf + 2, (~buttons >> 8) & 0xFF); st8(buf + 3, ~buttons & 0xFF)
	return 0
static func c_mmx4_pc_frame_number(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	return vsync_count

# ------------------------------------------------------------------ GPU (alto nível): VRAM + lista de primitivas
static var vram := PackedByteArray()
static var vram_dirty := true
static var prims: Array = []          # PackedInt32Array por primitiva: [palavras...]
static var draw_ofs := Vector2i.ZERO
static var bg_color := Color.BLACK

static func gpu_init() -> void:
	vram.resize(1024 * 512 * 2)

static func _rect(r: int) -> Array:
	return [s16(r), s16(r + 2), s16(r + 4), s16(r + 6)]

static func c_LoadImage(rect = 0, data = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	if vram.is_empty(): gpu_init()
	var r := _rect(rect)
	var src: int = data - BASE
	for y in r[3]:
		var vy: int = (r[1] + y) & 511
		var row := ram.slice(src + y * r[2] * 2, src + (y + 1) * r[2] * 2)
		var x0: int = r[0] & 1023
		if x0 + r[2] <= 1024:
			var d := (vy * 1024 + x0) * 2
			for i in row.size(): vram[d + i] = row[i]
		else:
			for x in r[2]:
				var d2: int = (vy * 1024 + ((x0 + x) & 1023)) * 2
				vram[d2] = row[x * 2]; vram[d2 + 1] = row[x * 2 + 1]
	vram_dirty = true
	return 0

static func c_StoreImage(rect = 0, data = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	if vram.is_empty(): gpu_init()
	var r := _rect(rect)
	for y in r[3]:
		for x in r[2]:
			var s: int = ((((r[1] + y) & 511) * 1024) + ((r[0] + x) & 1023)) * 2
			st16(data + (y * r[2] + x) * 2, vram.decode_u16(s))
	return 0

static func c_MoveImage(rect = 0, x = 0, y = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	if vram.is_empty(): gpu_init()
	var r := _rect(rect)
	var tmp := PackedByteArray(); tmp.resize(r[2] * r[3] * 2)
	for j in r[3]:
		for i in r[2]:
			tmp.encode_u16((j * r[2] + i) * 2, vram.decode_u16(((((r[1] + j) & 511) * 1024) + ((r[0] + i) & 1023)) * 2))
	for j in r[3]:
		for i in r[2]:
			vram.encode_u16(((((y + j) & 511) * 1024) + ((x + i) & 1023)) * 2, tmp.decode_u16((j * r[2] + i) * 2))
	vram_dirty = true
	return 0

static func c_ClearImage(rect = 0, cr = 0, cg = 0, cb = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	if vram.is_empty(): gpu_init()
	var r := _rect(rect)
	var v: int = ((cr >> 3) & 31) | (((cg >> 3) & 31) << 5) | (((cb >> 3) & 31) << 10)
	for j in r[3]:
		for i in r[2]:
			vram.encode_u16(((((r[1] + j) & 511) * 1024) + ((r[0] + i) & 1023)) * 2, v)
	vram_dirty = true
	return 0

static func c_ClearOTagR(ot = 0, n = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	for i in n:
		var e: int = ot + i * 16
		st64(e, 0xFFFFFF if i == 0 else ot + (i - 1) * 16)
		st64(e + 8, 0)
	return 0

static var vram_draw := PackedByteArray()   # VRAM como estava quando o GPU desenhou
static var vram_draw_dirty := true
static func c_DrawOTag(p = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	# o GPU do PS1 desenha a lista antes dos envios de VRAM que o jogo faz depois no quadro
	if vram_dirty:
		vram_draw = vram.duplicate()
		vram_dirty = false
		vram_draw_dirty = true
	var guard := 0
	while p != 0xFFFFFF and p != 0 and guard < 20000:
		guard += 1
		var n := ld64(p + 8)
		if n > 0 and n < 64:
			var w := PackedInt32Array(); w.resize(n)
			var o: int = p + 16 - BASE
			for i in n: w[i] = ram.decode_u32(o + i * 4)
			prims.append(w)
		p = ld64(p)
	return 0

static func c_PutDrawEnv(env = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	draw_ofs = Vector2i(s16(env + 8), s16(env + 10))
	if ld8(env + 0x18) != 0:
		bg_color = Color8(ld8(env + 0x19), ld8(env + 0x1A), ld8(env + 0x1B))
	return env

static func c_SetDefDrawEnv(env = 0, x = 0, y = 0, w = 0, h = 0, a5 = 0, a6 = 0, a7 = 0):
	st16(env, x); st16(env + 2, y); st16(env + 4, w); st16(env + 6, h)
	st16(env + 8, x); st16(env + 10, y)
	for i in 4: st16(env + 12 + i * 2, 0)
	st16(env + 0x14, 0x0A); st8(env + 0x16, 1); st8(env + 0x17, 0); st8(env + 0x18, 0)
	st8(env + 0x19, 0); st8(env + 0x1A, 0); st8(env + 0x1B, 0)
	return env

static func c_SetDefDispEnv(env = 0, x = 0, y = 0, w = 0, h = 0, a5 = 0, a6 = 0, a7 = 0):
	st16(env, x); st16(env + 2, y); st16(env + 4, w); st16(env + 6, h)
	for i in 4: st16(env + 8 + i * 2, 0)
	st32(env + 0x10, 0)
	return env

static func c_GetTPage(tp = 0, abr = 0, x = 0, y = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	return ((tp & 3) << 7) | ((abr & 3) << 5) | ((y & 0x100) >> 4) | ((x & 0x3FF) >> 6) | ((y & 0x200) << 2)

static func c_GetGraphType(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	return 0

static func c_SetDrawMode(p = 0, dfe = 0, dtd = 0, tpage = 0, tw = 0, a5 = 0, a6 = 0, a7 = 0):
	# DR_MODE: tag + 2 palavras
	st64(p + 8, 2)
	st32(p + 16, 0xE1000000 | (tpage & 0x9FF) | ((dtd & 1) << 9) | ((dfe & 1) << 10))
	st32(p + 20, 0xE2000000)
	return p

static var tk := 0
static var tk_limit := 0
static func tick(n: String) -> void:
	tk += 1
	if tk_limit and tk % tk_limit == 0:
		printerr("X4R: laço em ", n, " ", tk)
		print_stack()

# ------------------------------------------------------------------ som (sem áudio por enquanto: só respostas coerentes)
static var vab_next := 0
static func c_SsVabTransCompleted(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0): return 1
static func c_SsVabTransBodyPartly(a0 = 0, a1 = 0, vab = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0): return vab
static func c_SsVabOpenHeadSticky(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	vab_next = (vab_next + 1) % 16
	return vab_next
static func c_SsSepOpenJ(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0): return 0

# ------------------------------------------------------------------ mensagens do jogo (stderr)
static var _seen_msgs := {}
static func _fmt(f: String, args: Array) -> String:
	var out := ""; var i := 0; var k := 0
	while i < f.length():
		var ch := f[i]
		if ch == "%" and i + 1 < f.length():
			var j := i + 1
			while j < f.length() and "0123456789.-lzh".contains(f[j]): j += 1
			var t := f[j]
			var v = args[k] if k < args.size() else 0
			k += 1
			match t:
				"s": out += cstr(v)
				"x", "X": out += "%x" % v
				"%": out += "%"; k -= 1
				_: out += str(v)
			i = j + 1
		else:
			out += ch; i += 1
	return out
static func c_fprintf(fp = 0, f = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	var s := _fmt(cstr(f), [a2, a3, a4, a5, a6, a7]).strip_edges()
	if not _seen_msgs.has(s) and _seen_msgs.size() < 300:
		_seen_msgs[s] = true
		printerr("X4C: ", s)
	return 0
static func c___assert_fail(a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0):
	printerr("X4C assert: ", cstr(a0))
	return 0
