class_name OllamaClient
extends Node
## Minimal client for a local Ollama server.
## API reference: https://github.com/ollama/ollama/blob/main/docs/api.md
## Every call returns {"ok": true, ...} or {"ok": false, "error": "<message for the user>"}.

const TIMEOUT := 180.0

var _think_tags := RegEx.create_from_string("(?s)<think>.*?</think>")


## Sends a conversation ([{role, content}, ...]) and returns {"ok", "text"}.
func chat(messages: Array) -> Dictionary:
	var body := {"model": Settings.get_value("ollama_model"), "messages": messages, "stream": false}
	var response := await _request("", "/api/chat", HTTPClient.METHOD_POST, JSON.stringify(body))
	if not response.ok:
		return response
	var message: Variant = response.data.get("message")
	var text := String(message.get("content", "")) if message is Dictionary else ""
	# Reasoning models wrap their thoughts in <think> tags; the pet shouldn't say those out loud.
	text = _think_tags.sub(text, "", true).strip_edges()
	if text == "":
		return _fail("Hmm, I lost my train of thought. Try again?")
	return {"ok": true, "text": text}


## Lists installed models: {"ok", "models": [names]}. `base_url` overrides the saved URL.
func list_models(base_url := "") -> Dictionary:
	var response := await _request(base_url, "/api/tags", HTTPClient.METHOD_GET, "")
	if not response.ok:
		return response
	var names := []
	for model: Variant in response.data.get("models", []):
		if model is Dictionary:
			names.append(model.get("name", ""))
	return {"ok": true, "models": names}


func _request(base_url: String, path: String, method: HTTPClient.Method, body: String) -> Dictionary:
	var url := (base_url if base_url != "" else String(Settings.get_value("ollama_url"))).strip_edges().trim_suffix("/")
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var err := http.request(url + path, ["Content-Type: application/json"], method, body)
	if err != OK:
		http.queue_free()
		return _fail("I couldn't reach Ollama at %s (%s)." % [url, error_string(err)])
	var response: Array = await http.request_completed
	http.queue_free()
	var result: int = response[0]
	var code: int = response[1]
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_TIMEOUT:
			return _fail("Ollama took too long to answer. Maybe try a smaller model?")
		return _fail("I can't reach Ollama at %s. Is it running? (try: ollama serve)" % url)
	var data: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if code != 200:
		var message := String(data.get("error", "")) if data is Dictionary else ""
		if code == 404 and "not found" in message:
			var model := String(Settings.get_value("ollama_model"))
			return _fail("I don't know the model \"%s\" yet. Run: ollama pull %s" % [model, model])
		return _fail("Ollama said: %s" % (message if message != "" else "HTTP %d" % code))
	if not data is Dictionary:
		return _fail("Ollama sent something I couldn't read.")
	return {"ok": true, "data": data}


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
