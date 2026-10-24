// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import "../oracle"
import "."
// qualified, for HeldRing alone
import "../terminus" as Term
import "offspecial.js" as Off
import "hypr.js" as Hypr

Item {
  id: root
  // autofit: interpolate between workspace width and tray width driven by cross;
  // no Behavior here — width follows wsLayer (which animates via Collapsible) or
  // cross (which animates via its own Behavior) directly, so the special wash
  // at bg level (bound to workspacesMod.width) stays in lock-step with the
  // collapsing workspace instead of chasing it with a second easing.
  implicitWidth: root.hasTray ? (wsLayer.implicitWidth * (1 - root.cross) + trayLayer.implicitWidth * root.cross) : wsLayer.implicitWidth
  implicitHeight: Zenon.slot
  clip: true

  property string specialName: "special"
  // A window asking for attention lights its workspace in this ink until you
  // go there. Handed in by shell.qml — howler's critical color, the one ink
  // the shell already uses for "look at this".
  property color urgentInk: Zenon.red

  readonly property var specialWorkspace: {
    var values = Hyprland.workspaces.values;
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].name).startsWith("special:")) return values[i];
    }
    return null;
  }

  // monitor-agnostic: any special focused on any monitor counts
  property string _activeSpecialName: ""
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activespecial") {
        const parts = String(event.data).split(",");
        root._activeSpecialName = parts[0] ? parts[0].trim() : "";
      }
    }
  }
  readonly property bool specialFocused: {
    if (root.specialWorkspace === null) return false;
    if (root._activeSpecialName !== "") return true;
    try {
      const fw = Hyprland.focusedWorkspace;
      if (fw && String(fw.name).startsWith("special:")) return true;
    } catch (e) {}
    const sw = root.specialWorkspace;
    return sw.focused === true;
  }

  // A window in the special workspace asking for attention. It has no number
  // to light, so the whole workspace area blinks instead — shell.qml paints
  // it at bg level, over the special wash (specialUrgentWash), off this
  // value. Same two flashes and rest as a numbered workspace's urgentWash.
  readonly property bool specialUrgent: root.specialWorkspace !== null
    && root.specialWorkspace.urgent === true && !root.specialFocused
  property real specialFlash: 0
  SequentialAnimation on specialFlash {
    running: root.specialUrgent
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 60; easing.type: Easing.OutQuad }
    NumberAnimation { to: 0; duration: 120; easing.type: Easing.InQuad }
    NumberAnimation { to: 1; duration: 60; easing.type: Easing.OutQuad }
    NumberAnimation { to: 0; duration: 120; easing.type: Easing.InQuad }
    PauseAnimation { duration: 640 }
  }
  onSpecialUrgentChanged: if (!root.specialUrgent) root.specialFlash = 0

  // ── tray ────────────────────────────────────────────────────────────────
  readonly property var trayItems: {
    const vals = SystemTray.items.values;
    const out = [];
    for (let i = 0; i < vals.length; ++i) {
      const it = vals[i];
      if (it && it.status !== Status.Passive && it.icon !== "") out.push(it);
    }
    return out;
  }
  // Switched off in oracle the row simply never has a tray to reveal, which is
  // a state it already knows how to be in — the crossfade below is the one it
  // runs whenever the last tray application quits.
  property bool hasTray: Oracle.showTray && trayItems.length > 0
  property bool hovered: false
  property bool menuOpen: false

  // 500ms grace between transitions — keeps tray visible for half a second
  // after hover/menu leave to avoid flicker when crossing the gap or briefly
  // leaving the module. Immediate on enter, delayed on leave.
  property bool _latchedShow: false
  readonly property bool _intendShow: root.hovered || root.menuOpen
  Timer {
    id: graceTimer
    interval: 500
    onTriggered: {
      if (!root._intendShow) root._latchedShow = false
    }
  }
  on_IntendShowChanged: {
    if (root._intendShow) {
      graceTimer.stop()
      root._latchedShow = true
    } else {
      graceTimer.restart()
    }
  }
  onHasTrayChanged: {
    if (!root.hasTray) {
      graceTimer.stop()
      root._latchedShow = false
      root.hovered = false
      root.menuOpen = false
    }
  }

  readonly property bool showTray: root.hasTray && root._latchedShow
  // 0 = workspaces, 1 = tray — single scalar drives both opacity and width
  property real cross: root.showTray ? 1 : 0
  Behavior on cross { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

  // hover detection without stealing clicks from workspace/tray delegates
  HoverHandler {
    id: hoverHandler
    onHoveredChanged: root.hovered = hovered
  }

  // special toggle — disabled while tray is shown so tray clicks aren't hijacked
  MouseArea {
    anchors.fill: parent
    visible: root.specialWorkspace !== null && !root.showTray
    enabled: visible
    z: 2
    onClicked: {
      var sp = root.specialWorkspace !== null
          ? root.specialWorkspace.name.replace(/^special:/, "")
          : root.specialName;
      // asked for: OffSpecial leaves a show it was told about alone
      Quickshell.execDetached(Off.wanted(Hypr.toggleSpecial(sp)));
    }
  }

  // ── workspaces layer ──────────────────────────────────────────────────
  Item {
    id: wsLayer
    anchors.centerIn: parent
    implicitWidth: wsRow.implicitWidth
    implicitHeight: Zenon.slot
    opacity: 1 - root.cross
    visible: opacity > 0.01

    Row {
      id: wsRow
      anchors.verticalCenter: parent.verticalCenter
      leftPadding: Zenon.padModule
      rightPadding: Zenon.padModule

      Repeater {
        model: Hyprland.workspaces

        delegate: Collapsible {
          id: btn
          required property var modelData

          property bool isActive: modelData.focused
          // hyprland clears it the moment the workspace is visited
          readonly property bool isUrgent: modelData.urgent === true && !btn.isActive

          // workspaces appear and vanish as they are used; ease the gap shut
          active: !String(modelData.name).startsWith("special:")
          openWidth: wsBox.implicitWidth + Zenon.padModule * 2

          Item {
            id: wsBox
            anchors.centerIn: parent
            implicitWidth: Math.max(wsGhost.implicitWidth, wsLabel.implicitWidth)
            implicitHeight: Zenon.slot

            // Two quick flashes of the number's background, then a rest,
            // the pair every second: a blink you catch from the corner of
            // the eye, not a glow you have to read.
            Rectangle {
              id: urgentWash
              z: -1
              anchors.centerIn: parent
              width: wsBox.implicitWidth + 12
              height: Math.min(Zenon.slot - 8, width + 6)
              radius: Zenon.windowRadius
              color: root.urgentInk
              property real flash: 0
              opacity: btn.isUrgent ? urgentWash.flash : 0
              visible: opacity > 0.01
              SequentialAnimation on flash {
                running: btn.isUrgent
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: 120; easing.type: Easing.InQuad }
                NumberAnimation { to: 1; duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: 120; easing.type: Easing.InQuad }
                PauseAnimation { duration: 640 }
              }
            }

            BarText {
              id: wsGhost
              anchors.centerIn: parent
              text: "8"
              numeric: true
              // the unlit segments match the lit ones' thickness
              font.weight: wsLabel.font.weight
              color: Zenon.trough(Zenon.cyan)
            }

            BarText {
              id: wsLabel
              anchors.centerIn: parent
              text: {
                return ["1", "2", "3", "4", "5"].includes(String(modelData.id)) ? String(modelData.id) : " ";
              }
              numeric: true
              // the black copy below stands in for it while the wash is lit
              opacity: btn.isUrgent ? 1 - urgentWash.flash : 1
              color: {
                if (btn.isUrgent) return root.urgentInk
                if (root.specialWorkspace !== null && root.specialFocused)
                  // a meter's faint notch is too faint for a number — on
                  // paper or on the dark wash (user, 2026-10-24): inactive
                  // takes the same halfway step toward the lit ink as the
                  // cyan numbers do below
                  return btn.isActive ? Zenon.pink
                    : Zenon.light ? Zenon.alpha(Zenon.pink, 0.75) : Zenon.mix(Zenon.dimInk, Zenon.pink, 0.5)
                // Inactive in a dark theme: halfway from dim to the lit
                // cyan. Plain dim sat barely above the unlit "8" behind it
                // (wsGhost, trough cyan) and the numbers all but vanished
                // (user, dark-workspace.png, 2026-10-08); this stands well
                // clear of the ghost and still well under the active one.
                // Light keeps dimInk (muted), its own earlier fix.
                return btn.isActive ? Zenon.cyan
                  : Zenon.light ? Zenon.dimInk : Zenon.mix(Zenon.dimInk, Zenon.cyan, 0.5)
              }
              // DSEG7 Classic ships Light, Regular and Bold only — ExtraBold
              // and Black fell back to the same Bold file, so active and
              // inactive drew identically. Regular against Bold is a single
              // pixel at bar size, Light read too thin and a 1px outline far
              // too heavy (user, 2026-10-22), so the active number is Bold
              // with a copy one pixel right (wsThick) widening its uprights.
              font.weight: btn.isActive ? Font.Bold : Font.Normal
            }
            // the active number's second pass; urgent is never active, so it
            // never needs the black copy's treatment
            Text {
              id: wsThick
              anchors.fill: wsLabel
              anchors.leftMargin: 1
              anchors.rightMargin: -1
              visible: btn.isActive
              text: wsLabel.text
              font: wsLabel.font
              verticalAlignment: wsLabel.verticalAlignment
              horizontalAlignment: wsLabel.horizontalAlignment
              renderType: wsLabel.renderType
              color: wsLabel.color
            }
            // Black on the lit wash. A plain Text over the label, not a color
            // change on it: BarText eases every color over Zenon.normal, which
            // is longer than a flash, so the number never got to black.
            Text {
              anchors.fill: wsLabel
              text: wsLabel.text
              font: wsLabel.font
              verticalAlignment: wsLabel.verticalAlignment
              horizontalAlignment: wsLabel.horizontalAlignment
              renderType: wsLabel.renderType
              color: Zenon.black
              opacity: btn.isUrgent ? urgentWash.flash : 0
              visible: opacity > 0.01
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: !root.showTray
            onClicked: {
              Hyprland.dispatch(Hypr.focusWorkspace(modelData.name));
            }
          }
        }
      }
    }
  }

  // ── tray layer ────────────────────────────────────────────────────────
  Item {
    id: trayLayer
    anchors.centerIn: parent
    implicitWidth: trayRow.implicitWidth
    implicitHeight: Zenon.slot
    opacity: root.cross
    visible: opacity > 0.01

    Row {
      id: trayRow
      anchors.verticalCenter: parent.verticalCenter
      leftPadding: Zenon.padModule
      rightPadding: Zenon.padModule
      spacing: 10

      Repeater {
        model: root.trayItems

        delegate: Item {
          id: trayItem
          required property var modelData

          // match the bar's own glyphs — BarText is Zenon.textSize, so tray
          // icons sit on the same visual line as the workspaces they replace
          width: Zenon.textSize
          height: Zenon.textSize
          anchors.verticalCenter: parent.verticalCenter

          // the icon whose menu is open, outlined (terminus/HeldRing.qml),
          // as everything a right click asks about is across the suite
          Term.HeldRing {
            anchors.fill: parent
            anchors.margins: -4
            on: trayMenu.open
          }

          Image {
            id: trayIcon
            anchors.fill: parent
            // Hidden on error rather than emptied: assigning `source` here
            // replaced the binding, so an icon that failed once — a theme
            // not loaded yet, an app mid-restart — never came back when the
            // app published a good one.
            source: modelData.icon
            // drawn through the effect below, never as it comes
            visible: false
            fillMode: Image.PreserveAspectFit
            sourceSize.width: Zenon.textSize
            sourceSize.height: Zenon.textSize
            smooth: true
            mipmap: true
          }
          // ONE INK FOR THE WHOLE TRAY (user, 2026-10-19: "color-neutral and
          // theme-adherent"), the DETAIL KEPT: the clock's ink at the
          // opacity of each pixel's brightness (shaders/inktint.frag). Not a
          // stencil — steam's lines filled in — nor MultiEffect's
          // colorization, which keeps lightness and swaps only hue, so the
          // white and gray icons every tray is full of came out unchanged.
          ShaderEffect {
            anchors.fill: parent
            visible: trayIcon.status === Image.Ready
            property var source: trayIcon
            // the clock's ink (ClockModule: Zenon.cyan), as the bell's when caught up
            property color ink: Zenon.cyan
            property real floorAlpha: 0.25
            fragmentShader: Qt.resolvedUrl("shaders/inktint.frag.qsb")
          }

          TrayMenu {
            id: trayMenu
            menuHandle: modelData.menu
            anchorItem: trayItem
            onMenuClosed: root.menuOpen = false
          }

          // trayItems is rebuilt whenever any item's status or icon changes,
          // and the Repeater remakes every delegate with it — an open menu is
          // destroyed without ever going invisible, so menuClosed never fires
          // and menuOpen pins the tray open for good.
          Component.onDestruction: if (trayMenu.visible) root.menuOpen = false

          MouseArea {
            id: iconMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            onClicked: (mouse) => {
              if (mouse.button === Qt.LeftButton) modelData.activate()
              else if (modelData.hasMenu) {
                root.menuOpen = true
                trayMenu.show()
              }
              else modelData.secondaryActivate()
            }
          }

          Tooltip {
            anchorItem: trayItem
            cursorArea: iconMouse
            text: (modelData.tooltipTitle || modelData.title || "")
                + (modelData.tooltipDescription ? "\n" + modelData.tooltipDescription : "")
            show: iconMouse.containsMouse && text !== ""
          }
        }
      }
    }
  }
}
