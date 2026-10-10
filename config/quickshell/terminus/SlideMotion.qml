// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' the slide … logic, out of TerminusWindow.qml
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
  id: slide
  property var term: null
  readonly property alias archSweep: archSweep

  function millerRotate(down) {
    const o = term.millerOrder;
    term.millerOrder = down ? [o[1], o[2], o[0]] : [o[2], o[0], o[1]];
  }
  // A QUARTER of the pane, not a third. Distance is the other half of how
  // tight a move feels: the same duration over less ground reads as
  // controlled, and over more ground as a swing. Far enough to still say
  // which way the tree went.
  function startTravel(down) {
    term.millerAnimRef.stop();
    term.millerFadeRef.stop();
    term.chromeRef.miller.x = (down ? 1 : -1) * Math.round(term.chromeRef.millerBox.width * term.millerTravel);
    term.chromeRef.miller.opacity = term.millerDim;
    term.millerAnimRef.start();
    term.millerFadeRef.start();
    // The animator is running now, so millerAnim.running does the guarding
    // from here. This flag only ever covered the tick between the step and
    // this call — clearing it anywhere later would deadlock resumePreview,
    // which is the one thing that ends a slide.
    term.stepping = false;
  }
  function millerStep(from, to) {
    if (term.viewMode !== "columns" || from === "" || from === to) return;
    const down = to.indexOf(from === "/" ? "/" : from + "/") === 0;
    const up = from.indexOf(to === "/" ? "/" : to + "/") === 0;
    if (!down && !up) return;

    // THE COLUMNS CHANGE SEATS. Walking down, the preview becomes the middle
    // and the middle becomes the parent; walking up, the other way. Only the
    // far column is handed a directory it has never held, so the other two
    // sync against rows they already have and find nothing to do.
    //
    // Ahead of everything else in enter(): the cwd and the seed have not
    // moved yet, so no column has been told about the new directory. Rotate
    // afterwards and the column about to leave the middle would rebuild
    // itself for the new listing and then rotate away from it.
    // WHAT THE KEEPING COLUMNS ARE ABOUT, said before they are asked.
    //
    // Rotating is only half of it. A column's rows are bound BY SLOT, so the
    // one moving out of the middle immediately re-reads whichever source its
    // new slot names — and at this instant those sources still describe the
    // old position. Walking up, the column carrying the directory we are
    // leaving lands in the preview slot and reads previewRows, which is still
    // the child it was showing a moment ago: it would rebuild to the wrong
    // rows and then rebuild again when the real answer arrived.
    //
    // The directory being left is in hand right now, so the source is told
    // first and the binding finds the rows already there. The confirming pass
    // behind it writes the same thing and the diff finds nothing to do.
    const leaving = (term.act.view || []).slice();
    term.millerRotate(down);
    if (down) {
      term.parentRows = leaving;
    } else {
      term.previewRows = leaving;
      term.previewKind = "dir";
      // It IS showing this directory, so refreshPreview has nothing to ask
      // for and previewFade has no change of subject to announce.
      term.previewShown = from;
    }

    // ── THE SLIDE STARTS WITH THE COLUMNS, NOT AHEAD OF THEM ────────────
    // Setting the offset here put the travel on the frame BEFORE the columns
    // had taken their new seats. Caught on a capture: one frame showed the
    // OLD arrangement — parent, current and preview exactly as they were —
    // displaced bodily by a quarter of a pane, and the next frame snapped
    // into the new arrangement at a different offset. The whole tree leaping
    // sideways and back is the flicker that replaced the stale-rows one.
    //
    // Queued BEHIND the columns' own sync, which is a callLater queued a
    // moment ago by the rotation above, so the seats, the rows and the offset
    // all land on the same frame. By function reference rather than a closure
    // so that two quick steps coalesce to one travel, in the direction of the
    // second.
    term.stepping = true;
    Qt.callLater(term.startTravel, down);
  }
  // WHERE THE CURSOR WAS ASKED TO GO once the rows are actually in.
  //
  // Pulled out of the listing handler because rows now arrive two ways: from
  // the `find` behind a refresh, and from the peek the miller preview had
  // already taken of the directory you were about to step into. Going back UP
  // is the case that showed it — goUp arms wantSel with the directory you are
  // leaving so the cursor lands back on it, and a seeded arrival drew the rows
  // without ever consulting it.
  //
  // SPENT ONLY WHEN IT LANDS. It used to be cleared the moment any listing
  // arrived, found or not — and the listing that arrives first is very often
  // the one that raced a creation and does not have the new file in it yet.
  // The landing was thrown away, the rename opened on whatever row the cursor
  // happened to be on, and the new file sat there under its generic name. That
  // was the "sometimes" in inline creation. Left armed, the next listing takes
  // it, and there is always a next one: inotify fires when the file appears
  // and the command runner refreshes when it exits.
  function landWanted() {
    if (term.wantSel === "") return false;
    const want = term.wantSel;
    let at = -1;
    // through the pane, not the proxy — landWanted is called in the same
    // statement run that wrote the rows, and the proxy is one evaluation
    // behind there. See currentRow.
    const v = term.act.view;
    for (let i = 0; i < v.length; ++i)
      if (v[i].path === want) { at = i; break; }
    if (at < 0) return false;
    term.wantSel = "";
    term.act.sel = at;
    term.setAnchor(at);
    // Something just made: land on it, flash it, and open the name for
    // editing — the second half of `a`, once the row it is about exists.
    if (want === term.freshPath) {
      term.madePulse++;
      term.renamePath = want;
      term.renaming = true;
    }
    return true;
  }
  function goTo(path) {
    // ── A RESULTS PAGE IS NOT THE DIRECTORY UNDERNEATH IT ─────────────
    // cwd stays wherever you were when the page was opened: a collection
    // or a search is drawn OVER the listing, not instead of it. So this
    // early return was asking about cwd while the question was about the
    // screen, and the bookmark for the directory you opened the
    // collection from did nothing at all until you pressed Escape — which
    // is the usual case, because you open Recents from somewhere and that
    // somewhere is the bookmark that stops working.
    //
    // Asking for the directory a results page is covering means "put it
    // away", which is what Escape means — and clearSearch is what knows
    // how, with the cursor, the view mode and the zoom it restores. A
    // plain re-entry would drop all three.
    if (path === term.cwd) {
      if (term.searchMode !== "") term.clearSearch();
      return;
    }
    term.pushTrail(path);
    term.enter(path);
  }
  // Finder's ⌘R, and this window needs it more than Finder does. A tag
  // page, a collection, Recents, a find and a grep are all lists of files
  // drawn from everywhere at once — that is the point of them — and the
  // WHERE column tells you the directory as a fact you cannot act on. This
  // is the verb that acts on it: go to that directory, with the cursor on
  // the file you were looking at.
  //
  // Useful in a plain listing too, on a row inside an expanded branch: the
  // tree shows a file three levels down without ever having gone there.
  function reveal() {
    const r = term.currentRow();
    if (!r) { term.warn("nothing to reveal"); return; }
    const dir = Terminus.dirname(r.path);
    if (dir === "" || dir === r.path) {
      term.warn("no enclosing directory");
      return;
    }
    // ORDER MATTERS. A results page is drawn over a directory, and putting
    // it away restores the cursor it was opened from — wantSel and all —
    // so an aim taken before this one would be the one that got thrown
    // away. Same reason goTo has to ask clearSearch rather than re-enter.
    if (term.searchMode !== "") term.clearSearch();
    term.wantSel = r.path;
    // Already standing in it — which is the expanded-branch case, and the
    // case where a results page was covering its own directory. Nothing to
    // travel to, so the aim is taken here; if the listing is not up yet it
    // stays armed and the next one takes it.
    if (dir === term.cwd) { term.landWanted(); return; }
    term.goTo(dir);
  }
  // goTo is every navigation you asked for; enter is the move itself. The
  // split was already here — enter's own note says it is "what back and
  // forward use" — with nothing yet on the other side of it. This is that.
  //
  // The FIRST push seeds the pane's current directory as well, because a
  // trail that starts at the second place you visited cannot take you to the
  // first.
  // What the cursor is on, remembered against the directory being left.
  function markTrailSel() {
    const p = term.act;
    // Keyed by the PLACE — see root.here — so a collection remembers the
    // row you were on in it, the way a directory always has.
    const ref = term.here;
    if (ref === "") return;
    const r = term.currentRow();
    const m = p.trailSel;
    m[ref] = r ? r.path : "";
    p.trailSel = m;
  }
  function pushTrail(path) {
    const p = term.act;
    term.markTrailSel();
    const t = p.trailAt < 0 ? [] : p.trail.slice(0, p.trailAt + 1);
    if (t.length === 0 && term.here !== "") t.push(term.here);
    if (t.length > 0 && t[t.length - 1] === path) return;
    t.push(path);
    // A wall you cannot see the end of is a leak. Two hundred is more places
    // than anybody walks back through, and the oldest is the least missed.
    while (t.length > 200) t.shift();
    p.trail = t;
    p.trailAt = t.length - 1;
  }
  // SAYS SO WHEN THERE IS NOWHERE TO GO. These were silent at the ends of
  // the trail, which was fine while the keys that carried them were H and L —
  // a shifted letter you press deliberately. They are h, l and the arrows now,
  // which is the pair a hand reaches for by reflex, and a key that does
  // nothing and says nothing reads as a key that is not bound.
  // The one place that knows how to arrive at a trail entry, whichever
  // kind it is. enter() for a directory, the collection itself otherwise —
  // and NOT goToCollection, for the reason back() gives about enter:
  // walking the trail is not a new place to record.
  function travelTo(ref) {
    if (String(ref).indexOf("c:") !== 0) { term.enter(ref); return; }
    // ── THE ID SURVIVES THE ROUND TRIP, WHICHEVER KIND IT IS ────────
    // A collection you made is keyed by Date.now(), a number; the built-in
    // by the string "builtin:recents". Both become text in the trail, and
    // collById compares with ===, so handing back the wrong type finds
    // nothing. Asking collById which form it knows is exact — guessing
    // from isNaN would turn a string id that happens to be digits into a
    // number and lose it.
    const id = String(ref).slice(2);
    term.openCollection(term.collById(id) !== null ? id : Number(id));
  }
  function back() {
    if (!term.canBack) { term.warn("nothing to go back to"); return; }
    const p = term.act;
    term.markTrailSel();
    p.trailAt -= 1;
    term.aimAt(p.trail[p.trailAt]);
    // travelTo, not goTo: walking the trail is not a new place to record,
    // and recording it would make forward unreachable the moment you used
    // back.
    term.travelTo(p.trail[p.trailAt]);
  }
  function forward() {
    if (!term.canForward) { term.warn("nothing to go forward to"); return; }
    const p = term.act;
    term.markTrailSel();
    p.trailAt += 1;
    term.aimAt(p.trail[p.trailAt]);
    term.travelTo(p.trail[p.trailAt]);
  }
  // Armed BEFORE the move, because landWanted runs against the rows as they
  // arrive — see its note. Empty is not an answer worth arming: it would
  // clear an aim something else had a better reason to set.
  function aimAt(dir) {
    const want = term.act.trailSel[dir];
    if (want !== undefined && want !== "") term.wantSel = want;
  }
  // the move itself, with no history bookkeeping — what back and forward use
  function enter(path) {
    // An edit belongs to the row it was opened on, and that row is about to
    // stop existing. Not a cancel-with-delete: leaving a directory is not a
    // decision about the thing you were naming, so whatever it is called now
    // is what it keeps.
    if (term.renaming) term.endRename(false);
    // A create still waiting on a branch of the directory being left —
    // see pendingMake.
    term.pendingMake = null;
    term.makeGuardRef.stop();
    term.searchMode = "";
    term.searchQuery = "";
    // Navigating out of results is leaving them behind, not going back: the
    // way back was to where the search STARTED, and you have since gone
    // somewhere on purpose.
    term.searchBackCwd = "";
    term.searchBackSel = "";
    term.millerStep(term.cwd, path);
    // Held across the cursor reset below — see `arriving`. Dropped the
    // instant there are real rows to be about, which is the seed if there is
    // one and the listing if there is not.
    term.arriving = true;
    term.act.lastListing = null;   // a new directory is always a change
    term.act.cwd = path;
    term.act.query = "";
    term.chromeRef.filterField.text = "";
    term.act.marked = {};
    term.act.sel = 0;
    // Already in hand: draw it now and let the refresh behind it agree. The
    // seed is the exact bytes the refresh will return, so it recognises itself
    // and stops — the listing is never built twice.
    const seed = term.listingText[path];
    if (seed !== undefined) {
      term.act.raw = term.enrich(Terminus.parseListing(seed, path));
      // the cursor goes where it was asked to go in the same frame the rows do
      if (term.landWanted()) Qt.callLater(term.positionSel);
    }
    // HELD UNTIL BOTH HAVE SETTLED, then asked once. The rows and the cursor
    // cannot be written in one statement, and each of them on its own is a
    // complete answer to "what is under the cursor" — a wrong one. Going back
    // UP showed it worst: the rows arrive, the cursor is still at the top, so
    // the preview drew row zero of the parent; landWanted then moved it to
    // the directory you came out of and the preview was drawn a second time.
    // Measured at 27ms of the wrong directory, every step.
    term.arriving = false;
    if (term.viewMode === "columns") term.refreshPreview();
    // AND lastListing IS LEFT NULL ON PURPOSE. Marking the seed as the last
    // listing made the confirming `find` recognise itself and return early —
    // which skipped the whole of the handler behind that check, not just the
    // model write: landing the cursor where you asked for it, measuring the
    // directory when the usage mode is on, asking for thumbnails, putting the
    // scroll back. The seed exists to draw the rows a frame sooner, not to
    // stand in for the listing. The confirming pass writes the same rows, and
    // syncView compares them and finds nothing to do.
    term.refresh(true);
  }
  function goUp() {
    // ── A RESULTS PAGE HAS NO PARENT ──────────────────────────────────
    // cwd is whatever the page is covering, so "up" from a collection went
    // to the parent of a directory that is not on screen — an arbitrary
    // jump with no relation to anything you could see. Its rows come from
    // all over; the only honest meaning of outwards is out of the page.
    if (term.searchMode !== "") { term.clearSearch(); return; }
    const from = term.cwd;
    if (from === "/") return;
    // out of an archive's top, the cursor lands on the archive
    const at = Terminus.mountOf(from, term.archMounts);
    term.wantSel = (at && at.mnt === from) ? at.archive : from;
    term.goTo(term.parentOf(from));
  }
  function activate() {
    const r = term.currentRow();
    if (!r) return;
    // ── THE GATE ────────────────────────────────────
    // Only a directory, only into a grid, and only once per open — holdGo
    // re-enters here and must fall straight through.
    if (r.isDir && term.viewMode === "grid" && !term.picking) {
      if (term.openCleared === r.path) {
        term.openCleared = "";
      } else if (term.openHeld) {
        // A hold is already in flight. Falling through here is what a
        // repeated key does, and it went straight past the gate to
        // goTo — so the one press that was being waited for opened
        // anyway, mid-wait, with nothing ready.
        return;
      } else {
        term.openHeld = true;
        term.holdFor = r.path;
        term.splitPaneRef.warmAim.stop();
        term.warmPeek(r.path);
        // Already warm — the usual case, because the cursor was sitting
        // here while you decided. No wait at all.
        if (term.warmShown === r.path && term.warmSettled()) {
          term.holdGo();
          return;
        }
        term.holdPollRef.restart();
        term.holdStopRef.restart();
        return;
      }
    }
    term.openPulse++;
    // A LINK GOES WHERE IT POINTS. Entering one by its own path walked you
    // into ".../proj link/" — a second address for the directory, with the
    // link's parent above it in the crumbs and every path in it spelt
    // through the link — so a symlink felt like a copy rather than a way to
    // somewhere. It is resolved first, and you arrive at the real directory.
    if (r.isDir && r.isLink && !term.picking) { term.followLink(r.path); return; }
    if (r.isDir) { term.goTo(r.path); return; }

    // While a portal request is open, opening a FILE means something else.
    // Handing it to xdg-open would launch an application on top of a dialog
    // the caller is still blocked on — the one thing a picker must not do.
    if (term.picking) {
      if (term.portal.save) {
        // saving: the file you opened is the one you mean to replace, so its
        // name goes in the field and the overwrite is yours to confirm
        term.chromeRef.saveField.text = r.name;
        term.chromeRef.saveField.forceActiveFocus();
      } else {
        term.portalConfirm();
      }
      return;
    }

    // An archive is a place — see enterArchive. Its own application is
    // still one "Open with" away.
    if (Terminus.isArchive(r.name)) { term.enterArchive(r); return; }

    term.openFile(r.path);
  }
  function openFile(path) {
    const p = term.openerProcRef.createObject(term, {
      path: path, command: ["sh", "-c", Terminus.openOrAskCommand(path)]
    });
    if (p) p.running = true;
  }
  function followLink(path) {
    if (linkProc.running) return;
    linkProc.from = path;
    linkProc.command = ["readlink", "-e", "--", path];
    linkProc.running = true;
  }
  Process {
    id: linkProc
    property string from: ""
    stdout: StdioCollector {
      id: linkOut
      waitForEnd: true
      onStreamFinished: {
        const to = String(linkOut.text || "").trim();
        // A link that will not resolve still has its own path to go to,
        // which is at least what entering it used to do.
        term.goTo(to !== "" ? to : linkProc.from);
      }
    }
  }
  function shownPath(dir) { return Terminus.shownPath(dir, term.archMounts); }
  function parentOf(dir) { return Terminus.parentOf(dir, term.archMounts); }
  function enterArchive(r) {
    if (!r) return;
    const mnt = term.archBase + "/" + Qt.md5(r.path);
    if (term.archMounts[mnt] === r.path) { term.goTo(mnt); return; }
    if (archMountProc.running) return;
    archMountProc.mnt = mnt;
    archMountProc.archive = r.path;
    archMountProc.command = ["sh", "-c", Terminus.mountArchiveCommand(r.path, mnt,
      Terminus.terminusCacheDir() + "/archive-index")];
    archMountProc.running = true;
    term.status = "opening " + r.name + "\u2026";
  }
  Process {
    id: archMountProc
    property string mnt: ""
    property string archive: ""
    onExited: (code) => {
      if (code !== 0) {
        // Not something ratarmount can read — a format it has no backend
        // for, or a damaged file. The old answer still stands: hand it to
        // whatever opens it.
        term.status = "could not open " + Terminus.basename(archMountProc.archive)
          + " as a directory";
        term.openFile(archMountProc.archive);
        return;
      }
      const next = Object.assign({}, term.archMounts);
      next[archMountProc.mnt] = archMountProc.archive;
      term.archMounts = next;
      term.status = "";
      term.goTo(archMountProc.mnt);
    }
  }
  // Checked a couple of seconds after the directory changes, so walking
  // out and straight back in does not unmount and remount. A mount is in
  // use while any tab, or the second pane, is standing inside it.
  Timer {
    id: archSweep
    interval: 2000
    onTriggered: {
      const here = [term.cwd, term.otherCwd];
      for (const t of term.tabs) if (t && t.cwd) here.push(t.cwd);
      if (term.tabs[term.tab] && term.tabs[term.tab].otherCwd) here.push(term.tabs[term.tab].otherCwd);
      const next = Object.assign({}, term.archMounts);
      let gone = 0;
      for (const m in term.archMounts) {
        const used = here.some((d) => d === m || String(d).indexOf(m + "/") === 0);
        if (used) continue;
        term.run(Terminus.unmountArchiveCommand(m));
        delete next[m];
        ++gone;
      }
      if (gone > 0) term.archMounts = next;
    }
  }
}
