.pragma library
// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
.import "hypr.js" as Hypr
// ONE COPY FOR THE WHOLE SHELL (see morpheus/icons.js).
//
// ROOM — A WINDOW THAT WIDENS FOR A PANEL, AND GIVES IT BACK.
//
//   const room = Room.make(win, mons, wantW, 16, minW, "left");
//   if (room) Room.dispatches(win.address, room).forEach((d) => Hyprland.dispatch(d));
//
// Splitting a floating window asks for more room; unsplitting hands it back,
// and a sidebar shown or hidden does the same (terminus' split and sidebar,
// plato's tree, minerva's sidebar).
// Quickshell cannot resize a mapped window (implicitWidth is read once, at
// birth), so hyprland does it: these work out the numbers from its own json.
//
// `win` is `hyprctl -j activewindow`, `mons` is `hyprctl -j monitors`. The
// answer is { dw, dx }, a relative resize no wider than the monitor's
// usable area and the relative move that goes with it — or null when there is
// nothing to do: tiled, fullscreen or maximized windows are the layout's to
// size, not ours.
//
// ── IT GROWS FROM THE EDGE THE NEW THING IS ON, NOT FROM ITS MIDDLE ──────
// `edge` is the side being added or taken away: "left" for a sidebar, which
// moves the left edge and leaves the content where it was on screen;
// "right" for the split, which opens beside it. The window used to be
// centered after every resize, wherever you had put it. Now it stays put —
// unless growing would carry it past the monitor's usable area, and then it
// is pushed back inward just as far as it must be. Shrinking never moves
// what stays.
//
// Hyprland resizes a floating window about its CENTER (its default floating
// algorithm's resizeTarget), so the move makes up that half as well, and
// overshot by it before. Both are offsets, so they add up the same whichever
// lands first — the two dispatches are two requests, and an absolute move
// that beat the resize there was shifted by it afterwards.
//
// A monitor's width and height are its mode, before rotation and scale; its
// `reserved` is [left, top, right, bottom], the bar's share of it.
function make(win, mons, wantW, margin, minW, edge) {
  if (!win || !win.floating || win.fullscreen || !win.size) return null;
  const mon = (mons || []).find((m) => m.id === win.monitor);
  if (!mon) return null;
  const turned = (mon.transform || 0) % 2 === 1;
  const scale = mon.scale > 0 ? mon.scale : 1;
  const lw = (turned ? mon.height : mon.width) / scale;
  const r = mon.reserved || [0, 0, 0, 0];
  const left = mon.x + r[0] + margin;
  const right = mon.x + lw - r[2] - margin;
  const w = win.size[0];
  // Never past the monitor when growing — but a window you already made
  // wider than that by hand is not shrunk by a grow either.
  let newW = Math.min(wantW, Math.max(right - left, w));
  newW = Math.round(Math.max(newW, minW || 0));
  // EVEN, ALWAYS. Hyprland grows a floating window about its center (Δ/2
  // each side) and the move that pins the edge is whole pixels: an odd Δ
  // left half a pixel over on every grow and every give-back, and a window
  // toggled a dozen times walked right across the screen (plato's tree did).
  if ((newW - w) % 2) newW -= newW > w ? 1 : -1;
  if (newW === w) return null;
  const dw = newW - w;
  const x = win.at ? win.at[0] : left;
  let newX = edge === "left" ? x - dw : x;
  if (dw > 0) {
    if (newX + newW > right) newX = right - newW;
    if (newX < left) newX = left;
  }
  return { dw: dw, dx: Math.round(newX - (x - dw / 2)) };
}

function dispatches(address, room) {
  const sel = "address:" + address;
  const out = [Hypr.resizeBy(room.dw, 0, sel)];
  if (room.dx) out.push(Hypr.moveBy(room.dx, 0, sel));
  return out;
}
