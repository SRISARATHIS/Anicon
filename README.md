# Anicon

A tiny pixel knight that lives on your desktop. It wanders along the bottom of the
screen, naps when you're away, can be dragged and thrown, chats through a local LLM
(Ollama), and has a few handy skills.

Built with Godot 4.7 (GDScript). Runs on Linux, Windows and macOS.

## Setup

### Linux

1. **Install Godot 4.7** (the standard build, not .NET). Download it from
   [godotengine.org/download](https://godotengine.org/download), unzip it, and put the
   binary on your PATH as `godot`:

   ```sh
   mkdir -p ~/.local/bin
   mv ~/Downloads/Godot_v4.7*_linux.x86_64 ~/.local/bin/godot
   chmod +x ~/.local/bin/godot
   godot --version            # should print 4.7.x
   ```

   If `godot --version` says "command not found", add `~/.local/bin` to your PATH
   (`echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`, then open a new terminal).

2. **Download Anicon:**

   ```sh
   git clone https://github.com/SRISARATHIS/Anicon.git
   cd Anicon
   ```

3. **Import the sprites** (once, and again after pulling new art). This takes a few seconds:

   ```sh
   godot --headless --path . --import
   ```

4. **Install the `anicon` command:**

   ```sh
   ln -s "$PWD/bin/anicon" ~/.local/bin/anicon
   ```

5. **Optional: set up chat.** Install [Ollama](https://ollama.com). You can skip this
   step; everything except chat and the clipboard summary works without it.

   ```sh
   curl -fsSL https://ollama.com/install.sh | sh   # or: sudo dnf install ollama
   ```

   You don't need to download a model yourself: `anicon start` pulls `llama3.2:3b`
   (about 2 GB) in the background the first time.

6. **GNOME on Wayland only:** let the knight see your cursor and other windows (needed
   for chasing clicks, guard instinct and climbing windows):

   ```sh
   anicon setup
   ```

   Then **log out and back in** once. Skip this on X11, KDE and other desktops.
   Not sure which you have? Run `echo $XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP`.

7. **Start it:**

   ```sh
   anicon start
   ```

   The knight drops onto the bottom of your screen. `anicon status` checks that
   everything is running, and `anicon log` shows what went wrong if it doesn't appear.

### macOS

1. Install Godot 4.7 from [godotengine.org/download](https://godotengine.org/download)
   and drag `Godot.app` into Applications.
2. Download and import:

   ```sh
   git clone https://github.com/SRISARATHIS/Anicon.git
   cd Anicon
   export ANICON_GODOT=/Applications/Godot.app/Contents/MacOS/Godot
   "$ANICON_GODOT" --headless --path . --import
   ```

   Add the `export ANICON_GODOT=...` line to `~/.zshrc` so it's set in new terminals.
3. Install the command: `mkdir -p ~/.local/bin && ln -s "$PWD/bin/anicon" ~/.local/bin/anicon`
   (make sure `~/.local/bin` is on your PATH).
4. Optional chat: install Ollama from [ollama.com/download](https://ollama.com/download).
5. Start it: `anicon start`. The first time, macOS may ask for permission to allow
   Godot to run; allow it in System Settings → Privacy & Security.

### Windows

The `anicon` command is Linux/macOS only; on Windows you run Godot directly.

1. Install Godot 4.7 from [godotengine.org/download](https://godotengine.org/download)
   and unzip it, for example to `C:\Godot\godot.exe`.
2. Install [Git](https://git-scm.com/download/win), then in PowerShell:

   ```powershell
   git clone https://github.com/SRISARATHIS/Anicon.git
   cd Anicon
   C:\Godot\godot.exe --headless --path . --import
   ```

3. Optional chat: install Ollama from [ollama.com/download](https://ollama.com/download),
   then run `ollama pull llama3.2:3b` once.
4. Start it: `C:\Godot\godot.exe --path .` (close it from the knight's right-click menu → Quit).

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
Ollama it started. It runs the exported build from `build/` if there is one, otherwise
the project through Godot (`ANICON_GODOT` picks the binary). You can also run it in the
foreground with `godot --path .`.

To update later: `anicon stop`, `git pull`, `godot --headless --path . --import`, `anicon start`.

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
