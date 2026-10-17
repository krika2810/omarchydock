//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland

// macOS-style dock: pinned apps, running indicators, hover magnification.
ShellRoot {
    id: root

    // Desktop-entry IDs (filename without .desktop). Edit to taste.
    // Default list; once you pin/unpin from the right-click menu it is stored in pinned.json.
    property var pinned: [
        "nautilus", "chromium", "com.mitchellh.ghostty", "cursor",
        "obsidian", "com.obsproject.Studio", "localsend"
    ]

    function togglePin(id) {
        const list = pinned.slice();
        const i = list.indexOf(id);
        if (i >= 0) list.splice(i, 1); else list.push(id);
        pinned = list;
        pinStore.setText(JSON.stringify(list));
    }

    FileView {
        id: pinStore
        path: Quickshell.env("HOME") + "/.config/quickshell/dock/pinned.json"
        printErrors: false
        onLoaded: {
            try {
                const v = JSON.parse(text());
                if (Array.isArray(v)) root.pinned = v;
            } catch (e) {}
        }
    }

    // Icon size; resized by dragging the handle on the dock's right edge, and persisted.
    property int baseSize: 48
    readonly property int minBase: 16
    readonly property int maxBase: 96
    readonly property int maxSize: Math.round(baseSize * 1.75)
    readonly property int spacing: Math.round(baseSize / 6)
    readonly property int pad: Math.round(baseSize / 5)
    readonly property real sigma: baseSize * 1.45

    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.config/quickshell/dock/size.txt"
        printErrors: false
        onLoaded: {
            const v = parseInt(text());
            if (v >= root.minBase && v <= root.maxBase) root.baseSize = v;
        }
    }

    // Auto-hide: the dock slides off-screen and reappears when the pointer touches the bottom edge.
    property bool autoHide: false

    function setAutoHide(v) {
        autoHide = v;
        hideStore.setText(v ? "1" : "0");
    }

    FileView {
        id: hideStore
        path: Quickshell.env("HOME") + "/.config/quickshell/dock/autohide.txt"
        printErrors: false
        onLoaded: root.autoHide = text().trim() === "1"
    }

    // qs ipc -p ~/.config/quickshell/dock/shell.qml call dock toggleAutoHide
    IpcHandler {
        target: "dock"
        function toggleAutoHide(): void { root.setAutoHide(!root.autoHide); }
        function setAutoHide(on: bool): void { root.setAutoHide(on); }
    }

    // Build model: pinned first, then running apps that aren't pinned.
    property var items: {
        const tops = ToplevelManager.toplevels.values;
        const used = new Set();
        const out = [];
        const matches = (entry, appId) => {
            const a = (appId || "").toLowerCase();
            return a !== "" && (entry.id.toLowerCase() === a
                || (entry.startupClass || "").toLowerCase() === a);
        };
        for (const id of pinned) {
            const e = DesktopEntries.byId(id);
            if (!e) continue;
            const wins = tops.filter((t, i) => { if (matches(e, t.appId)) { used.add(i); return true; } return false; });
            out.push({ key: id, entry: e, name: e.name, icon: e.icon, wins: wins, sep: false, pinned: true });
        }
        const extra = [];
        tops.forEach((t, i) => {
            if (used.has(i)) return;
            const e = DesktopEntries.heuristicLookup(t.appId);
            const key = e ? e.id : t.appId;
            let g = extra.find(x => x.key === key);
            if (!g) {
                g = { key: key, entry: e, name: e ? e.name : t.appId, icon: e ? e.icon : t.appId, wins: [], sep: false, pinned: false };
                extra.push(g);
            }
            g.wins.push(t);
        });
        if (extra.length > 0 && out.length > 0) extra[0].sep = true;
        return out.concat(extra);
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            // Fixed at the largest possible dock so resizing never resizes the window.
            implicitHeight: Math.round(root.maxBase * 1.75) + 60
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "dock"
            color: "transparent"

            // Auto-hide state. `shown` lags hover by a short delay so brushing past the edge doesn't flicker.
            property bool shown: true
            property real slide: (!root.autoHide || shown) ? 1 : 0
            Behavior on slide {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            function updateShown() {
                if (!root.autoHide || hov.hovered || menu.visible) {
                    hideTimer.stop();
                    shown = true;
                } else {
                    hideTimer.restart();
                }
            }
            Timer {
                id: hideTimer
                interval: 350
                onTriggered: win.shown = false
            }
            Connections {
                target: root
                function onAutoHideChanged() { win.updateShown(); }
            }

            // Only the dock strip receives input; the rest of the window is click-through.
            mask: Region { item: hit }

            readonly property real baseTotal: root.items.length * (root.baseSize + root.spacing) - root.spacing + root.pad * 2
            readonly property real baseLeft: (width - baseTotal) / 2

            // Magnified size of each icon, from its position in the unmagnified layout.
            // 0..1 magnification strength; eases in quickly on enter and out slowly on leave.
            property real mag: hov.hovered ? 1 : 0
            Behavior on mag {
                NumberAnimation { duration: hov.hovered ? 100 : 300; easing.type: Easing.OutCubic }
            }

            readonly property var sizes: {
                const n = root.items.length, step = root.baseSize + root.spacing;
                const out = [];
                for (let i = 0; i < n; i++) {
                    const c = baseLeft + root.pad + i * step + root.baseSize / 2;
                    const d = area.mx - c;
                    out.push(root.baseSize + (root.maxSize - root.baseSize) * mag * Math.exp(-(d * d) / (2 * root.sigma * root.sigma)));
                }
                return out;
            }
            readonly property real total: sizes.reduce((a, s) => a + s, 0) + Math.max(0, sizes.length - 1) * root.spacing

            // Keep the point under the cursor fixed (in unmagnified coordinates) so icons spread
            // outward from it instead of sliding sideways.
            readonly property real rowX: {
                if (mag <= 0 || sizes.length === 0) return (width - total) / 2;
                const n = sizes.length, step = root.baseSize + root.spacing;
                const u = (area.mx - baseLeft - root.pad) / step;
                let p;
                if (u <= 0) p = u * step;
                else if (u >= n) p = total + (u - n) * step;
                else {
                    const idx = Math.floor(u), frac = u - idx;
                    p = 0;
                    for (let j = 0; j < idx; j++) p += sizes[j] + root.spacing;
                    p += frac * (sizes[idx] + root.spacing);
                }
                return area.mx - p;
            }

            Item {
                id: hit
                width: win.baseTotal + root.maxSize
                // While hidden, only a thin strip at the bottom edge is live, to reveal the dock.
                height: win.slide > 0.01 ? root.maxSize + 40 : 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
            }

            // HoverHandler isn't blocked by the icons' own MouseAreas, so hover stays stable.
            Item {
                id: area
                property real mx: -10000
                readonly property bool containsMouse: hov.hovered
                // Parented to the window root so it keeps receiving hover while the pointer is
                // over child items (icon mouse areas, tooltips, the grip) instead of dropping out.
                HoverHandler {
                    id: hov
                    parent: win.contentItem
                    onPointChanged: area.mx = point.position.x
                    onHoveredChanged: win.updateShown()
                }
            }

            // ---- Right-click context menu ----
            property var menuData: null

            function openMenu(cellItem, d) {
                menuData = d;
                menu.anchor.item = cellItem;
                menu.visible = true;
            }

            readonly property var menuEntries: {
                const d = menuData, out = [];
                if (!d) return out;
                if (d.entry) {
                    out.push({ label: d.wins.length > 0 ? "New Window" : "Open", run: () => d.entry.execute() });
                    for (const a of d.entry.actions) out.push({ label: a.name, run: () => a.execute() });
                }
                if (d.wins.length > 0)
                    out.push({ label: d.wins.length > 1 ? "Close All Windows" : "Close", run: () => d.wins.forEach(w => w.close()) });
                if (d.entry) {
                    const isPinned = root.pinned.includes(d.entry.id);
                    out.push({ label: isPinned ? "Remove from Dock" : "Keep in Dock", run: () => root.togglePin(d.entry.id) });
                }
                out.push({ label: root.autoHide ? "Always Show Dock" : "Hide Dock Automatically", run: () => root.setAutoHide(!root.autoHide) });
                return out;
            }

            PopupWindow {
                id: menu
                visible: false
                onVisibleChanged: win.updateShown()
                color: "transparent"
                anchor.edges: Edges.Top
                anchor.gravity: Edges.Top
                anchor.rect.y: -((root.maxSize - root.baseSize) / 2) - 8
                implicitWidth: 210
                implicitHeight: menuCol.implicitHeight + 12

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: Qt.rgba(0.12, 0.12, 0.14, 0.92)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)

                    Column {
                        id: menuCol
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2

                        Text {
                            width: parent.width
                            leftPadding: 8
                            topPadding: 2
                            bottomPadding: 4
                            elide: Text.ElideRight
                            text: win.menuData ? win.menuData.name : ""
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: 11
                        }

                        Repeater {
                            model: win.menuEntries
                            delegate: Rectangle {
                                required property var modelData
                                width: menuCol.width
                                height: 28
                                radius: 8
                                color: item.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    text: parent.modelData.label
                                    color: "white"
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    id: item
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    // Close first: some actions (pin, auto-hide) rebuild the entries and
                                    // destroy this row, which would otherwise skip the close.
                                    onClicked: { const run = parent.modelData.run; menu.visible = false; run(); }
                                }
                            }
                        }
                    }
                }
            }

            HyprlandFocusGrab {
                windows: [menu]
                active: menu.visible
                onCleared: menu.visible = false
            }

            // Frosted pill background
            Rectangle {
                id: pill
                x: win.rowX - root.pad
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8 - (1 - win.slide) * (height + 12)
                height: root.baseSize + root.pad * 2
                width: win.total + root.pad * 2
                radius: 20
                color: Qt.rgba(0.12, 0.12, 0.14, 0.55)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)
            }

            // Resize handle on the dock's right edge: drag up/down to change icon size (like macOS).
            MouseArea {
                id: grip
                x: pill.x + pill.width - 5
                y: pill.y
                width: 12
                height: pill.height
                hoverEnabled: true
                cursorShape: Qt.SizeVerCursor
                property real startY: 0
                property int startSize: 0
                // Global y keeps the measurement independent of the dock resizing under the cursor.
                function globalY(m) { return mapToItem(win.contentItem, m.x, m.y).y; }
                onPressed: m => { startY = globalY(m); startSize = root.baseSize; }
                onPositionChanged: m => {
                    if (!pressed) return;
                    const v = Math.round(startSize + (startY - globalY(m)) * 0.6);
                    root.baseSize = Math.max(root.minBase, Math.min(root.maxBase, v));
                }
                onReleased: store.setText(String(root.baseSize))

                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    height: parent.height * 0.5
                    radius: 1
                    color: "white"
                    opacity: grip.pressed ? 0.7 : grip.containsMouse ? 0.45 : 0.15
                }
            }

            Row {
                id: row
                x: win.rowX
                anchors.bottom: pill.bottom
                anchors.bottomMargin: root.pad
                spacing: root.spacing

                Repeater {
                    model: root.items
                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index

                        readonly property real size: win.sizes[index] ?? root.baseSize
                        property real bounce: 0

                        width: size
                        height: root.baseSize

                        IconImage {
                            id: icon
                            width: cell.size
                            height: cell.size
                            y: root.baseSize - cell.size - cell.bounce
                            source: Quickshell.iconPath(cell.modelData.icon, "application-x-executable")
                            asynchronous: true
                        }

                        // Running indicator
                        Rectangle {
                            visible: cell.modelData.wins.length > 0
                            width: 4; height: 4; radius: 2
                            color: "white"; opacity: 0.85
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: root.baseSize + 2
                        }

                        // Tooltip
                        Rectangle {
                            visible: ma.containsMouse
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: -root.maxSize + root.baseSize - 34
                            width: label.implicitWidth + 16; height: 24; radius: 8
                            color: Qt.rgba(0.1, 0.1, 0.12, 0.9)
                            Text {
                                id: label
                                anchors.centerIn: parent
                                text: cell.modelData.name
                                color: "white"; font.pixelSize: 12
                            }
                        }

                        SequentialAnimation {
                            id: bounceAnim
                            NumberAnimation { target: cell; property: "bounce"; to: 18; duration: 160; easing.type: Easing.OutQuad }
                            NumberAnimation { target: cell; property: "bounce"; to: 0; duration: 220; easing.type: Easing.OutBounce }
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            onClicked: mouse => {
                                const d = cell.modelData;
                                if (mouse.button === Qt.RightButton) {
                                    win.openMenu(cell, d);
                                } else if (mouse.button === Qt.LeftButton && d.wins.length > 0) {
                                    d.wins[0].activate();
                                } else if (d.entry) {
                                    bounceAnim.start();
                                    d.entry.execute();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
