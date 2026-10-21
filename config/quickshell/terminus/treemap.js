// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL (see morpheus/icons.js).
//
// THE SPACE MAP'S LAYOUT (2026-10-21): a directory's entries as rectangles,
// each as big as what it takes up — the squarified treemap of Bruls, Huizing
// and van Wijk (2000): rows of tiles laid along the short side, a row closed
// the moment adding one more would make its worst tile less square. Tiles
// come out near square, which is what lets two of them be compared by eye.
//
// Pure: values in, rectangles out — oracle/tests/treemap.js checks it.

// The worst aspect ratio in a row of areas laid along a side `side` long.
function worst(row, side) {
  let s = 0, mx = 0, mn = Infinity;
  for (const r of row) { s += r; if (r > mx) mx = r; if (r < mn) mn = r; }
  if (s <= 0 || mn <= 0) return Infinity;
  const ss = side * side;
  return Math.max(ss * mx / (s * s), (s * s) / (ss * mn));
}

// values: numbers, any order. → [{ i, x, y, w, h }] with i the value's own
// index; zero and negative values get no tile.
function squarify(values, x, y, w, h) {
  const idx = [];
  for (let i = 0; i < (values || []).length; ++i) if (values[i] > 0) idx.push(i);
  idx.sort((a, b) => values[b] - values[a]);
  const out = [];
  if (idx.length === 0 || w <= 0 || h <= 0) return out;
  let total = 0;
  for (const i of idx) total += values[i];
  const scale = (w * h) / total;
  const rect = { x: x, y: y, w: w, h: h };
  let row = [], rowIdx = [];
  const lay = () => {
    let s = 0;
    for (const r of row) s += r;
    if (rect.w >= rect.h) {
      // a column down the left
      const cw = s / rect.h;
      let yy = rect.y;
      for (let k = 0; k < row.length; ++k) {
        const hh = row[k] / cw;
        out.push({ i: rowIdx[k], x: rect.x, y: yy, w: cw, h: hh });
        yy += hh;
      }
      rect.x += cw;
      rect.w -= cw;
    } else {
      // a row across the top
      const rh = s / rect.w;
      let xx = rect.x;
      for (let k = 0; k < row.length; ++k) {
        const ww = row[k] / rh;
        out.push({ i: rowIdx[k], x: xx, y: rect.y, w: ww, h: rh });
        xx += ww;
      }
      rect.y += rh;
      rect.h -= rh;
    }
    row = [];
    rowIdx = [];
  };
  for (const i of idx) {
    const a = values[i] * scale;
    const side = Math.min(rect.w, rect.h);
    if (row.length === 0 || worst(row.concat([a]), side) <= worst(row, side)) {
      row.push(a);
      rowIdx.push(i);
    } else {
      lay();
      row.push(a);
      rowIdx.push(i);
    }
  }
  if (row.length) lay();
  return out;
}

// The entries a map shows: the biggest `max`, and the rest as one tile
// ("123 smaller items") so a directory of thousands is still a picture.
// items: [{ key, value, … }] → the same, plus perhaps { key: "rest",
// value, count, rest: true }.
function capItems(items, max) {
  const m = Math.max(1, max || 60);
  const live = (items || []).filter((it) => it && it.value > 0).sort((a, b) => b.value - a.value);
  if (live.length <= m) return live;
  const keep = live.slice(0, m - 1);
  let sum = 0;
  for (const it of live.slice(m - 1)) sum += it.value;
  return keep.concat([{ key: "rest", value: sum, count: live.length - (m - 1), rest: true }]);
}

// what each tile has room to say: "name" and "size" (two lines), the name
// only, or nothing (a sliver)
function labelFit(w, h) {
  if (w >= 64 && h >= 40) return 2;
  if (w >= 40 && h >= 20) return 1;
  return 0;
}
