pragma Singleton
import QtQuick
QtObject {
  readonly property color muted: "#6a707f"
  readonly property color cyan: "#9bbfbf"
  readonly property color keyInk: "#a2a8bc"
  readonly property color border: Qt.rgba(0.271, 0.314, 0.361, 0.3)
  readonly property color menuHi: Qt.rgba(0.608, 0.749, 0.749, 0.16)
  readonly property int fast: 110
  readonly property int ease: Easing.OutQuint
  property bool scrollAutohide: true
  readonly property int slow: 170
  readonly property int normal: 140
  readonly property int brisk: 75
  readonly property int elastic: 420
  // oracle's "Elastic scrolling", on as it ships
  readonly property bool elasticScroll: true
  // the menu card's, for CardBody (values as morpheus/Zenon has them)
  readonly property color white: "#dfdfdd"
  readonly property color red: "#e78284"
  readonly property string face: "JetBrainsMono Nerd Font Propo"
  readonly property int weight: 600
  readonly property color menuBg: "#000000"
  readonly property color menuShadowInk: "#000000"
  readonly property int menuRadius: 6
  readonly property int menuRowHeight: 30
  readonly property int menuSepHeight: 7
  readonly property int menuCardPad: 4
  readonly property int menuIconGap: 12
  readonly property int menuMaxHeight: menuRowHeight * 22 + 2
  readonly property int menuShadowGrow: 4
  readonly property int menuShadowBlur: 24
  readonly property int menuShadowDrop: 6
  readonly property int menuShadowPad: menuShadowGrow + menuShadowBlur + menuShadowDrop
  function menuScale(t) { return 1; }
  // what the real CardBody and ChosenFlash ask of Zenon since the 10-19/10-20
  // polish (type through px, motion through ms, the accent grey): missing
  // here, every QML test run wrote TypeErrors into the journal (Hestia showed
  // them, 2026-10-21) though the tests themselves passed
  function px(n) { return Math.max(1, Math.round(n)); }
  function ms(n) { return Math.round(n); }
  readonly property color accentMuted: muted
}
