// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES' BLUETOOTH PAGE — the adapter, your devices, and the ones nearby
// while it searches. Where BlueZ is missing or stopped, the button that
// installs or starts it; where there is no adapter, only that.

import QtQuick
import Quickshell
import "../morpheus"
import "../morpheus/controls" as Ctl
import "hermes.js" as H

Column {
  id: page

  property var win: null
  property int sel: 0
  // one cursor over both lists: yours first, then nearby
  readonly property var mine: Hermes.devices.filter((d) => d.paired)
  readonly property var nearby: Hermes.devices.filter((d) => !d.paired)
  readonly property int count: Hermes.btReady ? page.mine.length + page.nearby.length : 0
  function rowAt(i) { return i < page.mine.length ? page.mine[i] : page.nearby[i - page.mine.length] || null; }

  spacing: 16

  HermesSetup {
    width: parent.width
    topPadding: 40
    visible: Hermes.probe.known && !Hermes.probe.bt.hw && !Hermes.btReady
    glyph: H.G.btOff
    title: "No Bluetooth adapter"
    body: "Hermes found no Bluetooth hardware on this machine. A USB Bluetooth adapter shows up here once it is plugged in."
  }
  HermesSetup {
    width: parent.width
    topPadding: 40
    visible: Hermes.probe.bt.hw && !Hermes.probe.bt.installed && !Hermes.btReady
    glyph: H.G.bt
    ink: Zenon.blue
    title: "Bluetooth is not set up"
    body: "BlueZ, Linux's Bluetooth service, is not installed. Hermes installs it through Ceres and starts it."
    action: "Install Bluetooth"
    busy: Hermes.setupKind === "bluetooth"
    onGo: Hermes.setup("bluetooth")
  }
  // running, by systemd's word, and still not seen: quickshell's Bluetooth
  // module was asked before BlueZ existed and does not look again until
  // the shell restarts (2026-10-20: BlueZ installed, a USB adapter plugged
  // in, the page still said "stopped")
  // the adapter is in the kernel and BlueZ runs, but it never got the
  // adapter: the hardware failed to start, and nothing here can fix that
  HermesSetup {
    width: parent.width
    topPadding: 40
    visible: H.btStuck(Hermes.probe) && !Hermes.btReady
    glyph: H.G.btOff
    ink: Zenon.yellow
    title: "The adapter is not answering"
    body: "Linux sees a Bluetooth adapter, but it did not respond when it was started, so BlueZ could not use it. "
      + "Plugging it into another port (USB 2.0 if there is one) or reloading its driver often helps; "
      + "some unbranded dongles never work on Linux. The kernel log (journalctl -k) says why."
    action: "Look again"
    onGo: Hermes.reprobe()
    action2: "Turn off Bluetooth"
    busy: Hermes.setupKind === "bluetoothStop"
    onGo2: Hermes.setup("bluetoothStop")
  }
  HermesSetup {
    width: parent.width
    topPadding: 40
    visible: Hermes.probe.bt.running && !H.btStuck(Hermes.probe) && !Hermes.btReady
    glyph: H.G.bt
    ink: Zenon.blue
    title: "Bluetooth is running"
    body: "BlueZ is up, but the shell looked for it before it was there and does not look again on its own. Restarting the shell connects to it."
    action: "Restart the shell"
    onGo: Quickshell.execDetached([Quickshell.shellDir + "/scripts/restart.sh"])
    action2: "Turn off Bluetooth"
    busy: Hermes.setupKind === "bluetoothStop"
    onGo2: Hermes.setup("bluetoothStop")
  }
  HermesSetup {
    width: parent.width
    topPadding: 40
    visible: Hermes.probe.bt.installed && !Hermes.probe.bt.running && !Hermes.btReady
    glyph: H.G.btOff
    ink: Zenon.blue
    title: "Bluetooth is stopped"
    body: "BlueZ is installed but its service is not running. Starting it also starts it at every boot."
    action: "Start Bluetooth"
    busy: Hermes.setupKind === "bluetoothStart"
    onGo: Hermes.setup("bluetoothStart")
  }

  HermesCard {
    visible: Hermes.btReady
    glyph: Hermes.btOn ? H.G.bt : H.G.btOff
    glyphInk: Hermes.btOn ? Zenon.blue : Zenon.accentMuted
    title: "Bluetooth"
    note: Hermes.adapter ? Hermes.adapter.name : ""
    trailing: [
      Ctl.Check {
        lit: Hermes.btOn
        onToggled: Hermes.setBluetooth(!Hermes.btOn)
      }
    ]
    Item {
      width: parent.width
      height: 38
      Ctl.Check {
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        label: "Visible to other devices"
        lit: !!Hermes.adapter && Hermes.adapter.discoverable
        enabled2: Hermes.btOn
        onToggled: Hermes.setDiscoverable(!(Hermes.adapter && Hermes.adapter.discoverable))
      }
    }
  }

  HermesCard {
    visible: Hermes.btReady && Hermes.btOn
    glyph: H.G.btOn
    glyphInk: Zenon.blue
    title: "My devices"
    note: page.mine.length === 0 ? "" : page.mine.filter((d) => d.connected).length + " connected"
    EmptyState {
      width: parent.width
      height: 54
      verticalAlignment: Text.AlignVCenter
      visible: page.mine.length === 0
      text: "Nothing paired yet — Search finds devices nearby"
    }
    Item {
      width: parent.width
      height: mineCol.height + (page.mine.length > 0 ? 8 : 0)
      visible: page.mine.length > 0
      CursorBand {
        parent: mineCol.parent
        repeater: mineRep
        index: page.sel < page.mine.length ? page.sel : -1
        shown: page.sel < page.mine.length && (page.win ? page.win.listFocus : true)
      }
      Column {
        id: mineCol
        width: parent.width
        Repeater {
          id: mineRep
          model: page.mine.length
          delegate: HermesRow {
            readonly property var modelData: page.mine[index] || ({})
            required property int index
            width: mineCol.width
            height: 42
            kind: "bt"
            row: modelData
            picked: index === page.sel
            onClicked: { page.sel = index; if (page.win) page.win.activate(); }
          }
        }
      }
    }
  }

  HermesCard {
    visible: Hermes.btReady && Hermes.btOn && (page.nearby.length > 0 || Hermes.btScanning)
    glyph: H.G.scan
    glyphInk: Hermes.btScanning ? Zenon.cyan : Zenon.accentMuted
    title: "Nearby"
    note: Hermes.btScanning ? "Searching…" : ""
    EmptyState {
      width: parent.width
      height: 54
      verticalAlignment: Text.AlignVCenter
      visible: page.nearby.length === 0
      text: "Put the device in pairing mode"
    }
    Item {
      width: parent.width
      height: nearCol.height + (page.nearby.length > 0 ? 8 : 0)
      visible: page.nearby.length > 0
      CursorBand {
        parent: nearCol.parent
        repeater: nearRep
        index: page.sel - page.mine.length
        shown: page.sel >= page.mine.length && (page.win ? page.win.listFocus : true)
      }
      Column {
        id: nearCol
        width: parent.width
        Repeater {
          id: nearRep
          model: page.nearby.length
          delegate: HermesRow {
            readonly property var modelData: page.nearby[index] || ({})
            required property int index
            width: nearCol.width
            height: 42
            kind: "bt"
            row: modelData
            picked: index + page.mine.length === page.sel
            onClicked: { page.sel = index + page.mine.length; if (page.win) page.win.activate(); }
          }
        }
      }
    }
  }
}
