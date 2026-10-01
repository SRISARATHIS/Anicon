class_name Pet
extends Node2D
## The knight: animations, wandering behaviour and screen physics.
## The pet's window is a transparent layer covering the usable area of the screen the
## knight is on. Only the knight itself catches the mouse; everything else clicks through.
## Moving the sprite inside a still window is much smoother than moving a small window.
## It can also climb other apps' windows (see climb_skill.gd) and stand on their title
## bars; it falls off when that window moves or goes away.

signal double_clicked
signal right_clicked
signal action_finished
## Battle mode: the user clicked somewhere on the screen (screen coordinates).
signal arena_clicked(point: Vector2)
## Battle mode: the knight's sword hit `point`.
signal struck(point: Vector2)

enum State { IDLE, WALK, GUARD, SLEEP, DRAG, FALL, ACT, CLIMB }
## How the knight moves in run_to(): wander-walk, run, or creep behind its shield.
enum Pace { WALK, RUN, STALK }

const SHEET_DIR := "res://assets/sprites/royal_knight/"
## name: [sheet, frame width, fps, loop]
const ANIMS := {
	"idle": ["combat_ready_idle", 22, 8.0, true],
	"walk": ["walk", 22, 10.0, true],
	"run": ["run", 22, 14.0, true],
	"fall": ["fall", 22, 10.0, true],
	"roll": ["roll", 22, 18.0, false],
	"hit_front": ["hit_front", 22, 12.0, false],
	"hit_back": ["hit_back", 22, 12.0, false],
	"shield": ["shield_raise", 22, 8.0, false],
	"shield_walk": ["shield_raise_walk", 22, 7.0, true],
	"channel": ["sword_channel", 22, 8.0, true],
	"cheer": ["sword_raise", 22, 10.0, false],
	"climb": ["jump", 22, 10.0, true],
	"attack_1": ["attack_1", 40, 16.0, false],
	"attack_2": ["attack_2", 40, 16.0, false],
	"attack_3": ["attack_3", 40, 16.0, false],
}
const ATTACKS := ["attack_1", "attack_2", "attack_3"]
# Sizes below are in sprite pixels and get multiplied by scale_factor.
const BODY_HALF_WIDTH := 9.0
const BODY_HEIGHT := 22.0
const WALK_SPEED := 14.0
const RUN_SPEED := 45.0
const STALK_SPEED := 12.0
const ACCELERATION := 120.0
const DECELERATION := 160.0
const GRAVITY := 700.0
const AIR_DRAG := 150.0
const BOUNCE_SPEED := 250.0
const ROLL_SPEED := 120.0
const CLIMB_SPEED := 30.0
const MAX_THROW := 1500.0
## How quickly a dragged knight catches up with the cursor (higher = stiffer).
const DRAG_FOLLOW := 22.0
const DRAG_THRESHOLD := 5.0
const CLICK_DELAY := 0.3
const IDLE_POLL := 3.0
## Battle mode: sword reach in front of the feet, and how far the knight will leap.
const REACH := Rect2(-4, -30, 28, 30)
const LEAP_RANGE := 90.0
const ARENA_TINT := Color(0.12, 0.05, 0.2, 0.18)
const INVALID_RECT := Rect2i(0, 0, -1, -1)

var scale_factor := 3
var feet := Vector2.ZERO
var velocity := Vector2.ZERO
var state := State.IDLE
var facing := 1
## Looping animation shown instead of "idle" while the pet is busy (e.g. waiting for the LLM).
var busy_anim := ""
## In battle mode the whole screen catches clicks and every click becomes `arena_clicked`.
var battle_mode := false

var _state_time := 0.0
var _speed := 0.0
var _stopping := false
var _walk_target := NAN
var _pace := Pace.WALK
var _on_arrive := Callable()
var _area := Rect2()
var _area_refresh := 0.0
## The part of the window that catches the mouse; INVALID_RECT forces a refresh.
var _hit_rect := INVALID_RECT
var _bounced := false
var _pressed := false
var _dragged := false
var _press_mouse := Vector2.ZERO
var _grab_offset := Vector2.ZERO
var _pending_click := 0.0
var _last_mouse := Vector2i.ZERO
var _last_activity_msec := 0
var _system_idle := -1.0
var _idle_poll := 0.0
var _polling_idle := false
var _zzz_time := 0.0
var _strike_target := Vector2.ZERO
var _strike_pending := false
var _striking := false
var _struck_this_swing := false
var _combo := 0
var _effects: Array = []
## The window the knight stands on (-1 = the floor) or is climbing, and its rect then.
var _perch_id := -1
var _perch_rect := Rect2()

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var zzz: Label = $Zzz


func _ready() -> void:
	sprite.sprite_frames = _build_frames()
	sprite.animation_changed.connect(_fit_frame)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	_last_activity_msec = Time.get_ticks_msec()
	_area = _area_for(Vector2(DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen()).get_center()))
	_fit_window()
	set_scale_factor(Settings.get_value("scale"))
	_set_state(State.IDLE)


func set_scale_factor(value: int) -> void:
	scale_factor = clampi(value, 1, 10)
	var s := float(scale_factor)
	sprite.scale = Vector2(s, s)
	var settings := LabelSettings.new()
	settings.font_size = int(7 * s)
	settings.font_color = Color("e8f1ff")
	settings.outline_size = int(2 * s)
	settings.outline_color = Color("2b2230")
	zzz.label_settings = settings
	_sync_window()


func set_battle_mode(on: bool) -> void:
	drop_from_perch()
	battle_mode = on
	_walk_target = NAN
	_on_arrive = Callable()
	_strike_pending = false
	_striking = false
	_combo = 0
	_effects.clear()
	_hit_rect = INVALID_RECT
	_sync_window()
	queue_redraw()


## Run (or leap) to `point` and slash it. New targets during a swing chain into a combo.
func strike_at(point: Vector2) -> void:
	# Swing from the title bar if the target is in reach; otherwise jump down after it.
	if state == State.CLIMB or not can_reach(point):
		drop_from_perch()
	_strike_target = point
	_strike_pending = true
	if state == State.SLEEP:
		wake()
	if state in [State.IDLE, State.WALK, State.GUARD]:
		_continue_strike()


## Drops the pet in from the top of the screen.
func drop_in() -> void:
	_perch_id = -1
	_area = _area_for(feet if feet != Vector2.ZERO else Vector2(DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen()).get_center()))
	_fit_window()
	feet = Vector2(_area.get_center().x + randf_range(-100, 100), _area.position.y + BODY_HEIGHT * scale_factor)
	velocity = Vector2(randf_range(-60, 60) * scale_factor, 0)
	_set_state(State.FALL)


## Screen position just above the knight's head, for the speech bubble.
func head_screen_pos() -> Vector2i:
	return Vector2i(feet + Vector2(0, -(BODY_HEIGHT + 3) * scale_factor))


func area_center_x() -> float:
	return _area.get_center().x


func is_sleeping() -> bool:
	return state == State.SLEEP


## Plays a one-shot animation, then returns to idle (emits `action_finished`).
func play_once(anim: String) -> void:
	if state == State.DRAG or state == State.FALL:
		return
	_walk_target = NAN
	_on_arrive = Callable()
	state = State.ACT
	zzz.hide()
	sprite.speed_scale = 1.0
	sprite.play(anim)


## Runs to screen x, then calls `on_arrive` (dropped if the run is interrupted).
func run_to(x: float, on_arrive := Callable(), pace := Pace.RUN) -> void:
	if state == State.DRAG or state == State.FALL:
		if on_arrive.is_valid():
			on_arrive.call()
		return
	var keep_speed := state == State.WALK and pace == _pace
	_walk_target = clampf(x, _left_wall(), _right_wall())
	_on_arrive = on_arrive
	_pace = pace
	_set_state(State.WALK)
	if not keep_speed:
		_speed = 0.0


## Creeps to screen x behind the raised shield, then calls `on_arrive`.
func stalk_to(x: float, on_arrive := Callable()) -> void:
	run_to(x, on_arrive, Pace.STALK)


## Climbs the side of window `id` (from Pointer.windows) that the knight stands next to,
## then steps onto its title bar.
func climb(id: int) -> void:
	var window := Pointer.window_by_id(id)
	if window.is_empty() or state in [State.DRAG, State.FALL, State.CLIMB] or battle_mode:
		return
	_perch_id = id
	_perch_rect = window.rect
	_walk_target = NAN
	_on_arrive = Callable()
	facing = 1 if _perch_rect.get_center().x > feet.x else -1
	_set_state(State.CLIMB)


## Lets go of the window the knight is on or climbing; it falls to the floor.
func drop_from_perch() -> void:
	if _perch_id < 0:
		return
	_perch_id = -1
	if state != State.DRAG:
		_walk_target = NAN
		_on_arrive = Callable()
		velocity = Vector2.ZERO
		_set_state(State.FALL)


## Standing on a window's title bar (not climbing).
func is_perched() -> bool:
	return _perch_id >= 0 and state != State.CLIMB


## The window being stood on or climbed, as it was when the climb started.
func perch_rect() -> Rect2:
	return _perch_rect if _perch_id >= 0 else Rect2()


## Walking around on its own, without a destination.
func is_wandering() -> bool:
	return state == State.WALK and is_nan(_walk_target)


## Eases to a stop if walking, dropping any destination.
func stop_moving() -> void:
	if state != State.WALK:
		return
	_walk_target = NAN
	_on_arrive = Callable()
	_stopping = true


## Idle and free to do something new (not busy, battling or asleep).
func is_idle() -> bool:
	return state == State.IDLE and busy_anim == "" and not battle_mode and not _strike_pending


## Whether the sword can reach `point` from where the knight stands.
func can_reach(point: Vector2) -> bool:
	return _in_reach(point, 1 if point.x >= feet.x else -1)


## The part of the screen that belongs to the knight (where clicks hit it, not the desktop).
func screen_hit_rect() -> Rect2:
	return Rect2(Vector2(_hit_rect.position + get_window().position), Vector2(_hit_rect.size))


func set_busy(anim: String) -> void:
	busy_anim = anim
	if anim != "" and state in [State.WALK, State.GUARD, State.SLEEP]:
		_walk_target = NAN
		_set_state(State.IDLE)
	elif state == State.IDLE:
		sprite.play(busy_anim if busy_anim != "" else "idle")


func wake() -> void:
	_system_idle = 0.0
	_last_activity_msec = Time.get_ticks_msec()
	if state == State.SLEEP:
		play_once("cheer")


func stress() -> void:
	if state in [State.IDLE, State.WALK, State.GUARD]:
		play_once("hit_front")


func _process(delta: float) -> void:
	_track_activity(delta)
	_area_refresh -= delta
	if _area_refresh <= 0 and state != State.DRAG:
		_area_refresh = 1.0
		_area = _area_for(feet + Vector2(0, -1))
	_update_press(delta)
	_check_perch()
	_state_time -= delta
	match state:
		State.IDLE:
			_process_idle()
		State.WALK:
			_process_walk(delta)
		State.GUARD:
			if _state_time <= 0:
				_set_state(State.IDLE)
		State.SLEEP:
			_animate_zzz(delta)
		State.DRAG:
			_process_drag(delta)
		State.FALL:
			_process_fall(delta)
		State.CLIMB:
			_process_climb(delta)
	if state not in [State.DRAG, State.FALL, State.CLIMB]:
		if feet.y < _ground_y() - 0.5:
			_set_state(State.FALL)
		feet.y = minf(feet.y, _ground_y())
		feet.x = clampf(feet.x, _left_wall(), _right_wall())
	_sync_window()
	if not _effects.is_empty():
		for effect: Dictionary in _effects:
			effect.age += delta
		_effects = _effects.filter(func(e: Dictionary): return e.age < 0.4)
		queue_redraw()


func _draw() -> void:
	if not battle_mode:
		return
	var origin := Vector2(get_window().position)
	draw_rect(Rect2(Vector2.ZERO, get_window().size), ARENA_TINT)
	for effect: Dictionary in _effects:
		var t: float = effect.age / 0.4
		var center: Vector2 = effect.pos - origin
		var color := Color(1, 0.9, 0.4, 1.0 - t)
		for i in 8:
			var direction := Vector2.from_angle(i * TAU / 8 + 0.3)
			draw_line(center + direction * (4 + 10 * t) * scale_factor, center + direction * (8 + 14 * t) * scale_factor, color, scale_factor)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		right_clicked.emit()
	elif button.button_index == MOUSE_BUTTON_LEFT and battle_mode:
		if button.pressed:
			arena_clicked.emit(Vector2(DisplayServer.mouse_get_position()))
	elif button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			if button.double_click:
				_pending_click = 0.0
				double_clicked.emit()
				return
			_pressed = true
			_dragged = false
			_press_mouse = Vector2(DisplayServer.mouse_get_position())
		else:
			_pressed = false
			if state == State.DRAG:
				velocity = velocity.limit_length(MAX_THROW * scale_factor)
				_set_state(State.FALL)
			elif not _dragged:
				_pending_click = CLICK_DELAY


func _update_press(delta: float) -> void:
	if _pressed and state != State.DRAG:
		var mouse := Vector2(DisplayServer.mouse_get_position())
		if mouse.distance_to(_press_mouse) > DRAG_THRESHOLD:
			_dragged = true
			_perch_id = -1
			_grab_offset = feet - _press_mouse
			velocity = Vector2.ZERO
			_walk_target = NAN
			_on_arrive = Callable()
			_set_state(State.DRAG)
	if _pending_click > 0:
		_pending_click -= delta
		if _pending_click <= 0:
			_on_poked()


func _on_poked() -> void:
	if state == State.SLEEP:
		wake()
	elif state in [State.IDLE, State.WALK, State.GUARD]:
		play_once(ATTACKS.pick_random())


func _process_idle() -> void:
	_look_at_mouse()
	if battle_mode:
		return
	if _sleep_due():
		_set_state(State.SLEEP)
		return
	if _state_time > 0 or busy_anim != "" or not Settings.get_value("wander"):
		return
	var roll := randf()
	if roll < 0.55:
		facing = [-1, 1].pick_random()
		_walk_target = NAN
		_pace = Pace.WALK
		_speed = 0.0
		_set_state(State.WALK)
	elif roll < 0.75:
		_set_state(State.GUARD)
	elif roll < 0.85:
		play_once(ATTACKS.pick_random())
	else:
		_set_state(State.IDLE)


func _process_walk(delta: float) -> void:
	var s := float(scale_factor)
	var running := not is_nan(_walk_target)
	var top_speed := WALK_SPEED * s
	if running:
		top_speed = (STALK_SPEED if _pace == Pace.STALK else RUN_SPEED) * s
	var target_speed := 0.0 if _stopping else top_speed
	if running:
		var distance := absf(_walk_target - feet.x)
		var direction := 1 if _walk_target > feet.x else -1
		if distance < 0.5:
			feet.x = _walk_target
			_arrive()
			return
		if direction != facing:
			# Slow down before turning around instead of snapping.
			target_speed = 0.0
			if _speed < 1.0:
				facing = direction
		else:
			# Ease into the stop: never faster than what we can brake from in time.
			target_speed = minf(target_speed, sqrt(2.0 * DECELERATION * s * distance) + 1.5 * s)
	elif _state_time <= 0:
		_stopping = true
	var rate := (ACCELERATION if target_speed > _speed else DECELERATION) * s
	_speed = move_toward(_speed, target_speed, rate * delta)
	var step := _speed * delta
	if running and (1 if _walk_target > feet.x else -1) == facing and step >= absf(_walk_target - feet.x):
		feet.x = _walk_target
		_arrive()
		return
	feet.x += facing * step
	if feet.x <= _left_wall() or feet.x >= _right_wall():
		feet.x = clampf(feet.x, _left_wall(), _right_wall())
		if running:
			_arrive()
			return
		facing = -facing
	sprite.flip_h = facing < 0
	# Keep the legs in step with the actual speed so the knight doesn't skate.
	sprite.speed_scale = clampf(_speed / top_speed, 0.35, 1.0)
	if _stopping and _speed <= 0.0:
		_set_state(State.IDLE)


func _process_drag(delta: float) -> void:
	var target := Vector2(DisplayServer.mouse_get_position()) + _grab_offset
	var previous := feet
	feet = feet.lerp(target, 1.0 - exp(-DRAG_FOLLOW * delta))
	velocity = velocity.lerp((feet - previous) / maxf(delta, 0.001), 0.35)
	var area := _area_for(feet + Vector2(0, -1))
	if area != _area:
		_area = area
		_fit_window()
	if absf(velocity.x) > 50:
		facing = 1 if velocity.x > 0 else -1
		sprite.flip_h = facing < 0


func _process_fall(delta: float) -> void:
	var s := float(scale_factor)
	velocity.y += GRAVITY * s * delta
	velocity.x = move_toward(velocity.x, 0, AIR_DRAG * s * delta)
	feet += velocity * delta
	if _striking and not _struck_this_swing:
		_try_hit()
	var area := _area_for(feet + Vector2(0, -1))
	if area != _area:
		_area = area
		_fit_window()
	if feet.x < _left_wall():
		feet.x = _left_wall()
		velocity.x = absf(velocity.x) * 0.5
	elif feet.x > _right_wall():
		feet.x = _right_wall()
		velocity.x = -absf(velocity.x) * 0.5
	var ceiling := _area.position.y + BODY_HEIGHT * s
	if feet.y < ceiling:
		feet.y = ceiling
		velocity.y = absf(velocity.y) * 0.3
	if feet.y < _ground_y():
		return
	feet.y = _ground_y()
	if velocity.y > BOUNCE_SPEED * s and not _bounced:
		_bounced = true
		velocity = Vector2(velocity.x * 0.6, -velocity.y * 0.3)
		return
	var landing_speed := velocity.x
	velocity = Vector2.ZERO
	_set_state(State.IDLE)
	if _striking or _strike_pending:
		_striking = false
		if _strike_pending:
			_continue_strike()
		return
	if absf(landing_speed) > ROLL_SPEED * s:
		facing = 1 if landing_speed > 0 else -1
		sprite.flip_h = facing < 0
		play_once("roll")
	elif _bounced:
		play_once("hit_back")


func _process_climb(delta: float) -> void:
	var s := float(scale_factor)
	feet.y -= CLIMB_SPEED * s * delta
	if feet.y > _perch_rect.position.y:
		return
	# Over the top: hop onto the title bar, just inside the edge.
	feet.y = _perch_rect.position.y
	if facing > 0:
		feet.x = _perch_rect.position.x + (BODY_HALF_WIDTH + 2.0) * s
	else:
		feet.x = _perch_rect.end.x - (BODY_HALF_WIDTH + 2.0) * s
	_set_state(State.IDLE)
	feet.x = clampf(feet.x, _left_wall(), _right_wall())


## Falls off when the window being stood on or climbed moves, resizes or goes away.
func _check_perch() -> void:
	if _perch_id < 0:
		return
	var window := Pointer.window_by_id(_perch_id)
	if not Pointer.knows_windows() or window.is_empty() or window.rect != _perch_rect:
		drop_from_perch()


func _set_state(new_state: State) -> void:
	state = new_state
	zzz.visible = new_state == State.SLEEP
	sprite.speed_scale = 1.0
	_stopping = false
	match new_state:
		State.IDLE:
			_state_time = randf_range(3.0, 8.0)
			_speed = 0.0
			sprite.play(busy_anim if busy_anim != "" else "idle")
		State.WALK:
			_state_time = randf_range(2.0, 6.0)
			sprite.play({Pace.WALK: "walk", Pace.RUN: "run", Pace.STALK: "shield_walk"}[_pace if not is_nan(_walk_target) else Pace.WALK])
		State.GUARD:
			_state_time = randf_range(3.0, 7.0)
			sprite.play("shield")
		State.SLEEP:
			sprite.play("shield")
		State.DRAG, State.FALL:
			_bounced = false
			sprite.play("fall")
		State.CLIMB:
			sprite.play("climb")
	sprite.flip_h = facing < 0


func _arrive() -> void:
	_walk_target = NAN
	var callback := _on_arrive
	_on_arrive = Callable()
	_set_state(State.IDLE)
	if callback.is_valid():
		callback.call()


func _on_animation_finished() -> void:
	if state == State.ACT:
		_striking = false
		_set_state(State.IDLE)
		action_finished.emit()
		if _strike_pending:
			_continue_strike()


func _on_frame_changed() -> void:
	# The sword connects halfway through a ground swing.
	if _striking and state == State.ACT and not _struck_this_swing:
		if sprite.frame >= sprite.sprite_frames.get_frame_count(sprite.animation) / 2:
			_try_hit()


## Decide how to reach the strike target: swing, leap or run.
func _continue_strike() -> void:
	var s := float(scale_factor)
	var target := _strike_target
	var dx := target.x - feet.x
	var side := 1 if dx >= 0 else -1
	var height := feet.y - target.y
	if _in_reach(target, side):
		_strike_pending = false
		facing = side
		_swing()
		return
	if absf(dx) <= LEAP_RANGE * s and height > REACH.size.y * s * 0.8:
		# Jump so the apex is level with the target, arriving there horizontally at the apex.
		_strike_pending = false
		var rise := maxf(height - 18.0 * s, 10.0 * s)
		var up := sqrt(2.0 * GRAVITY * s * rise)
		facing = side
		velocity = Vector2(dx / (up / (GRAVITY * s)), -up)
		_set_state(State.FALL)
		_swing()
		return
	var stop_x := clampf(target.x - side * 12.0 * s, _left_wall(), _right_wall())
	if absf(stop_x - feet.x) < 1.0:
		# Already as close as we can get; swing anyway.
		_strike_pending = false
		facing = side
		_swing()
		return
	run_to(stop_x, _continue_strike)


func _swing() -> void:
	_striking = true
	_struck_this_swing = false
	var anim: String = ATTACKS[_combo % ATTACKS.size()]
	_combo += 1
	if state == State.FALL:
		sprite.play(anim)
	else:
		play_once(anim)
	sprite.flip_h = facing < 0


func _try_hit() -> void:
	if not _in_reach(_strike_target, facing):
		return
	_struck_this_swing = true
	_effects.append({"pos": _strike_target, "age": 0.0})
	struck.emit(_strike_target)
	if not battle_mode:
		return
	# Knock the cursor back a little (the platform may ignore this).
	var knocked := _strike_target + Vector2(facing * 30.0 * scale_factor, -10.0 * scale_factor)
	Input.warp_mouse(knocked - Vector2(get_window().position))


func _in_reach(point: Vector2, side: int) -> bool:
	var local := (point - feet) / scale_factor
	local.x *= side
	return REACH.has_point(local)


func _track_activity(delta: float) -> void:
	var mouse: Vector2i = Pointer.position
	if mouse != _last_mouse:
		_last_mouse = mouse
		_last_activity_msec = Time.get_ticks_msec()
	_idle_poll -= delta
	if _idle_poll <= 0 and not _polling_idle:
		_idle_poll = IDLE_POLL
		_poll_system_idle()
	if state == State.SLEEP and _idle_seconds() < 2.0:
		wake()


func _poll_system_idle() -> void:
	_polling_idle = true
	_system_idle = await Platform.threaded(func(): return Platform.idle_seconds())
	_polling_idle = false


func _idle_seconds() -> float:
	if _system_idle >= 0:
		return _system_idle
	return (Time.get_ticks_msec() - _last_activity_msec) / 1000.0


func _sleep_due() -> bool:
	return _idle_seconds() >= float(Settings.get_value("sleep_minutes")) * 60.0


func _look_at_mouse() -> void:
	if busy_anim != "" or (Time.get_ticks_msec() - _last_activity_msec > 2000 and not battle_mode):
		return
	var dx := _last_mouse.x - feet.x
	if absf(dx) > BODY_HALF_WIDTH * scale_factor and absf(dx) < 300:
		facing = 1 if dx > 0 else -1
		sprite.flip_h = facing < 0


func _animate_zzz(delta: float) -> void:
	_zzz_time += delta
	zzz.text = ["z", "zZ", "zZz"][int(_zzz_time / 0.7) % 3]


func _left_wall() -> float:
	var left := _area.position.x
	if is_perched():
		left = maxf(left, _perch_rect.position.x)
	return left + BODY_HALF_WIDTH * scale_factor


func _right_wall() -> float:
	var right := _area.end.x
	if is_perched():
		right = minf(right, _perch_rect.end.x)
	return right - BODY_HALF_WIDTH * scale_factor


## Where the feet rest: the title bar it's standing on, or the bottom of the screen.
func _ground_y() -> float:
	return _perch_rect.position.y if is_perched() else _area.end.y


func _area_for(point: Vector2) -> Rect2:
	return Rect2(DisplayServer.screen_get_usable_rect(Platform.screen_at(point)))


## Makes the window cover the usable area of the knight's current screen.
func _fit_window() -> void:
	var window := get_window()
	var rect := Rect2i(_area)
	if window.position != rect.position:
		window.position = rect.position
	if window.size != rect.size:
		window.size = rect.size
	_hit_rect = INVALID_RECT
	queue_redraw()


## Places the sprite and updates which part of the window catches the mouse.
func _sync_window() -> void:
	var s := float(scale_factor)
	var window := get_window()
	sprite.position = feet - Vector2(window.position)
	zzz.position = sprite.position + Vector2(3 * s, -(BODY_HEIGHT + 14) * s)
	var hit := Rect2i()
	if not battle_mode:
		# The current frame's box (so attacks aren't clipped where the OS clips to this
		# region, e.g. Windows), plus the "zZz" while sleeping.
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		var box := Rect2(sprite.position + sprite.offset * s, texture.get_size() * s)
		if zzz.visible:
			box = box.merge(Rect2(zzz.position, Vector2(24, 9) * s))
		hit = Rect2i(box.grow(2))
	if hit != _hit_rect:
		_hit_rect = hit
		# An empty polygon means the whole window catches the mouse (battle mode).
		window.mouse_passthrough_polygon = PackedVector2Array() if not hit.has_area() else PackedVector2Array([
			Vector2(hit.position), Vector2(hit.end.x, hit.position.y), Vector2(hit.end), Vector2(hit.position.x, hit.end.y),
		])


func _fit_frame() -> void:
	# Frames have different sizes; keep the knight's feet at the sprite origin.
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	sprite.offset = Vector2(-texture.get_width() / 2.0, -texture.get_height())


func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim: String in ANIMS:
		var def: Array = ANIMS[anim]
		var texture: Texture2D = load(SHEET_DIR + def[0] + ".png")
		var frame_width: int = def[1]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, def[2])
		frames.set_animation_loop(anim, def[3])
		for i in texture.get_width() / frame_width:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_width, 0, frame_width, texture.get_height())
			frames.add_frame(anim, atlas)
	return frames
