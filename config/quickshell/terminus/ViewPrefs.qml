// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' how each directory likes … logic, out of TerminusWindow.qml
// (2026-10-08). The state stays on the window (term); the window keeps a
// one-line forwarder for each function here, so callers are unchanged.

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import "../morpheus"
import "../picasso"
import "../oracle"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

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
      if (term.searchMode === "collection" && term.collOpenId >= 0)
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
    const o = term.dirViewOrder.slice();
    if (m[term.cwd] === undefined) o.push(term.cwd);
    // The SORT travels with the view, and for the same reason the view does:
    // how a directory wants to be read is a fact about the directory. A source tree
    // sorts by name and a downloads directory sorts by date, and having to say so
    // again every time you walk in is the window forgetting something you have
    // already told it twice.
    m[term.cwd] = { view: term.viewMode, zoom: term.zoom,
                    thumbZoom: term.thumbZoom,
                    sort: term.sortKey, desc: term.sortDesc };
    while (o.length > term.dirViewCap) delete m[o.shift()];
    term.dirViews = m;
    term.dirViewOrder = o;
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
    const m = term.dirViews;
    const o = term.dirViewOrder.slice();
    while (o.length > term.dirViewCap) delete m[o.shift()];
    term.dirViews = m;
    term.dirViewOrder = o;
    term.viewSaveRef.restart();
  }
  function forgetDirViews() {
    term.dirViews = ({});
    term.dirViewOrder = [];
    term.viewSaveRef.restart();
    term.status = "remembered views cleared";
  }
  function applyDirView() {
    if (!term.perDirView) return;
    // Already inside something terminus is doing to itself — a pane exchange, a
    // tab load — so the directory's own preference is not what is wanted.
    if (term.applyDepth > 0) return;
    const v = term.dirViews[term.cwd];
    if (!v) return;
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
