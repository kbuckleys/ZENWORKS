// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The menu card past its cap: xkb's ninety-nine layouts in a card eighteen
// rows tall. It must scroll on the wheel, open on the marked row, and a
// click must still land on the row under the pointer once it has scrolled.
import QtQuick
import QtTest
import "stubs"

Item {
  id: root
  width: 400; height: Zenon.menuMaxHeight + 40

  function rows(n, marked) {
    const out = [];
    for (let i = 0; i < n; ++i) out.push({ text: "Layout " + i, mark: i === marked });
    return out;
  }

  property int picked: -1

  CardBody {
    id: card
    width: 320
    height: Zenon.menuMaxHeight + 20
    pad: 10
    model: root.rows(99, 70)
    onChosen: (i) => root.picked = i
  }

  // the row the pointer would be over, at a y on the card's surface
  function rowAt(y) {
    return Math.floor((y - card.pad - Zenon.menuCardPad + card.scrollY) / Zenon.menuRowHeight);
  }

  TestCase {
    name: "CardBody"
    when: windowShown

    // New rows take a frame to be ready for a click — in use there are many
    // between a card opening and the pointer reaching it; here, one.
    function load(n, marked) {
      card.model = root.rows(n, marked);
      card.reveal();
      waitForRendering(card);
    }

    function init() {
      load(99, 70);
      root.picked = -1;
    }

    function test_opens_on_its_answer() {
      verify(card.scrollY > 0, "scrolled down to the marked row");
      const top = 70 * Zenon.menuRowHeight;
      const view = Zenon.menuMaxHeight - Zenon.menuCardPad * 2;
      verify(top >= card.scrollY && top + Zenon.menuRowHeight <= card.scrollY + view,
             "the marked row is in view: " + card.scrollY);
    }

    function test_no_mark_opens_at_the_top() {
      load(99, -1);
      compare(card.scrollY, 0);
    }

    function test_a_card_that_fits_does_not_move() {
      load(5, 4);
      compare(card.scrollY, 0);
    }

    function test_the_wheel_scrolls_it() {
      load(99, -1);
      mouseWheel(card, 160, 200, 0, -120);
      tryVerify(() => card.scrollY > 0, 2000, "a notch down moved it");
      const was = card.scrollY;
      mouseWheel(card, 160, 200, 0, 120);
      tryVerify(() => card.scrollY < was, 2000, "and a notch up brought it back");
    }

    function test_a_click_unscrolled() {
      load(99, -1);
      mouseClick(card, 160, card.pad + Zenon.menuCardPad + Zenon.menuRowHeight * 2 + 10);
      tryCompare(root, "picked", 2, 2000);
    }

    function test_a_click_after_scrolling_lands_on_its_row() {
      // scrolled to row 70's neighbourhood by reveal; click the middle
      const y = card.height / 2;
      const want = root.rowAt(y);
      verify(want > 18, "a row from past the first screenful: " + want);
      mouseClick(card, 160, y);
      tryCompare(root, "picked", want, 2000);
    }
  }
}
