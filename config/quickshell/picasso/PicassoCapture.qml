// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SCREENSHOT — what hyprshot.lua did, in picasso, and one thing it could
// not: a region you can still change your mind about.
//
//   screen   the monitor you are on, whole
//   window   the window that has the keyboard, the way macOS takes one —
//            alone, corners rounded, its drop shadow on transparency
//            (window-plain: no shadow; SUPER+ALT+PRINT)
//   region   a rectangle you draw, then ADJUST — slurp captured the moment
//            the button came up, so a box a few pixels off was a box you
//            drew again. Here it stays up with handles until you press Save
//            (or Return), and Abort (or Escape) walks away. Quick presets
//            (1–7: shapes, exact sizes, the screen; l the last region)
//            reshape it, Copy text (t) reads it with tesseract instead —
//            the viewer's OCR — and puts the words on the clipboard, and
//            Snap (s) puts the picture on the clipboard and saves nothing.
//
// THE SAME OVERLAY PICKS FOR A RECORDING (argus, 10-20). Argus' region and
// window recordings used to ask slurp, a crosshair that took the box the
// moment the button came up and knew nothing of windows. Now they ask here,
// through `qs ipc call Picasso pickRegion|pickWindow <file>`: the overlay
// comes up exactly as it does for a shot, but Save (Record, there) captures
// nothing — the rectangle is written to <file> in slurp's own "X,Y WxH" and
// argus hands it to wf-recorder. `cap.purpose` is which of the three the
// session is: "shot", "region" (draw a box, every tool a shot has but Copy
// text), or "window" (no box at all: the windows light under the pointer,
// starting with the one that has the keyboard, and a click — or Return —
// records the lit one). Whatever ends the session, it answers: an aborted
// one, or one the shell could not start, writes an empty file, so argus is
// never left waiting.
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
import "../morpheus"
import "../oracle"
import "capture.js" as Cap
import "viewer.js" as V

Scope {
  id: cap

  property bool busy: false
  // the region session: which screen it is on
  property var regionScreen: null
  property var monitor: null
  property string pendingGeo: ""
  property var wins: []
  // the last region saved, for `l` — in the coordinates of the screen it was on
  property var lastSel: null
  property string lastScreen: ""
  // "shot", or what a recording asked for — "region" or "window" — and the
  // file its answer goes to (see the header)
  property string purpose: "shot"
  property string reply: ""
  readonly property bool recording: cap.purpose !== "shot"


  Connections {
    target: Picasso
    // asked again while a region is up: that is "never mind"
    function onShotRequested(mode) {
      if (region.active) { region.finish(false); return; }
      if (cap.busy) return;
      cap.purpose = "shot";
      cap.shoot(mode);
    }
    // and a recording's pick: asked again while the overlay is up is the
    // same "never mind" (the second Super+Ctrl+R puts it away), and asked
    // while a shot is still being taken is told no at once — either way the
    // asker hears back, empty.
    function onGeometryRequested(kind, reply) {
      if (region.active) { region.finish(false); cap.say(reply, ""); return; }
      if (cap.busy) { cap.say(reply, ""); return; }
      cap.purpose = kind === "window" ? "window" : "region";
      cap.reply = reply;
      cap.shoot("pick");
    }
  }

  // A recording's answer, written whole: to a temporary name and then moved,
  // so argus, waiting for the file to appear, never reads half of it.
  function say(path, geo) {
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2.part\" && mv -f \"$2.part\" \"$2\"",
      "sh", geo, path]);
  }
  // the end of a recording's session: its answer, and the overlay free again
  function answer(geo) {
    cap.say(cap.reply, geo);
    cap.reply = "";
    cap.purpose = "shot";
    cap.busy = false;
  }

  function sh(s) { return Strings.shellQuote(s); }

  // ── asking hyprland where things are ──────────────────────────────────
  // monitors and clients as JSON, read here rather than through jq (which
  // this machine does not have — the old window mode silently depended on it).
  property string wantMode: ""
  Process {
    id: askProc
    // and the decoration settings a window shot draws its shadow from
    command: ["sh", "-c", "hyprctl -j monitors; echo '@@'; hyprctl -j clients; echo '@@'; hyprctl -j activewindow; "
      + "echo '@@'; printf '['; sep=; for o in " + Cap.SHADOW_OPTIONS.join(" ")
      + "; do printf \"$sep\"; hyprctl -j getoption \"$o\"; sep=,; done; printf ']'"]
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
    let mons = [], clients = [], active = null, opts = [];
    try { mons = JSON.parse(parts[0]); } catch (e) {}
    try { clients = JSON.parse(parts[1]); } catch (e) {}
    try { active = JSON.parse(parts[2]); } catch (e) {}
    try { opts = JSON.parse(parts[3]); } catch (e) {}
    const scr = Oracle.focusedScreen();
    const mon = mons.find(m => m.focused) || mons.find(m => scr && m.name === scr.name);
    if (!mon || !scr) {
      if (cap.recording) cap.answer(""); else cap.busy = false;
      return;
    }
    const plain = cap.wantMode === "window-plain";
    const mode = plain ? "window" : cap.wantMode;
    const file = Picasso.shotDir + "/" + Cap.fileName(new Date(), mode, mon.name);

    if (cap.wantMode === "screen") {
      cap.run("mkdir -p " + cap.sh(Picasso.shotDir) + " && grim -o " + cap.sh(mon.name)
              + " " + cap.sh(file), file);
      return;
    }
    // The window with the keyboard, the way macOS takes one: alone, corners
    // rounded, its drop shadow on transparency (capture.js shadowCommand).
    // `window-plain` keeps the rounding and leaves the shadow out.
    if (mode === "window") {
      if (!active || !active.at || !active.size) { cap.busy = false; return; }
      const wm = mons.find(m => m.id === active.monitor) || mon;
      const s = wm.scale > 0 ? wm.scale : 1;
      cap.run(Cap.windowShotCommand({
        dir: Picasso.shotDir, file: file,
        raw: Paths.runtimeDir() + "/picasso-window-" + Date.now() + ".png",
        helper: Quickshell.shellDir + "/picasso/bin/toplevel.py",
        address: String(active.address || ""),
        geo: active.at[0] + "," + active.at[1] + " " + active.size[0] + "x" + active.size[1],
        spec: Cap.shadowSpec(opts, s, plain, (active.fullscreen || 0) > 0),
        w: active.size[0] * s, h: active.size[1] * s
      }), file);
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
    // EVERY SESSION STARTS WITH THE WINDOW THAT HAS THE KEYBOARD LIT (10-21)
    // — a shot, a region recording and a window recording alike — so
    // Return alone takes it, and dragging draws a box instead, the way it
    // always did. Before, nothing was lit until the pointer moved; the
    // window under it lit then, which is usually but not always this one.
    // Moving the pointer still hands the light to whatever is under it.
    if (active && active.address)
      region.hoverWin = cap.wins.find(w => w.address === active.address) || null;
  }

  // The capture itself, then the part every mode shares.
  //
  // WITH THE POINTER OUT OF THE PICTURE. This machine draws its cursor in
  // software, into the frame itself, so grim cannot leave it out — every
  // window shot had the arrow sitting in it. So hyprland stops drawing it
  // (Picasso.cursorCmd) for the length of the capture, and the capture waits
  // a frame or two for that to land — long enough, too, for the region
  // overlay to have left the screen.
  // It always comes back: after grim, whether grim worked or not; on a
  // signal, through the trap; and grim gets ten seconds, so a hung capture
  // cannot keep it hidden.
  function run(cmd, file) {
    shotProc.file = file;
    shotProc.command = ["sh", "-c",
      "trap " + cap.sh(Picasso.cursorCmd(true)) + " EXIT; trap 'exit 130' INT TERM HUP; "
      + Picasso.cursorCmd(false) + "; sleep 0.1; timeout 10 sh -c " + cap.sh(cmd)];
    shotProc.running = true;
  }

  // ── the words in it ───────────────────────────────────────────────────
  // The rectangle to a png in the runtime directory, then the viewer's own
  // OCR (viewer.js ocrCommand: tesseract, the text to the clipboard, the png
  // removed). Nothing is kept in the screenshots; a toast says how it went.
  function readText(geo) {
    const tmp = Paths.runtimeDir() + "/picasso-ocr-" + Date.now() + ".png";
    textProc.command = ["sh", "-c",
      "sleep 0.15; timeout 10 grim -g \"$2\" \"$1\" || exit 4\n" + V.ocrCommand(tmp), "sh", tmp, geo];
    textProc.running = true;
  }
  Process {
    id: textProc
    onExited: (code) => {
      cap.busy = false;
      const say = code === 0 ? ["Text copied", "the words in the region are on the clipboard"]
        : code === 127 ? ["Reading text needs tesseract", "pacman -S tesseract tesseract-data-eng"]
        : code === 3 ? ["No text found", "tesseract read nothing in that region"]
        : ["Could not read the region", "the capture failed"];
      Quickshell.execDetached(["notify-send", "-a", "picasso", say[0], say[1]]);
    }
  }

  // ── a snap ────────────────────────────────────────────────────────────
  // The rectangle straight to the clipboard, through the same pointer-hiding
  // run() a shot uses, and nothing written to the screenshots. No file means
  // no capture card either — a plain toast says it is there.
  function snap(geo) {
    cap.run("grim -g " + cap.sh(geo) + " - | wl-copy --type image/png", "");
  }

  Process {
    id: shotProc
    property string file: ""
    onExited: (code) => {
      cap.busy = false;
      if (code !== 0) return;
      if (shotProc.file) cap.announce(shotProc.file);
      else Quickshell.execDetached(["notify-send", "-a", "picasso", "Snapped", "the region is on the clipboard"]);
    }
  }

  // a shell that died with the pointer hidden gives it back when it starts
  Component.onCompleted: Picasso.showCursor(true)

  // Clipboard, and the toast. The toast is howler's capture card — the
  // screenshot itself, with Open, Show in terminus and Annotate on it — and
  // the two hints are what make it one: what kind of capture, and which file.
  // The words are still sent, for the bell's history, which draws rows of
  // text. Howler does the buttons through picasso's own IPC, so nothing here
  // waits on the toast.
  function announce(file) {
    const name = file.split("/").pop();
    Quickshell.execDetached(["sh", "-c",
      "wl-copy --type image/png < " + cap.sh(file) + "; "
      + "notify-send -a picasso -i " + cap.sh(file)
      + " -h string:x-howler-capture:shot -h string:x-howler-file:" + cap.sh(file) + " "
      + cap.sh("Screenshot saved") + " " + cap.sh(name + " · copied")]);
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

    function preset(p) {
      region.hoverWin = null;
      region.sel = Cap.presetRect(region.sel, p, region.width, region.height, region.dpr);
    }
    // the region saved last, on this same screen
    readonly property bool hasLast: !!cap.lastSel && !!cap.monitor && cap.lastScreen === cap.monitor.name
    function useLast() {
      if (!region.hasLast) return;
      const l = cap.lastSel;
      region.hoverWin = null;
      region.sel = Cap.rectOf(l.x, l.y, l.x + l.w, l.y + l.h, region.width, region.height);
    }

    function begin() {
      region.sel = { x: 0, y: 0, w: 0, h: 0 };
      region.hoverWin = null;
      region.active = true;
      keys.forceActiveFocus();
      claim.restart();
    }

    // `how`: "text" reads it rather than keep it (see cap.readText);
    // "snap" puts it on the clipboard and keeps no file (see cap.snap)
    function finish(save, how) {
      // with no box drawn, what is taken is the lit window — the focused one
      // the session started with, or the one the pointer last crossed
      // (kept to the screen, the way a clicked window is: one hanging off
      // the edge would be a geometry grim and wf-recorder refuse)
      const h = region.hoverWin;
      const s = !region.has && h
        ? Cap.rectOf(h.x, h.y, h.x + h.w, h.y + h.h, region.width, region.height) : region.sel;
      const ok = save && s.w > 2 && s.h > 2;
      region.active = false;
      if (cap.recording) {
        if (ok && cap.purpose === "region") { cap.lastSel = s; cap.lastScreen = cap.monitor ? cap.monitor.name : ""; }
        const m = cap.monitor;
        cap.answer(ok ? (m.x + s.x) + "," + (m.y + s.y) + " " + s.w + "x" + s.h : "");
        return;
      }
      if (!ok) { cap.busy = false; return; }
      cap.lastSel = s;
      cap.lastScreen = cap.monitor ? cap.monitor.name : "";
      // In the layout's coordinates, which is what grim -g takes: the
      // monitor's own origin plus the box.
      const m = cap.monitor;
      cap.pendingGeo = (m.x + s.x) + "," + (m.y + s.y) + " " + s.w + "x" + s.h;
      if (how === "text") { cap.readText(cap.pendingGeo); return; }
      if (how === "snap") { cap.snap(cap.pendingGeo); return; }
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
    // ── WHAT IS LIT GLIDES ────────────────────────────────────────────
    // The lit box (`lx ly lw lh`) follows `lit`, but eased when it jumps on
    // its own — from one window to the next under the pointer, to a preset,
    // to the last region — and at once while you drag it or when it first
    // appears, so the box never lags your hand or grows out of a corner.
    property real lx: 0
    property real ly: 0
    property real lw: 0
    property real lh: 0
    property bool hadLit: false
    onLitChanged: {
      const r = region.lit;
      if (!r) { region.hadLit = false; litGlide.stop(); return; }
      if (!region.hadLit || ptr.grab !== "") {
        litGlide.stop();
        region.lx = r.x; region.ly = r.y; region.lw = r.w; region.lh = r.h;
      } else {
        litGlide.stop();
        gx.to = r.x; gy.to = r.y; gw.to = r.w; gh.to = r.h;
        litGlide.start();
      }
      region.hadLit = true;
    }
    ParallelAnimation {
      id: litGlide
      NumberAnimation { id: gx; target: region; property: "lx"; duration: Zenon.ms(160); easing.type: Easing.OutCubic }
      NumberAnimation { id: gy; target: region; property: "ly"; duration: Zenon.ms(160); easing.type: Easing.OutCubic }
      NumberAnimation { id: gw; target: region; property: "lw"; duration: Zenon.ms(160); easing.type: Easing.OutCubic }
      NumberAnimation { id: gh; target: region; property: "lh"; duration: Zenon.ms(160); easing.type: Easing.OutCubic }
    }

    // the dim, fading in as the overlay comes up rather than dropping over
    // the screen at once (it goes at once: Save must not wait for it)
    Item {
      anchors.fill: parent
      opacity: region.active ? 1 : 0
      Behavior on opacity { enabled: region.active; NumberAnimation { duration: Zenon.ms(180); easing.type: Easing.OutCubic } }
      readonly property bool on: !!region.lit
      Rectangle { color: region.shade; x: 0; y: 0; width: parent.width
        height: parent.on ? region.ly : parent.height }
      Rectangle { color: region.shade; visible: parent.on; x: 0
        y: region.ly + region.lh; width: parent.width
        height: parent.height - (region.ly + region.lh) }
      Rectangle { color: region.shade; visible: parent.on; x: 0
        y: region.ly; width: region.lx; height: region.lh }
      Rectangle { color: region.shade; visible: parent.on
        x: region.lx + region.lw; y: region.ly
        width: parent.width - (region.lx + region.lw); height: region.lh }

      // the outline: solid for a selection, thin for a window that would be
      // taken if you clicked
      Rectangle {
        visible: parent.on
        x: region.lx - 1
        y: region.ly - 1
        width: region.lw + 2
        height: region.lh + 2
        color: "transparent"
        border.width: region.has ? 2 : 1
        border.color: region.has ? Zenon.cyan : Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.6)
      }
    }

    // ── the handles ───────────────────────────────────────────────────
    Repeater {
      model: region.has ? ["tl", "t", "tr", "r", "br", "b", "bl", "l"] : []
      delegate: Rectangle {
        required property string modelData
        readonly property real hx: modelData.indexOf("l") >= 0 ? region.lx
          : modelData.indexOf("r") >= 0 ? region.lx + region.lw : region.lx + region.lw / 2
        readonly property real hy: modelData.indexOf("t") >= 0 ? region.ly
          : modelData.indexOf("b") >= 0 ? region.ly + region.lh : region.ly + region.lh / 2
        x: hx - 5
        y: hy - 5
        width: 10
        height: 10
        radius: Zenon.rad(2)
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
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
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
        // a window recording draws nothing: the release takes the window
        if (cap.purpose === "window") return;
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
        if (cap.purpose === "window") {
          if (m.button !== Qt.LeftButton) return;
          const w = Cap.windowAt(cap.wins, m.x, m.y);
          if (!w) return;
          region.hoverWin = w;
          region.finish(true);
          return;
        }
        if (m.button === Qt.RightButton) { ptr.grab = ""; return; }
        const drew = ptr.grab === "new";
        ptr.grab = "";
        // a click that never traveled: take the window under it whole
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
              text: "Right-drag to resize  ·  drag inside to move"
              color: Zenon.accentKey
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            Text {
              text: cap.recording ? "Arrows move  ·  ctrl+arrows size  ·  ↵ record  ·  esc abort"
                : "Arrows move  ·  ctrl+arrows size  ·  t copy text  ·  s snap  ·  ↵ save  ·  esc abort"
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(11)
            }
          }
          DialogButton { label: "Abort"; ink: Zenon.accentMuted; onClicked: region.finish(false) }
          DialogButton { visible: !cap.recording; label: "Copy text"; onClicked: region.finish(true, "text") }
          DialogButton { visible: !cap.recording; label: "Snap"; onClicked: region.finish(true, "snap") }
          DialogButton { label: cap.recording ? "Record" : "Save"; ink: Zenon.cyan; primary: true; onClicked: region.finish(true) }
        }
      }
    }

    // ── the quick presets ─────────────────────────────────────────────
    // Shapes about the selection's center (or the screen's, before one is
    // drawn), exact sizes in real pixels, the whole screen, and the last
    // region saved. Above the answer when there is a selection, above the
    // hint when there is not.
    Rectangle {
      id: presetBar
      // (a window recording has no box to shape)
      visible: region.active && ptr.grab === "" && cap.purpose !== "window"
      width: presetRow.implicitWidth + 12
      height: presetRow.implicitHeight + 10
      radius: Zenon.menuRadius
      color: Zenon.menuBgSolid
      border.width: 1
      border.color: Zenon.border
      x: region.has ? Math.max(8, Math.min(region.width - width - 8, actions.x + actions.width - width))
                    : (region.width - width) / 2
      y: region.has
        ? (actions.y > region.sel.y ? actions.y + actions.height + 8 : Math.max(8, actions.y - height - 8))
        : region.height - 60 - 34 - 10 - height
      Row {
        id: presetRow
        anchors.centerIn: parent
        spacing: 4
        Repeater {
          model: Cap.PRESETS.concat([{ key: "l", label: "Last", last: true }])
          delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool live: !chip.modelData.last || region.hasLast
            width: chipRow.implicitWidth + 16
            height: 26
            radius: Zenon.windowRadius
            color: chipMa.pressed && chip.live ? Zenon.wash(0.08) : "transparent"
            opacity: chip.live ? 1 : Zenon.disabledDim
            Row {
              id: chipRow
              anchors.centerIn: parent
              spacing: 6
              Text {
                text: chip.modelData.key
                color: Zenon.accentKey
                font.family: Zenon.faceMono
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(11)
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: chip.modelData.label
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            MouseArea {
              id: chipMa
              anchors.fill: parent
              hoverEnabled: true
              enabled: chip.live
              onClicked: chip.modelData.last ? region.useLast() : region.preset(chip.modelData)
            }
          }
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
        text: cap.purpose === "window" ? "Click a window to record it  ·  ↵ the lit one  ·  esc to abort"
          : cap.purpose === "region" ? "Drag to select the area to record  ·  click a window or ↵ the lit one  ·  1–7 a preset  ·  esc to abort"
          : "Drag to select  ·  click a window or ↵ the lit one  ·  1–7 a preset  ·  esc to abort"
        color: Zenon.accentKey
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: (e) => {
        e.accepted = true;
        if (e.key === Qt.Key_Escape) { region.finish(false); return; }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
          // (nothing drawn and nothing lit is nothing to take yet)
          if (!region.has && !region.hoverWin) return;
          region.finish(true);
          return;
        }
        // a window recording answers only to those two and the pointer
        if (cap.purpose === "window") return;
        if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
          const p = Cap.PRESETS.find((q) => q.key === String(e.key - Qt.Key_0));
          if (p) region.preset(p);
          return;
        }
        if (e.key === Qt.Key_L) { region.useLast(); return; }
        if (!region.has) return;
        if (e.key === Qt.Key_T) { if (!cap.recording) region.finish(true, "text"); return; }
        if (e.key === Qt.Key_S) { if (!cap.recording) region.finish(true, "snap"); return; }
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
