// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A DRIVE'S PARTITIONS, CHANGED, IN A SHEET — Disk Utility's Partition:
// the drive's map, its partitions and the free room between them as a
// list, and for the one picked what can be done there. Free room takes a
// new partition (filesystem, label, name, size, encrypted or not); a
// partition is resized within what is safe (S.resizeRange: down to what
// it holds, up to the next one) or deleted, after asking in red.
//
// Each change is made at once, through udisks (forge.py create, resize,
// delete) — nothing is queued up to apply later. The system's own disk
// never gets here (S.offWhy "partition").
//
//     Sheet { cardH: body.implicitHeight
//       StylusPartition { id: body; width: parent.width; win: sw } }

import QtQuick
import Quickshell.Io
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus"
import "../terminus/terminus.js" as Terminus
import "../ceres"
import "stylus.js" as S

FocusScope {
  id: body

  property var win: null
  readonly property var drive: body.win ? body.win.drive : null
  readonly property var mgr: body.win ? body.win.mgr : null

  // the rows: every partition and every free stretch, by where they lie
  readonly property var rows: {
    const d = body.drive;
    if (!d) return [];
    const out = (d.parts || []).map((p) => ({ part: p, free: null, at: p.offset }))
      .concat(S.freeSpaces(d).map((f) => ({ part: null, free: f, at: f.offset })));
    return out.sort((a, b) => a.at - b.at);
  }
  property int sel: 0
  readonly property var row: body.rows[Math.max(0, Math.min(body.sel, body.rows.length - 1))] || null
  readonly property var part: body.row ? body.row.part : null
  readonly property var free: body.row ? body.row.free : null

  // what can be resized, per filesystem (forge resizable), and which mkfs
  // are here (terminus' list) — asked as the sheet opens
  property var can: ({})
  property var have: ({})
  property bool working: false
  property string why: ""

  function reset(dev) {
    body.why = "";
    body.working = false;
    const i = body.rows.findIndex((r) => r.part && r.part.dev === dev);
    const f = body.rows.findIndex((r) => !!r.free);
    body.sel = i >= 0 ? i : f >= 0 ? f : 0;
    body.fill();
    body.mgr.ask(["resizable"], (j) => { if (j && !j.ev) body.can = j; });
    toolScan.running = true;
  }
  Process {
    id: toolScan
    command: ["sh", "-c", Terminus.fsToolsCommand()]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: body.have = Terminus.parseFsTools(text) }
  }

  // the form, as the picked row wants it
  property string fs: "ext4"
  property real size: 0
  property bool encrypt: false
  readonly property var range: body.part ? S.resizeRange(body.drive, body.part, body.can[body.part.fstype] || null)
    : { min: S.MIB, max: body.free ? body.free.size : 0, why: "" }
  // from `sel` itself, not body.part: in onSelChanged that binding may not
  // have caught up yet, and the form filled from the row before
  function fill() {
    const r = body.rows[Math.max(0, Math.min(body.sel, body.rows.length - 1))] || null;
    body.size = !r ? 0 : r.part ? r.part.size : r.free.size;
    body.encrypt = false;
    label.text = "";
    name.text = "";
    passA.text = "";
    passB.text = "";
    body.why = "";
  }
  onSelChanged: body.fill()
  function pick(i) { if (!body.working) body.sel = i; }

  readonly property bool sized: body.size >= body.range.min && body.size <= body.range.max
  readonly property bool passOk: !body.encrypt || (passA.text !== "" && passA.text === passB.text)
  readonly property string blocked: body.free ? S.createWhy(body.drive) : ""

  // ── DOING IT ───────────────────────────────────────────────────────────
  function done(j, words) {
    body.working = false;
    if (j && j.ok) { body.win.say(words, false); body.win.refresh(() => body.reset(j.dev || "")); }
    else body.why = j && j.why ? j.why : "It did not work";
  }
  function add() {
    if (!body.free || body.working || !body.sized || !body.passOk || body.blocked !== "") return;
    const f = Terminus.formatOf(body.fs);
    // a missing mkfs first, through Ceres, as DiskTool does
    if (f && !body.have[f.tool]) {
      const asked = Ceres.install(Terminus.fsPackage(body.fs), "to make a " + f.name + " partition", (ok) => {
        if (ok) { const h = Object.assign({}, body.have); h[f.tool] = true; body.have = h; body.add(); }
        else body.why = Terminus.fsPackage(body.fs) + " was not installed";
      });
      if (!asked) body.why = "Ceres is busy — try again once it is done";
      return;
    }
    body.working = true;
    const args = ["create", body.drive.dev, String(body.free.offset), String(S.mibDown(body.size))]
      .concat(body.fs ? ["--fs", body.fs] : [])
      .concat(body.fs && label.text.trim() !== "" ? ["--label", Terminus.cleanLabel(body.fs, label.text)] : [])
      .concat(S.canName(body.drive, {}) && name.text.trim() !== "" ? ["--name", S.cleanName(name.text)] : [])
      .concat(["--type", S.newType(body.encrypt ? "" : body.fs, body.drive.table)])
      .concat(body.encrypt ? ["--encrypt"] : []);
    const pass = body.encrypt ? passA.text : undefined;
    passA.text = "";
    passB.text = "";
    body.mgr.ask(args, (j) => body.done(j, "Partition made"), body.mgr.core, pass);
  }
  function resize() {
    if (!body.part || body.working || !body.sized || S.mibDown(body.size) === body.part.size) return;
    body.working = true;
    const dev = body.part.dev;
    if (body.part.mounts.length) body.win.leaveMountEverywhere(body.part.mounts[0]);
    body.mgr.ask(["resize", dev, String(S.mibDown(body.size))], (j) => {
      if (j) j.dev = dev;
      body.done(j, "Resized");
    });
  }
  function remove() {
    const p = body.part;
    if (!p || body.working) return;
    body.win.confirmErase("Delete " + S.partName(p) + "?",
      "the partition and everything on it are gone for good — its room becomes free space",
      [S.partName(p) + "  ·  " + Terminus.formatSize(p.size) + (p.fstype ? ", " + p.fstype : "")],
      () => {
        body.working = true;
        if (p.mounts.length) body.win.leaveMountEverywhere(p.mounts[0]);
        body.mgr.ask(["delete", p.dev], (j) => body.done(j, "Partition deleted"));
      });
  }

  implicitHeight: col.implicitHeight + 2 * 24

  Column {
    id: col
    x: 24
    y: 24
    width: parent.width - 48
    spacing: 14

    Text {
      text: "Partition " + S.driveTitle(body.drive)
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(17)
    }

    StylusMap { width: parent.width; drive: body.drive; hot: body.part ? body.part.dev : "" }

    // ── the rows ───────────────────────────────────────────────────────
    Item {
      width: parent.width
      height: rowCol.implicitHeight
      Column {
        id: rowCol
        width: parent.width
        Repeater {
          id: rowRep
          model: body.rows
          Item {
            required property var modelData
            required property int index
            width: rowCol.width
            height: 30
            Text {
              x: 10
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.part ? S.partName(modelData.part) : "Free space"
              color: modelData.part ? Zenon.ink : Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.part ? [modelData.part.fstype, Terminus.formatSize(modelData.part.size)].filter((x) => x).join("  ·  ")
                : Terminus.formatSize(modelData.free.size)
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            TapHandler { onTapped: body.pick(index) }
          }
        }
      }
      CursorBand { repeater: rowRep; index: body.sel; shown: body.rows.length > 0 }
      Text {
        visible: body.rows.length === 0
        text: "No room to make a partition"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    // ── a new partition, in free room ──────────────────────────────────
    Column {
      visible: !!body.free
      width: parent.width
      spacing: 12
      Segments {
        options: [["ext4", "ext4"], ["exfat", "exFAT"], ["vfat", "FAT32"], ["ntfs", "NTFS"], ["btrfs", "Btrfs"],
                  ["xfs", "XFS"], ["f2fs", "F2FS"], ["", "None"]]
        current: body.fs
        onChose: (v) => body.fs = v
      }
      Row {
        spacing: 10
        visible: body.fs !== ""
        BulkField { id: label; width: 220; ghost: "Label" }
        BulkField { id: name; width: 220; ghost: "Partition name"; visible: S.canName(body.drive, {}) }
      }
      Controls.Check {
        visible: body.fs !== ""
        height: 28
        width: 200
        label: "Encrypt (LUKS2)"
        lit: body.encrypt
        onToggled: body.encrypt = !body.encrypt
      }
      Row {
        visible: body.encrypt
        spacing: 10
        BulkField { id: passA; width: 220; masked: true; ghost: "Passphrase"; onAccepted: passB.claim() }
        BulkField { id: passB; width: 220; masked: true; ghost: "Again"; onAccepted: body.add() }
      }
    }

    // ── its size: new, or resized ──────────────────────────────────────
    Row {
      // nothing to choose when it can go neither way
      visible: !!body.row && body.range.max > body.range.min
      width: parent.width
      spacing: 10
      PrefSlider {
        readoutW: 76
        width: parent.width - sizeField.width - 10
        label: "Size"
        labelW: 60
        from: body.range.min / S.MIB
        to: Math.max(body.range.min / S.MIB + 1, body.range.max / S.MIB)
        value: body.size / S.MIB
        wheelStep: Math.max(1, Math.round((body.range.max - body.range.min) / S.MIB / 50))
        readout: Terminus.formatSize(body.size)
        onMoved: (v) => body.size = Math.round(v) * S.MIB
      }
      // or typed: "12 GiB", "500M"
      BulkField {
        id: sizeField
        width: 120
        ghost: "or type"
        onAccepted: {
          const n = Terminus.parseSizeStr(sizeField.text.replace(/i?B$/i, ""));
          if (n > 0) body.size = Math.max(body.range.min, Math.min(body.range.max, S.mibDown(n)));
          sizeField.text = "";
        }
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      visible: text !== ""
      text: body.why !== "" ? body.why : body.blocked !== "" ? body.blocked : body.part ? body.range.why
        : body.encrypt && passB.text !== "" && passA.text !== passB.text ? "The two do not match." : ""
      color: body.why !== "" ? Zenon.red : Zenon.yellow
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    Row {
      anchors.right: parent.right
      spacing: 10
      DialogButton { label: "Done"; ink: Zenon.accentMuted; ready: !body.working; onClicked: body.win.closePartition() }
      DialogButton {
        visible: !!body.part
        label: "Delete…"
        ink: Zenon.red
        ready: !body.working
        onClicked: body.remove()
      }
      BusyButton {
        visible: !!body.part
        label: "Resize"
        primary: true
        ink: Zenon.cyan
        ready: body.sized && !!body.part && S.mibDown(body.size) !== body.part.size
        busy: body.working
        busyText: "Working…"
        onClicked: body.resize()
      }
      BusyButton {
        visible: !!body.free
        label: "Add partition"
        primary: true
        ink: Zenon.cyan
        ready: body.sized && body.passOk && body.blocked === ""
        busy: body.working
        busyText: "Making it…"
        onClicked: body.add()
      }
    }
  }

  Keys.onEscapePressed: if (!body.working) body.win.closePartition()
  Keys.onUpPressed: body.pick(Math.max(0, body.sel - 1))
  Keys.onDownPressed: body.pick(Math.min(body.rows.length - 1, body.sel + 1))
}
