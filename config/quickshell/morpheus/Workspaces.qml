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
  // one blink of a flash, in and out: the urgent wash's pairs, the special
  // mark's and the system bell's alike
  readonly property int blinkIn: 60
  readonly property int blinkOut: 120

  readonly property var specialWorkspace: {
    var values = Hyprland.workspaces.values;
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].name).startsWith("special:")) return values[i];
    }
    return null;
  }

  // monitor-agnostic: any special focused on any monitor counts
  property string _activeSpecialName: ""
  // THE SYSTEM BELL (a terminal's BEL; Hyprland 0.57's socket2 `bell>>addr`):
  // howler plays the sound, and the ringing window's workspace blinks once
  // in the accent — never red, red is urgent — when it is not the one you
  // are on. bellSeq counts rings, so the same workspace can blink again.
  property var bellWorkspace: null
  property int bellSeq: 0
  function _ring(data) {
    const norm = (a) => String(a || "").toLowerCase().replace(/^0x/, "");
    const a = norm(data);
    if (a === "") return;
    const tl = Hyprland.toplevels.values.find((t) => norm(t.address) === a);
    if (!tl || !tl.workspace || tl.workspace.focused) return;
    root.bellWorkspace = tl.workspace;
    root.bellSeq++;
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activespecial") {
        const parts = String(event.data).split(",");
        root._activeSpecialName = parts[0] ? parts[0].trim() : "";
      } else if (event.name === "bell") {
        root._ring(event.data);
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
  // SHOWN TOO (user, 2026-10-28: "unfocused flash needs to extend to special
  // workspace as well"): the glyph covers the numbers then, so a numbered
  // workspace asking blinked behind it unseen — the active one under the
  // special as well, since it is not where you are. The area blinks for
  // those, and for a window of the special itself that is not the focused
  // one (Hyprland marks only unfocused windows; focusing it clears it).
  readonly property bool numberUrgent: Hyprland.workspaces.values.some(w =>
    w.urgent === true && !String(w.name).startsWith("special:"))
  readonly property bool specialUrgent: root.specialWorkspace !== null
    && (root.specialWorkspace.urgent === true || (root.specialFocused && root.numberUrgent))
  property real specialFlash: 0
  SequentialAnimation on specialFlash {
    running: root.specialUrgent
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: root.blinkIn; easing.type: Easing.OutQuad }
    NumberAnimation { to: 0; duration: root.blinkOut; easing.type: Easing.InQuad }
    NumberAnimation { to: 1; duration: root.blinkIn; easing.type: Easing.OutQuad }
    NumberAnimation { to: 0; duration: root.blinkOut; easing.type: Easing.InQuad }
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

  // THE SPECIAL WORKSPACE, BY CLICK (2026-10-26). This used to lie OVER the
  // numbers whenever a special workspace existed, so a click on "3" toggled
  // the special one instead of going to 3. Now the numbers come first: a
  // number goes to its workspace (and puts a shown special one away, or 3
  // would stay covered); the number you are on already, a click that did
  // nothing, shows or hides it; and this, under the numbers, takes the
  // module's bare ends. Off while the tray is shown so its clicks are its own.
  function toggleSpecial() {
    var sp = root.specialWorkspace !== null
        ? root.specialWorkspace.name.replace(/^special:/, "")
        : root.specialName;
    // asked for: OffSpecial leaves a show it was told about alone
    Quickshell.execDetached(Off.wanted(Hypr.toggleSpecial(sp)));
  }
  function clickNumber(ws, isActive) {
    if (root.specialWorkspace !== null && (root.specialFocused || isActive)) root.toggleSpecial();
    if (!isActive) Hyprland.dispatch(Hypr.focusWorkspace(ws.name));
  }
  MouseArea {
    anchors.fill: parent
    visible: root.specialWorkspace !== null && !root.showTray
    enabled: visible
    z: -1
    onClicked: root.toggleSpecial()
  }

  // ── workspaces layer ──────────────────────────────────────────────────
  Item {
    id: wsLayer
    anchors.centerIn: parent
    // autofit: from the numbers' width to the glyph's as it comes in
    implicitWidth: wsRow.implicitWidth * (1 - wsLayer.glyphShow)
      + (specialGlyph.implicitWidth + 1 + Zenon.padModule * 2) * wsLayer.glyphShow
    implicitHeight: Zenon.slot
    opacity: 1 - root.cross
    visible: opacity > 0.01

    // THE SPECIAL WORKSPACE SHOWN (user, 2026-10-26): the numbers give way
    // to its glyph, in onAccent on the accent fill (shell.qml), the module
    // fitting it (implicitWidth above). A click anywhere then puts it away:
    // the numbers' own areas stand aside for the bare-ends one (toggleSpecial).
    readonly property bool specialShown: root.specialWorkspace !== null && root.specialFocused
    property real glyphShow: wsLayer.specialShown ? 1 : 0
    Behavior on glyphShow { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
    Text {
      id: specialGlyph
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: -0.5
      text: "\uEAAE"
      color: Zenon.onAccent
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.clockSize
      opacity: wsLayer.glyphShow
      visible: opacity > 0.01
      // bolder as the active number is (wsThick): the glyph font has one
      // weight, so a copy one pixel right widens its strokes
      Text {
        x: 1
        text: specialGlyph.text
        color: specialGlyph.color
        font: specialGlyph.font
      }
      // black on the lit urgent wash, as a flashing number goes (its own
      // copy, not a color change, for the same reason as the number's)
      Text {
        text: specialGlyph.text
        font: specialGlyph.font
        color: Zenon.black
        opacity: root.specialUrgent ? root.specialFlash : 0
        visible: opacity > 0.01
        Text { x: 1; text: parent.text; font: parent.font; color: parent.color }
      }
    }

    Row {
      id: wsRow
      anchors.verticalCenter: parent.verticalCenter
      // centered: as the layer narrows to the glyph, the numbers fade in place
      anchors.horizontalCenter: parent.horizontalCenter
      leftPadding: Zenon.padModule
      rightPadding: Zenon.padModule
      // opacity only: hidden, a Row lays out none of its children and
      // the module would shrink to its padding
      opacity: 1 - wsLayer.glyphShow

      Repeater {
        // BY NUMBER (user, 2026-10-27: "the order is inverted"): Hyprland's
        // list is in the order the workspaces were made, so a 2 opened before
        // a 1 came first. Sorted as the workspace strip sorts them.
        model: Hyprland.workspaces.values.slice().sort((a, b) => a.id - b.id)

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
                NumberAnimation { to: 1; duration: root.blinkIn; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: root.blinkOut; easing.type: Easing.InQuad }
                NumberAnimation { to: 1; duration: root.blinkIn; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: root.blinkOut; easing.type: Easing.InQuad }
                PauseAnimation { duration: 640 }
              }
            }

            // the system bell's one blink (root.bellSeq): the urgent wash's
            // first pair, once, in the accent
            Rectangle {
              id: bellWash
              z: -1
              anchors.centerIn: parent
              width: urgentWash.width
              height: urgentWash.height
              radius: urgentWash.radius
              color: Zenon.cyan
              property real flash: 0
              opacity: btn.isUrgent ? 0 : bellWash.flash
              visible: opacity > 0.01
              SequentialAnimation {
                id: bellBlink
                NumberAnimation { target: bellWash; property: "flash"; to: 1; duration: root.blinkIn; easing.type: Easing.OutQuad }
                NumberAnimation { target: bellWash; property: "flash"; to: 0; duration: root.blinkOut; easing.type: Easing.InQuad }
                NumberAnimation { target: bellWash; property: "flash"; to: 1; duration: root.blinkIn; easing.type: Easing.OutQuad }
                NumberAnimation { target: bellWash; property: "flash"; to: 0; duration: root.blinkOut; easing.type: Easing.InQuad }
              }
              Connections {
                target: root
                function onBellSeqChanged() {
                  if (root.bellWorkspace === btn.modelData && !btn.isActive) bellBlink.restart();
                }
              }
            }

            BarText {
              id: wsGhost
              anchors.centerIn: parent
              text: "8"
              numeric: true
              // the unlit segments match the lit ones' thickness
              font.weight: wsLabel.font.weight
              // on the special workspace's accent fill: a trace of its ink
              color: root.specialWorkspace !== null && root.specialFocused
                ? Zenon.alpha(Zenon.onAccent, 0.12) : Zenon.trough(Zenon.cyan)
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
                  // inverted on the special workspace's accent fill
                  // (shell.qml specialTakeover; user, 2026-10-26): red was
                  // the fill, and red is the urgent flash's alone
                  return btn.isActive ? Zenon.onAccent : Zenon.alpha(Zenon.onAccent, 0.6)
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
              textFormat: Text.PlainText
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
              textFormat: Text.PlainText
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
            enabled: !root.showTray && !wsLayer.specialShown
            onClicked: root.clickNumber(modelData, btn.isActive)
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
            // the clock's ink (ClockModule: Zenon.cyan), as the bell's when caught up;
            // onAccent over the special workspace's accent fill (shell.qml)
            property color ink: root.specialWorkspace !== null && root.specialFocused ? Zenon.onAccent : Zenon.cyan
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
