// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES' PRINTERS PAGE — the printers CUPS has, what they are doing and
// the jobs waiting; finding one on the network or USB and adding it
// driverless (IPP Everywhere); and the scanners SANE sees, a scan saved to
// ~/Pictures/Scans and opened. Where CUPS or SANE is missing, the button
// that sets it up through Ceres.
//
// Unlike the other pages its state is its own (bin/hermes-print, asked
// every few seconds while the page is on screen and never otherwise):
// nothing outside this page — not the bar, not the quick panel — needs it.
//
//   ↑ ↓  a printer      delete  remove it (asked twice)

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../terminus"
import "../ceres"
import "hermes.js" as H
import "../morpheus/helpers.js" as Helpers

Column {
  id: page

  property var win: null
  property int sel: 0
  readonly property bool shown: page.visible && !!page.win && page.win.visible

  readonly property string helper: Quickshell.shellDir + "/hermes/bin/hermes-print"
  readonly property bool fake: Hermes.fake !== ""

  property var info: H.emptyPrint()
  readonly property var rows: page.info.printers
  readonly property int count: page.rows.length
  readonly property var picked: page.rows[Math.min(page.sel, page.rows.length - 1)] || null

  property var found: []
  property bool finding: false
  property bool foundOnce: false
  property var scanners: []
  property bool lookingScan: false
  property bool scannedOnce: false
  property int scanSel: 0
  property string scanFmt: "png"
  property string scanDpi: "300"
  property string scanMode: "Color"
  property bool scanning: false
  // the printer asked about once, waiting for the second ask (Remove)
  property string removeAsked: ""
  Timer { id: removeForget; interval: 3500; onTriggered: page.removeAsked = "" }

  spacing: 16

  // ── ASKING ─────────────────────────────────────────────────────────────
  function look() {
    if (page.fake) { page.info = H.parsePrint(JSON.stringify(page.fakeInfo)); return; }
    if (!statusProc.running) statusProc.running = true;
  }
  onShownChanged: if (page.shown) page.look()
  Timer { interval: 4000; repeat: true; running: page.shown && !page.fake; onTriggered: page.look() }
  Process {
    id: statusProc
    command: [page.helper, "status"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
      onStreamFinished: {
        const p = H.parsePrint(statusOut.text);
        // an empty answer (killed by a reload) keeps the last one
        if (p.known) page.info = p;
      }
    }
  }
  // set up through Ceres: asked again once it is done
  Connections {
    target: Hermes
    function onSetupKindChanged() { if (Hermes.setupKind === "") page.look(); }
  }

  // ── DOING ──────────────────────────────────────────────────────────────
  // One at a time. CUPS refusing for want of an administrator (a user not
  // in its SystemGroup) is asked again as root through Ceres' password card.
  function act(args, words, after) {
    if (actProc.running) { Hermes.tell("Still busy with the last one", true); return; }
    if (page.fake) { page.fakeAct(args); Hermes.tell(words); if (after) after(true); return; }
    actProc.args = args;
    actProc.words = words;
    actProc.after = after || null;
    actProc.command = [page.helper].concat(args);
    actProc.running = true;
  }
  Process {
    id: actProc
    property var args: []
    property string words: ""
    property var after: null
    stdout: StdioCollector {
      id: actOut
      waitForEnd: true
      onStreamFinished: {
        const r = H.parseAct(actOut.text);
        const after = actProc.after;
        if (r.ok) Hermes.tell(actProc.words);
        else if (r.admin) page.asRoot(actProc.args, actProc.words, after);
        else Hermes.tell("Not done: " + (r.error || "CUPS said no"), true);
        if (after && !r.admin) after(r.ok);
        page.look();
      }
    }
  }
  function asRoot(args, words, after) {
    const ok = Ceres.install([], words.charAt(0).toLowerCase() + words.slice(1) + " (as root)", (done) => {
      Hermes.tell(done ? words : "Not done", !done);
      if (after) after(done);
      page.look();
    }, [["@sudo", page.helper].concat(args)]);
    if (!ok) Hermes.tell("Ceres is busy — try again once it is done", true);
  }

  function testPage(p) { if (p) page.act(["test", p.name], "Test page sent to " + p.info); }
  function makeDefault(p) { if (p && !p.default) page.act(["default", p.name], p.info + " is the default"); }
  function pauseResume(p) {
    if (!p) return;
    if (p.state === "stopped") page.act(["resume", p.name], p.info + " resumed");
    else page.act(["pause", p.name], p.info + " paused");
  }
  function remove(p) {
    if (!p) return;
    if (page.removeAsked !== p.name) {
      page.removeAsked = p.name;
      removeForget.restart();
      Hermes.tell("Remove " + p.info + "? Again to remove it");
      return;
    }
    page.removeAsked = "";
    page.act(["remove", p.name], "Removed " + p.info, () => { page.sel = 0; });
  }
  function cancelJob(j) { if (j) page.act(["cancel", j.id], "Cancelled " + j.id); }
  function addPrinter(d) { if (d) page.act(["add", d.uri, d.queue || d.name], "Added " + d.name); }

  function find() {
    if (page.finding) return;
    page.finding = true;
    if (page.fake) { page.fakeLater("find"); return; }
    findProc.running = true;
  }
  Process {
    id: findProc
    command: [page.helper, "nearby"]
    stdout: StdioCollector {
      id: findOut
      waitForEnd: true
      onStreamFinished: {
        const r = H.parseDevices(findOut.text);
        page.found = r.devices;
        page.finding = false;
        page.foundOnce = true;
        if (!r.ok && r.error) Hermes.tell("Could not look: " + r.error, true);
      }
    }
  }

  function lookScanners() {
    if (page.lookingScan) return;
    page.lookingScan = true;
    if (page.fake) { page.fakeLater("scanners"); return; }
    scanListProc.running = true;
  }
  Process {
    id: scanListProc
    command: [page.helper, "scanners"]
    stdout: StdioCollector {
      id: scanListOut
      waitForEnd: true
      onStreamFinished: {
        const r = H.parseDevices(scanListOut.text);
        page.scanners = r.devices;
        page.scanSel = 0;
        page.lookingScan = false;
        page.scannedOnce = true;
      }
    }
  }
  readonly property string scanDir: (Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")) + "/Scans"
  function scan() {
    const s = page.scanners[page.scanSel];
    if (!s || page.scanning) return;
    page.scanning = true;
    const path = page.scanDir + "/" + H.scanFileName(new Date(), page.scanFmt);
    if (page.fake) { page.fakeLater("scan"); return; }
    scanProc.path = path;
    scanProc.command = [page.helper, "scan", s.id, path, page.scanFmt, page.scanDpi, page.scanMode];
    scanProc.running = true;
  }
  Process {
    id: scanProc
    property string path: ""
    stdout: StdioCollector {
      id: scanOut
      waitForEnd: true
      onStreamFinished: {
        const r = H.parseAct(scanOut.text);
        page.scanning = false;
        if (!r.ok) { Hermes.tell("The scan did not finish: " + (r.error || "scanimage failed"), true); return; }
        Hermes.tell("Scanned — " + scanProc.path.replace(/.*\//, ""));
        // picasso for a picture, minerva for a PDF: the desktop's defaults
        Quickshell.execDetached(["xdg-open", scanProc.path]);
      }
    }
  }

  // ── PRETENDING (HERMES_FAKE) ───────────────────────────────────────────
  property var fakeInfo: ({
    cups: { installed: true, running: true }, sane: { installed: true, airscan: true },
    printers: [
      { name: "Brother-HL-L2350DW", info: "Brother HL-L2350DW", model: "Brother HL-L2350DW series, driverless", uri: "ipp://brother.local/ipp/print",
        state: "printing", reasons: ["toner-low-report"], default: true, jobs: 1 },
      { name: "Office-Laser", info: "Office laser", model: "HP LaserJet, driverless", uri: "ipp://10.0.0.9/ipp/print",
        state: "idle", reasons: [], default: false, jobs: 0 }
    ],
    jobs: [{ id: "Brother-HL-L2350DW-41", printer: "Brother-HL-L2350DW", size: 48211, user: "you" }]
  })
  function fakeAct(args) {
    const fi = JSON.parse(JSON.stringify(page.fakeInfo));
    const at = fi.printers.findIndex((p) => p.name === args[1]);
    if (args[0] === "remove" && at >= 0) fi.printers.splice(at, 1);
    else if (args[0] === "default") fi.printers.forEach((p) => p.default = p.name === args[1]);
    else if (args[0] === "pause" && at >= 0) fi.printers[at].state = "stopped";
    else if (args[0] === "resume" && at >= 0) fi.printers[at].state = "idle";
    else if (args[0] === "cancel") fi.jobs = fi.jobs.filter((j) => j.id !== args[1]);
    else if (args[0] === "add") fi.printers.push({ name: args[2], info: args[2].replace(/-/g, " "), uri: args[1], state: "idle", reasons: [], jobs: 0 });
    page.fakeInfo = fi;
    page.look();
  }
  // each pretend answer after a moment, as the real ones take; several at
  // once each land (one timer per ask)
  Component { id: fakeTimer; Timer { interval: 900; running: true } }
  function fakeLater(what) {
    const t = fakeTimer.createObject(page);
    t.triggered.connect(() => { page.fakeAnswer(what); t.destroy(); });
  }
  function fakeAnswer(what) {
    {
      if (what === "find") {
        page.found = [{ uri: "dnssd://Canon%20TS5300._ipp._tcp.local/", name: "Canon TS5300", queue: "Canon-TS5300", kind: "network" },
                      { uri: "ipp://10.0.0.9/ipp/print", name: "Office laser", queue: "Office-Laser", kind: "network" }];
        page.finding = false; page.foundOnce = true;
      } else if (what === "scanners") {
        page.scanners = [{ id: "airscan:e0:Canon TS5300", name: "eSCL Canon TS5300 ip=10.0.0.12" }];
        page.lookingScan = false; page.scannedOnce = true;
      } else { page.scanning = false; Hermes.tell("Scanned (pretend)"); }
    }
  }

  // ── WHAT IS MISSING ────────────────────────────────────────────────────
  HermesSetup {
    width: parent.width
    topPadding: 40
    visible: page.info.known && !page.info.cups.installed
    glyph: H.G.printer
    title: "Printing is not set up"
    body: "CUPS, Linux's printing service, is not installed. Control Hub installs it through Ceres with what finds printers on the network and over USB, and starts it."
    action: "Set up printing"
    busy: Hermes.setupKind === "printing"
    onGo: Hermes.setup("printing")
  }
  HermesSetup {
    width: parent.width
    topPadding: 40
    visible: page.info.known && page.info.cups.installed && !page.info.cups.running
    glyph: H.G.printerOff
    title: "Printing is stopped"
    body: "CUPS is installed but not running. Starting it also starts it at every boot."
    action: "Start printing"
    busy: Hermes.setupKind === "printingStart"
    onGo: Hermes.setup("printingStart")
  }

  // ── THE PRINTERS ───────────────────────────────────────────────────────
  HermesCard {
    visible: page.info.cups.running
    glyph: H.G.printer
    glyphInk: page.rows.length > 0 ? Zenon.cyan : Zenon.accentMuted
    title: "Printers"
    note: page.rows.length > 0 && page.rows[0].default ? "Default · " + page.rows[0].info : ""
    EmptyState {
      width: parent.width
      height: 64
      verticalAlignment: Text.AlignVCenter
      visible: page.rows.length === 0
      text: "No printers yet — Find printers looks on the network and USB"
    }
    Item {
      width: parent.width
      height: prCol.height + (page.rows.length > 0 ? 8 : 0)
      visible: page.rows.length > 0
      CursorBand { parent: prCol.parent; repeater: prRep; index: page.sel; shown: page.win ? page.win.listFocus : true }
      Column {
        id: prCol
        width: parent.width
        Repeater {
          id: prRep
          model: page.rows.length
          delegate: Item {
            id: prRow
            required property int index
            readonly property var p: page.rows[index] || ({})
            width: prCol.width
            height: 46
            Text {
              id: prGlyph
              x: 18
              anchors.verticalCenter: parent.verticalCenter
              width: 24
              text: H.printerGlyph(prRow.p)
              color: H.reasonWords(prRow.p.reasons) !== "" ? Zenon.yellow : prRow.p.state === "printing" ? Zenon.cyan : Zenon.accentMuted
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(17)
            }
            Column {
              anchors.left: prGlyph.right
              anchors.leftMargin: 10
              anchors.right: prState.left
              anchors.rightMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              Text {
                width: parent.width
                elide: Text.ElideRight
                text: prRow.p.info + (prRow.p.default ? "  ·  default" : "")
                color: prRow.index === page.sel ? Zenon.ink : Zenon.white
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: Zenon.px(15)
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                visible: text !== ""
                text: prRow.p.model
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
              }
            }
            Text {
              id: prState
              anchors.right: parent.right
              anchors.rightMargin: 18
              anchors.verticalCenter: parent.verticalCenter
              text: H.printerWords(prRow.p)
              color: prRow.p.state === "printing" ? Zenon.cyan : H.reasonWords(prRow.p.reasons) !== "" ? Zenon.yellow : Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
            FlashOver { flash: page.win ? page.win.rowFlash : null; index: prRow.index }
            MouseArea {
              anchors.fill: parent
              onClicked: { page.sel = prRow.index; if (page.win) page.win.listFocus = true; }
            }
          }
        }
      }
    }
    // what can be done to the chosen one
    Row {
      x: 18
      visible: !!page.picked
      spacing: 8
      height: 44
      DialogButton { anchors.verticalCenter: parent.verticalCenter; label: "Print a test page"; onClicked: page.testPage(page.picked) }
      DialogButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: !!page.picked && !page.picked.default
        label: "Make default"
        onClicked: page.makeDefault(page.picked)
      }
      DialogButton {
        anchors.verticalCenter: parent.verticalCenter
        label: page.picked && page.picked.state === "stopped" ? "Resume" : "Pause"
        onClicked: page.pauseResume(page.picked)
      }
      DialogButton {
        anchors.verticalCenter: parent.verticalCenter
        label: page.picked && page.removeAsked === page.picked.name ? "Remove — sure?" : "Remove"
        onClicked: page.remove(page.picked)
      }
    }
  }

  // ── THE JOBS ───────────────────────────────────────────────────────────
  HermesCard {
    visible: page.info.cups.running && page.info.jobs.length > 0
    glyph: H.G.printer
    glyphInk: Zenon.cyan
    title: "Waiting to print"
    note: page.info.jobs.length + (page.info.jobs.length === 1 ? " job" : " jobs")
    Column {
      width: parent.width
      Repeater {
        model: page.info.jobs.length
        delegate: Item {
          id: jobRow
          required property int index
          readonly property var j: page.info.jobs[index] || ({})
          readonly property var on: page.rows.find((p) => p.name === jobRow.j.printer) || null
          width: parent ? parent.width : 0
          height: 40
          Text {
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 160
            elide: Text.ElideRight
            text: (jobRow.on ? jobRow.on.info : jobRow.j.printer) + "  ·  " + Helpers.sizeFormat(jobRow.j.size)
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
          DialogButton {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            label: "Cancel"
            onClicked: page.cancelJob(jobRow.j)
          }
        }
      }
    }
  }

  // ── FINDING ONE ────────────────────────────────────────────────────────
  HermesCard {
    visible: page.info.cups.running
    glyph: H.G.printerSearch
    glyphInk: page.finding ? Zenon.cyan : Zenon.accentMuted
    title: "Add a printer"
    note: page.foundOnce && !page.finding ? page.found.length + " found" : ""
    trailing: [
      BusyButton {
        label: page.foundOnce ? "Look again" : "Find printers"
        busy: page.finding
        busyText: "Looking…"
        onClicked: page.find()
      }
    ]
    EmptyState {
      width: parent.width
      height: 54
      verticalAlignment: Text.AlignVCenter
      visible: !page.finding && page.found.length === 0
      text: page.foundOnce ? "Nothing answered — is the printer on, and on this network?"
        : "Printers on the network and on USB, set up without a driver"
    }
    Column {
      width: parent.width
      visible: page.found.length > 0
      Repeater {
        model: page.found.length
        delegate: Item {
          id: devRow
          required property int index
          readonly property var d: page.found[index] || ({})
          readonly property bool added: H.alreadyAdded(devRow.d, page.rows)
          width: parent ? parent.width : 0
          height: 42
          Text {
            id: devGlyph
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            text: devRow.d.kind === "usb" ? "\u{F0553}" : H.G.network
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(16)
          }
          Text {
            anchors.left: devGlyph.right
            anchors.leftMargin: 10
            anchors.right: devAdd.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: devRow.d.name
            color: Zenon.white
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: Zenon.px(15)
          }
          DialogButton {
            id: devAdd
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            label: devRow.added ? "Added" : "Add"
            ready: !devRow.added
            onClicked: page.addPrinter(devRow.d)
          }
        }
      }
    }
  }

  // ── SCANNERS ───────────────────────────────────────────────────────────
  HermesCard {
    visible: page.info.known
    glyph: H.G.scanner
    glyphInk: page.scanners.length > 0 ? Zenon.cyan : Zenon.accentMuted
    title: "Scanners"
    note: page.scannedOnce && !page.lookingScan ? page.scanners.length + " found" : ""
    trailing: [
      BusyButton {
        visible: page.info.sane.installed
        label: page.scannedOnce ? "Look again" : "Find scanners"
        busy: page.lookingScan
        busyText: "Looking…"
        onClicked: page.lookScanners()
      }
    ]
    HermesSetup {
      width: parent.width
      topPadding: 6
      bottomPadding: 22
      visible: !page.info.sane.installed
      glyph: H.G.scanner
      title: "Scanning is not set up"
      body: "SANE, with its driverless backend for network and USB scanners. Control Hub installs it through Ceres."
      action: "Set up scanning"
      busy: Hermes.setupKind === "scanning"
      onGo: Hermes.setup("scanning")
    }
    EmptyState {
      width: parent.width
      height: 54
      verticalAlignment: Text.AlignVCenter
      visible: page.info.sane.installed && !page.lookingScan && page.scanners.length === 0
      text: page.scannedOnce ? "No scanner answered" : "Looking takes a few seconds, so it waits to be asked"
    }
    Column {
      width: parent.width
      visible: page.scanners.length > 0
      spacing: 4
      Repeater {
        model: page.scanners.length
        delegate: Item {
          id: scRow
          required property int index
          readonly property var s: page.scanners[index] || ({})
          width: parent ? parent.width : 0
          height: 40
          Text {
            id: scGlyph
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            // the one scans go to: a tick, as the chosen one in a menu wears it
            text: scRow.index === page.scanSel ? H.G.check : ""
            color: scRow.index === page.scanSel ? Zenon.cyan : Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(16)
          }
          Text {
            anchors.left: scGlyph.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: scRow.s.name
            color: scRow.index === page.scanSel ? Zenon.ink : Zenon.white
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: Zenon.px(15)
          }
          MouseArea { anchors.fill: parent; onClicked: page.scanSel = scRow.index }
        }
      }
      // how, and the button
      Flow {
        x: 18
        width: parent.width - 36
        spacing: 10
        Segments {
          options: [["png", "Picture"], ["pdf", "PDF"]]
          current: page.scanFmt
          onChose: (v) => page.scanFmt = v
        }
        Segments {
          options: [["150", "150 dpi"], ["300", "300 dpi"], ["600", "600 dpi"]]
          current: page.scanDpi
          onChose: (v) => page.scanDpi = v
        }
        Segments {
          options: [["Color", "Color"], ["Gray", "Gray"]]
          current: page.scanMode
          onChose: (v) => page.scanMode = v
        }
        BusyButton {
          label: "Scan"
          primary: true
          busy: page.scanning
          busyText: "Scanning…"
          onClicked: page.scan()
        }
      }
      EmptyState {
        width: parent.width
        height: 40
        verticalAlignment: Text.AlignVCenter
        text: "Saved to ~/Pictures/Scans, then opened"
      }
    }
  }
}
