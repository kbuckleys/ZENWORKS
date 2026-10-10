// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE LAST SCREENFULS STAY DECODED. The pool is on disk, but Qt keeps only a
// couple of megabytes of decoded pictures nobody is showing — so a tile made
// again (a scroll back, split mode re-laying a grid, a pane switched off and
// on) read its thumbnail off the disk once more and faded in again:
// thumbnails that "rebuilt" though they came from the cache (user,
// 2026-10-08).
//
// So the pooled thumbnails a grid has shown are held here, the newest `cap`
// of them, each by an Image never drawn — the same source and the same
// sourceSize as the tile's (Thumbs.size()), which is how Qt shares ONE
// decode between them. A remade tile is Ready on the frame it is made, and
// a Ready-at-once picture is not faded. At most `cap` thumbnails (≤ 480 px a
// side) per keeper. Shared by terminus' grid (Thumbnails) and picasso's
// gallery (picasso/Thumb.qml's `kept`).
//
//     ThumbKeeper { id: keeper }      keeper.keep(image.source)

import QtQuick
import "../morpheus/thumbs.js" as Thumbs

Item {
  id: keeper
  visible: false
  property int cap: 160
  property var kept: ({})
  ListModel { id: keepList }
  function keep(url) {
    const u = String(url);
    if (u === "" || keeper.kept[u]) return;
    keeper.kept[u] = true;
    keepList.append({ u: u });
    while (keepList.count > keeper.cap) {
      delete keeper.kept[keepList.get(0).u];
      keepList.remove(0);
    }
  }
  Repeater {
    model: keepList
    delegate: Image {
      required property string u
      visible: false
      asynchronous: true
      source: u
      sourceSize.width: Thumbs.size()
      sourceSize.height: Thumbs.size()
    }
  }
}
