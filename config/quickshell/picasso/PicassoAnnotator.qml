// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE ANNOTATION WINDOW. Opened by clicking a screenshot's toast, or by
// terminus' Annotate on any picture — never by itself.
//
// Everything is drawn onto a canvas at the picture's OWN resolution: the
// picture first, then each mark in order. The window shows that canvas
// scaled to fit, and saving writes the canvas as it is — so a mark drawn on
// a scaled-down view of a 2560-wide screenshot is saved at 2560, not at the
// size it happened to be on screen.
//
//   Save       over the picture it opened
//   Save New   a new file, through terminus' own save dialog — opened in
//              Screenshots with a name already in it, so Return takes the
//              default and anywhere else is a walk through the folders
//   Copy       the annotated picture to the clipboard
//
// Tools on keys as well as buttons: p pen, h highlighter, l line, a arrow,
// r rectangle, e ellipse, t text, n numbered marker, x pixelate. Shift
// holds a line to 45° and a box to a square. ctrl+z / ctrl+shift+z undo and
// redo, ctrl+s save, ctrl+shift+s save new, ctrl+c copy, esc close.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "capture.js" as Cap

Scope {
  id: mgr

  // terminus, handed in by shell.qml, for Save New's dialog
  property var fileManager: null

  Connections {
    target: Picasso
    function onAnnotateRequested(path) { mgr.open(path); }
  }

  function open(path) {
    const w = winComp.createObject(mgr, { path: String(path) });
    if (w) w.visible = true;
  }

  Component {
    id: winComp

    FloatingWindow {
      id: win
      title: "picasso-annotate"
      color: Zenon.layerBg
      implicitWidth: 1400
      implicitHeight: 900
      minimumSize: Qt.size(760, 480)

      property string path: ""
      // A closed window is done with, not hidden: each annotation is its own.
      onVisibleChanged: if (!win.visible) Qt.callLater(() => win.destroy())

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
      readonly property real stroke: [3, 6, 12][win.size] * win.unit
      readonly property real textPx: [22, 34, 52][win.size] * win.unit

      function commit(m) {
        const next = win.marks.slice();
        next.push(m);
        win.marks = next;
        win.undone = [];
        win.dirty = true;
        done.requestPaint();
      }
      function undo() {
        if (win.marks.length === 0) return;
        const m = win.marks.slice(), u = win.undone.slice();
        u.push(m.pop());
        win.marks = m; win.undone = u; win.dirty = true;
        win.renumber();
        done.requestPaint();
      }
      function redo() {
        if (win.undone.length === 0) return;
        const m = win.marks.slice(), u = win.undone.slice();
        m.push(u.pop());
        win.marks = m; win.undone = u; win.dirty = true;
        win.renumber();
        done.requestPaint();
      }
      function renumber() {
        let n = 1;
        for (const m of win.marks) if (m.kind === "number") n = Math.max(n, m.n + 1);
        win.nextNumber = n;
      }

      // ── saving ───────────────────────────────────────────────────────
      property string note: ""
      property string tip: ""
      Timer { id: noteClear; interval: 3000; onTriggered: win.note = "" }
      function say(t) { win.note = t; noteClear.restart(); }

      function saveTo(file) {
        if (!done.save(file)) { win.say("could not save to " + file); return false; }
        win.dirty = false;
        win.say("saved · " + file.replace(Quickshell.env("HOME"), "~"));
        return true;
      }
      function copy() {
        const tmp = Paths.runtimeDir() + "/picasso/annotated-" + Date.now() + ".png";
        Quickshell.execDetached(["mkdir", "-p", Paths.runtimeDir() + "/picasso"]);
        if (!done.save(tmp)) { win.say("could not copy"); return; }
        Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < "
          + Strings.shellQuote(tmp) + "; rm -f " + Strings.shellQuote(tmp)]);
        win.say("copied to the clipboard");
      }

      // Save New asks terminus' picker for a path — its save dialog, the
      // one applications get — and writes the canvas there when it answers.
      function saveNew() {
        const fm = mgr.fileManager;
        if (!fm) { win.say("no file manager to ask"); return; }
        const ok = fm.choose(false, Picasso.shotDir, (paths) => {
          if (paths.length === 0) return;
          let f = String(paths[0]);
          if (!/\.(png|jpe?g|webp|bmp)$/i.test(f)) f += ".png";
          win.saveTo(f);
        }, Cap.annotatedName(win.path));
        if (!ok) win.say("the file picker is busy with another request");
      }

      function close() {
        if (win.dirty && !discard.open) { discard.open = true; return; }
        win.visible = false;
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
          const head = Math.max(14 * win.unit, m.w * 4);
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
            ctx.lineWidth = 2 * win.unit;
            ctx.strokeStyle = "rgba(255,255,255,0.8)";
            ctx.setLineDash([6 * win.unit, 4 * win.unit]);
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
      function cssOf(c) { return "rgba(" + win.rgbOf(c).join(",") + "," + c.a + ")"; }

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
          if (ctrl && e.key === Qt.Key_Z) { shift ? win.redo() : win.undo(); return; }
          if (ctrl && e.key === Qt.Key_Y) { win.redo(); return; }
          if (ctrl && e.key === Qt.Key_S) { shift ? win.saveNew() : win.saveTo(win.path); return; }
          if (ctrl && e.key === Qt.Key_C) { win.copy(); return; }
          if (e.key === Qt.Key_Escape) { win.close(); return; }
          if (e.key === Qt.Key_BracketLeft) { win.size = Math.max(0, win.size - 1); return; }
          if (e.key === Qt.Key_BracketRight) { win.size = Math.min(2, win.size + 1); return; }
          for (const t of win.tools) if (e.text === t[2]) { win.tool = t[0]; return; }
          const n = parseInt(e.text, 10);
          if (n >= 1 && n <= win.inks.length) { win.ink = win.inks[n - 1]; return; }
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

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 14

          // tools
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
              model: win.tools
              delegate: Rectangle {
                required property var modelData
                readonly property bool on: win.tool === modelData[0]
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
                  onClicked: win.tool = modelData[0]
                }
                // named in the bar while hovered — a window has no tooltip
                // layer of its own to put it on
                Connections {
                  target: toolMa
                  function onContainsMouseChanged() {
                    if (toolMa.containsMouse) win.tip = modelData[3] + "  \u00b7  " + modelData[2];
                    else if (win.tip.indexOf(modelData[3] + " ") === 0) win.tip = "";
                  }
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
              model: win.inks
              delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool on: Qt.colorEqual(win.ink, modelData)
                width: 22; height: 22; radius: 11
                color: modelData
                border.width: on ? 2 : 1
                border.color: on ? Zenon.white : Zenon.border
                scale: on ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: Zenon.fast } }
                MouseArea { anchors.fill: parent; onClicked: win.ink = modelData }
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
                color: win.size === index ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                Rectangle {
                  anchors.centerIn: parent
                  width: [5, 9, 14][index]; height: width; radius: width / 2
                  color: win.size === index ? Zenon.white : Zenon.muted
                }
                MouseArea { anchors.fill: parent; onClicked: win.size = index }
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
                readonly property bool can: modelData[1] === "undo" ? win.marks.length > 0 : win.undone.length > 0
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
                  onClicked: modelData[1] === "undo" ? win.undo() : win.redo()
                }
              }
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: win.note !== "" ? win.note : win.tip
            color: win.note !== "" ? Zenon.sand : Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 13
            rightPadding: 6
          }
          DialogButton { label: "Copy"; ink: Zenon.muted; onClicked: win.copy() }
          DialogButton { label: "Save New"; ink: Zenon.white; onClicked: win.saveNew() }
          DialogButton { label: "Save"; ink: Zenon.cyan; primary: true; ready: win.dirty
                         onClicked: win.saveTo(win.path) }
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
          source: win.path !== "" ? "file://" + win.path : ""
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
              for (const m of win.marks) win.drawMark(ctx, m);
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
              if (win.live) win.drawMark(ctx, win.live);
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: !textEdit.visible
            cursorShape: win.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
            property real sx: 0
            property real sy: 0

            function constrain(m, x, y) {
              if (!(m.modifiers & Qt.ShiftModifier)) return [x, y];
              const dx = x - sx, dy = y - sy;
              if (win.tool === "rect" || win.tool === "ellipse" || win.tool === "pixelate") {
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
              const c = win.cssOf(win.ink);
              if (win.tool === "text") {
                textEdit.at = Qt.point(m.x, m.y);
                textEdit.text = "";
                textEdit.visible = true;
                textEdit.forceActiveFocus();
                return;
              }
              if (win.tool === "number") {
                win.commit({ kind: "number", x1: m.x, y1: m.y, r: win.textPx * 0.7,
                             n: win.nextNumber, ink: c, rgb: win.rgbOf(win.ink), w: 0 });
                win.nextNumber++;
                return;
              }
              win.live = { kind: win.tool, ink: c, w: win.stroke,
                           x1: m.x, y1: m.y, x2: m.x, y2: m.y, pts: [m.x, m.y] };
              liveInk.requestPaint();
            }
            onPositionChanged: (m) => {
              if (!win.live) return;
              const l = win.live;
              if (l.kind === "pen" || l.kind === "highlight") {
                l.pts.push(m.x, m.y);
              } else {
                const p = constrain(m, m.x, m.y);
                l.x2 = p[0]; l.y2 = p[1];
              }
              liveInk.requestPaint();
            }
            onReleased: (m) => {
              const l = win.live;
              win.live = null;
              liveInk.requestPaint();
              if (!l) return;
              const big = Math.abs(l.x2 - l.x1) > 2 || Math.abs(l.y2 - l.y1) > 2 || l.pts.length > 4;
              if (!big) return;
              if (l.kind === "pixelate")
                l.cells = win.pixelCells(Math.min(l.x1, l.x2), Math.min(l.y1, l.y2),
                                         Math.abs(l.x2 - l.x1), Math.abs(l.y2 - l.y1));
              win.commit(l);
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
            color: win.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: win.textPx
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
                win.commit({ kind: "text", x1: textEdit.at.x, y1: textEdit.at.y, text: t,
                             px: win.textPx, ink: win.cssOf(win.ink), w: 0 });
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
                           onClicked: { discard.open = false; win.dirty = false; win.visible = false; } }
          }
          Item {
            id: discardKeys
            Keys.onPressed: (e) => {
              e.accepted = true;
              if (e.key === Qt.Key_Escape) discard.open = false;
              else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.dirty = false; win.visible = false; }
            }
          }
        }
        onOpenChanged: open ? discardKeys.forceActiveFocus() : keys.forceActiveFocus()
      }
    }
  }
}
