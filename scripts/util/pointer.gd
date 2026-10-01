extends Node
## Where the mouse is and when it's clicked, anywhere on the desktop.
## GNOME on Wayland hides this from X11 apps like Anicon, so there it comes from the
## bundled GNOME Shell extension (extras/gnome-extension, installed by `anicon setup`),
## which sends "x y buttons" datagrams to 127.0.0.1. Elsewhere Godot can see the
## position itself, but not clicks in other apps.
## The extension also reports the other apps' windows ("W id,pid,x,y,w,h ..."), so the
## knight can climb them. Without it, `windows` stays empty.

## Left button went down anywhere on the desktop. Only emitted when `sees_clicks()`.
signal clicked(point: Vector2i)

const PORT := 47391
## Without a heartbeat for this long, the extension is considered gone.
const EXTENSION_TIMEOUT_MSEC := 3000

var position := Vector2i.ZERO
var buttons := 0
## Other apps' windows on the current workspace, topmost first: [{id: int, rect: Rect2}].
var windows: Array[Dictionary] = []

var _udp := PacketPeerUDP.new()
var _last_packet_msec := -EXTENSION_TIMEOUT_MSEC
var _last_windows_msec := -EXTENSION_TIMEOUT_MSEC


func _ready() -> void:
	# A second Anicon (or anything else on the port) just means no extension data.
	_udp.bind(PORT, "127.0.0.1")
	process_priority = -100
	if needs_extension():
		get_tree().create_timer(EXTENSION_TIMEOUT_MSEC / 1000.0).timeout.connect(func():
			if not sees_clicks():
				print("No data from the Anicon GNOME extension, so clicks and other windows are invisible. Run \"anicon setup\", then log out and back in."))


## True while the GNOME extension is reporting, i.e. we know about clicks in other apps.
func sees_clicks() -> bool:
	return Time.get_ticks_msec() - _last_packet_msec < EXTENSION_TIMEOUT_MSEC


## Whether `position` follows the mouse everywhere. Without the extension, an X11 app on
## Wayland only sees the mouse over its own window, so the position goes stale.
func knows_position() -> bool:
	return sees_clicks() or not needs_extension()


## True while the extension is reporting windows (`windows` is up to date).
func knows_windows() -> bool:
	return Time.get_ticks_msec() - _last_windows_msec < EXTENSION_TIMEOUT_MSEC


## The window with this id as {id, rect}, or {} if it's gone.
func window_by_id(id: int) -> Dictionary:
	for window in windows:
		if window.id == id:
			return window
	return {}


func needs_extension() -> bool:
	return OS.get_name() == "Linux" and OS.get_environment("XDG_SESSION_TYPE") == "wayland"


func _process(_delta: float) -> void:
	while _udp.is_bound() and _udp.get_available_packet_count() > 0:
		var fields := _udp.get_packet().get_string_from_utf8().split(" ", false)
		if fields.size() > 0 and fields[0] == "W":
			_read_windows(fields)
			continue
		if fields.size() != 3:
			continue
		_last_packet_msec = Time.get_ticks_msec()
		var was_down := buttons & 1
		position = Vector2i(fields[0].to_int(), fields[1].to_int())
		buttons = fields[2].to_int()
		if buttons & 1 and not was_down:
			clicked.emit(position)
	if not sees_clicks():
		position = DisplayServer.mouse_get_position()
	if not knows_windows():
		windows.clear()


func _read_windows(fields: PackedStringArray) -> void:
	_last_windows_msec = Time.get_ticks_msec()
	windows.clear()
	for i in range(1, fields.size()):
		var v := fields[i].split(",")
		# Our own windows (the knight's layer, menus, settings) aren't climbable.
		if v.size() != 6 or v[1].to_int() == OS.get_process_id():
			continue
		windows.append({"id": v[0].to_int(), "rect": Rect2(v[2].to_int(), v[3].to_int(), v[4].to_int(), v[5].to_int())})


func _exit_tree() -> void:
	_udp.close()
