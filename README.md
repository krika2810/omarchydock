# omarchydock

![omarchydock demo: hover magnification, drag to resize, auto-hide](docs/demo.gif)

[Full-quality video](docs/demo.mp4) · [Screenshot](docs/screenshot.png)

A macOS-style dock for [Omarchy](https://omarchy.org) / Hyprland, built with [Quickshell](https://quickshell.org).

## Features
- Pinned apps plus running apps, with a dot under running ones
- Smooth hover magnification
- Click to focus or launch, with a launch bounce
- Right-click menu: New Window, app actions, Close, Keep in / Remove from Dock
- Drag the handle on the dock's right edge up/down to resize icons (persisted)
- Optional auto-hide: right-click → "Hide Dock Automatically"; touch the bottom edge to reveal (persisted)
- Frosted pill look, click-through everywhere except the dock

## Install
```bash
git clone https://github.com/krika2810/omarchydock
cd omarchydock
./install.sh
quickshell -p ~/.config/quickshell/dock/shell.qml
```

Autostart on Hyprland (`~/.config/hypr/autostart.conf`):
```
exec-once = quickshell -p ~/.config/quickshell/dock/shell.qml
```

## Configure
Pins are stored in `~/.config/quickshell/dock/pinned.json` as desktop-entry IDs
(the `.desktop` filename without the extension). Edit it or use the right-click menu.

## Auto-hide
Toggle from the right-click menu, or bind a key in Hyprland:
```
bind = SUPER ALT, D, exec, qs ipc -p ~/.config/quickshell/dock/shell.qml call dock toggleAutoHide
```

## Requirements
Quickshell (included with Omarchy), Hyprland.

## License
MIT
