// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Arrow keys in a list or a grid (morpheus/gridnav.js), checked against the
// arithmetic each popup used to carry, over every selection, step and shape.

"use strict";

module.exports = {
  module: "morpheus/gridnav.js",
  cases: (N, t) => {
    // the popups' own versions, verbatim in their arithmetic
    const oldVert = (sel, delta, len, cols) => {        // artemis/folio
      const rows = Math.ceil(len / cols), row = Math.floor(sel / cols), col = sel % cols;
      let newRow = (row + delta) % rows;
      if (newRow < 0) newRow += rows;
      const rowValid = newRow === rows - 1 ? len - newRow * cols : cols;
      return newRow * cols + Math.min(col, rowValid - 1);
    };
    const oldHoriz = (sel, delta, len, cols) => {       // artemis/folio
      const row = Math.floor(sel / cols), col = sel % cols, rowStart = row * cols;
      const rowLen = Math.min(cols, len - rowStart);
      const newCol = (col + delta) % rowLen;
      return rowStart + (newCol < 0 ? newCol + rowLen : newCol);
    };
    const oldWrap = (sel, delta, len) => (sel + delta + len) % len;   // cynosure
    const oldClamp = (sel, len) => {                     // artemis/folio
      if (len === 0) return 0;
      if (sel >= len) return len - 1;
      if (sel < 0) return 0;
      return sel;
    };
    let bad = [];
    for (let len = 1; len <= 13; ++len)
      for (let cols = 1; cols <= 5; ++cols)
        for (let sel = 0; sel < len; ++sel)
          for (const d of [-1, 1]) {
            if (N.vert(sel, d, len, cols) !== oldVert(sel, d, len, cols)) bad.push(["vert", len, cols, sel, d]);
            if (N.horiz(sel, d, len, cols) !== oldHoriz(sel, d, len, cols)) bad.push(["horiz", len, cols, sel, d]);
            if (N.wrap(sel, d, len) !== oldWrap(sel, d, len)) bad.push(["wrap", len, sel, d]);
          }
    t.eq("vert, horiz and wrap agree with the popups' old arithmetic everywhere", bad.length, 0, bad.slice(0, 5));

    bad = [];
    for (let len = 0; len <= 6; ++len)
      for (let sel = -3; sel <= 9; ++sel)
        if (N.clamp(sel, len) !== oldClamp(sel, len)) bad.push([len, sel]);
    t.eq("clamp agrees with the old clampSel", bad.length, 0, bad.slice(0, 5));

    // the shapes, by hand: 7 items in 3 columns is rows [0 1 2] [3 4 5] [6]
    t.eq("down from the middle of a full row into the short last one lands on its end", N.vert(4, 1, 7, 3), 6);
    t.eq("down from the short last row wraps to the top, same column", N.vert(6, 1, 7, 3), 0);
    t.eq("up from the top wraps into the short last row", N.vert(2, -1, 7, 3), 6);
    t.eq("right in the short last row stays put", N.horiz(6, 1, 7, 3), 6);
    t.eq("right off a row's end wraps to its start", N.horiz(5, 1, 7, 3), 3);
    t.eq("a list is a grid one wide: down is the next one", N.vert(3, 1, 7, 1), 4);
    t.eq("wrap takes a step longer than the list", N.wrap(1, -9, 4), 0);
    t.eq("clamp of an empty list is 0", N.clamp(5, 0), 0);
  }
};
