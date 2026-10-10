import QtQuick
import QtTest
import "stubs"

Item {
  id: root
  width: 900; height: 520

  ListView {
    id: list
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: bar.scrollable ? bar.left : parent.right
    clip: true
    model: 25
    delegate: Item { width: list.width; height: 64 }
  }

  Scrollbar {
    id: bar
    flick: list
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
  }

  TestCase {
    name: "Scrollbar"
    when: windowShown

    function test_target_is_wide() {
      verify(bar.scrollable);
      console.log("   bar width", bar.width, "(painted", bar.thickness,
                  "+ grab", bar.grabPad + ")", "thumbH", bar.thumbH);
      compare(bar.width, 26, "the target is 26px, not 10");
    }

    function test_drag_on_the_painted_line() {
      list.contentY = 0;
      const p = bar.mapToItem(root, bar.width - 6, 20);
      mousePress(root, p.x, p.y);
      mouseMove(root, p.x, p.y + 120);
      mouseRelease(root, p.x, p.y + 120);
      console.log("   drag on the line -> contentY", Math.round(list.contentY));
      verify(list.contentY > 0);
    }

    function test_drag_well_left_of_the_line() {
      list.contentY = 0;
      // 20px left of the right edge: in the grab pad, nowhere near the 6px bar
      const p = bar.mapToItem(root, 4, 20);
      mousePress(root, p.x, p.y);
      mouseMove(root, p.x, p.y + 120);
      mouseRelease(root, p.x, p.y + 120);
      console.log("   drag in the grab pad -> contentY", Math.round(list.contentY));
      verify(list.contentY > 0, "the pad is grabbable too");
    }

    function test_click_the_groove_jumps() {
      list.contentY = 0;
      const p = bar.mapToItem(root, bar.width / 2, bar.height - 40);
      mousePress(root, p.x, p.y);
      mouseRelease(root, p.x, p.y);
      console.log("   click low -> contentY", Math.round(list.contentY));
      verify(list.contentY > 0);
    }

    // THE HOTSPOT. Moving the pointer n pixels must move the thumb n pixels,
    // so whatever part of it you grabbed stays under the cursor. This is the
    // property the old thumb.y-derived drag did not have.
    function test_thumb_stays_under_the_cursor() {
      list.contentY = 0;
      const grabAt = 30;                       // 30px down the thumb
      const p = bar.mapToItem(root, bar.width / 2, grabAt);
      mousePress(root, p.x, p.y);
      for (var dy = 20; dy <= 200; dy += 20) mouseMove(root, p.x, p.y + dy);
      // where the thumb's top is now, versus where the cursor is
      const cursorInBar = grabAt + 200;
      const offset = cursorInBar - bar.thumbY;
      console.log("   grabbed at", grabAt, "into the thumb; after 200px the",
                  "cursor sits", Math.round(offset), "into it");
      mouseRelease(root, p.x, p.y + 200);
      verify(Math.abs(offset - grabAt) <= 1,
             "the grab point drifted by " + Math.round(offset - grabAt) + "px");
    }

    // A dropped event must not leave a permanent error. The old drag kept
    // one forever; an anchored drag corrects itself on the next event.
    function test_survives_a_dropped_event() {
      list.contentY = 0;
      const grabAt = 30;
      const p = bar.mapToItem(root, bar.width / 2, grabAt);
      mousePress(root, p.x, p.y);
      mouseMove(root, p.x, p.y + 40);
      // ... a gap, as if the grab had been interrupted ...
      mouseMove(root, p.x, p.y + 200);
      const offset = (grabAt + 200) - bar.thumbY;
      console.log("   after a gap, the cursor sits", Math.round(offset),
                  "into the thumb");
      mouseRelease(root, p.x, p.y + 200);
      verify(Math.abs(offset - grabAt) <= 1, "drift survived a dropped event");
    }

    function test_wheel_over_the_bar() {
      list.contentY = 0;
      const p = bar.mapToItem(root, bar.width / 2, bar.height / 2);
      mouseWheel(root, p.x, p.y, 0, -120);
      // the notch glides there now (morpheus Elastic): wait for it to land
      tryVerify(() => Math.round(list.contentY) === Math.round(list.height * 0.25), 1000,
                "the default notch is a quarter of the viewport");
      console.log("   wheel down -> contentY", Math.round(list.contentY));
    }

    // A view of tiles sets its own notch so one lands on a row boundary.
    function test_wheel_step_overrides_the_notch() {
      list.contentY = 0;
      bar.wheelStep = 150;
      const p = bar.mapToItem(root, bar.width / 2, bar.height / 2);
      // a while after the last test's notch, so this one is calm (no gain)
      wait(400);
      mouseWheel(root, p.x, p.y, 0, -120);
      tryVerify(() => Math.round(list.contentY) === 150, 1000, "one notch is one row");
      console.log("   wheelStep 150 -> contentY", Math.round(list.contentY));
      bar.wheelStep = 0;
    }

    // Autohide: shown on a scroll, faded once the list has been still, and
    // back under the pointer. Off, always there.
    function test_autohide() {
      mouseMove(root, 10, 10);
      tryVerify(() => bar.opacity === 0, 3000, "asleep to begin with");
      list.contentY = 40;
      verify(bar.awake, "a scroll wakes it");
      compare(bar.opacity, 1, "and it is there at once, no fade in");
      tryVerify(() => !bar.awake, 3000, "still, it goes to sleep");
      verify(bar.opacity > 0.5, "and fades rather than snapping off");
      tryVerify(() => bar.opacity > 0 && bar.opacity < 1, 300, "partway through the fade");
      tryVerify(() => bar.opacity === 0, 1000, "then is gone");
      const p = bar.mapToItem(root, bar.width - 6, bar.height / 2);
      mouseMove(root, p.x, p.y);
      tryVerify(() => bar.awake, 500, "the pointer brings it back");
      mouseMove(root, 10, 10);
      Zenon.scrollAutohide = false;
      tryVerify(() => bar.opacity === 1, 1000, "off, it stays");
      Zenon.scrollAutohide = true;
    }
  }
}
