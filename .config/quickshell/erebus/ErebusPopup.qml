// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
  id: popup

  WlrLayershell.layer: WlrLayer.Overlay

  property bool shown: false
  property string confirmId: ""
  property int sel: 0

  readonly property string xdgSession: Quickshell.env("XDG_SESSION_ID") || ""

  property var entries: [
    { id: "lockscreen", label: "", cmd: "hyprlock", confirm: false },
    { id: "logout", label: "󰍃", cmd: "hyprshutdown -p 'loginctl terminate-session " + xdgSession + "'", confirm: true },
    { id: "suspend", label: "󰤄", cmd: "systemctl suspend", confirm: true },
    { id: "reboot", label: "", cmd: "hyprshutdown -p 'systemctl reboot'", confirm: true },
    { id: "shutdown", label: "⏻", cmd: "hyprshutdown -p 'systemctl poweroff'", confirm: true }
  ]

  property var confirmActions: [
    { id: "confirm", label: "" },
    { id: "cancel", label: "" }
  ]

  property var statusbar: null

  visible: bg.opacity > 0.01
  color: "transparent"
  anchors { left: true; right: true; top: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore
  focusable: true

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closeSession()
  }

  IpcHandler {
    target: "Erebus"
    function toggle() {
      popup.toggle();
    }
  }

  function currentList() {
    return popup.confirmId === "" ? popup.entries : popup.confirmActions;
  }

  function currentEntry() {
    for (let i = 0; i < popup.entries.length; ++i) {
      if (popup.entries[i].id === popup.confirmId) return popup.entries[i];
    }
    return null;
  }

  function openSession() {
    popup.shown = true;
    popup.confirmId = "";
    popup.sel = 0;
    focusRetry.counter = 0;
    focusRetry.restart();
  }

  function closeSession() {
    popup.shown = false;
  }

  function toggle() {
    if (popup.shown) popup.closeSession();
    else popup.openSession();
  }

  function execute(cmd) {
    Quickshell.execDetached(["sh", "-c", cmd + " >/dev/null 2>&1 &"]);
  }

  function confirm() {
    const list = popup.currentList();
    const item = list[popup.sel];
    if (!item) return;
    if (popup.confirmId === "") {
      const entry = item;
      if (!entry.confirm) {
        popup.execute(entry.cmd);
        popup.closeSession();
      } else {
        popup.confirmId = entry.id;
        popup.sel = 0;
      }
    } else {
      if (item.id === "confirm") {
        const e = popup.currentEntry();
        if (e) {
          popup.execute(e.cmd);
          popup.closeSession();
        }
      } else {
        popup.confirmId = "";
        popup.sel = 0;
      }
    }
  }

  function moveSel(delta) {
    const len = popup.currentList().length;
    if (len === 0) return;
    popup.sel = (popup.sel + delta + len) % len;
  }

  Timer {
    id: focusRetry
    interval: 60
    repeat: true
    onTriggered: {
      if (!popup.shown) {
        stop();
        return;
      }
      content.forceActiveFocus();
      if (content.activeFocus) stop();
      if (focusRetry.counter++ > 12) stop();
    }
    property int counter: 0
  }

  MouseArea {
    id: closeArea
    anchors.fill: parent
    onClicked: popup.closeSession()
  }

  Item {
    id: panel
    width: 250
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: popup.screen && popup.statusbar && popup.statusbar.screen && popup.screen.name === popup.statusbar.screen.name ? popup.statusbar.height : 0
    height: popup.confirmId === "" ? 36 : 72
    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Rectangle {
      id: bg
      anchors.fill: parent
      color: "#e78284"
      radius: 6
      topLeftRadius: 6
      topRightRadius: 6
      bottomLeftRadius: 0
      bottomRightRadius: 0
      border.width: 0
      clip: true

      opacity: popup.shown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      transform: Translate {
        y: popup.shown ? 0 : bg.height
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      }

      Item {
        id: content
        anchors.fill: parent
        clip: true
        focus: true
        Keys.forwardTo: content

        Item {
          id: mainView
          anchors.fill: parent
          visible: opacity > 0.01
          opacity: popup.confirmId === "" ? 1 : 0
          x: popup.confirmId === "" ? 0 : -12
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

          Grid {
            anchors.centerIn: parent
            columns: 5
            columnSpacing: 0
            rowSpacing: 0
            Repeater {
              model: popup.entries
              delegate: Item {
                required property var modelData
                required property int index
                width: 50
                height: 36

                Rectangle {
                  anchors.fill: parent
                  color: popup.confirmId === "" && index === popup.sel ? "#eebebe" : "transparent"
                  radius: 6
                  topLeftRadius: index === 0 ? 6 : 0
                  topRightRadius: index === 4 ? 6 : 0
                  bottomLeftRadius: 0
                  bottomRightRadius: 0
                }

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: "#000000"
                  font.family: "JetBrainsMono Nerd Font Propo"
                  font.weight: Font.Bold
                  font.pixelSize: 18
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    popup.sel = index;
                    popup.confirm();
                  }
                }
              }
            }
          }
        }

        Column {
          id: confirmView
          anchors.fill: parent
          visible: opacity > 0.01
          opacity: popup.confirmId !== "" ? 1 : 0
          x: popup.confirmId !== "" ? 0 : 12
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

          Rectangle {
            width: parent.width + 2
            height: 37
            x: -1
            y: -1
            color: "#000000"
            radius: 6
            topLeftRadius: 6
            topRightRadius: 6
            bottomLeftRadius: 0
            bottomRightRadius: 0
            clip: true
            Text {
              anchors.centerIn: parent
              text: {
                const e = popup.currentEntry();
                return e ? e.label : "";
              }
              color: "#e78284"
              font.family: "JetBrainsMono Nerd Font Propo"
              font.weight: Font.Bold
              font.pixelSize: 18
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
          }

          Row {
            width: parent.width
            height: 36
            Repeater {
              model: popup.confirmActions
              delegate: Item {
                required property var modelData
                required property int index
                width: parent.width / 2
                height: parent.height

                Rectangle {
                  anchors.fill: parent
                  color: index === popup.sel ? "#eebebe" : "transparent"
                  radius: 0
                }

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: "#000000"
                  font.family: "JetBrainsMono Nerd Font Propo"
                  font.weight: Font.Bold
                  font.pixelSize: 18
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    popup.sel = index;
                    popup.confirm();
                  }
                }
              }
            }
          }
        }

        Keys.onEscapePressed: (event) => {
          if (popup.confirmId !== "") {
            popup.confirmId = "";
            popup.sel = 0;
          } else {
            popup.closeSession();
          }
        }
        Keys.onReturnPressed: (event) => {
          event.accepted = true;
          popup.confirm();
        }
        Keys.onLeftPressed: popup.moveSel(-1)
        Keys.onRightPressed: popup.moveSel(1)
        Keys.onTabPressed: popup.moveSel(1)
        Keys.onBacktabPressed: popup.moveSel(-1)
        Keys.onUpPressed: popup.moveSel(-1)
        Keys.onDownPressed: popup.moveSel(1)
      }
    }
  }
}
