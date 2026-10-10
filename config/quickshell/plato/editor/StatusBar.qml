// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The line under the editor: the file and where you are in it — and, while
// nvim has a command line open, that instead. What nvim SAYS is not here:
// messages are cards in the editor's corner (Toasts.qml), so the file and
// its unsaved ● are always on show.
//
// nvim draws none of this. Its statusline, ruler, showmode and command line
// are all switched off (see nvim/init.lua); the same facts arrive as state
// and are laid out here.
//
// THE MODE IS A COLOUR AND A WORD, NOT A CHIP. The bar takes the mode's
// ink — a breath of tint across it, the position, and the mode's name in
// small capitals beside the tree's switch — green inserting,
// magenta selecting, red replacing, yellow on the command line, and muted
// in normal mode, which is where the bar should be quiet. The file wears its glyph, from the map terminus and
// artemis share (morpheus/icons.js), in terminus' ink for its kind.
//
// ON THE RIGHT, what nvim's own status line, ruler and showcmd would have
// said, from status.lua: a command half typed ("2d", in sand), a macro
// being recorded (a red dot, REC @q), the language servers (what they are
// doing while they work), the diagnostics counted, the git branch and this
// file's changes, the indent and line endings — and, while selecting, how
// much is selected in place of where you are. The servers, the counts, git
// and the indent are each a click away from doing something about them.
//
// THE COMMAND LINE takes the whole bar while it is open: a glyph for what
// kind of line it is (a command, a search forward or back, an answer to a
// prompt), the text with a breathing caret of the editor's own kind, kept in
// view however long the line grows, and — for a search — how many matches
// there are, live as you type. Completions rise out of the bar as a card
// anchored where the completed word starts — offered as you type (see
// editing.lua), and moved through with <Tab>.

import QtQuick
import "../../morpheus"
import "../../morpheus/icons.js" as Icons
import "../../terminus/terminus.js" as Terminus
import "kinds.js" as Kinds

Item {
  id: bar

  required property var ed
  property var client: null
  property font font
  // the glyphs beside the text: larger than it, as the tree's bar draws its
  // own (PlatoWindow hands in exactly that size, so the two lines match)
  property int glyphSize: bar.font.pixelSize + 5
  // MATERIAL DESIGN ICONS ARE DRAWN SMALL. The status line's own signs —
  // the package, the branch, the cog, the counts, the search — are nerd
  // font's Material set (U+F0000 on), drawn at about seven tenths of their
  // box, where the file's glyph and the tree's switch fill theirs: at one
  // size the right-hand side read a size smaller than the left. A quarter
  // larger, their ink stands as tall as the file glyph's.
  // Four under that rule (user, 2026-10-08), as glyphSize is, so the two
  // shrink together. And then (user, 2026-10-09, a third time too big): no
  // quarter at all — the tree toggle's own size, which is the size wanted.
  readonly property int iconSize: bar.glyphSize
  // between the file name and the marks after it (unsaved, saved, root…):
  // a set width, not spaces — a space is as wide as the mark's own font
  // makes it, and the lock's was half the dot's
  readonly property int markGap: Math.round(bar.iconSize * 0.9)
  // plugin updates waiting (core/Plugins.qml), and a click on their count
  property int pluginUpdates: 0
  // ── A SHEET SPLICED OUT OF THIS BAR ──────────────────────────────
  // While one hangs from here, the bar goes black — the glass's own colour
  // at its seam (morpheus/Sheet, Frost.fade*) — and its hairline opens over
  // the card, so the two read as one piece. From the plato window; x in
  // this bar's own coordinates.
  property real spliceInk: 0
  property real spliceX: 0
  property real spliceW: 0
  signal pluginsClicked()
  // the file tree beside the editor: whether it is shown, and a click on its
  // switch
  property bool treeShown: false
  signal treeToggled()
  // the status line's facts, each a way in: the diagnostics' list, the
  // language servers, git's status, and the file's indentation and endings
  signal diagnosticsClicked()
  signal lspClicked()
  signal gitClicked()
  signal formatClicked()
  readonly property var st: bar.ed.status

  // the window's tooltip (morpheus WindowTip), shared with the tab strip:
  // every way in on this bar names itself, as the tree's buttons do
  property var tips: null
  function tip(item, on, text, key) {
    // the pill follows whatever the pointer is on (see hoverPill)
    if (on) bar.hoverTarget = item;
    else if (bar.hoverTarget === item) bar.hoverTarget = null;
    if (!bar.tips) return;
    if (on) bar.tips.show(item, text, key || "");
    else bar.tips.hide(item);
  }

  implicitHeight: Math.ceil(fm.height * 1.9)

  FontMetrics { id: fm; font: bar.font }

  readonly property bool cmd: bar.ed.cmdlineShown
  // the mode's ink; transparent in normal mode
  readonly property color modeInk: {
    if (bar.cmd) return Zenon.yellow;
    switch (bar.ed.modeName) {
      case "insert": return Zenon.green;
      case "visual": return Zenon.magenta;
      case "replace": return Zenon.red;
      case "command": return Zenon.yellow;
      default: return "transparent";
    }
  }
  readonly property bool tinted: bar.modeInk.a > 0
  readonly property bool searching: bar.cmd
    && (bar.ed.cmdlineFirstc === "/" || bar.ed.cmdlineFirstc === "?")

  Rectangle {
    anchors.fill: parent
    color: Zenon.wash(0.03)
    Rectangle {
      anchors.fill: parent
      color: bar.tinted ? Qt.rgba(bar.modeInk.r, bar.modeInk.g, bar.modeInk.b, 0.17) : Zenon.alpha(bar.modeInk, 0)
      Behavior on color { ColorAnimation { duration: Zenon.normal } }
    }
    // black under a spliced sheet (see spliceInk)
    Rectangle {
      anchors.fill: parent
      color: Zenon.ground
      opacity: bar.spliceInk
      visible: opacity > 0.01
    }
    // the top hairline, open over a spliced card
    Rectangle {
      width: bar.spliceInk > 0.01 ? Math.max(0, Math.min(parent.width, bar.spliceX)) : parent.width
      height: 1
      color: Zenon.border
    }
    Rectangle {
      x: Math.max(0, Math.min(parent.width, bar.spliceX + bar.spliceW))
      width: Math.max(0, parent.width - x)
      visible: bar.spliceInk > 0.01
      height: 1
      color: Zenon.border
    }
    // A LANGUAGE SERVER AT WORK: a short blue sweep along the top edge, for
    // as long as it is busy (the cog beside its name holds still)
    Item {
      anchors.fill: parent
      clip: true
      visible: bar.lspBusy
      Rectangle {
        id: sweep
        height: 2
        width: Math.max(60, parent.width * 0.16)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: Qt.rgba(Zenon.blue.r, Zenon.blue.g, Zenon.blue.b, 0) }
          GradientStop { position: 0.5; color: Zenon.blue }
          GradientStop { position: 1; color: Qt.rgba(Zenon.blue.r, Zenon.blue.g, Zenon.blue.b, 0) }
        }
        NumberAnimation on x {
          running: bar.lspBusy
          loops: Animation.Infinite
          from: -sweep.width; to: sweep.parent.width
          duration: 1400
          easing.type: Easing.InOutQuad
        }
      }
    }
    // RECORDING A MACRO: a red stripe down the bar's left edge, breathing
    // with the dot on the right, so q pressed by accident is hard to miss
    Rectangle {
      visible: (bar.st.rec || "") !== ""
      width: 3
      height: parent.height
      color: Zenon.red
      SequentialAnimation on opacity {
        running: (bar.st.rec || "") !== ""
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
      }
    }
  }

  readonly property bool lspBusy: !!(bar.st.lsp && bar.st.lsp.busy)

  // ── THE POINTER'S PILL ─────────────────────────────────────────────
  // One soft rounded wash behind whatever way in the pointer is over — the
  // tree's switch, the servers, the counts, git, the indent, the updates —
  // gliding from one to the next rather than each lighting up on its own.
  // Set through tip(), which every one of them already calls.
  property Item hoverTarget: null
  property rect pillRect: Qt.rect(0, 0, 0, 0)
  function placePill() {
    const t = bar.hoverTarget;
    if (!t || !t.visible) return;
    const p = t.mapToItem(bar, 0, 0);
    bar.pillRect = Qt.rect(p.x, p.y, t.width, t.height);
  }
  onHoverTargetChanged: bar.placePill()
  onWidthChanged: bar.placePill()
  Rectangle {
    id: hoverPill
    readonly property bool on: bar.hoverTarget !== null && !bar.cmd
    x: bar.pillRect.x - 8
    width: bar.pillRect.width + 16
    y: 4
    height: bar.height - 8
    radius: 5
    color: Zenon.wash(0.07)
    opacity: hoverPill.on ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
    Behavior on x { enabled: hoverPill.opacity > 0.05; NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
    Behavior on width { enabled: hoverPill.opacity > 0.05; NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
  }

  // ── the tree's switch ──────────────────────────────────────────────
  // terminus' sidebar switch, the same glyph in the same inks: cyan while the
  // tree is out, white under the pointer, muted otherwise. First on the left,
  // since what it switches is to the left of everything else.
  Item {
    id: treeToggle
    visible: !bar.cmd
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    // as wide as its glyph: the bar's 14 on the left is the 14 on the right
    width: toggleGlyph.implicitWidth
    Text {
      id: toggleGlyph
      anchors.centerIn: parent
      // an escape, not the character: literal nerd glyphs do not survive
      // every editor and tool on their way into this file
      text: "\uEC02"
      color: bar.treeShown ? Zenon.cyan : (treeHover.hovered ? Zenon.white : Zenon.muted)
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: bar.glyphSize
    }
    // a target wider than the glyph, as a button's is
    HoverHandler { id: treeHover; margin: 8; cursorShape: Qt.PointingHandCursor
      onHoveredChanged: bar.tip(parent, hovered, bar.treeShown ? "Hide the file tree" : "Show the file tree", "|") }
    TapHandler { margin: 8; onTapped: bar.treeToggled() }
  }

  // ── the mode, by name ──────────────────────────────────────────────
  // A word, not a chip: small capitals, spaced, in the mode's ink — muted in
  // normal mode, where the bar stays quiet.
  Text {
    id: modeLabel
    visible: !bar.cmd
    anchors.left: treeToggle.right
    anchors.leftMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    width: Math.ceil(modeWidth.advanceWidth)
    font.family: Zenon.face
    font.pixelSize: bar.font.pixelSize - 2
    font.weight: Font.DemiBold
    font.letterSpacing: 1.2
    color: bar.tinted ? bar.modeInk : Zenon.muted
    text: bar.ed.modeName.toUpperCase()
    Behavior on color { ColorAnimation { duration: Zenon.normal } }
    // as wide as the longest name, so the path does not shift with the mode
    TextMetrics { id: modeWidth; font: modeLabel.font; text: "TERMINAL" }
  }

  // ── the file ───────────────────────────────────────────────────────
  Item {
    id: left
    visible: !bar.cmd
    anchors.left: modeLabel.right
    anchors.leftMargin: 14
    anchors.right: position.left
    anchors.rightMargin: 16
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    clip: true

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      readonly property string path: bar.ed.file
      readonly property int cut: path.lastIndexOf("/")
      readonly property var entry: {
        const name = path === "" ? "untitled" : path.slice(cut + 1);
        return Terminus.enrich([{ name: name, path: path, isDir: false, size: 1 }], Icons)[0];
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        rightPadding: 10
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: bar.iconSize
        color: Terminus.rowInk(parent.entry)
        text: parent.entry.glyph
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font: bar.font
        color: Zenon.muted
        textFormat: Text.PlainText
        text: parent.cut >= 0 ? parent.path.slice(0, parent.cut + 1) : ""
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font: bar.font
        color: Zenon.white
        textFormat: Text.PlainText
        text: parent.path === "" ? "untitled" : parent.path.slice(parent.cut + 1)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        // light red: Zenon's pink (the palette's bright red)
        color: bar.ed.modified ? Zenon.pink : Zenon.muted
        // unsaved: U+EA73, the glyph the user chose for it (tabs and the
        // buffer picker wear the same), as an escape so it survives editors
        font.family: bar.ed.modified ? Zenon.faceMono : bar.font.family
        font.pixelSize: bar.ed.modified || bar.ed.readonly ? bar.iconSize : bar.font.pixelSize
        leftPadding: text === "" ? 0 : bar.markGap
        text: bar.ed.modified ? "\uEA73" : bar.ed.readonly ? "󰌾" : ""
      }
      // JUST SAVED: a white floppy (U+F0C7) where the unsaved dot was, fading out —
      // the write seen, not just the dot gone (an undo back to the saved
      // text takes the dot too). From status.lua's `saved`, counted per
      // buffer by editing.lua.
      Text {
        id: savedTick
        anchors.verticalCenter: parent.verticalCenter
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: bar.iconSize
        color: Zenon.white
        leftPadding: bar.markGap
        text: "\uF0C7"
        opacity: 0
        visible: opacity > 0.01
        SequentialAnimation {
          id: savedFlash
          NumberAnimation { target: savedTick; property: "opacity"; to: 1; duration: Zenon.fast }
          PauseAnimation { duration: 900 }
          NumberAnimation { target: savedTick; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InQuad }
        }
        // Every status nvim sends is looked at, not only a change of the
        // count: a buffer never written counts 0, and a 0 that never
        // changed never set `seen` — so the very first save went unseen.
        // Keyed by the buffer the count is for (status.lua `buf`), not the
        // file name, which can arrive a status apart from it.
        property int seen: -1
        property int seenBuf: -1
        readonly property var st: bar.st
        onStChanged: {
          if (!savedTick.st) return;
          const n = savedTick.st.saved || 0;
          const b = savedTick.st.buf || 0;
          // the same buffer written again, not a switch to another one
          if (b === savedTick.seenBuf && n > savedTick.seen) savedFlash.restart();
          savedTick.seen = n;
          savedTick.seenBuf = b;
        }
      }
      // root's file, which a save writes as root (root.lua): U+F456 in
      // white (the user's choice), as an escape so it survives editors,
      // beside whatever else the name wears
      Text {
        visible: bar.st.root === true
        anchors.verticalCenter: parent.verticalCenter
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: bar.iconSize
        color: Zenon.white
        leftPadding: bar.markGap
        text: "\uF456"
      }
      // a file too big for the extras (large.lua): they are off for it
      Text {
        visible: bar.st.large === true
        anchors.verticalCenter: parent.verticalCenter
        font: bar.font
        color: Zenon.sand
        leftPadding: bar.markGap
        text: "large file · extras off"
      }
      // WHERE THE CURSOR IS INSIDE THE FILE: class › function (symbols.lua),
      // each with its kind's glyph (kinds.js, the outline picker's), and a
      // click on one goes to where it starts, as the outline does
      Item { width: 14; height: 1; visible: crumbRow.count > 0 }
      Repeater {
        id: crumbRow
        model: bar.ed._list(bar.st.trail)
        Row {
          id: crumb
          required property var modelData
          required property int index
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5
          Text {
            visible: crumb.index > 0
            anchors.verticalCenter: parent.verticalCenter
            font: bar.font
            color: Zenon.muted
            text: " \u203A "
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: bar.font.pixelSize
            color: crumbHover.hovered ? Zenon.white : Zenon.muted
            text: Kinds.glyph(crumb.modelData.kind)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            font: bar.font
            color: crumbHover.hovered ? Zenon.white : Zenon.muted
            textFormat: Text.PlainText
            text: crumb.modelData.name
          }
          HoverHandler { id: crumbHover; cursorShape: Qt.PointingHandCursor
            onHoveredChanged: bar.tip(crumb, hovered, "Go to " + String(crumb.modelData.kind || "symbol").toLowerCase() + " " + crumb.modelData.name, "") }
          TapHandler {
            onTapped: if (bar.client) bar.client.cmd("normal! m'\ncall cursor(" + crumb.modelData.line
              + ", " + (crumb.modelData.col || 1) + ")\nnormal! zz")
          }
        }
      }
    }
  }

  // ── where you are ──────────────────────────────────────────────────
  Row {
    id: position
    visible: !bar.cmd
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    spacing: 18
    // ── a command half typed: "2d", "\"a", "g" ──────────────────────
    // what showcmd would have said, in the sand of a key not yet answered
    // as key chips, the palette's and the leader's KeyCap, one per key
    Row {
      visible: bar.ed.pending !== ""
      spacing: 3
      anchors.verticalCenter: parent.verticalCenter
      Repeater {
        model: bar.keysOf(bar.ed.pending)
        KeyCap {
          required property var modelData
          anchors.verticalCenter: parent ? parent.verticalCenter : undefined
          label: modelData
          fontSize: Math.max(10, bar.font.pixelSize - 3)
        }
      }
    }
    // ── recording a macro ───────────────────────────────────────────
    // easy to start by accident (q) and invisible without this: a red dot
    // that breathes and the register, until q again
    Row {
      visible: (bar.st.rec || "") !== ""
      spacing: 6
      anchors.verticalCenter: parent.verticalCenter
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: bar.iconSize
        color: Zenon.red
        text: "\u{F044B}"
        SequentialAnimation on opacity {
          running: (bar.st.rec || "") !== ""
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
        }
      }
      Text { anchors.verticalCenter: parent.verticalCenter; font: bar.font; color: Zenon.red; text: "REC @" + (bar.st.rec || "") }
    }
    // ── the language servers ────────────────────────────────────────
    // what they are doing while they work (indexing 40%), a quiet cog when
    // one is attached and idle, nothing with none. A click: restart, stop,
    // what they are.
    Row {
      id: lspRow
      readonly property var lsp: bar.st.lsp || { names: [] }
      readonly property var names: bar.ed._list(lsp.names)
      visible: names.length > 0
      spacing: 6
      anchors.verticalCenter: parent.verticalCenter
      opacity: lspHover.hovered ? 1 : 0.85
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: bar.iconSize
        color: lspRow.lsp.busy ? Zenon.blue : Zenon.muted
        text: "\u{F0493}"
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font: bar.font
        color: parent.lsp.busy ? Zenon.blue : Zenon.muted
        textFormat: Text.PlainText
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 260)
        text: parent.lsp.busy || parent.names.join(" ")
      }
      HoverHandler { id: lspHover; cursorShape: Qt.PointingHandCursor
        onHoveredChanged: bar.tip(parent, hovered, "Language servers", "") }
      TapHandler { onTapped: bar.lspClicked() }
    }
    // ── what is wrong ───────────────────────────────────────────────
    // errors and warnings counted, in their inks; info and hints only when
    // there is nothing worse. A click lists them.
    Row {
      readonly property var d: bar.st.diag || { e: 0, w: 0, i: 0, h: 0 }
      visible: d.e + d.w + d.i + d.h > 0
      spacing: 10
      anchors.verticalCenter: parent.verticalCenter
      opacity: diagHover.hovered ? 1 : 0.9
      DiagCount { font: bar.font; glyphSize: bar.iconSize; n: parent.d.e; glyph: "\u{F0159}"; ink: Zenon.red }
      DiagCount { font: bar.font; glyphSize: bar.iconSize; n: parent.d.w; glyph: "\u{F0026}"; ink: Zenon.yellow }
      DiagCount { font: bar.font; glyphSize: bar.iconSize; n: parent.d.e + parent.d.w > 0 ? 0 : parent.d.i; glyph: "\u{F02FC}"; ink: Zenon.blue }
      DiagCount { font: bar.font; glyphSize: bar.iconSize; n: parent.d.e + parent.d.w > 0 ? 0 : parent.d.h; glyph: "\u{F0335}"; ink: Zenon.cyan }
      HoverHandler { id: diagHover; cursorShape: Qt.PointingHandCursor
        onHoveredChanged: bar.tip(parent, hovered, "Diagnostics", "space d d") }
      TapHandler { onTapped: bar.diagnosticsClicked() }
    }
    // ── git: the branch, and this file's changes ────────────────────
    // as the gutter colours them: added green, changed yellow, removed red.
    // A click: fugitive's status.
    Row {
      readonly property var df: bar.st.diff || null
      visible: (bar.st.branch || "") !== ""
      spacing: 8
      anchors.verticalCenter: parent.verticalCenter
      opacity: gitHover.hovered ? 1 : 0.85
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: bar.iconSize
        color: Zenon.magenta
        text: "\u{F062C}"
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font: bar.font
        color: Zenon.muted
        textFormat: Text.PlainText
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 180)
        text: bar.st.branch || ""
      }
      Text { anchors.verticalCenter: parent.verticalCenter; visible: !!parent.df && parent.df.a > 0; font: bar.font; color: Zenon.green; text: parent.df ? "+" + parent.df.a : "" }
      Text { anchors.verticalCenter: parent.verticalCenter; visible: !!parent.df && parent.df.c > 0; font: bar.font; color: Zenon.yellow; text: parent.df ? "~" + parent.df.c : "" }
      Text { anchors.verticalCenter: parent.verticalCenter; visible: !!parent.df && parent.df.d > 0; font: bar.font; color: Zenon.red; text: parent.df ? "-" + parent.df.d : "" }
      HoverHandler { id: gitHover; cursorShape: Qt.PointingHandCursor
        onHoveredChanged: bar.tip(parent, hovered, "Git status", "space g s") }
      TapHandler { onTapped: bar.gitClicked() }
    }
    // several cursors (multicursor.nvim): how many, in the cursor's cyan
    Row {
      visible: bar.ed.cursors > 1
      spacing: 6
      anchors.verticalCenter: parent.verticalCenter
      Text { anchors.verticalCenter: parent.verticalCenter; font.family: Zenon.faceMono; font.pixelSize: bar.iconSize; color: Zenon.cyan; text: "\u{F05E7}" }
      Text { anchors.verticalCenter: parent.verticalCenter; font: bar.font; color: Zenon.cyan; text: bar.ed.cursors + " cursors" }
    }
    SearchCount { visible: bar.ed.search !== null }
    // ── how the file is written: its indent, and its line endings ───
    // "spaces 4", "tabs 8"; the endings only when they are not unix', and
    // the encoding only when it is not utf-8. A click changes them.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      readonly property var ind: bar.st.indent || { tabs: false, width: 4 }
      font: bar.font
      // white outside normal mode, as the line count beside the position is
      color: fmtHover.hovered || bar.tinted ? Zenon.white : Zenon.muted
      textFormat: Text.PlainText
      text: (ind.tabs ? "tabs " : "spaces ") + ind.width
        + (bar.st.eol && bar.st.eol !== "unix" ? " · " + (bar.st.eol === "dos" ? "CRLF" : "CR") : "")
        + (bar.st.enc && bar.st.enc !== "utf-8" ? " · " + bar.st.enc : "")
      HoverHandler { id: fmtHover; cursorShape: Qt.PointingHandCursor
        onHoveredChanged: bar.tip(parent, hovered, "Indentation and line endings", "") }
      TapHandler { onTapped: bar.formatClicked() }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      font: bar.font
      color: Zenon.muted
      text: bar.ed.filetype
      visible: text !== ""
    }
    // where you are — or, while selecting, how much is selected
    Row {
      visible: !bar.st.sel
      anchors.verticalCenter: parent.verticalCenter
      // the line in white (the mode's ink outside normal mode), the column
      // a step back: the line is what you navigate by
      Text { anchors.verticalCenter: parent.verticalCenter; font: bar.font; color: bar.tinted ? bar.modeInk : Zenon.white; text: bar.ed.line }
      Text { anchors.verticalCenter: parent.verticalCenter; font: bar.font; color: Zenon.muted; text: ":" + bar.ed.column }
      Text { anchors.verticalCenter: parent.verticalCenter; font: bar.font; color: bar.tinted ? Zenon.white : Zenon.muted; text: "  " + bar.ed.lines }
    }
    Row {
      readonly property var sel: bar.st.sel || null
      visible: !!sel
      anchors.verticalCenter: parent.verticalCenter
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font: bar.font
        color: bar.modeInk.a > 0 ? bar.modeInk : Zenon.white
        // a block: its size, rows by columns
        text: !parent.sel ? "" : parent.sel.cols ? parent.sel.lines + " \u00D7 " + parent.sel.cols
          : parent.sel.lines > 1 ? parent.sel.lines + " lines"
          : parent.sel.chars + (parent.sel.chars === 1 ? " char" : " chars")
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font: bar.font
        color: Zenon.muted
        text: !parent.sel ? "" : parent.sel.cols ? "  block"
          : parent.sel.lines > 1
          ? "  " + parent.sel.words + " words · " + parent.sel.chars + " chars"
          : "  " + parent.sel.words + (parent.sel.words === 1 ? " word" : " words")
      }
    }
    // Last in the line: news about plato, not about the file.
    // The shell's own sign for "updates are waiting": the bar's update
    // module shows packages as this glyph in this yellow, and so does this,
    // with the count beside it. Nothing at all when there are none. A click
    // opens the plugin panel.
    Row {
      visible: bar.pluginUpdates > 0
      spacing: 6
      anchors.verticalCenter: parent.verticalCenter
      opacity: pluginHover.hovered ? 1 : 0.85
      Text {
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: bar.iconSize
        color: Zenon.yellow
        text: "󰏗"
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        font: bar.font
        color: Zenon.yellow
        text: String(bar.pluginUpdates)
      }
      HoverHandler { id: pluginHover; cursorShape: Qt.PointingHandCursor
        onHoveredChanged: bar.tip(parent, hovered, "Plugin updates", "space U") }
      TapHandler { onTapped: bar.pluginsClicked() }
    }
  }

  // "2d" → ["2", "d"]; "<C-w>" and showcmd's "^W" → "ctrl w"; a space named
  function keysOf(p) {
    const ks = String(p).match(/<[^>]+>|\^.|[\s\S]/g) || [];
    return ks.map((k) => k === " " ? "space"
      : /^\^.$/.test(k) ? "ctrl " + k.charAt(1).toLowerCase()
      : /^<[^>]+>$/.test(k) ? k.slice(1, -1).replace(/^C-/i, "ctrl ").replace(/^S-/i, "shift ")
        .replace(/^A-|^M-/i, "alt ").toLowerCase()
      : k);
  }

  // "3/12" with the search glyph — or "?/12" when the cursor is on no match
  component SearchCount: Row {
    spacing: 7
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    readonly property var sc: bar.ed.search
    Text {
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.faceMono
      font.weight: Zenon.weight
      font.pixelSize: bar.iconSize
      color: Zenon.muted
      text: "󰍉"
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      font: bar.font
      color: parent.sc && parent.sc.total === 0 ? Zenon.red : Zenon.white
      text: {
        const s = parent.sc;
        if (!s) return "";
        if (s.total === 0) return "no match";
        const more = s.incomplete ? "+" : "";
        return (s.current > 0 ? s.current : "?") + "/" + s.total + more;
      }
    }
  }

  // ── the command line ───────────────────────────────────────────────
  // pos is a BYTE offset into the command's text; the caret is placed by
  // characters, so the bytes are walked back into them
  function charsBefore(text, bytes) {
    let b = 0, i = 0;
    const cs = String(text).match(/[\uD800-\uDBFF][\uDC00-\uDFFF]|[\s\S]/g) || [];
    while (i < cs.length && b < bytes) {
      const c = cs[i].codePointAt(0);
      b += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
      i++;
    }
    return cs.slice(0, i).join("");
  }
  readonly property string kindGlyph: {
    switch (bar.ed.cmdlineFirstc) {
      case ":": return "󰆍";
      case "/": return "󰍉";
      case "?": return "󰍉";
      case "=": return "󰇼";
      case "": return bar.ed.cmdlinePrompt !== "" ? "󰏫" : "󰆍";
      default: return bar.ed.cmdlineFirstc;
    }
  }
  Item {
    id: cmdRow
    visible: bar.cmd
    anchors.fill: parent

    Text {
      id: kind
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.faceMono
      font.weight: Zenon.weight
      font.pixelSize: bar.iconSize
      color: Zenon.yellow
      text: bar.kindGlyph
    }
    // input()'s question, before the answer
    Text {
      id: prompt
      anchors.left: kind.right
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      font: bar.font
      color: Zenon.muted
      textFormat: Text.PlainText
      text: bar.ed.cmdlinePrompt
    }
    Item {
      id: field
      anchors.left: prompt.right
      anchors.leftMargin: prompt.text === "" ? 0 : 8
      anchors.right: cmdRight.left
      anchors.rightMargin: 14
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      clip: true

      TextMetrics {
        id: beforeCaret
        font: bar.font
        text: bar.charsBefore(bar.ed.cmdlineText, bar.ed.cmdlinePos)
      }
      // scrolled along with the caret, so the end of a long line stays in
      // view as it is typed
      readonly property real caretX: beforeCaret.advanceWidth
      readonly property real shift: Math.min(0, field.width - 12 - field.caretX)

      Text {
        id: cmdText
        x: field.shift
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        font: bar.font
        color: Zenon.white
        text: bar.ed.cmdlineText
      }
      Rectangle {
        id: caret
        x: field.shift + field.caretX
        width: 2
        height: fm.height
        anchors.verticalCenter: parent.verticalCenter
        color: Zenon.yellow
        Behavior on x { NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase } }
        // breathing, as the editor's caret does, and solid while typing
        SequentialAnimation on opacity {
          id: breathe
          running: bar.cmd
          loops: Animation.Infinite
          PauseAnimation { duration: 500 }
          NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
        }
        Connections {
          target: bar.ed
          function onCmdlineTextChanged() { caret.opacity = 1; breathe.restart(); }
          function onCmdlinePosChanged() { caret.opacity = 1; breathe.restart(); }
        }
      }
    }
    Row {
      id: cmdRight
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 14
      SearchCount { visible: bar.searching && bar.ed.search !== null }
    }
  }

  // ── the command line's completions ─────────────────────────────────
  // nvim chooses them and which is selected (<Tab>, <S-Tab>); this draws
  // them above the bar, starting under the word being completed
  Item {
    id: wild
    readonly property var items: bar.ed.pumItems
    readonly property int shown: Math.min(10, wild.items.length)
    readonly property real rowH: Math.ceil(fm.height * 1.45)
    visible: bar.cmd && bar.ed.pumShown && bar.ed.pumCmdline && wild.items.length > 0
    z: 50
    TextMetrics {
      id: beforeWord
      font: bar.font
      text: bar.charsBefore(bar.ed.cmdlineText, bar.ed.pumCol)
    }
    readonly property real widest: {
      let w = 120;
      for (let i = 0; i < wild.items.length; ++i)
        w = Math.max(w, String(wild.items[i].word).length * fm.averageCharacterWidth);
      return Math.min(520, w + 28);
    }
    width: wild.widest
    height: wild.shown * wild.rowH + 10
    x: Math.max(6, Math.min(bar.width - wild.width - 6,
      field.x + field.shift + beforeWord.advanceWidth - 14))
    y: -wild.height - 6

    Rectangle {
      anchors.fill: parent
      radius: Zenon.windowRadius
      color: Zenon.alpha(Zenon.card, 0.97)
      // full-strength hairline, as the completion menu's (CompletionMenu)
      border.width: 1
      border.color: Qt.rgba(Zenon.border.r, Zenon.border.g, Zenon.border.b, 0.9)
    }
    ListView {
      id: wildList
      // the shell's one scroll (morpheus Elastic), a few items a notch
      ElasticScroll { view: wildList; step: wild.rowH * 3 }
      x: 0
      y: 5
      width: wild.width
      height: wild.shown * wild.rowH
      clip: true
      model: wild.items
      currentIndex: bar.ed.pumSelected
      boundsBehavior: Flickable.StopAtBounds
      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      delegate: Item {
        id: wi
        required property var modelData
        required property int index
        readonly property bool chosen: wi.index === bar.ed.pumSelected
        width: wildList.width
        height: wild.rowH
        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: 4
          anchors.rightMargin: 4
          radius: 3
          visible: wi.chosen
          color: Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.16)
        }
        Text {
          x: 14
          width: parent.width - 28
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
          font: bar.font
          color: wi.chosen ? Zenon.yellow : Zenon.white
          text: wi.modelData.word
        }
        MouseArea {
          anchors.fill: parent
          onClicked: if (bar.client) bar.client.pumPick(wi.index)
        }
      }
    }
  }
}
