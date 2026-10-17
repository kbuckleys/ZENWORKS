// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// FOCUSRETRY — asking for the keyboard until it is had.
//
// A surface that has just mapped is not given the keyboard on the frame it
// asks: the compositor hands it over a few frames later, and a
// forceActiveFocus() before then lands nowhere. So the ask is repeated every
// 60ms, up to a dozen times, until whatever should hold the keys does. This
// Timer was written out in nine windows; each now says only what to focus
// (onPlace) and how to tell that it took (took).
//
// begin() starts a fresh run of asks; restart() carries on the count.

import QtQuick

Timer {
  id: root

  // false once the window is going away: the asking stops with it
  property bool live: true
  // true once the right item holds the keyboard
  property bool took: false
  property int counter: 0

  // put the keyboard where it belongs, once per ask
  signal place()

  interval: 60
  repeat: true

  function begin() {
    root.counter = 0;
    root.restart();
  }

  onTriggered: {
    if (!root.live) {
      root.stop();
      return;
    }
    root.place();
    if (root.took) root.stop();
    if (root.counter++ > 12) root.stop();
  }
}
