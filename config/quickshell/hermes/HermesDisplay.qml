// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES' DISPLAY PAGE — brightness for every screen that can be dimmed
// (a laptop's own panel through its backlight, a monitor over DDC/CI with
// ddcutil), and the night light (hyprsunset): on by hand or from sunset to
// sunrise, and how warm.

import QtQuick
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "hermes.js" as H

Column {
  id: page

  property var win: null
  property int sel: 0
  readonly property int count: 0
  readonly property bool canDdc: Hermes.probe.display.ddcutil && Hermes.probe.display.i2c

  spacing: 16

  HermesCard {
    glyph: H.G.sun
    glyphInk: Hermes.screens.length > 0 ? Zenon.yellow : Zenon.accentMuted
    title: "Brightness"
    note: Hermes.ddcReading ? "Asking the monitors…" : ""

    // by count, so a drag keeps its slider (see the quick panel's)
    Repeater {
      model: Hermes.screens.length
      delegate: PrefSlider {
        required property int index
        readonly property var modelData: Hermes.screens[index] || ({ label: "", pct: 0 })
        width: parent ? parent.width - 8 : 0
        height: 40
        labelW: 230
        label: modelData.label
        value: modelData.pct
        from: 1
        to: 100
        wheelStep: 5
        readout: modelData.pct + "%"
        onMoved: (v) => Hermes.setBrightness(modelData, v)
      }
    }
    // monitors over DDC: ddcutil missing, or there but with no i2c access
    HermesSetup {
      width: parent.width
      topPadding: 6
      bottomPadding: 22
      visible: Hermes.probe.known && !page.canDdc
      glyph: H.G.monitor
      ink: Zenon.yellow
      title: Hermes.probe.display.ddcutil ? "Monitors are not reachable yet" : "Monitor brightness"
      body: Hermes.probe.display.ddcutil
        ? "ddcutil is installed, but the i2c-dev module is not loaded, so monitors cannot be asked. Setting it up loads it now and at every boot."
        : "An external monitor's brightness is set over DDC/CI with ddcutil. Hermes installs it through Ceres and loads the i2c-dev module it needs."
      action: Hermes.probe.display.ddcutil ? "Load i2c-dev" : "Install ddcutil"
      busy: Hermes.setupKind === "ddcutil"
      onGo: Hermes.setup("ddcutil")
    }
    EmptyState {
      width: parent.width
      height: 54
      verticalAlignment: Text.AlignVCenter
      visible: page.canDdc && Hermes.screens.length === 0 && !Hermes.ddcReading
      text: "No screen answered — DDC/CI may be off in the monitor's own menu"
    }
    Item {
      width: parent.width
      height: 40
      visible: page.canDdc && !Hermes.ddcReading
      DialogButton {
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        label: "Ask the monitors again"
        onClicked: Hermes.readDdc()
      }
    }
  }

  HermesCard {
    glyph: H.G.night
    glyphInk: Hermes.nightActive ? Zenon.yellow : Zenon.accentMuted
    title: "Night light"
    note: !Hermes.probe.display.hyprsunset ? "" : Hermes.nightActive ? "On · " + H.kelvinWords(Hermes.kelvin)
      : Hermes.nightSun ? "Waiting for sunset" : "Off"
    trailing: [
      Ctl.Check {
        visible: Hermes.probe.display.hyprsunset
        lit: Hermes.nightWanted
        onToggled: Hermes.toggleNight()
      }
    ]
    HermesSetup {
      width: parent.width
      topPadding: 6
      bottomPadding: 22
      visible: Hermes.probe.known && !Hermes.probe.display.hyprsunset
      glyph: H.G.night
      ink: Zenon.yellow
      title: "Night light needs hyprsunset"
      body: "Hyprland's own screen tint. Hermes installs it through Ceres and runs it while the night light is on."
      action: "Install hyprsunset"
      busy: Hermes.setupKind === "hyprsunset"
      onGo: Hermes.setup("hyprsunset")
    }
    Item {
      width: parent.width
      height: 40
      visible: Hermes.probe.display.hyprsunset
      Ctl.Check {
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        label: "From sunset to sunrise"
        lit: Hermes.nightSun
        onToggled: Hermes.setNightSun(!Hermes.nightSun)
      }
    }
    PrefSlider {
      visible: Hermes.probe.display.hyprsunset
      width: parent ? parent.width - 8 : 0
      height: 40
      labelW: 230
      label: "Warmth"
      value: Hermes.kelvin
      from: H.KELVIN_MIN
      to: H.KELVIN_MAX
      wheelStep: 100
      readout: (Hermes.kelvin / 1000).toFixed(1) + "k"
      neutral: H.KELVIN_DEFAULT
      onMoved: (v) => Hermes.setKelvin(v)
    }
    EmptyState {
      width: parent.width
      height: 30
      visible: Hermes.probe.display.hyprsunset && Hermes.nightSun
      text: "The times are the weather's; with the weather off, 19:00 to 07:00"
    }
  }
}
