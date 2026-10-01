extends Skill
## Guard instinct: when the cursor rests near the knight, it raises its shield, creeps
## toward the cursor and slashes it. It gives up if the cursor leaves.
## On GNOME Wayland this needs the Anicon GNOME extension (`anicon setup`).

## How close counts as "near", in screen pixels from the knight's feet.
const NEAR_X := 260.0
const NEAR_Y := 320.0
## The cursor must stay within STILL_PX for REST_TIME seconds.
const STILL_PX := 4
const REST_TIME := 1.2
const COOLDOWN := 6.0

var _anchor := Vector2i.ZERO
var _rest := 0.0
var _cooldown := 0.0
var _stalking := false


func _init() -> void:
	title = "Guard instinct"
	order = 7


func get_actions() -> Array:
	return [{"id": "toggle", "title": "Guard instinct: %s" % ("on" if Settings.get_value("guard_instinct") else "off")}]


func run_action(_id: String) -> void:
	var enabled: bool = not Settings.get_value("guard_instinct")
	Settings.set_value("guard_instinct", enabled)
	if enabled and not Pointer.knows_position():
		app.say("I can't see your cursor yet. Run \"anicon setup\" in a terminal, then log out and back in.", 8.0)
	else:
		app.say("Guard instinct: %s." % ("on. Rest your cursor near me, if you dare" if enabled else "off"))


func _process(delta: float) -> void:
	var pet: Pet = app.pet
	_cooldown -= delta
	if not Settings.get_value("guard_instinct") or pet.battle_mode or not Pointer.knows_position():
		_rest = 0.0
		if _stalking:
			_give_up()
		return
	var cursor: Vector2i = Pointer.position
	var moved := (cursor - _anchor).length() > STILL_PX
	if moved:
		_anchor = cursor
		_rest = 0.0
	else:
		_rest += delta

	if _stalking:
		if pet.state != Pet.State.WALK and pet.state != Pet.State.ACT:
			_stalking = false  # dragged, thrown or otherwise interrupted
		elif not _is_near(Vector2(cursor)):
			_give_up()
		elif moved and pet.state == Pet.State.WALK:
			pet.stalk_to(_stop_x(Vector2(cursor)), _strike)
		return

	if _cooldown <= 0 and _rest >= REST_TIME and _is_near(Vector2(cursor)) and pet.is_idle():
		_stalking = true
		pet.play_once("shield")
		pet.action_finished.connect(_advance, CONNECT_ONE_SHOT)


## Shield is up: creep closer, or strike right away if already in reach.
func _advance() -> void:
	var pet: Pet = app.pet
	if not _stalking or pet.state != Pet.State.IDLE:
		_stalking = false
		return
	var cursor := Vector2(Pointer.position)
	if pet.can_reach(cursor):
		_strike()
	else:
		pet.stalk_to(_stop_x(cursor), _strike)


func _strike() -> void:
	_stalking = false
	_cooldown = COOLDOWN
	app.pet.strike_at(Vector2(Pointer.position))


func _give_up() -> void:
	_stalking = false
	_cooldown = 2.0
	app.pet.stop_moving()


func _is_near(cursor: Vector2) -> bool:
	var feet: Vector2 = app.pet.feet
	return absf(cursor.x - feet.x) <= NEAR_X and cursor.y <= feet.y and cursor.y >= feet.y - NEAR_Y \
		and Platform.screen_at(cursor) == Platform.screen_at(feet + Vector2(0, -1))


## Where to stop so the cursor is just in front of the sword.
func _stop_x(cursor: Vector2) -> float:
	var side := 1.0 if cursor.x >= app.pet.feet.x else -1.0
	return cursor.x - side * 12.0 * app.pet.scale_factor
