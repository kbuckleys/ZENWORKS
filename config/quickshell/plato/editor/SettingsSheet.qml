// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Plato's settings, in plato: Space , or Ctrl , — a terminus sheet
// (PlatoSheet) hanging from the tab strip, drawn from core/Settings.qml's
// specs the way oracle's panel is drawn from its schema. Adding a setting
// there adds its row here; nothing in this file names one.
//
// The controls are oracle's, at a sheet's size: a switch, a track with its
// reading, a chip that steps through its choices. The typeface is not
// here: it is oracle's Monospace font (Zenon.faceCode).
// Every change applies at once, in every window.
//
// TYPING FILTERS: every letter goes into a query (read back in the footer)
// and only the settings whose name or section match it stay, under their
// section's heading. Esc clears the query first and closes the sheet once
// it is empty. So the keys are the arrows: ↑/↓ (or ctrl j/k) move, ←/→
// jump across the columns, Enter (or Space, with nothing typed) flips a
// switch, holds a number for ←/→ to slide (Esc lets go) or opens a color's
// dropdown, ctrl ←/→ change the
// value either way, ctrl r puts the setting back to its default.

import QtQuick
import Quickshell
import "../../morpheus"
import "../../morpheus/controls" as Controls
import "../../terminus"
import "../../oracle/oracle.js" as Ora

PlatoSheet {
  id: sheet

  property var settings: null
  required property font face
  // the window, for the color dropdown's card (a popup of its own)
  property var window: null

  signal closed()

  onDismissed: sheet.close()
  function open() {
    sheet.editing = "";
    query.text = "";
    sheet.sel = Math.max(0, sheet.firstRow());
    sheet.shown = true;
    query.forceActiveFocus();
  }
  // Esc: out of a text being typed, then the query
  // cleared, and only then the sheet closed
  function back() {
    if (drop.open) { drop.open = false; return; }
    if (sheet.editing === "" && query.text !== "") { query.text = ""; return; }
    sheet.close();
  }
  function close() {
    drop.open = false;
    if (sheet.editing !== "") { sheet.endEdit(false); return; }
    sheet.shown = false;
    sheet.closed();
  }

  // ── the rows: a header per section, then its settings ───────────────
  // Filtered by the query: a setting stays when every word typed is in its
  // name or its section's; a section with none left loses its heading too.
  function groupsFor(q) {
    const s = sheet.settings;
    if (!s) return [];
    const words = q.toLowerCase().split(/\s+/).filter((w) => w !== "");
    const out = [];
    for (const sec of s.sections) {
      const mine = s.specs.filter((sp) => {
        if (sp.section !== sec.id) return false;
        const hay = (sp.label + " " + sec.label).toLowerCase();
        return words.every((w) => hay.indexOf(w) >= 0);
      });
      if (mine.length === 0) continue;
      out.push([{ header: true, label: sec.label, icon: sec.icon }]
        .concat(mine.map((sp) => ({ header: false, spec: sp }))));
    }
    return out;
  }
  // ── TWO EVEN COLUMNS (user, 2026-10-08) ────────────────────────────
  // Split only between sections in their written order, one column ran 23
  // rows and the other 33. Now the sections are dealt to the two columns
  // for the most even heights there are (every way tried: there are only a
  // handful), each column keeping the sections' order and the first one
  // staying top left. `rows` is the left column's sections, then the
  // right's; `split` is where the right begins.
  function arrange(groups) {
    const flat = (gs) => [].concat(...gs);
    if (groups.length <= 1) { const r = flat(groups); return { rows: r, split: r.length }; }
    const n = groups.length, len = groups.map((g) => g.length);
    const total = len.reduce((a, b) => a + b, 0);
    let best = 1, gap = Infinity;
    for (let m = 1; m < (1 << n); m += 2) {
      let left = 0;
      for (let i = 0; i < n; ++i) if (m & (1 << i)) left += len[i];
      const d = Math.abs(2 * left - total);
      if (d < gap) { gap = d; best = m; }
    }
    const L = groups.filter((_, i) => best & (1 << i)), R = groups.filter((_, i) => !(best & (1 << i)));
    return { rows: flat(L).concat(flat(R)), split: flat(L).length };
  }
  readonly property var shaped: sheet.arrange(sheet.groupsFor(query.text))
  readonly property var rows: sheet.shaped.rows
  // the whole list, whose taller column is what one column may hold
  readonly property var allShaped: sheet.arrange(sheet.groupsFor(""))
  readonly property var allRows: sheet.allShaped.rows
  onRowsChanged: sheet.sel = Math.max(0, sheet.firstRow())
  property int sel: 0
  // ── A NUMBER IS HELD TO BE SLID (user, 2026-10-19): Enter on its row
  // rings it, ←/→ then move it, Esc or Enter lets go. Leaving the row lets
  // go too.
  property string sliding: ""
  onSelChanged: sheet.sliding = ""
  onShownChanged: sheet.sliding = ""
  function firstRow() { return sheet.rows.findIndex((r) => !r.header); }
  function step(dir) {
    let i = sheet.sel;
    do { i += dir; } while (i >= 0 && i < sheet.rows.length && sheet.rows[i].header);
    if (i >= 0 && i < sheet.rows.length) sheet.sel = i;
  }
  readonly property var cur: sheet.rows[sheet.sel] && !sheet.rows[sheet.sel].header
    ? sheet.rows[sheet.sel].spec : null

  function nudge(spec, dir) {
    if (!spec || !sheet.settings) return;
    sheet.settings.nudge(spec.key, dir);
  }
  // ── A SETTING THAT IS WORDS (a path) is typed, in the help strip's place:
  // Enter keeps it, Esc leaves it as it was
  property string editing: ""
  function editText(spec) {
    sheet.editing = spec.key;
    textField.text = String(sheet.settings.get(spec.key) || "");
    textField.selectAll();
    textField.forceActiveFocus();
  }
  function endEdit(keep) {
    if (keep && sheet.editing !== "") sheet.settings.set(sheet.editing, textField.text.trim());
    sheet.editing = "";
    query.forceActiveFocus();
  }
  function activate(spec) {
    if (!spec || !sheet.settings) return;
    if (spec.type === "text" && !spec.pick) { sheet.editText(spec); return; }
    if (spec.pick === "color") sheet.openDrop(spec);
    else if (spec.type === "int" || spec.type === "real") sheet.sliding = spec.key;
    else sheet.settings.nudge(spec.key, 1);
  }

  // ── the sheet ──────────────────────────────────────────────────────
  // TWO COLUMNS: the sections split where the rows come out most even, the
  // first half down the left and the rest down the right. The keys still
  // walk every setting in order (↑/↓), and ←/→ jump across.
  readonly property real roomH: Math.max(300, sheet.height - sheet.fromTop - sheet.footH - 40)
  readonly property int helpH: 52
  // THE CARD FITS WHAT IS LEFT. Filtered down to what one column of the
  // full sheet would hold, it is one column, half as wide; and it is only
  // as tall as its taller column (room for the "no match" line at least).
  // The sheet eases between sizes (morpheus Sheet).
  readonly property int allSplit: sheet.allShaped.split
  readonly property bool twoCols: sheet.rows.length > Math.max(sheet.allSplit, sheet.allRows.length - sheet.allSplit)
  readonly property int split: sheet.twoCols ? sheet.shaped.split : sheet.rows.length
  // (two rows' room when nothing matches, for the line that says so)
  readonly property int tallest: sheet.rows.length === 0 ? 2
    : Math.max(sheet.split, sheet.rows.length - sheet.split)
  readonly property real wideW: Math.min(1160, Math.max(700, sheet.width - 60))
  readonly property real oneColW: Math.max(560, Math.round(sheet.wideW / 2))
  cardW: sheet.twoCols ? sheet.wideW : sheet.oneColW
  cardH: Math.min(sheet.roomH, sheet.tallest * sheet.rowH + 14 + sheet.helpH)
  footText: query.text === "" ? "type to filter settings" : query.text
  footInk: query.text !== "" ? Zenon.white : Zenon.accentMuted
  hints: drop.open ? [["↑↓", "move"], ["↵", "use"], ["esc", "back"]]
    : sheet.sliding !== "" ? [["←→", "slide"], ["esc", "done"]]
    : [[sheet.twoCols ? "↑↓←→" : "↑↓", "move"], ["↵", "toggle"], ["ctrl ←→", "change"],
       ["ctrl r", "default"], ["esc", query.text !== "" ? "clear" : "close"]]

  // across: the row at the same height in the other column
  function across(dir) {
    if (!sheet.twoCols) return;
    const inLeft = sheet.sel < sheet.split;
    if ((dir > 0) !== inLeft) return;
    const at = inLeft ? sheet.sel : sheet.sel - sheet.split;
    let i = inLeft ? Math.min(sheet.rows.length - 1, sheet.split + at)
                   : Math.min(sheet.split - 1, at);
    while (i >= 0 && i < sheet.rows.length && sheet.rows[i].header) i++;
    if (i >= 0 && i < sheet.rows.length) sheet.sel = i;
  }

  // one setting's row, for either column (a column's `from` is where its
  // slice of the rows starts)
  Component {
    id: settingRow
  Item {
      id: row
      required property var modelData
      required property int index
      // where it is in the whole list, which the keys walk
      readonly property int gi: row.ListView.view.from + row.index
      readonly property var spec: row.modelData.header ? null : row.modelData.spec
      // a dependency on every write, since value() is a call
      readonly property var value: { sheet.settings ? sheet.settings.revision : 0;
        return row.spec && sheet.settings ? sheet.settings.get(row.spec.key) : null; }
      readonly property bool changed: { sheet.settings ? sheet.settings.revision : 0;
        return row.spec && sheet.settings ? !sheet.settings.isDefault(row.spec.key) : false; }
      width: row.ListView.view.width
      height: sheet.rowH

      // a section's name, as terminus' sheets head a group
      Row {
        visible: row.modelData.header
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 3
        spacing: 9
        Text {
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
          color: Zenon.blue
          text: row.modelData.icon || ""
        }
        Text {
          font.family: Zenon.face
          font.pixelSize: Zenon.px(14)
          font.weight: Font.DemiBold
          font.letterSpacing: 1.1
          color: Zenon.blue
          text: String(row.modelData.label || "").toUpperCase()
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: !row.modelData.header
        onClicked: { sheet.sel = row.gi; query.forceActiveFocus(); }
      }
      // a setting: its name — in oracle's "changed" yellow, with oracle's
      // restore glyph after it (U+E612), when it is not at its default; a
      // click on the glyph puts it back (as ctrl r does)
      Row {
        visible: !row.modelData.header
        x: 22
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text {
          id: rowName
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, row.width - 22 - 250 - (row.changed ? 30 : 0))
          elide: Text.ElideRight
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
          color: row.changed ? Zenon.yellow
            : row.gi === sheet.sel ? Zenon.white : Zenon.alpha(Zenon.ink, 0.9)
          text: row.spec ? row.spec.label : ""
        }
        Item {
          visible: row.changed
          anchors.verticalCenter: parent.verticalCenter
          width: restoreGlyph.implicitWidth + 8
          height: rowName.height
          Rectangle {
            anchors.centerIn: parent
            width: parent.width + 4
            height: parent.width + 4
            radius: Zenon.windowRadius
            color: restoreMa.pressed ? Zenon.pressWash(0.14) : Zenon.wash(0)
          }
          Text {
            id: restoreGlyph
            anchors.centerIn: parent
            text: "\uE612"
            color: restoreMa.pressed ? Zenon.ink : Zenon.yellow
            font.family: Zenon.glyphMono
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
          MouseArea {
            id: restoreMa
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            onClicked: { if (row.spec) sheet.settings.reset(row.spec.key); query.forceActiveFocus(); }
          }
        }
      }

      // held to be slid (see sliding)
      HeldRing {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        z: 5
        on: row.spec !== null && sheet.sliding === row.spec.key
      }

      // ── the control ──────────────────────────────────────────────────
      Loader {
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        active: row.spec !== null
        sourceComponent: !row.spec ? null
          : row.spec.pick === "color" ? colorChip
          : row.spec.type === "bool" ? switchControl
          : row.spec.type === "int" || row.spec.type === "real" ? trackControl
          : chipControl
        property var spec: row.spec
        property var value: row.value
        property int rowIndex: row.gi
      }
    }
  }

  ListView {
    id: list
    // the slice of the rows this column shows
    readonly property bool mine: sheet.sel >= list.from && sheet.sel < list.to
    anchors.top: parent.top
    anchors.topMargin: 6
    anchors.bottom: helpRule.top
    anchors.bottomMargin: 6
    clip: true
    model: sheet.rows.slice(list.from, list.to)
    currentIndex: list.mine ? sheet.sel - list.from : -1
    boundsBehavior: Flickable.DragAndOvershootBounds
    boundsMovement: Flickable.FollowBoundsBehavior
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
    ElasticScroll { view: list }
    SelectBar { view: list; index: Math.max(0, sheet.sel - list.from); rowH: sheet.rowH; on: list.mine }

    delegate: settingRow
    anchors.left: parent.left
    width: sheet.twoCols ? parent.width / 2 - 0.5 : parent.width
    property int from: 0
    property int to: sheet.split
  }
  Rectangle {
    visible: sheet.twoCols
    x: parent.width / 2
    anchors.top: parent.top
    anchors.topMargin: 10
    anchors.bottom: helpRule.top
    anchors.bottomMargin: 10
    width: 1
    color: Zenon.border
  }
  ListView {
    id: list2
    // the slice of the rows this column shows
    readonly property bool mine: sheet.sel >= list2.from && sheet.sel < list2.to
    visible: sheet.twoCols
    anchors.top: parent.top
    anchors.topMargin: 6
    anchors.bottom: helpRule.top
    anchors.bottomMargin: 6
    clip: true
    model: sheet.rows.slice(list2.from, list2.to)
    currentIndex: list2.mine ? sheet.sel - list2.from : -1
    boundsBehavior: Flickable.DragAndOvershootBounds
    boundsMovement: Flickable.FollowBoundsBehavior
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
    ElasticScroll { view: list2 }
    SelectBar { view: list2; index: Math.max(0, sheet.sel - list2.from); rowH: sheet.rowH; on: list2.mine }

    delegate: settingRow
    anchors.right: parent.right
    width: parent.width / 2 - 0.5
    property int from: sheet.split
    property int to: sheet.rows.length
  }

  // ── what the setting does ──────────────────────────────────────────
  Rectangle {
    id: helpRule
    anchors.bottom: help.top
    width: parent.width
    height: 1
    color: Zenon.border
  }
  Text {
    id: help
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: 18
    anchors.rightMargin: 18
    height: sheet.helpH
    verticalAlignment: Text.AlignVCenter
    // centered, over the centered keys below (user, 2026-10-19)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
    color: Zenon.accentMuted
    text: sheet.editing !== "" ? "" : sheet.cur ? (sheet.cur.help || "") : ""
  }
  Rectangle {
    visible: sheet.editing !== ""
    anchors.fill: help
    anchors.topMargin: 10
    anchors.bottomMargin: 10
    anchors.leftMargin: -8
    anchors.rightMargin: -8
    radius: Zenon.radiusControl
    color: Zenon.alpha(Zenon.card, 0.98)
    border.width: 1
    border.color: Zenon.border
    TextInput {
      id: textField
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      verticalAlignment: TextInput.AlignVCenter
      font.family: Zenon.faceFixed
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
      color: Zenon.white
      selectionColor: Qt.rgba(Zenon.magenta.r, Zenon.magenta.g, Zenon.magenta.b, 0.5)
      cursorDelegate: Caret { field: textField }
      clip: true
      Keys.onReturnPressed: sheet.endEdit(true)
      Keys.onEnterPressed: sheet.endEdit(true)
      Keys.onEscapePressed: sheet.endEdit(false)
    }
    // focused for typing: terminus' held ring (user, 2026-10-11 — every
    // text field wears it, its own border staying neutral)
    HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: textField.activeFocus }
  }

  // ── controls (oracle's, at a sheet's size) ─────────────────────────
  // the suite's one on/off, a tick (user, 2026-10-20: "scrap toggle")
  component SwitchBox: Item {
    id: sw
    property var spec: null
    property bool on: false
    width: 20
    height: 20
    Controls.Check {
      anchors.centerIn: parent
      enabled: false
      lit: sw.on
    }
    MouseArea {
      anchors.fill: parent
      anchors.margins: -8
      onClicked: sheet.settings.nudge(sw.spec.key, 1)
    }
  }
  Component {
    id: switchControl
    SwitchBox { spec: parent ? parent.spec : null; on: parent ? parent.value === true : false }
  }

  component Track: Item {
    id: sl
    property var spec: null
    property real value: 0
    width: 230
    height: 24
    readonly property real frac: sl.spec ? Ora.fraction(sl.spec, sl.value) : 0
    Rectangle {
      id: bar
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 150
      height: 4
      radius: height / 2
      color: Zenon.wash(0.10)
      Rectangle {
        width: Math.round(bar.width * sl.frac)
        height: parent.height
        radius: 2
        color: Zenon.cyan
        Behavior on width { NumberAnimation { duration: Zenon.brisk } }
      }
      Rectangle {
        width: 12
        height: 12
        radius: height / 2
        y: -4
        x: Math.round(bar.width * sl.frac) - 6
        color: drag.pressed ? Zenon.white : Zenon.cyan
        border.width: 1
        border.color: Zenon.border
        Behavior on x { NumberAnimation { duration: Zenon.brisk } }
      }
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 66
      horizontalAlignment: Text.AlignRight
      font.family: Zenon.face
      font.weight: Font.Medium
      font.pixelSize: Zenon.px(16)
      color: Zenon.white
      text: sl.spec ? Ora.display(sl.spec, sl.value) : ""
    }
    MouseArea {
      id: drag
      x: -6
      y: -8
      width: bar.width + 12
      height: sl.height + 16
      onPressed: (m) => drag.apply(m.x)
      onPositionChanged: (m) => { if (drag.pressed) drag.apply(m.x); }
      onWheel: (w) => { sheet.settings.nudge(sl.spec.key, w.angleDelta.y > 0 ? 1 : -1); w.accepted = true; }
      function apply(mx) { sheet.settings.set(sl.spec.key, Ora.fromFraction(sl.spec, (mx - 6) / bar.width)); }
    }
  }
  Component {
    id: trackControl
    Track { spec: parent ? parent.spec : null; value: parent ? Number(parent.value) : 0 }
  }

  // a choice: ‹ value ›, stepped by a click on either side
  component Chip: Rectangle {
    id: chip
    property var spec: null
    property var value: null
    property string shown: chip.spec ? Ora.display(chip.spec, chip.value) : ""
    width: 190
    height: 26
    radius: Zenon.radiusControl
    color: Zenon.wash(0.06)
    border.width: 1
    border.color: Zenon.border
    Text {
      anchors.left: parent.left
      anchors.leftMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.faceMono
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
      color: Zenon.accentMuted
      text: "\u{F0141}"
    }
    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 26
      anchors.rightMargin: 26
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      font.family: Zenon.face
      font.weight: Font.Medium
      font.pixelSize: Zenon.px(15)
      color: Zenon.white
      text: chip.shown
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.faceMono
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
      color: Zenon.accentMuted
      text: "\u{F0142}"
    }
    MouseArea {
      anchors.fill: parent
      onClicked: (m) => {
        if (chip.spec.type === "text") sheet.editText(chip.spec);
        else sheet.settings.nudge(chip.spec.key, m.x < chip.width / 2 ? -1 : 1);
      }
    }
  }
  Component {
    id: chipControl
    Chip { spec: parent ? parent.spec : null; value: parent ? parent.value : null }
  }
  // ── A COLOR: a swatch, and a dropdown of them ────────────────────
  // The choice shown as itself — a dot in the color and its name — and
  // Enter, Space or a click opens the choices as the shell's menu card
  // (morpheus CardPopup) under the chip, each with its swatch and a tick on
  // the one in use. ↑/↓ move in it, Enter takes one, Esc puts it away;
  // ctrl ←/→ on the row still step through them without it.
  property var chips: ({})
  Component {
    id: colorChip
    Rectangle {
      id: cc
      readonly property var spec: parent ? parent.spec : null
      readonly property var value: parent ? parent.value : null
      readonly property color ink: { const c = Zenon[String(cc.value)]; return c !== undefined ? c : Zenon.white; }
      width: 190
      height: 26
      radius: Zenon.radiusControl
      color: Zenon.wash(0.06)
      border.width: 1
      border.color: drop.open && drop.spec === cc.spec ? Zenon.cyan : Zenon.border
      Component.onCompleted: if (cc.spec) sheet.chips[cc.spec.key] = cc
      Component.onDestruction: if (cc.spec && sheet.chips[cc.spec.key] === cc) delete sheet.chips[cc.spec.key]
      Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        height: 12
        radius: height / 2
        color: cc.ink
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.4)
        Behavior on color { ColorAnimation { duration: Zenon.fast } }
      }
      Text {
        anchors.left: dot.right
        anchors.leftMargin: 9
        anchors.right: chev.left
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        font.family: Zenon.face
        font.weight: Font.Medium
        font.pixelSize: Zenon.px(15)
        color: Zenon.white
        text: cc.spec ? Ora.display(cc.spec, cc.value) : ""
      }
      Text {
        id: chev
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
        color: Zenon.accentMuted
        text: "\u{F0140}"
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { sheet.sel = parent.parent ? parent.parent.rowIndex : sheet.sel; sheet.openDrop(cc.spec); }
      }
    }
  }
  property int dropSel: 0
  function openDrop(spec) {
    const chip = sheet.chips[spec.key];
    if (!chip || !sheet.window) return;
    const p = chip.mapToItem(sheet.window.contentItem, 0, chip.height + 4);
    drop.spec = spec;
    drop.at = Qt.point(p.x, p.y);
    sheet.dropSel = Math.max(0, spec.options.findIndex((o) => o.value === sheet.settings.get(spec.key)));
    drop.open = true;
  }
  function takeDrop(i) {
    const o = drop.spec ? drop.spec.options[i] : null;
    if (o) sheet.settings.set(drop.spec.key, o.value);
    drop.open = false;
  }
  CardPopup {
    id: drop
    property var spec: null
    window: sheet.window
    cardWidth: 190
    fit: true   // as wide as its longest choice, as every menu
    activeIndex: sheet.dropSel
    model: {
      if (!drop.spec) return [];
      sheet.settings ? sheet.settings.revision : 0;
      const now = sheet.settings ? sheet.settings.get(drop.spec.key) : "";
      return drop.spec.options.map((o) => ({ text: o.label, icon: "\u25CF",
        iconInk: Zenon[o.value], mark: o.value === now }));
    }
    onChosen: (i) => sheet.takeDrop(i)
    onHovered: (i) => sheet.dropSel = i
  }
  // a click anywhere else in the sheet puts the dropdown away
  MouseArea {
    anchors.fill: parent
    visible: drop.open
    z: 50
    onClicked: drop.open = false
  }

  ScrollRail {
    target: sheet.twoCols ? list2 : list
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: helpRule.top
  }

  // ── keys, and the query ────────────────────────────────────────────
  // typed into, never seen: the footer reads it back. What is not a letter
  // for the query is caught here first.
  TextInput {
    id: query
    width: 0
    height: 0
    opacity: 0
    focus: sheet.shown && sheet.editing === ""
    Keys.onPressed: (event) => {
      const k = event.key;
      const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
      event.accepted = true;
      if (drop.open) {
        const n = drop.spec ? drop.spec.options.length : 0;
        if (k === Qt.Key_Escape) drop.open = false;
        else if (n && (k === Qt.Key_Down || (ctrl && (k === Qt.Key_J || k === Qt.Key_N)))) sheet.dropSel = (sheet.dropSel + 1) % n;
        else if (n && (k === Qt.Key_Up || (ctrl && (k === Qt.Key_K || k === Qt.Key_P)))) sheet.dropSel = (sheet.dropSel - 1 + n) % n;
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) sheet.takeDrop(sheet.dropSel);
        return;
      }
      if (sheet.sliding !== "") {
        if (k === Qt.Key_Left || k === Qt.Key_Right) sheet.nudge(sheet.cur, k === Qt.Key_Right ? 1 : -1);
        else if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter
                 || k === Qt.Key_Space) sheet.sliding = "";
        return;
      }
      if (k === Qt.Key_Escape) sheet.back();
      else if (k === Qt.Key_Down || (k === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))
               || (ctrl && (k === Qt.Key_J || k === Qt.Key_N))) sheet.step(1);
      else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && (k === Qt.Key_K || k === Qt.Key_P))) sheet.step(-1);
      // ←/→ ARE MOVEMENT, ACROSS THE COLUMNS (user, 2026-10-19): they
      // used to step the value, which flipped whatever switch the cursor
      // sat on when you only meant to change column. The value is ctrl's.
      else if (ctrl && k === Qt.Key_Left) sheet.nudge(sheet.cur, -1);
      else if (ctrl && k === Qt.Key_Right) sheet.nudge(sheet.cur, 1);
      else if (ctrl && k === Qt.Key_R) { if (sheet.cur) sheet.settings.reset(sheet.cur.key); }
      else if (k === Qt.Key_Right) sheet.across(1);
      else if (k === Qt.Key_Left) sheet.across(-1);
      else if (k === Qt.Key_Return || k === Qt.Key_Enter
               || (k === Qt.Key_Space && query.text === "")) sheet.activate(sheet.cur);
      else event.accepted = false;
    }
  }
  EmptyState {
    visible: sheet.rows.length === 0
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -sheet.helpH / 2
    text: "No setting matches “" + query.text + "”"
  }
}
