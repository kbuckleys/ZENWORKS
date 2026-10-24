// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// A STICKY'S PAGE — the text a desktop note is written in, lifted out of
// ClioBoard so another surface can write in the same one (folio's snippets,
// 2026-10-21). The scrolling text, its caret, its spelling marks, the edges
// that melt where the text runs on, the scrollbar on the card's edge, and
// the ghost line an empty page shows.
//
// Fills the card it sits in; the text is `inset` in from its edges. RICH
// for a sticky (its bold, italic and underline are edits — see
// ClioBoard's card.mark), PLAIN for anything kept as plain text. What the
// text is saved as, and what the keys do beyond typing, belong to the
// holder: it listens on `edit` and to keyPressed.

import QtQuick
import "../morpheus"

Item {
  id: nf
  anchors.fill: parent

  property bool rich: true
  // the card's ground, which the edges melt into
  property color ground: "transparent"
  property string placeholder: ""
  property string face: Zenon.face
  property int weight: Zenon.weight
  property real size: Zenon.px(16)
  property int inset: 10
  // room kept clear at the bottom of the scrollbar's track (a sticky's
  // corner grip)
  property int barRoom: 0
  // the spelling's manager (Clio.app), and whether the marks are drawn
  property var mgr: null
  property bool spelling: true
  // the page stands aside (a sticky's typeface list)
  property bool hidden: false
  // the ghost stays while the caret is in the empty page (a sticky's goes)
  property bool ghostFocused: false

  readonly property alias edit: body
  readonly property alias spell: bodySpell
  readonly property alias scroll: bodyScroll

  // every key the text did not take for itself is the holder's first
  signal keyPressed(var e)

  Flickable {
    id: bodyScroll
    visible: !nf.hidden
    // Finder's rubber band and the smooth wheel notch, one rule for
    // the whole shell — see morpheus/Elastic.qml. Inside the view
    // rather than over it: it pins itself to the viewport.
    ElasticScroll { view: bodyScroll }
    anchors.fill: parent
    anchors.margins: nf.inset
    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    TextEdit {
      id: body
      width: parent.width
      // RICH TEXT for a sticky, because the formatting buttons are edits
      // rather than properties. Plain text would render the tags they
      // insert as the characters they are made of.
      textFormat: nf.rich ? TextEdit.RichText : TextEdit.PlainText
      wrapMode: TextEdit.Wrap
      selectByMouse: true
      persistentSelection: true
      color: Zenon.white
      selectionColor: Zenon.wash(0.25)
      selectedTextColor: Zenon.white
      font.family: nf.face
      font.weight: nf.weight
      font.pixelSize: nf.size

      // a hair wider than the default: on a sticky's tinted face a 2px
      // line in the text's own white all but vanishes
      cursorDelegate: Caret { field: body; thick: 3 }
      // the spelling, as a note's in the window (SpellMarks)
      SpellMarks { id: bodySpell; field: body; mgr: nf.mgr; visible: nf.spelling }

      Keys.onPressed: (e) => nf.keyPressed(e)
    }
  }

  // ── WHERE THE TEXT RUNS ON ──────────────────────────────────────────
  // A long note was cut off by a hard edge mid-line. Now the last few
  // pixels melt into the card's ground, and only while there is more past
  // them — at the end of the text the edge is clean. The first edge does
  // the same once the text has been scrolled.
  Rectangle {
    visible: bodyScroll.visible && bodyScroll.contentY > 1
    anchors.top: bodyScroll.top
    anchors.left: bodyScroll.left
    anchors.right: bodyScroll.right
    height: 14
    gradient: Gradient {
      GradientStop { position: 0; color: nf.ground }
      GradientStop { position: 1; color: Qt.rgba(nf.ground.r, nf.ground.g, nf.ground.b, 0) }
    }
  }
  Rectangle {
    visible: bodyScroll.visible
      && bodyScroll.contentY + bodyScroll.height < bodyScroll.contentHeight - 1
    anchors.bottom: bodyScroll.bottom
    anchors.left: bodyScroll.left
    anchors.right: bodyScroll.right
    height: 22
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(nf.ground.r, nf.ground.g, nf.ground.b, 0) }
      GradientStop { position: 1; color: nf.ground }
    }
  }

  // A SIBLING OF THE FLICKABLE, NEVER A CHILD OF IT. Inside, it becomes
  // part of the scrolling content: it travels up with the text and its
  // anchors resolve against the content item, whose height is the whole
  // document. On the card's edge, not the text's inset from it.
  Scrollbar {
    flick: bodyScroll
    anchors.right: parent.right
    anchors.top: bodyScroll.top
    anchors.bottom: bodyScroll.bottom
    anchors.bottomMargin: nf.barRoom
  }

  // The placeholder, which is not the TextEdit's own: a rich-text edit has
  // no ghost, and an empty page that says nothing at all looks broken
  // rather than blank.
  Text {
    x: nf.inset
    y: nf.inset
    width: parent.width - nf.inset * 2
    wrapMode: Text.Wrap
    visible: body.length === 0 && (nf.ghostFocused || !body.activeFocus) && !nf.hidden
    text: nf.placeholder
    color: Zenon.wash(0.35)
    font.family: nf.face
    font.weight: nf.weight
    font.pixelSize: nf.size
  }
}
