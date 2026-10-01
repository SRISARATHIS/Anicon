extends Skill
## Chase my clicks: click rapidly anywhere (3 clicks within 1.5 s) and the knight runs
## after your cursor and slashes it. Clicks keep reaching your apps as usual. The chase
## lasts a few seconds after the latest click, so keep clicking to keep it going.
## On GNOME Wayland this needs the Anicon GNOME extension (`anicon setup`).

const CLICKS_TO_START := 3
const CLICK_WINDOW_MSEC := 1500
## How long the chase lasts after the latest click.
const CHASE_MSEC := 6000
## How often the knight re-aims at the moving cursor.
const RETARGET_SECONDS := 0.25

var _recent: Array[int] = []
var _chasing_until := 0
var _retarget := 0.0


func _init() -> void:
	title = "Chase my clicks"
	order = 6


func _ready() -> void:
	Pointer.clicked.connect(_on_clicked)


func get_actions() -> Array:
	return [{"id": "toggle", "title": "Chase my clicks: %s" % ("on" if Settings.get_value("chase_clicks") else "off")}]


func run_action(_id: String) -> void:
	var enabled: bool = not Settings.get_value("chase_clicks")
	Settings.set_value("chase_clicks", enabled)
	if enabled and Pointer.needs_extension() and not Pointer.sees_clicks():
		app.say("I can't see your clicks yet. Run \"anicon setup\" in a terminal, then log out and back in.", 8.0)
	else:
		app.say("Chasing clicks: %s." % ("on! Click fast three times" if enabled else "off"))


func is_chasing() -> bool:
	return Time.get_ticks_msec() < _chasing_until


func _process(delta: float) -> void:
	if not is_chasing():
		return
	var pet: Pet = app.pet
	if not Settings.get_value("chase_clicks") or pet.battle_mode or pet.state == Pet.State.DRAG:
		_chasing_until = 0
		return
	_retarget -= delta
	if _retarget > 0:
		return
	_retarget = RETARGET_SECONDS
	var cursor := Vector2(Pointer.position)
	if _reachable(cursor):
		pet.strike_at(cursor)


func _on_clicked(point: Vector2i) -> void:
	var pet: Pet = app.pet
	var spot := Vector2(point)
	if not Settings.get_value("chase_clicks") or pet.battle_mode:
		return
	# Clicks on the knight itself are pokes and drags.
	if pet.screen_hit_rect().has_point(spot) or not _reachable(spot):
		return
	var now := Time.get_ticks_msec()
	if is_chasing():
		_chasing_until = now + CHASE_MSEC
		return
	_recent.append(now)
	_recent = _recent.filter(func(t: int): return now - t <= CLICK_WINDOW_MSEC)
	if _recent.size() >= CLICKS_TO_START:
		_recent.clear()
		_chasing_until = now + CHASE_MSEC
		_retarget = 0.0
		pet.strike_at(spot)


## Other screens are out of reach.
func _reachable(spot: Vector2) -> bool:
	var pet: Pet = app.pet
	return Platform.screen_at(spot) == Platform.screen_at(pet.feet + Vector2(0, -1))
