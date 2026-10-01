extends Skill
## Quick clipboard tools, plus a summary from the local LLM.

func _init() -> void:
	title = "Clipboard"
	order = 40


func get_actions() -> Array:
	return [
		{"id": "count", "title": "Count words"},
		{"id": "tidy", "title": "Tidy up whitespace"},
		{"id": "upper", "title": "UPPERCASE"},
		{"id": "lower", "title": "lowercase"},
		{"id": "title", "title": "Title Case"},
		{"id": "summarize", "title": "Summarize with AI"},
	]


func run_action(id: String) -> void:
	var text := DisplayServer.clipboard_get()
	if text.strip_edges() == "":
		app.say("Your clipboard is empty. Copy some text first!")
		return
	match id:
		"count":
			var words := RegEx.create_from_string("\\S+").search_all(text).size()
			app.say("%d words, %d characters, %d lines." % [words, text.length(), text.count("\n") + 1])
		"tidy":
			var lines := PackedStringArray()
			for line in text.split("\n"):
				lines.append(RegEx.create_from_string("[ \\t]+").sub(line.strip_edges(), " ", true))
			var tidy := RegEx.create_from_string("\\n{3,}").sub("\n".join(lines), "\n\n", true).strip_edges()
			_replace(tidy, "Tidied up!")
		"upper":
			_replace(text.to_upper(), "SHOUTING ENABLED!")
		"lower":
			_replace(text.to_lower(), "shh... all lowercase now.")
		"title":
			var result := text
			for word in RegEx.create_from_string("[^\\W_]+").search_all(text):
				var original := word.get_string()
				result = result.substr(0, word.get_start()) + original.left(1).to_upper() + original.substr(1).to_lower() + result.substr(word.get_end())
			_replace(result, "Every Word Is Important Now.")
		"summarize":
			await _summarize(text)


func _replace(text: String, message: String) -> void:
	DisplayServer.clipboard_set(text)
	app.pet.play_once("attack_3")
	app.say(message + " (clipboard updated)")


func _summarize(text: String) -> void:
	app.pet.set_busy("channel")
	var ticket: int = app.bubble.think()
	var result: Dictionary = await app.chat.ask_once("Summarize the following text in two or three short sentences. Reply with only the summary.\n\n" + text.left(8000))
	app.pet.set_busy("")
	if not app.bubble.is_current(ticket):
		return
	if not result.ok:
		app.say(result.error, 8.0)
		return
	DisplayServer.clipboard_set(result.text)
	app.say(result.text + "\n(Summary copied to your clipboard.)", 20.0)
