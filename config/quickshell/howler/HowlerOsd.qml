// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE VOLUME OSD — the one thing howler shows that nobody sent it.
//
// IT IS THE BAR'S VOLUME TOOLTIP, MOVED. Same fill, same border, same radius,
// same 20/10 padding and the same bold sixteen — see morpheus/Tooltip, whose
// metrics these are copied from rather than approximated. The tooltip itself
// is a CursorAnchor and follows the pointer, which is the one thing an OSD
// must not do; everything else about it is right, so everything else about it
// is here.
//
// It rides in the toast stack at the end nearest the bar, so a volume change
// and a notification arrive in the same place rather than in two overlays
// that drift apart by a few pixels.
//
// AND BRIGHTNESS (2026-10-20). Hermes announces every brightness change it
// makes — its sliders, the brightness keys (`qs ipc call Hermes brightness`)
// — and the same card shows it: the sun in yellow, the meter, the figure,
// and the screen's name when there is more than one. Whichever changed last
// is the one on the card.
//
// IT DOES NOT SHOW ON THE FIRST BINDING. Volume.level arrives once when
// Pipewire is first read, and an OSD that took that for a change would greet
// every login with a volume bar nobody asked for.

import QtQuick
import "../morpheus"
import "../hermes"

Item {
  id: osd

  property bool atTop: false
  property bool active: false
  // "volume" or "bright": what the card is showing
  property string kind: "volume"

  implicitWidth: card.implicitWidth
  // ONLY THE POP MOVES (user, 2026-10-26: "remove the slide animations
  // from OSD. only pop"). Its room in the stack is there at once and stays
  // until the pop back has finished, then goes at once: a height eased open
  // and shut carried the card along the stack, which read as a slide.
  // Cutting the height on the frame `active` went false is what once killed
  // the close, so the room is held while `leave` runs.
  readonly property bool held: osd.active || leave.running
  implicitHeight: osd.held ? card.implicitHeight : 0
  // the bounce's time both ways
  readonly property int popMs: Howler.openMs * 2
  visible: osd.held

  // ── THE FIRST VALUE IS THE STATE OF THE MACHINE, NOT NEWS ──────────────
  // Suppressing it by counting signals did not work, and could not: `ready`,
  // `level` and `muted` are three separate bindings off one audio object, so
  // when the sink appears `levelChanged` can arrive while `ready` is still
  // false. That bump returned at the readiness check WITHOUT priming, and the
  // flag was still down when the first real change came — which is the change
  // that got eaten instead. It also failed the other way: a sink whose volume
  // happens to match the null-state defaults emits nothing at all at startup,
  // so nothing primed and the same thing happened.
  //
  // So the guard is the VALUE rather than the count. What was on screen when
  // the sink was first understood is remembered, and a bump that does not
  // differ from it is not news no matter how many signals carried it.
  // AND THE VALUE ALONE IS NOT ENOUGH EITHER. PwObjectTracker only starts
  // streaming a sink's properties once it is being tracked, so the real
  // volume can arrive a moment AFTER `ready` — priming on readiness records
  // the placeholder, and the true value then reads as a change. Which is the
  // OSD that greets a cold start.
  //
  // So readiness opens a settling window instead of arming anything. Whatever
  // pipewire says during it is the state of the machine; the first thing
  // after it is news. Re-armed from scratch if the sink goes away and comes
  // back, because that is a cold start for this purpose too.
  property bool armed: false
  property real seenLevel: 0
  property bool seenMuted: false

  function prime() {
    if (!Volume.ready) return;
    osd.seenLevel = Volume.level;
    osd.seenMuted = Volume.muted;
  }

  Timer {
    id: settle
    interval: 1500
    onTriggered: {
      osd.prime();
      osd.armed = true;
    }
  }

  Connections {
    target: Volume
    function onReadyChanged() {
      osd.armed = false;
      if (Volume.ready) settle.restart();
      else settle.stop();
    }
    // INSIDE THE WINDOW IT IS STATE, AFTER IT, NEWS. Recording and comparing
    // are the two halves of the same fact and only one of them can be true of
    // any given signal — doing both would record the value and then find it
    // unchanged, which is an OSD that never fires at all.
    function onLevelChanged() { osd.armed ? osd.bump() : osd.prime(); }
    function onMutedChanged() { osd.armed ? osd.bump() : osd.prime(); }
  }

  // Belt as well as braces: a signal that carries no change is not news even
  // once the window has closed, and pipewire does emit those.
  function bump() {
    if (!Volume.ready || !osd.armed) return;
    if (Volume.level === osd.seenLevel && Volume.muted === osd.seenMuted)
      return;
    osd.seenLevel = Volume.level;
    osd.seenMuted = Volume.muted;
    osd.kind = "volume";
    osd.show();
  }
  // up, with the pop; already up, it only holds longer — a step while it
  // is open moves the reading, not the card (user, 2026-10-26: animations
  // for opening and closing only)
  function show() {
    if (!osd.active) arrive.restart();
    osd.active = true;
    hold.restart();
  }

  // Hermes says so only when something actually moved it, so there is no
  // startup value to settle past
  Connections {
    target: Hermes
    function onBrightnessBumped() {
      osd.kind = "bright";
      osd.show();
    }
  }
  readonly property bool bright: osd.kind === "bright"

  Component.onCompleted: if (Volume.ready) settle.restart()

  Timer {
    id: hold
    interval: 1400
    onTriggered: osd.active = false
  }

  // ── THE MOTION IS ON A CONTAINER, NOT ON THE CARD ──────────────────
  // The fade and the slide used to sit on `card` itself, with the shadow a
  // sibling beside it. MenuShadow follows geometry, not transforms, so the
  // shadow landed at full strength in its final place on frame one while the
  // card slid and faded in on top of it — the stutter the OSD had and
  // cynosure used to have. Toasts never did, because theirs hang shadow and
  // card off one delegate that carries the motion. Same here: one item
  // moves, and both ride in it, so the shadow's layer is rendered once and
  // simply carried along.
  Item {
    id: body
    width: card.implicitWidth
    height: card.implicitHeight

    // set by the pop itself (arrive, leave): in quickly, out late in the
    // bounce back so the swell is seen. A Behavior whose duration followed
    // `active` read the old one, and faded out before the swell began.
    opacity: 0

    // ITS OWN MOTION, NOT A TOAST'S (user, 2026-10-26: "the OSDs need
    // different animations than notification toasts. go for bounce"). A
    // toast slides in from its corner; the OSD pops where it stands, over
    // its size and back (OutBack, the suite's ease for things arriving),
    // and goes the way it came, bounced back (user, 2026-10-26): a swell
    // past its size, then down to where it popped from. Nothing between.
    scale: 1
    ParallelAnimation {
      id: arrive
      NumberAnimation {
        target: body; property: "scale"
        from: 0.72; to: 1
        // twice a toast's arrival: at its 140 the overshoot was over before
        // it read as one
        duration: osd.popMs
        easing.type: Easing.OutBack; easing.overshoot: 2.2
      }
      NumberAnimation { target: body; property: "opacity"; to: 1; duration: Howler.closeMs; easing.type: Zenon.ease }
    }
    ParallelAnimation {
      id: leave
      NumberAnimation {
        target: body; property: "scale"
        to: 0.72
        duration: osd.popMs
        easing.type: Easing.InBack; easing.overshoot: 2.2
      }
      NumberAnimation { target: body; property: "opacity"; to: 0; duration: osd.popMs; easing.type: Easing.InQuart }
    }
    Connections {
      target: osd
      function onActiveChanged() { if (!osd.active) { arrive.stop(); leave.restart(); } else leave.stop(); }
    }

    // It shares the toasts' stack and their skin, so it casts what they
    // cast. The stack's surface is the whole output — see HowlerToasts —
    // so there is already room around it for this to fall into.
    // The CARD'S radius, not the toasts': the hole is cut to this, and a
    // smaller one left the shadow missing from the card's corners.
    MenuShadow {
      panel: card
      cornerRadius: card.radius
    }

    Rectangle {
      id: card
      implicitWidth: content.implicitWidth + 56
      implicitHeight: content.height + 28
      // NOT CENTERED IN ITS PARENT, and this was the whole of "the OSD has no
      // background": the card's implicit size is measured from `content`, so
      // anchoring `content` to the card is a size that depends on itself. QML
      // breaks that loop by calling it zero — a rectangle of no size paints no
      // fill and no border, while the Row inside it, which is centered on that
      // zero, carries on drawing. The meter and the text with nothing behind
      // them was a binding loop, not a missing color.
      x: 0
      y: 0

      // A TOAST'S SKIN. Same ground, same border, same corners, same
      // transparency — it shares their stack, so it is one of them.
      // THE TOAST'S OWN SKIN, which is the point of the OSD looking like
      // one — so it follows the same two settings rather than keeping a
      // copy of what they used to say.
      color: Howler.bg
      border.color: Zenon.border
      border.width: Howler.borderSize
      radius: Howler.radius * 2

      // COPIED FROM morpheus/NowPlayingPanel's volume row, verbatim — the
      // horizontal green meter, its glyph and its percentage. Not approximated
      // from the bar's vertical six-notch version, which is a different widget
      // for a different place.
      Row {
        id: content
        x: 28
        y: 14
        // AN EXPLICIT HEIGHT, for the same reason the card is not centered in.
        // Its children anchor to this Row's verticalCenter, and a Row measures
        // itself FROM its children — so leaving the height implicit made the
        // children's position depend on a height that depended on them, and
        // that loop resolved to zero all the way up to the card.
        height: 28
        spacing: 10

        // THE SPEAKER, AND THE MUTE. Both literals were empty — lost when
        // howler was rebuilt — so this drew nothing at all and the only thing
        // saying "muted" was the word at the far end. Written as escapes rather
        // than as the characters themselves, which is how they went missing.
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: osd.bright ? "\u{F00DF}" : Volume.muted ? "\uF466" : "\uF028"
          color: osd.bright ? Zenon.yellow : Volume.muted ? Zenon.red : Zenon.green
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(18)
        }

        // ONE OR THE OTHER, never both — the rule the bar's own meter follows,
        // written down in PulseAudioModule. Muted is not a quiet volume, it is
        // the absence of one, so the glyph says so and the gauge goes away
        // rather than standing beside it drawn empty and red.
        Meter {
          anchors.verticalCenter: parent.verticalCenter
          visible: osd.bright || !Volume.muted
          vertical: false
          segCount: 14
          thickness: 9
          segLength: 6
          segGap: 2
          value: osd.bright ? Hermes.osdBright.pct / 100 : Volume.level
          accent: osd.bright ? Zenon.yellow : Zenon.green
        }

        // And the figure goes with it: "muted" was the word doing the glyph's
        // job, which is why there was no glyph to see.
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: osd.bright || !Volume.muted
          width: 52
          horizontalAlignment: Text.AlignRight
          text: (osd.bright ? Hermes.osdBright.pct : Volume.percent) + "%"
          // tabular, so dragging the volume does not jiggle the bar beside it
          font.features: { "tnum": 1 }
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(17)
        }
        // which screen, when there is more than one to tell apart
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: osd.bright && Hermes.osdBright.label !== ""
          text: Hermes.osdBright.label
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
      }
    }
  }
}

