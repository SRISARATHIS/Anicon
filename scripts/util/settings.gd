extends Node
## Persistent user settings, stored in user://settings.cfg.
## Read with get_value(), write with set_value(); listeners get `changed`.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "anicon"
const PERSONALITY := "You are {name}, a tiny, brave pixel-art knight who lives on the user's computer desktop. You are cheerful, loyal and a little dramatic. You love quests, snacks and protecting your user from bugs. Keep replies short (one to three sentences), in plain text without markdown."

var defaults := {}
var _config := ConfigFile.new()


func _init() -> void:
	defaults = {
		"pet_name": "Sir Pixel",
		"scale": 3,
		"sleep_minutes": 3.0,
		"wander": true,
		"personality": PERSONALITY,
		"ollama_url": "http://localhost:11434",
		"ollama_model": "llama3.2:3b",
		"cpu_watch": true,
		"chase_clicks": true,
		"guard_instinct": true,
		"climb_windows": true,
		"launcher": _default_launcher(),
		"autostart": false,
	}
	_config.load(PATH)


func get_value(key: String) -> Variant:
	return _config.get_value(SECTION, key, defaults[key])


func set_value(key: String, value: Variant) -> void:
	if typeof(defaults[key]) == TYPE_INT:
		value = int(value)
	elif typeof(defaults[key]) == TYPE_FLOAT:
		value = float(value)
	if get_value(key) == value:
		return
	_config.set_value(SECTION, key, value)
	_config.save(PATH)
	changed.emit(key, value)


func _default_launcher() -> String:
	match OS.get_name():
		"Windows":
			return "Explorer = explorer.exe\nNotepad = notepad.exe\nGodot docs = https://docs.godotengine.org"
		"macOS":
			return "Finder = open -a Finder\nTerminal = open -a Terminal\nGodot docs = https://docs.godotengine.org"
		_:
			return "Files = nautilus\nTerminal = ptyxis\nGodot docs = https://docs.godotengine.org"
