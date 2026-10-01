extends Skill
## Reminders and timers: "10m stretch", "1h30m call mom", "at 14:30 standup".
## Saved to disk, so they survive restarts.

const SAVE_PATH := "user://reminders.json"
const UNITS := "hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s"

var _reminders: Array = []
var _check := 0.0


func _init() -> void:
	title = "Reminders"
	order = 10


func _ready() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if saved is Array:
			_reminders = saved


func get_actions() -> Array:
	var actions := [{"id": "new", "title": "New reminder..."}]
	if not _reminders.is_empty():
		actions.append({"id": "list", "title": "Upcoming (%d)" % _reminders.size()})
		actions.append({"id": "clear", "title": "Cancel all"})
	return actions


func run_action(id: String) -> void:
	match id:
		"new":
			await _new_reminder()
		"list":
			var lines := PackedStringArray()
			for reminder: Dictionary in _reminders:
				lines.append("%s  %s" % [_clock(reminder.due), reminder.text])
			app.say("\n".join(lines), 10.0)
		"clear":
			_reminders.clear()
			_save()
			app.say("All reminders cancelled.")


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0 or _reminders.is_empty():
		return
	_check = 1.0
	var now := Time.get_unix_time_from_system()
	var due := _reminders.filter(func(r: Dictionary): return r.due <= now)
	if due.is_empty():
		return
	_reminders = _reminders.filter(func(r: Dictionary): return r.due > now)
	_save()
	var lines := PackedStringArray()
	for reminder: Dictionary in due:
		var late: bool = now - reminder.due > 120
		lines.append("Reminder: %s%s" % [reminder.text, " (it was due while I was away)" if late else ""])
	app.alert("\n".join(lines))


func _new_reminder() -> void:
	var answer: String = await app.bubble.ask("10m stretch  ·  1h30m call mom  ·  at 14:30 standup", "What should I remind you about, and when?")
	if answer == Bubble.CANCELLED or answer == Bubble.INTERRUPTED:
		return
	var reminder := parse(answer)
	if reminder.is_empty():
		app.say("I didn't catch the time. Try \"10m stretch\" or \"at 14:30 standup\".", 6.0)
		return
	_reminders.append(reminder)
	_reminders.sort_custom(func(a: Dictionary, b: Dictionary): return a.due < b.due)
	_save()
	app.pet.play_once("cheer")
	app.say("On it! I'll remind you at %s: %s" % [_clock(reminder.due), reminder.text])


## Parses "10m text", "1h30m text", "in 5 minutes text", "at 9:15pm text" or "25 text"
## (plain number = minutes). Returns {"due": unix time, "text": String} or {}.
static func parse(input: String) -> Dictionary:
	var text := input.strip_edges()
	var now := Time.get_unix_time_from_system()
	var found := RegEx.create_from_string("(?i)^at\\s+(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\s*(.*)$").search(text)
	if found:
		var hour := found.get_string(1).to_int()
		var minute := found.get_string(2).to_int()
		var half := found.get_string(3).to_lower()
		if half == "pm" and hour < 12:
			hour += 12
		elif half == "am" and hour == 12:
			hour = 0
		if hour > 23 or minute > 59:
			return {}
		var local := Time.get_time_dict_from_system()
		var wait: int = (hour * 3600 + minute * 60) - (local.hour * 3600 + local.minute * 60 + local.second)
		if wait <= 0:
			wait += 86400
		return _reminder(now + wait, found.get_string(4))

	found = RegEx.create_from_string("(?i)^(?:in\\s+)?((?:\\d+(?:\\.\\d+)?\\s*(?:%s)(?![a-z])\\s*)+)(.*)$" % UNITS).search(text)
	if found:
		var seconds := 0.0
		var parts := RegEx.create_from_string("(?i)(\\d+(?:\\.\\d+)?)\\s*([a-z]+)").search_all(found.get_string(1))
		for part in parts:
			var unit := part.get_string(2).to_lower()
			seconds += part.get_string(1).to_float() * (3600.0 if unit.begins_with("h") else 1.0 if unit.begins_with("s") else 60.0)
		return _reminder(now + seconds, found.get_string(2))

	found = RegEx.create_from_string("^(\\d+(?:\\.\\d+)?)(?:\\s+(.*))?$").search(text)
	if found:
		return _reminder(now + found.get_string(1).to_float() * 60.0, found.get_string(2))
	return {}


static func _reminder(due: float, text: String) -> Dictionary:
	text = text.strip_edges()
	return {"due": due, "text": text if text != "" else "Time's up!"}


## Local wall-clock time ("14:30") for a unix timestamp.
static func _clock(unix_time: float) -> String:
	var bias: int = Time.get_time_zone_from_system().bias
	return Time.get_time_string_from_unix_time(int(unix_time) + bias * 60).left(5)


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_reminders))
