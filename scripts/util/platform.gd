class_name Platform
## Per-OS helpers: screens, CPU, idle time, battery, notifications and autostart.
## Functions marked "Blocking" may take a while; run them with `await Platform.threaded(...)`.

static var _idle_supported := true


## Runs `fn` on a worker thread and returns its result without blocking the game loop.
static func threaded(fn: Callable) -> Variant:
	var thread := Thread.new()
	thread.start(fn)
	var tree := Engine.get_main_loop() as SceneTree
	while thread.is_alive():
		await tree.process_frame
	return thread.wait_to_finish()


## Index of the screen containing `point`, or the closest one.
static func screen_at(point: Vector2) -> int:
	var best := DisplayServer.get_primary_screen()
	var best_distance := INF
	for i in DisplayServer.get_screen_count():
		var rect := Rect2(DisplayServer.screen_get_usable_rect(i))
		if rect.has_point(point):
			return i
		var closest := point.clamp(rect.position, rect.end)
		if closest.distance_to(point) < best_distance:
			best = i
			best_distance = closest.distance_to(point)
	return best


## Blocking. Total CPU usage in percent, or -1 if unknown.
static func cpu_percent() -> float:
	var out := []
	match OS.get_name():
		"Linux":
			var a := _proc_stat()
			OS.delay_msec(300)
			var b := _proc_stat()
			if a.is_empty() or b.is_empty() or b[0] <= a[0]:
				return -1.0
			return 100.0 * (1.0 - float(b[1] - a[1]) / float(b[0] - a[0]))
		"Windows":
			var command := "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average"
			if OS.execute("powershell", ["-NoProfile", "-Command", command], out) == 0:
				var value := String(out[0]).strip_edges()
				if value.is_valid_float():
					return value.to_float()
		"macOS":
			if OS.execute("ps", ["-A", "-o", "%cpu"], out) == 0:
				var total := 0.0
				for line in String(out[0]).split("\n"):
					if line.strip_edges().is_valid_float():
						total += line.strip_edges().to_float()
				return minf(total / OS.get_processor_count(), 100.0)
	return -1.0


## Blocking. Seconds since the user last touched mouse or keyboard, or -1 if the OS
## can't tell us (the pet then falls back to watching the mouse itself).
static func idle_seconds() -> float:
	if not _idle_supported or OS.get_name() != "Linux":
		return -1.0
	# GNOME's idle monitor also works on Wayland, where X11 apps can't see the global mouse.
	var out := []
	var args := ["call", "--session", "--dest", "org.gnome.Mutter.IdleMonitor",
		"--object-path", "/org/gnome/Mutter/IdleMonitor/Core",
		"--method", "org.gnome.Mutter.IdleMonitor.GetIdletime"]
	if OS.execute("gdbus", args, out) == 0:
		var found := RegEx.create_from_string("uint64 (\\d+)").search(String(out[0]))
		if found:
			return found.get_string(1).to_float() / 1000.0
	_idle_supported = false
	return -1.0


## [used, total] physical memory in bytes, or [] if unknown.
static func memory_bytes() -> Array:
	if OS.get_name() == "Linux" and FileAccess.file_exists("/proc/meminfo"):
		# Godot's "available" includes swap on Linux, so read the kernel's own estimate.
		var info := {}
		for line in FileAccess.get_file_as_string("/proc/meminfo").split("\n", false):
			var parts := line.split(":")
			info[parts[0]] = parts[1].to_int() * 1024
		if info.has("MemTotal") and info.has("MemAvailable"):
			return [info.MemTotal - info.MemAvailable, info.MemTotal]
	var memory := OS.get_memory_info()
	if memory.physical <= 0:
		return []
	var free: int = memory.available if memory.available >= 0 else memory.free
	return [memory.physical - free, memory.physical]


## Battery charge in percent, or -1 if there is no battery or we can't read it.
static func battery_percent() -> int:
	if OS.get_name() == "Linux":
		for battery in ["BAT0", "BAT1", "BAT"]:
			var path := "/sys/class/power_supply/%s/capacity" % battery
			if FileAccess.file_exists(path):
				return FileAccess.get_file_as_string(path).strip_edges().to_int()
	return -1


## Shows a desktop notification where it's easy to do so (Linux, macOS).
static func notify(title: String, body: String) -> void:
	match OS.get_name():
		"Linux":
			OS.create_process("notify-send", ["--app-name=Anicon", title, body])
		"macOS":
			var script := "display notification %s with title %s" % [_apple_quote(body), _apple_quote(title)]
			OS.create_process("osascript", ["-e", script])


## Starts Anicon at login (or stops doing so).
static func set_autostart(enabled: bool) -> void:
	var command := PackedStringArray([OS.get_executable_path()])
	if not OS.has_feature("template"):
		# Running from source: the executable is Godot itself, so point it at the project.
		command.append_array(["--path", ProjectSettings.globalize_path("res://")])
	var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	match OS.get_name():
		"Linux":
			var path := home.path_join(".config/autostart/anicon.desktop")
			if enabled:
				DirAccess.make_dir_recursive_absolute(path.get_base_dir())
				var quoted := PackedStringArray()
				for part in command:
					quoted.append("\"%s\"" % part if " " in part else part)
				var file := FileAccess.open(path, FileAccess.WRITE)
				file.store_string("[Desktop Entry]\nType=Application\nName=Anicon\nComment=A tiny pixel knight on your desktop\nExec=%s\nX-GNOME-Autostart-enabled=true\n" % " ".join(quoted))
			elif FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		"Windows":
			var key := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
			if enabled:
				var quoted := PackedStringArray()
				for part in command:
					quoted.append("\"%s\"" % part)
				OS.execute("reg", ["add", key, "/v", "Anicon", "/t", "REG_SZ", "/d", " ".join(quoted), "/f"])
			else:
				OS.execute("reg", ["delete", key, "/v", "Anicon", "/f"])
		"macOS":
			var path := home.path_join("Library/LaunchAgents/com.anicon.pet.plist")
			if enabled:
				var items := ""
				for part in command:
					items += "\t\t<string>%s</string>\n" % part.xml_escape()
				var file := FileAccess.open(path, FileAccess.WRITE)
				file.store_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>Label</key>\n\t<string>com.anicon.pet</string>\n\t<key>ProgramArguments</key>\n\t<array>\n%s\t</array>\n\t<key>RunAtLoad</key>\n\t<true/>\n</dict>\n</plist>\n" % items)
			elif FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


## [total, idle] jiffies from the first line of /proc/stat.
static func _proc_stat() -> Array:
	var file := FileAccess.open("/proc/stat", FileAccess.READ)
	if file == null:
		return []
	var fields := file.get_line().split(" ", false)
	var total := 0
	for i in range(1, fields.size()):
		total += fields[i].to_int()
	return [total, fields[4].to_int() + fields[5].to_int()]


static func _apple_quote(text: String) -> String:
	return "\"%s\"" % text.replace("\\", "\\\\").replace("\"", "\\\"")
