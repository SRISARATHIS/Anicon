extends Skill
## Reports CPU, memory and battery. When the CPU stays very busy the knight looks
## flustered, but it only talks when asked.

const WATCH_INTERVAL := 10.0
const BUSY_PERCENT := 85.0
const COMPLAIN_COOLDOWN_MSEC := 300000

var _watch := 5.0
var _sampling := false
var _busy_streak := 0
var _last_complaint := -COMPLAIN_COOLDOWN_MSEC


func _init() -> void:
	title = "How's my computer?"
	order = 30


func run_action(_id: String) -> void:
	var ticket: int = app.bubble.think()
	var cpu: float = await Platform.threaded(func(): return Platform.cpu_percent())
	if app.bubble.is_current(ticket):
		app.say(_report(cpu), 8.0)


func _process(delta: float) -> void:
	_watch -= delta
	if _watch > 0 or _sampling or not Settings.get_value("cpu_watch"):
		return
	_watch = WATCH_INTERVAL
	_watch_cpu()


func _watch_cpu() -> void:
	_sampling = true
	var cpu: float = await Platform.threaded(func(): return Platform.cpu_percent())
	_sampling = false
	_busy_streak = _busy_streak + 1 if cpu >= BUSY_PERCENT else 0
	if _busy_streak < 2 or Time.get_ticks_msec() - _last_complaint < COMPLAIN_COOLDOWN_MSEC:
		return
	_last_complaint = Time.get_ticks_msec()
	app.pet.stress()


func _report(cpu: float) -> String:
	var parts := PackedStringArray()
	if cpu >= 0:
		parts.append("CPU %d%%" % roundi(cpu))
	var memory := Platform.memory_bytes()
	if not memory.is_empty():
		parts.append("RAM %.1f / %.1f GB" % [memory[0] / 1073741824.0, memory[1] / 1073741824.0])
	var battery := Platform.battery_percent()
	if battery >= 0:
		parts.append("battery %d%%" % battery)
	var mood := "All quiet on the desktop front."
	if cpu >= BUSY_PERCENT:
		mood = "Your computer is under siege!"
	elif cpu >= 50:
		mood = "Things are getting busy in here."
	return "%s\n%s" % [mood, "  ·  ".join(parts)]
