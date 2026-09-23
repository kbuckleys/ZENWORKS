// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CERES' PANEL — what is waiting, and the one button that installs it.
//
// It opens out of the bar's update count the way the bell's panel opens out
// of the bell, and it is a view of Ceres and nothing else: the list, the
// transaction, its progress and its result all live in the singleton. So
// closing this mid-upgrade hides the upgrade rather than stopping it, and
// opening it again shows the run exactly where it has got to.
//
// FOUR FACES, one at a time, chosen by `face` below:
//   list      what is pending, with Update all
//   auth      the password, in calypso's field — same glyph, same dots,
//             same shake, because a password prompt is a password prompt
//   progress  what paru is doing, how far through, and its log
//   result    what happened, or why it did not

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "../morpheus"
import "."
import "../oracle"
import "ceres.js" as Cer

LayerPopup {
  id: popup

  focusable: true

  // ── which face ──────────────────────────────────────────────────────────
  // Asking for the password is this panel's state; everything after it is
  // Ceres'. A refused password comes back as Ceres' "authfail", which is the
  // auth face again with the field shaken and the message changed.
  property bool asking: false
  readonly property string face: {
    const s = Ceres.txState;
    if (s === "auth" || s === "running") return "progress";
    if (s === "done" || s === "failed") return "result";
    if (Ceres.newsGate) return "news";
    if (s === "authfail" || popup.asking) return "auth";
    return "list";
  }

  // The window answers a request for a password when it is the one on
  // screen; the panel answers when it is, or when nothing is.
  property bool answersAuth: true

  readonly property int rowH: 32
  readonly property int headH: 44
  readonly property int footH: 48
  readonly property int noteH: 22

  // Headings and packages in one model, so the list scrolls as one thing.
  readonly property var rows: {
    const out = [];
    if (Ceres.repo.length) {
      out.push({ head: true, label: "Official", n: Ceres.repo.length, aur: false });
      for (const u of Ceres.repo) out.push({ head: false, u: u, aur: false });
    }
    if (Ceres.aur.length) {
      out.push({ head: true, label: "AUR", n: Ceres.aur.length, aur: true });
      for (const u of Ceres.aur) out.push({ head: false, u: u, aur: true });
    }
    return out;
  }

  function bodyH() {
    if (popup.face === "list")
      return popup.rows.length === 0 ? 96
        : Math.min(Oracle.notifMaxHeight, popup.rows.length * popup.rowH + 16);
    if (popup.face === "auth") return field.implicitHeight + (field.purpose !== "" ? 12 : 0);
    if (popup.face === "progress") return 260;
    if (popup.face === "news") return Math.min(Oracle.notifMaxHeight, 110 + Ceres.unreadNews.length * 150);
    return Math.min(Oracle.notifMaxHeight, 72 + tx.resultRows * 24);
  }

  // shell.qml asks for this by name to size the morph.
  function calcHeight() {
    return popup.headH + Ceres.notes.length * popup.noteH
      + (Ceres.notes.length ? 8 : 0) + popup.bodyH() + popup.footH;
  }
  readonly property int panelWidth: 720

  // ── opening ─────────────────────────────────────────────────────────────

  HyprlandFocusGrab {
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    popup.playOpen();
    keys.forceActiveFocus();
  }

  function closePopup() {
    // The password does not outlive the panel it was typed into, and neither
    // does a request nobody confirmed: an unanswered rehearsal left armed
    // would be what a later Update all ran instead.
    field.pw = "";
    if (!Ceres.txBusy) Ceres.forgetNext();
    popup.asking = false;
    // A result that has been seen is done with; a run in progress is not.
    if (Ceres.txState === "done" || Ceres.txState === "authfail") Ceres.txClear();
    popup.collapsing = true;
    popup.playClose();
  }

  function toggle() {
    if (popup.shown && !popup.collapsing) popup.closePopup();
    else popup.openPopup();
  }

  Connections {
    target: Ceres
    function onOpenRequested() { if (!popup.shown || popup.collapsing) popup.openPopup(); }
    function onToggleRequested() { popup.toggle(); }
    // Something asked for needs paru, and there is none: setup lives in
    // the window, so the panel hands over to it.
    function onSetupRequested() {
      if (popup.shown && !popup.collapsing) popup.closePopup();
      Ceres.openWindow("updates");
    }
    function onAuthRequested() {
      if (!popup.answersAuth) return;
      if (!popup.shown || popup.collapsing) popup.openPopup();
      Ceres.txClear();
      field.pw = "";
      field.failed = false;
      popup.asking = true;
    }
    // an upgrade held for the news: the panel shows it, if it is the one
    // answering
    function onNewsGateChanged() {
      if (Ceres.newsGate && popup.answersAuth && (!popup.shown || popup.collapsing)) popup.openPopup();
    }
    // sudo said no: the field comes back, shaken
    function onTxStateChanged() { if (Ceres.txState === "authfail") field.failed = true; }
  }

  // ── what the keys do ────────────────────────────────────────────────────
  function startAuth() {
    if (Ceres.total === 0 || Ceres.txBusy) return;
    Ceres.request(Cer.upgradeSteps(), "", -1);
  }

  function back() {
    if (popup.face === "auth") {
      popup.asking = false; Ceres.txClear(); field.pw = ""; field.failed = false;
      Ceres.forgetNext();
      return;
    }
    if (popup.face === "result") { Ceres.txClear(); return; }
    popup.closePopup();
  }

  Item {
    id: keys
    focus: true
    Keys.onReleased: (event) => {
      if (popup.face === "auth") event.accepted = field.keyUp(event);
    }
    Keys.onPressed: (event) => {
      const k = event.key;
      if (popup.face === "auth") {
        event.accepted = field.key(event);
        return;
      }
      if (popup.face === "news") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) Ceres.passNews();
        else if (k === Qt.Key_Escape) Ceres.holdBack();
        return;
      }
      if (k === Qt.Key_Escape) { event.accepted = true; popup.back(); return; }
      if (popup.face === "list") {
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { event.accepted = true; popup.startAuth(); }
        else if (k === Qt.Key_R) { event.accepted = true; Ceres.check(); }
        else if (k === Qt.Key_O) { event.accepted = true; popup.closePopup(); Ceres.openWindow("updates"); }
        else if (k === Qt.Key_J || k === Qt.Key_Down) { event.accepted = true; list.flick(0, -800); }
        else if (k === Qt.Key_K || k === Qt.Key_Up) { event.accepted = true; list.flick(0, 800); }
        return;
      }
      if (popup.face === "result") {
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { event.accepted = true; Ceres.txClear(); }
        else if (k === Qt.Key_T && Ceres.txState === "failed") { event.accepted = true; Ceres.txInTerminal(); popup.closePopup(); }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  // ── pieces ──────────────────────────────────────────────────────────────


  component Rule: Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: 1
    color: Zenon.border
  }

  // ── the card ────────────────────────────────────────────────────────────
  Item {
    id: panel
    width: Zenon.layerWidth(popup.panelWidth)
    height: popup.calcHeight()
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    anchors {
      horizontalCenter: parent.horizontalCenter
      top: Zenon.barTop ? parent.top : undefined
      bottom: Zenon.barTop ? undefined : parent.bottom
      topMargin: Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      bottomMargin: Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    }
    z: 1
    opacity: popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    MouseArea { anchors.fill: parent }

    LayerShadow {
      panel: bgRoot
      cornerRadius: Zenon.pillRadius
      morphed: popup.morphMode
    }

    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      color: popup.morphMode ? "transparent" : Zenon.layerBg
      border.color: Zenon.border
      border.width: 1
      radius: Zenon.pillRadius

      // ── the head ────────────────────────────────────────────────────
      Item {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: popup.headH

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          text: popup.face === "progress" ? "Updating"
            : popup.face === "result" ? (Ceres.txState === "done" ? "Updated" : "Update failed")
            : Ceres.total === 0 ? "Up to date"
            : "Updates  " + Ceres.total
          color: popup.face === "result" && Ceres.txState === "failed" ? Zenon.red : Zenon.blue
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 16
        }

        // How fresh the list is, and the way to make it fresher.
        Row {
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10
          visible: popup.face === "list"

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Ceres.checking ? "checking…"
              : Ceres.lastOk > 0 ? "checked " + Cer.age(Ceres.now - Ceres.lastOk) : ""
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 12
          }

          Text {
            id: refresh
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: refreshHov.hovered ? Zenon.white : Zenon.keyInk
            font.family: Zenon.face
            font.pixelSize: 14
            RotationAnimation on rotation {
              running: Ceres.checking
              loops: Animation.Infinite
              from: 0; to: 360; duration: 900
              onRunningChanged: if (!running) refresh.rotation = 0
            }
            HoverHandler { id: refreshHov }
            TapHandler { onTapped: Ceres.check() }
          }
        }

        Rule { anchors.bottom: parent.bottom }
      }

      // ── what is wrong with the answer ───────────────────────────────
      Column {
        id: notes
        anchors.top: head.bottom
        anchors.topMargin: Ceres.notes.length ? 6 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        Repeater {
          model: Ceres.notes
          delegate: Text {
            required property string modelData
            width: notes.width
            height: popup.noteH
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: modelData
            color: Zenon.red
            font.family: Zenon.face
            font.pixelSize: 13
          }
        }
      }

      Item {
        id: body
        anchors.top: notes.bottom
        anchors.topMargin: Ceres.notes.length ? 2 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: foot.top

        // ── list ────────────────────────────────────────────────────
        Text {
          anchors.centerIn: parent
          visible: popup.face === "list" && popup.rows.length === 0
          text: Ceres.lastOk > 0 ? "nothing to update" : "not checked yet"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 15
        }

        ListView {
          id: list
          // terminus' scrollbar — see morpheus/ScrollRail. Parented to the view
          // itself, so in a Flickable it stays put instead of scrolling away.
          ScrollRail {
            target: list
            parent: list
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
          }
          ElasticScroll { view: list }
          anchors.fill: parent
          anchors.topMargin: 8
          anchors.bottomMargin: 8
          anchors.leftMargin: 16
          anchors.rightMargin: 16
          visible: popup.face === "list"
          clip: true
          model: popup.rows
          boundsBehavior: Flickable.StopAtBounds
          delegate: Item {
            required property var modelData
            width: list.width - 14
            height: popup.rowH

            Text {
              visible: modelData.head
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: (modelData.aur ? "" : "") + "  " + modelData.label
                + "  " + modelData.n
              color: modelData.aur ? Ceres.ink.aur : Ceres.ink.repo
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: 13
            }

            ChangeRow {
              visible: !modelData.head
              anchors.left: parent.left
              anchors.leftMargin: 22
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              u: modelData.head ? null : modelData.u
            }
          }
        }

        // ── auth ────────────────────────────────────────────────────
        PasswordField {
          id: field
          visible: popup.face === "auth"
          anchors.fill: parent
          purpose: Ceres.nextLabel
          onSubmitted: (p) => { popup.asking = false; Ceres.upgradeAll(p); }
          onCancelled: popup.back()
        }

        // ── the news, before an upgrade ─────────────────────────────
        NewsView {
          visible: popup.face === "news"
          anchors.fill: parent
          anchors.margins: 16
        }

        // ── progress and result ─────────────────────────────────────
        TxView {
          id: tx
          visible: popup.face === "progress" || popup.face === "result"
          anchors.fill: parent
          anchors.margins: 16
        }
      }

      // ── the foot ────────────────────────────────────────────────────
      Item {
        id: foot
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: popup.footH

        Rectangle { anchors.fill: parent; color: Zenon.hintBg }
        Rule { anchors.top: parent.top }

        HintRow {
          // at the left: this strip always carries at least one button on the
          // right, so centring only ever pushed the keys into it
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          rows: {
            switch (popup.face) {
            case "list":
              return (Ceres.total > 0 ? [["return", "update all"]] : [])
                .concat([["r", "check"], ["o", "manage packages"]]);
            case "auth": return [["return", "confirm"], ["esc", "back"]];
            case "progress": return [["esc", "hide — it keeps going"]];
            case "news": return [["return", "continue"], ["esc", "back"]];
            }
            return Ceres.txState === "failed"
              ? [["t", "open in terminal"], ["return", "back"]]
              : [["return", "back"]];
          }
        }

        Row {
          id: panelBtns
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8

          DialogButton {
            visible: popup.face === "news"
            label: "Back"
            ink: Zenon.muted
            onClicked: Ceres.holdBack()
          }
          DialogButton {
            visible: popup.face === "news"
            label: "Continue"
            ink: Zenon.cyan
            primary: true
            onClicked: Ceres.passNews()
          }
          DialogButton {
            visible: popup.face === "result" && Ceres.txState === "failed"
            label: "Open in terminal"
            ink: Zenon.yellow
            onClicked: { Ceres.txInTerminal(); popup.closePopup(); }
          }
          DialogButton {
            visible: popup.face === "list"
            label: "Manage packages"
            ink: Zenon.muted
            onClicked: { popup.closePopup(); Ceres.openWindow("updates"); }
          }
          DialogButton {
            visible: popup.face === "list" && Ceres.total > 0
            label: "Update all"
            ink: Zenon.cyan
            primary: true
            onClicked: popup.startAuth()
          }
          DialogButton {
            visible: popup.face === "result"
            label: "Back"
            ink: Zenon.muted
            onClicked: Ceres.txClear()
          }
        }
      }
    }
  }
}
