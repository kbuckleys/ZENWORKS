// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CHECK, REPAIR OR FORMAT A DISK — the card inside the sheet terminus opens
// from a disk's menu. Each filesystem's own tools and nothing that wraps them
// (see the CHECK, REPAIR AND FORMAT notes in terminus.js); which of them are
// installed decides what is offered.
//
//     Sheet { cardH: tool.implicitHeight
//       DiskTool { id: tool; width: parent.width; host: root
//         disk: d; mode: "repair" | "format"; have: tools } }
//
// The holder supplies `host`, the terminus window: its disks (for the whole
// drive's other partitions), leaveMountEverywhere (a disk being worked on is
// stepped out of first), pollDisks (to see the result), and confirmErase
// (the confirmation sheet — formatting asks there, in red, like a delete).
//
// The run's output is the log, streamed; "@@rc N" at the end of it is the
// tool's own status, which Terminus.repairVerdict reads.

import QtQuick
import Quickshell.Io
import "../morpheus"
import "../picasso"
import "terminus.js" as Terminus

FocusScope {
  id: tool

  property var host: null
  property var disk: null
  property string mode: "repair"
  property var have: ({})
  signal closed()

  // ── WHAT IS ON OFFER ──────────────────────────────────────────────────
  readonly property string fs: tool.disk ? tool.disk.fstype : ""
  readonly property var can: Terminus.repairCan(tool.fs, tool.have)
  readonly property var formats: Terminus.formatsAvailable(tool.have)
  readonly property bool mounted: !!tool.disk && tool.disk.mount !== ""
  readonly property string devName: tool.disk ? tool.disk.path.replace(/^\/dev\//, "") : ""
  readonly property string title: !tool.disk ? ""
    : (tool.disk.label || tool.disk.partLabel || tool.devName)

  // The whole drive this partition is on, and its other partitions —
  // a whole-drive format takes them too, so it is only offered when none of
  // them is something the system is standing on.
  readonly property string device: tool.disk ? (tool.disk.device || "") : ""
  readonly property var siblings: {
    if (!tool.host || tool.device === "") return [];
    return (tool.host.disks || []).filter((x) => x.device === tool.device);
  }
  readonly property bool wholeOk: tool.device !== "" && !!tool.have["sfdisk"]
    && tool.siblings.every((x) => !Terminus.isSystemMount(x.mount))

  // ── CHOICES ───────────────────────────────────────────────────────────
  property string action: "check"           // repair: check | repair
  property string scope: "part"             // format: part | gpt | msdos
  property string target: ""                // format: fs
  property int block: 0
  property bool quick: true
  property int reserved: 1
  property bool mountAfter: true
  readonly property var fmt: Terminus.formatOf(tool.target)

  // ── RUNNING ───────────────────────────────────────────────────────────
  property bool running: false
  property var log: []
  property int rc: -1
  property var verdict: null
  readonly property bool done: tool.rc >= 0

  function reset() {
    tool.action = "check";
    tool.scope = "part";
    const f = tool.formats;
    // the disk's own format if it can be made again, else the first offered
    tool.target = f.some((x) => x.fs === tool.fs) ? tool.fs : (f.length > 0 ? f[0].fs : "");
    tool.block = 0;
    tool.quick = true;
    tool.reserved = 1;
    tool.mountAfter = true;
    label.text = tool.disk ? (tool.disk.label || "") : "";
    tool.log = [];
    tool.rc = -1;
    tool.verdict = null;
  }

  function say(line) {
    const next = tool.log.slice(-399);
    next.push(String(line));
    tool.log = next;
    Qt.callLater(() => logView.positionViewAtEnd());
  }

  function start() {
    if (tool.running || !tool.disk) return;
    let cmd = "";
    if (tool.mode === "repair") {
      if (tool.mounted) tool.host.leaveMountEverywhere(tool.disk.mount);
      cmd = Terminus.repairCommand(tool.disk.path, tool.fs, tool.action, tool.mounted);
    } else {
      const whole = tool.scope !== "part";
      const parts = whole ? tool.siblings : [tool.disk];
      const mounts = parts.filter((x) => x.mount !== "");
      for (const x of mounts) tool.host.leaveMountEverywhere(x.mount);
      cmd = Terminus.formatCommand({
        fs: tool.target, label: label.text, block: tool.block, quick: tool.quick,
        reserved: tool.reserved, mountAfter: tool.mountAfter,
        target: tool.disk.path, device: tool.device !== "" ? tool.device : tool.disk.path,
        table: whole ? tool.scope : "", mounts: mounts.map((x) => x.path)
      });
    }
    if (cmd === "") return;
    tool.log = [];
    tool.rc = -1;
    tool.verdict = null;
    tool.running = true;
    proc.command = ["sh", "-c", cmd];
    proc.running = true;
  }

  // Formatting asks first, on the confirmation sheet, in red — it is the
  // most final thing this window can do.
  function go() {
    if (tool.running) return;
    if (tool.done) { tool.reset(); return; }
    if (tool.mode === "repair") { tool.start(); return; }
    if (!tool.fmt) return;
    const whole = tool.scope !== "part";
    const what = whole ? "the whole of " + tool.device.replace(/^\/dev\//, "")
                       : tool.title + " (" + tool.devName + ")";
    tool.host.confirmErase("Erase " + what + "?",
      "everything on it is gone for good — it becomes an empty "
        + tool.fmt.name + (whole ? " drive with one partition" : " partition"),
      whole ? tool.siblings.map((x) => (x.label || x.path.replace(/^\/dev\//, "")) + "  " + x.size)
            : [],
      () => tool.start());
  }

  Process {
    id: proc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => {
        const m = /^@@rc (\d+)$/.exec(line);
        if (m) { tool.rc = Number(m[1]); return; }
        tool.say(line);
      }
    }
    stderr: SplitParser { splitMarker: "\n"; onRead: (line) => tool.say(line) }
    onExited: (code) => {
      tool.running = false;
      if (tool.rc < 0) tool.rc = code;
      const last = tool.log.length > 0 ? tool.log[tool.log.length - 1] : "";
      if (tool.rc === 90)
        tool.verdict = { ok: false, line: "could not unmount: " + Terminus.tidyDiskError(last) };
      else if (tool.mode === "repair")
        tool.verdict = Terminus.repairVerdict(tool.can ? tool.can.tool : "", tool.action, tool.rc);
      else if (tool.rc === 0)
        tool.verdict = { ok: true, line: "formatted as " + (tool.fmt ? tool.fmt.name : tool.target) };
      else tool.verdict = Terminus.repairVerdict("", "format", tool.rc);
      if (tool.verdict && tool.verdict.line.indexOf("finished with errors") === 0 && tool.mode === "format")
        tool.verdict = { ok: false, line: "formatting failed (exit " + tool.rc + ")" };
      if (tool.host) {
        tool.host.pollDisks();
        if (tool.verdict.ok) tool.host.status = tool.title + ": " + tool.verdict.line;
        else tool.host.warn(tool.title + ": " + tool.verdict.line);
      }
    }
  }

  Keys.onEscapePressed: if (!tool.running) tool.closed()
  Keys.onReturnPressed: tool.go()
  Keys.onEnterPressed: tool.go()

  // ── LAYOUT ────────────────────────────────────────────────────────────
  readonly property int pad: 20
  implicitHeight: body.y + body.height + 14 + 32 + 14

  Column {
    id: body
    x: tool.pad
    y: 16
    width: tool.width - 2 * tool.pad
    spacing: 12

    // What it is, in one line.
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: !tool.disk ? "" : [tool.disk.fstype + (tool.disk.fsVer ? " " + tool.disk.fsVer : ""),
                               tool.disk.path, tool.disk.size,
                               tool.mounted ? "mounted at " + tool.disk.mount : "not mounted"]
                              .filter((x) => x).join("  ·  ")
      color: Zenon.muted
      font.family: Zenon.faceMono
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    // ── REPAIR ─────────────────────────────────────────────────────
    Column {
      visible: tool.mode === "repair"
      width: parent.width
      spacing: 10

      Text {
        visible: !tool.can
        width: parent.width
        wrapMode: Text.WordWrap
        text: Terminus.fsPackage(tool.fs) !== ""
          ? "Nothing here can check " + tool.fs + " — install " + Terminus.fsPackage(tool.fs) + " for its tools."
          : "There is no checker for " + (tool.fs || "this disk") + "."
        color: Zenon.yellow
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

      Row {
        visible: !!tool.can
        spacing: 8
        Seg {
          width: 150
          label: "Check"
          chosen: tool.action === "check"
          live: !tool.running
          onHit: { tool.action = "check"; if (tool.done) tool.reset(); }
        }
        Seg {
          width: 150
          label: "Repair"
          visible: !!tool.can && tool.can.repair
          chosen: tool.action === "repair"
          live: !tool.running
          onHit: { tool.action = "repair"; if (tool.done) { const a = "repair"; tool.reset(); tool.action = a; } }
        }
      }

      Text {
        visible: !!tool.can
        width: parent.width
        wrapMode: Text.WordWrap
        text: {
          if (!tool.can) return "";
          const verb = tool.action === "check"
            ? tool.can.tool + " reads it and changes nothing."
            : tool.can.tool + " fixes what it finds.";
          const ntfs = tool.fs === "ntfs"
            ? (tool.action === "repair"
               ? " For NTFS that is the dirty flag and the journal — enough to mount it again; Windows' chkdsk /f is the full repair."
               : " For NTFS it says whether the volume is marked dirty.")
            : "";
          const btrfs = tool.fs === "btrfs" ? " Btrfs is checked only: its repair is a last resort, not a menu item." : "";
          const mnt = tool.mounted ? " It is unmounted while this runs and mounted again after." : "";
          return verb + ntfs + btrfs + mnt + " Needs your password.";
        }
        color: Zenon.soft
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
        lineHeight: 1.15
      }
    }

    // ── FORMAT ─────────────────────────────────────────────────────
    Column {
      visible: tool.mode === "format"
      width: parent.width
      spacing: 12

      Text {
        visible: tool.formats.length === 0
        width: parent.width
        wrapMode: Text.WordWrap
        text: "No mkfs tools found — install e2fsprogs, ntfs-3g, exfatprogs or dosfstools."
        color: Zenon.yellow
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

      // What to erase: this partition, or the whole drive with a new table.
      Row {
        visible: tool.wholeOk && tool.formats.length > 0
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: "erase"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Repeater {
          model: [["part", "This partition"], ["gpt", "Whole drive · GPT"], ["msdos", "Whole drive · MBR"]]
          delegate: Seg {
            required property var modelData
            width: 150
            label: modelData[1]
            chosen: tool.scope === modelData[0]
            live: !tool.running
            onHit: tool.scope = modelData[0]
          }
        }
      }

      Row {
        visible: tool.formats.length > 0
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: "format"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Flow {
          width: body.width - 118
          spacing: 8
          Repeater {
            model: tool.formats
            delegate: Seg {
              required property var modelData
              width: 82
              label: modelData.name
              chosen: tool.target === modelData.fs
              live: !tool.running
              onHit: { tool.target = modelData.fs; tool.block = 0; }
            }
          }
        }
      }
      Text {
        visible: !!tool.fmt
        x: 118
        width: body.width - 118
        wrapMode: Text.WordWrap
        text: tool.fmt ? tool.fmt.note : ""
        color: Zenon.soft
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }

      Row {
        visible: !!tool.fmt
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: "label"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        BulkField {
          id: label
          width: 260
          ghost: "none"
          onAccepted: tool.go()
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (!tool.fmt) return "";
            const c = Terminus.cleanLabel(tool.target, label.text);
            return c !== label.text.trim() && label.text.trim() !== ""
              ? "saved as “" + c + "”" : "up to " + tool.fmt.labelMax;
          }
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }

      Row {
        visible: !!tool.fmt && tool.fmt.blocks.length > 1
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: tool.target === "ext4" || tool.target === "xfs" ? "block size" : "cluster size"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Flow {
          width: body.width - 118
          spacing: 6
          Repeater {
            model: tool.fmt ? tool.fmt.blocks : []
            delegate: Seg {
              required property var modelData
              width: modelData === 0 ? 92 : 68
              height: 28
              label: modelData === 0 ? "auto ✓" : Terminus.blockLabel(modelData)
              chosen: tool.block === modelData
              live: !tool.running
              onHit: tool.block = modelData
            }
          }
        }
      }

      Row {
        visible: tool.target === "ext4"
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: "kept for root"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Repeater {
          model: [0, 1, 5]
          delegate: Seg {
            required property var modelData
            width: 68
            height: 28
            label: modelData + "%"
            chosen: tool.reserved === modelData
            live: !tool.running
            onHit: tool.reserved = modelData
          }
        }
      }

      Row {
        visible: !!tool.fmt
        x: 118
        spacing: 24
        Switch {
          width: 150
          visible: tool.target === "ntfs"
          label: "Quick format"
          on: tool.quick
          onToggled: tool.quick = !tool.quick
        }
        Switch {
          width: 170
          label: "Mount when done"
          on: tool.mountAfter
          onToggled: tool.mountAfter = !tool.mountAfter
        }
      }
    }

    // ── THE RUN ────────────────────────────────────────────────────
    Rectangle {
      visible: tool.running || tool.log.length > 0
      width: parent.width
      height: Math.min(200, Math.max(60, logView.contentHeight + 16))
      radius: 6
      color: Zenon.darken(0.35)
      border.width: 1
      border.color: Zenon.border
      ListView {
        id: logView
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        model: tool.log
        boundsBehavior: Flickable.StopAtBounds
        delegate: Text {
          required property var modelData
          required property int index
          width: logView.width
          wrapMode: Text.WrapAnywhere
          text: modelData
          color: modelData.indexOf("$ ") === 0 ? Zenon.cyan : Zenon.soft
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
    }

    Row {
      visible: tool.running || !!tool.verdict
      spacing: 10
      Working {
        running: tool.running
        visible: tool.running
        ink: Zenon.cyan
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: body.width - 40
        wrapMode: Text.WordWrap
        text: tool.running ? (tool.mode === "format" ? "formatting…" : "running " + (tool.can ? tool.can.tool : "") + "…")
          : (tool.verdict ? tool.verdict.line : "")
        color: tool.running ? Zenon.soft : (tool.verdict && tool.verdict.ok ? Zenon.green : Zenon.red)
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
    }
  }

  // ── ANSWERS, bottom right, Close left of the verb ─────────────────────
  Row {
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 14
    spacing: 8
    DialogButton {
      label: tool.done ? "Close" : "Cancel"
      ink: Zenon.muted
      ready: !tool.running
      onClicked: if (!tool.running) tool.closed()
    }
    DialogButton {
      visible: tool.mode === "repair" ? !!tool.can : tool.formats.length > 0
      label: tool.done ? "Again" : (tool.mode === "format" ? "Format…"
             : (tool.action === "repair" ? "Repair" : "Check"))
      ink: tool.done ? Zenon.cyan
        : (tool.mode === "format" ? Zenon.red : (tool.action === "repair" ? Zenon.yellow : Zenon.cyan))
      primary: true
      ready: !tool.running
      onClicked: tool.go()
    }
  }
}
