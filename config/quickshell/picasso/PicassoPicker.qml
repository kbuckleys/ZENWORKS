// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE COLOR PICKER, in place of hyprpicker. The screen stays live under it;
// the pointer carries a round loupe of the pixels around it, and a card
// beside it says what the one in the middle is, in the format you copy in.
//
//   click          copy it, and close
//   shift+click    copy it, and stay — for picking a palette in one go
//   ctrl (held)    the target moves at a fifth of the pointer's pace
//   arrows         move the target one pixel
//   wheel / tab    change the format: HEX, RGB, HSL, HSV, OKLCH, CMYK
//   right / esc    close without copying
//
// The format is oracle's (Picker format, under Background), so the wheel
// changes a setting rather than a passing state: the format you copied in
// last is the one it opens in next time.
//
// NO SCREENSHOT FILE. Reading a pixel needs a copy of the screen — nothing
// on wayland can read another surface's pixels otherwise, and hyprpicker
// takes one too, through the same screencopy. This one is a ScreencopyView:
// the compositor hands the frame straight to the GPU, with no grim and no
// PNG written and read back. It is taken once, when the picker opens.
//
// AND IT IS WHAT YOU SEE, the way hyprpicker shows its own. The live screen
// used to show through instead, so a window that opened while the picker
// was up was on screen but not in the copy being read — you pointed at it
// and got the colour of whatever had been there before. Shown frozen, what
// you see is always what you pick.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import "../morpheus"
import "../oracle"
import "capture.js" as Cap

Scope {
  id: picker

  property bool active: false
  // Where the pointer already is, asked of hyprland as the picker opens —
  // a hover only arrives on the first MOVE, and until then the loupe had
  // nowhere to be.
  property point startAt: Qt.point(-1, -1)
  // The pointer is hidden by hyprland for as long as the picker is up (it is
  // a blank cursor over the picker anyway), so the frame it copies has no
  // arrow in it — see Picasso.cursorCmd.
  onActiveChanged: {
    Picasso.showCursor(!picker.active);
    if (picker.active) { picker.startAt = Qt.point(-1, -1); cursorProc.running = true; }
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      id: cursorOut
      onStreamFinished: {
        const p = String(cursorOut.text || "").trim().split(",");
        picker.startAt = Qt.point(Number(p[0]), Number(p[1]));
      }
    }
  }

  readonly property string scheme: Cap.SCHEMES.indexOf(Oracle.pickerScheme) >= 0
    ? Oracle.pickerScheme : "hex"

  Connections {
    target: Picasso
    // the binding again puts it away, the way every toggle here works
    function onPickRequested() { picker.active = !picker.active; }
  }

  function sh(s) { return Strings.shellQuote(s); }

  function stepScheme(dir) {
    Oracle.set("pickerScheme", Cap.stepScheme(picker.scheme, dir));
  }

  // Copied, and said so — with the color itself as the toast's picture,
  // made with magick at the moment it is copied.
  function copy(r, g, b) {
    const text = Cap.format(r, g, b, picker.scheme);
    const hex = Cap.format(r, g, b, "hex");
    const dir = Paths.runtimeDir() + "/picasso";
    const sw = dir + "/swatch-" + hex.slice(1) + ".png";
    Quickshell.execDetached(["sh", "-c",
      "printf '%s' " + picker.sh(text) + " | wl-copy; mkdir -p " + picker.sh(dir) + "; "
      + "magick -size 64x64 xc:" + picker.sh(hex) + " " + picker.sh(sw) + " 2>/dev/null; "
      + "notify-send -a picasso -u low -i " + picker.sh(sw) + " " + picker.sh("Color copied")
      + " " + picker.sh(text)]);
  }

  Variants {
    model: picker.active ? Quickshell.screens : []

    PanelWindow {
      id: pane
      required property var modelData
      screen: pane.modelData

      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "picasso-picker"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }

      // THE TARGET — the pixel the loupe is on — and the pointer, which are
      // not always the same place: ctrl slows the target to a fifth of the
      // pointer's travel, and the arrows move it a pixel at a time, for the
      // one-pixel-wide line a hand cannot land on.
      property real mx: -1
      property real my: -1
      property real px: -1
      property real py: -1
      readonly property real fine: 0.2

      function aim(x, y) {
        pane.mx = Math.max(0, Math.min(pane.width - 1, x));
        pane.my = Math.max(0, Math.min(pane.height - 1, y));
        pane.sample();
      }
      function nudge(dx, dy) {
        if (pane.mx < 0) return;
        pane.aim(Math.floor(pane.mx) + 0.5 + dx, Math.floor(pane.my) + 0.5 + dy);
      }
      property var rgb: null
      // the colour under the target, worn by the loupe's rim and the card's
      // edge alike
      readonly property color ink: pane.rgb
        ? Qt.rgba(pane.rgb.r / 255, pane.rgb.g / 255, pane.rgb.b / 255, 1) : Zenon.border
      // held so its url stays valid while the canvas reads from it
      property var grab: null

      // the pointer's starting place, if it is on this screen and no move
      // has said otherwise yet
      Connections {
        target: picker
        function onStartAtChanged() {
          const gx = picker.startAt.x - pane.modelData.x, gy = picker.startAt.y - pane.modelData.y;
          if (pane.mx >= 0 || gx < 0 || gy < 0 || gx >= pane.width || gy >= pane.height) return;
          pane.px = gx; pane.py = gy;
          pane.aim(gx, gy);
          keys.forceActiveFocus();
        }
      }

      function sample() {
        if (pane.mx < 0 || !reader.ready) { pane.rgb = null; return; }
        const k = reader.width / Math.max(1, pane.width);
        const d = reader.getContext("2d").getImageData(
          Math.min(reader.width - 1, Math.floor(pane.mx * k)),
          Math.min(reader.height - 1, Math.floor(pane.my * k)), 1, 1).data;
        pane.rgb = { r: d[0], g: d[1], b: d[2] };
      }

      // ── the copy of the screen ─────────────────────────────────────────
      // One frame, taken as this surface appears and while it is still
      // empty — shown full screen as the frozen picture you pick from, and
      // read in two ways: magnified by the loupe, and pixel by pixel through
      // `reader`.
      // NOT TAKEN AT ONCE. The pointer is drawn into the frame on this
      // machine — a software cursor, so asking the capture to leave it out
      // (paintCursor) cannot — and hyprland only stops drawing it once the
      // picker has asked (onActiveChanged). So the capture waits a beat for
      // the pointer to be gone; taken straight away, the loupe magnified
      // the arrow.
      property bool armed: false
      Timer {
        interval: 140
        running: true
        onTriggered: pane.armed = true
      }

      ScreencopyView {
        id: scv
        anchors.fill: parent
        captureSource: pane.armed ? pane.modelData : null
        live: false
        paintCursor: false
        onHasContentChanged: if (hasContent)
          scv.grabToImage((r) => { pane.grab = r; }, scv.sourceSize)
      }

      // The frame again, as pixels a script can read: the grab, loaded as
      // an Image, drawn into a canvas. Through an Image rather than the
      // canvas' own loadImage, which took a grab's url on one screen and
      // silently never on the other. Off to the side of the window rather
      // than hidden: an invisible canvas is never painted, and one that is
      // not painted has nothing to read back.
      Image {
        id: frame
        visible: false
        cache: false
        source: pane.grab ? pane.grab.url : ""
        onStatusChanged: if (frame.status === Image.Ready) reader.requestPaint()
      }
      Canvas {
        id: reader
        x: -width - 16
        width: Math.max(1, scv.sourceSize.width)
        height: Math.max(1, scv.sourceSize.height)
        renderTarget: Canvas.Image
        property bool ready: false
        onPaint: {
          if (frame.status !== Image.Ready) return;
          getContext("2d").drawImage(frame, 0, 0, width, height);
          reader.ready = true;
          pane.sample();
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPositionChanged: (m) => {
          // ctrl held: the target follows at a fifth of the pointer's pace
          if ((m.modifiers & Qt.ControlModifier) && pane.mx >= 0 && pane.px >= 0)
            pane.aim(pane.mx + (m.x - pane.px) * pane.fine, pane.my + (m.y - pane.py) * pane.fine);
          else
            pane.aim(m.x, m.y);
          pane.px = m.x; pane.py = m.y;
        }
        onEntered: keys.forceActiveFocus()
        onExited: { pane.mx = -1; pane.px = -1; pane.rgb = null; }
        onClicked: (m) => {
          if (m.button === Qt.RightButton) { picker.active = false; return; }
          if (!pane.rgb) return;
          picker.copy(pane.rgb.r, pane.rgb.g, pane.rgb.b);
          if (!(m.modifiers & Qt.ShiftModifier)) picker.active = false;
        }
        onWheel: (w) => {
          picker.stepScheme(w.angleDelta.y > 0 ? -1 : 1);
          w.accepted = true;
        }
      }

      Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => {
          if (e.key === Qt.Key_Escape) { e.accepted = true; picker.active = false; }
          else if (e.key === Qt.Key_Tab) { e.accepted = true; picker.stepScheme(1); }
          else if (e.key === Qt.Key_Backtab) { e.accepted = true; picker.stepScheme(-1); }
          // a pixel at a time
          else if (e.key === Qt.Key_Left)  { e.accepted = true; pane.nudge(-1, 0); }
          else if (e.key === Qt.Key_Right) { e.accepted = true; pane.nudge(1, 0); }
          else if (e.key === Qt.Key_Up)    { e.accepted = true; pane.nudge(0, -1); }
          else if (e.key === Qt.Key_Down)  { e.accepted = true; pane.nudge(0, 1); }
          else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && pane.rgb) {
            e.accepted = true;
            picker.copy(pane.rgb.r, pane.rgb.g, pane.rgb.b);
            picker.active = false;
          }
        }
      }

      // ── the loupe ─────────────────────────────────────────────────────
      // ROUND, and ON the pointer rather than beside it: the pointer itself
      // is hidden, so the loupe is where you are, and the boxed pixel in its
      // middle is the one a click takes. A ClippingRectangle, because a
      // plain Rectangle's clip ignores its radius and left the loupe square.
      // an odd number of pixels across, so one sits exactly in the middle,
      // each drawn a WHOLE number of pixels wide — at 11.2 the grid lines
      // could not land on the pixel edges, and drifted across the loupe
      // 17 across: two more than it was, room for the card's three bands
      readonly property int span: 17
      readonly property int zoom: 11
      readonly property int loupeSize: pane.span * pane.zoom

      ClippingRectangle {
        id: loupe
        z: 2
        opacity: pane.mx >= 0 && reader.ready ? 1 : 0
        x: Math.round(pane.mx - width / 2)
        y: Math.round(pane.my - height / 2)
        width: pane.loupeSize
        height: pane.loupeSize
        radius: width / 2
        color: "black"

        ShaderEffectSource {
          anchors.fill: parent
          sourceItem: scv
          // not hidden: the frozen frame is the picture you pick from
          hideSource: false
          // LIVE, though the frame behind it never changes: a source that
          // is not live renders once and then ignores its own sourceRect, so
          // the loupe stayed on the first spot while the reading moved on.
          live: true
          smooth: false
          sourceRect: Qt.rect(Math.floor(pane.mx) - Math.floor(pane.span / 2),
                              Math.floor(pane.my) - Math.floor(pane.span / 2),
                              pane.span, pane.span)
        }

        // ── the pixel grid ──────────────────────────────────────────
        // A hairline on every pixel edge, so what is magnified reads as
        // pixels you can count rather than as a blur of blocks — dark, and
        // faint, so it separates the cells without tinting them.
        Repeater {
          model: pane.span - 1
          delegate: Rectangle {
            required property int index
            x: (index + 1) * pane.zoom
            width: 1
            height: loupe.height
            color: Qt.rgba(0, 0, 0, 0.28)
          }
        }
        Repeater {
          model: pane.span - 1
          delegate: Rectangle {
            required property int index
            y: (index + 1) * pane.zoom
            height: 1
            width: loupe.width
            color: Qt.rgba(0, 0, 0, 0.28)
          }
        }

        // the pixel that will be taken
        Rectangle {
          anchors.centerIn: parent
          width: Math.round(pane.zoom) + 2
          height: width
          color: "transparent"
          border.width: 2
          border.color: pane.rgb ? Cap.inkOn(pane.rgb.r, pane.rgb.g, pane.rgb.b) : "white"
        }
      }

      // ── the reading ─────────────────────────────────────────────────
      // ONE INSTRUMENT: a panel exactly as tall as the loupe, starting at the
      // loupe's centre and running out to one side, with the circle laid over
      // its near half — the lens, and the plate it is mounted on. Out to the
      // right, or mirrored to the left near the right edge of the screen.
      // Square where it meets the circle, which touches its top and bottom
      // edges there; rounded at the far end.
      readonly property bool flipped:
        loupe.x + loupe.width + readout.implicitWidth + 44 > pane.width - 8
      Rectangle {
        id: card
        z: 1
        opacity: loupe.opacity
        // matched to the RIM, which stands 2px outside the lens all round —
        // matched to the lens, the panel stopped short of the circle you see
        y: loupe.y - 3
        height: loupe.height + 6
        width: loupe.width / 2 + readout.implicitWidth + 44
        x: pane.flipped ? loupe.x + loupe.width / 2 - card.width : loupe.x + loupe.width / 2
        color: Zenon.menuBgSolid
        // no edge of its own: the rim below runs round lens and plate as one
        readonly property int rad: Zenon.menuRadius + 4
        topLeftRadius: pane.flipped ? card.rad : 0
        bottomLeftRadius: pane.flipped ? card.rad : 0
        topRightRadius: pane.flipped ? 0 : card.rad
        bottomRightRadius: pane.flipped ? 0 : card.rad

        Column {
          id: readout
          anchors.verticalCenter: parent.verticalCenter
          x: pane.flipped ? 22 : loupe.width / 2 + 22
          spacing: 10

          // THE COLOUR, as a chip you could lay against something — big
          // enough to read as the colour rather than as a dot beside a
          // number — and what it is: the value you copy, and where it is.
          Row {
            spacing: 12
            Rectangle {
              width: 42; height: 42; radius: 8
              anchors.verticalCenter: parent.verticalCenter
              color: pane.rgb ? Qt.rgba(pane.rgb.r / 255, pane.rgb.g / 255, pane.rgb.b / 255, 1) : "transparent"
              border.width: 1
              border.color: Zenon.wash(0.14)
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 3
              Text {
                text: pane.rgb ? Cap.format(pane.rgb.r, pane.rgb.g, pane.rgb.b, picker.scheme) : ""
                color: Zenon.white
                font.family: Zenon.faceMono
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(17)
              }
              Text {
                text: pane.mx < 0 ? "" : Math.floor(pane.mx) + ", " + Math.floor(pane.my)
                color: Zenon.muted
                font.family: Zenon.faceMono
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
              }
            }
          }

          // the formats the wheel walks through, this one lit — picasso's
          // own answer buttons, as the focus card and the viewer wear them
          Row {
            spacing: 4
            Repeater {
              model: Cap.SCHEMES
              delegate: Seg {
                required property string modelData
                label: Cap.SCHEME_LABELS[modelData]
                chosen: modelData === picker.scheme
                height: 24
                width: Math.max(38, schemeMetrics.advanceWidth + 16)
                TextMetrics {
                  id: schemeMetrics
                  font.family: Zenon.face
                  font.pixelSize: Zenon.px(13)
                  font.weight: 600
                  text: Cap.SCHEME_LABELS[modelData]
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Zenon.border
          }

          // the gestures, as keys — the cap every hint in the shell is
          // written on — two to a row so the card stays the lens' height
          Grid {
            columns: 4
            columnSpacing: 8
            rowSpacing: 6
            verticalItemAlignment: Grid.AlignVCenter
            Repeater {
              model: ["click", "copy", "shift click", "copy, keep going",
                      "ctrl", "slow", "arrows", "one pixel",
                      "wheel", "format", "esc", "close"]
              delegate: Item {
                id: hintCell
                required property string modelData
                required property int index
                readonly property bool isKey: index % 2 === 0
                implicitWidth: hintCell.isKey ? hintCap.implicitWidth : hintText.implicitWidth + (index % 4 === 1 ? 10 : 0)
                implicitHeight: 19
                KeyCap {
                  id: hintCap
                  visible: hintCell.isKey
                  anchors.verticalCenter: parent.verticalCenter
                  label: hintCell.isKey ? hintCell.modelData : ""
                }
                Text {
                  id: hintText
                  visible: !hintCell.isKey
                  anchors.verticalCenter: parent.verticalCenter
                  text: hintCell.modelData
                  color: Zenon.muted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(12)
                }
              }
            }
          }
        }
      }

      // ── the rim ───────────────────────────────────────────────────
      // ONE OUTLINE round lens and plate together: half the circle on the
      // open side, running straight into the plate's top and bottom edges
      // where they meet it, and round the plate's far end. They were two
      // rims, and where the ring curved away from the plate's band each
      // stopped short of the other.
      // The band is the colour itself, and a band of the colour on a field
      // of that colour vanished — so it is drawn over a dark stroke two
      // pixels wider, a hairline either side. Its middle runs half a pixel
      // outside the lens, so it reaches 3 out: the plate's edge.
      readonly property string rimPath: {
        const r = loupe.width / 2, R = r + 0.5;
        const cx = loupe.x + r, cy = loupe.y + r;
        const s = pane.flipped ? -1 : 1, sw = pane.flipped ? 0 : 1;
        const fx = (pane.flipped ? card.x : card.x + card.width) - s * 2.5;
        const cr = Math.max(0, card.rad - 2.5);
        const top = cy - R, bot = cy + R;
        return "M " + cx + " " + top
          + " L " + (fx - s * cr) + " " + top
          + " A " + cr + " " + cr + " 0 0 " + sw + " " + fx + " " + (top + cr)
          + " L " + fx + " " + (bot - cr)
          + " A " + cr + " " + cr + " 0 0 " + sw + " " + (fx - s * cr) + " " + bot
          + " L " + cx + " " + bot
          + " A " + R + " " + R + " 0 0 " + sw + " " + cx + " " + top + " Z";
      }
      Shape {
        z: 3
        anchors.fill: parent
        opacity: loupe.opacity
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: "transparent"
          strokeColor: Qt.rgba(0, 0, 0, 0.55)
          strokeWidth: 5
          PathSvg { path: pane.rimPath }
        }
        ShapePath {
          fillColor: "transparent"
          strokeColor: pane.ink
          strokeWidth: 3
          PathSvg { path: pane.rimPath }
        }
      }
    }
  }
}
