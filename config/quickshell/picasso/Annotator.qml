// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ANNOTATION — the viewer's drawing mode. Reached from the viewer's own
// Annotate (a), and from everything that used to open a window of its own
// for this: a screenshot's toast, terminus' and folio's Annotate. Those all
// still say Picasso.annotate(path); the viewer answers it by opening on that
// picture, in this mode, with the picture's directory around it.
//
// Everything is drawn onto a canvas at the picture's OWN resolution: the
// picture first, then each mark in order. The window shows that canvas
// scaled to fit, and saving writes the canvas as it is — so a mark drawn on
// a scaled-down view of a 2560-wide screenshot is saved at 2560, not at the
// size it happened to be on screen.
//
//   Save       over the picture it opened
//   Save New   a new file, through terminus' own save dialog — opened in
//              the picture's own directory with a name already in it, so Return
//              takes the default and anywhere else is a walk through directories
//   Copy       the annotated picture to the clipboard
//
// Tools on keys as well as buttons: p pen, h highlighter, l line, a arrow,
// r rectangle, e ellipse, t text, n numbered marker, x pixelate, s spotlight,
// c crop; o rounds the corners of a rectangle or a spotlight.
// Shift holds a line to 45° and a box to a square. ctrl+z / ctrl+shift+z undo and
// redo, ctrl+s save, ctrl+shift+s save new, ctrl+c copy, esc back to the
// viewer — asking first when there are marks nobody saved.

import QtQuick
import Quickshell
import "../morpheus"
import "capture.js" as Cap
import "viewer.js" as V

Item {
  id: ann

  property string path: ""
  // terminus, for Save New's dialog — the viewer's, handed down
  property var fileManager: null

  // Done with: the marks are saved, or discarded, or there were none.
  signal finished()
  // A file was written — the viewer reloads it, or adds a new one to the
  // gallery.
  signal saved(string file)

  function takeFocus() { keys.forceActiveFocus(); }

  // every button's name, under it — see morpheus/WindowTip
  WindowTip { id: tips; window: ann.QsWindow.window }

  // ── what is drawn ────────────────────────────────────────────────
  property var marks: []
  property var undone: []
  property var live: null
  property bool dirty: false
  property int nextNumber: 1

  property string tool: "arrow"
  property color ink: Zenon.red
  property int size: 1       // 0 small, 1 medium, 2 large
  // rectangles and spotlights with rounded corners (o)
  property bool rounded: false
  // where the pointer is over the picture, for the tool's preview under it
  property point hoverAt: Qt.point(0, 0)

  readonly property var tools: [
    ["pen",       "", "p", "Pen"],
    ["highlight", "", "h", "Highlighter"],
    ["line",      "", "l", "Line"],
    ["arrow",     "", "a", "Arrow"],
    ["rect",      "", "r", "Rectangle"],
    ["ellipse",   "", "e", "Ellipse"],
    ["text",      "", "t", "Text"],
    ["number",    "", "n", "Numbered marker"],
    ["pixelate",  "", "x", "Pixelate"],
    ["spot",      "\uf0eb", "s", "Spotlight"],
    ["crop",      "\uf125", "c", "Crop"]
  ]
  readonly property var inks: [Zenon.red, Zenon.yellow, Zenon.green, Zenon.cyan,
                               Zenon.blue, Zenon.magenta, "#ffffff", "#000000"]

  // Sizes in the PICTURE's pixels, scaled to how big the picture is, so
  // "medium" means the same thing on a 1080p shot and a 4K one.
  readonly property real unit: Math.max(1, paper.width / 1600)
  readonly property real stroke: [3, 6, 12][ann.size] * ann.unit
  readonly property real textPx: [22, 34, 52][ann.size] * ann.unit

  // ── the crop ─────────────────────────────────────────────────────
  // A crop is a mark like any other — {kind: "crop", r} in the picture's
  // pixels, r null for the whole picture — so undo and redo take it back
  // like a stroke. The last one is the crop. Marks stay in the whole
  // picture's coordinates; only what is shown and saved is cut down to it.
  readonly property var whole: ({ x: 0, y: 0, w: paper.width, h: paper.height })
  readonly property var crop: {
    for (let i = ann.marks.length - 1; i >= 0; --i)
      if (ann.marks[i].kind === "crop") return ann.marks[i].r;
    return null;
  }
  readonly property bool cropping: ann.tool === "crop"
  // the box being set up while the crop tool is in the hand
  property var draft: null
  // what is on screen and in the file: all of it while cropping, so the
  // box can grow back out
  readonly property var shown: ann.cropping || !ann.crop ? ann.whole : ann.crop
  // the tool to go back to when the crop is done with
  property string back: "arrow"
  property string was: "arrow"
  onToolChanged: {
    ann.glide = true; glideOff.restart();
    if (ann.tool === "crop") ann.draft = ann.crop;
    else if (ann.was === "crop") ann.applyCrop();
    if (ann.tool !== "crop") ann.back = ann.tool;
    ann.was = ann.tool;
  }
  function sameRect(a, b) {
    if (!a || !b) return !a && !b;
    return a.x === b.x && a.y === b.y && a.w === b.w && a.h === b.h;
  }
  function applyCrop() {
    let r = ann.draft;
    if (r && r.x === 0 && r.y === 0 && r.w === paper.width && r.h === paper.height) r = null;
    if (!ann.sameRect(r, ann.crop)) ann.commit({ kind: "crop", r: r });
  }
  function cancelCrop() { ann.draft = ann.crop; ann.tool = ann.back; }
  // the frame slides to a new crop, but not while the window is resized
  property bool glide: false
  Timer { id: glideOff; interval: Zenon.slow + 60; onTriggered: ann.glide = false }

  function commit(m) {
    const next = ann.marks.slice();
    next.push(m);
    ann.marks = next;
    ann.undone = [];
    ann.dirty = true;
    done.requestPaint();
  }
  function undo() {
    if (ann.marks.length === 0) return;
    const m = ann.marks.slice(), u = ann.undone.slice();
    u.push(m.pop());
    ann.marks = m; ann.undone = u; ann.dirty = true;
    ann.afterStep();
  }
  function afterStep() {
    ann.renumber();
    ann.glide = true; glideOff.restart();
    if (ann.cropping) ann.draft = ann.crop;
    done.requestPaint();
  }
  function redo() {
    if (ann.undone.length === 0) return;
    const m = ann.marks.slice(), u = ann.undone.slice();
    m.push(u.pop());
    ann.marks = m; ann.undone = u; ann.dirty = true;
    ann.afterStep();
  }
  function renumber() {
    let n = 1;
    for (const m of ann.marks) if (m.kind === "number") n = Math.max(n, m.n + 1);
    ann.nextNumber = n;
  }

  // ── saving ───────────────────────────────────────────────────────
  property string note: ""
  Timer { id: noteClear; interval: 3000; onTriggered: ann.note = "" }
  function say(t) { ann.note = t; noteClear.restart(); }

  // Asked before the picture is written over itself — the viewer keeps a
  // copy first, for its undo — and handed the write to do once it has.
  property var guard: null
  function saveTo(file) {
    if (ann.guard && file === ann.path) { ann.guard(file, () => ann.write_(file)); return true; }
    return ann.write_(file);
  }
  // A crop set up and not applied yet is applied by saving; the canvas
  // then repaints at its new size, and only that is written.
  function whenPainted(fn) {
    if (ann.cropping) ann.tool = ann.back;
    if (done.stale) done.after = fn; else fn();
  }
  function write_(file) {
    if (ann.cropping || done.stale) { ann.whenPainted(() => ann.write_(file)); return true; }
    if (!done.save(file)) { ann.say("could not save to " + file); return false; }
    ann.dirty = false;
    ann.saved(file);
    ann.say("saved · " + file.replace(Quickshell.env("HOME"), "~"));
    return true;
  }
  function copy() {
    if (ann.cropping || done.stale) { ann.whenPainted(() => ann.copy()); return; }
    // Straight into the runtime directory, which always exists. A
    // subdirectory was made by a detached mkdir that had not run yet when
    // save() did, so the first Copy of every session failed.
    const tmp = Paths.runtimeDir() + "/picasso-annotated-" + Date.now() + ".png";
    if (!done.save(tmp)) { ann.say("could not copy"); return; }
    Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < "
      + Strings.shellQuote(tmp) + "; rm -f " + Strings.shellQuote(tmp)]);
    ann.say("copied to the clipboard");
  }

  // Save New asks terminus' picker for a path — its save dialog, the
  // one applications get — and writes the canvas there when it answers.
  function saveNew() {
    const fm = ann.fileManager;
    if (!fm) { ann.say("no file manager to ask"); return; }
    const here = ann.path.replace(/\/[^\/]*$/, "");
    const ok = fm.choose(false, here !== "" ? here : Picasso.shotDir, (paths) => {
      if (paths.length === 0) return;
      let f = String(paths[0]);
      if (!/\.(png|jpe?g|webp|bmp)$/i.test(f)) f += ".png";
      ann.saveTo(f);
    }, Cap.annotatedName(ann.path));
    if (!ok) ann.say("the file picker is busy with another request");
  }

  function close() {
    if (ann.dirty && !discard.open) { discard.open = true; return; }
    ann.finished();
  }

  // ── drawing a mark ───────────────────────────────────────────────
  function drawMark(ctx, m) {
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = m.ink;
    ctx.fillStyle = m.ink;
    ctx.lineWidth = m.w;
    const nx = Math.min(m.x1, m.x2), ny = Math.min(m.y1, m.y2);
    const nw = Math.abs(m.x2 - m.x1), nh = Math.abs(m.y2 - m.y1);
    // a soft shadow under the drawn marks, so they lift off a busy picture
    if (["pen", "line", "arrow", "rect", "ellipse", "number"].indexOf(m.kind) >= 0) {
      ctx.shadowColor = "rgba(0,0,0,0.45)";
      ctx.shadowBlur = Math.max(4 * ann.unit, (m.w || m.r / 4) * 1.4);
      ctx.shadowOffsetY = Math.max(1, (m.w || m.r / 4) * 0.35);
    }
    switch (m.kind) {
    case "highlight":
      ctx.globalAlpha = 0.35;
      ctx.lineWidth = m.w * 3.5;
      ctx.lineCap = "butt";
      // fall through
    case "pen": {
      const p = m.pts;
      if (!p || p.length < 2) break;
      ctx.beginPath();
      ctx.moveTo(p[0], p[1]);
      for (let i = 2; i < p.length; i += 2) ctx.lineTo(p[i], p[i + 1]);
      ctx.stroke();
      break;
    }
    case "line":
    case "arrow": {
      ctx.beginPath();
      ctx.moveTo(m.x1, m.y1);
      const a = Math.atan2(m.y2 - m.y1, m.x2 - m.x1);
      const head = Math.max(14 * ann.unit, m.w * 4);
      // the shaft stops short of the tip, so a thick line does not
      // poke out past the head
      const ex = m.kind === "arrow" ? m.x2 - Math.cos(a) * head * 0.6 : m.x2;
      const ey = m.kind === "arrow" ? m.y2 - Math.sin(a) * head * 0.6 : m.y2;
      ctx.lineTo(ex, ey);
      ctx.stroke();
      if (m.kind === "arrow") {
        ctx.beginPath();
        ctx.moveTo(m.x2, m.y2);
        ctx.lineTo(m.x2 - Math.cos(a - 0.45) * head, m.y2 - Math.sin(a - 0.45) * head);
        ctx.lineTo(m.x2 - Math.cos(a + 0.45) * head, m.y2 - Math.sin(a + 0.45) * head);
        ctx.closePath();
        ctx.fill();
      }
      break;
    }
    case "rect":
      if (m.round > 0) {
        const rr = Math.min(m.round, nw / 2, nh / 2);
        ctx.beginPath();
        ctx.roundedRect(nx, ny, nw, nh, rr, rr);
        ctx.stroke();
      } else ctx.strokeRect(nx, ny, nw, nh);
      break;
    case "spot":
      // in the hand: its hole, outlined; committed, all of them go at once
      // (drawSpots), so two never darken each other's hole
      ann.drawSpots(ctx, [m]);
      ctx.lineWidth = 2 * ann.unit;
      ctx.strokeStyle = "rgba(255,255,255,0.8)";
      ctx.setLineDash([6 * ann.unit, 4 * ann.unit]);
      ann.spotPath(ctx, m);
      ctx.stroke();
      break;
    case "ellipse":
      ctx.beginPath();
      ctx.ellipse(nx, ny, nw, nh);
      ctx.stroke();
      break;
    case "text": {
      ctx.font = "bold " + Math.round(m.px) + "px \"" + Zenon.face + "\"";
      ctx.textBaseline = "top";
      const lines = String(m.text).split("\n");
      // a thin dark edge, so white text reads on a white window
      ctx.lineWidth = Math.max(2, m.px / 10);
      ctx.strokeStyle = "rgba(0,0,0,0.55)";
      for (let i = 0; i < lines.length; ++i) {
        ctx.strokeText(lines[i], m.x1, m.y1 + i * m.px * 1.2);
        ctx.fillText(lines[i], m.x1, m.y1 + i * m.px * 1.2);
      }
      break;
    }
    case "number": {
      const r = m.r;
      ctx.beginPath();
      ctx.ellipse(m.x1 - r, m.y1 - r, r * 2, r * 2);
      ctx.fill();
      ctx.lineWidth = Math.max(2, r / 8);
      ctx.strokeStyle = "rgba(0,0,0,0.45)";
      ctx.stroke();
      ctx.fillStyle = Cap.inkOn(m.rgb[0], m.rgb[1], m.rgb[2]);
      ctx.font = "bold " + Math.round(r * 1.1) + "px \"" + Zenon.face + "\"";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(m.n), m.x1, m.y1 + r * 0.05);
      break;
    }
    case "pixelate":
      if (m.cells) {
        for (const c of m.cells) { ctx.fillStyle = c[4]; ctx.fillRect(c[0], c[1], c[2], c[3]); }
      } else {
        // while it is being drawn: where the blocks will go
        ctx.lineWidth = 2 * ann.unit;
        ctx.strokeStyle = "rgba(255,255,255,0.8)";
        ctx.setLineDash([6 * ann.unit, 4 * ann.unit]);
        ctx.strokeRect(nx, ny, nw, nh);
      }
      break;
    }
    ctx.restore();
  }

  // ── the spotlight ────────────────────────────────────────────────
  // Everything but the boxes, dimmed: one even-odd fill of the whole
  // picture with every box cut out of it, drawn where the first one falls
  // among the marks — marks before it are dimmed with the picture, marks
  // after it stand out.
  function spotPath(ctx, m) {
    const nx = Math.min(m.x1, m.x2), ny = Math.min(m.y1, m.y2);
    const nw = Math.abs(m.x2 - m.x1), nh = Math.abs(m.y2 - m.y1);
    ctx.beginPath();
    if (m.round > 0) {
      const rr = Math.min(m.round, nw / 2, nh / 2);
      ctx.roundedRect(nx, ny, nw, nh, rr, rr);
    } else ctx.rect(nx, ny, nw, nh);
  }
  // Each box clips itself out in turn — clips intersect — so what is
  // left to dim is outside all of them, and boxes that overlap stay lit.
  function drawSpots(ctx, spots) {
    ctx.save();
    ctx.fillRule = Qt.OddEvenFill;
    for (const m of spots) {
      ann.spotPath(ctx, m);
      ctx.rect(0, 0, paper.width, paper.height);
      ctx.clip();
    }
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    ctx.fillRect(0, 0, paper.width, paper.height);
    ctx.restore();
  }

  // The blocks a pixelate mark paints, read off what is drawn now.
  function pixelCells(x, y, w, h) {
    const s = ann.shown;
    const x2 = Math.min(x + w, s.x + s.w), y2 = Math.min(y + h, s.y + s.h);
    x = Math.max(x, s.x); y = Math.max(y, s.y); w = x2 - x; h = y2 - y;
    x = Math.round(x); y = Math.round(y); w = Math.round(w); h = Math.round(h);
    if (w < 2 || h < 2) return [];
    const b = Math.max(8, Math.round(Math.min(paper.width, paper.height) / 90));
    // the canvas holds only what is shown — the crop — from its corner
    const d = done.getContext("2d").getImageData(x - done.x, y - done.y, w, h).data;
    const out = [];
    for (let by = 0; by < h; by += b) {
      for (let bx = 0; bx < w; bx += b) {
        const bw = Math.min(b, w - bx), bh = Math.min(b, h - by);
        let r = 0, g = 0, bl = 0, n = 0;
        for (let yy = by; yy < by + bh; yy += 2)
          for (let xx = bx; xx < bx + bw; xx += 2) {
            const i = (yy * w + xx) * 4;
            r += d[i]; g += d[i + 1]; bl += d[i + 2]; ++n;
          }
        out.push([x + bx, y + by, bw, bh,
                  "rgb(" + Math.round(r / n) + "," + Math.round(g / n) + "," + Math.round(bl / n) + ")"]);
      }
    }
    return out;
  }

  function rgbOf(c) { return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)]; }
  function cssOf(c) { return "rgba(" + ann.rgbOf(c).join(",") + "," + c.a + ")"; }

  // ── the keys ─────────────────────────────────────────────────────
  Item {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.onPressed: (e) => {
      if (textEdit.visible) return;
      const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
      if (discard.open) return;
      e.accepted = true;
      if (ctrl && e.key === Qt.Key_Z) { shift ? ann.redo() : ann.undo(); return; }
      if (ctrl && e.key === Qt.Key_Y) { ann.redo(); return; }
      if (ctrl && e.key === Qt.Key_S) { shift ? ann.saveNew() : ann.saveTo(ann.path); return; }
      if (ctrl && e.key === Qt.Key_C) { ann.copy(); return; }
      if (ann.cropping) {
        if (e.key === Qt.Key_Escape) { ann.cancelCrop(); return; }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ann.tool = ann.back; return; }
        if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) { ann.draft = null; return; }
        if (e.text === "c") { ann.tool = ann.back; return; }
      }
      if (e.key === Qt.Key_Escape) { ann.close(); return; }
      if (e.key === Qt.Key_BracketLeft) { ann.size = Math.max(0, ann.size - 1); return; }
      if (e.key === Qt.Key_BracketRight) { ann.size = Math.min(2, ann.size + 1); return; }
      if (e.text === "o") { ann.rounded = !ann.rounded; return; }
      for (const t of ann.tools) if (e.text === t[2]) { ann.tool = t[0]; return; }
      const n = parseInt(e.text, 10);
      if (n >= 1 && n <= ann.inks.length) { ann.ink = ann.inks[n - 1]; return; }
      e.accepted = false;
    }
  }

  // ── the bar ──────────────────────────────────────────────────────
  Rectangle {
    id: bar
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 52
    color: Zenon.headBg
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }

    // ── A NARROW WINDOW ────────────────────────────────────────────
    // The tools from the left and the verbs from the right met in the
    // middle and drew over each other. First the verbs give up their words
    // (`tight`: icons, named in their tips); if the tools still do not fit
    // beside them, the tools scroll sideways under the wheel — none of them
    // is ever dropped.
    readonly property real verbsW: verbsWide.implicitWidth
    readonly property bool tight: toolRow.implicitWidth + 12 + 16 + bar.verbsW + 12 > bar.width
    readonly property real verbsAt: bar.width - 12
      - (bar.tight ? verbsNarrow.implicitWidth : bar.verbsW)

    Flickable {
      id: toolFlick
      x: 12
      width: Math.max(0, bar.verbsAt - 16 - 12)
      height: parent.height
      contentWidth: toolRow.implicitWidth
      contentHeight: height
      interactive: contentWidth > width
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.HorizontalFlick
      clip: true
      ElasticScroll { view: toolFlick; horizontal: true; step: 120 }

    Row {
      id: toolRow
      y: (toolFlick.height - height) / 2
      spacing: 14

      // back to the viewer — esc, as a button
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 34; height: 34; radius: Zenon.windowRadius
        color: backMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        Text {
          anchors.centerIn: parent
          text: ""
          color: backMa.containsMouse ? Zenon.cyan : Zenon.white
          font.family: Zenon.face
          font.pixelSize: 16
        }
        MouseArea {
          id: backMa
          anchors.fill: parent
          hoverEnabled: true
          onClicked: ann.close()
          onContainsMouseChanged: containsMouse ? tips.show(parent, "Back to the viewer", "esc")
                                                : tips.hide(parent)
        }
      }

      Rectangle { width: 1; height: 26; color: Zenon.border; anchors.verticalCenter: parent.verticalCenter }

      // tools
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
          model: ann.tools
          delegate: Rectangle {
            id: toolBtn
            required property var modelData
            readonly property bool on: ann.tool === modelData[0]
            width: 34; height: 34; radius: Zenon.windowRadius
            color: on ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.20)
              : (toolMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
            border.width: on ? 1 : 0
            border.color: Zenon.cyan
            Text {
              anchors.centerIn: parent
              text: modelData[1]
              color: on ? Zenon.cyan : Zenon.white
              font.family: Zenon.face
              font.pixelSize: 16
            }
            MouseArea {
              id: toolMa
              anchors.fill: parent
              hoverEnabled: true
              onClicked: ann.tool = on && modelData[0] === "crop" ? ann.back : modelData[0]
              onContainsMouseChanged: containsMouse ? tips.show(toolBtn, modelData[3], modelData[2])
                                                    : tips.hide(toolBtn)
            }
          }
        }
      }

      Rectangle { width: 1; height: 26; color: Zenon.border; anchors.verticalCenter: parent.verticalCenter }

      // inks
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Repeater {
          model: ann.inks
          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool on: Qt.colorEqual(ann.ink, modelData)
            width: 22; height: 22; radius: 11
            color: modelData
            border.width: on ? 2 : 1
            border.color: on ? Zenon.white : Zenon.border
            scale: on ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: Zenon.fast } }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: ann.ink = modelData
              onContainsMouseChanged: containsMouse
                ? tips.show(parent, ["Red", "Peach", "Green", "Cyan", "Blue", "Violet",
                                     "White", "Black"][index], String(index + 1))
                : tips.hide(parent)
            }
          }
        }
      }

      Rectangle { width: 1; height: 26; color: Zenon.border; anchors.verticalCenter: parent.verticalCenter }

      // sizes
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
          model: 3
          delegate: Rectangle {
            required property int index
            width: 30; height: 30; radius: Zenon.windowRadius
            color: ann.size === index ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            Rectangle {
              anchors.centerIn: parent
              width: [5, 9, 14][index]; height: width; radius: width / 2
              color: ann.size === index ? Zenon.white : Zenon.muted
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: ann.size = index
              onContainsMouseChanged: containsMouse
                ? tips.show(parent, ["Thin", "Medium", "Thick"][index], "[  ]")
                : tips.hide(parent)
            }
          }
        }
      }

      // corners, rounded or square, for a rectangle or a spotlight
      Rectangle {
        id: roundBtn
        anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30; radius: Zenon.windowRadius
        color: ann.rounded ? Qt.rgba(1, 1, 1, 0.10) : (roundMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        Rectangle {
          anchors.centerIn: parent
          width: 14; height: 11
          radius: ann.rounded ? 4 : 0
          color: "transparent"
          border.width: 1.5
          border.color: ann.rounded ? Zenon.white : Zenon.muted
          Behavior on radius { NumberAnimation { duration: Zenon.fast } }
        }
        MouseArea {
          id: roundMa
          anchors.fill: parent
          hoverEnabled: true
          onClicked: ann.rounded = !ann.rounded
          onContainsMouseChanged: containsMouse
            ? tips.show(roundBtn, ann.rounded ? "Square corners" : "Rounded corners", "o")
            : tips.hide(roundBtn)
        }
      }

      Rectangle { width: 1; height: 26; color: Zenon.border; anchors.verticalCenter: parent.verticalCenter }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
          model: [["", "undo"], ["", "redo"]]
          delegate: Rectangle {
            required property var modelData
            readonly property bool can: modelData[1] === "undo" ? ann.marks.length > 0 : ann.undone.length > 0
            width: 32; height: 32; radius: Zenon.windowRadius
            color: urMa.containsMouse && can ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
            Text {
              anchors.centerIn: parent
              text: modelData[0]
              color: can ? Zenon.white : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 15
            }
            MouseArea {
              id: urMa
              anchors.fill: parent
              hoverEnabled: true
              onClicked: modelData[1] === "undo" ? ann.undo() : ann.redo()
              onContainsMouseChanged: containsMouse
                ? tips.show(parent, modelData[1] === "undo" ? "Undo" : "Redo",
                            modelData[1] === "undo" ? "ctrl+z" : "ctrl+shift+z")
                : tips.hide(parent)
            }
          }
        }
      }
    }

    }

    Row {
      id: verbsWide
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
      // measured even while the icons stand in (see `tight`), so it stays
      // laid out and only goes see-through and deaf
      opacity: bar.tight ? 0 : 1
      enabled: !bar.tight
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ann.note
        color: Zenon.sand
        font.family: Zenon.face
        font.pixelSize: 13
        rightPadding: 6
      }
      DialogButton { label: "Copy"; ink: Zenon.muted; onClicked: ann.copy() }
      DialogButton { label: "Save New"; ink: Zenon.white; onClicked: ann.saveNew() }
      DialogButton { label: "Save"; ink: Zenon.cyan; primary: true; ready: ann.dirty
                     onClicked: ann.saveTo(ann.path) }
    }

    // the same three as icons, the viewer's own glyphs where it has them
    Row {
      id: verbsNarrow
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      visible: bar.tight
      Repeater {
        model: [
          { g: "\uf0c5", name: "Copy", key: "", ink: Zenon.muted, live: true, act: () => ann.copy() },
          { g: "\uf0c7", name: "Save New", key: "", ink: Zenon.white, live: true, act: () => ann.saveNew() },
          { g: "\uf00c", name: "Save", key: "", ink: Zenon.cyan, live: ann.dirty, act: () => ann.saveTo(ann.path) }
        ]
        delegate: Rectangle {
          required property var modelData
          width: 34; height: 34; radius: Zenon.windowRadius
          color: verbMa.containsMouse && modelData.live ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
          Text {
            anchors.centerIn: parent
            text: modelData.g
            color: modelData.live ? modelData.ink : Zenon.muted
            opacity: modelData.live ? 1 : 0.5
            font.family: Zenon.face
            font.pixelSize: 15
          }
          MouseArea {
            id: verbMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: if (modelData.live) modelData.act()
            onContainsMouseChanged: containsMouse
              ? tips.show(parent, modelData.name, modelData.key) : tips.hide(parent)
          }
        }
      }
    }
  }

  // ── the picture ──────────────────────────────────────────────────
  Item {
    id: view
    anchors.top: bar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true

    Image {
      id: source
      source: ann.path !== "" ? Strings.fileUrl(ann.path) : ""
      visible: false
      cache: false
    }

    // the picture's own size, shown scaled to fit — never upscaled past
    // twice, which only makes a small picture blurry
    Item {
      id: paper
      width: source.implicitWidth
      height: source.implicitHeight
      // fitted to what is shown — the crop, once there is one
      readonly property var f: ann.shown
      readonly property real fit: f.w > 0
        ? Math.min(2, (view.width - 48) / f.w, (view.height - 48) / f.h) : 1
      transformOrigin: Item.TopLeft
      scale: paper.fit
      x: Math.round((view.width - f.w * fit) / 2 - f.x * fit)
      y: Math.round((view.height - f.h * fit) / 2 - f.y * fit)
      Behavior on scale { enabled: ann.glide; NumberAnimation { duration: Zenon.slow; easing.type: Easing.OutCubic } }
      Behavior on x { enabled: ann.glide; NumberAnimation { duration: Zenon.slow; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: ann.glide; NumberAnimation { duration: Zenon.slow; easing.type: Easing.OutCubic } }

      Rectangle {
        x: paper.f.x; y: paper.f.y; width: paper.f.w; height: paper.f.h
        anchors.margins: -1 / paper.fit
        color: "transparent"
        border.width: 1 / paper.fit
        border.color: Zenon.border
      }

      // Everything committed, the picture underneath — and what is saved.
      // Only what is shown, from its corner: cropped, the canvas IS the crop.
      Canvas {
        id: done
        x: paper.f.x; y: paper.f.y; width: paper.f.w; height: paper.f.h
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        property bool loaded: false
        // a new size not painted yet — saving waits for it (whenPainted)
        property bool stale: false
        property var after: null
        readonly property var at: paper.f
        onAtChanged: { done.stale = true; requestPaint(); }
        Component.onCompleted: loadImage(source.source)
        onImageLoaded: { done.loaded = true; requestPaint(); }
        onPaint: {
          const ctx = getContext("2d");
          ctx.save();
          ctx.clearRect(0, 0, width, height);
          ctx.translate(-done.x, -done.y);
          if (done.loaded) ctx.drawImage(source.source, 0, 0, paper.width, paper.height);
          let spotted = false;
          for (const m of ann.marks) {
            if (m.kind !== "spot") { ann.drawMark(ctx, m); continue; }
            if (spotted) continue;
            spotted = true;
            ann.drawSpots(ctx, ann.marks.filter((k) => k.kind === "spot"));
          }
          ctx.restore();
        }
        onPainted: {
          done.stale = false;
          const f = done.after;
          done.after = null;
          if (f) f();
        }
      }

      // The mark in the hand, on its own layer so drawing it does not
      // repaint the picture every move.
      // cut to the crop too, so a stroke run past it is seen to stop there
      Item {
        x: paper.f.x; y: paper.f.y; width: paper.f.w; height: paper.f.h
        clip: true
        Canvas {
          id: liveInk
          x: -parent.x; y: -parent.y
          width: paper.width; height: paper.height
          renderStrategy: Canvas.Immediate
          onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (ann.live) ann.drawMark(ctx, ann.live);
          }
        }
      }

      // ── the tool, under the pointer ──────────────────────────────────
      // The brush as a ring its own size and ink (a highlighter's band
      // filled, as it will lay down); the next numbered marker, faint,
      // where a click will put it. In the picture's pixels, like the marks.
      Item {
        id: brush
        readonly property bool stroked: ["pen", "highlight", "line", "arrow", "rect", "ellipse"].indexOf(ann.tool) >= 0
        visible: drawMa.containsMouse && !ann.cropping && (brush.stroked || ann.tool === "number")
        x: ann.hoverAt.x
        y: ann.hoverAt.y
        // never smaller than a few screen pixels, to be seen at all
        readonly property real d: Math.max(ann.tool === "highlight" ? ann.stroke * 3.5 : ann.stroke, 8 / paper.fit)
        Rectangle {
          visible: brush.stroked
          x: -width / 2; y: -height / 2
          width: brush.d + 2 / paper.fit; height: width; radius: width / 2
          color: "transparent"
          border.width: 1 / paper.fit
          border.color: Qt.rgba(0, 0, 0, 0.5)
        }
        Rectangle {
          visible: brush.stroked
          x: -width / 2; y: -height / 2
          width: brush.d; height: width; radius: width / 2
          color: ann.tool === "highlight" ? Qt.rgba(ann.ink.r, ann.ink.g, ann.ink.b, 0.35) : "transparent"
          border.width: 1.5 / paper.fit
          border.color: ann.ink
        }
        Rectangle {
          visible: ann.tool === "number" && !drawMa.pressed
          readonly property real r: ann.textPx * 0.7
          x: -r; y: -r
          width: r * 2; height: r * 2; radius: r
          color: ann.ink
          opacity: 0.45
          Text {
            anchors.centerIn: parent
            text: ann.nextNumber
            color: Cap.inkOn(ann.rgbOf(ann.ink)[0], ann.rgbOf(ann.ink)[1], ann.rgbOf(ann.ink)[2])
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: parent.r * 1.1
          }
        }
      }

      MouseArea {
        id: drawMa
        anchors.fill: parent
        enabled: !textEdit.visible && !ann.cropping
        hoverEnabled: true
        cursorShape: ann.tool === "text" ? Qt.IBeamCursor
          : brush.stroked || ann.tool === "number" ? Qt.BlankCursor : Qt.CrossCursor
        property real sx: 0
        property real sy: 0

        function constrain(m, x, y) {
          if (!(m.modifiers & Qt.ShiftModifier)) return [x, y];
          const dx = x - sx, dy = y - sy;
          if (ann.tool === "rect" || ann.tool === "ellipse" || ann.tool === "pixelate" || ann.tool === "spot") {
            const s = Math.max(Math.abs(dx), Math.abs(dy));
            return [sx + Math.sign(dx || 1) * s, sy + Math.sign(dy || 1) * s];
          }
          // lines to the nearest 45°
          const a = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
          const len = Math.sqrt(dx * dx + dy * dy);
          return [sx + Math.cos(a) * len, sy + Math.sin(a) * len];
        }

        onPressed: (m) => {
          keys.forceActiveFocus();
          sx = m.x; sy = m.y;
          const c = ann.cssOf(ann.ink);
          if (ann.tool === "text") {
            textEdit.at = Qt.point(m.x, m.y);
            textEdit.text = "";
            textEdit.visible = true;
            textEdit.forceActiveFocus();
            return;
          }
          if (ann.tool === "number") {
            ann.commit({ kind: "number", x1: m.x, y1: m.y, r: ann.textPx * 0.7,
                         n: ann.nextNumber, ink: c, rgb: ann.rgbOf(ann.ink), w: 0 });
            ann.nextNumber++;
            return;
          }
          ann.live = { kind: ann.tool, ink: c, w: ann.stroke,
                       round: ann.rounded ? Math.max(10 * ann.unit, ann.stroke * 3) : 0,
                       x1: m.x, y1: m.y, x2: m.x, y2: m.y, pts: [m.x, m.y] };
          liveInk.requestPaint();
        }
        onPositionChanged: (m) => {
          ann.hoverAt = Qt.point(m.x, m.y);
          if (!ann.live) return;
          const l = ann.live;
          if (l.kind === "pen" || l.kind === "highlight") {
            l.pts.push(m.x, m.y);
          } else {
            const p = constrain(m, m.x, m.y);
            l.x2 = p[0]; l.y2 = p[1];
          }
          liveInk.requestPaint();
        }
        onReleased: (m) => {
          const l = ann.live;
          ann.live = null;
          liveInk.requestPaint();
          if (!l) return;
          const big = Math.abs(l.x2 - l.x1) > 2 || Math.abs(l.y2 - l.y1) > 2 || l.pts.length > 4;
          if (!big) return;
          if (l.kind === "pixelate")
            l.cells = ann.pixelCells(Math.min(l.x1, l.x2), Math.min(l.y1, l.y2),
                                     Math.abs(l.x2 - l.x1), Math.abs(l.y2 - l.y1));
          ann.commit(l);
        }
      }

      // typing a text mark, where it will be drawn and at its size
      TextEdit {
        id: textEdit
        visible: false
        property point at: Qt.point(0, 0)
        x: at.x
        y: at.y
        width: Math.max(40, contentWidth + 4)
        color: ann.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: ann.textPx
        selectionColor: Zenon.selBg
        Rectangle {
          anchors.fill: parent
          anchors.margins: -4
          z: -1
          color: "transparent"
          border.width: 1 / paper.fit
          border.color: Zenon.cyan
        }
        function finish(keep) {
          const t = textEdit.text.replace(/\s+$/, "");
          textEdit.visible = false;
          keys.forceActiveFocus();
          if (keep && t !== "")
            ann.commit({ kind: "text", x1: textEdit.at.x, y1: textEdit.at.y, text: t,
                         px: ann.textPx, ink: ann.cssOf(ann.ink), w: 0 });
        }
        Keys.onPressed: (e) => {
          if (e.key === Qt.Key_Escape) { e.accepted = true; textEdit.finish(false); }
          // Return ends it; shift+Return is a new line
          else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                   && !(e.modifiers & Qt.ShiftModifier)) { e.accepted = true; textEdit.finish(true); }
        }
        onActiveFocusChanged: if (!activeFocus && visible) textEdit.finish(true)
      }
    }

    // ── the crop box, while the crop tool is in the hand ──────────────
    // The viewer's own: the rest darkened, thirds, a body that moves and
    // grips that resize. Shift keeps it square. Return or another tool
    // applies it, esc puts it back, ⌫ lets go of it.
    Item {
      id: cropLayer
      x: paper.x; y: paper.y
      width: paper.width * paper.fit; height: paper.height * paper.fit
      visible: ann.cropping
      readonly property real k: paper.fit
      readonly property var r: ann.draft || ann.whole
      readonly property real tw: paper.width
      readonly property real th: paper.height
      function square(r, edge, m) {
        return (m.modifiers & Qt.ShiftModifier) ? V.fitAspect(r, edge, 1, tw, th) : r;
      }

      Rectangle { x: 0; y: 0; width: parent.width; height: cropLayer.r.y * cropLayer.k; color: "#99000000" }
      Rectangle { x: 0; y: (cropLayer.r.y + cropLayer.r.h) * cropLayer.k; width: parent.width
                  height: parent.height - y; color: "#99000000" }
      Rectangle { x: 0; y: cropLayer.r.y * cropLayer.k; width: cropLayer.r.x * cropLayer.k
                  height: cropLayer.r.h * cropLayer.k; color: "#99000000" }
      Rectangle { x: (cropLayer.r.x + cropLayer.r.w) * cropLayer.k; y: cropLayer.r.y * cropLayer.k
                  width: parent.width - x; height: cropLayer.r.h * cropLayer.k; color: "#99000000" }

      // a fresh box, dragged out anywhere
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        property real ax: 0
        property real ay: 0
        onPressed: (m) => { keys.forceActiveFocus(); ax = m.x / cropLayer.k; ay = m.y / cropLayer.k; }
        onPositionChanged: (m) => {
          const cx = m.x / cropLayer.k, cy = m.y / cropLayer.k;
          const r = cropLayer.square(Cap.rectOf(ax, ay, cx, cy, cropLayer.tw, cropLayer.th),
                                     (cx < ax ? "l" : "r") + (cy < ay ? "t" : "b"), m);
          if (r.w >= 4 && r.h >= 4) ann.draft = r;
        }
      }

      Rectangle {
        id: cropBox
        x: cropLayer.r.x * cropLayer.k
        y: cropLayer.r.y * cropLayer.k
        width: cropLayer.r.w * cropLayer.k
        height: cropLayer.r.h * cropLayer.k
        color: "transparent"
        border.width: 1
        border.color: Zenon.cyan

        Repeater {
          model: 2
          Rectangle { required property int index; x: cropBox.width * (index + 1) / 3; width: 1
                      height: cropBox.height; color: Qt.rgba(1, 1, 1, 0.25) }
        }
        Repeater {
          model: 2
          Rectangle { required property int index; y: cropBox.height * (index + 1) / 3; height: 1
                      width: cropBox.width; color: Qt.rgba(1, 1, 1, 0.25) }
        }

        Repeater {
          model: ["move", "tl", "t", "tr", "l", "r", "bl", "b", "br"]
          delegate: MouseArea {
            id: grip
            required property string modelData
            readonly property bool body: grip.modelData === "move"
            readonly property real gx: grip.modelData.indexOf("l") >= 0 ? 0
              : grip.modelData.indexOf("r") >= 0 ? cropBox.width : cropBox.width / 2
            readonly property real gy: grip.modelData.indexOf("t") >= 0 ? 0
              : grip.modelData.indexOf("b") >= 0 ? cropBox.height : cropBox.height / 2
            x: grip.body ? 0 : grip.gx - 9
            y: grip.body ? 0 : grip.gy - 9
            width: grip.body ? cropBox.width : 18
            height: grip.body ? cropBox.height : 18
            z: grip.body ? 0 : 1
            cursorShape: grip.body ? Qt.SizeAllCursor
              : (grip.modelData === "tl" || grip.modelData === "br") ? Qt.SizeFDiagCursor
              : (grip.modelData === "tr" || grip.modelData === "bl") ? Qt.SizeBDiagCursor
              : (grip.modelData === "l" || grip.modelData === "r") ? Qt.SizeHorCursor : Qt.SizeVerCursor
            property var r0: null
            property point p0
            onPressed: (m) => {
              keys.forceActiveFocus();
              grip.r0 = cropLayer.r;
              grip.p0 = grip.mapToItem(cropLayer, m.x, m.y);
            }
            onPositionChanged: (m) => {
              if (!grip.r0) return;
              const p = grip.mapToItem(cropLayer, m.x, m.y);
              const dx = (p.x - grip.p0.x) / cropLayer.k, dy = (p.y - grip.p0.y) / cropLayer.k;
              if (grip.body) { ann.draft = Cap.moveRect(grip.r0, dx, dy, cropLayer.tw, cropLayer.th); return; }
              const r = cropLayer.square(Cap.resizeRect(grip.r0, grip.modelData, dx, dy,
                                                        cropLayer.tw, cropLayer.th), grip.modelData, m);
              if (r.w >= 4 && r.h >= 4) ann.draft = r;
            }
            onReleased: grip.r0 = null
            // a double click on the box applies it
            onDoubleClicked: if (grip.body) ann.tool = ann.back
            Rectangle {
              visible: !grip.body
              anchors.centerIn: parent
              width: 10; height: 10; radius: 2
              color: Zenon.cyan
              border.width: 1
              border.color: "#000000"
            }
          }
        }
      }

      // the size it will be saved at
      Rectangle {
        x: cropBox.x + 6
        y: Math.max(6, cropBox.y - height - 6)
        width: cropSize.implicitWidth + 12
        height: 22
        radius: 4
        color: "#cc000000"
        Text {
          id: cropSize
          anchors.centerIn: parent
          text: Math.round(cropLayer.r.w) + " × " + Math.round(cropLayer.r.h)
          color: Zenon.white
          font.family: Zenon.face
          font.pixelSize: 12
        }
      }
    }

    // what the keys do, while cropping
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 12
      visible: ann.cropping
      width: cropHint.implicitWidth + 20
      height: 26
      radius: 13
      color: "#cc000000"
      Text {
        id: cropHint
        anchors.centerIn: parent
        text: "return apply  ·  esc cancel  ·  ⌫ whole picture  ·  shift square"
        color: Zenon.muted
        font.family: Zenon.face
        font.pixelSize: 12
      }
    }
  }

  // ── closing with changes ─────────────────────────────────────────
  Item {
    id: discard
    anchors.fill: parent
    z: 11
    property bool open: false
    visible: discardSheet.cardInk > 0.01 || discard.open
    InputShield { visible: discard.open; onClicked: discard.open = false }
    Sheet {
      backdrop: view   // frosted over it — see morpheus/Sheet
      id: discardSheet
      shown: discard.open
      fromTop: bar.height
      cardW: 420
      cardH: 120
      Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 18
        text: "Close without saving the marks?"
        color: Zenon.white
        font.family: Zenon.face
        font.pixelSize: 16
      }
      Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        spacing: 8
        DialogButton { label: "Keep editing"; ink: Zenon.muted; onClicked: discard.open = false }
        DialogButton { label: "Discard"; ink: Zenon.red; primary: true
                       onClicked: { discard.open = false; ann.dirty = false; ann.finished(); } }
      }
      Item {
        id: discardKeys
        Keys.onPressed: (e) => {
          e.accepted = true;
          if (e.key === Qt.Key_Escape) discard.open = false;
          else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { discard.open = false; ann.dirty = false; ann.finished(); }
        }
      }
    }
    onOpenChanged: open ? discardKeys.forceActiveFocus() : keys.forceActiveFocus()
  }
}
