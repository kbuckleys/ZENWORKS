// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// USAGE BAR — a measurement drawn as a length, with its own figure written
// inside it.
//
// One bar, two places: the size column in the disk-usage view, and the disks
// down the sidebar. They were drawn separately — a 15px band with the figure
// inside it in one, a 2px hairline with the figure sitting somewhere else in
// the other — which is two answers in one window to the same question.
//
// The number sits ON the bar. A bar and a caption beside it are two things to
// read; one band with its own value written in it is one. The TRACK is what
// makes a short bar mean anything: every row shows the full length as well as
// its own share, so "small" is read against "small compared to what" rather
// than floating in the dark.
//
// A FILE of its own rather than an inline component, because both callers are
// themselves inline components of TerminusWindow — and because the size column
// and the sidebar are as far apart as two parts of that document get.

import QtQuick
import "../morpheus"

Item {
  id: bar

  // 0..1. Clamped rather than drawn past the end of its own track.
  property real frac: 0
  // Asked for, not answered yet. An empty track says so; no track at all
  // would say this row is not part of the question.
  property bool pending: false
  // false takes the band away and leaves the figure — the size column with the
  // usage mode off, which is a number and not a proportion.
  property bool bars: true
  property string label: ""
  property color accent: Zenon.cyan
  property color ink: Zenon.white
  // The listing's bar grows leftwards to MEET its number at the right edge.
  // A disk fills from the left, the way every gauge does.
  property bool fromRight: false
  property real labelPad: 8
  property real barRadius: 4
  property int fontSize: 14
  property int fontWeight: Font.Medium
  readonly property real span: Math.max(0, Math.min(1, bar.frac))
  // Does the fill's edge land on the written figure? A couple of pixels
  // either side counts, so the mark never grazes the first or last glyph.
  readonly property bool overText: {
    const edge = bar.fromRight ? bar.width - fill.width : fill.width;
    const right = bar.width - bar.labelPad;
    return edge > right - figure.contentWidth - 3 && edge < right + 3;
  }

  Rectangle {
    id: track
    anchors.fill: parent
    visible: bar.bars
    radius: bar.barRadius
    color: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.07)
  }

  Rectangle {
    id: fill
    visible: bar.bars
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: bar.fromRight ? undefined : parent.left
    anchors.right: bar.fromRight ? parent.right : undefined
    radius: bar.barRadius
    // No artificial minimum. A floor of a few pixels made 6 B and 0 B look
    // like the same measurement with a rendering fault, and the figure inside
    // already says which is which — so a share too small to draw is not drawn.
    //
    // The same goes for a share that would end inside the label's padding.
    // Growing from the right, 1% of the column is two pixels standing in the
    // gap just past the last digit, where it read as a typed pipe — "8.4
    // GiB|" on every row that was small next to the biggest. Only a fill that
    // reaches the figure is a length anyone can see.
    readonly property real want: Math.round(bar.span * bar.width)
    width: (bar.pending || bar.span <= 0
            || (bar.fromRight && fill.want < bar.labelPad)) ? 0 : fill.want

    // Lit along the top edge. A flat block at this height reads as a slab; the
    // sheen is what makes it read as a bar. Two stops, so no gradient library.
    //
    // Kept CLOSE TO THE TRACK in tone on purpose. The fill's edge lands
    // wherever the measurement puts it, which for most rows is somewhere in
    // the middle of the number — and against a bright fill that edge cut the
    // digits in half. Softened, the length still reads at a glance while the
    // number stays one piece of text on one surface.
    gradient: Gradient {
      GradientStop {
        position: 0.0
        color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.30)
      }
      GradientStop {
        position: 1.0
        color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.17)
      }
    }

    // The leading edge, brighter than the fill it ends.
    //
    // An unmarked edge inside the number reads as the digits having been cut
    // in half; a deliberate line reads as a mark on a scale, which is what it
    // is. Hidden at the extremes, where there is nothing to mark: a full bar
    // has no interior edge and an empty one has no bar.
    Rectangle {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: bar.fromRight ? parent.left : undefined
      anchors.right: bar.fromRight ? undefined : parent.right
      width: 1
      // fill.width too: a fill held at zero still anchors this to its edge,
      // which is the track's own end, and it stood there alone
      //
      // AND NOT THROUGH THE FIGURE. Once the listing went to a log scale most
      // bars end somewhere in their own number, and a bright line there cut
      // a glyph clean in two — "Ki|B", "2.|3". The soft edge of the fill
      // alone passes under the digits without breaking them; the mark comes
      // back wherever it lands in clear track.
      visible: bar.span > 0.01 && bar.span < 0.995 && fill.width > 0
        && !bar.overText
      color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.55)
    }

    Behavior on width {
      NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
    }
  }

  // Declared last so it draws over the band.
  Text {
    id: figure
    anchors.fill: parent
    horizontalAlignment: Text.AlignRight
    verticalAlignment: Text.AlignVCenter
    rightPadding: bar.labelPad
    text: bar.label
    color: bar.ink
    elide: Text.ElideRight
    font.family: Zenon.face
    font.pixelSize: bar.fontSize
    // enough weight to stay one word where the fill's edge crosses it
    font.weight: bar.fontWeight
  }
}
