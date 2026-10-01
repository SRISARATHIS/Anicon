class_name SettingsWindow
extends Window
## Settings editor. Values live in the Settings autoload; this window only edits them.

var _app: Main
var _fields := {}
var _status: Label


func _init(app: Main) -> void:
	_app = app
	title = "Anicon Settings"
	size = Vector2i(460, 640)
	min_size = Vector2i(380, 420)
	visible = false
	close_requested.connect(hide)
	_build()


func open() -> void:
	for key: String in _fields:
		var field: Control = _fields[key]
		var value: Variant = Settings.get_value(key)
		if field is LineEdit:
			field.text = str(value)
		elif field is TextEdit:
			field.text = str(value)
		elif field is SpinBox:
			field.value = value
		elif field is CheckBox:
			field.button_pressed = value
	_status.text = ""
	var area := DisplayServer.screen_get_usable_rect(Platform.screen_at(_app.pet.feet))
	position = area.position + (area.size - size) / 2
	show()
	grab_focus()


func _save() -> void:
	for key: String in _fields:
		var field: Control = _fields[key]
		if field is LineEdit or field is TextEdit:
			Settings.set_value(key, field.text.strip_edges())
		elif field is SpinBox:
			Settings.set_value(key, field.value)
		elif field is CheckBox:
			Settings.set_value(key, field.button_pressed)
	hide()


func _test_connection() -> void:
	_status.text = "Checking..."
	var result: Dictionary = await _app.ollama.list_models(_fields["ollama_url"].text)
	if not result.ok:
		_status.text = result.error
		return
	var model := String(_fields["ollama_model"].text).strip_edges()
	var models: Array = result.models
	if models.is_empty():
		_status.text = "Connected, but no models are installed. Run: ollama pull %s" % model
	elif model in models or (model + ":latest") in models:
		_status.text = "Connected! \"%s\" is ready." % model
	else:
		_status.text = "Connected, but \"%s\" isn't installed. Run: ollama pull %s\nInstalled: %s" % [model, model, ", ".join(models)]


func _build() -> void:
	var background := Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)

	_heading(form, "Character")
	_line(form, "pet_name", "Name")
	_spin(form, "scale", "Size", 1, 8, 1)
	_spin(form, "sleep_minutes", "Fall asleep after this many idle minutes", 1, 120, 1)
	_check(form, "wander", "Wander around on its own")
	_text(form, "personality", "Personality ({name} becomes the pet's name)")

	_heading(form, "Ollama (chat)")
	_line(form, "ollama_url", "Server URL")
	_line(form, "ollama_model", "Model")
	var test := Button.new()
	test.text = "Test connection"
	test.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	test.pressed.connect(_test_connection)
	form.add_child(test)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_status)

	_heading(form, "Skills")
	_check(form, "chase_clicks", "Chase my clicks (click fast three times)")
	_check(form, "guard_instinct", "Guard instinct (creep up on a resting cursor)")
	_check(form, "cpu_watch", "Look flustered when the CPU is very busy")
	_text(form, "launcher", "App launcher, one per line: Name = command or URL")

	_heading(form, "System")
	_check(form, "autostart", "Start Anicon when I log in")

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(hide)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	buttons.add_child(cancel)
	buttons.add_child(save)
	layout.add_child(buttons)


func _heading(form: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	if form.get_child_count() > 0:
		form.add_child(HSeparator.new())
	form.add_child(label)


func _caption(form: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.75)
	form.add_child(label)


func _line(form: Control, key: String, caption: String) -> void:
	_caption(form, caption)
	var field := LineEdit.new()
	form.add_child(field)
	_fields[key] = field


func _text(form: Control, key: String, caption: String) -> void:
	_caption(form, caption)
	var field := TextEdit.new()
	field.custom_minimum_size = Vector2(0, 110)
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form.add_child(field)
	_fields[key] = field


func _spin(form: Control, key: String, caption: String, low: float, high: float, step: float) -> void:
	_caption(form, caption)
	var field := SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = step
	field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	form.add_child(field)
	_fields[key] = field


func _check(form: Control, key: String, caption: String) -> void:
	var field := CheckBox.new()
	field.text = caption
	form.add_child(field)
	_fields[key] = field
