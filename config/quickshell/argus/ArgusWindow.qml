// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ARGUS' EDITOR — a recording, cut and kept. The video (morpheus/VideoClip,
// picasso's player) over a filmstrip with the kept part between two yellow
// handles; on the right, what to keep it as:
//
//   MP4    copied as it is (instant; the cut lands on the nearest keyframe),
//          or Exact (re-encoded, to the frame)
//   GIF    its width and frame rate, looping or once
//   WebM   VP9, for the web
//
// Save puts it beside the original ("…-cut.mp4"); Save as… asks terminus'
// picker. Done, howler says so with the same card a recording gets.
//
//   space  play, pause (inside the cut)    i  o   in, out at the playhead
//   ← →    a second ( shift: a tenth )     [  ]   to the in, to the out
//   1 2 3  MP4 · GIF · WebM                m      mute
//   ctrl s save    ctrl shift s  save as…  esc    stops a save, or a crop

import QtQuick
import Quickshell
import Quickshell.Io
import QtMultimedia
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "../picasso" as Pic
import "argus.js" as A

FloatingWindow {
  id: aw
  title: "argus"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1240
  implicitHeight: 800
  minimumSize: Qt.size(900, 560)

  property var mgr: null

  onVisibleChanged: if (!aw.visible) Qt.callLater(() => { stopSave(); if (aw.mgr) aw.mgr.retire(aw); aw.destroy(); })
  onClosed: aw.visible = false

  readonly property int headH: 60
  readonly property int sideW: 300

  // ── THE CLIP ───────────────────────────────────────────────────────────
  property string path: ""
  readonly property string name: aw.path.replace(/.*\//, "")
  property real inMs: 0
  property real outMs: 0
  readonly property real dur: player.duration
  readonly property real lenMs: Math.max(0, aw.outMs - aw.inMs)
  property bool muted: false
  property var frames: []
  property string facts: ""

  function load(p) {
    stopSave();
    aw.path = p;
    aw.inMs = 0;
    aw.outMs = 0;
    aw.frames = [];
    aw.facts = "";
    aw.savedTo = "";
    aw.crop = null;
    aw.cropping = false;
    aw.probeW = 0;
    aw.probeH = 0;
    // the same file again: its length does not change, so the cut and the
    // strip would wait on onDurationChanged for good (0→0, no frames;
    // audit 2026-10-28d)
    const again = String(player.source) === Strings.fileUrl(p) && player.duration > 0;
    player.source = Strings.fileUrl(p);
    if (again) { aw.outMs = player.duration; aw.makeStrip(); }
    factsProc.command = ["ffprobe", "-v", "error", "-select_streams", "v:0",
      "-show_entries", "stream=width,height,r_frame_rate:format=size,duration", "-of", "json", p];
    factsProc.running = true;
  }
  // the length arrives with the media: the cut starts as all of it
  Connections {
    target: player
    function onDurationChanged() {
      if (player.duration > 0 && aw.outMs <= 0) {
        aw.outMs = player.duration;
        aw.makeStrip();
      }
    }
  }
  function setIn(ms) { const r = A.clampRange(ms, aw.outMs, aw.dur, "in"); aw.inMs = r.inMs; aw.outMs = r.outMs; }
  function setOut(ms) { const r = A.clampRange(aw.inMs, ms, aw.dur, "out"); aw.inMs = r.inMs; aw.outMs = r.outMs; }

  // playing stays inside the cut: from its start if outside it, back to its
  // start at its end
  function toggle() {
    if (!player.going && (player.position < aw.inMs || player.position >= aw.outMs - 50)) player.seekMs(aw.inMs);
    player.toggle();
  }
  Timer {
    interval: 30
    repeat: true
    running: player.going
    onTriggered: if (player.position >= aw.outMs) { player.seekMs(aw.inMs); }
  }

  // ── WHAT IT IS ─────────────────────────────────────────────────────────
  Process {
    id: factsProc
    stdout: StdioCollector {
      id: factsOut
      waitForEnd: true
      onStreamFinished: {
        try {
          const j = JSON.parse(factsOut.text);
          const st = (j.streams || [])[0] || {};
          aw.probeW = Number(st.width) || 0;
          aw.probeH = Number(st.height) || 0;
          const fr = String(st.r_frame_rate || "").split("/");
          const fps = fr.length === 2 && Number(fr[1]) > 0 ? Math.round(Number(fr[0]) / Number(fr[1])) : 0;
          const mb = (Number((j.format || {}).size) || 0) / 1048576;
          aw.facts = [st.width && st.height ? st.width + "×" + st.height : "", fps ? fps + " fps" : "",
                      mb ? (mb >= 10 ? Math.round(mb) : mb.toFixed(1)) + " MB" : ""].filter((x) => x).join("  ·  ");
        } catch (e) { aw.facts = ""; }
      }
    }
  }

  // ── THE FILMSTRIP ──────────────────────────────────────────────────────
  // a dozen frames into the cache, under a name of their own per file
  readonly property string stripDir: Paths.cacheDir() + "/quickshell/argus-strip"
  readonly property int stripCount: 14
  function makeStrip() {
    if (aw.path === "" || aw.dur <= 0) return;
    const dir = aw.stripDir + "/" + Qt.md5(aw.path + ":" + aw.dur);
    stripProc.dir = dir;
    // made once per file: kept in the cache and reused while the last frame
    // is there; the directory is $1, the ffmpeg line the rest
    stripProc.command = ["sh", "-c", "d=$1; shift; mkdir -p \"$d\" || exit 1; "
      + "[ -s \"$d/f" + (aw.stripCount < 10 ? "0" : "") + aw.stripCount + ".jpg\" ] && exit 0; "
      + "rm -f \"$d\"/f*.jpg; exec \"$@\"", "sh", dir].concat(A.stripArgs(aw.path, dir, aw.dur, aw.stripCount));
    stripProc.running = true;
  }
  Process {
    id: stripProc
    property string dir: ""
    onExited: {
      const out = [];
      for (let i = 1; i <= aw.stripCount; ++i) out.push("file://" + stripProc.dir + "/f" + (i < 10 ? "0" : "") + i + ".jpg");
      aw.frames = out;
    }
  }

  // ── SAVING ─────────────────────────────────────────────────────────────
  readonly property var opts: aw.mgr ? aw.mgr.settings : A.defaults()
  property bool saving: false
  property real progress: 0
  property string savingTo: ""
  property string savedTo: ""
  function say(t, bad) { saidBox.say(t, bad); }

  // ── THE CROP (user, 2026-10-21: "so many memes on the fly") ─────────
  // picasso's crop box over the picture; `crop` in the video's pixels, null
  // for all of it. While `cropping` the box takes the drags; after, the cut
  // is drawn as a frame with the rest dimmed, and the save crops to it.
  property bool cropping: false
  property var crop: null
  property string cropRatio: "free"
  // the frame's size as the player draws it, else ffprobe's (known before
  // a frame has been shown)
  property real probeW: 0
  property real probeH: 0
  readonly property real vw: player.vw > 0 ? player.vw : aw.probeW
  readonly property real vh: player.vh > 0 ? player.vh : aw.probeH
  readonly property var cropNow: A.cropOf(aw.crop, aw.vw, aw.vh)
  // the largest box of the ratio, centered (or the box as it is, free)
  function ratioBox(id) {
    const v = A.ratioValue(id);
    if (!(v > 0)) return aw.crop || { x: 0, y: 0, w: aw.vw, h: aw.vh };
    let w = aw.vw, h = w / v;
    if (h > aw.vh) { h = aw.vh; w = h * v; }
    return { x: Math.round((aw.vw - w) / 2), y: Math.round((aw.vh - h) / 2), w: Math.round(w), h: Math.round(h) };
  }
  function cropWith(id) {
    if (aw.vw <= 0) return;
    if (id === "off") { aw.crop = null; aw.cropping = false; return; }
    aw.cropRatio = id;
    aw.crop = aw.ratioBox(id);
    aw.cropping = true;
  }
  function toggleCrop() {
    if (aw.vw <= 0) return;
    if (aw.cropping) { aw.cropping = false; return; }
    if (!aw.crop) aw.crop = aw.ratioBox(aw.cropRatio);
    aw.cropping = true;
  }

  // `fresh`: `to` is not the name the picker showed, so not one you agreed to replace
  function save(to, fresh) {
    if (aw.saving || aw.path === "" || aw.dur <= 0) return;
    aw.cropping = false;
    const out = to || "";
    aw.savingTo = out;
    aw.progress = 0;
    aw.saving = true;
    // beside the original, or a name the picker never asked about (see
    // saveAs): under the first one not taken (asked of the file system,
    // which the pure half cannot)
    const free = out === "" ? aw.candidates() : fresh ? A.variants(out) : null;
    if (free) {
      nameProc.command = ["sh", "-c", "for p in \"$@\"; do [ -e \"$p\" ] || { printf '%s' \"$p\"; exit 0; }; done",
        "sh"].concat(free);
      nameProc.running = true;
      return;
    }
    aw.runSave(out);
  }
  function candidates() {
    const first = A.outPath(aw.path, aw.opts.format);
    const out = [first];
    for (let n = 2; n < 60; ++n) out.push(first.replace(/(-cut)(\.[^.]+)$/, "$1-" + n + "$2"));
    return out;
  }
  Process {
    id: nameProc
    stdout: StdioCollector {
      id: nameOut
      waitForEnd: true
      onStreamFinished: {
        const p = nameOut.text.trim();
        if (p === "") { aw.saving = false; aw.say(aw.savingTo === "" ? "No free name beside the original — use Save as…" : "No free name for it — pick another in Save as…", true); return; }
        aw.runSave(p);
      }
    }
  }
  function runSave(out) {
    aw.savingTo = out;
    const o = Object.assign({}, aw.opts, { inMs: aw.inMs, outMs: aw.outMs, crop: aw.cropNow });
    saveProc.lenMs = aw.lenMs;
    saveProc.command = A.ffmpegArgs(aw.path, out, o);
    saveProc.running = true;
  }
  function saveAs() {
    if (aw.saving || !aw.mgr || !aw.mgr.fileManager) return;
    const suggested = A.outPath(aw.path, aw.opts.format).replace(/.*\//, "");
    aw.mgr.fileManager.choose(false, A.dirOf(aw.path), (paths) => {
      if (!paths || paths.length === 0) return;
      // the picker asked about the name typed; a changed extension is a
      // different file, which it did not
      const want = A.withExt(paths[0], aw.opts.format);
      aw.save(want, want !== paths[0]);
    }, suggested);
  }
  // any video, from anywhere — not only the captures directory
  function openAsk() {
    if (aw.saving || !aw.mgr || !aw.mgr.fileManager) return;
    aw.mgr.fileManager.choose(false, aw.path !== "" ? A.dirOf(aw.path) : "", (paths) => {
      if (paths && paths.length > 0) aw.load(paths[0]);
    });
  }
  function stopSave() {
    if (saveProc.running) { saveProc.stopped = true; saveProc.signal(15); }
  }
  Process {
    id: saveProc
    property real lenMs: 1
    property bool stopped: false
    property string tail: ""
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => { if (/^out_time_(us|ms)=/.test(line)) aw.progress = A.progressOf(line, saveProc.lenMs); }
    }
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: (line) => { saveProc.tail = line; }
    }
    onExited: (code) => {
      aw.saving = false;
      if (saveProc.stopped) {
        saveProc.stopped = false;
        Quickshell.execDetached(["rm", "-f", aw.savingTo]);
        aw.say("Stopped");
        return;
      }
      if (code !== 0) { aw.say("Could not save: " + (saveProc.tail || "ffmpeg failed"), true); return; }
      aw.savedTo = aw.savingTo;
      aw.say("Saved " + aw.savingTo.replace(/.*\//, ""));
      aw.announce(aw.savingTo);
    }
  }
  // howler's capture card, as a recording gets: a frame of it, its file
  function announce(file) {
    const gif = /\.gif$/i.test(file);
    Quickshell.execDetached(["sh", "-c",
      "f=$1; t=\"${XDG_RUNTIME_DIR:-/tmp}/howler-capture-$(basename \"$f\").png\"; rm -f \"$t\"; "
      + "ffmpeg -nostdin -loglevel quiet -y -i \"$f\" -frames:v 1 \"$t\"; "
      + "if [ -s \"$t\" ]; then notify-send -a argus -i \"$t\" -h string:x-howler-capture:" + (gif ? "shot" : "video")
      + " -h \"string:x-howler-file:$f\" -h \"string:x-howler-picture:$t\" \"\u{F0190} Cut saved\" \"$f\"; "
      + "else notify-send -a argus \"\u{F0190} Cut saved\" \"$f\"; fi", "sh", file]);
  }

  // ── KEYS ───────────────────────────────────────────────────────────────
  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
      e.accepted = true;
      // never the window (user, 2026-10-25: a stray esc lost the cut being
      // made) — it is closed as any window is
      if (e.key === Qt.Key_Escape) { if (aw.saving) aw.stopSave(); else if (aw.cropping) aw.cropping = false; return; }
      if (e.key === Qt.Key_C && !ctrl) { aw.toggleCrop(); return; }
      if (aw.cropping && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { aw.cropping = false; return; }
      if (ctrl && e.key === Qt.Key_O) { aw.openAsk(); return; }
      if (ctrl && e.key === Qt.Key_S) { if (shift) aw.saveAs(); else aw.save(""); return; }
      if (e.key === Qt.Key_Space) { aw.toggle(); return; }
      if (e.key === Qt.Key_I) { aw.setIn(player.position); return; }
      if (e.key === Qt.Key_O) { aw.setOut(player.position); return; }
      if (e.key === Qt.Key_BracketLeft || e.key === Qt.Key_Home) { player.seekMs(aw.inMs); return; }
      if (e.key === Qt.Key_BracketRight || e.key === Qt.Key_End) { player.seekMs(Math.max(aw.inMs, aw.outMs - 100)); return; }
      if (e.key === Qt.Key_Left) { player.seekBy(shift ? -100 : -1000); return; }
      if (e.key === Qt.Key_Right) { player.seekBy(shift ? 100 : 1000); return; }
      if (e.key === Qt.Key_M) { aw.muted = !aw.muted; return; }
      if (e.key >= Qt.Key_1 && e.key <= Qt.Key_3 && aw.mgr) { aw.mgr.set("format", A.FORMATS[e.key - Qt.Key_1].id); return; }
      e.accepted = false;
    }
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent

    Rectangle { anchors.fill: parent; color: Zenon.layerBg }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      anchors.left: parent.left
      anchors.right: parent.right
      height: aw.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Text {
        id: headGlyph
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F16FF}"
        color: Zenon.yellow
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(20)
      }
      Text {
        textFormat: Text.PlainText
        id: headTitle
        anchors.left: headGlyph.right
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.45)
        elide: Text.ElideMiddle
        text: aw.name !== "" ? aw.name : "Argus"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(18)
      }
      Text {
        anchors.left: headTitle.right
        anchors.leftMargin: 12
        anchors.baseline: headTitle.baseline
        anchors.right: headBtns.left
        anchors.rightMargin: 16
        elide: Text.ElideRight
        text: aw.facts
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Row {
        id: headBtns
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        DialogButton {
          visible: aw.savedTo !== ""
          label: "Show in Terminus"
          onClicked: Quickshell.execDetached(["qs", "ipc", "call", "Terminus", "reveal", aw.savedTo])
        }
        // the cut just saved, out to something else (morpheus/Share)
        DialogButton {
          id: shareBtn
          visible: aw.savedTo !== ""
          label: "Share \u25BE"
          onClicked: {
            const at = shareBtn.mapToItem(shareMenu, 0, shareBtn.height + 4);
            shareMenu.open(at.x, at.y, Share.items([aw.savedTo], false, 1)
              .map((t) => ({ text: t.label, icon: t.glyph, run: t.act })));
          }
        }
        DialogButton {
          label: "Open…"
          ready: !aw.saving && !!aw.mgr && !!aw.mgr.fileManager
          onClicked: aw.openAsk()
        }
        DialogButton {
          label: "Save as…"
          ready: !aw.saving && !!aw.mgr && !!aw.mgr.fileManager && aw.dur > 0
          onClicked: aw.saveAs()
        }
        BusyButton {
          label: "Save"
          ink: Zenon.yellow
          primary: true
          ready: !aw.saving && aw.dur > 0
          busy: aw.saving
          busyText: Math.round(aw.progress * 100) + "%"
          onClicked: aw.save("")
        }
      }
    }

    // ── the picture ──────────────────────────────────────────────────────
    Rectangle {
      id: screen
      anchors.top: head.bottom
      anchors.left: parent.left
      anchors.right: side.left
      anchors.bottom: transport.top
      color: Zenon.ground
      VideoClip {
        id: player
        anchors.fill: parent
        anchors.margins: 16
        autoPlay: false
        muted: aw.muted
        fillMode: VideoOutput.PreserveAspectFit
        onFailed: (msg) => aw.say("This video cannot be played  ·  " + msg, true)
      }
      MouseArea { anchors.fill: parent; onClicked: aw.toggle() }

      // the picture's own rectangle inside the player (fitted, centered)
      Item {
        id: pic
        readonly property real k: aw.vw > 0 ? Math.min(player.width / aw.vw, player.height / aw.vh) : 1
        x: player.x + (player.width - aw.vw * k) / 2
        y: player.y + (player.height - aw.vh * k) / 2
        width: aw.vw * k
        height: aw.vh * k
        visible: aw.vw > 0
      }
      // the crop once set: the rest dimmed, the cut framed
      Item {
        visible: !aw.cropping && !!aw.cropNow
        x: pic.x; y: pic.y; width: pic.width; height: pic.height
        readonly property var c: aw.cropNow || { x: 0, y: 0, w: aw.vw, h: aw.vh }
        readonly property real cx: c.x * pic.k
        readonly property real cy: c.y * pic.k
        readonly property real cw: c.w * pic.k
        readonly property real ch: c.h * pic.k
        Rectangle { width: parent.width; height: parent.cy; color: Zenon.shade(0.55) }
        Rectangle { y: parent.cy + parent.ch; width: parent.width; height: parent.height - y; color: Zenon.shade(0.55) }
        Rectangle { y: parent.cy; width: parent.cx; height: parent.ch; color: Zenon.shade(0.55) }
        Rectangle { x: parent.cx + parent.cw; y: parent.cy; width: parent.width - x; height: parent.ch; color: Zenon.shade(0.55) }
        Rectangle { x: parent.cx; y: parent.cy; width: parent.cw; height: parent.ch; color: "transparent"; border.width: 1; border.color: Zenon.yellow }
      }
      Pic.CropBox {
        x: pic.x; y: pic.y; width: pic.width; height: pic.height
        visible: aw.cropping && aw.vw > 0
        k: pic.k
        r: aw.crop || { x: 0, y: 0, w: aw.vw, h: aw.vh }
        tw: aw.vw
        th: aw.vh
        ratio: A.ratioValue(aw.cropRatio)
        shiftSquare: true
        onDrawn: (r) => aw.crop = r
        onTouched: keys.forceActiveFocus()
        onBodyDoubleClicked: aw.cropping = false
      }
      Text {
        anchors.centerIn: parent
        visible: aw.dur > 0 && !player.going && !aw.cropping
        text: ""
        color: Zenon.white
        opacity: 0.8
        style: Text.Outline
        styleColor: Zenon.shade(0.6)
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(44)
      }
      EmptyState {
        anchors.centerIn: parent
        visible: aw.path === ""
        text: "No video open — ctrl o opens one, super r records the screen"
      }
    }

    // ── play, the times, mute ────────────────────────────────────────────
    Item {
      id: transport
      anchors.left: parent.left
      anchors.right: side.left
      anchors.bottom: stripBox.top
      height: 44
      Text {
        id: playGlyph
        x: 22
        anchors.verticalCenter: parent.verticalCenter
        text: player.going ? "" : ""
        color: playPress.pressed ? Zenon.cyan : Zenon.white
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(16)
        MouseArea { id: playPress; anchors.fill: parent; anchors.margins: -8; onClicked: aw.toggle() }
      }
      Text {
        anchors.left: playGlyph.right
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: A.stamp(player.position) + "  /  " + A.stamp(aw.dur)
        font.features: { "tnum": 1 }
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Text {
        anchors.centerIn: parent
        text: aw.dur > 0 ? A.stamp(aw.inMs) + "  →  " + A.stamp(aw.outMs) + "   ·   " + A.stamp(aw.lenMs) + " kept" : ""
        font.features: { "tnum": 1 }
        color: Zenon.yellow
        font.family: Zenon.face
        font.weight: 600
        font.pixelSize: Zenon.px(14)
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        text: aw.muted ? "" : ""
        color: aw.muted ? Zenon.red : mutePress.pressed ? Zenon.cyan : Zenon.white
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(15)
        MouseArea { id: mutePress; anchors.fill: parent; anchors.margins: -8; onClicked: aw.muted = !aw.muted }
      }
    }

    // ── the filmstrip ────────────────────────────────────────────────────
    Item {
      id: stripBox
      anchors.left: parent.left
      anchors.right: side.left
      anchors.bottom: foot.top
      height: 104
      ArgusStrip {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 8
        anchors.bottomMargin: 24
        frames: aw.frames
        duration: aw.dur
        inMs: aw.inMs
        outMs: aw.outMs
        position: player.position
        onSeek: (ms) => player.seekMs(ms)
        // the picture follows the end being moved, so you see where it cuts
        onInMoved: (ms) => { aw.setIn(ms); player.seekMs(aw.inMs); }
        onOutMoved: (ms) => { aw.setOut(ms); player.seekMs(Math.max(aw.inMs, aw.outMs - 40)); }
      }
    }

    // ── what to keep it as ───────────────────────────────────────────────
    Item {
      id: side
      anchors.top: head.bottom
      anchors.right: parent.right
      anchors.bottom: foot.top
      width: aw.sideW
      SideGlass { edge: "left" }

      // the settings scroll when the window is too low for them all
      // (user, 2026-10-25: very low screens)
      Flickable {
        id: sideFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: sideCol.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        clip: true
      Column {
        id: sideCol
        x: 20
        y: 20
        width: sideFlick.width - 40
        spacing: 14

        SectionLabel { text: "Keep it as" }
        Row {
          spacing: 6
          Repeater {
            model: A.FORMATS
            delegate: Rectangle {
              required property var modelData
              readonly property bool on: aw.opts.format === modelData.id
              width: (aw.sideW - 40 - 12) / 3
              height: 34
              radius: Zenon.radiusControl
              color: fmtPress.pressed ? Zenon.pressTile(on) : on ? Zenon.alpha(Zenon.yellow, 0.18) : Zenon.wash(0.05)
              border.width: 1
              border.color: on ? Zenon.alpha(Zenon.yellow, 0.6) : Zenon.border
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: modelData.label
                color: parent.on ? Zenon.yellow : Zenon.ink
                font.family: Zenon.face
                font.weight: parent.on ? Zenon.titleWeight : Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              MouseArea { id: fmtPress; anchors.fill: parent; onClicked: if (aw.mgr) aw.mgr.set("format", modelData.id) }
            }
          }
        }

        // MP4
        Ctl.Check {
          visible: aw.opts.format === "mp4"
          label: "Exact cut (re-encode)"
          lit: aw.opts.exact
          onToggled: aw.mgr.set("exact", !aw.opts.exact)
        }
        EmptyState {
          width: parent.width
          horizontalAlignment: Text.AlignLeft
          visible: aw.opts.format === "mp4"
          text: aw.opts.exact ? "To the frame; takes as long as an encode does."
            : "Instant and lossless, but the cut lands on the nearest keyframe — up to a second early."
        }
        Ctl.Check {
          visible: aw.opts.format !== "gif"
          label: "Keep the sound"
          lit: aw.opts.audio
          onToggled: aw.mgr.set("audio", !aw.opts.audio)
        }

        // GIF
        SectionLabel { visible: aw.opts.format === "gif"; text: "Width" }
        Flow {
          visible: aw.opts.format === "gif"
          width: parent.width
          spacing: 6
          Repeater {
            model: A.GIF_WIDTHS
            delegate: Rectangle {
              required property int modelData
              readonly property bool on: aw.opts.gifWidth === modelData
              width: (aw.sideW - 40 - 18) / 4
              height: 30
              radius: Zenon.radiusControl
              color: wPress.pressed ? Zenon.pressTile(on) : on ? Zenon.alpha(Zenon.yellow, 0.18) : Zenon.wash(0.05)
              border.width: 1
              border.color: on ? Zenon.alpha(Zenon.yellow, 0.6) : Zenon.border
              Text {
                anchors.centerIn: parent
                text: modelData === 0 ? "Full" : String(modelData)
                color: parent.on ? Zenon.yellow : Zenon.ink
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
              MouseArea { id: wPress; anchors.fill: parent; onClicked: aw.mgr.set("gifWidth", modelData) }
            }
          }
        }
        SectionLabel { visible: aw.opts.format === "gif"; text: "Frames a second" }
        Flow {
          visible: aw.opts.format === "gif"
          width: parent.width
          spacing: 6
          Repeater {
            model: A.GIF_FPS
            delegate: Rectangle {
              required property int modelData
              readonly property bool on: aw.opts.gifFps === modelData
              width: (aw.sideW - 40 - 18) / 4
              height: 30
              radius: Zenon.radiusControl
              color: rPress.pressed ? Zenon.pressTile(on) : on ? Zenon.alpha(Zenon.yellow, 0.18) : Zenon.wash(0.05)
              border.width: 1
              border.color: on ? Zenon.alpha(Zenon.yellow, 0.6) : Zenon.border
              Text {
                anchors.centerIn: parent
                text: String(modelData)
                color: parent.on ? Zenon.yellow : Zenon.ink
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
              MouseArea { id: rPress; anchors.fill: parent; onClicked: aw.mgr.set("gifFps", modelData) }
            }
          }
        }
        Ctl.Check {
          visible: aw.opts.format === "gif"
          label: "Loop forever"
          lit: aw.opts.loop
          onToggled: aw.mgr.set("loop", !aw.opts.loop)
        }

        // WebM
        EmptyState {
          width: parent.width
          horizontalAlignment: Text.AlignLeft
          visible: aw.opts.format === "webm"
          text: "VP9 with Opus sound — small, and plays in every browser."
        }

        // ── the crop ──────────────────────────────────────────────────
        SectionLabel { text: "Crop" }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: [{ id: "off", label: "Off" }].concat(A.CROP_RATIOS)
            delegate: Rectangle {
              required property var modelData
              readonly property bool on: modelData.id === "off" ? !aw.crop && !aw.cropping
                : (!!aw.crop || aw.cropping) && aw.cropRatio === modelData.id
              width: (aw.sideW - 40 - 12) / 3
              height: 30
              radius: Zenon.radiusControl
              opacity: aw.vw > 0 ? 1 : Zenon.disabledDim
              color: cropPress.pressed ? Zenon.pressTile(on) : on ? Zenon.alpha(Zenon.yellow, 0.18) : Zenon.wash(0.05)
              border.width: 1
              border.color: on ? Zenon.alpha(Zenon.yellow, 0.6) : Zenon.border
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: modelData.label
                color: parent.on ? Zenon.yellow : Zenon.ink
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
              MouseArea { id: cropPress; anchors.fill: parent; onClicked: aw.cropWith(modelData.id) }
            }
          }
        }
        EmptyState {
          width: parent.width
          horizontalAlignment: Text.AlignLeft
          text: aw.cropping ? "Drag the box or its corners; return or c when it is right"
            : aw.cropNow ? aw.cropNow.w + " × " + aw.cropNow.h + "  ·  c changes it"
              + (aw.opts.format === "mp4" && !aw.opts.exact ? "  ·  cropping re-encodes" : "")
            : "c crops the picture"
        }

        Item { width: 1; height: 6 }
        SectionLabel { text: "Saves as" }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.WrapAnywhere
          text: aw.path === "" ? "—" : A.outPath(aw.path, aw.opts.format).replace(/.*\//, "")
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        EmptyState {
          width: parent.width
          horizontalAlignment: Text.AlignLeft
          text: "beside the original; Save as… puts it anywhere"
        }
      }
      }
      ElasticScroll { anchors.fill: sideFlick; view: sideFlick }
      Scrollbar { flick: sideFlick; anchors.right: parent.right; anchors.top: sideFlick.top; anchors.bottom: sideFlick.bottom }

      // a save under way
      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20
        spacing: 8
        visible: aw.saving
        Text {
          text: aw.savingTo === "" ? "Saving…" : "Saving " + aw.savingTo.replace(/.*\//, "") + "…"
          width: parent.width
          elide: Text.ElideMiddle
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        Rectangle {
          width: parent.width
          height: 6
          radius: 3
          color: Zenon.wash(0.1)
          Rectangle { width: parent.width * aw.progress; height: parent.height; radius: 3; color: Zenon.yellow }
        }
      }
    }

    // ── what was just done, said once ────────────────────────────────────
    Ctl.Said {
      anchors.horizontalCenter: screen.horizontalCenter
      anchors.bottom: transport.top
      anchors.bottomMargin: 18
      id: saidBox
      lasts: 3200
    }

    HintBar {
      id: foot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      rows: aw.saving ? [["esc", "stop saving"]]
        : aw.cropping ? [["drag", "the box"], ["shift", "square"], ["return", "done"], ["esc", "done"]]
        : [["space", "play"], ["i o", "in, out"], ["c", "crop"], ["← →", "seek"], ["[ ]", "to in, out"], ["1 2 3", "format"],
           ["ctrl s", "save"], ["ctrl shift s", "save as"]]
    }
  }

  PopMenu { id: shareMenu; anchors.fill: parent; window: aw; onClosed: keys.forceActiveFocus() }
}
