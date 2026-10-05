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
    font: row.face
    textFormat: Text.PlainText
    color: number.rel === 0 ? row.ed.cursorLineNrFg : row.ed.lineNrFg
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
      if (st && st.bg) {
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
      color: modelData.c
    }
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
    const chars = Array.from(d.t);
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
  Text {
    x: row.textX
    width: row.width - row.textX
    height: row.cellH
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.StyledText
    font: row.face
    color: row.ed.normalFg
    text: row.markup
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
