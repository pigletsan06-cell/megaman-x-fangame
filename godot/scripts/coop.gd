class_name Coop
extends Node
## Co-op online para 2 jogadores (ENet, UDP, porta 7777). Cada PC roda o próprio jogo (os motores do X4/X5/X6 só têm
## 1 jogador); este nó, filho da raiz (fica entre as cenas), liga os dois:
##  - sala: o anfitrião cria (o jogo tenta abrir a porta do roteador por UPnP) e o convidado entra pelo IP;
##  - a fase: o anfitrião escolhe no hub; a tela MISSÃO abre nos dois (cada um escolhe personagem e armadura, com o
##    save dele) e a fase só começa quando os dois confirmam;
##  - na fase: o estado de cada um a cada quadro (posição, quadro do sprite, vida, chefe) e a aparência (X com as peças
##    ou Zero com as cores); avisos (saída da fase).
## Versões diferentes do fangame não jogam juntas (VER).
const PORT := 7777
const VER := 3   # 3: MISSÃO nos dois antes da fase (M_PICK, M_READY, M_CANCEL)
enum { M_HELLO = 1, M_LAUNCH, M_STATE, M_LOOK, M_EVENT, M_BYE, M_PICK, M_READY, M_CANCEL }

static var me: Coop

var role := ""             # "" | "host" | "client"
var peer_id := 0           # o parceiro no ENet (0 = ninguém)
var status := ""           # texto para o hub
var ext_ip := ""           # IP de fora (UPnP), anfitrião
var lan_ips: PackedStringArray = []
var upnp_ok := false
var upnp_done := false
var partner := {}          # o HELLO do parceiro
var st: Array = []         # último estado do parceiro na fase
var st_ms := 0             # quando chegou (ms)
var look := {}             # aparência do parceiro na fase
var launch_req := {}       # (convidado) fase pedida pelo anfitrião ("rx" = quando chegou, ms deste PC)
var pick_req := {}         # (convidado) fase escolhida pelo anfitrião: abrir a MISSÃO ({game, stage, final, rx})
var peer_ready := false    # o parceiro confirmou na MISSÃO
var cancel_req := false    # (convidado) o anfitrião saiu da MISSÃO
var events: Array = []     # avisos recebidos (a fase consome)
var my_name := ""
var _upnp: UPNP
var _thr: Thread
var _mp: SceneMultiplayer

## o nó do co-op (criado na primeira vez, filho da raiz)
static func node() -> Coop:
	if me == null or not is_instance_valid(me):
		me = Coop.new(); me.name = "Coop"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(me)
		me._setup()
	return me

## ligado a um parceiro agora
static func on() -> bool:
	return me != null and is_instance_valid(me) and me.peer_id != 0

static func is_host() -> bool:
	return me != null and is_instance_valid(me) and me.role == "host"

## P1 (anfitrião) ou P2 (convidado)
static func tag(host_side: bool) -> String:
	return "P1" if host_side else "P2"

static func log_line(t: String) -> void:
	print("co-op: ", t)
	var f := FileAccess.open("user://coop.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://coop.log") else FileAccess.WRITE)
	if f: f.seek_end(); f.store_line("%s %s" % [Time.get_datetime_string_from_system(), t]); f.close()

func _setup() -> void:
	_mp = (Engine.get_main_loop() as SceneTree).get_multiplayer() as SceneMultiplayer
	_mp.peer_connected.connect(_on_peer)
	_mp.peer_disconnected.connect(_on_peer_gone)
	_mp.peer_packet.connect(_on_packet)
	_mp.connected_to_server.connect(_on_connected)
	_mp.connection_failed.connect(_on_failed)
	_mp.server_disconnected.connect(_on_server_gone)
	my_name = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else OS.get_environment("USER")
	if my_name == "": my_name = "jogador"

# ---------------- sala ----------------
func host() -> void:
	leave()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, 1)
	if err != OK:
		status = "não deu para criar a sala na porta %d (erro %d)" % [PORT, err]; return
	_mp.multiplayer_peer = p
	role = "host"; peer_id = 0; partner = {}
	lan_ips = PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."): lan_ips.append(a)
	status = "sala criada: esperando o parceiro (abrindo a porta %d no roteador...)" % PORT
	ext_ip = ""; upnp_ok = false; upnp_done = false
	_thr = Thread.new(); _thr.start(_upnp_work)
	log_line("sala criada na porta %d, IPs locais %s" % [PORT, lan_ips])

func _upnp_work() -> void:
	var u := UPNP.new()
	var ok := false; var ip := ""
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() and u.get_gateway().is_valid_gateway():
		ok = u.add_port_mapping(PORT, PORT, "MegaMan X Fangame co-op", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS
		ip = u.query_external_address()
	_upnp_done.call_deferred(ok, ip, u)

func _upnp_done(ok: bool, ip: String, u: UPNP) -> void:
	if _thr: _thr.wait_to_finish(); _thr = null
	_upnp = u if ok else null
	upnp_ok = ok; ext_ip = ip; upnp_done = true
	log_line("UPnP %s, IP de fora %s" % ["ok" if ok else "não", ip])
	if role == "host" and peer_id == 0:
		status = "sala criada: passe o IP para o parceiro" if ok else "sala criada, mas o roteador não abriu a porta sozinho: abra a porta %d (UDP) ou usem Radmin VPN / ZeroTier" % PORT

func join(ip: String) -> void:
	leave()
	ip = ip.strip_edges()
	var port := PORT
	if ip.contains(":"):
		port = int(ip.get_slice(":", 1)); ip = ip.get_slice(":", 0)
	if ip == "": status = "digite o IP do anfitrião"; return
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port)
	if err != OK:
		status = "não deu para conectar em %s (erro %d)" % [ip, err]; return
	_mp.multiplayer_peer = p
	role = "client"; peer_id = 0; partner = {}
	status = "conectando em %s:%d..." % [ip, port]
	log_line("conectando em %s:%d" % [ip, port])

func leave() -> void:
	if role != "": log_line("saindo da sala (%s)" % role)
	if peer_id != 0: _send(M_BYE, {}, true)
	if _mp and _mp.multiplayer_peer and not (_mp.multiplayer_peer is OfflineMultiplayerPeer):
		_mp.multiplayer_peer.close()
		_mp.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _upnp:
		var u := _upnp; _upnp = null
		var t := Thread.new(); t.start(func(): u.delete_port_mapping(PORT, "UDP"))
		t.wait_to_finish()
	role = ""; peer_id = 0; partner = {}; st = []; look = {}; launch_req = {}; events = []
	status = ""

func _exit_tree() -> void:
	if _thr: _thr.wait_to_finish(); _thr = null

# ---------------- conexão ----------------
# a fase demora a carregar (o jogo fica alguns segundos sem responder): espera mais antes de dar a conexão por perdida
func _long_timeout(id: int) -> void:
	var p := _mp.multiplayer_peer as ENetMultiplayerPeer
	if p == null: return
	var pp := p.get_peer(id)
	if pp: pp.set_timeout(64, 20000, 60000)

func _on_peer(id: int) -> void:
	if role == "host":
		if peer_id != 0 and peer_id != id: return
		peer_id = id
		_long_timeout(id)
		status = "parceiro entrou: conferindo a versão..."
		_send(M_HELLO, _hello(), true)

func _on_connected() -> void:   # (convidado)
	peer_id = 1
	_long_timeout(1)
	status = "conectado: conferindo a versão..."
	_send(M_HELLO, _hello(), true)

func _on_failed() -> void:
	log_line("não conectou")
	status = "não conectou (IP errado, sala fechada ou porta bloqueada)"
	role = ""; peer_id = 0

func _on_server_gone() -> void:
	status = "o anfitrião fechou a sala"
	log_line("anfitrião saiu")
	var keep := status
	leave(); status = keep

func _on_peer_gone(id: int) -> void:
	if id != peer_id: return
	log_line("parceiro saiu (%d)" % id)
	peer_id = 0; partner = {}; st = []; look = {}; peer_ready = false; pick_req = {}
	if role == "host": status = "o parceiro saiu: a sala continua aberta"

func _hello() -> Dictionary:
	return {"ver": VER, "name": my_name}

# ---------------- mensagens ----------------
func _send(kind: int, data, reliable: bool) -> void:
	if _mp == null or peer_id == 0: return
	var b := PackedByteArray([kind]); b.append_array(var_to_bytes(data))
	_mp.send_bytes(b, peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 0)

func send_state(s: Array) -> void: _send(M_STATE, s, false)
func send_look(d: Dictionary) -> void: _send(M_LOOK, d, true)
func send_event(d: Dictionary) -> void: _send(M_EVENT, d, true)
func send_launch(d: Dictionary) -> void: _send(M_LAUNCH, d, true)
func send_pick(d: Dictionary) -> void: peer_ready = false; _send(M_PICK, d, true)
func send_ready(r: bool) -> void: _send(M_READY, {"ready": r}, true)
func send_cancel() -> void: peer_ready = false; _send(M_CANCEL, {}, true)

func _on_packet(id: int, b: PackedByteArray) -> void:
	if id != peer_id or b.size() < 1: return
	var data = bytes_to_var(b.slice(1))
	match b[0]:
		M_HELLO:
			if typeof(data) != TYPE_DICTIONARY: return
			if int(data.get("ver", 0)) != VER:
				status = "versões diferentes do fangame (a sua %d, a do parceiro %d): atualizem os dois" % [VER, int(data.get("ver", 0))]
				_send(M_BYE, {}, true); return
			partner = data
			status = "conectado com %s (%s)" % [str(data.get("name", "?")), "você é o P1: escolha a fase" if role == "host" else "você é o P2: o P1 escolhe a fase"]
			log_line("conectado com %s" % [data])
		M_LAUNCH:
			if typeof(data) == TYPE_DICTIONARY and role == "client": launch_req = data; launch_req["rx"] = Time.get_ticks_msec()
		M_PICK:
			if typeof(data) == TYPE_DICTIONARY and role == "client":
				pick_req = data; pick_req["rx"] = Time.get_ticks_msec(); peer_ready = false; cancel_req = false
		M_READY:
			if typeof(data) == TYPE_DICTIONARY: peer_ready = bool(data.get("ready", false))
		M_CANCEL:
			if role == "client": cancel_req = true; pick_req = {}; peer_ready = false
		M_STATE:
			if typeof(data) == TYPE_ARRAY: st = data; st_ms = Time.get_ticks_msec()
		M_LOOK:
			if typeof(data) == TYPE_DICTIONARY: look = data
		M_EVENT:
			if typeof(data) == TYPE_DICTIONARY: events.append(data)
		M_BYE:
			if role == "client": _on_server_gone()
			else: _on_peer_gone(peer_id)

## estado do parceiro recente (menos de 0,5 s)
func fresh() -> bool:
	return peer_id != 0 and not st.is_empty() and Time.get_ticks_msec() - st_ms < 500
