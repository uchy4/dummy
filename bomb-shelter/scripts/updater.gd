extends Node
## Autoload: checks GitHub Releases once at startup for a newer build than
## the one baked into this binary (BuildInfo.BUILD, stamped by CI). When one
## exists, the menu and Quick Settings offer a one-tap update: the APK is
## signed with the same key every build, so Android installs it straight
## over this one — no uninstall, settings intact.

signal update_found(build: int)
signal check_done  ## fired once the release check resolves (success or not)

const RELEASES_API := "https://api.github.com/repos/uchy4/dummy/releases/latest"

var latest_build := 0
var apk_url := ""
var check_finished := false

var _checking := false
var _last_check_ms := -1000000


func _ready() -> void:
	_check()


## Re-check when the app comes back to the foreground (the user may have
## left it open in the app switcher while a new build shipped).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN \
			and Time.get_ticks_msec() - _last_check_ms > 60000:
		_check()


func _check() -> void:
	if BuildInfo.BUILD <= 0 or _checking:
		return  # dev build: nothing meaningful to compare against
	_checking = true
	_last_check_ms = Time.get_ticks_msec()
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	req.request_completed.connect(_on_response.bind(req))
	var err := req.request(RELEASES_API, [
		"Accept: application/vnd.github+json",
		"User-Agent: bomb-shelter-updater",
	])
	if err != OK:
		req.queue_free()
		_checking = false


func update_available() -> bool:
	return latest_build > BuildInfo.BUILD and apk_url != ""


## Hand the APK to the system browser: it downloads and Android's installer
## applies it as an in-place update (same signing key as this build).
func launch_update() -> void:
	if apk_url != "":
		OS.shell_open(apk_url)


func _on_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	check_finished = true
	_checking = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		check_done.emit()
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		check_done.emit()
		return
	var rel := data as Dictionary
	var re := RegEx.create_from_string("bomb-shelter-build-(\\d+)")
	var m := re.search(str(rel.get("tag_name", "")))
	if m == null:
		check_done.emit()
		return
	var found := int(m.get_string(1))
	var want := "bomb-shelter-2d.apk"
	var assets: Array = rel.get("assets", [])
	for a: Variant in assets:
		if a is Dictionary:
			var asset: Dictionary = a
			if str(asset.get("name", "")) == want:
				apk_url = str(asset.get("browser_download_url", ""))
	latest_build = found
	if update_available():
		update_found.emit(latest_build)
	check_done.emit()
