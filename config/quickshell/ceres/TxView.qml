// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A TRANSACTION, WATCHED — its progress while it runs and what it did once it
// has. One view for the panel and the window, reading Ceres and nothing
// else, so the same run looks the same wherever you look at it from.
//
//   running   what paru is doing, on a band filled by pacman.log's own record
//             of each package; what is moving right now — a download's size,
//             speed and time left, read off pacman's own bar; and the log
//   done      counts by verb, the disk moved, and every package changed
//   failed    paru's own last error, and the whole log that led to it —
//             and, when paru stopped on a question it could not ask (a
//             provider to pick, a package to replace), that question, here,
//             answered by settle()
//
// THE LOG IS TEXT, NOT ROWS. It was a list of elided lines, which could not
// be selected, cut off everything past the width of the pane, and jumped back
// to the bottom on every new line whether you had scrolled up to read or not.
// It is one read-only text now: select with the mouse and ctrl+c (or Copy)
// takes it, long lines wrap, and it follows the end only while you are AT the
// end — scroll up and it stays where you put it.

import QtQuick
import Quickshell
import "../morpheus"
import "."
import "ceres.js" as Cer

Item {
  id: view
  // Text size over the panel's: the window reads 2px larger.
  property int grow: 0

  readonly property bool running: Ceres.txBusy
  readonly property bool failed: Ceres.txState === "failed"
  readonly property bool cancelled: view.failed && Ceres.txError === "Cancelled"
  readonly property var tally: Cer.tally(Ceres.txEvents)

  // What a holder of this view needs to size itself for the result.
  readonly property int resultRows: view.failed ? 12 : Ceres.txEvents.length

  // ── WHAT PARU COULD NOT ASK ──────────────────────────────────────────
  // Ceres.txSettle, when the failure was a question: the picks made so far
  // ({ menu: option }, each menu's first by default — paru's own default),
  // and settle() to run it again answered. pickNext steps the first menu,
  // for the holder's ← →.
  readonly property var settleInfo: view.failed ? Ceres.txSettle : null
  readonly property bool settling: !!view.settleInfo
  // only conflicts between installed and incoming packages can be agreed to;
  // two incoming packages that conflict need a different provider instead
  readonly property bool settleable: view.settling
    && view.settleInfo.conflicts.every((c) => !c.inner)
  property var picks: ({})
  onSettleInfoChanged: view.picks = ({})
  function pickOf(p) { return view.picks[p.name] || p.options[0]; }
  function pick(name, option) {
    const n = Object.assign({}, view.picks);
    n[name] = option;
    view.picks = n;
  }
  function pickNext(by) {
    if (!view.settling || view.settleInfo.providers.length === 0) return;
    const p = view.settleInfo.providers[0];
    const i = p.options.indexOf(view.pickOf(p));
    view.pick(p.name, p.options[(i + by + p.options.length) % p.options.length]);
  }
  function settle() {
    if (!view.settleable) return;
    const c = {};
    for (const p of view.settleInfo.providers) c[p.name] = view.pickOf(p);
    Ceres.txSettleRun(c);
  }

  // For the holder's ctrl+c: whatever is selected in whichever log is up.
  function copy() {
    const pane = view.running ? liveLog : failLog;
    return pane.copySelection();
  }

  // ── one log, drawn the same way running or failed ──────────────────────
  component LogPane: Rectangle {
    id: pane
    property var lines: []
    radius: Zenon.windowRadius
    color: Zenon.darken(0.25)
    border.width: 1
    border.color: Zenon.border
    clip: true

    // Selected text if there is any, else nothing; true when something went.
    function copySelection() {
      const t = String(logText.selectedText || "").replace(/[\u2028\u2029]/g, "\n");
      if (t === "") return false;
      pane.toClipboard(t);
      return true;
    }
    function toClipboard(t) {
      Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", t]);
      copied.restart();
    }

    // Each line, escaped, and inked by what it is: paru's own headings, the
    // errors that explain a failure, warnings, and pacman's bars dimmed —
    // they are the progress, not the story.
    function lineHtml(l) {
      const e = String(l).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      const t = String(l).trim();
      if (/^(?:==>\s*)?error:|^==> ERROR:/i.test(t))
        return "<span style='color:" + Zenon.red + "'>" + e + "</span>";
      if (/^(?:==>\s*)?warning:|^==> WARNING:/i.test(t))
        return "<span style='color:" + Zenon.yellow + "'>" + e + "</span>";
      if (/^(?:::|==>)\s/.test(t))
        return "<span style='color:" + Zenon.cyan + "'><b>" + e + "</b></span>";
      if (Cer.progressOf(t))
        return "<span style='color:" + Zenon.muted + "'>" + e + "</span>";
      return e;
    }

    // following the end until you scroll away from it
    property bool follow: true

    Item {
      id: head
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 30

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "Log"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 13 + view.grow
      }

      Row {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        // back to the end, when you have scrolled away from it
        Text {
          visible: !pane.follow
          text: "  latest"
          color: latestMa.containsMouse ? Zenon.white : Zenon.keyInk
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: 13 + view.grow
          MouseArea {
            id: latestMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            onClicked: { pane.follow = true; pane.toEnd(); }
          }
        }

        Text {
          text: copied.running ? "  copied"
            : (logText.selectedText !== "" ? "  copy selection" : "  copy log")
          color: copied.running ? Zenon.green
            : (copyMa.containsMouse ? Zenon.white : Zenon.keyInk)
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: 13 + view.grow
          MouseArea {
            id: copyMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            onClicked: if (!pane.copySelection()) pane.toClipboard(pane.lines.join("\n"))
          }
        }
      }

      Timer { id: copied; interval: 1400 }

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Zenon.border
      }
    }

    Flickable {
      id: flick
      ElasticScroll { view: flick }
      anchors.top: head.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 1
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentWidth: width
      contentHeight: logText.height + 16

      // Whether you are at the end is decided by where you LEFT it, not by
      // every step on the way: a programmatic move to the end must not read
      // as the user having scrolled.
      property bool moving_: false
      onContentYChanged: {
        if (flick.moving_) return;
        pane.follow = flick.contentY >= flick.contentHeight - flick.height - 24;
      }
      onContentHeightChanged: if (pane.follow) pane.toEnd()
      onHeightChanged: if (pane.follow) pane.toEnd()

      TextEdit {
        id: logText
        x: 12
        y: 8
        width: flick.width - 24 - 10
        readOnly: true
        selectByMouse: true
        // Selecting must not take the keyboard from the window, which is
        // where escape and shift+escape are answered — so a press selects
        // without focusing, and the selection outlives the focus it never had.
        activeFocusOnPress: false
        persistentSelection: true
        wrapMode: TextEdit.WrapAnywhere
        textFormat: TextEdit.RichText
        selectionColor: Zenon.selBg
        selectedTextColor: Zenon.white
        color: Zenon.keyInk
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: 13 + view.grow
        text: "<div style='white-space:pre-wrap'>"
          + pane.lines.map(pane.lineHtml).join("<br>") + "</div>"
      }
    }

    ScrollRail {
      target: flick
      anchors.right: parent.right
      anchors.top: flick.top
      anchors.bottom: parent.bottom
    }

    function toEnd() {
      flick.moving_ = true;
      flick.contentY = Math.max(0, flick.contentHeight - flick.height);
      flick.moving_ = false;
    }
  }

  // ── running ─────────────────────────────────────────────────────────────
  Item {
    visible: view.running
    anchors.fill: parent

    // ── THE PHASE IS THE BAR ──────────────────────────────────────────────
    // What paru is doing, on ONE band that fills with the whole job — and
    // everything known about how far along it is written on that band. A
    // second, thinner bar under it said the same thing twice.
    //
    // How far: pacman's own Total bar while downloading, its "(x/y)"
    // counters while installing (see Cer.overallOf), and between those the
    // packages pacman.log has recorded against the number expected. The
    // fill is translucent so the words on it stay the loudest thing in it.
    Rectangle {
      id: track
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 36
      radius: Zenon.windowRadius
      color: Zenon.darken(0.25)
      border.width: 1
      border.color: Ceres.txCancelling ? Zenon.red : Zenon.border
      clip: true

      readonly property var total: Ceres.txTotal
      readonly property real frac: track.total ? track.total.frac
        : Math.min(1, Ceres.txEvents.length
            / Math.max(1, Ceres.txExpected, Ceres.txEvents.length))

      // ── THE FILL ──────────────────────────────────────────────────────
      // In the window's own accent, not a wash of yellow: a ramp that
      // deepens toward the leading edge, so the band reads as moving
      // rightward even while it is still. No line at the edge: it read as a
      // text cursor. Red, all of it, while cancelling.
      readonly property color ink: Ceres.txCancelling ? Zenon.red : Zenon.cyan
      Item {
        id: fill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: Math.max(0, (parent.width - 2) * track.frac)
        Behavior on width { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }

        Rectangle {
          anchors.fill: parent
          radius: Zenon.windowRadius - 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(track.ink.r, track.ink.g, track.ink.b, 0.04) }
            GradientStop { position: 1.0; color: Qt.rgba(track.ink.r, track.ink.g, track.ink.b, 0.20) }
          }
        }
      }

      Text {
        id: phaseText
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: Ceres.txPhase !== "" ? Ceres.txPhase : "Working"
        color: Ceres.txCancelling ? Zenon.red : Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 15 + view.grow
      }

      // ── WHAT PACMAN HAS IN HAND, ON THE BAND ────────────────────────────
      // A name, not a second bar — and not a row of its own either: a line
      // under the band that came and went with each package made the log
      // below it jump on every step of a batch. Here it takes the room the
      // band already has, between the phase and the readings, and gives way
      // to them (elided) when the band is short. Between bars, the last
      // package pacman.log recorded, so it is never empty mid-job.
      Text {
        id: now
        anchors.left: phaseText.right
        anchors.leftMargin: 12
        anchors.right: readings.left
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: {
          const l = Ceres.txLive;
          if (l) return l.label.replace(/^\(\s*\d+\/\d+\)\s*/, "");
          const e = Ceres.txEvents[Ceres.txEvents.length - 1];
          return e ? e.verb + " " + e.name + (e.to ? " " + e.to : "") : "";
        }
        color: Zenon.keyInk
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: 14 + view.grow
      }

      // the readings, then the percentage — or, before pacman has drawn a
      // bar, the package count
      Row {
        id: readings
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: text !== ""
          text: !track.total ? ""
            : [track.total.of, track.total.size, track.total.rate, track.total.eta]
                .filter(x => x !== "").join("   ")
          color: Zenon.keyInk
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: 13 + view.grow
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: track.total ? Math.floor(track.frac * 100) + "%"
            : Ceres.txEvents.length + " / " + Math.max(Ceres.txExpected, Ceres.txEvents.length)
          color: track.total ? Zenon.white : Zenon.keyInk
          font.family: Zenon.face
          font.weight: track.total ? Font.Bold : Font.Normal
          font.pixelSize: 14 + view.grow
        }
      }
    }

    LogPane {
      id: liveLog
      anchors.top: track.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      lines: Ceres.txLog
    }
  }

  // ── done, or not ────────────────────────────────────────────────────────
  Item {
    visible: !view.running
    anchors.fill: parent

    Text {
      id: resultLine
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      wrapMode: Text.Wrap
      text: {
        if (view.cancelled)
          return "Cancelled" + (Ceres.txEvents.length
            ? " — " + Ceres.txEvents.length + " already changed, and kept" : "");
        if (view.failed) return Ceres.txError;
        const t = view.tally, parts = [];
        for (const v of Cer.VERBS) if (t[v].length) parts.push(t[v].length + " " + v);
        // A run that changed no package — paccache, the download sweep — is
        // reported in the tool's own words rather than as "nothing changed",
        // which for a cache cleanup reads as the button not working.
        return (parts.length ? parts.join(" · ")
                             : ((Cer.summaryLine ? Cer.summaryLine(Ceres.txLog) : "") || "nothing changed"))
          + (Ceres.txDisk !== "" ? "      " + Ceres.txDisk : "");
      }
      color: view.cancelled ? Zenon.yellow : view.failed ? Zenon.red : Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: 15 + view.grow
    }

    // ── THE QUESTION, ASKED HERE ─────────────────────────────────────
    // Which provider (chips, the first lit — what paru would take), and
    // every replacement spelled out as what comes in and what goes, in the
    // confirm sheet's green and red. Nothing is replaced until you say so.
    Column {
      id: settleBox
      visible: view.settling
      anchors.top: resultLine.bottom
      anchors.topMargin: visible ? 12 : 0
      anchors.left: parent.left
      anchors.right: parent.right
      height: visible ? implicitHeight : 0
      spacing: 8

      Repeater {
        model: view.settling ? view.settleInfo.providers : []
        delegate: Row {
          id: provRow
          required property var modelData
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: provRow.modelData.name + " from"
            color: Zenon.keyInk
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: 14 + view.grow
          }
          Repeater {
            model: provRow.modelData.options
            delegate: Rectangle {
              id: chip
              required property string modelData
              readonly property bool on: view.pickOf(provRow.modelData) === chip.modelData
              width: chipText.implicitWidth + 20
              height: chipText.implicitHeight + 8
              radius: 5
              color: chip.on ? Zenon.alpha(Zenon.cyan, 0.16)
                : chipHov.hovered ? Zenon.wash(0.06) : Zenon.wash(0)
              border.width: 1
              border.color: chip.on ? Zenon.cyan : Zenon.border
              Behavior on color { ColorAnimation { duration: Zenon.fast } }
              Text {
                id: chipText
                anchors.centerIn: parent
                text: chip.modelData
                color: chip.on ? Zenon.cyan : Zenon.ink
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: 14 + view.grow
              }
              HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: view.pick(provRow.modelData.name, chip.modelData) }
            }
          }
        }
      }

      Repeater {
        model: view.settling ? view.settleInfo.conflicts : []
        delegate: Text {
          required property var modelData
          width: settleBox.width
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: "<font color='" + Zenon.green + "'>+ " + modelData.pkg + "</font>"
            + (modelData.inner
              ? "  <font color='" + Zenon.muted + "'>conflicts with</font>  "
                + "<font color='" + Zenon.yellow + "'>" + modelData.replaces.join(", ") + "</font>"
                + "  <font color='" + Zenon.muted + "'>— both incoming; pick another provider or use a terminal</font>"
              : "  <font color='" + Zenon.muted + "'>replaces</font>  "
                + "<font color='" + Zenon.red + "'>\u2212 " + modelData.replaces.join(", ") + "</font>")
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: 14 + view.grow
        }
      }
    }

    // ── WHAT CHANGED, AND THE LOG, AFTER IT IS OVER ─────────────────
    // The log used to go when the job did: a finished run swapped it for
    // the list of changes, and anything you had been reading in it was
    // gone. It stays now, underneath — the list of what changed on top,
    // no taller than it needs up to two fifths of the view, and the whole
    // log below it, still selectable and still at the end. On failure
    // there is no list, and the log is the explanation.
    ListView {
      id: changes
      ScrollRail {
        target: changes
        parent: changes
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
      }
      ElasticScroll { view: changes }
      visible: !view.failed && count > 0
      anchors.top: resultLine.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      height: visible ? Math.min(contentHeight, parent.height * 0.4) : 0
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: view.failed ? [] : Ceres.txEvents
      delegate: ChangeRow {
        required property var modelData
        width: changes.width - 14
        u: modelData
        glyph: modelData.verb === "removed" ? "\uF068"
          : modelData.verb === "installed" ? "\uF067" : "\uF062"
        glyphInk: modelData.verb === "removed" ? Zenon.red
          : modelData.verb === "installed" ? Zenon.green : Zenon.blue
      }
    }

    LogPane {
      id: failLog
      anchors.top: changes.visible ? changes.bottom : settleBox.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      lines: view.running ? [] : Ceres.txLog
    }
  }
}
