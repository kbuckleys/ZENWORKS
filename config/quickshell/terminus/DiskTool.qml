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
import "../morpheus/controls" as Controls
import "../ceres"
import "terminus.js" as Terminus

FocusScope {
  id: tool

  property var host: null
  property var disk: null
  property string mode: "repair"
  property var have: ({})
  // what the card opens set to, applied by reset(): { scope, fs, label }
  // (stylus' "Reset to a normal drive")
  property var preset: null
  signal closed()

  // ── WHAT IS ON OFFER ──────────────────────────────────────────────────
  readonly property string fs: tool.disk ? tool.disk.fstype : ""
  readonly property var can: Terminus.repairCan(tool.fs, tool.have)
  // EVERY FORMAT, installed or not (2026-10-24): one whose mkfs is missing
  // is installed through Ceres when it is chosen and formatted with (`got`
  // holds what was installed while this card was up)
  readonly property var formats: Terminus.FORMATS
  property var got: ({})
  function hasTool(t) { return !!tool.have[t] || !!tool.got[t]; }
  // the packages a format with these options still needs, [] when none
  readonly property var needs: {
    const out = [];
    if (tool.fmt && !tool.hasTool(tool.fmt.tool)) out.push(Terminus.fsPackage(tool.target));
    if (tool.encrypt && !tool.hasTool("cryptsetup")) out.push("cryptsetup");
    return out.filter((x) => x !== "");
  }
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
  property bool encrypt: false
  property bool zero: false
  readonly property var fmt: Terminus.formatOf(tool.target)
  // the size being formatted, for Auto: the partition, or the whole drive
  // (its own size when the host knows it, else its partitions added up)
  readonly property real bytes: {
    if (!tool.disk) return 0;
    const one = (x) => x.bytes || Math.max(0, Terminus.parseSizeStr(x.size));
    if (tool.scope === "part") return one(tool.disk);
    return tool.disk.deviceBytes || tool.siblings.reduce((a, x) => a + one(x), 0);
  }
  readonly property bool passOk: !tool.encrypt || (passA.text !== "" && passA.text === passB.text)

  // ── RUNNING ───────────────────────────────────────────────────────────
  property bool running: false
  property var log: []
  property int rc: -1
  property var verdict: null
  readonly property bool done: tool.rc >= 0

  function reset() {
    tool.action = "check";
    tool.scope = "part";
    // the disk's own format if it can be made again, else the first that
    // is installed, else the first
    const f = tool.formats;
    const ready = f.filter((x) => tool.hasTool(x.tool));
    tool.target = f.some((x) => x.fs === tool.fs) ? tool.fs : (ready.length > 0 ? ready[0].fs : f[0].fs);
    tool.block = 0;
    tool.quick = true;
    tool.reserved = 1;
    tool.mountAfter = true;
    tool.encrypt = false;
    tool.zero = false;
    passA.text = "";
    passB.text = "";
    label.text = tool.disk ? (tool.disk.label || "") : "";
    if (tool.preset) {
      if (tool.preset.scope) tool.scope = tool.preset.scope;
      if (tool.preset.fs) tool.target = tool.preset.fs;
      if (tool.preset.label !== undefined) label.text = tool.preset.label;
    }
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

  // the passphrase on its way to the root script's stdin (see formatCommand)
  property string pending: ""
  function start() {
    if (tool.running || !tool.disk) return;
    // a missing mkfs (or cryptsetup) first, through Ceres' own password
    // card and log; the format follows once it is in
    if (tool.mode === "format" && tool.needs.length > 0) {
      const want = tool.needs.slice();
      const asked = Ceres.install(want, "to format " + tool.title, (ok) => {
        if (!ok) { tool.verdict = { ok: false, line: "not formatted: " + want.join(", ") + " was not installed" }; tool.rc = 1; return; }
        const g = Object.assign({}, tool.got);
        g[tool.fmt.tool] = true;
        if (tool.encrypt) g["cryptsetup"] = true;
        tool.got = g;
        tool.start();
      });
      if (!asked) tool.verdict = { ok: false, line: "Ceres is busy — try again once it is done" };
      return;
    }
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
        reserved: tool.reserved, mountAfter: tool.mountAfter, bytes: tool.bytes,
        zero: tool.zero, encrypt: tool.encrypt,
        target: tool.disk.path, device: tool.device !== "" ? tool.device : tool.disk.path,
        table: whole ? tool.scope : "", mounts: mounts.map((x) => x.path)
      });
      tool.pending = tool.encrypt ? passA.text : "";
      passA.text = "";
      passB.text = "";
    }
    if (cmd === "") return;
    tool.log = [];
    tool.rc = -1;
    tool.verdict = null;
    tool.running = true;
    proc.stdinEnabled = tool.pending !== "";
    proc.command = ["sh", "-c", cmd];
    proc.running = true;
  }

  // Formatting asks first, on the confirmation sheet, in red — it is the
  // most final thing this window can do.
  // a check that found what Repair can fix: the next press repairs, with
  // no going back to switch modes (2026-10-24)
  readonly property bool repairNext: tool.done && tool.mode === "repair" && tool.action === "check"
    && !!tool.verdict && !tool.verdict.ok && !!tool.can && tool.can.repair
  function go() {
    if (tool.running) return;
    if (tool.repairNext) { tool.action = "repair"; tool.rc = -1; tool.verdict = null; tool.start(); return; }
    if (tool.done) { tool.reset(); return; }
    if (tool.mode === "repair") { tool.start(); return; }
    if (!tool.fmt || !tool.passOk) return;
    const whole = tool.scope !== "part";
    const what = whole ? "the whole of " + tool.device.replace(/^\/dev\//, "")
                       : tool.title + " (" + tool.devName + ")";
    tool.host.confirmErase("Erase " + what + "?",
      "everything on it is gone for good — it becomes an empty "
        + (tool.encrypt ? "encrypted " : "") + tool.fmt.name + (whole ? " drive with one partition" : " partition")
        + (tool.zero ? ", every byte overwritten with zeros first" : ""),
      whole ? tool.siblings.map((x) => (x.label || x.path.replace(/^\/dev\//, "")) + "  " + x.size)
            : [],
      () => tool.start());
  }

  Process {
    id: proc
    // the passphrase, once, then stdin shut; never held past this
    onStarted: if (tool.pending !== "") { proc.write(tool.pending + "\n"); tool.pending = ""; proc.stdinEnabled = false; }
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
  // a holder whose bar does not already name the card (stylus' sheets hang
  // from a plain head) gives it its heading here, and the padding its
  // other sheets keep; terminus' bar says it, and keeps 20
  property string heading: ""
  property int pad: 20
  implicitHeight: body.y + body.height + 14 + 32 + (tool.heading !== "" ? tool.pad : 14)

  Column {
    id: body
    x: tool.pad
    y: tool.heading !== "" ? tool.pad : 16
    width: tool.width - 2 * tool.pad
    spacing: 12

    Text {
      visible: tool.heading !== ""
      width: parent.width
      elide: Text.ElideRight
      text: tool.heading
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(17)
    }

    // What it is, in one line.
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: !tool.disk ? "" : [tool.disk.fstype + (tool.disk.fsVer ? " " + tool.disk.fsVer : ""),
                               tool.disk.path, tool.disk.size,
                               tool.mounted ? "mounted at " + tool.disk.mount : "not mounted"]
                              .filter((x) => x).join("  ·  ")
      color: Zenon.accentMuted
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
        // one pill of choices, the suite's (user, 2026-10-24: not a row of
        // separate buttons)
        Segments {
          enabled: !tool.running
          options: [["check", "Check"]].concat(tool.can && tool.can.repair ? [["repair", "Repair"]] : [])
          current: tool.action
          onChose: (v) => {
            if (tool.done) tool.reset();
            tool.action = v;
          }
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
        color: Zenon.accentSoft
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

      // What to erase: this partition, or the whole drive with a new table.
      Row {
        visible: tool.wholeOk
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: "Erase"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Segments {
          anchors.verticalCenter: parent.verticalCenter
          enabled: !tool.running
          options: [["part", "This partition"], ["gpt", "Whole drive · GPT"], ["msdos", "Whole drive · MBR"]]
          current: tool.scope
          onChose: (v) => tool.scope = v
        }
      }

      Row {
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: "Format"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Segments {
          anchors.verticalCenter: parent.verticalCenter
          enabled: !tool.running
          options: tool.formats.map((f) => [f.fs, f.name])
          current: tool.target
          // not installed yet: the download mark before its name, and said
          // under the row
          glyphOf: (v) => { const f = Terminus.formatOf(v); return f && !tool.hasTool(f.tool) ? "\u{F01DA}" : ""; }
          onChose: (v) => { tool.target = v; tool.block = 0; }
        }
      }
      Text {
        visible: !!tool.fmt
        x: 118
        width: body.width - 118
        wrapMode: Text.WordWrap
        text: !tool.fmt ? "" : tool.fmt.note
          + (tool.hasTool(tool.fmt.tool) ? "" : " — needs " + Terminus.fsPackage(tool.target) + ", installed when you format")
        color: Zenon.accentSoft
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
          text: "Label"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        BulkField {
          id: label
          width: 260
          ghost: "None"
          onAccepted: tool.go()
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (!tool.fmt) return "";
            const c = Terminus.cleanLabel(tool.target, label.text);
            return c !== label.text.trim() && label.text.trim() !== ""
              ? "Saved as “" + c + "”" : "up to " + tool.fmt.labelMax;
          }
          color: Zenon.accentMuted
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
          text: tool.target === "ext4" || tool.target === "xfs" ? "Block size" : "Cluster size"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Segments {
          anchors.verticalCenter: parent.verticalCenter
          enabled: !tool.running
          // Auto says what it is for this size (autoBlock)
          readonly property int auto: Terminus.autoBlock(tool.target, tool.bytes)
          // the size Auto names is not offered a second time beside it
          options: (tool.fmt ? tool.fmt.blocks : []).filter((b) => b === 0 || b !== auto).map((b) => [String(b),
            b === 0 ? (auto > 0 ? "Auto · " + Terminus.blockLabel(auto) : "Auto") : Terminus.blockLabel(b)])
          current: String(tool.block)
          onChose: (v) => tool.block = Number(v)
        }
      }

      Row {
        visible: tool.target === "ext4"
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: "Kept for root"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Segments {
          anchors.verticalCenter: parent.verticalCenter
          enabled: !tool.running
          options: [["0", "0%"], ["1", "1%"], ["5", "5%"]]
          current: String(tool.reserved)
          onChose: (v) => tool.reserved = Number(v)
        }
      }

      // ENCRYPTED: LUKS2 around the filesystem, the passphrase twice
      Row {
        visible: !!tool.fmt
        x: 118
        spacing: 24
        Controls.Check {
          height: 28
          width: 190
          label: "Encrypt (LUKS2)"
          lit: tool.encrypt
          onToggled: tool.encrypt = !tool.encrypt
        }
        Controls.Check {
          height: 28
          width: 230
          label: "Overwrite with zeros first"
          lit: tool.zero
          onToggled: tool.zero = !tool.zero
        }
      }
      Row {
        visible: tool.encrypt
        spacing: 8
        Text {
          width: 110
          anchors.verticalCenter: parent.verticalCenter
          text: "Passphrase"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        BulkField { id: passA; width: 200; masked: true; ghost: "Passphrase"; onAccepted: passB.claim() }
        BulkField { id: passB; width: 200; masked: true; ghost: "Again"; onAccepted: tool.go() }
      }
      Text {
        textFormat: Text.PlainText
        visible: tool.encrypt || tool.zero
        x: 118
        width: body.width - 118
        wrapMode: Text.WordWrap
        text: [tool.encrypt ? (passB.text !== "" && passA.text !== passB.text ? "The two do not match."
                 : "Only Linux opens it, and only with this passphrase — lose it and the data is gone.") : "",
               tool.zero ? "Zeros over every byte, once: slow, and what was there cannot be read back." : ""]
          .filter((x) => x).join(" ")
        color: tool.encrypt && passB.text !== "" && passA.text !== passB.text ? Zenon.red : Zenon.accentSoft
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }

      Row {
        visible: !!tool.fmt
        x: 118
        spacing: 24
        Controls.Check {
          height: 28
          width: 150
          visible: tool.target === "ntfs"
          label: "Quick format"
          lit: tool.quick
          onToggled: tool.quick = !tool.quick
        }
        Controls.Check {
          height: 28
          width: 170
          label: "Mount when done"
          lit: tool.mountAfter
          onToggled: tool.mountAfter = !tool.mountAfter
        }
      }
    }

    // ── THE RUN ────────────────────────────────────────────────────
    Rectangle {
      visible: tool.running || tool.log.length > 0
      width: parent.width
      height: Math.min(200, Math.max(60, logView.contentHeight + 16))
      radius: Zenon.windowRadius
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
          color: modelData.indexOf("$ ") === 0 ? Zenon.cyan : Zenon.accentSoft
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      ElasticScroll { anchors.fill: logView; view: logView }
      ScrollRail { target: logView; anchors.right: parent.right; anchors.top: logView.top; anchors.bottom: logView.bottom }
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
        text: tool.running ? (tool.mode === "format" ? "Formatting…" : "Running " + (tool.can ? tool.can.tool : "") + "…")
          : (tool.verdict ? tool.verdict.line : "")
        color: tool.running ? Zenon.accentSoft : (tool.verdict && tool.verdict.ok ? Zenon.green : Zenon.red)
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
    }
  }

  // ── ANSWERS, bottom right, Close left of the verb ─────────────────────
  Row {
    anchors.right: parent.right
    anchors.rightMargin: tool.heading !== "" ? tool.pad : 14
    anchors.bottom: parent.bottom
    anchors.bottomMargin: tool.heading !== "" ? tool.pad : 14
    spacing: 8
    DialogButton {
      label: tool.done ? "Close" : "Cancel"
      ink: Zenon.accentMuted
      ready: !tool.running
      onClicked: if (!tool.running) tool.closed()
    }
    DialogButton {
      visible: tool.mode === "repair" ? !!tool.can : true
      label: tool.repairNext ? "Repair" : tool.done ? "Again" : (tool.mode === "format" ? "Format…"
             : (tool.action === "repair" ? "Repair" : "Check"))
      ink: tool.repairNext ? Zenon.yellow : tool.done ? Zenon.cyan
        : (tool.mode === "format" ? Zenon.red : (tool.action === "repair" ? Zenon.yellow : Zenon.cyan))
      primary: true
      ready: !tool.running && (tool.mode !== "format" || tool.passOk)
      onClicked: tool.go()
    }
  }
}
