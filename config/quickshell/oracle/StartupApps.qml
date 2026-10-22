// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// STARTUP APPS, unfolded — Windows' second row (user's pick, 2026-10-22).
//
// Two lists in the Tools fold's frame. The shell's own (autostart.lua's
// lines, Ora.STARTUP_OWN), read-only, each with a dot that says whether it
// is running now: hyprpolkitagent once failed at login and nothing said so
// until Hestia looked (2026-10-20). Then yours (hypr/lua/startup.lua): a box
// to turn each on or off, its name, its command, its delay, the same dot; a
// click opens its editor, which can also start it now. "Add app" lists the
// installed apps to filter; "Add command" is a blank one. Every change is
// the whole list, handed to Oracle.setStartupApps. See Ora's STARTUP.
//
// Running is read from `ps -eo args=`, every few seconds while unfolded.
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
  id: sa
  // the panel's palette, handed in rather than reached for
  property string face: Zenon.face
  property color fgColor: Zenon.white
  property color dimColor: Zenon.accentMuted
  property color highlight: Zenon.cyan

  readonly property var apps: (Oracle.revision, Oracle.startupApps)
  property int open: -1
  // "" | "apps": the installed apps' list is up
  property bool picking: false
  property string query: ""
  property string ps: ""
  property bool psRead: false

  function running(look) { return Ora.startupRunning(sa.ps, look); }

  function patch(i, change) {
    const next = sa.apps.map((a) => Object.assign({}, a));
    Object.assign(next[i], change);
    Oracle.setStartupApps(next);
  }
  function remove(i) {
    const next = sa.apps.slice();
    next.splice(i, 1);
    if (sa.open === i) sa.open = -1;
    else if (sa.open > i) sa.open--;
    Oracle.setStartupApps(next);
  }
  function add(name, command) {
    const next = sa.apps.concat([{ name: name, command: command, on: true, delay: 0 }]);
    // a blank command is kept here until it is typed: the file drops it
    Oracle.setStartupApps(next);
    sa.picking = false;
    sa.open = next.length - 1;
  }
  // what a desktop entry runs, without its field codes (%U and the like)
  function execOf(e) {
    const x = Ora.execForStartup(e.execString);
    return x !== "" ? x : "gtk-launch " + e.id;
  }
  readonly property var installed: {
    if (!sa.picking) return [];
    const q = sa.query.toLowerCase();
    const vals = DesktopEntries.applications.values;
    const out = [];
    for (let i = 0; i < vals.length; ++i) {
      const e = vals[i];
      if (!e || e.noDisplay) continue;
      if (q && String(e.name).toLowerCase().indexOf(q) < 0 && String(e.id).toLowerCase().indexOf(q) < 0) continue;
      out.push({ name: String(e.name), id: String(e.id), command: sa.execOf(e) });
    }
    out.sort((a, b) => a.name.localeCompare(b.name));
    return out.slice(0, 40);
  }

  Process {
    id: psProc
    command: ["ps", "-eo", "args="]
    stdout: StdioCollector {
      onStreamFinished: { sa.ps = this.text; sa.psRead = true; }
    }
  }
  Timer {
    interval: 4000
    running: sa.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!psProc.running) psProc.running = true
  }

  implicitHeight: body.implicitHeight + 24

  Column {
    id: body
    x: 24
    y: 6
    width: sa.width - 48
    spacing: 10

    Item {
      width: body.width
      height: list.implicitHeight + 12
      Controls.ListFrame { anchors.fill: parent }
      Column {
        id: list
        x: 6
        y: 6
        width: parent.width - 12

        Head { text: "The shell's own" }
        Repeater {
          model: Ora.startupOwn()
          delegate: Item {
            id: own
            required property var modelData
            width: list.width
            height: 28
            Dot { id: ownDot; x: 10; anchors.verticalCenter: parent.verticalCenter; up: sa.running(own.modelData.look) }
            Text {
              anchors.left: ownDot.right
              anchors.leftMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: own.modelData.name
              color: sa.fgColor
              font.family: sa.face
              font.pixelSize: Zenon.px(16)
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: !sa.psRead ? "" : sa.running(own.modelData.look) ? "running" : "not running"
              color: sa.running(own.modelData.look) ? sa.dimColor : Zenon.red
              font.family: sa.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
          }
        }

        Head { text: sa.apps.length ? "Yours" : "Yours · none yet" }
        Repeater {
          model: sa.apps.length
          delegate: Column {
            id: appRow
            required property int index
            readonly property var a: sa.apps[appRow.index] || Ora.normStartup({})
            readonly property bool isOpen: sa.open === appRow.index
            readonly property string look: Ora.startupLook(appRow.a.command)
            width: list.width

            Rectangle {
              width: parent.width
              height: 30
              radius: Zenon.windowRadius
              color: rowTap.pressed ? Zenon.pressFill : appRow.isOpen ? Zenon.wash(0.05) : "transparent"
              Controls.Check {
                id: onBox
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                lit: appRow.a.on
                ink: sa.highlight
                onToggled: sa.patch(appRow.index, { on: !appRow.a.on })
              }
              Text {
                id: appName
                anchors.left: onBox.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width * 0.35)
                elide: Text.ElideRight
                text: appRow.a.name || Ora.startupName(appRow.a.command) || "New app"
                color: appRow.a.on ? sa.fgColor : sa.dimColor
                font.family: sa.face
                font.pixelSize: Zenon.px(16)
              }
              Text {
                anchors.left: appName.right
                anchors.leftMargin: 16
                anchors.right: runState.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: appRow.a.command + (appRow.a.delay ? "  · after " + appRow.a.delay + " s" : "")
                color: sa.dimColor
                font.family: Zenon.faceMono
                font.pixelSize: Zenon.px(13)
              }
              Text {
                id: runState
                anchors.right: drop.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: !sa.psRead || !appRow.look ? "" : sa.running(appRow.look) ? "running" : "not running"
                color: sa.dimColor
                font.family: sa.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
              ClearChip {
                id: drop
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                size: Zenon.px(14)
                onClicked: sa.remove(appRow.index)
              }
              // between the box and the ×, so neither of theirs counts twice
              Item {
                anchors.left: onBox.right
                anchors.right: drop.left
                height: parent.height
                TapHandler {
                  id: rowTap
                  onTapped: sa.open = appRow.isOpen ? -1 : appRow.index
                }
              }
            }

            Loader {
              active: appRow.isOpen
              visible: active
              width: parent.width
              sourceComponent: Column {
                id: ed
                readonly property var a: appRow.a
                function set(change) { sa.patch(appRow.index, change); }
                leftPadding: 34
                topPadding: 6
                bottomPadding: 12
                spacing: 8
                Line {
                  label: "Name"
                  T.BulkField {
                    Layout.preferredWidth: 240
                    text: ed.a.name
                    ghost: Ora.startupName(ed.a.command)
                    onFocusedChanged: if (!focused && text !== ed.a.name) ed.set({ name: text })
                    onAccepted: ed.set({ name: text })
                  }
                }
                Line {
                  label: "Command"
                  T.BulkField {
                    id: cmdField
                    Layout.preferredWidth: 420
                    mono: true
                    text: ed.a.command
                    ghost: "what to run, as in a terminal"
                    onFocusedChanged: if (!focused && text !== ed.a.command) ed.set({ command: text })
                    onAccepted: ed.set({ command: text })
                    Component.onCompleted: if (ed.a.command === "") claim()
                  }
                }
                Line {
                  label: "Start"
                  T.Segments {
                    options: [["0", "At login"], ["5", "After 5 s"], ["10", "10 s"], ["30", "30 s"], ["60", "1 min"]]
                    current: String(ed.a.delay)
                    onChose: (v) => ed.set({ delay: Number(v) })
                  }
                }
                Line {
                  label: ""
                  DialogButton {
                    label: "Start now"
                    ink: sa.highlight
                    ready: ed.a.command.trim() !== ""
                    onClicked: {
                      Quickshell.execDetached(["sh", "-c", ed.a.command]);
                      psLater.restart();
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // ── THE INSTALLED APPS, to filter ──────────────────────────────────
    Column {
      visible: sa.picking
      width: body.width
      spacing: 8
      T.BulkField {
        id: filter
        width: 280
        ghost: "Filter apps"
        clearable: true
        onTextChanged: sa.query = text
      }
      Item {
        width: body.width
        height: pickList.implicitHeight + 12
        Controls.ListFrame { anchors.fill: parent }
        Column {
          id: pickList
          x: 6
          y: 6
          width: parent.width - 12
          Text {
            visible: sa.installed.length === 0
            leftPadding: 10
            height: 28
            verticalAlignment: Text.AlignVCenter
            text: "No app by that name."
            color: sa.dimColor
            font.family: sa.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
          Repeater {
            model: sa.installed
            delegate: Rectangle {
              id: inst
              required property var modelData
              width: pickList.width
              height: 28
              radius: Zenon.windowRadius
              color: instTap.pressed ? Zenon.pressFill : instHover.hovered ? Zenon.wash(0.06) : "transparent"
              Text {
                id: instName
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: inst.modelData.name
                color: sa.fgColor
                font.family: sa.face
                font.pixelSize: Zenon.px(16)
              }
              Text {
                anchors.left: instName.right
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: inst.modelData.command
                color: sa.dimColor
                font.family: Zenon.faceMono
                font.pixelSize: Zenon.px(13)
              }
              HoverHandler { id: instHover }
              TapHandler { id: instTap; onTapped: sa.add(inst.modelData.name, inst.modelData.command) }
            }
          }
        }
      }
    }

    Row {
      spacing: 8
      DialogButton {
        label: sa.picking ? "Cancel" : "Add app"
        ink: sa.picking ? sa.fgColor : sa.highlight
        primary: !sa.picking
        onClicked: {
          sa.picking = !sa.picking;
          if (sa.picking) { sa.open = -1; filter.text = ""; filter.claim(); }
        }
      }
      DialogButton {
        visible: !sa.picking
        label: "Add command"
        ink: sa.fgColor
        onClicked: sa.add("", "")
      }
    }
  }

  // a started app shows as running a moment later, not at the next tick
  Timer { id: psLater; interval: 1200; onTriggered: if (!psProc.running) psProc.running = true }

  component Head: Text {
    leftPadding: 10
    height: 28
    verticalAlignment: Text.AlignVCenter
    color: sa.dimColor
    font.family: sa.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(15)
  }
  // green while it runs, red when the shell's own is not
  component Dot: Rectangle {
    property bool up: false
    width: 6
    height: 6
    radius: 3
    color: !sa.psRead ? sa.dimColor : up ? Zenon.green : Zenon.red
    opacity: 0.8
  }
  component Line: RowLayout {
    property string label: ""
    spacing: 12
    Text {
      Layout.preferredWidth: 120
      Layout.preferredHeight: 28
      verticalAlignment: Text.AlignVCenter
      text: parent.label
      color: sa.dimColor
      font.family: sa.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
  }
}
