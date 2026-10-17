// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The daemon half: one background layer surface per monitor. There is no
// separate background process to talk to — this shell IS the background daemon,
// so setting one is an assignment, not an IPC call to something else.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../morpheus"
import "../oracle"
import "picasso.js" as Art

Variants {
  // one surface per monitor, rebuilt by Quickshell when monitors come and go
  model: Quickshell.screens

  PanelWindow {
    id: surface
    required property var modelData

    screen: surface.modelData
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "picasso"
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    // the floor under the image: with no background set this is what you see,
    // and it matches hyprland's own background_color
    color: "black"
    // A fullscreen surface that took input would swallow every click on the
    // desktop. It is scenery; it must never be a target.
    mask: Region {}

    readonly property string want:
      surface.modelData ? Picasso.wallpaperFor(surface.modelData.name) : ""
    readonly property string screenName: surface.modelData ? surface.modelData.name : ""

    // one output's background lends the glass its tint — see Zenon.wallAccent
    // — the one Follow Background follows (Oracle.followMonitor, the first
    // by default). One output speaks for all: a pill tinted differently per
    // monitor would be two shells.
    Binding {
      when: !!Oracle.pickScreen(Oracle.followMonitor)
        && surface.screenName === Oracle.pickScreen(Oracle.followMonitor).name
      target: Zenon
      property: "wallAccent"
      value: Picasso.accentFor(surface.want) || "transparent"
    }

    // A color is not a file: nothing is loaded for it, the scene's ground
    // simply turns that color and the picture frame fades out over it.
    readonly property string solid: Art.colorOf(surface.want)
    property bool wasSolid: false

    readonly property var look: Picasso.lookFor(surface.screenName)

    // This monitor's slice of a span: the whole desk, moved into this
    // monitor's own coordinates, most of it off the edge and clipped away.
    readonly property var spanTarget: {
      const r = Picasso.spanRectFor(surface.screenName);
      if (!r || !surface.modelData) return null;
      return { x: r.x - surface.modelData.x, y: r.y - surface.modelData.y, w: r.w, h: r.h };
    }

    // Only worked out when something will use it — see Picasso.accentFor.
    readonly property string accent:
      (surface.solid === "" && (surface.look.backdrop === "accent" || surface.look.tint === "accent"))
        ? Picasso.accentFor(surface.want) : ""

    // Two images and a crossfade rather than one image whose source changes:
    // swapping a source in place shows a black frame while the new file
    // decodes, which on a 4K background is very visible.
    property bool aFront: true
    readonly property Item front: surface.aFront ? imgA : imgB
    readonly property Item back: surface.aFront ? imgB : imgA

    // ── startup fade + zoom ──────────────────────────────────────────
    // WallContainer handles startup/unlock (whole surface zoom), per-Wall
    // handles background change (only the NEW background zooms, old stays
    // static) — so applying a background never looks like old+new both zoom.
    property real intro: 0
    property bool _introInstant: false
    property bool _initialLoadDone: false
    Behavior on intro {
      enabled: !surface._introInstant
      NumberAnimation { duration: Arrival.duration; easing.type: Zenon.ease }
    }
    // interval is set at play time: a cold login waits for the session to be
    // on screen, a background change or an unlock does not (Arrival.delay())
    Timer { id: introTimer; interval: 60; onTriggered: surface.intro = 1 }

    // ARMED BY THE SURFACE AND THE IMAGE TOGETHER, not by Component.onCompleted.
    //
    // Same trap the pill's intro was in: on a cold login this runs before there
    // is a mapped surface, so the 60ms wait and the 750ms zoom finished against
    // a window that had not been shown — and unlike the pill there is a second
    // gate here, because a fade against an undecoded 4K image is black on black
    // even once the surface IS up. So the arrival waits for both: a window on
    // screen, and a background actually decoded into the front buffer.
    //
    // Latched. A background change must NOT come through here — that has its own
    // per-Wall zoom, so that the outgoing background stays put while only the
    // incoming one moves — and unlock replays through Picasso.introTick.
    property bool _introArmed: false
    // This surface's first presented frame, for the same reason the pill waits
    // on one: the window reports itself visible ~150ms before it has handed the
    // compositor anything.
    property bool framed: false
    Connections {
      target: wallContainer.Window.window
      enabled: !surface.framed
      function onFrameSwapped() { surface.framed = true; }
    }

    readonly property bool introReady: surface.framed
      // no background set is a legitimate resting state, not something to wait on
      && (surface.want === "" || surface.solid !== ""
          || surface.front.showing)

    onIntroReadyChanged: if (surface.introReady) surface.playIntro()

    // The same guarded safety net the pill has. Counted from the window being
    // up rather than from load, so it can never beat a slow first frame — but
    // if a frame genuinely never arrives, the background must not be left at
    // opacity 0, which would show as no background at all.
    Timer {
      interval: 2500
      running: !surface._introArmed && surface.backingWindowVisible
      onTriggered: surface.playIntro()
    }

    function playIntro() {
      if (surface._introArmed) return;
      surface._introArmed = true;
      surface._introInstant = true;
      surface.intro = 0;
      surface._introInstant = false;
      introTimer.interval = Arrival.delay();
      introTimer.restart();
    }

    Connections {
      target: Picasso
      function onIntroTickChanged() {
        surface._introArmed = true;
        surface._introInstant = true;
        surface.intro = 0;
        surface._introInstant = false;
        introTimer.interval = 60;
        introTimer.restart();
      }
      function onHoldTickChanged() {
        introTimer.stop();
        surface._introInstant = true;
        surface.intro = 0;
        surface._introInstant = false;
      }
    }

    onWantChanged: surface.load()

    // ── WHAT THIS MONITOR IS SHOWING, told to the store ─────────────────
    // So whoever applied a background can wait for it to be on screen (the
    // card's Apply turns into working dots until it is) rather than for the
    // assignment, which is instant and says nothing about a decode.
    readonly property string onScreen: surface.solid !== "" ? surface.want
      : surface.front.showing ? surface.front.path : ""
    onOnScreenChanged: Picasso.noteShown(surface.screenName, surface.onScreen)
    function failed(img) {
      if (img.status === Image.Error && img.path !== "" && img.path === surface.want)
        Picasso.noteFailed(surface.screenName, img.path);
    }

    function load() {
      // Asked of `want` itself, not of `solid`: this runs from onWantChanged,
      // which can fire before the binding on `solid` has caught up.
      if (Art.isColor(surface.want)) { surface.wasSolid = true; return; }
      // Coming back from a color: what the frame was holding is a picture
      // from before the color, and letting it fade back in on its way to
      // the new one would show a background nobody asked for.
      if (surface.wasSolid) {
        surface.wasSolid = false;
        if (surface.front.path !== surface.want) surface.show(surface.front, "");
      }
      // Compared by the PATH each frame was given, not by reading its URL
      // back: the URL is percent-encoded (see Strings.fileUrl), and one
      // stripped of "file://" no longer matched a path with a space or a #
      // in it — so the double buffer never recognized its own picture.
      const frontSrc = surface.front.path;
      const backSrc = surface.back.path;
      if (surface.want === frontSrc)
        return;
      if (surface.want === "") {
        surface.show(surface.front, "");
        return;
      }
      // recently applied background is still in the back buffer (front is the
      // other one, back is the previous pick). Setting back.source to the same
      // url wouldn't reload and ready() would never fire, so the flip stalls
      // and the old background stays — looks like picasso refused the pick.
      if (surface.want === backSrc) {
        if (surface.back.showing) {
          // back already decoded, just flip to it (with zoom)
          if (surface._initialLoadDone) {
            if (surface.back === imgA) imgA._pendingZoom = true;
            else imgB._pendingZoom = true;
          }
          surface.ready(surface.back);
        } else if (surface.back.status === Image.Null || surface.back.status === Image.Error) {
          // back was cleared or failed — force a reload
          surface.show(surface.back, "");
          surface.show(surface.back, surface.want);
          if (surface._initialLoadDone) {
            if (surface.back === imgA) imgA._pendingZoom = true;
            else imgB._pendingZoom = true;
          }
        }
        // if back is Loading, its onStatusChanged will flip when ready
        return;
      }
      // background change — don't touch wallContainer (which would zoom the
      // OLD background). Just set the new source in back; its own per-Wall
      // zoom will run when it flips to front in ready().
      if (surface._initialLoadDone) {
        // mark the back wall to zoom when it becomes front
        if (surface.back === imgA) imgA._pendingZoom = true;
        else imgB._pendingZoom = true;
      }
      // no first-load branch: the whole-surface intro is armed by introReady,
      // once this image has decoded and there is a window to show it in
      surface.show(surface.back, surface.want);
    }

    // The one way a frame is pointed at a picture, so its path and its URL
    // cannot disagree.
    function show(img, path) {
      img.path = path;
      img.source = path === "" ? "" : Strings.fileUrl(path);
    }

    // Flip only once the incoming image has actually decoded — and only an
    // image that IS the one wanted. A frame decodes again whenever its size
    // changes (a span lays the picture across the whole desk, a fit or a
    // turn reshapes the frame), and that includes the frame holding the
    // picture being replaced: its second "ready" flipped the OLD background
    // back to the front a moment after the new one arrived (user's capture,
    // 2026-10-11) — the pick seemed refused, and picking it again did nothing.
    function ready(img) {
      if (img === surface.back && img.status === Image.Ready
          && img.path === surface.want && img.path !== surface.front.path) {
        surface.aFront = !surface.aFront;
        // the crossfade and the zoom run Arrival.duration from here
        Picasso.transitionUntil = Math.max(Picasso.transitionUntil, Date.now() + Arrival.duration);
        // per-Wall zoom for background change
        if (img._pendingZoom) {
          img._pendingZoom = false;
          img._zoomInstant = true;
          img.scale = Oracle.backgroundZoom;
          img._zoomInstant = false;
          img.scale = 1.0;
        }
        if (!surface._initialLoadDone) {
          surface._initialLoadDone = true;
        }
      }
    }

    // ── ONE FRAME OF THE DOUBLE BUFFER: A STILL, OR AN ANIMATION ─────────
    // Two pictures inside, and only one is ever handed the file: a still to
    // an Image, which decodes off the GUI thread, an animation to an
    // AnimatedImage. It was an AnimatedImage alone, and that decodes a
    // still with QMovie ON the GUI thread: measured, a 5120x3200 background
    // froze the shell for 115 ms at every start and every change, where
    // Image (asynchronous) froze it for 0 ms and was ready as soon
    // (approved 2026-10-09, done 2026-10-11). An animated .png (APNG) is
    // shown as a still: nothing in its name says it moves.
    component Wall: Item {
      id: wall
      // the file this frame is showing, as a path — see surface.show()
      property string path: ""
      property url source: ""
      // by the name: these are the formats that can move
      readonly property bool moving: /\.(gif|webp|apng|mng)$/i.test(wall.path)
      // as an Image's: Null, Loading, Ready, Error — of the one in use
      readonly property int status: wall.moving ? anim.status : still.status
      // THIS frame's picture has been decoded at least once. Not `status`:
      // a frame decodes again when its size changes, and drawn by status it
      // went black for the length of that decode (the desktop blacked out
      // for a second when a span was applied). The pixels it had stay on
      // screen meanwhile — retainWhileLoading — so it stays shown.
      property string readyPath: ""
      readonly property bool showing: wall.path !== "" && wall.readyPath === wall.path
      // (a Connections, as below: the Walls' own onStatusChanged would replace
      // a handler written here)
      Connections {
        target: wall
        function onStatusChanged() { if (wall.status === Image.Ready) wall.readyPath = wall.path; }
      }
      // THIS surface's monitor, not a global. The Wall component is declared
      // inside the per-screen surface, so `surface.modelData` is the output
      // it is painting — which is the whole point of the fit being per
      // monitor: the portrait screen can center what the landscape one crops.
      readonly property int fillMode: Picasso.fillModeFor(
        surface.modelData ? surface.modelData.name : "")
      anchors.fill: parent

      Image {
        id: still
        anchors.fill: parent
        // the file the probe settled on: the picture itself, or its
        // screen-sized copy when it is far bigger than the screen (useFile)
        source: wall.moving || wall.useFile === "" ? "" : Strings.fileUrl(wall.useFile)
        fillMode: wall.fillMode
        // which part a crop keeps, already carried through the frame's turn
        horizontalAlignment: scene.hAlign
        verticalAlignment: scene.vAlign
        sourceSize: wall.sourceSize
        asynchronous: true
        retainWhileLoading: true
        cache: false
        smooth: true
      }
      AnimatedImage {
        id: anim
        anchors.fill: parent
        source: wall.moving ? wall.source : ""
        fillMode: wall.fillMode
        horizontalAlignment: scene.hAlign
        verticalAlignment: scene.vAlign
        sourceSize: wall.sourceSize
        asynchronous: true
        retainWhileLoading: true
        cache: false
        smooth: true
        playing: true
        paused: false
      }

      // ── decode at screen size, not at file size ──────────────────────
      //
      // Without a sourceSize every background is decoded at its FULL
      // resolution and kept that way for as long as it is assigned. The
      // originals in this library run to 7276x4895, which is 135MB of RGBA
      // for a monitor that can show 8MB of it — and there are two Walls per
      // surface and one surface per monitor, so four full-size decodes sit
      // resident at once. That, not the module count, is where this shell's
      // memory went: a measured 92MB for one 5785x3857 background against
      // 36MB for the same file decoded to fit.
      //
      // ONE AXIS AT A TIME, WHICH IS THE WHOLE SUBTLETY. AnimatedImage is not
      // Image here: give Image both axes and it scales to COVER the box with
      // the aspect ratio intact, but give AnimatedImage both and it scales to
      // exactly that box and stretches the picture — visibly, a 3:2 background
      // squashed onto 16:9. Constrain a single axis and it preserves the
      // aspect ratio the way Image does. So pin whichever axis makes the
      // decode COVER the screen, and leave the other at 0, which is how Qt
      // spells "unconstrained":
      //
      //   image no wider than the screen -> pin the width, height overflows
      //   image wider than the screen    -> pin the height, width overflows
      //
      // The image measures its own aspect ratio for free: with one axis
      // pinned, implicitWidth/implicitHeight IS the source's ratio, so no
      // probe decode is needed to choose between the two.
      //
      // ASKED OF THE FILE, NOT OF THE DECODE, which is the whole trick.
      //
      // The obvious source for "is this wider than the screen" is the image
      // itself: with one axis pinned, implicitWidth/implicitHeight is the
      // source's ratio. But that answer exists BECAUSE of the decode that
      // sourceSize asked for, so using it to choose sourceSize is a cycle —
      // sourceSize -> decode -> status -> wide -> sourceSize. Latching it in a
      // status handler instead of a binding hid the shape of that without
      // breaking it, and Qt still said so: "Binding loop detected for property
      // sourceSize", four of them on every start.
      //
      // The probe below already knows. `magick identify` reads the header and
      // reports the file's real dimensions — the same ratio, owing nothing to
      // how the file is being decoded. So the question is asked there, and
      // this goes back to being an ordinary binding over two ordinary numbers.
      //
      // Both are 0 until the probe answers, so this is false and the
      // width-pinned branch runs — the right guess for anything that is not a
      // panorama, which is what makes the second decode the rare case.
      readonly property bool _wide:
        wall._natW > 0 && wall._natH > 0 && wall.height > 0
          && (wall._natW / wall._natH) > (wall.width / wall.height)

      Connections {
        // Connections, not a handler on the component root: the two Walls
        // below declare their own where they are created, and one here would
        // be replaced by theirs rather than run alongside it.
        target: wall
        // a new background is measured from scratch
        function onSourceChanged() { wall._measure(); }
      }


      // ── never decode BIGGER than the file ────────────────────────────
      //
      // sourceSize is not a cap, it is an instruction: ask for more pixels
      // than the file holds and Qt scales the image UP while decoding it,
      // which costs real memory for no picture at all. Measured on a
      // 1858x1394 background against a 2560x1440 screen: 15MB decoded at its
      // own size, 43MB decoded at the size that would cover the screen. A
      // background smaller than the monitor is not unusual — it is what the
      // default in picasso.json is — so covering it blindly turns the saving
      // above into a loss.
      //
      // Qt cannot answer "how big is this file" without decoding it, and the
      // decode is the thing being sized, so the question goes to the same
      // tool that already makes every thumbnail in this shell. It reads the
      // header only, and `[0]` takes the first frame so an animation answers
      // once rather than once per frame.
      //
      // Deliberately not gating the load on the answer. The first decode
      // runs at the cover size, which is already bounded and correct to look
      // at; the probe only ever makes it smaller, and only for images that
      // were going to be upscaled. A large background — the case this whole
      // block exists for — is never re-decoded, because its natural size is
      // larger than the cover size and the clamp changes nothing. And if
      // magick is missing the sizes stay 0, the clamp is skipped, and the
      // behavior is simply the uncapped cover.
      property int _natW: 0
      property int _natH: 0

      // ── A PICTURE FAR BIGGER THAN THE SCREEN IS SHOWN FROM A COPY ──────
      // Qt decodes every picture on ONE loader thread for the whole shell,
      // and a png is decoded whole before it is scaled: a 15119x8504
      // background took 1.3 s per monitor there, and every picture anywhere
      // in the shell waited behind it (user: applying a large one "freezes
      // picasso for like a second", 2026-10-11). So the probe now runs
      // FIRST, and a picture over BIG_PX that is three times the screen's
      // area is made into a cover-sized jpeg by ImageMagick in its own
      // process — once, kept in the cache by path, time, size and screen
      // size — and that is what Qt decodes. The background on screen stays
      // until it is ready. Not for "centered" and "tiled", which show the
      // picture at its own size, and not for an animation.
      //
      // `useFile` is what the still is given: "" while the probe is out.
      property string useFile: ""
      readonly property bool natural: wall.fillMode === Image.Pad || wall.fillMode === Image.Tile
      // the cover size the copy was made for, so a frame that grows (a span)
      // past it is measured again rather than shown blurred
      property size copyFor: Qt.size(0, 0)
      Process {
        id: sizeProbe
        // Which file this run is measuring. A frame can be handed a new
        // picture while the last probe is still out; `running = true` then
        // does nothing, and the old file's size was taken as the new one's.
        property string forPath: ""
        property size forCover: Qt.size(0, 0)
        property bool again: false
        onExited: {
          // nothing usable came back (no magick): the picture itself
          if (sizeProbe.forPath === wall.path && wall.useFile === "" && wall.path !== "")
            wall.useFile = wall.path;
          if (sizeProbe.again) { sizeProbe.again = false; wall._measure(); }
        }
        stdout: StdioCollector {
          id: sizeOut
          waitForEnd: true
          onStreamFinished: {
            if (sizeProbe.forPath !== wall.path) return;
            const lines = String(sizeOut.text).trim().split("\n");
            const m = (lines[0] || "").match(/^(\d+)\s+(\d+)/);
            if (m) {
              wall._natW = parseInt(m[1], 10);
              wall._natH = parseInt(m[2], 10);
            }
            const copy = lines.length > 1 && lines[1].indexOf("FILE ") === 0 ? lines[1].slice(5) : "";
            wall.copyFor = copy !== "" ? sizeProbe.forCover : Qt.size(0, 0);
            wall.useFile = copy !== "" ? copy : wall.path;
          }
        }
      }
      readonly property real bigPx: 40000000

      // Measured from Component.onCompleted as well as on every change: a
      // source assigned while the object is still being built has already
      // been set by the time Connections is listening, so the first background
      // of the session would otherwise be the one that never gets measured.
      // It resets the aspect latch too — both questions are asked again of
      // every new file.
      function _measure() {
        // a new picture: nothing shown from the old file's copy
        if (sizeProbe.forPath !== wall.path) { wall.useFile = ""; wall._natW = 0; wall._natH = 0; }
        if (wall.path === "") { wall.useFile = ""; return; }
        // laid out yet? the copy is made for the frame's size
        if (wall.width < 2 || wall.height < 2) { sizeLater.restart(); return; }
        if (sizeProbe.running) { sizeProbe.again = true; return; }
        sizeProbe.forPath = wall.path;
        // the cover at zoom, whichever way the frame is shaped
        const cw = Math.max(1, wall._coverW), ch = Math.max(1, wall._coverH);
        sizeProbe.forCover = Qt.size(cw, ch);
        const copying = !wall.moving && !wall.natural;
        sizeProbe.command = ["sh", "-c",
          'set -- "$1" "$2" "$3" "$4" "$5" "$6"; '
          + 'wh=$(magick identify -ping -format "%w %h" "$1[0]" 2>/dev/null) || exit 0; '
          + 'echo "$wh"; [ "$5" = 1 ] || exit 0; '
          + 'set -- "$1" "$2" "$3" "$4" "$5" "$6" $wh; '
          + '[ "$(( $7 * $8 ))" -gt "$6" ] && [ "$(( $7 * $8 ))" -gt "$(( 3 * $2 * $3 ))" ] || exit 0; '
          + 'key=$(printf "%s:%s" "$1" "$(stat -c %Y:%s "$1")" | md5sum | cut -c1-20); '
          + 'out="$4/$key-$2x$3.jpg"; '
          + 'if [ ! -s "$out" ]; then mkdir -p "$4" && magick "$1[0]" -auto-orient -resize "$2x$3^" -quality 93 "$out.part.jpg" '
          + '&& mv -f "$out.part.jpg" "$out" || exit 0; fi; '
          + 'touch -c "$out"; echo "FILE $out"; '
          // copies not shown for a month go (each use touches its own)
          + 'find "$4" -name "*.jpg" -mtime +30 -delete 2>/dev/null; exit 0',
          "sh", wall.path, String(cw), String(ch),
          Paths.cacheDir() + "/quickshell/picasso/backgrounds", copying ? "1" : "0", String(wall.bigPx)];
        sizeProbe.running = true;
      }
      // grown past the copy it shows (spanned across the desk): a bigger copy
      Timer {
        id: regrow
        interval: 300
        onTriggered: if (wall.copyFor.width > 0
                         && (wall._coverW > wall.copyFor.width * 1.02 || wall._coverH > wall.copyFor.height * 1.02))
                       wall._measure()
      }
      on_CoverWChanged: regrow.restart()
      on_CoverHChanged: regrow.restart()
      Timer { id: sizeLater; interval: 50; onTriggered: wall._measure() }
      // centered or tiled shows the picture at its own size: never the copy
      onNaturalChanged: wall._measure()
      Component.onCompleted: wall._measure()

      // Headroom for the zoom: the surface scales to Oracle.backgroundZoom on
      // arrival and each Wall replays the same figure on a change, so the image
      // is briefly drawn larger than the screen, and a decode pinned to exactly
      // the screen would soften for the length of that animation. One setting
      // feeds all three, which is what keeps the decode from being too small
      // for the move it has to cover.
      readonly property real _zoom: Oracle.backgroundZoom
      readonly property real _dpr: wall.Screen.devicePixelRatio
      readonly property int _coverW: Math.ceil(wall.width * wall._zoom * wall._dpr)
      readonly property int _coverH: Math.ceil(wall.height * wall._zoom * wall._dpr)
      // ONE binding over the whole size, not two over its halves.
      //
      // sourceSize is a value type: assigning .width reads the current size to
      // build the new one, so a separate binding on .height is invalidated by
      // it and re-runs, which invalidates .width again. Qt calls that what it
      // is — "Binding loop detected for property sourceSize.width" — and it
      // fired four times on every start. Qt.size() writes both at once and
      // there is nothing left to chase its own tail.
      // (both pictures decode at this; see Image and AnimatedImage above)
      readonly property size sourceSize: Qt.size(
        wall._wide ? 0
          : (wall._natW > 0 ? Math.min(wall._coverW, wall._natW) : wall._coverW),
        wall._wide
          ? (wall._natH > 0 ? Math.min(wall._coverH, wall._natH) : wall._coverH)
          : 0)
      // per-wallpaper zoom — only the NEW background scales, old stays static
      // matches wallContainer intro zoom (1100 OutQuint) so unlock and
      // wallpaper-change feel like the same camera move.
      property bool _pendingZoom: false
      property bool _zoomInstant: false
      Behavior on scale {
        enabled: !_zoomInstant
        NumberAnimation { duration: Arrival.duration; easing.type: Zenon.ease }
      }
      Behavior on opacity {
        NumberAnimation { duration: Arrival.duration; easing.type: Zenon.ease }
      }
    }

    Item {
      id: wallContainer
      anchors.fill: parent
      opacity: surface.intro
      // zoom from Oracle.backgroundZoom down to 1.0 driven by the same scalar
      // as opacity, so the two stay locked without a second Behavior chasing
      // the first
      readonly property real zoomBy: Oracle.backgroundZoom - 1
      transform: Scale {
        origin.x: wallContainer.width / 2
        origin.y: wallContainer.height / 2
        xScale: 1 + wallContainer.zoomBy * (1 - surface.intro)
        yScale: 1 + wallContainer.zoomBy * (1 - surface.intro)
      }

      Scene {
        id: scene
        anchors.fill: parent
        look: surface.look
        target: surface.spanTarget
        solid: surface.solid
        accent: surface.accent
        thumb: surface.solid === "" ? Picasso.thumbFor(surface.want) : ""

        // Both Walls live in one frame that fades out under a color, so
        // the double buffer below never has to know colors exist.
        Item {
          anchors.fill: parent
          opacity: surface.solid === "" ? 1 : 0
          Behavior on opacity {
            NumberAnimation { duration: Arrival.duration; easing.type: Zenon.ease }
          }

          Wall {
            id: imgA
            opacity: surface.aFront && showing ? 1 : 0
            onStatusChanged: { surface.ready(imgA); surface.failed(imgA); }
          }

          Wall {
            id: imgB
            opacity: !surface.aFront && showing ? 1 : 0
            onStatusChanged: { surface.ready(imgB); surface.failed(imgB); }
          }
        }
      }
    }

    Component.onCompleted: surface.load()
  }
}
