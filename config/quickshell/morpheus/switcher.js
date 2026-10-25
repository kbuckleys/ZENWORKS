// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
.pragma library
// THE WINDOW SWITCHER'S PURE HALF (morpheus/WindowSwitcher.qml): the order
// the windows stand in, and where a step lands. No Quickshell here, so
// oracle/tests/switcher.js can pin all of it.
//
// The order is most recently used first, as macOS and Windows keep it: the
// window you are in is first, the one you came from second — so one tap of
// the keys goes back to it, and holding on goes further back in time.

// the address moved to the front, once
function touch(mru, address) {
  const a = String(address || "");
  if (a === "") return mru || [];
  return [a].concat((mru || []).filter((x) => x !== a));
}

// the order at login, from Hyprland's own focus history:
// [{ address, history }] with history 0 the focused window, -1 unknown
function seed(pairs) {
  return (pairs || [])
    .filter((p) => p && p.address && Number(p.history) >= 0)
    .sort((a, b) => Number(a.history) - Number(b.history))
    .map((p) => String(p.address));
}

// the windows ([{ address, … }]) in that order; ones it has never seen
// after them, in the order given
function ordered(windows, mru) {
  const rank = {};
  (mru || []).forEach((a, i) => { rank[a] = i; });
  const known = [], unknown = [];
  for (const w of windows || []) {
    if (String(w.address) in rank) known.push(w);
    else unknown.push(w);
  }
  known.sort((a, b) => rank[String(a.address)] - rank[String(b.address)]);
  return known.concat(unknown);
}

// where the first press lands: forward is the window before this one,
// back is the oldest
function firstStop(dir, count) {
  if (count <= 1) return 0;
  return dir < 0 ? count - 1 : 1;
}

// a step from `at`, wrapping round
function stepFrom(at, dir, count) {
  if (count <= 0) return 0;
  return ((at + (dir < 0 ? -1 : 1)) % count + count) % count;
}
