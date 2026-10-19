// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' how each directory likes … logic, out of TerminusWindow.qml
// (2026-10-08). The state stays on the window (term); the window keeps a
// one-line forwarder for each function here, so callers are unchanged.

import QtQuick
import Quickshell
import "terminus.js" as Terminus
import "../morpheus/lru.js" as Lru

Item {
  id: viewPrefs
  property var term: null

  function rememberView() {
    // ── A RESULTS PAGE IS NOT A DIRECTORY ──────────────────────────────
    // cwd is still wherever you were standing when you opened a collection
    // or a tag, so every one of these writes was landing on THAT directory's
    // remembered view. Switching a collection to grid quietly rearranged
    // the directory you had left, and you found out the next time you
    // walked into it.
    //
    // A collection keeps its own instead — it is a list you made, and how
    // you want it read is a fact about it. A tag page and a plain search
    // keep nothing: there is no record to hang it on, and guessing at one
    // is how this went wrong in the first place.
    if (term.searchMode !== "") {
      if (term.applyingDirView || term.applyDepth > 0) return;
      // -1 is "none open"; an id is a number (one you made) or a string
      // ("builtin:recents", a search's "search:…") — `>= 0` was false for
      // every string, so Recents never remembered its view (2026-10-11)
      if (term.searchMode === "collection" && term.collOpenId !== -1)
        term.rememberCollectionView();
      else if (term.searchMode === "tag")
        term.rememberTagView();
      // find and grep keep nothing: a search is typed once and gone, and
      // there is no record to hang a preference on.
      return;
    }
    if (!term.perDirView) return;
    // isPicker as well as picking — a dialog must not teach this machine how
    // any directory wants to be sorted. See isPicker for why both.
    if (term.applyingDirView || term.cwd === ""
        || term.picking || term.isPicker) return;
    const m = term.dirViews;
    // The SORT travels with the view, and for the same reason the view does:
    // how a directory wants to be read is a fact about the directory. A source tree
    // sorts by name and a downloads directory sorts by date, and having to say so
    // again every time you walk in is the window forgetting something you have
    // already told it twice.
    // ── THE GRID'S ZOOM ONLY WHEN IT WAS THE GRID BEING ZOOMED ──────────
    // A record is rewritten whenever anything about the directory changes
    // (its sort, its view), and it used to take the grid zoom along every
    // time — whatever the last grid had been left at — so directories never
    // zoomed in the grid came back as large tiles (user, 2026-10-11). Now
    // the zoom is kept only while the directory is in the grid, and an
    // earlier choice survives a change made in another view.
    const was = m[term.cwd];
    const rec = { view: term.viewMode, zoom: term.zoom,
                  sort: term.sortKey, desc: term.sortDesc };
    if (term.viewMode === "grid") rec.thumbZoom = term.thumbZoom;
    else if (was && was.thumbZoom !== undefined) rec.thumbZoom = was.thumbZoom;
    // kept, and the oldest let go past the cap: morpheus/lru.js, picasso's too
    const r = Lru.remember(m, term.dirViewOrder, term.cwd, rec, term.dirViewCap);
    term.dirViews = r.map;
    term.dirViewOrder = r.order;
    term.viewSaveRef.restart();
  }
  // Every directory's remembered view, sort and zoom, forgotten at once.
  //
  // The per-directory memory is a convenience that quietly accumulates: three
  // hundred directories, each insisting on the arrangement you gave it once
  // months ago. There was no way to say "start again" short of deleting the
  // preferences file, which takes the bookmarks and the tabs with it.
  //
  // What is on screen is left alone. Forgetting how this directory liked to be
  // read is not a reason to rearrange it while you are looking at it — the
  // next visit is when the difference should show.
  // Brought down to the cap when the cap comes down. Without this, moving the
  // slider left recorded a smaller number and kept every entry already over
  // it — the setting would only bite on the next directory visited.
  function trimDirViews() {
    const r = Lru.trim(term.dirViews, term.dirViewOrder, term.dirViewCap);
    term.dirViews = r.map;
    term.dirViewOrder = r.order;
    term.viewSaveRef.restart();
  }
  function forgetDirViews() {
    term.dirViews = ({});
    term.dirViewOrder = [];
    term.viewSaveRef.restart();
    // and the one you are looking at goes to the default too, when there
    // is one — that is what resetting views means (user, 2026-10-17)
    if (term.defaultView !== "" && term.viewRing.indexOf(term.defaultView) >= 0) {
      term.setView(term.defaultView);
      term.status = "views reset to " + term.defaultView;
    } else term.status = "remembered views cleared";
  }
  function applyDirView() {
    if (!term.perDirView) return;
    // Already inside something terminus is doing to itself — a pane exchange, a
    // tab load — so the directory's own preference is not what is wanted.
    if (term.applyDepth > 0) return;
    const v = term.dirViews[term.cwd];
    // No record, or none that chose a grid zoom: the grid starts at its
    // default — the smallest tile — not at the last directory's size.
    if (!v || !(Number(v.thumbZoom) > 0)) {
      term.applyDepth++;
      term.act.zoom = term.thumbZoomDefault;
      term.applyDepth--;
    }
    if (!v) {
      // a directory with no view of its own takes the default, when one
      // is chosen (otherwise it keeps the last directory's)
      if (term.defaultView !== "" && term.viewRing.indexOf(term.defaultView) >= 0) {
        term.applyDepth++;
        term.act.viewMode = term.defaultView;
        term.applyDepth--;
      }
      return;
    }
    term.applyDepth++;
    if (term.viewRing.indexOf(v.view) >= 0) term.act.viewMode = v.view;
    const z = Number(v.zoom);
    if (!isNaN(z) && z > 0) term.zoom = term.zoomClamp(z);
    const tz = Number(v.thumbZoom);
    if (!isNaN(tz) && tz > 0) term.act.zoom = term.zoomClamp(tz);
    // Older records have no sort in them, and a missing answer must not be
    // read as "name ascending" — that would quietly re-sort every directory
    // remembered before this existed.
    if (typeof v.sort === "string" && v.sort !== "") term.sortKey = v.sort;
    if (typeof v.desc === "boolean") term.sortDesc = v.desc;
    term.applyDepth--;
  }
}
