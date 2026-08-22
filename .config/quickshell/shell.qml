// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "dash"
import "runner"
import "folio"
import "erebus"
import "scout"
import "lexi"
import "hitman"
import "ideo"
import "vault"
import "adder"

ShellRoot {
  id: root

  RunnerPopup {
    id: runner
    statusbar: bar
  }

  FolioPopup {
    id: folio
    statusbar: bar
  }

  ErebusPopup {
    id: erebus
    statusbar: bar
  }

  ScoutPopup {
    id: scout
    statusbar: bar
  }

  LexiPopup {
    id: lexi
    statusbar: bar
  }

  HitmanPopup {
    id: hitman
    statusbar: bar
  }

  IdeoPopup {
    id: ideo
    statusbar: bar
  }

  VaultPopup {
    id: vault
    statusbar: bar
  }

  AdderPopup {
    id: adder
    statusbar: bar
  }

  property var statusScreen: (function() {
    const target = Quickshell.env("QS_STATUS_SCREEN") || "HDMI-A-1";
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; ++i) {
      if (screens[i].name === target) return screens[i];
    }
    return screens.length ? screens[0] : null;
  })()

  PanelWindow {
      id: bar
      anchors { left: true; right: true; bottom: true }
      implicitHeight: 32
      screen: root.statusScreen
      exclusionMode: ExclusionMode.Auto
      color: "#80000000"

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
      GpuModule { implicitHeight: 32 }
      Divider { implicitHeight: 32 }
      CpuModule { implicitHeight: 32 }
      TemperatureModule { implicitHeight: 32 }
      Divider { implicitHeight: 32 }
      MemoryModule { implicitHeight: 32 }
      MprisModule { implicitHeight: 32 }
      PulseAudioModule { implicitHeight: 32 }
      ClockModule { implicitHeight: 32 }
    }
  }
}
