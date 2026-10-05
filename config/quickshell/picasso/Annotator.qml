// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ANNOTATION — the viewer's drawing mode. Reached from the viewer's own
// Annotate (a), and from everything that used to open a window of its own
// for this: a screenshot's toast, terminus' and folio's Annotate. Those all
// still say Picasso.annotate(path); the viewer answers it by opening on that
// picture, in this mode, with the picture's folder around it.
//
// Everything is drawn onto a canvas at the picture's OWN resolution: the
// picture first, then each mark in order. The window shows that canvas
// scaled to fit, and saving writes the canvas as it is — so a mark drawn on
// a scaled-down view of a 2560-wide screenshot is saved at 2560, not at the
// size it happened to be on screen.
//
//   Save       over the picture it opened
//   Save New   a new file, through terminus' own save dialog — opened in
//              the picture's own folder with a name already in it, so Return
//              takes the default and anywhere else is a walk through folders
//   Copy       the annotated picture to the clipboard
//
// Tools on keys as well as buttons: p pen, h highlighter, l line, a arrow,
// r rectangle, e ellipse, t text, n numbered marker, x pixelate. Shift
// holds a line to 45° and a box to a square. ctrl+z / ctrl+shift+z undo and
// redo, ctrl+s save, ctrl+shift+s save new, ctrl+c copy, esc back to the
// viewer — asking first when there are marks nobody saved.

import QtQuick
import Quickshell
import "../morpheus"
import "capture.js" as Cap

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

  readonly property var tools: [
    ["pen",       "", "p", "Pen"],
    ["highlight", "", "h", "Highlighter"],
    ["line",      "", "l", "Line"],
    ["arrow",     "", "a", "Arrow"],
    ["rect",      "", "r", "Rectangle"],
    ["ellipse",   "", "e", "Ellipse"],
    ["text",      "", "t", "Text"],
    ["number",    "", "n", "Numbered marker"],
    ["pixelate",  "", "x", "Pixelate"]
  ]
  readonly property var inks: [Zenon.red, Zenon.yellow, Zenon.green, Zenon.cyan,
                               Zenon.blue, Zenon.magenta, "#ffffff", "#000000"]

  // Sizes in the PICTURE's pixels, scaled to how big the picture is, so
  // "medium" means the same thing on a 1080p shot and a 4K one.
  readonly property real unit: Math.max(1, paper.width / 1600)
  readonly property real stroke: [3, 6, 12][ann.size] * ann.unit
  readonly property real textPx: [22, 34, 52][ann.size] * ann.unit

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
    ann.renumber();
    done.requestPaint();
  }
  function redo() {
    if (ann.undone.length === 0) return;
    const m = ann.marks.slice(), u = ann.undone.slice();
    m.push(u.pop());
    ann.marks = m; ann.undone = u; ann.dirty = true;
    ann.renumber();
    done.requestPaint();
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
  function write_(file) {
    if (!done.save(file)) { ann.say("could not save to " + file); return false; }
    ann.dirty = false;
    ann.saved(file);
    ann.say("saved · " + file.replace(Quickshell.env("HOME"), "~"));
    return true;
  }
  function copy() {
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
      ctx.strokeRect(nx, ny, nw, nh);
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

  // The blocks a pixelate mark paints, read off what is drawn now.
  function pixelCells(x, y, w, h) {
    x = Math.round(x); y = Math.round(y); w = Math.round(w); h = Math.round(h);
    if (w < 2 || h < 2) return [];
    const b = Math.max(8, Math.round(Math.min(paper.width, paper.height) / 90));
    const d = done.getContext("2d").getImageData(x, y, w, h).data;
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
      if (e.key === Qt.Key_Escape) { ann.close(); return; }
      if (e.key === Qt.Key_BracketLeft) { ann.size = Math.max(0, ann.size - 1); return; }
      if (e.key === Qt.Key_BracketRight) { ann.size = Math.min(2, ann.size + 1); return; }
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
              onClicked: ann.tool = modelData[0]
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
      readonly property real fit: width > 0
        ? Math.min(2, (view.width - 48) / width, (view.height - 48) / height) : 1
      transformOrigin: Item.TopLeft
      scale: paper.fit
      x: Math.round((view.width - width * fit) / 2)
      y: Math.round((view.height - height * fit) / 2)

      Rectangle {
        anchors.fill: parent
        anchors.margins: -1 / paper.fit
        color: "transparent"
        border.width: 1 / paper.fit
        border.color: Zenon.border
      }

      // Everything committed, the picture underneath — and what is saved.
      Canvas {
        id: done
        anchors.fill: parent
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        property bool loaded: false
        Component.onCompleted: loadImage(source.source)
        onImageLoaded: { done.loaded = true; requestPaint(); }
        onPaint: {
          const ctx = getContext("2d");
          ctx.clearRect(0, 0, width, height);
          if (done.loaded) ctx.drawImage(source.source, 0, 0, width, height);
          for (const m of ann.marks) ann.drawMark(ctx, m);
        }
      }

      // The mark in the hand, on its own layer so drawing it does not
      // repaint the picture every move.
      Canvas {
        id: liveInk
        anchors.fill: parent
        renderStrategy: Canvas.Immediate
        onPaint: {
          const ctx = getContext("2d");
          ctx.clearRect(0, 0, width, height);
          if (ann.live) ann.drawMark(ctx, ann.live);
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: !textEdit.visible
        cursorShape: ann.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
        property real sx: 0
        property real sy: 0

        function constrain(m, x, y) {
          if (!(m.modifiers & Qt.ShiftModifier)) return [x, y];
          const dx = x - sx, dy = y - sy;
          if (ann.tool === "rect" || ann.tool === "ellipse" || ann.tool === "pixelate") {
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
                       x1: m.x, y1: m.y, x2: m.x, y2: m.y, pts: [m.x, m.y] };
          liveInk.requestPaint();
        }
        onPositionChanged: (m) => {
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
