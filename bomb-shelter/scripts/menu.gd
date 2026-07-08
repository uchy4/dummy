class_name Menu
extends Control
## Boot menu: host a match on this device, or discover and join a game
## being hosted on the local Wi-Fi (host phones broadcast a UDP beacon).

const STALE := 4.0

var _games := {}  # ip -> {name, ws, http, seen}
var _udp := PacketPeerUDP.new()
var _scan_ok := false
var _name_edit: LineEdit
var _list: VBoxContainer
var _scan_label: Label
var _refresh := 0.0
var _ver_label: Label
var _upd_btn: Button


func _ready() -> void:
	if OS.has_feature("web"):
		# The browser (engine) build is only ever loaded from a host's /g/
		# page: skip the menu entirely and join that host directly.
		_web_autojoin()
		return
	NetHub.advertising = false
	Main.register_actions()
	_build_ui()
	_scan_ok = _udp.bind(NetHub.BEACON_PORT) == OK
	if not _scan_ok:
		_scan_label.text = "LAN scan unavailable (port in use)"
	if OS.get_environment("BOMB_SHELTER_SMOKE") == "1":
		call_deferred("_host")


func _process(delta: float) -> void:
	if _scan_ok:
		while _udp.get_available_packet_count() > 0:
			var ip := _udp.get_packet_ip()
			var msg: Variant = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
			if msg is Dictionary and str(msg.get("g", "")) == "bombshelter":
				_games[ip] = {
					"name": str(msg.get("n", "Host")), "ws": int(msg.get("ws", 0)),
					"http": int(msg.get("http", 0)), "seen": 0.0,
				}
	for ip in _games.keys():
		_games[ip].seen += delta
		if _games[ip].seen > STALE:
			_games.erase(ip)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.5
		_rebuild_list()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("17100a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "BOMB SHELTER"
	title.add_theme_font_size_override(&"font_size", 42)
	title.add_theme_color_override(&"font_color", Color("ffca28"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# Always-visible build/update status right under the title, so there is
	# never any doubt which build this device runs.
	_ver_label = Label.new()
	_ver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ver_label.add_theme_font_size_override(&"font_size", 13)
	_ver_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	_ver_label.text = "dev build" if BuildInfo.BUILD <= 0 \
		else "build %d — checking for updates…" % BuildInfo.BUILD
	box.add_child(_ver_label)

	# In-place update: visible only when the launch check found a newer CI
	# build. Same signing key every build, so Android installs it right over
	# this one — no uninstall. Method connections (never lambdas) to the
	# Updater autoload: they auto-disconnect when this menu is freed.
	_upd_btn = Button.new()
	_upd_btn.visible = Updater.update_available()
	if _upd_btn.visible:
		_upd_btn.text = "⬇ UPDATE AVAILABLE — install build %d" % Updater.latest_build
	_upd_btn.add_theme_font_size_override(&"font_size", 18)
	_upd_btn.add_theme_color_override(&"font_color", Color("1b5e20"))
	_upd_btn.modulate = Color("b9f6ca")
	_upd_btn.pressed.connect(func() -> void: Updater.launch_update())
	box.add_child(_upd_btn)
	if BuildInfo.BUILD > 0:
		Updater.update_found.connect(_on_update_found)
		Updater.check_done.connect(_refresh_update_status)
		_refresh_update_status()

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name (for joining)"
	_name_edit.text = Settings.join_name
	_name_edit.max_length = 10
	box.add_child(_name_edit)

	var host := Button.new()
	host.text = "HOST GAME"
	host.add_theme_font_size_override(&"font_size", 24)
	host.pressed.connect(_host)
	box.add_child(host)

	var join_title := Label.new()
	join_title.text = "Join over local Wi-Fi:"
	join_title.add_theme_font_size_override(&"font_size", 18)
	box.add_child(join_title)

	_scan_label = Label.new()
	_scan_label.text = "searching for hosted games…"
	_scan_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	box.add_child(_scan_label)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 8)
	box.add_child(_list)

	var hint := Label.new()
	hint.text = "Phones without the app can join from a browser:\nhost a game, then Quick Settings > Show web-join QR."
	hint.add_theme_font_size_override(&"font_size", 13)
	hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _on_update_found(b: int) -> void:
	if is_instance_valid(_upd_btn):
		_upd_btn.text = "⬇ UPDATE AVAILABLE — install build %d" % b
		_upd_btn.visible = true
	_refresh_update_status()


## Keep the status line honest: update available / up to date / unreachable.
func _refresh_update_status() -> void:
	if _ver_label == null or not is_instance_valid(_ver_label):
		return
	if Updater.update_available():
		_ver_label.text = "build %d — update available!" % BuildInfo.BUILD
	elif Updater.latest_build > 0:
		_ver_label.text = "build %d — up to date" % BuildInfo.BUILD
	elif Updater.check_finished:
		_ver_label.text = "build %d — couldn't reach update server" % BuildInfo.BUILD


func _rebuild_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	if _scan_ok:
		_scan_label.visible = _games.is_empty()
	for ip in _games:
		var g: Dictionary = _games[ip]
		var b := Button.new()
		b.text = "JOIN  %s  (%s)" % [g.name, ip]
		b.add_theme_font_size_override(&"font_size", 20)
		b.pressed.connect(_join.bind(str(ip), int(g.ws)))
		_list.add_child(b)


func _host() -> void:
	Settings.in_lobby = true  # everyone gathers in the lounge first
	NetHub.advertising = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Browser build boot: the host's address comes from the page URL itself
## and the ws port + player name ride in the query string (/g/?ws=N&n=NAME).
func _web_autojoin() -> void:
	set_process(false)
	Main.register_actions()
	var host := str(JavaScriptBridge.eval("location.hostname", true))
	var qs := str(JavaScriptBridge.eval("location.search", true))
	var wsp := NetHub.WS_PORT_BASE
	var join_name := "Guest"
	for kv in qs.trim_prefix("?").split("&"):
		if kv.begins_with("ws="):
			wsp = maxi(1, int(kv.substr(3)))
		elif kv.begins_with("n="):
			join_name = kv.substr(2).uri_decode()
	Settings.join_ip = host
	Settings.join_ws_port = wsp
	Settings.join_name = join_name.strip_edges().substr(0, 10)
	if Settings.join_name.is_empty():
		Settings.join_name = "Guest"
	get_tree().change_scene_to_file.call_deferred("res://scenes/client.tscn")


func _join(ip: String, ws_port: int) -> void:
	Settings.join_ip = ip
	Settings.join_ws_port = ws_port
	Settings.join_name = _name_edit.text.strip_edges()
	if Settings.join_name.is_empty():
		Settings.join_name = "Guest"
	get_tree().change_scene_to_file("res://scenes/client.tscn")
