import QtQuick
import QtTest
import "stubs"

// The same bar on its side, as picasso's filmstrip wears it: a sideways
// ListView with margins, whose contentX starts at -leftMargin rather than 0.
Item {
  id: root
  width: 900; height: 200

  ListView {
    id: strip
    anchors.fill: parent
    orientation: ListView.Horizontal
    leftMargin: 10
    rightMargin: 10
    spacing: 6
    clip: true
    model: 40
    delegate: Item { width: 100; height: strip.height }
  }

  Scrollbar {
    id: bar
    flick: strip
    horizontal: true
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
  }

  TestCase {
    name: "ScrollbarHorizontal"
    when: windowShown

    function test_lies_along_the_bottom() {
      verify(bar.scrollable);
      compare(bar.height, bar.thickness + bar.grabPad);
      compare(bar.width, root.width);
    }

    function home() { strip.contentX = strip.originX - strip.leftMargin; }

    function test_starts_at_the_left_margin() {
      home();
      compare(bar.thumbY, 0, "the thumb is at the start");
      strip.contentX = strip.originX;
      verify(bar.thumbY > 0, "the margin counts as scrolled past");
    }

    function test_drag_moves_the_strip() {
      home();
      const p = bar.mapToItem(root, 20, bar.height - 6);
      mousePress(root, p.x, p.y);
      for (var dx = 20; dx <= 200; dx += 20) mouseMove(root, p.x + dx, p.y);
      const offset = (20 + 200) - bar.thumbY;
      mouseRelease(root, p.x + 200, p.y);
      verify(strip.contentX > strip.originX);
      verify(Math.abs(offset - 20) <= 1, "the grab point drifted by " + Math.round(offset - 20) + "px");
    }

    function test_end_is_reachable() {
      const p = bar.mapToItem(root, bar.width - 2, bar.height - 6);
      mousePress(root, p.x, p.y);
      mouseRelease(root, p.x, p.y);
      compare(Math.round(strip.contentX + strip.width),
              Math.round(strip.originX + strip.contentWidth + strip.rightMargin),
              "the last tile and its margin are in view");
      compare(Math.round(bar.thumbY + bar.thumbH), Math.round(bar.width));
    }
  }
}
