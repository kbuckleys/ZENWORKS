// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
.pragma library
// ONE COPY FOR THE WHOLE SHELL (see morpheus/icons.js).
//
// GRIDNAV — where the selection goes on an arrow key, in a list or a grid.
//
// A list is a grid one column wide. Rows fill left to right, so the last row
// can be short: moving down into it keeps the column where it can and lands
// on the row's last item where it cannot, and left/right wrap within the
// row they are in. Up and down wrap around the ends. This was worked out
// again in artemis, folio, zeus, cynosure, lexi, ideo and picasso; the
// popups keep only which list they move in and how it scrolls to follow.
//
// Every function takes the selection and the item count and returns the
// new selection; `len` is at least 1 (the callers return on an empty list).

// a step that wraps around the ends: last + 1 is the first
function wrap(sel, delta, len) {
  return ((sel + delta) % len + len) % len;
}

// inside 0..len-1, and 0 when there is nothing
function clamp(sel, len) {
  return len <= 0 ? 0 : Math.max(0, Math.min(sel, len - 1));
}

// a row up or down, wrapping; the column kept, or the short last row's end
function vert(sel, delta, len, cols) {
  const rows = Math.ceil(len / cols);
  const col = sel % cols;
  const row = wrap(Math.floor(sel / cols), delta, rows);
  const rowLen = row === rows - 1 ? len - row * cols : cols;
  return row * cols + Math.min(col, rowLen - 1);
}

// a column left or right, wrapping inside the row
function horiz(sel, delta, len, cols) {
  const start = sel - sel % cols;
  const rowLen = Math.min(cols, len - start);
  return start + wrap(sel % cols, delta, rowLen);
}

