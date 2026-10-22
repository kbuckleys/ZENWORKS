// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// KEYSSHEET — every shortcut on one sheet, over the whole screen.
//
// The list is Oracle's own: binds.lua read by Ora.parseBindsLua, folded with
// keys.lua into Oracle.keyValues, grouped under binds.lua's `-- NAME` heads.
// Nothing is parsed twice and nothing can drift from the Shortcuts section;
// a bind with no chord is simply not on the sheet.
//
// Held or tapped (binds.lua's keysSheet: Super+/). IPC `Keys hold` on the
// press opens it; `Keys release` on the key coming up closes it, but only
// once it was held past HOLD_MS — a quick tap leaves it open to read and
// type into, closed by Esc, a click, or the same keys again.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "oracle.js" as Ora
import "../morpheus"

PanelWindow {
  id: sheet

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "zenworks-keys"
  WlrLayershell.keyboardFocus: sheet.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  anchors { left: true; right: true; top: true; bottom: true }
  color: "transparent"

  property bool shown: false
  property real showFactor: sheet.shown ? 1 : 0
  Behavior on showFactor { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
  visible: sheet.shown || sheet.showFactor > 0.01

  // a press held at least this long is a peek: letting go closes it
  readonly property int holdMs: 400
  property real heldAt: 0
  property string query: ""

  function open() {
    sheet.query = "";
    sheet.shown = true;
  }
  function close() {
    sheet.shown = false;
    sheet.heldAt = 0;
  }

  IpcHandler {
    target: "Keys"
    function toggle() { if (sheet.shown) sheet.close(); else sheet.open(); }
    // not `show`: `qs ipc call Keys show` printed the target instead of calling it
    function open() { sheet.open(); }
    function hide() { sheet.close(); }
    // the bind's press; pressed again while it stays open, it closes
    function hold() {
      if (sheet.shown) { sheet.close(); return; }
      sheet.open();
      sheet.heldAt = Date.now();
    }
    function release() { sheet.letGo(); }
  }

  function letGo() {
    if (sheet.heldAt > 0 && Date.now() - sheet.heldAt >= sheet.holdMs) sheet.close();
    sheet.heldAt = 0;
  }

  HyprlandFocusGrab {
    windows: [ sheet ]
    active: sheet.shown
    onCleared: sheet.close()
  }

  // ── THE LIST ──
  // [{ group, label, binds: [{ label, caps }] }], bound binds only, the query
  // matched against the label, the group and the chord as written
  readonly property var groups: {
    Oracle.revision;
    const q = sheet.query.trim().toLowerCase();
    const out = [];
    let cur = null;
    for (const b of Oracle.bindList) {
      const chord = Oracle.keyValues["bind:" + b.id] || "";
      if (chord === "") continue;
      const glabel = Ora.bindGroupLabel(b.group);
      if (q !== "" && (b.label + " " + glabel + " " + Ora.chordCaps(chord).join(" ")).toLowerCase().indexOf(q) < 0)
        continue;
      if (!cur || cur.group !== b.group) {
        cur = { group: b.group, label: glabel, binds: [] };
        out.push(cur);
      }
      cur.binds.push({ label: b.label, caps: Ora.chordCaps(chord) });
    }
    return out;
  }
  readonly property int count: sheet.groups.reduce((n, g) => n + g.binds.length, 0)

  readonly property real rowH: Zenon.px(15) + 14
  readonly property real headH: Zenon.px(13) + 18
  readonly property real colW: Zenon.px(15) * 26
  readonly property real colGap: 28
  readonly property int colCount: Math.max(1, Math.min(4,
    Math.floor((sheet.width * 0.9 - 48 + sheet.colGap) / (sheet.colW + sheet.colGap))))

  // each group into whichever column is shortest so far, in order: the
  // groups read top to bottom, left to right, and the columns end level
  readonly property var columns: {
    const cols = [];
    const h = [];
    for (let i = 0; i < sheet.colCount; ++i) { cols.push([]); h.push(0); }
    for (const g of sheet.groups) {
      let k = 0;
      for (let i = 1; i < h.length; ++i) if (h[i] < h[k] - 1) k = i;
      cols[k].push(g);
      h[k] += sheet.headH + g.binds.length * sheet.rowH + 18;
    }
    return cols.filter((c) => c.length > 0);
  }

  // ── THE SCREEN ──
  Rectangle {
    anchors.fill: parent
    color: Zenon.darken(0.32)
    opacity: sheet.showFactor
    MouseArea { anchors.fill: parent; onClicked: sheet.close() }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(sheet.width - 48, Math.max(sheet.colW + 48, body.implicitWidth + 48))
    height: Math.min(sheet.height - 96, headRow.height + Math.max(120, scroller.contentHeight) + Zenon.hintBarH + 12)
    radius: Zenon.windowRadius
    color: Zenon.layerBg
    border.width: 1
    border.color: Zenon.border
    clip: true
    opacity: sheet.showFactor
    scale: 0.97 + 0.03 * sheet.showFactor

    // a click on the card is not a click on the screen behind it
    MouseArea { anchors.fill: parent }

    Item {
      id: headRow
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 64

      Text {
        anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
        text: "Shortcuts"
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(20)
      }

      // the filter: whatever is typed lands here, there is nothing to click
      Text {
        anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
        text: sheet.query !== "" ? sheet.query : sheet.count + " shortcuts"
        color: sheet.query !== "" ? Zenon.cyan : Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
    }

    Flickable {
      id: scroller
      anchors { left: parent.left; right: parent.right; top: headRow.bottom; bottom: foot.top; bottomMargin: 12 }
      contentWidth: width
      contentHeight: body.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Row {
        id: body
        x: Math.max(24, (scroller.width - implicitWidth) / 2)
        spacing: sheet.colGap

        Repeater {
          model: sheet.columns
          delegate: Column {
            required property var modelData
            width: sheet.colW
            spacing: 18

            Repeater {
              model: parent.modelData
              delegate: Column {
                id: grp
                required property var modelData
                width: sheet.colW

                SectionLabel {
                  text: grp.modelData.label
                  height: sheet.headH
                  verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                  model: grp.modelData.binds
                  delegate: Item {
                    id: row
                    required property var modelData
                    width: sheet.colW
                    height: sheet.rowH

                    Text {
                      anchors { left: parent.left; right: caps.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                      text: row.modelData.label
                      color: Zenon.white
                      elide: Text.ElideRight
                      font.family: Zenon.face
                      font.weight: Zenon.weight
                      font.pixelSize: Zenon.px(15)
                    }

                    Row {
                      id: caps
                      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                      spacing: 4
                      Repeater {
                        model: row.modelData.caps
                        delegate: KeyCap { required property var modelData; label: modelData; fontSize: 12 }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    ElasticScroll { anchors.fill: scroller; view: scroller }
    Scrollbar { flick: scroller; anchors.right: parent.right; anchors.top: scroller.top; anchors.bottom: scroller.bottom }

    EmptyState {
      anchors.centerIn: scroller
      visible: sheet.count === 0
      text: sheet.query !== "" ? "No shortcut matches" : "No shortcuts"
    }

    HintBar {
      id: foot
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      rows: [["type", "filter"], ["backspace", "erase"], ["return", "edit in settings"], ["esc", "close"]]
    }
  }

  Item {
    id: keys
    focus: sheet.shown
    Keys.onPressed: (e) => {
      if (e.key === Qt.Key_Escape) { sheet.close(); e.accepted = true; return; }
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
        sheet.close();
        Quickshell.execDetached(["qs", "ipc", "call", "Oracle", "at", "keys"]);
        e.accepted = true;
        return;
      }
      if (e.key === Qt.Key_Backspace) {
        sheet.query = (e.modifiers & Qt.ControlModifier) ? "" : sheet.query.slice(0, -1);
        e.accepted = true;
        return;
      }
      if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) {
        scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height,
          scroller.contentY + (e.key === Qt.Key_Down ? 1 : -1) * sheet.rowH * 3));
        e.accepted = true;
        return;
      }
      // a held peek types nothing: the keys still down are the bind's own
      if (sheet.heldAt > 0) return;
      if (e.text !== "" && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
          && e.text.charCodeAt(0) >= 32) {
        sheet.query += e.text;
        e.accepted = true;
      }
    }
    // the bind's release may never come (Super let go before the key), but
    // the sheet has the keyboard by then, so Super coming up is seen here
    Keys.onReleased: (e) => {
      if (e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R || e.key === Qt.Key_Meta)
        sheet.letGo();
    }
  }
}
