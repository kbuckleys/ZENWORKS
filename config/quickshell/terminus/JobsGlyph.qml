// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE JOBS' GLYPH — the drawer's handle in a bar: there only while there is
// work, glowing as it starts, breathing while it runs, bursting green when
// the last lands (red on a fault), with a count once there are two. Lifted
// out of terminus' path bar (Chrome.qml, 2026-10-13). The holder opens its drawer on
// `hovered`, and keeps it to while there are jobs (Jobs.model.count).
//
//     JobsGlyph { onHoveredChanged: … }
//
// A browser's downloads button, and for the same reason: work that takes
// time is not the thing you are doing, it is a thing that is happening, and
// it belongs at the edge of the window rather than in a card floating over
// the corner of it.

import QtQuick
import QtQuick.Effects
import "../morpheus"

Item {
  id: jobsToggle
  // the shell's jobs
  readonly property var jobs: Jobs
  // the glyph's size
  property int size: Zenon.px(15)
  // the pointer is on it (the holder opens its drawer from that)
  readonly property bool hovered: jobsHov.hovered
  readonly property bool live: jobsToggle.jobs.model.count > 0
  // ONE COLOR, READ BY EVERYTHING. The glyph, the count, the glow and
  // the burst all wear it, so "something went wrong" is a single fact
  // about the drawer rather than four things that have to be kept in
  // step. Red is reserved for exactly this — the same rule the confirm
  // card's verbInk follows.
  // Bad news first — a failure alongside a success is still a
  // failure to go and look at. Then green, but only once nothing is
  // RUNNING: green while a second job is still going would be
  // reporting the batch finished when half of it has not.
  readonly property color tone: jobsToggle.jobs.faults > 0 ? Zenon.red
    : (jobsToggle.jobs.live === 0 && jobsToggle.jobs.done > 0 ? Zenon.green
                                               : Zenon.cyan)
  width: jobsToggle.live ? 32 : 0
  visible: width > 0.5
  height: Math.round(jobsToggle.size * 2.2)
  // Grows and collapses rather than appearing: it sits between the
  // status chip and the hamburger, and a button that pops into
  // existence shoves everything to its left across in one frame.
  Behavior on width {
    NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
  }

  // How lit the glow is, 0 to 1. Driven by the two animations below
  // rather than bound to anything: it has to BURST when a job starts
  // and then settle into a breath, and a binding can only ever say
  // one of those.
  property real glow: 0

  // ── the glow ────────────────────────────────────────────────
  // A blurred COPY of the glyph underneath the real one, not the
  // glyph itself blurred — blurring the thing you are meant to read
  // is how an icon becomes a smudge. The copy is what spreads; the
  // glyph on top of it stays sharp.
  Item {
    anchors.centerIn: parent
    width: parent.height
    height: parent.height
    opacity: jobsToggle.glow
    visible: opacity > 0.01
    // it swells with the burst, which is most of what makes a glow
    // read as an event rather than as a color
    scale: 1.0 + 0.55 * jobsToggle.glow
    layer.enabled: true
    layer.effect: MultiEffect {
      blurEnabled: true
      // blurMax is the kernel, which is the actual softness knob —
      // `blur` alone is only the fraction of it that gets used. The
      // menu's shadow note spells this out at length.
      blurMax: 48
      blur: 1.0
      brightness: 0.5
      saturation: 0.4
      autoPaddingEnabled: true
    }

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: jobsGlyph.text
      color: jobsToggle.tone
      font: jobsGlyph.font
    }
  }

  Text {
    id: jobsGlyph
    anchors.centerIn: parent
    // nf-fa-download, as an escape — a literal nerd glyph does not
    // survive the trip through a shell heredoc and arrives as
    // nothing at all. The browser's own sign for "things are coming
    // in", which is what this is.
    text: "\uF019"
    color: jobsToggle.tone
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: jobsToggle.size
  }

  // How many, when there is more than one — the same thing a browser
  // does, and the reason the glyph alone is not enough now that jobs
  // run together.
  Text {
    anchors.right: parent.right
    anchors.rightMargin: -1
    anchors.top: parent.top
    anchors.topMargin: 5
    visible: jobsToggle.jobs.model.count > 1
    text: jobsToggle.jobs.model.count
    color: Zenon.black
    style: Text.Outline
    styleColor: jobsToggle.tone
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(10)
  }

  // ON HOVER, not on click. Checking what is running is a glance, and
  // a glance should not cost a click and then a second click to put
  // it away again.
  HoverHandler { id: jobsHov }

  // A BURST when a job starts, then a breath for as long as any is
  // running. Two animations rather than one, because they answer two
  // different questions — "something just began" and "something is
  // still going" — and one curve cannot say both.
  SequentialAnimation {
    id: jobsGlowBurst
    NumberAnimation { target: jobsToggle; property: "glow"; to: 1.0;
                      duration: Zenon.ms(140); easing.type: Easing.OutQuad }
    NumberAnimation { target: jobsToggle; property: "glow"; to: 0.5;
                      duration: Zenon.ms(460); easing.type: Easing.InQuad }
  }

  SequentialAnimation {
    id: jobsFaultBurst
    NumberAnimation { target: jobsToggle; property: "glow"; to: 1.0;
                      duration: Zenon.ms(110); easing.type: Easing.OutQuad }
    NumberAnimation { target: jobsToggle; property: "glow"; to: 0.62;
                      duration: Zenon.ms(320); easing.type: Easing.InQuad }
  }

  // FINISHING IS NEWS TOO. It bursts like a start and a fault do,
  // and then it STAYS — settling to a floor instead of fading out,
  // because the green is the receipt and a receipt that dims itself
  // after half a second is one you had to be watching for.
  SequentialAnimation {
    id: jobsDoneBurst
    NumberAnimation { target: jobsToggle; property: "glow"; to: 1.0;
                      duration: Zenon.ms(130); easing.type: Easing.OutQuad }
    NumberAnimation { target: jobsToggle; property: "glow"; to: 0.55;
                      duration: Zenon.ms(420); easing.type: Easing.InQuad }
  }

  SequentialAnimation {
    id: jobsGlowPulse
    // jobsLive, not live: rows outlive the work now, and a drawer
    // sitting there green is finished — breathing at you is what
    // something still running does.
    running: jobsToggle.jobs.live > 0 && !jobsGlowBurst.running
             && !jobsFaultBurst.running && !jobsDoneBurst.running
    loops: Animation.Infinite
    NumberAnimation { target: jobsToggle; property: "glow"
                      to: jobsToggle.jobs.faults > 0 ? 0.95 : 0.78
                      duration: Zenon.glow; easing.type: Zenon.breathEase }
    NumberAnimation { target: jobsToggle; property: "glow"
                      to: jobsToggle.jobs.faults > 0 ? 0.45 : 0.28
                      duration: Zenon.glow; easing.type: Zenon.breathEase }
  }

  // and out when the last one finishes, rather than freezing at
  // whatever the pulse was on
  NumberAnimation {
    id: jobsGlowOut
    target: jobsToggle
    property: "glow"
    to: 0
    duration: Zenon.normal
    easing.type: Zenon.ease
  }

  Connections {
    target: jobsToggle.jobs
    function onStartedChanged() {
      jobsGlowOut.stop();
      jobsGlowBurst.restart();
    }
    // A failure bursts too, and harder: it settles to a brighter floor
    // than a start does, so a drawer with bad news in it is lit even
    // when nothing is running behind it.
    function onFaultedChanged() {
      jobsGlowOut.stop();
      jobsFaultBurst.restart();
    }
    // Only when the LAST one lands. Each job in a batch finishing
    // would otherwise re-burst the glyph while the rest are still
    // going, which reads as "done" three times before it is.
    function onFinishedChanged() {
      if (jobsToggle.jobs.live > 0) return;
      jobsGlowOut.stop();
      jobsDoneBurst.restart();
    }
  }

  // The model's own count, rather than a second counter kept in step
  // with it by hand: the last job leaving IS the count reaching zero.
  Connections {
    target: jobsToggle.jobs.model
    function onCountChanged() {
      if (jobsToggle.jobs.model.count > 0) return;
      jobsGlowBurst.stop();
      jobsGlowOut.restart();
    }
  }
}
