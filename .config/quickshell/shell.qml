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

      UpdateModule { id: updateMod; implicitHeight: 32 }
      TrayExpander { id: trayMod; implicitHeight: 32 }
      Item { implicitWidth: 8; implicitHeight: 32; visible: updateMod.hasUpdates || trayMod.hasTray }
      Divider { implicitHeight: 32; visible: updateMod.hasUpdates || trayMod.hasTray }
      Item { implicitWidth: 8; implicitHeight: 32; visible: updateMod.hasUpdates || trayMod.hasTray }
      Workspaces { implicitHeight: 32 }

      Item {
        Layout.fillWidth: true
        height: 1
      }

      NetworkModule { implicitHeight: 32 }
      Item { implicitWidth: 8; implicitHeight: 32 }
      Divider { implicitHeight: 32 }
      Item { implicitWidth: 8; implicitHeight: 32 }
      GpuModule { implicitHeight: 32 }
      Item { implicitWidth: 8; implicitHeight: 32 }
      CpuModule { implicitHeight: 32 }
      TemperatureModule { implicitHeight: 32 }
      Item { implicitWidth: 8; implicitHeight: 32 }
      MemoryModule { implicitHeight: 32 }
      Item { implicitWidth: 8; implicitHeight: 32 }
      Divider { implicitHeight: 32 }
      Item { implicitWidth: 8; implicitHeight: 32 }
      Item {
        id: audioGroup
        implicitWidth: audioRow.implicitWidth
        implicitHeight: 32
        Layout.preferredWidth: audioRow.implicitWidth
        Layout.preferredHeight: 32
        Row {
          id: audioRow
          anchors.verticalCenter: parent.verticalCenter
          MprisModule { id: mprisMod; implicitHeight: 32 }
          PulseAudioModule { id: pulseMod; implicitHeight: 32 }
        }
      }
      ClockModule { implicitHeight: 32 }
    }

    Tooltip {
      anchorItem: audioGroup
      show: mprisMod.hovered || pulseMod.hovered
      text: {
        const m = mprisMod.mprisTooltipText;
        const v = pulseMod.tooltipText;
        if (m && v) return m + "\n\n" + v;
        if (m) return m;
        return v;
      }
    }
  }
}
