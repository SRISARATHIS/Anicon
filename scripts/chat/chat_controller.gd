class_name ChatController
extends Node
## The ongoing conversation with the pet: personality, history and persistence.

const HISTORY_PATH := "user://chat_history.json"
const MAX_MESSAGES := 20

var history: Array = []
var _ollama: OllamaClient


func _init(ollama: OllamaClient) -> void:
	_ollama = ollama
	if FileAccess.file_exists(HISTORY_PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(HISTORY_PATH))
		if saved is Array:
			history = saved


## Sends the user's message and returns the pet's reply (or a friendly error).
func send(text: String) -> String:
	history.append({"role": "user", "content": text})
	var result := await _ollama.chat([_system_message()] + history.slice(-MAX_MESSAGES))
	if not result.ok:
		history.pop_back()
		return result.error
	history.append({"role": "assistant", "content": result.text})
	history = history.slice(-MAX_MESSAGES)
	_save()
	return result.text


## A single request in the pet's voice that doesn't touch the conversation history.
func ask_once(prompt: String) -> Dictionary:
	return await _ollama.chat([_system_message(), {"role": "user", "content": prompt}])


func clear() -> void:
	history.clear()
	_save()


func _system_message() -> Dictionary:
	var personality := String(Settings.get_value("personality"))
	return {"role": "system", "content": personality.replace("{name}", Settings.get_value("pet_name"))}


func _save() -> void:
	var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(history))
