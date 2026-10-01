extends Node
## Smoke test: `godot --path . -- --selftest [output_dir]`
## Exercises the pet, bubble, menu, skills and Ollama, logs what happens and saves
## snapshots of the windows, then quits. Exit code 0 means no check failed.

var app: Main
var _out := "user://selftest"
var _failures := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--selftest")
	if index + 1 < args.size():
		_out = args[index + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().create_timer(3.0).timeout
	await _run()
	_log("DONE with %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	var pet := app.pet
	var window := get_window()
	_log("screens: %s" % [range(DisplayServer.get_screen_count()).map(func(i): return DisplayServer.screen_get_usable_rect(i))])
	_log("pet window %s size %s, feet %s, state %s" % [window.position, window.size, pet.feet, Pet.State.keys()[pet.state]])
	_check(pet.state != Pet.State.FALL, "pet landed after drop-in")
	_check(not app.bubble.visible, "stays quiet on startup")
	_check(Rect2i(window.position, window.size) == DisplayServer.screen_get_usable_rect(Platform.screen_at(pet.feet + Vector2(0, -1))), "window covers the knight's screen")
	_check(pet.sprite.position == pet.feet - Vector2(window.position), "sprite sits at the feet")
	var hit := Rect2(window.mouse_passthrough_polygon[0], window.mouse_passthrough_polygon[2] - window.mouse_passthrough_polygon[0])
	_check(hit.has_point(pet.sprite.position + Vector2(0, -10 * pet.scale_factor)) and hit.size.x < 200, "only the knight catches the mouse (%s)" % hit)
	_snapshot(window, "pet_idle", Rect2i(Vector2i(pet.sprite.position) - Vector2i(72, 120), Vector2i(144, 120)))

	for anim in ["walk", "cheer", "attack_2", "channel", "shield"]:
		pet.sprite.play(anim)
		pet.sprite.frame = pet.sprite.sprite_frames.get_frame_count(anim) / 2
		await get_tree().process_frame
		await get_tree().process_frame
		_snapshot(window, "pet_" + anim, Rect2i(Vector2i(pet.sprite.position) - Vector2i(72, 120), Vector2i(144, 120)))
	pet._set_state(Pet.State.IDLE)

	# Smooth movement: speed ramps up, never jumps, and eases into the stop.
	var start_x := pet.feet.x
	var goal := clampf(start_x - 300.0, pet._left_wall(), pet._right_wall())
	if absf(goal - start_x) < 200:
		goal = start_x + 300.0
	pet.run_to(goal)
	var steps: Array[float] = []
	var last := pet.feet.x
	while pet.state == Pet.State.WALK:
		await get_tree().process_frame
		steps.append(absf(pet.feet.x - last))
		last = pet.feet.x
	var max_step: float = steps.max()
	_log("run of %d px: %d frames, first steps %s, last steps %s, max %.2f" % [absf(goal - start_x), steps.size(), steps.slice(0, 4), steps.slice(-4), max_step])
	_check(is_equal_approx(pet.feet.x, goal), "run arrives exactly")
	_check(steps[0] < max_step * 0.3 and steps[-2] < max_step * 0.6, "run accelerates and decelerates")

	pet.feet.y -= 300
	await get_tree().create_timer(2.5).timeout
	_check(pet.state != Pet.State.FALL and is_equal_approx(pet.feet.y, DisplayServer.screen_get_usable_rect(Platform.screen_at(pet.feet + Vector2(0, -1))).end.y), "pet falls back to the floor")

	var reminders: Script = load("res://scripts/skills/reminder_skill.gd")
	var now := Time.get_unix_time_from_system()
	for case in [["10m stretch", 600, "stretch"], ["1h30m call mom", 5400, "call mom"], ["in 5 minutes tea", 300, "tea"], ["25 pizza", 1500, "pizza"], ["90s", 90, "Time's up!"]]:
		var parsed: Dictionary = reminders.parse(case[0])
		_check(not parsed.is_empty() and absf(parsed.due - now - case[1]) < 2 and parsed.text == case[2], "parse '%s' -> %s" % [case[0], parsed])
	var at: Dictionary = reminders.parse("at 9:15pm standup")
	_check(not at.is_empty() and at.text == "standup" and at.due > now and at.due <= now + 86400, "parse 'at 9:15pm standup' -> %s" % [at])
	_check(reminders.parse("hello there").is_empty(), "parse rejects 'hello there'")

	app.say("Hello from the self test! This message is long enough to wrap onto a second line.")
	await get_tree().create_timer(2.5).timeout
	_log("bubble %s size %s anchor %s" % [app.bubble.position, app.bubble.size, app.bubble.anchor])
	_check(app.bubble.visible and app.bubble.position.y + app.bubble.size.y <= pet.head_screen_pos().y + 1, "bubble sits above the head")
	_snapshot(app.bubble, "bubble_say")
	app.bubble.think()
	await get_tree().create_timer(0.5).timeout
	_snapshot(app.bubble, "bubble_think")
	app.bubble.ask("Say something...", "A previous reply.")
	await get_tree().create_timer(0.5).timeout
	_snapshot(app.bubble, "bubble_ask")
	app.bubble.hide_bubble()

	var battle: Skill = app.skills.skills.filter(func(s): return s.title == "Battle mode")[0]
	battle.start()
	pet.arena_clicked.connect(func(point: Vector2): _log("  arena click at %s" % point))
	await get_tree().create_timer(0.5).timeout
	_check(window.size == DisplayServer.screen_get_usable_rect(Platform.screen_at(pet.feet + Vector2(0, -1))).size, "battle mode window covers the screen")
	_check(window.mouse_passthrough_polygon.is_empty(), "battle mode catches clicks everywhere")
	var s := float(pet.scale_factor)
	var room := -1.0 if pet.feet.x - pet._left_wall() > pet._right_wall() - pet.feet.x else 1.0
	var targets := [
		pet.feet + Vector2(15 * s, -12 * s),
		pet.feet + Vector2(room * 400, -10 * s),
		pet.feet + Vector2(room * (400 - 60 * s), -70 * s),
	]
	for target: Vector2 in targets:
		pet.arena_clicked.emit(target)
		var waited := 0.0
		while (pet._strike_pending or pet._striking or pet.state != Pet.State.IDLE) and waited < 6.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if OS.has_environment("ANICON_TRACE") and Engine.get_process_frames() % 6 == 0:
				_log("  t=%.2f feet=%s state=%s anim=%s target=%s pending=%s striking=%s" % [waited, pet.feet, Pet.State.keys()[pet.state], pet.sprite.animation, pet._walk_target, pet._strike_pending, pet._striking])
		_log("strike at %s -> feet %s, hits %d" % [target, pet.feet, battle._hits])
	_snapshot(window, "battle_arena")
	_check(battle._hits == targets.size(), "knight hit every target (%d/%d)" % [battle._hits, targets.size()])
	battle.stop()
	await get_tree().create_timer(0.5).timeout
	_check(not window.mouse_passthrough_polygon.is_empty(), "battle mode off makes the screen click-through again")

	await _test_pointer_skills()

	app._show_menu()
	await get_tree().create_timer(0.5).timeout
	_log("menu items: %s" % [range(app.menu.item_count).map(func(i): return app.menu.get_item_text(i))])
	_check(app.menu.item_count >= 8, "menu has chat, skills and app items")
	_snapshot(app.menu, "menu")
	app.menu.hide()

	var cpu: float = await Platform.threaded(func(): return Platform.cpu_percent())
	_check(cpu >= 0 and cpu <= 100, "cpu percent %.1f" % cpu)
	var idle: float = await Platform.threaded(func(): return Platform.idle_seconds())
	_log("system idle seconds: %.1f" % idle)
	_log("battery: %d" % Platform.battery_percent())
	var stats := app.skills.skills.filter(func(s): return s.title == "How's my computer?")
	_log("stats report: %s" % stats[0]._report(cpu))

	var models: Dictionary = await app.ollama.list_models()
	_log("ollama list_models: %s" % models)
	if models.ok:
		var reply: Dictionary = await app.chat.ask_once("Introduce yourself in one short sentence.")
		_check(reply.ok, "ollama reply: %s" % reply)


## Chase-my-clicks and guard instinct, fed with fake GNOME-extension datagrams.
func _test_pointer_skills() -> void:
	var pet := app.pet
	var s := float(pet.scale_factor)
	var udp := PacketPeerUDP.new()
	udp.set_dest_address("127.0.0.1", Pointer.PORT)
	var send := func(point: Vector2, buttons: int):
		udp.put_packet(("%d %d %d" % [point.x, point.y, buttons]).to_utf8_buffer())
	var hits := [0]
	pet.struck.connect(func(_point: Vector2): hits[0] += 1)
	await _wait_until_idle()

	# Three quick clicks away from the knight: it should run over and slash the spot.
	var side := -1.0 if pet.feet.x - pet._left_wall() > 400 else 1.0
	var spot := pet.feet + Vector2(side * 350, -10 * s)
	for i in 3:
		send.call(spot, 1)
		await get_tree().create_timer(0.08).timeout
		send.call(spot, 0)
		await get_tree().create_timer(0.15).timeout
	_check(Pointer.sees_clicks(), "pointer data arrives over UDP")
	await get_tree().create_timer(0.3).timeout
	_check(pet.state == Pet.State.WALK and pet.sprite.animation == "run", "rapid clicks send the knight running")
	var chase: Skill = app.skills.skills.filter(func(skill): return skill.title == "Chase my clicks")[0]
	var waited := 0.0
	while hits[0] == 0 and waited < 6.0:
		if int(waited * 60) % 20 == 0:
			send.call(spot, 0)  # heartbeat, as the extension does
		await get_tree().process_frame
		waited += get_process_delta_time()
	_log("chase: feet %s, spot %s, hits %d" % [pet.feet, spot, hits[0]])
	_check(hits[0] >= 1 and absf(pet.feet.x - spot.x) < 30 * s, "knight chased the clicks and hit the spot")

	# While the chase lasts, the knight follows the cursor itself.
	var cursor := spot - Vector2(side * 250, 0)
	hits[0] = 0
	waited = 0.0
	send.call(cursor, 1)  # another click keeps the chase going
	await get_tree().create_timer(0.08).timeout
	while hits[0] == 0 and waited < 6.0 and chase.is_chasing():
		if int(waited * 60) % 10 == 0:
			send.call(cursor, 0)
		await get_tree().process_frame
		waited += get_process_delta_time()
	_log("chase cursor: feet %s, cursor %s, hits %d" % [pet.feet, cursor, hits[0]])
	_check(hits[0] >= 1 and absf(pet.feet.x - cursor.x) < 30 * s, "knight chased the moving cursor and hit it")

	# A single click elsewhere must not start a chase.
	chase._chasing_until = 0
	await _wait_until_idle()
	send.call(spot - Vector2(side * 300, 0), 1)
	await get_tree().create_timer(0.08).timeout
	send.call(spot - Vector2(side * 300, 0), 0)
	await get_tree().create_timer(0.6).timeout
	_check(pet.state != Pet.State.WALK or pet.sprite.animation != "run", "a single click is ignored")
	await _wait_until_idle()

	# Cursor resting near the knight: shield up, creep closer, slash.
	var guard: Skill = app.skills.skills.filter(func(skill): return skill.title == "Guard instinct")[0]
	guard._cooldown = 0.0
	hits[0] = 0
	var rest := pet.feet + Vector2(-side * 150, -12 * s)
	var seen := {}
	waited = 0.0
	while waited < 12.0 and hits[0] == 0:
		pet._state_time = 1.0  # no wandering off mid-test
		if int(waited * 60) % 20 == 0:
			send.call(rest, 0)  # heartbeat, as the extension does
		seen[pet.sprite.animation] = true
		await get_tree().process_frame
		waited += get_process_delta_time()
	_log("guard: animations %s, feet %s, cursor %s, hits %d after %.1fs" % [seen.keys(), pet.feet, rest, hits[0], waited])
	_check(seen.has("shield") and seen.has("shield_walk"), "guard raises the shield and creeps")
	_check(hits[0] >= 1, "guard slashes the resting cursor")
	await _wait_until_idle()
	udp.close()
	await _test_climbing()


## A (fake) window behind the knight: it climbs onto the title bar, wanders there, and
## falls off when the window moves or its title bar is clicked.
func _test_climbing() -> void:
	var pet := app.pet
	var s := float(pet.scale_factor)
	var climb: Skill = app.skills.skills.filter(func(skill): return skill.title == "Climb windows")[0]
	var screen := Rect2(DisplayServer.screen_get_usable_rect(Platform.screen_at(pet.feet + Vector2(0, -1))))
	var rect := Rect2(clampf(pet.feet.x - 150, screen.position.x + 100, screen.end.x - 500), screen.end.y - 250, 400, 250)
	var feed := func(r: Rect2):
		Pointer._read_windows(PackedStringArray(["W", "424242,0,%d,%d,%d,%d" % [r.position.x, r.position.y, r.size.x, r.size.y]]))
	climb._cooldown = 0.0
	var seen := {}
	var waited := 0.0
	while waited < 15.0 and not pet.is_perched():
		feed.call(rect)
		seen[pet.sprite.animation] = true
		await get_tree().process_frame
		waited += get_process_delta_time()
	_log("climb: animations %s, feet %s, window %s after %.1fs" % [seen.keys(), pet.feet, rect, waited])
	_check(seen.has("climb") and pet.is_perched() and is_equal_approx(pet.feet.y, rect.position.y), "knight climbs onto the title bar")
	waited = 0.0
	var stayed := true
	while waited < 4.0:
		feed.call(rect)
		if stayed and not (pet.is_perched() and pet.feet.x >= rect.position.x and pet.feet.x <= rect.end.x):
			stayed = false
			_log("  left the window: feet %s state %s anim %s" % [pet.feet, Pet.State.keys()[pet.state], pet.sprite.animation])
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check(stayed, "knight stays on the window while it's still")

	feed.call(Rect2(rect.position + Vector2(40, 30), rect.size))
	await get_tree().process_frame
	_check(not pet.is_perched() and pet.state == Pet.State.FALL, "moving the window drops the knight")
	await get_tree().create_timer(2.5).timeout
	_check(is_equal_approx(pet.feet.y, screen.end.y), "knight lands on the floor")

	waited = 0.0
	pet.climb(424242)
	while waited < 15.0 and not pet.is_perched():
		feed.call(Rect2(rect.position + Vector2(40, 30), rect.size))
		await get_tree().process_frame
		waited += get_process_delta_time()
	climb._on_clicked(Vector2i(rect.position + Vector2(40 + rect.size.x / 2, 40)))
	_check(not pet.is_perched() and pet.state == Pet.State.FALL, "clicking the title bar drops the knight")
	await _wait_until_idle()


func _wait_until_idle() -> void:
	var pet := app.pet
	var waited := 0.0
	while (pet._strike_pending or pet._striking or pet.state != Pet.State.IDLE) and waited < 8.0:
		await get_tree().process_frame
		waited += get_process_delta_time()


func _snapshot(viewport: Viewport, name: String, region := Rect2i()) -> void:
	var image := viewport.get_texture().get_image()
	if region.has_area():
		image = image.get_region(region)
	image.save_png(_out.path_join(name + ".png"))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
	_log(("PASS " if ok else "FAIL ") + what)


func _log(text: String) -> void:
	print("[selftest] ", text)
