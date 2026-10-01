extends Skill
## Launches the apps and URLs listed in Settings ("Name = command or URL").

func _init() -> void:
	title = "Launch"
	order = 20


func get_actions() -> Array:
	var actions := []
	for entry: Dictionary in entries():
		actions.append({"id": entry.name, "title": entry.name})
	actions.append({"id": "", "title": "Edit list..."})
	return actions


func run_action(id: String) -> void:
	if id == "":
		app.settings_window.open()
		return
	for entry: Dictionary in entries():
		if entry.name == id:
			_launch(entry.name, entry.target)
			return


static func entries() -> Array:
	var result := []
	for line in String(Settings.get_value("launcher")).split("\n", false):
		var parts := line.split("=", true, 1)
		if parts.size() == 2 and parts[0].strip_edges() != "" and parts[1].strip_edges() != "":
			result.append({"name": parts[0].strip_edges(), "target": parts[1].strip_edges()})
	return result


func _launch(label: String, target: String) -> void:
	var expanded := _expand_home(target)
	if "://" in target or FileAccess.file_exists(expanded) or DirAccess.dir_exists_absolute(expanded):
		OS.shell_open(expanded)
	else:
		var words := PackedStringArray()
		for found in RegEx.create_from_string("\"([^\"]*)\"|(\\S+)").search_all(target):
			words.append(_expand_home(found.get_string(1) if found.get_string(1) != "" else found.get_string(2)))
		if OS.create_process(words[0], words.slice(1)) == -1:
			app.say("I couldn't start \"%s\". Check the command in Settings." % words[0], 6.0)
			app.pet.play_once("hit_front")
			return
	app.pet.play_once("cheer")
	app.say("Opening %s!" % label)


static func _expand_home(path: String) -> String:
	if path == "~" or path.begins_with("~/"):
		var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
		return home + path.substr(1)
	return path
