// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SCREENSHOT — what hyprshot.lua did, in picasso, and one thing it could
// not: a region you can still change your mind about.
//
//   screen   the monitor you are on, whole
//   window   the window that has the keyboard
//   region   a rectangle you draw, then ADJUST — slurp captured the moment
//            the button came up, so a box a few pixels off was a box you
//            drew again. Here it stays up with handles until you press Save
//            (or Return), and Abort (or Escape) walks away.
//
// Every one of them is saved to ~/Pictures/Screenshots (XDG's pictures
// directory, as picasso finds it), copied to the clipboard, and announced by
// a toast. CLICKING THAT TOAST is what opens the annotation window — it
// never opens by itself, so a screenshot taken to paste somewhere costs
// nothing more than it did.
//
// THE REGION IS DRAWN OVER THE LIVE SCREEN, and only the rectangle is ever
// captured. It used to freeze the monitor first — a full-resolution PNG
// written to disk before the overlay could even appear, which is what made
// region mode slow to start. Now the overlay opens at once, and Save puts it
// away and asks grim for exactly the rectangle, so the box's own outline is
// never in the shot.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../morpheus"
import "capture.js" as Cap

Scope {
  id: cap

  property bool busy: false
  // the region session: which screen it is on
  property var regionScreen: null
  property var monitor: null
  property string pendingGeo: ""
  property var wins: []


  Connections {
    target: Picasso
    // asked again while a region is up: that is "never mind"
    function onShotRequested(mode) {
      if (region.active) { region.finish(false); return; }
      cap.shoot(mode);
    }
  }

  function focusedScreen() {
    const m = Hyprland.focusedMonitor;
    if (m) for (const s of Quickshell.screens) if (s.name === m.name) return s;
    return Quickshell.screens.length ? Quickshell.screens[0] : null;
  }

  function sh(s) { return Strings.shellQuote(s); }

  // ── asking hyprland where things are ──────────────────────────────────
  // monitors and clients as JSON, read here rather than through jq (which
  // this machine does not have — the old window mode silently depended on it).
  property string wantMode: ""
  Process {
    id: askProc
    command: ["sh", "-c", "hyprctl -j monitors; echo '@@'; hyprctl -j clients; echo '@@'; hyprctl -j activewindow"]
    stdout: StdioCollector {
      id: askOut
      onStreamFinished: cap.answered(String(askOut.text || ""))
    }
  }

  function shoot(mode) {
    if (cap.busy) return;
    cap.busy = true;
    cap.wantMode = mode;
    askProc.running = true;
  }

  function answered(text) {
    const parts = text.split("@@");
    let mons = [], clients = [], active = null;
    try { mons = JSON.parse(parts[0]); } catch (e) {}
    try { clients = JSON.parse(parts[1]); } catch (e) {}
    try { active = JSON.parse(parts[2]); } catch (e) {}
    const scr = cap.focusedScreen();
    const mon = mons.find(m => m.focused) || mons.find(m => scr && m.name === scr.name);
    if (!mon || !scr) { cap.busy = false; return; }
    const file = Picasso.shotDir + "/" + Cap.fileName(new Date(), cap.wantMode, mon.name);

    if (cap.wantMode === "screen") {
      cap.run("mkdir -p " + cap.sh(Picasso.shotDir) + " && grim -o " + cap.sh(mon.name)
              + " " + cap.sh(file), file);
      return;
    }
    if (cap.wantMode === "window") {
      if (!active || !active.at || !active.size) { cap.busy = false; return; }
      const g = active.at[0] + "," + active.at[1] + " " + active.size[0] + "x" + active.size[1];
      cap.run("mkdir -p " + cap.sh(Picasso.shotDir) + " && grim -g " + cap.sh(g)
              + " " + cap.sh(file), file);
      return;
    }
    // region: straight to the overlay — nothing is captured until Save
    const ws = [mon.activeWorkspace ? mon.activeWorkspace.id : -1,
                mon.specialWorkspace ? mon.specialWorkspace.id : -1];
    cap.wins = Cap.windowsOn(clients, mon, ws);
    cap.monitor = mon;
    region.target = file;
    cap.regionScreen = scr;
    region.begin();
  }

  // The capture itself, then the part every mode shares.
  //
  // WITH THE POINTER OUT OF THE PICTURE. This machine draws its cursor in
  // software, into the frame itself, so grim cannot leave it out — every
  // window shot had the arrow sitting in it. For the moment of the capture
  // a transparent surface covers the monitor with the pointer hidden over
  // it (see `hider`), and the capture waits a beat for that to land.
  function run(cmd, file) {
    shotProc.file = file;
    shotProc.command = ["sh", "-c", cmd];
    hider.screen = cap.focusedScreen();
    hider.visible = true;
    hideLater.restart();
  }

  Timer {
    id: hideLater
    interval: 140
    onTriggered: shotProc.running = true
  }

  Process {
    id: shotProc
    property string file: ""
    onExited: (code) => {
      hider.visible = false;
      cap.busy = false;
      if (code === 0) cap.announce(shotProc.file);
    }
  }

  PanelWindow {
    id: hider
    visible: false
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "picasso-hider"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.BlankCursor
    }
  }

  // Clipboard, and the toast. -w and a default action, the way ceres' update
  // toast does it: howler invokes `default` on a left click and notify-send
  // prints its name, so the click is heard by the shell this spawned — which
  // then asks picasso for the annotation window. Detached, so any number of
  // screenshots can each be waiting on their own toast.
  function announce(file) {
    const name = file.split("/").pop();
    Quickshell.execDetached(["sh", "-c",
      "wl-copy --type image/png < " + cap.sh(file) + "; "
      + "a=$(notify-send -a picasso -i " + cap.sh(file) + " -w -A default=Annotate "
      + cap.sh("Screenshot saved") + " " + cap.sh(name + " · copied · click to annotate") + "); "
      + "[ \"$a\" = default ] && qs ipc call Picasso annotate " + cap.sh(file)]);
  }

  // ── the region ────────────────────────────────────────────────────────
  PanelWindow {
    id: region
    property string target: ""
    property bool active: false
    // the selection, in this screen's coordinates; w = 0 is none yet
    property var sel: ({ x: 0, y: 0, w: 0, h: 0 })
    readonly property bool has: region.sel.w > 2 && region.sel.h > 2
    // the window under the pointer before anything is drawn — a click
    // without a drag takes it whole
    property var hoverWin: null
    // the output's scale, so the size label reads in real pixels
    readonly property real dpr: cap.monitor && cap.monitor.scale ? cap.monitor.scale : 1

    screen: cap.regionScreen
    visible: region.active
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "picasso-region"
    WlrLayershell.keyboardFocus: region.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    function begin() {
      region.sel = { x: 0, y: 0, w: 0, h: 0 };
      region.hoverWin = null;
      region.active = true;
      keys.forceActiveFocus();
      claim.restart();
    }

    function finish(save) {
      const s = region.sel;
      region.active = false;
      if (!save || !region.has) { cap.busy = false; return; }
      // In the layout's coordinates, which is what grim -g takes: the
      // monitor's own origin plus the box.
      const m = cap.monitor;
      cap.pendingGeo = (m.x + s.x) + "," + (m.y + s.y) + " " + s.w + "x" + s.h;
      // after the overlay has left the screen (run() waits a beat for the
      // pointer anyway, which is also long enough for that)
      cap.run("mkdir -p " + cap.sh(Picasso.shotDir) + " && grim -g "
        + cap.sh(cap.pendingGeo) + " " + cap.sh(region.target), region.target);
    }

    // the keyboard, asked for until it is given — a layer's first frame
    // drops a focus request
    Timer {
      id: claim
      interval: 30
      repeat: true
      property int n: 0
      onTriggered: {
        if (!region.active || keys.activeFocus || claim.n++ > 15) { claim.stop(); claim.n = 0; return; }
        keys.forceActiveFocus();
      }
    }

    // ── the dim, everywhere but the selection ─────────────────────────
    readonly property color shade: Qt.rgba(0, 0, 0, 0.45)
    readonly property var lit: region.has ? region.sel
      : (region.hoverWin ? region.hoverWin : null)
    Rectangle { color: region.shade; x: 0; y: 0; width: parent.width
      height: region.lit ? region.lit.y : parent.height }
    Rectangle { color: region.shade; visible: !!region.lit; x: 0
      y: region.lit ? region.lit.y + region.lit.h : 0; width: parent.width
      height: region.lit ? parent.height - (region.lit.y + region.lit.h) : 0 }
    Rectangle { color: region.shade; visible: !!region.lit; x: 0
      y: region.lit ? region.lit.y : 0; width: region.lit ? region.lit.x : 0
      height: region.lit ? region.lit.h : 0 }
    Rectangle { color: region.shade; visible: !!region.lit
      x: region.lit ? region.lit.x + region.lit.w : 0; y: region.lit ? region.lit.y : 0
      width: region.lit ? parent.width - (region.lit.x + region.lit.w) : 0
      height: region.lit ? region.lit.h : 0 }

    // the outline: solid for a selection, dashed-looking thin for a window
    // that would be taken if you clicked
    Rectangle {
      visible: !!region.lit
      x: region.lit ? region.lit.x - 1 : 0
      y: region.lit ? region.lit.y - 1 : 0
      width: region.lit ? region.lit.w + 2 : 0
      height: region.lit ? region.lit.h + 2 : 0
      color: "transparent"
      border.width: region.has ? 2 : 1
      border.color: region.has ? Zenon.cyan : Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.6)
    }

    // ── the handles ───────────────────────────────────────────────────
    Repeater {
      model: region.has ? ["tl", "t", "tr", "r", "br", "b", "bl", "l"] : []
      delegate: Rectangle {
        required property string modelData
        readonly property real hx: modelData.indexOf("l") >= 0 ? region.sel.x
          : modelData.indexOf("r") >= 0 ? region.sel.x + region.sel.w : region.sel.x + region.sel.w / 2
        readonly property real hy: modelData.indexOf("t") >= 0 ? region.sel.y
          : modelData.indexOf("b") >= 0 ? region.sel.y + region.sel.h : region.sel.y + region.sel.h / 2
        x: hx - 5
        y: hy - 5
        width: 10
        height: 10
        radius: 2
        color: Zenon.white
        border.width: 1
        border.color: Zenon.cyan
      }
    }

    // the size, where you are looking
    Rectangle {
      visible: region.has
      x: region.sel.x
      y: region.sel.y >= 30 ? region.sel.y - 28 : region.sel.y + 6
      width: sizeText.implicitWidth + 16
      height: 22
      radius: Zenon.windowRadius
      color: Zenon.menuBgSolid
      border.width: 1
      border.color: Zenon.border
      Text {
        id: sizeText
        anchors.centerIn: parent
        text: Math.round(region.sel.w * region.dpr) + " × " + Math.round(region.sel.h * region.dpr)
        color: Zenon.white
        font.family: Zenon.faceMono
        font.pixelSize: 13
      }
    }

    // ── the pointer ───────────────────────────────────────────────────
    MouseArea {
      id: ptr
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: ptr.grab === "move" ? Qt.ClosedHandCursor
        : ptr.grab !== "" && ptr.grab !== "new" ? Qt.SizeAllCursor : Qt.CrossCursor
      // "" idle, "new" drawing, "move", or an edge ("tl", "r" …)
      property string grab: ""
      property real px: 0
      property real py: 0
      property var start: null

      function edgeAt(x, y) {
        if (!region.has) return "";
        const s = region.sel, m = 8;
        const l = Math.abs(x - s.x) <= m, r = Math.abs(x - (s.x + s.w)) <= m;
        const t = Math.abs(y - s.y) <= m, b = Math.abs(y - (s.y + s.h)) <= m;
        const inX = x >= s.x - m && x <= s.x + s.w + m, inY = y >= s.y - m && y <= s.y + s.h + m;
        let e = "";
        if (t && inX) e += "t"; else if (b && inX) e += "b";
        if (l && inY) e += "l"; else if (r && inY) e += "r";
        if (e !== "") return e;
        if (x > s.x && x < s.x + s.w && y > s.y && y < s.y + s.h) return "move";
        return "";
      }

      onPositionChanged: (m) => {
        if (ptr.grab === "") {
          if (!region.has) region.hoverWin = Cap.windowAt(cap.wins, m.x, m.y);
          return;
        }
        const W = region.width, H = region.height;
        if (ptr.grab === "new") {
          region.sel = Cap.rectOf(ptr.px, ptr.py, m.x, m.y, W, H);
        } else if (ptr.grab === "move") {
          region.sel = Cap.moveRect(ptr.start, m.x - ptr.px, m.y - ptr.py, W, H);
        } else {
          region.sel = Cap.resizeRect(ptr.start, ptr.grab, m.x - ptr.px, m.y - ptr.py, W, H);
        }
      }
      onPressed: (m) => {
        ptr.px = m.x; ptr.py = m.y;
        ptr.start = region.sel;
        // RIGHT-DRAG RESIZES from wherever you are: the corner nearest the
        // pointer follows it, so the box can be adjusted without first
        // finding an eight-pixel handle.
        if (m.button === Qt.RightButton) {
          if (!region.has) return;
          const s = region.sel;
          ptr.grab = (m.x < s.x + s.w / 2 ? "l" : "r") + (m.y < s.y + s.h / 2 ? "t" : "b");
          return;
        }
        const e = ptr.edgeAt(m.x, m.y);
        ptr.grab = e !== "" ? e : "new";
      }
      onReleased: (m) => {
        if (m.button === Qt.RightButton) { ptr.grab = ""; return; }
        const drew = ptr.grab === "new";
        ptr.grab = "";
        // a click that never travelled: take the window under it whole
        if (drew && Math.abs(m.x - ptr.px) < 4 && Math.abs(m.y - ptr.py) < 4) {
          const w = Cap.windowAt(cap.wins, m.x, m.y);
          region.sel = w ? Cap.rectOf(w.x, w.y, w.x + w.w, w.y + w.h, region.width, region.height)
                         : ptr.start;
        }
      }
      acceptedButtons: Qt.LeftButton | Qt.RightButton
    }

    // ── the answer ────────────────────────────────────────────────────
    // Save and Abort under the selection, or above it when there is no room
    // below. Nothing is captured until Save.
    Row {
      id: actions
      visible: region.has && ptr.grab === ""
      spacing: 8
      x: Math.max(8, Math.min(region.width - width - 8, region.sel.x + region.sel.w - width))
      y: region.sel.y + region.sel.h + 10 + height < region.height
        ? region.sel.y + region.sel.h + 10
        : Math.max(8, region.sel.y - height - 10)
      Rectangle {
        width: actRow.implicitWidth + 16
        height: actRow.implicitHeight + 12
        radius: Zenon.menuRadius
        color: Zenon.menuBgSolid
        border.width: 1
        border.color: Zenon.border
        Row {
          id: actRow
          anchors.centerIn: parent
          spacing: 8
          // what else the box answers to, beside the two buttons
          Column {
            anchors.verticalCenter: parent.verticalCenter
            rightPadding: 6
            Text {
              text: "right-drag to resize  ·  drag inside to move"
              color: Zenon.keyInk
              font.family: Zenon.face
              font.pixelSize: 12
            }
            Text {
              text: "arrows move  ·  ctrl+arrows size  ·  ↵ save  ·  esc abort"
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 11
            }
          }
          DialogButton { label: "Abort"; ink: Zenon.muted; onClicked: region.finish(false) }
          DialogButton { label: "Save"; ink: Zenon.cyan; primary: true; onClicked: region.finish(true) }
        }
      }
    }

    // what to do before there is a selection
    Rectangle {
      visible: !region.has
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 60
      width: hint.implicitWidth + 28
      height: 34
      radius: Zenon.menuRadius
      color: Zenon.menuBgSolid
      border.width: 1
      border.color: Zenon.border
      Text {
        id: hint
        anchors.centerIn: parent
        text: "drag to select  ·  click a window to take it  ·  right-drag resizes once drawn  ·  esc to abort"
        color: Zenon.keyInk
        font.family: Zenon.face
        font.pixelSize: 14
      }
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: (e) => {
        e.accepted = true;
        if (e.key === Qt.Key_Escape) { region.finish(false); return; }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { region.finish(true); return; }
        if (!region.has) return;
        const n = (e.modifiers & Qt.ShiftModifier) ? 10 : 1;
        let dx = 0, dy = 0;
        if (e.key === Qt.Key_Left) dx = -n;
        else if (e.key === Qt.Key_Right) dx = n;
        else if (e.key === Qt.Key_Up) dy = -n;
        else if (e.key === Qt.Key_Down) dy = n;
        else return;
        // ctrl grows or shrinks from the bottom-right; plain arrows move
        region.sel = (e.modifiers & Qt.ControlModifier)
          ? Cap.resizeRect(region.sel, "br", dx, dy, region.width, region.height)
          : Cap.moveRect(region.sel, dx, dy, region.width, region.height);
      }
    }
  }
}
