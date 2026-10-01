extends Skill
## Battle mode: the screen becomes an arena. Click anywhere and the knight runs (or leaps)
## over and slashes your cursor; keep clicking to chain combos.
## Esc, the menu, or a minute without clicks ends it. Other apps can't be clicked meanwhile.

const QUIET_TIMEOUT := 60.0

var active := false
var _hits := 0
var _clicks := 0
var _quiet := 0.0


func _init() -> void:
	title = "Battle mode"
	order = 5


func get_actions() -> Array:
	return [{"id": "toggle", "title": "Leave battle mode" if active else "Battle mode!"}]


func run_action(_id: String) -> void:
	if active:
		stop()
	else:
		start()


func start() -> void:
	var pet: Pet = app.pet
	active = true
	_hits = 0
	_clicks = 0
	_quiet = 0.0
	pet.wake()
	pet.set_busy("")
	pet.set_battle_mode(true)
	pet.arena_clicked.connect(_on_arena_clicked)
	pet.struck.connect(_on_struck)
	get_window().grab_focus()
	app.say("Battle mode! Click anywhere and I'll get that cursor. Esc to stop.", 4.0)


## `quietly` skips the summary (used when battle mode times out on its own).
func stop(quietly := false) -> void:
	if not active:
		return
	active = false
	var pet: Pet = app.pet
	pet.arena_clicked.disconnect(_on_arena_clicked)
	pet.struck.disconnect(_on_struck)
	pet.set_battle_mode(false)
	if quietly:
		return
	if _clicks == 0:
		app.say("No foes today? Fine by me.")
	elif _hits == 0:
		app.say("That cursor is too quick for me... next time!")
	else:
		pet.play_once("cheer")
		app.say("Victory! I hit your cursor %d time%s out of %d." % [_hits, "" if _hits == 1 else "s", _clicks], 6.0)


func _process(delta: float) -> void:
	if not active:
		return
	_quiet += delta
	if _quiet > QUIET_TIMEOUT:
		stop(true)


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		stop()


func _on_arena_clicked(point: Vector2) -> void:
	_quiet = 0.0
	_clicks += 1
	app.pet.strike_at(point)


func _on_struck(_point: Vector2) -> void:
	_hits += 1
