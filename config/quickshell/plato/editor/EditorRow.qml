// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One screen row: its gutter, and its text in colour.
//
// FOUR LAYERS, back to front: the backgrounds of its spans (a selection, a
// search match, a colour code's own colour), the text itself, and underlines
// — straight or curled, in the colour the highlight asks for, which is why
// they are drawn here rather than left to the text's own <u>: that one is
// always the text's colour and always straight, and a diagnostic's is neither.
//
// THE TEXT IS ONE ITEM. The spans become StyledText — <font>, <b>, <i>, <s> —
// and every space is &nbsp;: StyledText is HTML underneath and folds a run of
// spaces into one, which in a monospace grid moves everything after it.
// Measured: "a····b" drew three cells wide.
//
// WHOEVER HOLDS THE ROW SETS `info`. A window's rows are a pool its
// WindowView hands lines to (and moves, when the view scrolls); a float's
// rows arrive whole. Either way a row only re-lays its text when `info`
// changes — never because some other row did, or because the view moved.

import QtQuick
import QtQuick.Shapes
import "../../morpheus"
import "../../morpheus/icons.js" as Icons
import "cells.js" as Cells

Item {
  id: row

  required property var ed
  required property real cellW
  required property real cellH
  required property font face
  required property real gutterW
  required property real textX

  property var info: ({ n: 0, k: 0, t: "", s: [], f: false })
  // which visible LINE this row belongs to (folds and wrapped lines are one),
  // and the cursor's: what relative numbers count. -1: not known (a row just
  // scrolled out, drawn while the glide finishes) — counted from the cursor's
  // buffer line instead.
  property int ord: -1
  property int curOrd: 0
  // nvim's 'relativenumber' for the window this row is in
  property bool relative: true
  // git's bar in the gutter (the settings' "Changes in the gutter")
  property bool gitGutter: true
  // zen mode: outside the cursor's paragraph, faded back
  property bool dimmed: false
  // the cursor's block (view.lua's scope): { col, first, last }, or null
  property var scope: null
  // arriving: 0 → 1 as a row a fold uncovered fades in (WindowView)
  property real enter: 1
  // the dimming eases on its own, so a fade-in is not eased a second time
  // the selection: drawn here as a rounded strip of this row's own (a
  // float's rows), unless the window draws one shape over all its rows
  property bool ownSelection: true
  // a row past the file's end shows a dim ~, as vim's do (a window's rows)
  property bool eofMark: false
  property real dimLevel: row.dimmed ? 0.3 : 1
  Behavior on dimLevel { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
  opacity: row.dimLevel * row.enter

  width: parent ? parent.width : 0
  height: row.cellH

  // a new colourscheme: same rows, other colours
  Connections {
    target: row.ed
    function onStylesReset() { row.infoChanged(); }
  }

  // ── git: a bar down the gutter's left edge ─────────────────────────
  // green added, yellow changed; lines deleted here, a red wedge at the
  // top of the line below them (see git.lua)
  Rectangle {
    visible: row.gitGutter && row.gutterW > 0 && !!row.info.v
    x: 1
    y: row.info.v === "d" ? 0 : 1
    width: row.info.v === "d" ? 5 : 3
    height: row.info.v === "d" ? 3 : row.cellH - 2
    radius: 1.5
    color: row.info.v === "a" ? Zenon.green : row.info.v === "c" ? Zenon.yellow : Zenon.red
    opacity: 0.85
  }

  // ── the gutter: a sign, then the number ────────────────────────────
  Text {
    visible: row.gutterW > 0 && row.info.g !== undefined && row.info.g !== null
    x: 0
    width: row.cellW * 2
    height: row.cellH
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font: row.face
    textFormat: Text.PlainText
    text: visible ? row.info.g[0] : ""
    color: {
      if (!visible) return row.ed.lineNrFg;
      const st = row.ed.styles[row.info.g[1]];
      return st && st.fg ? st.fg : row.ed.lineNrFg;
    }
  }
  // Relative numbers with the current line's own, as the terminal nvim has
  // them — counted in lines, so a wrapped line or a fold is one — or every
  // line its own number, with 'relativenumber' off. A wrapped line's
  // continuation rows carry none.
  //
  // KEPT CLEAR OF THE TEXT: three cells between the number and the line,
  // where the gutter has room for them (nvim's 'numberwidth' is set to leave
  // it), and never less than one.
  Text {
    id: number
    visible: row.gutterW > 0
    readonly property int rel: row.ord >= 0 ? Math.abs(row.ord - row.curOrd)
      : Math.abs(row.info.n - row.ed.line)
    readonly property bool own: !row.relative || number.rel === 0
    text: row.info.n === 0 || row.info.k !== 0 ? "" : String(number.own ? row.info.n : number.rel)
    readonly property real gap: Math.max(1, Math.min(3,
      Math.round(row.gutterW / row.cellW) - 2 - number.text.length)) * row.cellW
    x: row.cellW * 2
    width: Math.max(0, row.gutterW - row.cellW * 2 - number.gap)
    height: row.cellH
    horizontalAlignment: Text.AlignRight
    verticalAlignment: Text.AlignVCenter
    font.family: row.face.family
    font.pixelSize: row.face.pixelSize
    font.weight: number.rel === 0 ? Font.Bold : row.face.weight
    textFormat: Text.PlainText
    color: number.rel === 0 ? row.ed.numberHere : row.ed.lineNrFg
    // QUIETER FURTHER OUT: the numbers near the cursor are the ones a
    // count is read off; the rest step back, to half strength
    opacity: number.rel === 0 ? 1 : Math.max(0.5, 1 - number.rel * 0.04)
  }

  // ── rendered markdown's blocks (view.lua's `md`) ───────────────────
  // Drawn under the text: a heading's band, fading out to the right with an
  // accent at its start; a code block's framed panel and its language in
  // the corner; a quote's bars, a callout tinted in its colour; a table's
  // frame, its header lit and its rows striped; a rule that fades at both
  // ends. A block that spans rows is one shape: each row draws its slice of
  // a taller rounded rectangle, and only the block's first and last rows
  // show its corners.
  readonly property var md: row.info.md || null
  readonly property var mdQ: row.md && row.md.q ? row.md.q : null
  readonly property var mdT: row.md && row.md.tb ? row.md.tb : null
  function headInk(n) {
    return [Zenon.magenta, Zenon.blue, Zenon.cyan, Zenon.green, Zenon.yellow, Zenon.pink][Math.max(0, Math.min(5, n - 1))];
  }
  function calloutInk(k) {
    return k === "note" ? Zenon.blue : k === "tip" ? Zenon.green : k === "important" ? Zenon.magenta
      : k === "warning" ? Zenon.yellow : k === "caution" ? Zenon.red : Zenon.muted;
  }
  function has(e, c) { return !!e && e.indexOf(c) >= 0; }
  // the glyph for a code block's language: the file tree's, for a file of it
  function langGlyph(lang) {
    const l = String(lang || "").toLowerCase();
    const ext = ({ python: "py", javascript: "js", typescript: "ts", rust: "rs", bash: "sh",
      shell: "sh", zsh: "sh", console: "sh", markdown: "md", yaml: "yml", ruby: "rb",
      golang: "go", "c++": "cpp", csharp: "cs", kotlin: "kt", haskell: "hs",
      "front matter": "yml" })[l] || l;
    return ext ? Icons.glyphFor({ name: "x." + ext }) : "";
  }

  // a heading
  Item {
    id: headBand
    visible: row.md !== null && row.md.k === "h"
    readonly property color ink: visible ? row.headInk(row.md.n) : "transparent"
    readonly property real strength: visible ? [0.24, 0.18, 0.13, 0.1, 0.08, 0.07][Math.min(5, row.md.n - 1)] : 0
    x: row.textX - row.cellW * 0.6
    width: Math.max(0, row.width - x - row.cellW * 0.5)
    height: row.cellH
    Rectangle {
      anchors.fill: parent
      radius: 4
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Qt.rgba(headBand.ink.r, headBand.ink.g, headBand.ink.b, headBand.strength) }
        GradientStop { position: 0.75; color: Qt.rgba(headBand.ink.r, headBand.ink.g, headBand.ink.b, 0) }
      }
    }
    Rectangle {
      x: 0
      y: 3
      width: 3
      height: parent.height - 6
      radius: 1.5
      color: parent.ink
    }
  }

  // a code block, or front matter
  Item {
    id: codePanel
    visible: row.md !== null && row.md.k === "c"
    readonly property bool atTop: visible && row.has(row.md.e, "t")
    readonly property bool atBottom: visible && row.has(row.md.e, "b")
    x: row.textX + (visible ? row.md.x : 0) * row.cellW - row.cellW * 0.6
    width: Math.max(0, row.width - x - row.cellW * 0.5)
    height: row.cellH
    clip: true
    Rectangle {
      y: codePanel.atTop ? 1 : -8
      width: parent.width
      height: parent.height + (codePanel.atTop ? -1 : 8) + (codePanel.atBottom ? -1 : 8)
      radius: 6
      color: Qt.rgba(1, 1, 1, 0.04)
      border.width: 1
      border.color: Zenon.border
    }
    // the language, quiet, in the panel's top right corner
    Row {
      visible: codePanel.visible && !!row.md.lang
      anchors.right: parent.right
      anchors.rightMargin: row.cellW
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.round(row.cellW * 0.5)
      Text {
        readonly property string g: parent.visible ? row.langGlyph(row.md.lang) : ""
        visible: g !== ""
        text: g
        font.family: row.face.family
        font.pixelSize: Math.round(row.face.pixelSize * 0.85)
        color: Zenon.muted
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: parent.visible ? row.md.lang : ""
        font.family: row.face.family
        font.pixelSize: Math.round(row.face.pixelSize * 0.8)
        color: Zenon.muted
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  // a quote: a callout's tint, then its bars
  Item {
    id: callout
    visible: row.mdQ !== null && !!row.mdQ.k && row.mdQ.b.length > 0
    readonly property color ink: visible ? row.calloutInk(row.mdQ.k) : "transparent"
    readonly property bool atTop: visible && row.has(row.mdQ.e, "t")
    readonly property bool atBottom: visible && row.has(row.mdQ.e, "b")
    x: visible ? row.textX + row.mdQ.b[0] * row.cellW : 0
    width: Math.max(0, row.width - x - row.cellW * 0.5)
    height: row.cellH
    clip: true
    Rectangle {
      y: callout.atTop ? 1 : -8
      width: parent.width
      height: parent.height + (callout.atTop ? -1 : 8) + (callout.atBottom ? -1 : 8)
      radius: 6
      color: Qt.rgba(callout.ink.r, callout.ink.g, callout.ink.b, 0.08)
    }
  }
  Repeater {
    model: row.mdQ ? row.mdQ.b : []
    Rectangle {
      required property var modelData
      required property int index
      readonly property bool atTop: row.has(row.mdQ.e, "t")
      readonly property bool atBottom: row.has(row.mdQ.e, "b")
      readonly property color ink: index === 0 && row.mdQ.k ? row.calloutInk(row.mdQ.k) : Zenon.muted
      x: Math.round(row.textX + modelData * row.cellW + row.cellW * 0.3)
      y: atTop ? 3 : 0
      width: 3
      height: row.cellH - (atTop ? 3 : 0) - (atBottom ? 3 : 0)
      radius: (atTop || atBottom) ? 1.5 : 0
      color: ink
      opacity: index === 0 && row.mdQ.k ? 1 : 0.7
    }
  }

  // a table: its frame, the header lit, every other row striped
  Item {
    id: tableFrame
    visible: row.mdT !== null
    readonly property bool atTop: visible && row.has(row.mdT.e, "t")
    readonly property bool atBottom: visible && row.has(row.mdT.e, "b")
    x: visible ? row.textX + (row.mdT.x + 0.5) * row.cellW : 0
    width: visible ? Math.max(0, (row.mdT.w - 1) * row.cellW + 1) : 0
    height: row.cellH
    clip: true
    Rectangle {
      y: tableFrame.atTop ? 0 : -8
      width: parent.width
      height: parent.height + (tableFrame.atTop ? 0 : 8) + (tableFrame.atBottom ? 0 : 8)
      radius: 6
      color: !tableFrame.visible ? "transparent" : row.mdT.h ? Qt.rgba(1, 1, 1, 0.07)
        : row.mdT.z ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(1, 1, 1, 0.012)
      border.width: 1
      border.color: "#454b57"
    }
    // the columns' rules, one line down the whole table
    Repeater {
      model: tableFrame.visible ? row.mdT.c : []
      Rectangle {
        required property var modelData
        x: Math.round((modelData - row.mdT.x - 0.5) * row.cellW)
        width: 1
        height: row.cellH
        color: "#454b57"
      }
    }
    // the rule under the header (its --- row is hidden), or across that
    // row when the cursor shows it as written
    Rectangle {
      visible: tableFrame.visible && (!!row.mdT.d || !!row.mdT.u)
      y: row.mdT && row.mdT.u ? row.cellH - 1 : Math.round(row.cellH / 2)
      width: parent.width
      height: 1
      color: "#5a6170"
    }
  }

  // a rule, fading in and out
  Rectangle {
    visible: row.md !== null && row.md.k === "hr"
    x: row.textX
    width: Math.max(0, row.width - row.textX - row.cellW)
    y: Math.round(row.cellH / 2)
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.rgba(Zenon.muted.r, Zenon.muted.g, Zenon.muted.b, 0) }
      GradientStop { position: 0.5; color: Zenon.muted }
      GradientStop { position: 1; color: Qt.rgba(Zenon.muted.r, Zenon.muted.g, Zenon.muted.b, 0) }
    }
  }

  // ── backgrounds ────────────────────────────────────────────────────
  // only the spans that have one: most rows have none, and a Repeater over
  // nothing costs nothing when the row changes
  readonly property var bgSpans: {
    row.info;
    const out = [];
    const sp = row.info.s || [];
    for (let k = 0; k < sp.length; ++k) {
      const st = row.ed.styles[sp[k][2]];
      // a selection or a match is a wash over the text (hl.lua's `wash`)
      if (st && st.bg && !(st.v && !row.ownSelection)) {
        const c = Qt.color(st.bg);
        out.push({ x: sp[k][0], w: sp[k][1], c: st.a ? Qt.rgba(c.r, c.g, c.b, st.a) : c });
      }
    }
    return out;
  }
  Repeater {
    model: row.bgSpans
    Rectangle {
      required property var modelData
      x: row.textX + modelData.x * row.cellW
      width: modelData.w * row.cellW
      height: row.cellH
      radius: 3
      color: modelData.c
    }
  }

  // ── a diagnostic's pill, and a fold's ──────────────────────────────
  // The message at a line's end sits in a soft pill of its severity's
  // colour, half a cell of air either side; one the window's edge cut short
  // ends in "…" (view.lua) and its pill runs into the edge. A closed
  // fold's "⋯ N lines" is a quiet pill of its own.
  readonly property var vt: row.info.vt ? Array.from(row.info.vt) : null
  function sevInk(k) {
    return k === "e" ? Zenon.red : k === "w" ? Zenon.yellow : k === "i" ? Zenon.blue : Zenon.cyan;
  }
  Rectangle {
    visible: row.vt !== null
    readonly property color ink: row.vt ? row.sevInk(row.vt[2]) : "transparent"
    x: row.vt ? row.textX + (row.vt[0] - 0.5) * row.cellW : 0
    width: row.vt ? (row.vt[1] - row.vt[0] + (row.vt[3] ? 0.5 : 1)) * row.cellW : 0
    y: 1
    height: row.cellH - 2
    radius: height / 2
    color: Qt.rgba(ink.r, ink.g, ink.b, 0.13)
  }
  readonly property var fc: row.info.fc ? Array.from(row.info.fc) : null
  Rectangle {
    visible: row.fc !== null
    x: row.fc ? row.textX + (row.fc[0] - 0.75) * row.cellW : 0
    width: row.fc ? (row.fc[1] + 1.5) * row.cellW : 0
    y: 2
    height: row.cellH - 4
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.05)
    border.width: 1
    border.color: Zenon.border
  }
  // a float's selection, one strip a row (a window draws its own shape)
  readonly property var sl: row.ownSelection && row.info.sl ? Array.from(row.info.sl) : null
  Rectangle {
    visible: row.sl !== null
    x: row.sl ? row.textX + row.sl[0] * row.cellW : 0
    width: row.sl ? (row.sl[1] - row.sl[0]) * row.cellW : 0
    height: row.cellH
    radius: 3
    color: Qt.rgba(row.ed.visualInk.r, row.ed.visualInk.g, row.ed.visualInk.b, row.ed.visualAlpha)
  }

  // ── INDENT GUIDES, AS THE FILE TREE DRAWS ITS OWN ──────────────────
  // terminus' tree guides (EntryRow): a one-pixel line in the muted ink,
  // on a whole pixel, rows meeting exactly. Stronger than the tree's 0.6
  // (the user found the tree's strength faint over code): 0.55 for every
  // guide, and whole for the block the cursor is in. Under the text: a
  // guide only ever crosses blank indent anyway.
  readonly property var guides: row.info.ig ? Array.from(row.info.ig) : []
  Repeater {
    model: row.guides
    Rectangle {
      required property var modelData
      readonly property bool lit: row.scope !== null && row.scope.col === modelData
        && row.info.n >= row.scope.first && row.info.n <= row.scope.last
      x: Math.floor(row.textX + modelData * row.cellW + row.cellW / 2)
      width: 1
      height: row.cellH
      color: Zenon.muted
      opacity: lit ? 1 : 0.55
    }
  }

  // ── the text ───────────────────────────────────────────────────────
  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/ /g, "&nbsp;");
  }
  readonly property string markup: {
    const d = row.info;
    const styles = row.ed.styles;
    const chars = Cells.chars(d.t);
    let out = "";
    let pos = 0;
    for (let k = 0; k < d.s.length; ++k) {
      const sp = d.s[k];
      const cs = sp.length > 3 ? sp[3] : sp[0];
      const cl = sp.length > 3 ? sp[4] : sp[1];
      if (cs > pos) out += row.esc(chars.slice(pos, cs).join(""));
      let seg = row.esc(chars.slice(cs, cs + cl).join(""));
      const st = styles[sp[2]];
      if (st) {
        if (st.b) seg = "<b>" + seg + "</b>";
        if (st.i) seg = "<i>" + seg + "</i>";
        if (st.s) seg = "<s>" + seg + "</s>";
        if (st.fg) seg = "<font color=\"" + st.fg + "\">" + seg + "</font>";
      }
      out += seg;
      pos = Math.max(pos, cs + cl);
    }
    if (pos < chars.length) out += row.esc(chars.slice(pos).join(""));
    return out;
  }
  // Not clipped, so a glyph taller than its cell — box drawing reaches from
  // the very top of the line to the very bottom — meets the row above and
  // the row below rather than stopping short of them. The window clips.
  //
  // A RENDERED H1 OR H2 IS SET LARGER, a little past its row — headings sit
  // between blank lines. Not the cursor's line: written out, it is on the
  // grid the cursor moves on.
  readonly property real textScale: row.md && row.md.k === "h" && !row.md.raw && row.info.k === 0
    ? (row.md.n === 1 ? 1.25 : row.md.n === 2 ? 1.12 : 1) : 1
  Text {
    x: row.textX
    width: row.width - row.textX
    height: row.cellH
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.StyledText
    font.family: row.face.family
    font.weight: row.face.weight
    font.pixelSize: Math.round(row.face.pixelSize * row.textScale)
    color: row.ed.normalFg
    text: row.markup
  }

  // past the end of the file: a dim ~ where the text would start
  Text {
    visible: row.eofMark && row.info.n === 0
    x: row.textX
    height: row.cellH
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    font: row.face
    color: row.ed.lineNrFg
    opacity: 0.35
    text: "~"
  }

  // ── the bracket at the cursor, and its partner ─────────────────────
  // outlined in the cursor's cyan, as the jump trail's ghost is
  readonly property var pairCells: row.info.m ? Array.from(row.info.m) : []
  Repeater {
    model: row.pairCells
    Rectangle {
      required property var modelData
      x: row.textX + modelData * row.cellW
      width: row.cellW
      height: row.cellH
      radius: 2
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
      border.width: 1
      border.color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.8)
    }
  }

  // ── underlines ─────────────────────────────────────────────────────
  readonly property var ulSpans: {
    row.info;
    const out = [];
    const sp = row.info.s || [];
    for (let k = 0; k < sp.length; ++k) {
      const st = row.ed.styles[sp[k][2]];
      if (st && (st.u === true || st.c === true))
        out.push({ x: sp[k][0], w: sp[k][1], curl: st.c === true,
                   ink: st.sp ? st.sp : st.fg ? st.fg : row.ed.normalFg });
    }
    return out;
  }
  Repeater {
    model: row.ulSpans
    Item {
      id: uline
      required property var modelData
      x: row.textX + modelData.x * row.cellW
      width: modelData.w * row.cellW
      y: row.cellH - 3
      height: 3

      Rectangle {
        visible: !uline.modelData.curl
        y: 1
        width: uline.width
        height: 1
        color: uline.modelData.ink
      }
      Shape {
        visible: uline.modelData.curl
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: uline.modelData.ink
          strokeWidth: 1
          fillColor: "transparent"
          // a wave with a period of four pixels, as far as the span reaches
          PathSvg {
            path: {
              const w = Math.ceil(uline.width);
              let p = "M0 2";
              for (let x = 0; x < w; x += 4) p += " Q" + (x + 1) + " 0 " + (x + 2) + " 2 Q" + (x + 3) + " 4 " + (x + 4) + " 2";
              return p;
            }
          }
        }
      }
    }
  }
}
