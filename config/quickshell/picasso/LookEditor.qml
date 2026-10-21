// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE LOOK, as controls: what fills the space around a picture, then dim,
// vignette, blur, color, light, contrast and tint. The focus card's Look
// tab and the viewer's edit panel are both this, so a photo and a background
// are edited with the same hands and the answers mean the same thing —
// the look they produce is one picasso.js look, painted by one Scene.
//
// It holds nothing. `look` comes in, and every change goes out through
// `touched`; the owner stages it however it stages things. The keyboard is the
// owner's too: it names the row it has lit in `kbRow`, and the ring follows.

import QtQuick
import "../morpheus"
import "../terminus" as Term
import "picasso.js" as Art

Item {
  id: ed

  property var look: Art.lookOf({})
  // the picture the look is for — its own color is a tint and a backdrop
  property string path: ""
  // a background has space around it to fill; a photo being edited does not
  property bool showBackdrop: true
  // the picture covers the whole screen (cropped, stretched): nothing is
  // left around it for the backdrop to fill, and the row says so
  property bool fills: false
  property string kbRow: ""
  // what the custom tint swatch holds when the tint is one of the presets
  property string customTint: "#7a8cff"
  // the owner's morpheus/WindowTip, if it has one: the swatches are the
  // only controls here with no words on them, so they say what they are
  property var tips: null

  function swatchName(k) {
    if (k === "") return "No tint";
    if (k === "accent") return "Its own color";
    if (k === "custom") return "A color of your own";
    for (const c of Art.presetColors) if (c.hex === k) return c.name;
    return k;
  }

  // THE SHELL'S ACCENT (Oracle's Accent color), on the background card only
  // (user, 2026-10-20) — not part of the look, and not staged with it: a
  // choice here is the setting itself. `accent` is its value, "" the theme's.
  property bool showAccent: false
  property string accent: ""
  // the accent's swatch ON: "" theme's, "accent" the picture's, "custom"
  readonly property string accentKind: {
    if (ed.accent === "") return "";
    const own = Picasso.accentFor(ed.path);
    return own && own.toLowerCase() === ed.accent ? "accent" : "custom";
  }
  // what the custom accent swatch holds when the accent is not one
  property string customAccent: ""
  signal accentChosen(string hex)
  // the screen picker, for the accent
  signal pickAccent()

  signal touched(string key, var value)
  signal resetLook()
  // the color picker, for "tint", "backdrop" or "accent" — the owner shows it
  signal editColor(string which)

  readonly property bool tintIsCustom:
    ed.look.tint !== "" && Art.tintPresets.indexOf(ed.look.tint) < 0

  function pct(v) { return Math.round(v * 100) + "%"; }
  function signed(v) { return (v > 0 ? "+" : "") + ed.pct(v); }

  implicitHeight: col.implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: 6

    // What fills the space a picture does not — around a fitted or
    // centered one, or the corners a turn leaves bare.
    Item {
      width: parent.width
      height: bdHead.height
      visible: ed.showBackdrop
      Head { id: bdHead; text: "Around it" }
    }
    // Color chosen again opens its picker — Segments answers a choice
    // of the one already chosen as well.
    Term.Segments {
      id: bdRow
      visible: ed.showBackdrop
      width: ed.width
      even: true
      textSize: Zenon.px(13)
      options: [["black", "Black"], ["color", "Color"], ["accent", "Its color"], ["blur", "Blurred"]]
      current: ed.look.backdrop
      onChose: (v) => {
        if (v === "color" && ed.look.backdrop === "color") ed.editColor("backdrop");
        else ed.touched("backdrop", v);
      }
      Ring { on: ed.kbRow === "backdrop" }
    }
    Item { width: 1; height: ed.showBackdrop ? 6 : 0 }

    Slide {
      width: parent.width
      label: "Dim"
      value: ed.look.dim; from: 0; to: 0.8; rest: 0
      valueText: ed.pct(ed.look.dim)
      kbOn: ed.kbRow === "dim"
      onMoved: (v) => ed.touched("dim", v)
    }
    Slide {
      width: parent.width
      label: "Vignette"
      value: ed.look.vignette; from: 0; to: 1; rest: 0
      valueText: ed.pct(ed.look.vignette)
      kbOn: ed.kbRow === "vignette"
      onMoved: (v) => ed.touched("vignette", v)
    }
    Slide {
      width: parent.width
      label: "Blur"
      value: ed.look.blur; from: 0; to: 1; rest: 0
      valueText: ed.pct(ed.look.blur)
      kbOn: ed.kbRow === "blur"
      onMoved: (v) => ed.touched("blur", v)
    }
    Slide {
      width: parent.width
      label: "Color"
      value: ed.look.saturation; from: -1; to: 1; rest: 0
      valueText: ed.signed(ed.look.saturation)
      kbOn: ed.kbRow === "saturation"
      onMoved: (v) => ed.touched("saturation", v)
    }
    Slide {
      width: parent.width
      label: "Light"
      value: ed.look.brightness; from: -1; to: 1; rest: 0
      valueText: ed.signed(ed.look.brightness)
      kbOn: ed.kbRow === "brightness"
      onMoved: (v) => ed.touched("brightness", v)
    }
    Slide {
      width: parent.width
      label: "Contrast"
      value: ed.look.contrast; from: -1; to: 1; rest: 0
      valueText: ed.signed(ed.look.contrast)
      kbOn: ed.kbRow === "contrast"
      onMoved: (v) => ed.touched("contrast", v)
    }

    Item { width: 1; height: 4 }

    Item {
      width: parent.width
      height: tintHead.height
      Head { id: tintHead; text: "Tint" }
    }
    // One row, always: 9 swatches of 30 with gaps of 6 is 318 pixels, and
    // whatever holds this is made at least that wide (the viewer's panel is
    // sized for it).
    Row {
      spacing: 6
      Repeater {
        model: Art.tintPresets
        delegate: Rectangle {
          id: sw
          required property string modelData
          readonly property bool isCustom: sw.modelData === "custom"
          readonly property string ink: sw.isCustom ? ed.customTint
            : sw.modelData === "accent" ? (Picasso.accentFor(ed.path) || "#777777")
            : sw.modelData
          readonly property bool on: sw.isCustom ? ed.tintIsCustom
            : ed.look.tint === sw.modelData
          width: 30
          height: 30
          radius: height / 2
          color: sw.modelData === "" ? "transparent" : sw.ink
          border.width: sw.on ? 2 : 1
          border.color: sw.on ? Zenon.white : Zenon.wash(0.25)
          // none: a slash
          Rectangle {
            visible: sw.modelData === ""
            anchors.centerIn: parent
            width: 20; height: 2; rotation: -45
            color: Zenon.accentMuted
          }
          // its own color: a small image mark; custom: a plus
          Text {
            anchors.centerIn: parent
            visible: sw.modelData === "accent" || sw.isCustom
            text: sw.isCustom ? "\uF1FB" : "\uF03E"
            color: Art.hexToHsv(sw.ink).v > 0.6 ? "#000000" : "#ffffff"
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(11)
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: ed.tips !== null
            onContainsMouseChanged: if (ed.tips) containsMouse
              ? ed.tips.show(sw, ed.swatchName(sw.modelData)) : ed.tips.hide(sw)
            onClicked: {
              if (sw.isCustom) {
                if (ed.tintIsCustom) ed.editColor("tint");
                else ed.touched("tint", ed.customTint);
              } else ed.touched("tint", sw.modelData);
            }
          }
          Ring { on: ed.kbRow === "tint" && sw.on; radius: width / 2 }
        }
      }
    }
    Slide {
      width: parent.width
      label: "Strength"
      opacity: ed.look.tint !== "" ? 1 : 0.4
      value: ed.look.tintAmount; from: 0; to: 1; rest: 0.5
      valueText: ed.pct(ed.look.tintAmount)
      kbOn: ed.kbRow === "tintAmount"
      onMoved: (v) => ed.touched("tintAmount", v)
    }

    // ── the shell's accent ──
    // Laid out as the tint above it: a head, then a row of 30px swatches.
    // The head's right end says what is worn — the hex, or the theme's.
    // Choices are the theme's own, the picture's own color, one of your
    // own (chosen again, it opens the picker), and, set apart as a tool
    // rather than a color, a pixel off the screen. "Shell" says it is not
    // the picture's: set at once, never staged with the look.
    Item { width: 1; height: ed.showAccent ? 4 : 0 }
    Item {
      visible: ed.showAccent
      width: parent.width
      height: acHead.height
      Head { id: acHead; text: "Shell accent" }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: acHead.verticalCenter
        text: ed.accent === "" ? "theme's own" : ed.accent
        color: Zenon.accentSoft
        font.family: ed.accent === "" ? Zenon.face : Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }
    Row {
      visible: ed.showAccent
      spacing: 6

      Repeater {
        model: ["", "accent", "custom"]
        delegate: Rectangle {
          id: ac
          required property string modelData
          readonly property string ink: ac.modelData === "" ? Zenon.hex(Zenon.themeAccent)
            : ac.modelData === "accent" ? (Picasso.accentFor(ed.path) || "#777777")
            : (ed.customAccent || Zenon.hex(Zenon.cyan))
          readonly property bool on: ed.accentKind === ac.modelData
          width: 30
          height: 30
          radius: height / 2
          color: ac.ink
          border.width: ac.on ? 2 : 1
          border.color: ac.on ? Zenon.white : Zenon.wash(0.25)
          // what each one is: the theme's (restore), the picture's (an
          // image), yours (a palette — the picker opens on it)
          Text {
            anchors.centerIn: parent
            text: ac.modelData === "" ? "\u{F099B}" : ac.modelData === "accent" ? "\u{F02E9}" : "\u{F03D8}"
            color: Art.hexToHsv(ac.ink).v > 0.6 ? "#000000" : "#ffffff"
            opacity: 0.85
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(14)
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: ed.tips !== null
            onContainsMouseChanged: if (ed.tips) containsMouse
              ? ed.tips.show(ac, ({ "": "The theme's own",
                                    accent: "This picture's color",
                                    custom: ed.accentKind === "custom" ? "Choose the color" : "A color of your own" })[ac.modelData])
              : ed.tips.hide(ac)
            onClicked: {
              if (ac.modelData === "custom" && ed.accentKind === "custom") ed.editColor("accent");
              else ed.accentChosen(ac.modelData === "" ? "" : ac.ink);
            }
          }
          Ring { on: ed.kbRow === "accent" && ac.on; radius: width / 2 }
        }
      }

      // a hairline between the colors and the tool
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 18
        color: Zenon.border
      }

      // off the screen: a tool, not a swatch — a ring with the eyedropper
      Rectangle {
        id: dropper
        width: 30
        height: 30
        radius: height / 2
        color: dropMa.pressed ? Zenon.pressWash(0.14) : dropMa.containsMouse ? Zenon.wash(0.1) : "transparent"
        border.width: 1
        border.color: Zenon.wash(0.25)
        Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        Text {
          anchors.centerIn: parent
          text: "\u{F020A}"
          color: Zenon.accentSoft
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(15)
        }
        MouseArea {
          id: dropMa
          anchors.fill: parent
          hoverEnabled: true
          onContainsMouseChanged: if (ed.tips) containsMouse
            ? ed.tips.show(dropper, "Picker") : ed.tips.hide(dropper)
          onClicked: ed.pickAccent()
        }
      }
    }
    Item { width: 1; height: ed.showAccent ? 2 : 0 }

    Text {
      text: "Reset look"
      color: resetMa.pressed || ed.kbRow === "reset" ? Zenon.cyan : Zenon.accentSoft
      font.family: Zenon.face
      font.weight: 600
      font.pixelSize: Zenon.px(14)
      MouseArea {
        id: resetMa
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        onClicked: ed.resetLook()
      }
      Ring { on: ed.kbRow === "reset" }
    }
  }
}
