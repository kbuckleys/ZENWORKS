// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Past an edge the list STRETCHES (morpheus/Elastic's `stretch`, the
// Android overscroll the user chose over the rubber band, 2026-10-12): the
// content is scaled from that edge and held to it — the first row never
// slides off the top — and the settle brings it back to no stretch at all.
import QtQuick
import QtTest
import "stubs"

Item {
  id: root
  width: 400; height: 400

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    model: 40
    delegate: Rectangle { width: list.width; height: 50; objectName: "row" + index }
  }
  Elastic { id: elastic }

  function rowTop(i) {
    for (const c of list.contentItem.children)
      if (c.objectName === "row" + i) return c.mapToItem(root, 0, 0).y;
    return NaN;
  }

  TestCase {
    name: "Stretch"
    when: windowShown

    // each from rest: the list at its top, nothing in flight, the edge's
    // one answer not yet spent
    function init() {
      elastic.halt(list);
      list.positionViewAtBeginning();
      elastic.spent = false;
      elastic.atTop = true;
      wait(50);
    }

    function test_past_the_top_it_stretches_and_holds() {
      elastic.scroll(list, -400);
      tryVerify(() => list.contentY < -5, 1000, "the wheel asked past the top");
      const t = list.contentItem.transform;
      verify(t.length === 2, "the list was given its stretcher");
      verify(t[0].yScale > 1.01, "stretched: " + t[0].yScale);
      verify(t[0].yScale <= 1 + elastic.stretch * 0.1 + 0.001, "no further than the band's cap: " + t[0].yScale);
      fuzzyCompare(rowTop(0), 0, 0.5, "the first row is held to the top, not slid off it");
      tryVerify(() => Math.abs(t[0].yScale - 1) < 0.001 && list.contentY === 0, 2500, "and it settles back");
    }

    function test_past_the_bottom_it_stretches_upward() {
      list.positionViewAtEnd();
      wait(50);
      const end = list.contentY;
      elastic.scroll(list, 400);
      tryVerify(() => list.contentY > end + 5, 1000, "the wheel asked past the bottom");
      const t = list.contentItem.transform;
      verify(t[0].yScale > 1.01, "stretched: " + t[0].yScale);
      compare(t[0].origin.y, end + list.height, "from the bottom edge");
      tryVerify(() => Math.abs(t[0].yScale - 1) < 0.001, 2500, "and it settles back");
    }
  }
}
