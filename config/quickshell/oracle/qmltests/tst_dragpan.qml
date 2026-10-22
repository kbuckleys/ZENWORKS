import QtQuick
import QtTest
import "stubs"

// morpheus/DragPan: a plain drag pans a zoomed-in view; a shift drag is left
// to the content's own handler (minerva's PDF selects text); nothing pans
// while the view fits
Item {
  id: root
  width: 600; height: 400

  Flickable {
    id: flick
    anchors.fill: parent
    interactive: false
    contentWidth: wide ? 1600 : 600
    contentHeight: 2000
    property bool wide: true
    DragPan { id: pan; flick: flick; on: flick.wide }
    Rectangle {
      width: flick.contentWidth; height: flick.contentHeight
      color: "white"
      DragHandler {
        id: sel
        target: null
        acceptedModifiers: flick.wide ? Qt.ShiftModifier : Qt.KeyboardModifierMask
        property bool used: false
        onActiveChanged: if (active) used = true
      }
    }
  }

  TestCase {
    name: "DragPan"
    when: windowShown

    function drag(mods) {
      mousePress(root, 300, 200, Qt.LeftButton, mods);
      for (let i = 1; i <= 10; ++i) mouseMove(root, 300 - 12 * i, 200 - 8 * i, -1, Qt.LeftButton, mods);
      mouseRelease(root, 180, 120, Qt.LeftButton, mods);
    }
    function init() { flick.contentX = 400; flick.contentY = 400; sel.used = false; flick.wide = true; }

    function test_plain_drag_pans() {
      drag(Qt.NoModifier);
      console.log("   pan ->", flick.contentX, flick.contentY);
      compare(flick.contentX, 520, "the page follows the hand, the threshold included");
      compare(flick.contentY, 480);
      verify(!sel.used, "the selection stays out of it");
    }
    function test_shift_drag_selects() {
      drag(Qt.ShiftModifier);
      compare(flick.contentX, 400);
      compare(flick.contentY, 400);
      verify(sel.used, "the selection has it");
    }
    function test_fitted_does_not_pan() {
      flick.wide = false;
      flick.contentX = 0;
      drag(Qt.NoModifier);
      compare(flick.contentY, 400);
      verify(sel.used, "a plain drag selects at fit");
    }
    // the user's presses come from a touchpad (device type TouchPad, not
    // Mouse): a handler that left it out showed the hand and never panned.
    // A synthetic press is always the core mouse, so this checks the list.
    function test_touchpad_accepted() {
      const hs = pan.data.filter((o) => o.acceptedDevices !== undefined);
      verify(hs.length > 0);
      for (const h of hs) verify(h.acceptedDevices & PointerDevice.TouchPad, "every handler takes the touchpad");
    }
    function test_clamped() {
      flick.contentX = 1000;
      drag(Qt.NoModifier);
      compare(flick.contentX, 1000, "no further than the content");
    }
  }
}
