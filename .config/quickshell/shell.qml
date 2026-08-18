//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "."

ShellRoot {
  id: root

  property var hdmiScreen: (function() {
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; ++i) {
      if (screens[i].name === "HDMI-A-1") return screens[i];
    }
    return screens.length ? screens[0] : null;
  })()

  PanelWindow {
    id: bar
    anchors { left: true; right: true; bottom: true }
    implicitHeight: 32
    screen: root.hdmiScreen
    exclusionMode: ExclusionMode.Auto
    color: "transparent"

    RowLayout {
      id: barLayout
      anchors.fill: parent
      spacing: 0

      UpdateModule { implicitHeight: 32 }
      TrayExpander { implicitHeight: 32 }
      Workspaces { implicitHeight: 32 }

      Item {
        Layout.fillWidth: true
        height: 1
      }

      NetworkModule { implicitHeight: 32 }
      Divider { implicitHeight: 32 }
      NvidiaModule { implicitHeight: 32 }
      Divider { implicitHeight: 32 }
      CpuModule { implicitHeight: 32 }
      TemperatureModule { implicitHeight: 32 }
      Divider { implicitHeight: 32 }
      MemoryModule { implicitHeight: 32 }
      MprisModule { implicitHeight: 32 }
      PulseAudioModule { implicitHeight: 32 }
      ClockModule { implicitHeight: 32 }
      StatusModule { implicitHeight: 32 }
    }
  }
}
