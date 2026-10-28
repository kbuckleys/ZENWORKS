// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ABOUT THIS COMPUTER, unfolded — the About row's fold-out: a head of the
// distro's logo in the panel's accent, its name and the machine's model,
// then machine.py's sections (System, Processor, Memory, …)
// under small labels as `key  value` lines. A row with a share (memory in
// use, a filesystem, a battery) draws it as terminus' UsageBar with the
// figure written in; a row's `note` is a dimmer second line. What it reads
// is Oracle.computer (oracle/machine.py through Ora.readComputer).
//
// Loaded by URL from OracleWindow, not named as a type: oracle/ has a
// qmldir, and a type added to one is not seen until the shell restarts.

import QtQuick
import QtQuick.Shapes
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus"
import "oracle.js" as Ora

Item {
  id: pc
  // the panel's palette, handed in rather than reached for
  property string face: Zenon.face
  property color fgColor: Zenon.white
  property color dimColor: Zenon.accentMuted
  property color highlight: Zenon.cyan

  readonly property var c: (Oracle.revision, Oracle.computer)
  readonly property bool reading: (Oracle.revision, Oracle.computerReading)
  readonly property var sections: pc.c && pc.c.ok ? pc.c.sections : []
  readonly property bool shown: pc.sections.length > 0
  property bool copied: false

  implicitHeight: frame.height + 24

  // in the list frame, as the Tools fold's packages are: what a row folds
  // open is a box under it, not loose text on the panel
  Item {
    id: frame
    x: 24
    y: 6
    width: pc.width - 48
    height: body.implicitHeight + 32
    Controls.ListFrame { anchors.fill: parent }
  }

  Timer { id: copiedTimer; interval: 1600; onTriggered: pc.copied = false }

  // the key column: as wide as the longest key (a display's model, a mount
  // point), so none is cut short, up to a third of a column
  FontMetrics {
    id: keyFm
    font.family: pc.face
    font.weight: Font.DemiBold
    font.pixelSize: Zenon.px(14)
  }
  readonly property real keyNeed: {
    let w = 0;
    for (const s of pc.sections) for (const r of s.rows) w = Math.max(w, keyFm.advanceWidth(r.k));
    return Math.ceil(Math.max(w + 4, 96));
  }
  readonly property real keyWidth: Math.min(pc.keyNeed, pc.colWidth / 3)

  // UP TO THREE COLUMNS (user, 2026-10-25: two; 2026-10-27: up to three):
  // as many side by side as each still fits a key, the gap and 280 of
  // reading (a usage bar shrinks to its column); one column otherwise
  readonly property real colGap: 64
  function fits(n) { return (facts.width - (n - 1) * pc.colGap) / n >= pc.keyNeed + 24 + Zenon.px(280); }
  readonly property int nUp: pc.fits(3) ? 3 : pc.fits(2) ? 2 : 1
  readonly property real colWidth: Math.floor((facts.width - (pc.nUp - 1) * pc.colGap) / pc.nUp)
  // the sections stay in their order, down the left and on down the right,
  // cut where the two halves come out nearest the same height (a section's
  // label and the gap over it count as two lines, a note as half of one)
  // a column is as wide as its widest reading (a bar counts as its full
  // 400), so the right one starts a gap after what the left one shows
  // rather than halfway across the panel
  FontMetrics {
    id: valFm
    font.family: pc.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
  }
  FontMetrics {
    id: noteFm
    font.family: pc.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(12)
  }
  function fitWidth(secs) {
    let w = 0;
    for (const s of secs) for (const r of s.rows)
      w = Math.max(w, typeof r.frac === "number" ? Zenon.px(400) : valFm.advanceWidth(r.v),
        r.note ? noteFm.advanceWidth(r.note) : 0);
    return Math.ceil(Math.min(pc.colWidth, pc.keyWidth + 24 + w + 4));
  }
  // where the centered columns start: the head, the inks and the buttons
  // line up with it
  readonly property real colsX: Math.max(0, (facts.width - colsRow.width) / 2)

  // the sections in their order, cut into nUp runs whose tallest is as short
  // as it can be (every cut tried: there are a dozen sections at the most)
  readonly property var columns: {
    const secs = pc.sections;
    const n = Math.min(pc.nUp, secs.length);
    if (n < 2) return [secs];
    const weight = secs.map((s) => 2 + s.rows.reduce((a, r) => a + 1 + (r.note ? 0.6 : 0), 0));
    const sum = (a, b) => weight.slice(a, b).reduce((x, y) => x + y, 0);
    let best = null, bestH = Infinity;
    const cut = (from, left, cuts) => {
      if (left === 1) {
        const all = cuts.concat([secs.length]);
        let h = 0, a = 0;
        for (const b of all) { h = Math.max(h, sum(a, b)); a = b; }
        if (h < bestH) { bestH = h; best = all; }
        return;
      }
      for (let k = from + 1; k <= secs.length - left + 1; ++k) cut(k, left - 1, cuts.concat([k]));
    };
    cut(0, n, []);
    const out = [];
    let a = 0;
    for (const b of best) { out.push(secs.slice(a, b)); a = b; }
    return out;
  }

  Column {
    id: body
    parent: frame
    x: 18
    y: 16
    width: frame.width - 36
    spacing: 0

    // the logo beside the distro's name and the machine's model: a head the
    // facts hang under, rather than a tall column beside them that the
    // window's frosted header cut through once the fold scrolled
    // THE HEAD, ONE LINE (user, 2026-10-27): the logo at the first column's
    // edge; the inks and the buttons at the right, ending where the last
    // column ends. Reread stays when there is nothing to show yet.
    Item {
      width: body.width
      height: Math.max(pc.shown ? headRow.height : 0, headSide.height + (pc.shown ? 0 : 12))
      Column {
        id: headSide
        x: Math.max(0, pc.colsX + colsRow.width - width)
        y: pc.shown ? (headRow.height - headRow.bottomPadding + headRow.topPadding - height) / 2 : 0
        spacing: 10
        // the theme's inks, each flowing into the next (user, 2026-10-28:
        // "colors merging in gradients"): one bar, a stop per ink
        Rectangle {
          visible: pc.shown
          anchors.right: parent.right
          width: 26 * 8
          height: 14
          radius: Zenon.rad(3)
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0 / 7; color: Zenon.red }
            GradientStop { position: 1 / 7; color: Zenon.sand }
            GradientStop { position: 2 / 7; color: Zenon.yellow }
            GradientStop { position: 3 / 7; color: Zenon.green }
            GradientStop { position: 4 / 7; color: Zenon.cyan }
            GradientStop { position: 5 / 7; color: Zenon.blue }
            GradientStop { position: 6 / 7; color: Zenon.magenta }
            GradientStop { position: 7 / 7; color: Zenon.pink }
          }
        }
        // centered under the inks (user, 2026-10-27)
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8
          DialogButton {
            visible: pc.shown
            label: pc.copied ? "Copied" : "Copy"
            ink: pc.highlight
            primary: true
            onClicked: {
              Strings.copy(Ora.computerText(pc.c));
              pc.copied = true;
              copiedTimer.restart();
            }
          }
          DialogButton {
            label: pc.reading ? "Reading…" : "Reread"
            ink: pc.fgColor
            ready: !pc.reading
            onClicked: Oracle.readComputer(true)
          }
        }
      }
      Row {
        id: headRow
        visible: pc.shown
        x: pc.colsX
        spacing: 18
        topPadding: 8
        bottomPadding: 20
        Item {
          id: logo
          readonly property bool arch: !!pc.c && pc.c.glyph === "\uF303"
          width: logo.arch ? logo.height : logoGlyph.contentWidth
          height: Zenon.px(64)
          Text {
            id: logoGlyph
            visible: !logo.arch
            anchors.verticalCenter: parent.verticalCenter
            text: pc.c ? pc.c.glyph : ""
            color: pc.highlight
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(58)
          }
          // ARCH IS DRAWN, NOT TYPED. Nerd Fonts' Arch logo (U+F303) carries
          // a small ™ beside its right foot, close enough that no crop takes
          // it off cleanly at every size (a sliver of the T stayed). This is
          // the one outline from /usr/share/pixmaps/archlinux-logo.svg,
          // without its ™ paths, in the panel's accent.
          Shape {
            visible: logo.arch
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: pc.highlight
              strokeColor: "transparent"
              fillRule: ShapePath.OddEvenFill
              // the outline spans 12..245 of the file's 256 box: fit that span
              scale: Qt.size(logo.height / 233, logo.height / 233)
              PathSvg {
                path: "m116.98 0c-10.316 25.309-16.543 41.855-28.031 66.41 7.043 7.4609 15.691 16.156 29.734 25.977-15.098-6.207-25.395-12.445-33.094-18.918-14.703 30.68-37.742 74.391-84.492 158.39 36.746-21.219 65.23-34.293 91.773-39.289-1.1406-4.8945-1.7852-10.195-1.7422-15.734l0.042969-1.1719c0.58203-23.551 12.828-41.645 27.336-40.418 14.508 1.2266 25.781 21.316 25.199 44.867-0.10938 4.4219-0.60938 8.6914-1.4805 12.641 26.258 5.1328 54.438 18.18 90.684 39.105-7.1484-13.156-13.527-25.016-19.621-36.316-9.5938-7.4336-19.605-17.117-40.023-27.594 14.035 3.6406 24.082 7.8516 31.914 12.555-61.941-115.32-66.957-130.66-88.199-180.5z"
              }
            }
          }
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            textFormat: Text.PlainText
            text: pc.c ? pc.c.title : ""
            color: pc.highlight
            font.family: pc.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(19)
          }
          Text {
            visible: !!(pc.c && pc.c.model)
            width: Math.min(implicitWidth, Math.max(0, colsRow.width - logo.width - 18 - headSide.width - 24))
            elide: Text.ElideRight
            text: pc.c ? pc.c.model : ""
            color: pc.dimColor
            font.family: pc.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
      }

    }

    Column {
      id: facts
      width: body.width
      spacing: 4

      Rectangle {
        visible: pc.shown
        width: facts.width
        height: 1
        color: Zenon.border
      }

      // the columns, each as wide as what it shows, centered together
      Row {
        id: colsRow
        x: pc.colsX
        spacing: pc.colGap
        Repeater {
          model: pc.columns
          delegate: Column {
            id: col
            required property var modelData
            required property int index
            // as wide as its widest reading, a column's share at the most
            // (a long reading elides against it), so the lot can be centered
            width: pc.fitWidth(col.modelData)
            Repeater {
              model: col.modelData
              delegate: Column {
                id: sect
                required property var modelData
                required property int index
                width: col.width
                // room between one fact and the next, so a reading is read as
                // its own key's and not the line under it
                spacing: 10
                topPadding: sect.index === 0 ? 20 : 22

                SectionLabel {
                  text: sect.modelData.name
                }

                Repeater {
                  model: sect.modelData.rows
                  delegate: Row {
                    id: fact
                    required property var modelData
                    readonly property bool hasBar: typeof fact.modelData.frac === "number"
                    width: col.width
                    spacing: 24
                    Text {
                      id: factKey
                      width: pc.keyWidth
                      elide: Text.ElideRight
                      text: fact.modelData.k
                      color: pc.highlight
                      font.family: pc.face
                      font.weight: Font.DemiBold
                      font.pixelSize: Zenon.px(14)
                      // level with the bar's figure, not its top edge
                      topPadding: fact.hasBar ? (bar.height - contentHeight) / 2 : 0
                    }
                    Column {
                      width: fact.width - factKey.width - fact.spacing
                      spacing: 2
                      Text {
                        visible: !fact.hasBar
                        width: parent.width
                        elide: Text.ElideRight
                        text: fact.modelData.v
                        color: pc.fgColor
                        font.family: pc.face
                        font.weight: Zenon.weight
                        font.pixelSize: Zenon.px(14)
                      }
                      UsageBar {
                        id: bar
                        visible: fact.hasBar
                        width: Math.min(parent.width, 420)
                        height: fact.hasBar ? Zenon.px(18) : 0
                        frac: fact.hasBar ? fact.modelData.frac : 0
                        // filling up is the one thing worth a second color
                        accent: fact.hasBar && fact.modelData.frac > 0.85 && fact.modelData.k !== "Battery"
                          ? Zenon.red : pc.highlight
                        label: fact.modelData.v
                        ink: pc.fgColor
                        fontSize: 13
                      }
                      Text {
                        visible: !!fact.modelData.note
                        width: parent.width
                        elide: Text.ElideRight
                        text: fact.modelData.note || ""
                        color: pc.dimColor
                        font.family: pc.face
                        font.weight: Zenon.weight
                        font.pixelSize: Zenon.px(12)
                        bottomPadding: 2
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // nothing to show: still reading (the dots), or why not
      Working {
        running: !pc.shown && pc.reading
        height: Zenon.px(20)
      }
      Text {
        visible: !pc.shown && !pc.reading
        width: facts.width
        wrapMode: Text.Wrap
        // no `why` before the first read
        text: pc.c && pc.c.why ? pc.c.why : ""
        color: pc.dimColor
        font.family: pc.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

    }
  }
}
