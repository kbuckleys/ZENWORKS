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
// reading, a chip that steps through its choices, and for the typeface a
// list of every monospaced family installed, each name set in its own face.
// Every change applies at once, in every window.
//
// Keys: j/k or ↑/↓ move, h/l or ←/→ change the value (a switch flips, a
// number steps, a choice cycles), Enter or Space flips a switch or opens the
// typeface list, r puts the setting back to its default, Esc closes (or
// leaves the typeface list).

import QtQuick
import Quickshell
import Quickshell.Io
import "../../morpheus"
import "../../terminus"
import "../../oracle/oracle.js" as Ora

PlatoSheet {
  id: sheet

  property var settings: null
  required property font face

  signal closed()

  onDismissed: sheet.close()
  function open() {
    sheet.picking = false;
    sheet.editing = "";
    sheet.sel = Math.max(0, sheet.firstRow());
    sheet.shown = true;
    keys.forceActiveFocus();
  }
  function close() {
    if (sheet.picking) { sheet.picking = false; keys.forceActiveFocus(); return; }
    if (sheet.editing !== "") { sheet.endEdit(false); return; }
    sheet.shown = false;
    sheet.closed();
  }

  // ── the rows: a header per section, then its settings ───────────────
  readonly property var rows: {
    const s = sheet.settings;
    if (!s) return [];
    const out = [];
    for (const sec of s.sections) {
      out.push({ header: true, label: sec.label, icon: sec.icon });
      for (const sp of s.specs) if (sp.section === sec.id) out.push({ header: false, spec: sp });
    }
    return out;
  }
  property int sel: 0
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
    if (spec.pick === "font") { if (dir > 0) sheet.openFonts(); return; }
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
    keys.forceActiveFocus();
  }
  function activate(spec) {
    if (!spec || !sheet.settings) return;
    if (spec.type === "text" && !spec.pick) { sheet.editText(spec); return; }
    if (spec.pick === "font") sheet.openFonts();
    else if (spec.type === "bool") sheet.settings.nudge(spec.key, 1);
    else sheet.settings.nudge(spec.key, 1);
  }

  // ── the sheet ──────────────────────────────────────────────────────
  // TWO COLUMNS: the sections split where the rows come out most even, the
  // first half down the left and the rest down the right. The keys still
  // walk every setting in order (j/k), and H / L jump across.
  readonly property real roomH: Math.max(300, sheet.height - sheet.fromTop - sheet.footH - 40)
  readonly property int helpH: 52
  readonly property int split: {
    const r = sheet.rows;
    let best = r.length, gap = r.length;
    for (let i = 1; i < r.length; ++i) {
      if (!r[i].header) continue;
      const d = Math.abs(i - (r.length - i));
      if (d < gap) { gap = d; best = i; }
    }
    return best;
  }
  readonly property int tallest: Math.max(sheet.split, sheet.rows.length - sheet.split)
  cardW: Math.min(1160, Math.max(700, sheet.width - 60))
  cardH: Math.min(sheet.roomH, sheet.tallest * sheet.rowH + 14 + sheet.helpH)
  footText: sheet.picking ? (fontQuery.text === "" ? "type to filter" : fontQuery.text)
    : "plato settings"
  footInk: sheet.picking ? Zenon.white : Zenon.muted
  hints: sheet.picking ? [["↑↓", "move"], ["↵", "use"], ["esc", "back"]]
    : [["↑↓", "move"], ["←→", "change"], ["H L", "column"], ["r", "default"], ["esc", "close"]]

  // across: the row at the same height in the other column
  function across(dir) {
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
          font.pixelSize: 14
          color: Zenon.blue
          text: row.modelData.icon || ""
        }
        Text {
          font.family: Zenon.face
          font.pixelSize: 13
          font.weight: Font.DemiBold
          font.letterSpacing: 1.1
          color: Zenon.blue
          text: String(row.modelData.label || "").toUpperCase()
        }
      }

      // a setting: its name, with a dot when it is not at its default
      Rectangle {
        visible: row.changed
        x: 22
        anchors.verticalCenter: parent.verticalCenter
        width: 5
        height: 5
        radius: 2.5
        color: Zenon.cyan
      }
      Text {
        visible: !row.modelData.header
        x: 36
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 36 - 250
        elide: Text.ElideRight
        font.family: Zenon.face
        font.pixelSize: 15
        color: row.gi === sheet.sel ? Zenon.white : "#c8ccd6"
        text: row.spec ? row.spec.label : ""
      }
      MouseArea {
        anchors.fill: parent
        enabled: !row.modelData.header
        onClicked: { sheet.sel = row.gi; keys.forceActiveFocus(); }
      }

      // ── the control ──────────────────────────────────────────────────
      Loader {
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        active: row.spec !== null
        sourceComponent: !row.spec ? null
          : row.spec.pick === "font" ? fontChip
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
    visible: !sheet.picking
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
    width: parent.width / 2 - 0.5
    property int from: 0
    property int to: sheet.split
  }
  Rectangle {
    visible: !sheet.picking
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
    visible: !sheet.picking
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
    visible: !sheet.picking
    anchors.bottom: help.top
    width: parent.width
    height: 1
    color: Zenon.border
  }
  Text {
    id: help
    visible: !sheet.picking
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: 18
    anchors.rightMargin: 18
    height: sheet.helpH
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
    font.family: Zenon.face
    font.pixelSize: 13
    color: Zenon.muted
    text: sheet.editing !== "" ? "" : sheet.cur ? (sheet.cur.help || "") : ""
  }
  Rectangle {
    visible: sheet.editing !== "" && !sheet.picking
    anchors.fill: help
    anchors.topMargin: 10
    anchors.bottomMargin: 10
    anchors.leftMargin: -8
    anchors.rightMargin: -8
    radius: 4
    color: Qt.rgba(0.05, 0.055, 0.065, 0.98)
    border.width: 1
    border.color: Zenon.cyan
    TextInput {
      id: textField
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      verticalAlignment: TextInput.AlignVCenter
      font.family: Zenon.faceFixed
      font.pixelSize: 14
      color: Zenon.white
      selectionColor: Qt.rgba(Zenon.magenta.r, Zenon.magenta.g, Zenon.magenta.b, 0.5)
      cursorDelegate: Caret { field: textField }
      clip: true
      Keys.onReturnPressed: sheet.endEdit(true)
      Keys.onEnterPressed: sheet.endEdit(true)
      Keys.onEscapePressed: sheet.endEdit(false)
    }
  }

  // ── controls (oracle's, at a sheet's size) ─────────────────────────
  component SwitchBox: Item {
    id: sw
    property var spec: null
    property bool on: false
    width: 40
    height: 20
    Rectangle {
      id: track
      anchors.fill: parent
      radius: height / 2
      color: sw.on ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.30) : Qt.rgba(1, 1, 1, 0.07)
      border.width: 1
      border.color: sw.on ? Zenon.cyan : Zenon.border
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Rectangle {
        width: 14
        height: 14
        radius: 7
        y: 3
        x: sw.on ? track.width - width - 3 : 3
        color: sw.on ? Zenon.cyan : Zenon.muted
        Behavior on x { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      }
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
      radius: 2
      color: Qt.rgba(1, 1, 1, 0.10)
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
        radius: 6
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
      font.pixelSize: 15
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
    property string family: Zenon.face
    property bool opens: false
    width: 190
    height: 26
    radius: 4
    color: Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: Zenon.border
    Text {
      visible: !chip.opens
      anchors.left: parent.left
      anchors.leftMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.faceMono
      font.pixelSize: 12
      color: Zenon.muted
      text: "\u{F0141}"
    }
    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 26
      anchors.rightMargin: 26
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: chip.opens ? Text.AlignLeft : Text.AlignHCenter
      elide: Text.ElideRight
      font.family: chip.family
      font.weight: Font.Medium
      font.pixelSize: 14
      color: Zenon.white
      text: chip.shown
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.faceMono
      font.pixelSize: 12
      color: Zenon.muted
      text: "\u{F0142}"
    }
    MouseArea {
      anchors.fill: parent
      onClicked: (m) => {
        if (chip.opens) sheet.openFonts();
        else if (chip.spec.type === "text") sheet.editText(chip.spec);
        else sheet.settings.nudge(chip.spec.key, m.x < chip.width / 2 ? -1 : 1);
      }
    }
  }
  Component {
    id: chipControl
    Chip { spec: parent ? parent.spec : null; value: parent ? parent.value : null }
  }
  Component {
    id: fontChip
    Chip {
      spec: parent ? parent.spec : null
      value: parent ? parent.value : null
      shown: String(value || "")
      family: String(value || Zenon.faceFixed)
      opens: true
      width: 230
    }
  }

  // ── the typeface list ──────────────────────────────────────────────
  // Every family fontconfig calls monospaced (spacing 100) or dual-width
  // (90, as many Nerd Fonts' Mono cuts are), each set in itself, filtered
  // by what is typed.
  property bool picking: false
  property var families: []
  readonly property var shownFamilies: {
    const q = fontQuery.text.toLowerCase();
    return q === "" ? sheet.families : sheet.families.filter((f) => f.toLowerCase().indexOf(q) >= 0);
  }
  property int fontSel: 0
  function openFonts() {
    sheet.picking = true;
    fontQuery.text = "";
    if (sheet.families.length === 0) famProc.running = true;
    const i = sheet.families.indexOf(sheet.settings.fontFamily);
    sheet.fontSel = Math.max(0, i);
    fontQuery.forceActiveFocus();
  }
  function useFont() {
    const f = sheet.shownFamilies[sheet.fontSel];
    if (f) sheet.settings.set("fontFamily", f);
    sheet.picking = false;
    keys.forceActiveFocus();
  }
  Process {
    id: famProc
    command: ["sh", "-c", "{ fc-list :spacing=100 family; fc-list :spacing=90 family; }"
      + " | cut -d, -f1 | sort -u"]
    stdout: StdioCollector {
      id: famOut
      onStreamFinished: {
        sheet.families = famOut.text.split("\n").map((l) => l.trim()).filter((l) => l !== "");
        const i = sheet.families.indexOf(sheet.settings.fontFamily);
        sheet.fontSel = Math.max(0, i);
      }
    }
  }
  onShownFamiliesChanged: if (sheet.fontSel >= sheet.shownFamilies.length) sheet.fontSel = 0

  TextInput {
    id: fontQuery
    // typed into, never seen: the footer reads it back
    width: 0
    height: 0
    opacity: 0
    focus: sheet.picking
    Keys.onPressed: (event) => {
      const n = sheet.shownFamilies.length;
      const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
      if (event.key === Qt.Key_Escape) { sheet.close(); event.accepted = true; }
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { sheet.useFont(); event.accepted = true; }
      else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
        if (n) sheet.fontSel = (sheet.fontSel + 1) % n; event.accepted = true;
      } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
        if (n) sheet.fontSel = (sheet.fontSel - 1 + n) % n; event.accepted = true;
      }
    }
  }
  ListView {
    id: fonts
    visible: sheet.picking
    anchors.fill: parent
    anchors.topMargin: 6
    anchors.bottomMargin: 6
    clip: true
    model: sheet.shownFamilies
    currentIndex: sheet.fontSel
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
    ElasticScroll { view: fonts }
    SelectBar { view: fonts; index: sheet.fontSel; rowH: sheet.rowH }
    delegate: Item {
      id: fam
      required property string modelData
      required property int index
      width: fonts.width
      height: sheet.rowH
      Text {
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 140
        elide: Text.ElideRight
        font.family: fam.modelData
        font.pixelSize: 16
        color: fam.modelData === (sheet.settings ? sheet.settings.fontFamily : "") ? Zenon.cyan : Zenon.white
        text: fam.modelData
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        font.family: fam.modelData
        font.pixelSize: 15
        color: Zenon.muted
        text: "{ 0O il1 => }"
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { sheet.fontSel = fam.index; sheet.useFont(); }
      }
    }
  }
  ScrollRail {
    target: sheet.picking ? fonts : list2
    anchors.right: parent.right
    anchors.rightMargin: 2
    anchors.top: parent.top
    anchors.bottom: sheet.picking ? parent.bottom : helpRule.top
  }

  // ── keys ───────────────────────────────────────────────────────────
  Item {
    id: keys
    focus: sheet.shown && !sheet.picking
    Keys.onPressed: (event) => {
      event.accepted = true;
      const k = event.key, t = event.text;
      if (k === Qt.Key_Escape || t === "q") sheet.close();
      else if (k === Qt.Key_Down || t === "j" || (k === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) sheet.step(1);
      else if (k === Qt.Key_Up || t === "k" || k === Qt.Key_Backtab) sheet.step(-1);
      else if (t === "H") sheet.across(-1);
      else if (t === "L") sheet.across(1);
      else if (t === "g") sheet.sel = sheet.firstRow();
      else if (t === "G") { sheet.sel = sheet.rows.length - 1; if (sheet.rows[sheet.sel].header) sheet.step(-1); }
      else if (k === Qt.Key_Right || t === "l") sheet.nudge(sheet.cur, 1);
      else if (k === Qt.Key_Left || t === "h") sheet.nudge(sheet.cur, -1);
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) sheet.activate(sheet.cur);
      else if (t === "r" && sheet.cur) sheet.settings.reset(sheet.cur.key);
      else event.accepted = false;
    }
  }
}
