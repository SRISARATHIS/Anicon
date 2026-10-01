class_name Bubble
extends Window
## Speech bubble floating above the pet, in its own transparent window.
## It can show text (typed out), a "thinking" animation, or ask the user for input.

signal _answered(text: String)

## ask() results besides the typed text.
const CANCELLED := ""
const INTERRUPTED := "\u0001"
const MAX_WIDTH := 260.0
const FONT_SIZE := 15
const TAIL_HEIGHT := 12.0
const TYPE_SPEED := 45.0
const ASK_TIMEOUT := 120.0
const INK := Color("2b2230")
const PAPER := Color("fffaf0")

## Screen point the tail points at (the pet's head).
var anchor := Vector2i.ZERO

var _session := 0
var _asking := false
var _thinking := false
var _hide_in := 0.0
var _typed := 0.0
var _think_time := 0.0
var _ask_left := 0.0

var _root: VBoxContainer
var _label: Label
var _input: LineEdit
var _tail: Control


func _init() -> void:
	title = "Anicon"
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	unfocusable = true
	visible = false
	_build()


func say(text: String, seconds := 0.0) -> void:
	_begin()
	_set_text(text)
	_hide_in = seconds if seconds > 0 else clampf(2.5 + text.length() / 15.0, 3.0, 20.0)
	_show_passive()


## Shows animated dots. Returns a ticket for is_current().
func think() -> int:
	_begin()
	_thinking = true
	_think_time = 0.0
	_label.text = "..."
	_label.visible = true
	_label.visible_characters = -1
	_show_passive()
	return _session


## True if nothing else has used the bubble since `ticket` was handed out.
func is_current(ticket: int) -> bool:
	return ticket == _session and visible


## Shows `text` (optional) with an input box and waits for the user's answer.
## Returns the typed text, CANCELLED (Esc/empty/timeout) or INTERRUPTED (bubble reused).
func ask(placeholder: String, text := "") -> String:
	_begin()
	_set_text(text)
	_input.text = ""
	_input.placeholder_text = placeholder
	_input.show()
	_asking = true
	_ask_left = ASK_TIMEOUT
	_refit()
	unfocusable = false
	show()
	grab_focus()
	_input.grab_focus()
	return await _answered


func hide_bubble() -> void:
	_begin()
	hide()


func follow(point: Vector2i) -> void:
	if point != anchor:
		anchor = point
		if visible:
			_place()


func _process(delta: float) -> void:
	if not visible:
		return
	if _thinking:
		_think_time += delta
		_label.text = ".".repeat(1 + int(_think_time * 3.0) % 3)
	elif _label.visible_characters >= 0:
		_typed += delta * TYPE_SPEED
		_label.visible_characters = int(_typed)
		if _label.visible_characters >= _label.get_total_character_count():
			_label.visible_characters = -1
	if _hide_in > 0:
		_hide_in -= delta
		if _hide_in <= 0:
			hide_bubble()
	if _asking:
		_ask_left -= delta
		if _ask_left <= 0:
			_cancel()


## Ends whatever the bubble was doing before.
func _begin() -> void:
	_session += 1
	_thinking = false
	_hide_in = 0.0
	_input.hide()
	unfocusable = true
	if _asking:
		_asking = false
		_answered.emit(INTERRUPTED)


func _set_text(text: String) -> void:
	_label.text = text
	_label.visible = text != ""
	_label.visible_characters = 0
	_typed = 0.0


func _show_passive() -> void:
	_refit()
	unfocusable = true
	if not visible:
		show()


func _submit(text: String) -> void:
	if not _asking:
		return
	_asking = false
	unfocusable = true
	_answered.emit(text.strip_edges())


func _cancel() -> void:
	if not _asking:
		return
	_asking = false
	hide_bubble()
	_answered.emit(CANCELLED)


func _refit() -> void:
	# Size the window from font metrics; containers can't lay out while hidden.
	var font := _label.get_theme_font("font")
	var width := MAX_WIDTH
	if not _input.visible:
		width = clampf(font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 4, 24.0, MAX_WIDTH)
	var height := 0.0
	if _label.visible:
		var paragraph := TextParagraph.new()
		paragraph.width = width
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		paragraph.add_string(_label.text, font, FONT_SIZE)
		var lines := paragraph.get_line_count()
		height = lines * font.get_height(FONT_SIZE) + (lines - 1) * _label.get_theme_constant("line_spacing") + 2
	_label.custom_minimum_size = Vector2(width, height)
	_input.custom_minimum_size = Vector2(width, 0)
	_root.reset_size()
	size = Vector2i(_root.get_combined_minimum_size().ceil())
	_root.size = size
	_place()


func _place() -> void:
	var area := DisplayServer.screen_get_usable_rect(Platform.screen_at(Vector2(anchor)))
	var pos := Vector2i(anchor.x - size.x / 2, anchor.y - size.y)
	pos.x = clampi(pos.x, area.position.x + 4, maxi(area.position.x + 4, area.end.x - size.x - 4))
	pos.y = clampi(pos.y, area.position.y, maxi(area.position.y, area.end.y - size.y))
	if pos != position:
		position = pos
	_tail.queue_redraw()


func _draw_tail() -> void:
	var x := clampf(anchor.x - position.x, 18.0, size.x - 18.0)
	var points := PackedVector2Array([Vector2(x - 9, 0), Vector2(x, TAIL_HEIGHT), Vector2(x + 9, 0)])
	_tail.draw_colored_polygon(points, PAPER)
	_tail.draw_polyline(points, INK, 3.0)


func _on_input_gui(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_input.accept_event()
		_cancel()


func _on_window_input(event: InputEvent) -> void:
	# Clicking a plain message dismisses it.
	var button := event as InputEventMouseButton
	if button and button.pressed and not _asking:
		hide_bubble()


func _build() -> void:
	window_input.connect(_on_window_input)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PAPER
	panel_style.border_color = INK
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(10)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.clip_text = true
	_label.add_theme_color_override("font_color", INK)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)

	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("f1e7d0")
	input_style.set_corner_radius_all(6)
	input_style.set_content_margin_all(6)
	_input = LineEdit.new()
	_input.add_theme_stylebox_override("normal", input_style)
	_input.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_input.add_theme_color_override("font_color", INK)
	_input.add_theme_color_override("font_placeholder_color", Color(INK, 0.5))
	_input.add_theme_color_override("caret_color", INK)
	_input.add_theme_font_size_override("font_size", FONT_SIZE - 1)
	_input.text_submitted.connect(_submit)
	_input.text_changed.connect(func(_text: String): _ask_left = ASK_TIMEOUT)
	_input.gui_input.connect(_on_input_gui)
	_input.hide()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label)
	box.add_child(_input)
	panel.add_child(box)

	_tail = Control.new()
	_tail.custom_minimum_size = Vector2(0, TAIL_HEIGHT)
	_tail.draw.connect(_draw_tail)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", -3)
	_root.add_child(panel)
	_root.add_child(_tail)
	add_child(_root)
