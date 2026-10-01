// Anicon pointer bridge: sends the pointer position and button state to the Anicon
// knight as small UDP datagrams on 127.0.0.1, so it can follow the cursor and notice
// clicks even over native Wayland windows. Nothing leaves this computer.
//
// Datagrams (logical pixels):
//   "x y buttons"   pointer; buttons bit 1 = left, 2 = right, 4 = middle.
//   "W id,pid,x,y,w,h ..."   frame rects of the windows on the active workspace, topmost
//                    first, so the knight can climb them. Minimized, maximized and
//                    fullscreen windows are left out (there's no room on top of those).
// Sent when something changes (pointer polled ~60 times a second, windows ~10 times)
// and once a second as a heartbeat.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const PORT = 47391;
const POLL_MS = 16;
const HEARTBEAT_MS = 1000;
const WINDOWS_EVERY = 6;

export default class AniconPointerBridge extends Extension {
    enable() {
        this._socket = Gio.Socket.new(Gio.SocketFamily.IPV4, Gio.SocketType.DATAGRAM, Gio.SocketProtocol.UDP);
        this._address = Gio.InetSocketAddress.new_from_string('127.0.0.1', PORT);
        this._encoder = new TextEncoder();
        this._last = '';
        this._lastSent = 0;
        this._lastWindows = '';
        this._lastWindowsSent = 0;
        this._tick = 0;
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, POLL_MS, () => {
            this._poll();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        this._socket?.close();
        this._socket = null;
        this._address = null;
        this._encoder = null;
    }

    _poll() {
        this._pollPointer();
        if (++this._tick % WINDOWS_EVERY === 0)
            this._pollWindows();
    }

    _pollPointer() {
        const [x, y, mods] = global.get_pointer();
        let buttons = 0;
        if (mods & Clutter.ModifierType.BUTTON1_MASK)
            buttons |= 1;
        if (mods & Clutter.ModifierType.BUTTON3_MASK)
            buttons |= 2;
        if (mods & Clutter.ModifierType.BUTTON2_MASK)
            buttons |= 4;
        const message = `${x} ${y} ${buttons}`;
        const now = GLib.get_monotonic_time() / 1000;
        if (message === this._last && now - this._lastSent < HEARTBEAT_MS)
            return;
        this._last = message;
        this._lastSent = now;
        this._send(message);
    }

    _pollWindows() {
        const workspace = global.workspace_manager.get_active_workspace();
        const windows = global.display.sort_windows_by_stacking(
            workspace.list_windows().filter(w => this._climbable(w))).reverse();
        const message = ['W', ...windows.map(w => {
            const r = w.get_frame_rect();
            return `${w.get_id()},${w.get_pid()},${r.x},${r.y},${r.width},${r.height}`;
        })].join(' ');
        const now = GLib.get_monotonic_time() / 1000;
        if (message === this._lastWindows && now - this._lastWindowsSent < HEARTBEAT_MS)
            return;
        this._lastWindows = message;
        this._lastWindowsSent = now;
        this._send(message);
    }

    _climbable(w) {
        const type = w.get_window_type();
        return (type === Meta.WindowType.NORMAL || type === Meta.WindowType.DIALOG) &&
            !w.minimized && !w.fullscreen && !w.is_hidden() &&
            // GNOME 49 replaced get_maximized() with is_maximized().
            !(w.is_maximized ? w.is_maximized() : w.get_maximized() === Meta.MaximizeFlags.BOTH);
    }

    _send(message) {
        try {
            this._socket.send_to(this._address, this._encoder.encode(message), null);
        } catch (e) {
            // Nobody listening (Anicon isn't running) is fine.
        }
    }
}
