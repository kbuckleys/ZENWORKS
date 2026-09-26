// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE CARD ITSELF — rows, flash and shadow — without the surface it stands on.
//
// CardMenu puts it on a layer surface, placed in screen coordinates, which is
// right for a menu opened on the desktop or out of the pill. CardPopup puts
// it on an xdg-popup hung off a window, which is the only way a window can
// open a card: a client is never told where its own window is, and the
// compositor places a popup for it. One card, so the two look and behave
// exactly alike; see CardMenu for the row format.
import QtQuick
import Quickshell.Widgets
import "."

Item {
  id: root

  property var model: []
  // the room around the card for its shadow; the card is inset by it
  property int pad: Zenon.menuShadowPad
  property real shade: 1
  property bool hinged: false
  property bool onRight: false
  property string squareEdge: ""

  signal chosen(int index)

  readonly property alias card: bg

  function rowHeight(m) {
    return (m && m.isSeparator) ? Zenon.menuSepHeight : Zenon.menuRowHeight;
  }

  // The flash a row gives when it is clicked, and the reason the card
  // outlives the click: the action runs at the END of it.
  component ChosenFlash: Item {
    id: flash
    anchors.fill: parent
    z: 3
    property var pending: null
    property real chosen: 0
    readonly property bool running: flashAnim.running

    function fire(act) {
      flash.pending = act;
      flashAnim.restart();
    }

    SequentialAnimation {
      id: flashAnim
      NumberAnimation { target: flash; property: "chosen"; to: 1;
                        duration: 60; easing.type: Easing.OutQuad }
      NumberAnimation { target: flash; property: "chosen"; to: 0;
                        duration: 130; easing.type: Easing.InQuad }
      ScriptAction {
        script: {
          const act = flash.pending;
          flash.pending = null;
          if (act) act();
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      visible: flash.chosen > 0
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                     0.55 * flash.chosen)
    }
  }

  ClippingRectangle {
    id: bg
    anchors.fill: parent
    anchors.margins: root.pad
    // Grows out of its own top-left corner rather than appearing at full
    // size, so the card unfolds FROM the thing it belongs to.
    transformOrigin: Item.TopLeft
    scale: Zenon.menuScale(root.shade)
    opacity: root.shade
    // Opaque, like terminus' card: a menu sits ON what is behind it, not in
    // it, and a translucent ground let the wallpaper read through the rows.
    color: Zenon.menuBg
    border.color: Zenon.border
    border.width: 1
    radius: Zenon.menuRadius
    // Square where it meets its parent, round everywhere else — so a submenu
    // reads as hinged off the row that opened it rather than as a second card
    // that happens to be touching. Only when there IS a parent: a root card
    // opened at a pointer keeps all four corners.
    topLeftRadius:     (root.hinged &&  root.onRight) || root.squareEdge === "top" ? 0 : bg.radius
    bottomLeftRadius:  (root.hinged &&  root.onRight) || root.squareEdge === "bottom" ? 0 : bg.radius
    topRightRadius:    (root.hinged && !root.onRight) || root.squareEdge === "top" ? 0 : bg.radius
    bottomRightRadius: (root.hinged && !root.onRight) || root.squareEdge === "bottom" ? 0 : bg.radius

    Column {
      anchors.fill: parent
      anchors.margins: Zenon.menuCardPad
      spacing: 0

      Repeater {
        model: root.model

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          width: bg.width - 8
          height: root.rowHeight(row.modelData)

          readonly property bool sep: row.modelData.isSeparator || false
          readonly property bool on: row.modelData.enabled !== false && !row.sep
          // `danger` is for a row that is ARMED — one that has been clicked
          // once and is waiting to be confirmed. Arming is not an event, so it
          // does not flash; the row going red is the reply.
          readonly property color ink: !row.on ? Zenon.muted
            : ((row.modelData.danger || false) ? Zenon.red : Zenon.white)
          // Lit by the pointer, OR because the card it opened is still up.
          // A branch you are standing inside is still the row you came from,
          // and the pointer has by then moved off it onto the child.
          readonly property bool lit: row.on
            && (hover.containsMouse || row.index === root.activeIndex)

          Rectangle {
            anchors.fill: parent
            color: row.lit ? Zenon.border : "transparent"
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            // EDGE TO EDGE — a separator in a menu spans the whole card, as
            // every menu's does. The row sits inside the card's padding, so
            // it reaches back out by exactly that much.
            anchors.leftMargin: -Zenon.menuCardPad
            anchors.rightMargin: -Zenon.menuCardPad
            height: 1
            color: Zenon.border
            visible: row.sep
          }

          Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            visible: !row.sep

            // A row's mark is EITHER a glyph or an image, never both. Most of
            // this shell's menus draw icons from the font, but a tray menu's
            // come from the application as image URLs, and an application's
            // own icon is not something a font can stand in for.
            Item {
              id: icon
              anchors.verticalCenter: parent.verticalCenter
              width: 16
              height: 16
              visible: icon.glyph !== "" || icon.src !== ""
              readonly property string glyph: row.modelData.icon || ""
              readonly property string src: row.modelData.image || ""

              Text {
                anchors.fill: parent
                visible: icon.glyph !== ""
                text: icon.glyph
                color: row.ink
                font.family: Zenon.face
                font.pixelSize: 15
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
              }

              Image {
                anchors.fill: parent
                visible: icon.glyph === "" && icon.src !== ""
                source: icon.src
                sourceSize.width: 16
                sourceSize.height: 16
                // An application's icon is its own; dimming it for a disabled
                // row is the only thing done to it.
                opacity: row.on ? 1 : 0.45
              }
            }

            Text {
              anchors.left: icon.visible ? icon.right : parent.left
              anchors.leftMargin: icon.visible ? Zenon.menuIconGap : 0
              anchors.right: tail.left
              anchors.rightMargin: tail.width > 0 ? 8 : 0
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignLeft
              text: row.modelData.text || ""
              elide: Text.ElideRight
              color: row.ink
              font.family: Zenon.face
              font.weight: Font.Medium
              font.pixelSize: 16
            }

            // The chevron on a row that has children, or the tick on one that
            // reports a current choice. Never both — a row is a branch or an
            // answer, and one that looked like both would be lying about one.
            Text {
              id: tail
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              // COLLAPSES when it has nothing to show. A row with neither a
              // chevron nor a tick was still reserving 24px for one, so the
              // longest label in a card was elided by a column that was not
              // there — and the only fix available to a caller was to guess a
              // wider card. A plain row now gets that width back.
              width: tail.text === "" ? 0 : 16
              height: 16
              text: (row.modelData.hasChildren || false) ? ""
                : ((row.modelData.mark || false) ? "" : "")
              // Three answers, not two. A TICK is a state and keeps its
              // cyan; a CHEVRON is punctuation belonging to the label beside
              // it and takes the label's own white. Muted was lumping the
              // chevron in with "nothing here", which is what made it look
              // like a disabled row.
              color: (row.modelData.mark || false) ? Zenon.cyan
                : ((row.modelData.hasChildren || false) ? Zenon.white
                  : Zenon.muted)
              font.family: Zenon.face
              // The chevron matches the label it punctuates, which is 16.
              // The tick stays smaller: it is a state sitting in the margin,
              // not part of the sentence.
              font.pixelSize: (row.modelData.mark || false) ? 13 : 16
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignHCenter
            }
          }

          ChosenFlash { id: flash }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            enabled: row.on && !flash.running
            onEntered: root.hovered(row.index)
            // ONLY A POINTER THAT LEFT. Disabling a hovered MouseArea makes
            // Qt report an exit too — and the flash disables this one for its
            // whole length. So confirming an armed row ("Empty Trash", second
            // click) reported the pointer as gone, the owner disarmed it, and
            // the flash then ended in `chosen` on a row that was no longer
            // armed: it armed again instead of acting, every time.
            onExited: if (hover.enabled) root.unhovered(row.index)
            // A row that ASKS does not flash. The flash is the reply to an
            // action, and a row that opens a question has not done anything
            // yet — the question is the reply. Everything else flashes, and
            // the action runs at the end of it.
            onClicked: (event) => {
              if (event.button === Qt.RightButton) {
                // No flash: a right click on a row is a second question about
                // it, not the row doing its job.
                root.secondary(row.index);
                return;
              }
              if (row.modelData.asks || false) root.chosen(row.index);
              else flash.fire(() => root.chosen(row.index));
            }
          }
        }
      }
    }
  }

  // A row was pointed at. Separate from `chosen` because a branch opens on
  // hover and acts on click, and only the owner knows which rows are branches.
  signal hovered(int index)
  // And pointed away from — which is how an armed row disarms, so it cannot
  // sit primed waiting for a stray click later.
  signal unhovered(int index)

  // A row was RIGHT-clicked. Some rows carry two answers — icarus' trash row
  // opens the folder on a left click and its own card on a right one — and a
  // menu that swallowed the second button made that impossible to express.
  // Owners that have nothing to say to it simply do not connect it.
  signal secondary(int index)

  // The row whose own card is currently open, which stays lit while you are
  // inside that card. The owner knows which row that is; this card cannot,
  // because the child is a separate window. -1 for none. Both icarus' desktop
  // menu and terminus' context menu have always done this; a CardMenu that
  // did not was the one menu on the desktop whose parent row went dark the
  // moment its child appeared.
  property int activeIndex: -1

  MenuShadow {
    panel: bg
    reach: root.pad
    opacity: root.shade
    transformOrigin: Item.TopLeft
    scale: bg.scale
  }
}
