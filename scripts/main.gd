class_name Main
extends Node
## Wires the pet, its speech bubble, chat, skills and menus together.

const HIDE_SECONDS := 600.0

var bubble: Bubble
var ollama: OllamaClient
var chat: ChatController
var skills: SkillRegistry
var menu: PopupMenu
var settings_window: SettingsWindow

var _menu_actions := {}
var _chatting := false

@onready var pet: Pet = $Pet


func _ready() -> void:
	get_window().title = "Anicon"
	ollama = OllamaClient.new()
	add_child(ollama)
	chat = ChatController.new(ollama)
	add_child(chat)
	bubble = Bubble.new()
	add_child(bubble)
	settings_window = SettingsWindow.new(self)
	add_child(settings_window)
	skills = SkillRegistry.new()
	add_child(skills)
	skills.load_all(self)
	menu = PopupMenu.new()
	menu.id_pressed.connect(_on_menu_id)
	add_child(menu)

	pet.double_clicked.connect(open_chat)
	pet.right_clicked.connect(_show_menu)
	Settings.changed.connect(_on_setting_changed)
	if "--selftest" in OS.get_cmdline_user_args():
		var test: Node = load("res://tests/selftest.gd").new()
		test.app = self
		add_child(test)

	pet.drop_in()


func _process(_delta: float) -> void:
	if bubble.visible:
		bubble.follow(pet.head_screen_pos())


func say(text: String, seconds := 0.0) -> void:
	bubble.follow(pet.head_screen_pos())
	bubble.say(text, seconds)


## Gets the user's attention: notification, run to the middle of the screen, raise the sword.
func alert(text: String) -> void:
	if not get_window().visible:
		_unhide()
	pet.wake()
	Platform.notify(Settings.get_value("pet_name"), text)
	pet.run_to(pet.area_center_x(), pet.play_once.bind("cheer"))
	say(text, 15.0)


func open_chat() -> void:
	if _chatting:
		return
	_chatting = true
	pet.wake()
	var placeholder := "Say something to %s..." % Settings.get_value("pet_name")
	var reply := ""
	while true:
		bubble.follow(pet.head_screen_pos())
		var message := await bubble.ask(placeholder, reply)
		if message == Bubble.CANCELLED or message == Bubble.INTERRUPTED:
			break
		pet.set_busy("channel")
		var ticket := bubble.think()
		reply = await chat.send(message)
		pet.set_busy("")
		if not bubble.is_current(ticket):
			break
	_chatting = false


func _show_menu() -> void:
	menu.clear(true)
	_menu_actions.clear()
	_add_item(menu, "Chat...", open_chat)
	menu.add_separator()
	for skill in skills.skills:
		var actions := skill.get_actions()
		if actions.size() == 1:
			_add_item(menu, actions[0].title, skill.run_action.bind(actions[0].id))
			continue
		var submenu := PopupMenu.new()
		submenu.id_pressed.connect(_on_menu_id)
		for action: Dictionary in actions:
			_add_item(submenu, action.title, skill.run_action.bind(action.id))
		menu.add_submenu_node_item(skill.title, submenu)
	menu.add_separator()
	_add_item(menu, "Forget our conversation", _forget_chat)
	_add_item(menu, "Settings...", settings_window.open)
	_add_item(menu, "Hide for 10 minutes", _hide_for_a_while)
	_add_item(menu, "Quit", get_tree().quit)
	menu.reset_size()
	menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _add_item(target: PopupMenu, label: String, action: Callable) -> void:
	var id := _menu_actions.size()
	_menu_actions[id] = action
	target.add_item(label, id)


func _on_menu_id(id: int) -> void:
	_menu_actions[id].call()


func _forget_chat() -> void:
	chat.clear()
	say("Huh? What were we talking about?")


func _hide_for_a_while() -> void:
	bubble.hide_bubble()
	get_window().hide()
	get_tree().create_timer(HIDE_SECONDS).timeout.connect(_unhide)


func _unhide() -> void:
	if get_window().visible:
		return
	get_window().show()
	pet.drop_in()


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"scale":
			pet.set_scale_factor(value)
		"autostart":
			Platform.set_autostart(value)
