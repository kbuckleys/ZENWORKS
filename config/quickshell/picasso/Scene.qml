// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SCENE — a monitor's picture as it is finally seen: laid in a frame that may
// be turned, mirrored or stretched across a whole desk, over a backdrop, then
// blurred, greyed, tinted, vignetted and dimmed.
//
// ONE DEFINITION, TWO SIZES. The daemon paints a monitor with it and the
// picker's card paints the little monitors on its map with it, so what the
// map promises is what the wall does — they cannot drift, because there is
// only one of them. The picture itself is the caller's: the daemon's two
// crossfading Walls, or the card's single Image, go in as children and fill
// the frame.
//
//     Scene {
//       look: Picasso.lookFor(name)
//       target: …            // the region the picture covers, or null
//       unit: 1              // this item's pixels per screen pixel
//       Image { anchors.fill: parent; … }
//     }

import QtQuick
import QtQuick.Effects
import "picasso.js" as Art

Item {
  id: scene

  property var look: Art.lookOf({})
  // The region the picture covers, in this item's coordinates. Null is the
  // item itself; a span hands in the whole desk, most of which is off this
  // monitor and simply clipped away.
  property var target: null
  // How big a screen pixel is here. 1 on the wall; the map's scale on the
  // card, so a blur of 40 pixels on the wall is a blur of 2 on a monitor
  // drawn 150 pixels wide rather than a smear across all of it.
  property real unit: 1
  // For the backdrop: the picture's own colour, and a small copy of it
  property string accent: ""
  property string thumb: ""
  // A plain colour for the ground — a colour wallpaper, which has no
  // picture at all and is nothing but backdrop
  property string solid: ""

  default property alias content: frame.data

  clip: true

  readonly property var tgt: scene.target
    ? scene.target : { x: 0, y: 0, w: scene.width, h: scene.height }
  readonly property var fr: Art.frameRect(scene.tgt, scene.look.rotate)
  readonly property bool fxOn: Art.lookNeedsFx(scene.look)
  readonly property color tintInk: scene.look.tint === "accent"
    ? (scene.accent !== "" ? scene.accent : "#808080")
    : (scene.look.tint !== "" ? scene.look.tint : "#808080")

  // The alignment flags for the picture inside the frame, carried through
  // the frame's own turn and mirror — see picasso.js alignInFrame.
  readonly property var alignFlags: Art.alignFlags(
    Art.alignInFrame(scene.look.align, scene.look.rotate, scene.look.mirror))
  readonly property int hAlign: scene.alignFlags[0]
  readonly property int vAlign: scene.alignFlags[1]

  readonly property color groundInk: {
    if (scene.solid !== "") return scene.solid;
    const b = scene.look.backdrop;
    if (b === "color") return scene.look.backdropColor;
    if (b === "accent" && scene.accent !== "") return scene.accent;
    return "#000000";
  }

  Item {
    id: fx
    anchors.fill: parent
    // A layer only when something is asked of it. It is an offscreen copy
    // of a whole monitor, and a plain wallpaper should not pay for one.
    layer.enabled: scene.fxOn
    layer.effect: MultiEffect {
      blurEnabled: scene.look.blur > 0
      blur: scene.look.blur
      blurMax: Math.max(1, Math.round(64 * scene.unit))
      saturation: scene.look.saturation
      colorization: scene.look.tint !== "" ? scene.look.tintAmount : 0
      colorizationColor: scene.tintInk
    }

    Rectangle {
      anchors.fill: parent
      color: scene.groundInk
      Behavior on color {
        ColorAnimation { duration: 400; easing.type: Easing.OutCubic }
      }
    }

    // The blurred backdrop: the same picture, filling, and soft enough that
    // it reads as the picture's light rather than a second copy of it.
    Image {
      id: blurSrc
      anchors.fill: parent
      visible: false
      source: scene.look.backdrop === "blur" && scene.solid === "" && scene.thumb !== ""
        ? "file://" + scene.thumb : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: 128
      sourceSize.height: 128
    }
    MultiEffect {
      anchors.fill: parent
      visible: blurSrc.source.toString() !== "" && blurSrc.status === Image.Ready
      source: blurSrc
      blurEnabled: true
      blur: 1.0
      blurMax: Math.max(1, Math.round(64 * scene.unit))
      brightness: -0.12
    }

    Item {
      id: frame
      x: scene.fr.x
      y: scene.fr.y
      width: scene.fr.w
      height: scene.fr.h
      // mirror first, then turn: picasso.js alignInFrame undoes them in the
      // opposite order, and the two have to agree
      transform: [
        Scale {
          origin.x: frame.width / 2
          origin.y: frame.height / 2
          xScale: scene.look.mirror ? -1 : 1
        },
        Rotation {
          origin.x: frame.width / 2
          origin.y: frame.height / 2
          angle: scene.look.rotate
        }
      ]
    }
  }

  // Per monitor, even across a span: a vignette is how a SCREEN falls off,
  // and one drawn over the whole desk would darken only its outer edges.
  Vignette {
    anchors.fill: parent
    amount: scene.look.vignette
  }

  Rectangle {
    anchors.fill: parent
    color: "#000000"
    opacity: scene.look.dim
    Behavior on opacity {
      NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }
  }
}
