// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WINDOW RULES, unfolded — Windows' first row (user's pick, 2026-10-22).
//
// Your rules in the list frame Tools' packages stand in: a box to turn each
// on or off, its app, what it does; a click opens its editor under it, one
// at a time. "Add rule" lists the windows open now, by app (hyprctl clients),
// and the one you pick is the rule's app — no class names to look up. Every
// change is the whole list, handed to Oracle.setWindowRules, which writes
// hypr/lua/windows.lua and reloads hyprland: rules.lua makes each an
// hl.window_rule after the suite's own. See Ora's WINDOW RULES.
//
// The suite's own rules are listed under yours (user, 2026-10-24), from
// hypr/lua/windowdefaults.lua, and change the same way: a change is kept as
// a stand-in in windows.lua, and the × on a changed one puts it back as it
// ships. A shipped rule is not deleted — turn it off instead.
//
// Loaded by URL from OracleWindow, not named as a type (see ComputerPanel).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "oracle.js" as Ora
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus" as T

Item {
  id: wr
  // the panel's palette, handed in rather than reached for
  property string face: Zenon.face
  property color fgColor: Zenon.white
  property color dimColor: Zenon.accentMuted
  property color highlight: Zenon.cyan

  readonly property var rules: (Oracle.revision, Oracle.windowRules)
  readonly property var shipped: (Oracle.revision, Oracle.shippedRules)
  // what is listed: yours, then the shipped ones (Ora.windowRuleRows)
  readonly property var rows: Ora.windowRuleRows(wr.shipped, wr.rules)
  // the row whose editor is open, by index; -1 none
  property int open: -1
  // the open-window picker is up
  property bool picking: false
  // hyprctl clients, one per app (a suite window each): [{ cls, title, pin, name }]
  property var apps: []

  function patch(i, change) {
    Oracle.setWindowRules(Ora.windowRulesPatched(wr.shipped, wr.rules, i, change));
  }
  function remove(i) {
    // a shipped row stays where it is, put back; one of yours goes
    if (!wr.rows[i].shipped) {
      if (wr.open === i) wr.open = -1;
      else if (wr.open > i) wr.open--;
    }
    Oracle.setWindowRules(Ora.windowRulesRemoved(wr.shipped, wr.rules, i));
  }
  function add(cls, name, title) {
    const next = wr.rules.concat([Ora.blankWindowRule(cls, name, title)]);
    Oracle.setWindowRules(next);
    wr.picking = false;
    // the last of yours, which come before the shipped ones
    wr.open = Ora.windowRuleRows(wr.shipped, next).filter((w) => !w.shipped).length - 1;
  }
  // an app's own name, from its desktop entry when there is one
  function appName(cls) {
    const e = typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(cls) : null;
    return e && e.name ? e.name : cls;
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        let list = [];
        try { list = JSON.parse(this.text); } catch (e) {}
        wr.apps = Ora.windowPickRows(list, wr.shipped, wr.appName);
      }
    }
  }
  function pick() {
    wr.picking = !wr.picking;
    if (wr.picking) { wr.open = -1; clientsProc.running = true; }
  }

  implicitHeight: body.implicitHeight + 24

  Column {
    id: body
    x: 24
    y: 6
    width: wr.width - 48
    spacing: 10

    Text {
      visible: wr.rows.length === 0 && !wr.picking
      text: "No rules yet. Add one from a window that is open now."
      color: wr.dimColor
      font.family: wr.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }

    Row {
      spacing: 8
      DialogButton {
        label: wr.picking ? "Cancel" : "Add rule"
        ink: wr.picking ? wr.fgColor : wr.highlight
        primary: !wr.picking
        onClicked: wr.pick()
      }
    }

    // ── THE PICKER: what is open now, by app ────────────────────────────
    Item {
      visible: wr.picking
      width: body.width
      height: pickList.implicitHeight + 12
      Controls.ListFrame { anchors.fill: parent }
      Column {
        id: pickList
        x: 6
        y: 6
        width: parent.width - 12
        Text {
          visible: wr.apps.length === 0
          leftPadding: 10
          height: 28
          verticalAlignment: Text.AlignVCenter
          text: clientsProc.running ? "Looking…" : "No windows are open."
          color: wr.dimColor
          font.family: wr.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        Repeater {
          model: wr.apps
          delegate: Rectangle {
            id: app
            required property var modelData
            width: pickList.width
            height: 28
            radius: Zenon.windowRadius
            color: appTap.pressed ? Zenon.pressFill : appHover.hovered ? Zenon.wash(0.06) : "transparent"
            Text {
              id: appName
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: app.modelData.name
              color: wr.fgColor
              font.family: wr.face
              font.pixelSize: Zenon.px(16)
            }
            Text {
              anchors.left: appName.right
              anchors.leftMargin: 16
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              text: app.modelData.cls + (app.modelData.title ? " · " + app.modelData.title : "")
              color: wr.dimColor
              font.family: wr.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            HoverHandler { id: appHover }
            TapHandler { id: appTap; onTapped: wr.add(app.modelData.cls, app.modelData.name, app.modelData.pin) }
          }
        }
      }
    }

    // ── THE RULES ─────────────────────────────────────────────────────
    Item {
      visible: wr.rows.length > 0
      width: body.width
      height: list.implicitHeight + 12
      Controls.ListFrame { anchors.fill: parent }
      Column {
        id: list
        x: 6
        y: 6
        width: parent.width - 12
        Repeater {
          // count-keyed: an array model rebuilt on every change would make
          // the open editor (and its field's focus) start over
          model: wr.rows.length
          delegate: Column {
            id: ruleRow
            required property int index
            readonly property var w: wr.rows[ruleRow.index] || null
            readonly property var r: ruleRow.w ? ruleRow.w.rule : Ora.blankWindowRule("")
            readonly property bool isShipped: !!ruleRow.w && ruleRow.w.shipped !== ""
            readonly property bool isOpen: wr.open === ruleRow.index
            width: list.width

            // the shipped ones under a heading of their own, after yours
            SectionLabel {
              visible: ruleRow.isShipped && (ruleRow.index === 0 || !wr.rows[ruleRow.index - 1].shipped)
              leftPadding: 10
              topPadding: ruleRow.index === 0 ? 4 : 14
              bottomPadding: 6
              text: "Shipped"
            }

            Rectangle {
              width: parent.width
              height: 30
              radius: Zenon.windowRadius
              color: headTap.pressed ? Zenon.pressFill : ruleRow.isOpen ? Zenon.wash(0.05) : "transparent"
              Controls.Check {
                id: onBox
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                lit: ruleRow.r.on
                ink: wr.highlight
                onToggled: wr.patch(ruleRow.index, { on: !ruleRow.r.on })
              }
              Text {
                id: ruleName
                anchors.left: onBox.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width * 0.45)
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Strings.escapeHtml(ruleRow.r.name || ruleRow.r.class)
                  + (ruleRow.r.title ? "  <font color='" + wr.dimColor + "'>“"
                     + Strings.escapeHtml(ruleRow.r.title) + "”</font>" : "")
                color: ruleRow.r.on ? wr.fgColor : wr.dimColor
                font.family: wr.face
                font.pixelSize: Zenon.px(16)
              }
              Text {
                anchors.left: ruleName.right
                anchors.leftMargin: 16
                anchors.right: drop.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: Ora.windowRuleWords(ruleRow.r)
                color: wr.dimColor
                font.family: wr.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
              // deletes one of yours; on a shipped rule you changed, puts it
              // back as it ships; hidden on one left as it ships, its room
              // kept so the words do not shift when it comes
              ClearChip {
                id: drop
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                size: Zenon.px(14)
                shown: !ruleRow.isShipped || ruleRow.w.changed
                onClicked: wr.remove(ruleRow.index)
              }
              // between the box and the ×, so neither of theirs counts twice
              Item {
                anchors.left: onBox.right
                anchors.right: drop.left
                height: parent.height
                TapHandler {
                  id: headTap
                  onTapped: wr.open = ruleRow.isOpen ? -1 : ruleRow.index
                }
              }
            }

            // ── ITS EDITOR ──────────────────────────────────────────
            Loader {
              active: ruleRow.isOpen
              visible: active
              width: parent.width
              sourceComponent: Column {
                id: ed
                readonly property var r: ruleRow.r
                function set(change) { wr.patch(ruleRow.index, change); }
                leftPadding: 34
                topPadding: 6
                bottomPadding: 12
                spacing: 8

                Line {
                  label: "Name"
                  T.BulkField {
                    Layout.preferredWidth: 220
                    text: ed.r.name
                    ghost: ed.r.class
                    onFocusedChanged: if (!focused && text !== ed.r.name) ed.set({ name: text })
                    onAccepted: ed.set({ name: text })
                  }
                }
                Line {
                  label: "Window class"
                  T.BulkField {
                    Layout.preferredWidth: 220
                    mono: true
                    text: ed.r.class
                    onFocusedChanged: if (!focused && text !== "" && text !== ed.r.class) ed.set({ class: text })
                    onAccepted: if (text !== "") ed.set({ class: text })
                  }
                }
                Line {
                  label: "Title has"
                  T.BulkField {
                    Layout.preferredWidth: 220
                    text: ed.r.title
                    ghost: "any window of the app"
                    onFocusedChanged: if (!focused && text !== ed.r.title) ed.set({ title: text })
                    onAccepted: ed.set({ title: text })
                  }
                }
                Line {
                  label: "Floating"
                  Controls.Check { lit: ed.r.float; ink: wr.highlight; onToggled: ed.set({ float: !ed.r.float }) }
                  // the size only means something to a floating window
                  T.BulkField {
                    id: wField
                    visible: ed.r.float
                    Layout.preferredWidth: 70
                    ghost: "width"
                    text: ed.r.size ? ed.r.size.split(" ")[0] : ""
                    onAccepted: ed.setSize()
                    onFocusedChanged: if (!focused) ed.setSize()
                  }
                  Text {
                    visible: ed.r.float
                    text: "×"
                    color: wr.dimColor
                    font.family: wr.face
                    font.pixelSize: Zenon.px(15)
                  }
                  T.BulkField {
                    id: hField
                    visible: ed.r.float
                    Layout.preferredWidth: 70
                    ghost: "height"
                    text: ed.r.size ? ed.r.size.split(" ")[1] : ""
                    onAccepted: ed.setSize()
                    onFocusedChanged: if (!focused) ed.setSize()
                  }
                  Controls.Check {
                    visible: ed.r.float
                    label: "Pinned"
                    lit: ed.r.pin
                    ink: wr.highlight
                    onToggled: ed.set({ pin: !ed.r.pin })
                  }
                  // hyprland's persistent_size: reopens at the size it was
                  // left at, which a size above is only the first of
                  Controls.Check {
                    visible: ed.r.float
                    label: "Remember size"
                    lit: ed.r.persistent_size
                    ink: wr.highlight
                    onToggled: ed.set({ persistent_size: !ed.r.persistent_size })
                  }
                }
                // both numbers or neither: half a size is no size
                function setSize() {
                  const w = parseInt(wField.text), h = parseInt(hField.text);
                  const size = w > 0 && h > 0 ? w + " " + h : "";
                  if (size !== ed.r.size && (size !== "" || (wField.text === "" && hField.text === ""))) ed.set({ size: size });
                }
                Line {
                  label: "Centered"
                  Controls.Check { lit: ed.r.center; ink: wr.highlight; onToggled: ed.set({ center: !ed.r.center }) }
                }
                Line {
                  label: "Opens"
                  T.Segments {
                    options: [["", "Normal"], ["maximize", "Maximized"], ["fullscreen", "Full screen"]]
                    current: ed.r.open
                    onChose: (v) => ed.set({ open: v })
                  }
                }
                Line {
                  label: "Workspace"
                  T.Segments {
                    options: [["", "Any"], ["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["5", "5"],
                              ["6", "6"], ["7", "7"], ["8", "8"], ["9", "9"], ["special", "Special"]]
                    current: ed.r.workspace
                    pad: 18
                    onChose: (v) => ed.set({ workspace: v })
                  }
                  Controls.Check {
                    visible: ed.r.workspace !== ""
                    label: "Stay where I am"
                    lit: ed.r.silent
                    ink: wr.highlight
                    onToggled: ed.set({ silent: !ed.r.silent })
                  }
                }
                Line {
                  label: "Opacity"
                  T.Segments {
                    options: [["100", "100%"], ["95", "95%"], ["90", "90%"], ["85", "85%"], ["80", "80%"], ["70", "70%"], ["60", "60%"]]
                    current: String(ed.r.opacity)
                    pad: 18
                    onChose: (v) => ed.set({ opacity: Number(v) })
                  }
                }
                Line {
                  label: "Keep awake"
                  T.Segments {
                    options: [["", "No"], ["focus", "While focused"], ["fullscreen", "In full screen"], ["always", "Always"]]
                    current: ed.r.idle_inhibit
                    onChose: (v) => ed.set({ idle_inhibit: v })
                  }
                }
                Line {
                  label: "Also"
                  Controls.Check { label: "No blur behind"; lit: ed.r.no_blur; ink: wr.highlight; onToggled: ed.set({ no_blur: !ed.r.no_blur }) }
                  Controls.Check { label: "Opens without focus"; lit: ed.r.no_initial_focus; ink: wr.highlight; onToggled: ed.set({ no_initial_focus: !ed.r.no_initial_focus }) }
                }
                Text {
                  text: "Takes hold for windows opened from now on."
                  color: wr.dimColor
                  font.family: wr.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                }
              }
            }
          }
        }
      }
    }
  }

  // a label and what sets it, on one line
  // (RowLayout: it centers what it holds, a box beside a field)
  component Line: RowLayout {
    property string label: ""
    spacing: 12
    Text {
      Layout.preferredWidth: 120
      Layout.preferredHeight: 28
      verticalAlignment: Text.AlignVCenter
      text: parent.label
      color: wr.dimColor
      font.family: wr.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
  }
}
