// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The list of jobs, as a card: every copy, move, archive and extract at once,
// live, each with its own meter and its own way to stop. Drawn from Jobs, so
// the terminus drawer and the bar's panel are the same card showing the same
// rows. It was terminus' own drawer until the jobs moved here — see Jobs.qml.

import QtQuick
import "."

Rectangle {
  id: jobsCard
  // Whether the pointer is on the card — the drawer and the bar panel each
  // keep themselves open while it is.
  readonly property bool hovered: cardHov.hovered
  width: 352
  height: jobsCol.implicitHeight
  color: Zenon.black
  border.color: Zenon.border
  border.width: 1
  radius: 8
  // How far in the card is, 0..1 — the holder's fade, which the card
  // grows with from its top right corner (where it hangs from).
  property real shown: 1
  transformOrigin: Item.TopRight
  scale: 0.96 + 0.04 * jobsCard.shown

  HoverHandler { id: cardHov }

  Column {
    id: jobsCol
    width: parent.width
    topPadding: 4
    bottomPadding: 6

    Item {
      width: parent.width
      height: 26

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: {
          const bad = Jobs.faults;
          const live = Jobs.model.count - bad;
          const runs = live === 1 ? "1 operation" : live + " operations";
          if (bad === 0) return runs;
          const said = bad === 1 ? "1 did not finish"
                                 : bad + " did not finish";
          return live === 0 ? said : runs + "  \u00b7  " + said;
        }
        color: Jobs.faults > 0 ? Zenon.red : Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }

      // Only once there are two. With one job the row's own × is right
      // there and a second way to press it is just another thing to
      // read past.
      Text {
        id: stopAll
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: Jobs.model.count - Jobs.faults > 1
        text: "stop all"
        color: stopAllHov.hovered ? Zenon.red : Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)

        HoverHandler { id: stopAllHov }
        MouseArea {
          anchors.fill: parent
          onClicked: Jobs.cancelAll()
        }
      }
    }

    Repeater {
      model: Jobs.model

      // `model` rather than named roles: the row carries nine of them
      // and declaring each one as a required property is nine lines
      // that say nothing the ListModel has not already said.
      delegate: Item {
        id: jobRow
        required property var model
        width: jobsCol.width
        height: 50

        readonly property bool ended: jobRow.model.state !== "running"
        readonly property color ink: jobRow.model.state === "failed"
          ? Zenon.red
          : (jobRow.ended || jobRow.model.cancelled ? Zenon.muted : Zenon.white)

        // icarus' menu highlight, which the context menu and its submenu
        // already wear. A drawer that lit its rows a different colour
        // from every other list in this window read as a different piece
        // of software — the same argument the context menu's own note
        // makes about matching the desktop menu.
        Rectangle {
          anchors.fill: parent
          color: rowHov.hovered ? Zenon.border : "transparent"
        }
        HoverHandler { id: rowHov }

        // ── THE SAME SENTENCE AS THE COPY TO / MOVE TO HEADER ────────
        // What is being done as its glyph, the thing, an arrow, and the
        // directory it is going to — terminus' send header says a transfer that
        // way, and the drawer said it as "Copying 3 items" with no word of
        // where. Running or ended is said by the ink and the word after it.
        Item {
          id: jobRowLabel
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.top: parent.top
          anchors.topMargin: 6
          anchors.right: jobRowPct.left
          anchors.rightMargin: 8
          height: jobWhat.implicitHeight
          clip: true

          readonly property string opGlyph: jobRow.model.op === "move" ? "\uDB80\uDD90"
            : jobRow.model.op === "copy" ? "\uDB80\uDD8F"
            : jobRow.model.op === "archive" ? "\uF187" : "\uF1C6"
          readonly property string tail: {
            if (jobRow.ended)
              return jobRow.model.state === "failed" ? "failed"
                : (jobRow.model.state === "done" ? "" : "stopped");
            return jobRow.model.entries > 0
              ? jobRow.model.seen + "/" + jobRow.model.entries
              : (jobRow.model.index > 0 ? jobRow.model.index + "/" + jobRow.model.total : "");
          }
          readonly property bool hasTo: (jobRow.model.to || "") !== ""
          // what the two names may have between them, after the marks
          readonly property real room: jobRowLabel.width - jobOp.implicitWidth - jobArrow.implicitWidth
            - jobDir.implicitWidth - (jobTail.text !== "" ? jobTail.implicitWidth + 10 : 0) - 34

          Row {
            spacing: 0
            Text {
              id: jobOp
              text: jobRowLabel.opGlyph
              color: jobRow.ended ? jobRow.ink : Zenon.keyInk
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
              rightPadding: 8
            }
            Text {
              id: jobWhat
              text: jobRow.model.what
              width: Math.min(implicitWidth, jobRowLabel.hasTo
                ? Math.max(40, jobRowLabel.room - Math.min(jobTo.implicitWidth, jobRowLabel.room / 2))
                : jobRowLabel.room + jobArrow.implicitWidth + jobDir.implicitWidth)
              elide: Text.ElideMiddle
              color: jobRow.ink
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            Text {
              id: jobArrow
              visible: jobRowLabel.hasTo
              text: "\uDB85\uDFB7"
              leftPadding: 8
              rightPadding: 8
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            Text {
              id: jobDir
              visible: jobRowLabel.hasTo
              text: "\uF07B"
              rightPadding: 5
              color: jobRow.ended ? jobRow.ink : Zenon.cyan
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            Text {
              id: jobTo
              visible: jobRowLabel.hasTo
              text: jobRow.model.to || ""
              width: Math.min(implicitWidth, Math.max(40, jobRowLabel.room - jobWhat.width))
              elide: Text.ElideMiddle
              color: jobRow.ended ? jobRow.ink : Zenon.cyan
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            Text {
              id: jobTail
              text: jobRowLabel.tail
              visible: text !== ""
              leftPadding: 10
              color: jobRow.model.state === "failed" ? Zenon.red : Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
          }
        }

        Text {
          id: jobRowPct
          anchors.right: jobRowStop.left
          anchors.rightMargin: 8
          anchors.verticalCenter: jobRowLabel.verticalCenter
          // An ended row said nothing at all, which was right while
          // the only rows that could end were bad ones and the state
          // word beside them carried the news. A row that WORKED is
          // now the drawer's whole point, and a blank where the
          // percentage was is not a receipt.
          // The speed and the time left ahead of the percentage, once
          // rsync has said them: "how far" is half the question, and
          // "how long" is the half you were actually wondering about.
          text: jobRow.model.state === "done" ? "done"
            : jobRow.ended ? ""
            : jobRow.model.cancelled ? "stopping"
            // An archive has a time left but no speed, so each half is said
            // on its own.
            : (jobRow.model.rate !== "" ? jobRow.model.rate + "  \u00b7  " : "")
              + (jobRow.model.eta !== "" ? jobRow.model.eta + " left  \u00b7  " : "")
              + jobRow.model.pct + "%"
          color: jobRow.model.state === "done" ? Zenon.green
            : jobRow.model.cancelled ? Zenon.muted : Zenon.cyan
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(14)
        }

        // Stopping it has to be possible from here. A list that reports
        // percentages and offers no way out is a set of progress bars
        // you have to wait for whatever they turn out to be doing — a
        // mistyped destination, a directory far bigger than you thought.
        Item {
          id: jobRowStop
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: jobRowLabel.verticalCenter
          width: 18
          height: 18

          Text {
            anchors.centerIn: parent
            text: "\uF00D"   // nf-fa-times
            color: jobStopHov.hovered ? Zenon.red : Zenon.muted
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }

          HoverHandler { id: jobStopHov }
          MouseArea {
            anchors.fill: parent
            // The same glyph does both jobs because it is the same
            // gesture: make this row go away. On one that is running
            // that means stop it; on one that already stopped there is
            // nothing left to stop, only to dismiss.
            onClicked: Jobs.dismiss(jobRow.model.id)
          }
        }

        // A METER, NOT A BAR. The same instrument the zoom control
        // and the audio quick look already are, so a proportion in this
        // window is read the same way wherever it turns up.
        Meter {
          id: jobBar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          anchors.bottomMargin: 9
          vertical: false
          thickness: 6
          segLength: 6
          segGap: 3
          // Every segment counts. A dead zone is for a control you set
          // by hand and nudge off its floor; this is a readout.
          deadZone: 0
          // From the PARENT's width, not this item's own. segCount
          // feeds implicitWidth inside Meter, so measuring `width`
          // here would be a size that depends on itself.
          segCount: Math.max(10, Math.floor((parent.width - 24) / 9))

          // NOT EVERY JOB CAN SAY HOW FAR ALONG IT IS.
          //
          // The percentage is counted out of entries, and an archive of
          // ONE file has exactly one entry: it sits at 0 for the whole
          // run and then jumps to 100 as it exits. An empty meter for
          // twenty seconds is indistinguishable from one that does not
          // work — which is what it was taken for.
          //
          // So a job with nothing to report says so by MOVING: the fill
          // sweeps the segments end to end, which is what every
          // progress readout that cannot count does. The moment a real
          // percentage arrives the sweep stops and the count takes over.
          readonly property bool counting: jobRow.ended
            || jobRow.model.pct > 0 || jobRow.model.entries > 1
            || jobRow.model.index > 0

          property real chase: 0
          NumberAnimation on chase {
            running: !jobBar.counting && !jobRow.model.cancelled
            loops: Animation.Infinite
            from: 0; to: 1
            duration: 1150
            easing.type: Easing.InOutQuad
          }

          value: jobBar.counting || jobRow.model.cancelled
            ? jobRow.model.pct / 100 : jobBar.chase
          accent: jobRow.model.state === "failed" ? Zenon.red
            : jobRow.model.state === "done" ? Zenon.green
            : (jobRow.ended || jobRow.model.cancelled ? Zenon.muted
                                                      : Zenon.cyan)
          // The row is edited in place rather than rebuilt — see the
          // note on Jobs.model — which is what lets this animate at all.
          // Off while sweeping: the chase is already an animation, and
          // easing it a second time turns it to soup.
          Behavior on value {
            enabled: jobBar.counting
            NumberAnimation { duration: 300; easing.type: Zenon.ease }
          }
        }
      }
    }
  }
}
