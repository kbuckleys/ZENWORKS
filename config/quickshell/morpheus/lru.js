.pragma library
// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A MEMORY WITH A CAP — a record per key (a directory, mostly), kept in the
// order last touched, the oldest let go past `cap`. Terminus' per-directory
// view and sort (ViewPrefs) and Picasso's per-directory sort keep theirs
// through this, so the two remember the same way (user, 2026-10-19: "make
// each dir remember its sort state — just like terminus").
//
//   const r = Lru.remember(map, order, dir, record, 300);
//   obj.map = r.map; obj.order = r.order;     // new objects: bindings see it

function remember(map, order, key, value, cap) {
  const m = Object.assign({}, map || {});
  const o = (order || []).filter(function (k) { return k !== key; });
  o.push(key);
  m[key] = value;
  return trim(m, o, cap);
}

function trim(map, order, cap) {
  const m = Object.assign({}, map || {});
  const o = (order || []).slice();
  while (o.length > Math.max(0, cap)) delete m[o.shift()];
  return { map: m, order: o };
}
