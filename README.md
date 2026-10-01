# Anicon

A tiny pixel knight that lives on your desktop. It wanders along the bottom of the
screen, naps when you're away, can be dragged and thrown, chats through a local LLM
(Ollama), and has a few handy skills.

Built with Godot 4.7 (GDScript). Runs on Linux, Windows and macOS.

## Turn it on and off

```sh
anicon start     # the knight drops in
anicon stop      # and leaves
anicon toggle    # on if off, off if on
anicon status    # running or not (exit code 0 / 3)
anicon restart
anicon log       # last lines of its log
anicon setup     # GNOME only, once: lets the knight see your cursor and clicks
```

`anicon start` also starts Ollama if it's installed but not running (and downloads the
chat model in the background if it's missing), and `anicon stop` shuts down only an
Ollama it started. `bin/anicon` works on Linux and macOS. Put it on your PATH with
`ln -s "$PWD/bin/anicon" ~/.local/bin/anicon`. It runs the exported build from `build/`
if there is one, otherwise the project through Godot (`ANICON_GODOT` picks the binary).
You can also run it in the foreground with `godot --path .`.

For chat, install [Ollama](https://ollama.com) and pull the default model:

```sh
curl -fsSL https://ollama.com/install.sh | sh   # or: sudo dnf install ollama
ollama pull llama3.2:3b
```

## Using the knight

| Do this | And the knight... |
| --- | --- |
| Click | swings its sword |
| Drag and let go | gets thrown, bounces and rolls |
| Double-click | opens a chat bubble (Enter to send, Esc to close) |
| Right-click | opens the menu: chat, skills, settings, hide, quit |
| Leave the computer | falls asleep behind its shield, wakes when you're back |
| Put a window behind it | walks to the window's side, climbs up and wanders along the title bar |
| Click that title bar, or move/close the window | falls back down |

The knight never talks on its own. It only speaks in answer to something you did:
a chat, a skill from the menu, or a reminder you set.

### Skills (right-click menu)

- **Chase my clicks** (on by default): click fast three times anywhere and the knight
  runs after your cursor and slashes it, for a few seconds after your latest click;
  keep clicking to keep it chasing. Your apps still get the clicks as usual.
- **Guard instinct** (on by default): rest the cursor near the knight and it raises its
  shield, creeps closer and slashes. It gives up if the cursor leaves.
- **Climb windows** (on by default): when a window sits behind the knight for a moment,
  it climbs onto the window's title bar and wanders there. Click the title bar, or move,
  resize, minimize or close the window, and it falls off. Maximized and fullscreen
  windows have no room on top, so it leaves those alone.
- **Battle mode!** Click anywhere on the screen; the knight runs or leaps over and
  slashes your cursor. Keep clicking for combos. Esc ends it. While it's on, the
  screen is an arena, so other apps can't be clicked.
- **Reminders**: `10m stretch`, `1h30m call mom`, `at 14:30 standup`, `25 pizza`
  (plain number = minutes). They survive restarts.
- **Launch**: apps and URLs from Settings, one per line as `Name = command or URL`.
- **How's my computer?**: CPU, RAM and battery. When the CPU stays above 85% the
  knight looks flustered (silently; can be turned off).
- **Clipboard**: count words, tidy whitespace, change case, or summarize with the LLM.

Add a skill by dropping a `something_skill.gd` that `extends Skill` into
`scripts/skills/`; it appears in the menu automatically. See `scripts/skills/skill.gd`.

## Notes

- The knight's window is a transparent, click-through layer over the screen it's on;
  only the knight itself catches the mouse. Moving the sprite inside a still window is
  much smoother than moving a small window around.
- GNOME on Wayland doesn't let X11 apps see the cursor or clicks outside their own
  windows, or other apps' windows, so chasing clicks, guard instinct and climbing
  windows there need the small bundled extension in `extras/gnome-extension/`.
  `anicon setup` installs it; log out and back in once (and again after the extension
  changes). It only sends the pointer position, button state and window rectangles to
  127.0.0.1 (UDP port 47391).
- On Linux the game runs through XWayland (`display_server/driver.linuxbsd="x11"`),
  because native Wayland doesn't let apps place their own windows or stay on top.
  On GNOME, sleep detection uses Mutter's idle monitor, since X11 apps can't see the
  mouse over Wayland windows.
- Settings, chat history and reminders live in Godot's `user://` folder
  (`~/.local/share/godot/app_userdata/Anicon/` on Linux).
- Smoke test: `godot --path . -- --selftest build/selftest` (logs checks, saves window
  snapshots). Don't click on the screen while it runs battle mode.
- Exporting needs Godot's export templates (Editor → Manage Export Templates); presets
  for Linux, Windows and macOS are in `export_presets.cfg`.

## Credits

Knight sprites: "Knight Hero Platformer Animation Pack" by PixiVan, CC0
(see `assets/sprites/royal_knight/CREDITS.md`).
