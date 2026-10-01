extends Skill
## Climb windows: when a window sits behind the knight for a moment, it walks out to the
## window's side, climbs up and wanders along the title bar. Click the title bar, or
## move, resize, minimize or close the window, and it falls back down.
## On GNOME Wayland this needs the Anicon GNOME extension (`anicon setup`), which is what
## tells the knight where the other windows are.

## How long a window must cover the knight before it climbs out.
const COVERED_TIME := 1.5
## Rest after falling off, so it doesn't climb straight back up.
const COOLDOWN := 5.0
## Height of the clickable title bar strip, in screen pixels.
const TITLE_STRIP := 40.0

var _covered_id := -1
var _covered := 0.0
var _cooldown := 0.0
var _was_on_window := false


func _init() -> void:
	title = "Climb windows"
	order = 8


func _ready() -> void:
	Pointer.clicked.connect(_on_clicked)


func get_actions() -> Array:
	return [{"id": "toggle", "title": "Climb windows: %s" % ("on" if Settings.get_value("climb_windows") else "off")}]


func run_action(_id: String) -> void:
	var enabled: bool = not Settings.get_value("climb_windows")
	Settings.set_value("climb_windows", enabled)
	if not enabled:
		app.pet.drop_from_perch()
	if enabled and Pointer.needs_extension() and not Pointer.knows_windows():
		app.say("I can't see your windows yet. Run \"anicon setup\" in a terminal, then log out and back in.", 8.0)
	else:
		app.say("Climbing windows: %s." % ("on! Put a window behind me" if enabled else "off"))


func _process(delta: float) -> void:
	var pet: Pet = app.pet
	var on_window := pet.perch_rect().has_area()
	if _was_on_window and not on_window:
		_cooldown = COOLDOWN
	_was_on_window = on_window
	_cooldown -= delta
	if not Settings.get_value("climb_windows") or on_window or _cooldown > 0 or not (pet.is_idle() or pet.is_wandering()):
		_covered_id = -1
		return
	var window := _covering_window(pet)
	if window.is_empty() or window.id != _covered_id:
		_covered_id = -1 if window.is_empty() else window.id
		_covered = 0.0
		return
	_covered += delta
	if _covered < COVERED_TIME:
		return
	_covered_id = -1
	var edge := _climb_spot(pet, window.rect)
	if is_nan(edge):
		_cooldown = COOLDOWN
		return
	pet.run_to(edge, pet.climb.bind(window.id))


## The topmost window behind the knight that it could stand on, or {}.
func _covering_window(pet: Pet) -> Dictionary:
	var s := float(pet.scale_factor)
	var body := Rect2(pet.feet - Vector2(Pet.BODY_HALF_WIDTH * s, Pet.BODY_HEIGHT * s), Vector2(Pet.BODY_HALF_WIDTH * 2 * s, Pet.BODY_HEIGHT * s))
	var screen := Rect2(DisplayServer.screen_get_usable_rect(Platform.screen_at(pet.feet + Vector2(0, -1))))
	for window: Dictionary in Pointer.windows:
		var rect: Rect2 = window.rect
		if not rect.intersects(body):
			continue
		# Needs headroom above the title bar, something to climb, and room to stand on.
		var climbable := rect.position.y - Pet.BODY_HEIGHT * s >= screen.position.y \
			and rect.position.y < pet.feet.y - 4 * s and rect.size.x >= Pet.BODY_HALF_WIDTH * 4 * s
		return window if climbable else {}
	return {}


## Screen x just outside the nearer side of `rect` that the knight can reach, or NAN.
func _climb_spot(pet: Pet, rect: Rect2) -> float:
	var half := Pet.BODY_HALF_WIDTH * pet.scale_factor
	var screen := Rect2(DisplayServer.screen_get_usable_rect(Platform.screen_at(pet.feet + Vector2(0, -1))))
	var spots := [rect.position.x - half, rect.end.x + half]
	if absf(spots[1] - pet.feet.x) < absf(spots[0] - pet.feet.x):
		spots.reverse()
	for x: float in spots:
		if x - half >= screen.position.x and x + half <= screen.end.x:
			return x
	return NAN


func _on_clicked(point: Vector2i) -> void:
	var pet: Pet = app.pet
	var rect := pet.perch_rect()
	var spot := Vector2(point)
	if not rect.has_area() or pet.screen_hit_rect().has_point(spot):
		return
	if Rect2(rect.position, Vector2(rect.size.x, TITLE_STRIP)).has_point(spot):
		pet.drop_from_perch()
