// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Hestia's overview: what wants looking at. Services that failed, services
// restarting over and over (one that keeps dying and being started again
// looks fine from a list — it is "running" most of the time), this boot's
// errors, how long the boot took and what took it, and the drives' health
// and the firmware updates waiting (core/health.py, fwupd).

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../hermes"
import "../ceres"
import "../terminus"
import "hestia.js" as H

Item {
  id: ov

  property var mgr: null
  property var win: null

  readonly property var all: ov.mgr ? ov.mgr.system.concat(ov.mgr.user) : []
  readonly property var failed: ov.all.filter((u) => u.active === "failed")
  readonly property var looping: ov.all.filter((u) => H.looping(u)).sort((a, b) => b.restarts - a.restarts)
  property var errors: []

  function load() {
    if (!ov.mgr) return;
    ov.mgr.refreshBoot();
    ov.mgr.ask(["logs"].concat(H.logArgs({ prio: "3", boot: "0", n: 40 })), (rows) => { if (rows) ov.errors = rows.reverse(); });
    if (!drivesProc.running) drivesProc.running = true;
    if (!fwProc.running) fwProc.running = true;
  }

  // ── DRIVES AND FIRMWARE ──────────────────────────────────────────────
  property var drives: []
  property var firmware: ({ known: false, installed: false, devices: [] })
  readonly property var sickDrives: ov.drives.filter((d) => H.diskVerdict(d).level === "bad" || H.diskVerdict(d).level === "warn")
  readonly property string health: Quickshell.shellDir + "/hestia/core/health.py"
  Process {
    id: drivesProc
    command: ["python3", ov.health, "disks"]
    stdout: StdioCollector { id: drivesOut; waitForEnd: true; onStreamFinished: ov.drives = H.parseDrives(drivesOut.text) }
  }
  Process {
    id: fwProc
    command: ["python3", ov.health, "firmware"]
    stdout: StdioCollector { id: fwOut; waitForEnd: true; onStreamFinished: { const f = H.parseFirmware(fwOut.text); if (f.known) ov.firmware = f; } }
  }
  // Every firmware step is root's, through Ceres' password card: fwupd
  // installed with its daily metadata timer; the metadata fetched now; one
  // device updated. Asked again once each is done.
  property string fwBusy: ""
  function fwStep(kind, pkgs, why, steps) {
    if (ov.fwBusy !== "") return;
    ov.fwBusy = kind;
    const ok = Ceres.install(pkgs, why, (done) => { ov.fwBusy = ""; ov.load(); }, steps);
    if (!ok) { ov.fwBusy = ""; if (ov.win) ov.win.say("Ceres is busy — try again once it is done", true); }
  }
  function fwSetup() {
    ov.fwStep("setup", ["fwupd"], "for firmware updates in System Journal",
              [["@sudo", "systemctl", "enable", "--now", "fwupd-refresh.timer"], ["@sudo", "fwupdmgr", "refresh", "--force"]]);
  }
  function fwRefresh() { ov.fwStep("refresh", [], "look for firmware updates", [["@sudo", "fwupdmgr", "refresh", "--force"]]); }
  function fwUpdate(d) {
    ov.fwStep(d.id, [], "update the firmware of " + d.name,
              [["@sudo", "fwupdmgr", "update", d.id, "-y", "--no-reboot-check"]]);
  }
  onVisibleChanged: if (ov.visible) ov.load()
  // the first page is visible from the start, so no change ever says so
  Component.onCompleted: Qt.callLater(() => { if (ov.visible) ov.load(); })

  // a failing service clicked flashes, then opens (morpheus/RowFlash)
  RowFlash { id: rowFlash }
  Flickable {
    id: pageFlick
    anchors.fill: parent
    contentHeight: col.implicitHeight + 48
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: col
      x: 28
      y: 24
      width: ov.width - 56
      spacing: 16

      // ── all well, said plainly ───────────────────────────────────────────
      HermesCard {
        // all well: centered, the accent's check (U+F05D; user, 2026-10-21 —
        // the green one went)
        centered: ov.failed.length + ov.looping.length === 0
        glyph: ov.failed.length + ov.looping.length === 0 ? "\uF05D" : "\u{F0028}"
        glyphInk: ov.failed.length + ov.looping.length === 0 ? Zenon.cyan : Zenon.red
        title: ov.failed.length + ov.looping.length === 0 ? "Everything is running as it should"
          : ov.failed.length > 0 && ov.looping.length > 0 ? ov.failed.length + " failed, " + ov.looping.length + " restarting over and over"
          : ov.failed.length > 0 ? (ov.failed.length === 1 ? "1 service failed" : ov.failed.length + " services failed")
          : (ov.looping.length === 1 ? "1 service keeps restarting" : ov.looping.length + " services keep restarting")
        note: ov.mgr && ov.mgr.loadingUnits && ov.all.length === 0 ? "Asking systemd…" : ""

        Repeater {
          model: ov.failed.length + ov.looping.length
          delegate: Item {
            required property int index
            readonly property bool isFailed: index < ov.failed.length
            readonly property var u: isFailed ? ov.failed[index] : ov.looping[index - ov.failed.length]
            width: parent ? parent.width : 0
            height: 50
            Rectangle { anchors.fill: parent; color: rowPress.pressed ? Zenon.pressTile(false) : "transparent" }
            FlashOver { flash: rowFlash; index: parent.index }
            Column {
              anchors.left: parent.left
              anchors.leftMargin: 18
              anchors.right: what.left
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2
              Text {
                width: parent.width
                elide: Text.ElideRight
                text: H.shortName(u.unit) + (u.scope === "user" ? "  (yours)" : "")
                color: Zenon.ink
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: Zenon.px(14)
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: u.desc || ""
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
              }
            }
            Text {
              id: what
              anchors.right: parent.right
              anchors.rightMargin: 18
              anchors.verticalCenter: parent.verticalCenter
              text: isFailed ? "Failed" : "Restarted " + u.restarts + " times"
              color: Zenon.red
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: Zenon.px(13)
            }
            MouseArea { id: rowPress; anchors.fill: parent; onClicked: { const x = parent.u; if (ov.win) rowFlash.flashThen(parent.index, () => ov.win.showUnit(x.unit, x.scope)); } }
          }
        }
      }

      // ── this boot's errors ───────────────────────────────────────────────
      HermesCard {
        glyph: "\u{F09EE}"
        glyphInk: ov.errors.length > 0 ? Zenon.yellow : Zenon.accentMuted
        title: "Errors since this boot"
        note: ov.errors.length > 0 ? "the latest " + ov.errors.length : ""
        trailing: [
          DialogButton {
            implicitHeight: 28
            label: "In the journal"
            onClicked: if (ov.win) ov.win.journalOf("", "", "3")
          }
        ]
        EmptyState {
          width: parent ? parent.width : 0
          height: 44
          verticalAlignment: Text.AlignVCenter
          visible: ov.errors.length === 0
          text: "No errors logged since the machine started"
        }
        Repeater {
          model: Math.min(8, ov.errors.length)
          delegate: Item {
            required property int index
            readonly property var r: ov.errors[index]
            width: parent ? parent.width : 0
            height: Math.max(26, errText.contentHeight + 8)
            Text {
              id: errTime
              x: 18
              y: 4
              text: H.clock(r.t)
              color: Zenon.accentMuted
              font.family: Zenon.faceCode
              font.weight: Zenon.codeWeight
              font.pixelSize: Zenon.px(12)
            }
            Text {
              id: errWho
              x: errTime.x + errTime.width + 10
              y: 4
              width: 130
              elide: Text.ElideRight
              text: r.ident || H.shortName(r.unit)
              color: Zenon.red
              font.family: Zenon.faceCode
              font.weight: Math.min(900, Zenon.codeWeight + 100)
              font.pixelSize: Zenon.px(12)
            }
            Text {
              id: errText
              x: errWho.x + errWho.width + 10
              y: 4
              width: parent.width - x - 18
              wrapMode: Text.WrapAnywhere
              maximumLineCount: 2
              elide: Text.ElideRight
              text: r.msg
              color: Zenon.ink
              font.family: Zenon.faceCode
              font.weight: Zenon.codeWeight
              font.pixelSize: Zenon.px(12)
            }
          }
        }
        Item { width: 1; height: 8; visible: ov.errors.length > 0 }
      }

      // ── the boot ─────────────────────────────────────────────────────────
      HermesCard {
        glyph: "\u{F14DE}"
        glyphInk: Zenon.cyan
        title: "The last boot"
        note: ""
        EmptyState {
          width: parent ? parent.width : 0
          height: 40
          verticalAlignment: Text.AlignVCenter
          visible: !ov.mgr || !ov.mgr.bootInfo
          text: "Asking systemd-analyze\u2026"
        }
        HermesFact { label: "Took"; value: ov.mgr && ov.mgr.bootInfo ? ov.mgr.bootInfo.summary.replace(/^Startup finished in /, "") : "" }
        Repeater {
          model: ov.mgr && ov.mgr.bootInfo ? Math.min(6, ov.mgr.bootInfo.blame.length) : 0
          delegate: HermesFact {
            required property int index
            readonly property var b: ov.mgr.bootInfo.blame[index]
            label: index === 0 ? "Slowest" : ""
            value: b.took + "  ·  " + b.unit
          }
        }
        Item { width: 1; height: 8 }
      }

      // ── the drives ───────────────────────────────────────────────────────
      HermesCard {
        glyph: "\u{F02CA}"
        glyphInk: ov.sickDrives.length > 0 ? Zenon.yellow : Zenon.cyan
        title: ov.sickDrives.length > 0 ? "A drive wants looking at" : "Drives"
        note: ov.drives.length > 0 ? ov.drives.length + (ov.drives.length === 1 ? " drive" : " drives") : ""
        EmptyState {
          width: parent ? parent.width : 0
          height: 40
          verticalAlignment: Text.AlignVCenter
          visible: ov.drives.length === 0
          text: drivesProc.running ? "Asking udisks\u2026" : "udisks reported no drives"
        }
        Repeater {
          model: ov.drives.length
          delegate: HermesFact {
            required property int index
            readonly property var d: ov.drives[index]
            label: d.model || d.dev
            value: H.diskLine(d) + (H.diskVerdict(d).why.length > 1 ? "  ·  " + H.diskVerdict(d).why.slice(1).join(", ") : "")
            labelW: 220
          }
        }
        Item { width: 1; height: 8 }
      }

      // ── firmware ─────────────────────────────────────────────────────────
      HermesCard {
        glyph: "\u{F061A}"
        glyphInk: ov.firmware.devices.length > 0 ? Zenon.yellow : Zenon.accentMuted
        title: ov.firmware.devices.length > 0 ? "Firmware updates" : "Firmware"
        note: ov.firmware.installed ? (ov.firmware.devices.length > 0 ? ov.firmware.devices.length + " waiting" : "Up to date") : ""
        trailing: [
          BusyButton {
            visible: ov.firmware.installed
            glyph: true
            label: "\u{F0450}"
            busy: ov.fwBusy === "refresh"
            onClicked: ov.fwRefresh()
          }
        ]
        HermesSetup {
          width: parent ? parent.width : 0
          topPadding: 6
          bottomPadding: 22
          visible: ov.firmware.known && !ov.firmware.installed
          glyph: "\u{F061A}"
          title: "Firmware updates need fwupd"
          body: "fwupd updates the firmware of drives, docks, mice, keyboards and the board itself from LVFS, where the makers publish it. Installed through Ceres; it looks for updates once a day."
          action: "Install fwupd"
          busy: ov.fwBusy === "setup"
          onGo: ov.fwSetup()
        }
        EmptyState {
          width: parent ? parent.width : 0
          height: 40
          verticalAlignment: Text.AlignVCenter
          visible: ov.firmware.installed && ov.firmware.devices.length === 0
          text: "Nothing to update"
        }
        Repeater {
          model: ov.firmware.devices.length
          delegate: Item {
            id: fwRow
            required property int index
            readonly property var d: ov.firmware.devices[index]
            width: parent ? parent.width : 0
            height: 48
            Column {
              x: 18
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - fwBtn.width - 50
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: fwRow.d.name + "  ·  " + fwRow.d.version + " \u2192 " + fwRow.d.update
                color: Zenon.ink
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: Zenon.px(14)
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: (fwRow.d.reboot ? "Restart needed afterwards  ·  " : "") + fwRow.d.summary
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
              }
            }
            BusyButton {
              id: fwBtn
              anchors.right: parent.right
              anchors.rightMargin: 14
              anchors.verticalCenter: parent.verticalCenter
              label: "Update"
              ink: Zenon.green
              busy: ov.fwBusy === fwRow.d.id
              busyText: "Updating\u2026"
              onClicked: ov.fwUpdate(fwRow.d)
            }
          }
        }
        Item { width: 1; height: 8 }
      }
    }
  }
  // over the view, not inside it (a child of a Flickable scrolls away with
  // its content and never sees the wheel — see morpheus/ElasticScroll)
  ElasticScroll { anchors.fill: pageFlick; view: pageFlick }
  // up under the head, down under the hints, frosted (morpheus/ScrollEdge)
  ScrollEdge { view: pageFlick; follow: true; chromeTop: ov.win ? -ov.win.headH : 0 }
  ScrollEdge { view: pageFlick; below: true; follow: true; bar: ov.win ? ov.win.footItem : null }
  Scrollbar { flick: pageFlick; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom }
}
