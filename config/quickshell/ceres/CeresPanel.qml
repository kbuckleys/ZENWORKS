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
import Quickshell.Widgets
import Quickshell.Hyprland
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
  readonly property int footH: Zenon.hintBarH   // morpheus/HintBar's strip

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
    if (Ceres.flat.length) {
      out.push({ head: true, label: "Flatpak", n: Ceres.flat.length, aur: false, flatpak: true });
      for (const u of Ceres.flat) out.push({ head: false, u: u, aur: false, flatpak: true });
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
    // the log stays under the result (TxView) — room for it, or it was a
    // collapsed frame under one line (user, 2026-10-17)
    return Math.min(Oracle.notifMaxHeight, 72 + tx.resultRows * 24 + (tx.failed ? 0 : 150));
  }

  // shell.qml asks for this by name to size the morph.
  function calcHeight() {
    // the notes take what their bar takes, a button and all
    return popup.headH + notes.height + popup.bodyH() + popup.footH;
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

  // ── CARRIED ON IN THE WINDOW (user, 2026-10-18) ──────────────────────
  // The head's last button: the same moment, in the full window — a job's
  // log, the news, the password card. Put away WITHOUT closePopup's
  // forgetting: the request is still wanted, only asked for elsewhere. A
  // password card is asked again once the window is up (it answers then —
  // see answersAuth in shell.qml); the typed half of one is not carried.
  function continueInWindow() {
    const asked = popup.asking || Ceres.txState === "authfail";
    Ceres.openWindow("updates");
    field.pw = "";
    field.failed = false;
    popup.asking = false;
    popup.collapsing = true;
    popup.playClose();
    if (asked) Qt.callLater(() => { if (Ceres.windowShown) Ceres.authRequested(); });
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
    Ceres.updateAll();
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
      // shift+esc stops the job; plain esc still only hides the panel
      if (k === Qt.Key_Escape && (event.modifiers & Qt.ShiftModifier) && Ceres.txBusy) {
        event.accepted = true;
        Ceres.cancel();
        return;
      }
      if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_C
          && (popup.face === "progress" || popup.face === "result") && tx.copy()) {
        event.accepted = true;
        return;
      }
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
        else if (k === Qt.Key_Y && tx.settleable) { event.accepted = true; tx.settle(); }
        else if ((k === Qt.Key_Left || k === Qt.Key_Right) && tx.settling) {
          event.accepted = true;
          tx.pickNext(k === Qt.Key_Left ? -1 : 1);
        }
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
  LayerPanel {
    id: panel
    host: popup
    ground: bgRoot
    width: Zenon.layerWidth(popup.panelWidth)
    height: popup.calcHeight()

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
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          // named for what the steps are (2026-10-14: another app's install
          // failed under "Update failed")
          readonly property var words: Ceres.txKind === "install" ? ["Installing", "Installed", "Install failed"]
            : Ceres.txKind === "remove" ? ["Removing", "Removed", "Removal failed"]
            : Ceres.txKind === "other" ? ["Working", "Done", "Failed"]
            : ["Updating", "Updated", "Update failed"]
          text: popup.face === "progress" ? words[0]
            : popup.face === "result" ? (Ceres.txState === "done" ? words[1] : words[2])
            : Ceres.total === 0 ? "Up to date"
            : "Updates  " + Ceres.total
          color: popup.face === "result" && Ceres.txState === "failed" ? Zenon.red : Zenon.cyan
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(16)
        }

        // How fresh the list is, and the way to make it fresher.
        Row {
          anchors.right: toWindow.left
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10
          visible: popup.face === "list"

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Ceres.checking ? "Checking…"
              : Ceres.lastOk > 0 ? "checked " + Cer.age(Ceres.now - Ceres.lastOk) : ""
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }

          Text {
            id: refresh
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: refreshPress.pressed ? Zenon.white : Zenon.accentKey
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
            RotationAnimation on rotation {
              running: Ceres.checking
              loops: Animation.Infinite
              from: 0; to: 360; duration: Zenon.spin
              onRunningChanged: if (!running) refresh.rotation = 0
            }
            HoverHandler { id: refreshHov }
            TapHandler { id: refreshPress; onTapped: Ceres.check() }
          }
        }

        // on in the full window, whatever the panel is showing
        Text {
          id: toWindow
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          text: "\u{F03CC}"
          color: toWindowPress.pressed ? Zenon.white : Zenon.accentKey
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(15)
          HoverHandler { id: toWindowHov }
          TapHandler { id: toWindowPress; onTapped: popup.continueInWindow() }
        }

        Rule { anchors.bottom: parent.bottom }
      }

      // ── what is wrong with the answer ───────────────────────────────
      // the window's bar, in the panel's sizes (user, 2026-10-15: plain red
      // lines here, and no way to answer them) — ceres/NoteBar
      Item {
        id: notes
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Ceres.noteItems.length ? noteBar.height + 14 : 0
        NoteBar {
          id: noteBar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          anchors.topMargin: 8
          textSize: Zenon.px(14)
          glyphSize: Zenon.px(13)
          rowH: 22
        }
      }

      Item {
        id: body
        anchors.top: notes.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: foot.top

        // ── list ────────────────────────────────────────────────────
        Text {
          anchors.centerIn: parent
          visible: popup.face === "list" && popup.rows.length === 0
          text: Ceres.lastOk > 0 ? "Nothing to update" : "Not checked yet"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(15)
        }

        ListView {
          id: list
          // terminus' scrollbar — see morpheus/ScrollRail. Parented out of the view
          // (to the body), so it stays put instead of scrolling away.
          ScrollRail {
            target: list
            // Against the card's edge, not the list's 16 in from it.
            parent: body
            // Parented out, it no longer hid with the list: during a job the
            // list's thumb stood beside the log's, scrolling nothing (user,
            // 2026-10-18)
            on: list.visible
            anchors.right: parent.right
            anchors.top: list.top
            anchors.bottom: list.bottom
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
              textFormat: Text.PlainText
              visible: modelData.head
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: (modelData.flatpak ? "\uF324" : modelData.aur ? "" : "") + "  " + modelData.label
                + "  " + modelData.n
              color: modelData.flatpak ? Ceres.ink.flat : modelData.aur ? Ceres.ink.aur : Ceres.ink.repo
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(13)
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
          authSource: Ceres
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

      // the updates still below rise out of the foot, frosted — see
      // morpheus/ScrollEdge; follow runs it from the list's bottom edge
      // down through the foot, which is declared after and draws over it
      ScrollEdge {
        view: list
        below: true
        follow: true
        bar: foot
      }

      // ── the foot ────────────────────────────────────────────────────
      // morpheus/HintBar, as every strip (ceres' height, ground and rule);
      // the buttons stand at its right end
      HintBar {
        id: foot
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        rows: {
          switch (popup.face) {
          case "list":
            return (Ceres.total > 0 ? [["return", "update all"]] : [])
              .concat([["r", "check"], ["o", "manage packages"]]);
          case "auth": return [["return", "confirm"], ["esc", "back"]];
          case "progress": return [["esc", "hide — it keeps going"], ["shift esc", "cancel"]];
          case "news": return [["return", "continue"], ["esc", "back"]];
          }
          if (tx.settleable) return [["y", "resolve"], ["t", "open in terminal"], ["return", "back"]];
          return Ceres.txState === "failed"
            ? [["t", "open in terminal"], ["return", "back"]]
            : [["return", "back"]];
        }

        DialogButton {
          visible: popup.face === "news"
          label: "Back"
          ink: Zenon.accentMuted
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
          visible: popup.face === "result" && tx.settleable
          label: tx.settling && tx.settleInfo.conflicts.length ? "Replace and install" : "Install"
          ink: Zenon.cyan
          primary: true
          onClicked: tx.settle()
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
          ink: Zenon.accentMuted
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
          ink: Zenon.accentMuted
          onClicked: Ceres.txClear()
        }
      }
    }
  }
}
