// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// READING ALOUD (user, 2026-10-21): the book, a sentence at a time, from
// where the view is — an EPUB's or a text's sentence lit as it is spoken,
// a PDF's page turned as it is done. espeak-ng speaks (offline, small, in
// [extra]); a machine without it is offered it through Ceres the first
// time. One espeak-ng per sentence, so stopping is stopping it, and the
// pace (settings.speakRate) is its words a minute.
//
// A comic has no words to read.

import QtQuick
import Quickshell.Io
import "../ceres"
import "minerva.js" as M

Item {
  id: vo
  property var win: null
  readonly property var page: vo.win ? vo.win.page : null
  readonly property bool can: !!vo.page && vo.page.ready && vo.win.kind !== "comic"

  property bool on: false
  property bool paused: false
  property bool known: false
  property bool ready: false
  signal said(string text, bool bad)

  // the words being read and the sentences in them
  property string text: ""
  property var queue: []
  property int at: 0
  property int pdfPage: 0

  Process {
    running: true
    command: ["sh", "-c", "command -v espeak-ng >/dev/null"]
    onExited: (code) => { vo.ready = code === 0; vo.known = true; }
  }
  function install(then) {
    if (Ceres.installing !== null || Ceres.txBusy) { vo.said("Ceres is busy — try again in a moment", true); return; }
    Ceres.install(["espeak-ng"], "for reading aloud in Minerva", (ok) => {
      vo.ready = ok;
      vo.said(ok ? "Ready to read aloud" : "espeak-ng was not installed", !ok);
      if (ok && then) then();
    });
  }

  function toggle() { if (vo.on) vo.stop(); else vo.start(); }
  function start() {
    if (!vo.can) return;
    if (!vo.ready) { vo.install(() => vo.start()); return; }
    vo.on = true;
    vo.paused = false;
    vo.load(true);
  }
  function stop() {
    vo.on = false;
    vo.paused = false;
    voice.running = false;
    if (vo.page && vo.page.light) vo.page.light(0, 0);
  }
  function pause() {
    if (!vo.on) return;
    vo.paused = !vo.paused;
    // the sentence starts again on the way back
    if (vo.paused) voice.running = false; else vo.next();
  }
  // a sentence either way
  function skip(d) {
    if (!vo.on) return;
    vo.at = Math.max(0, vo.at + d);
    vo.paused = false;
    // the one speaking is let go, and its exit starts the new one
    if (voice.running) { vo.again = true; voice.running = false; } else vo.next();
  }
  property bool again: false

  // the words from here: a PDF's page, or the chapter from the view's top
  function load(fromView) {
    const p = vo.page;
    if (!p) { vo.stop(); return; }
    if (p.paged) {
      vo.pdfPage = p.where.page;
      vo.text = p.pageText(vo.pdfPage);
      vo.queue = M.sentences(vo.text);
    } else {
      vo.text = p.plainText();
      const from = fromView ? p.topPos() : 0;
      vo.queue = M.sentences(vo.text).filter((s) => s.end > from);
    }
    vo.at = 0;
    vo.next();
  }
  function next() {
    if (!vo.on || vo.paused) return;
    if (vo.at >= vo.queue.length) { vo.onward(); return; }
    const s = vo.queue[vo.at];
    if (!vo.page.paged) vo.page.light(s.start, s.end);
    voice.command = ["espeak-ng", "-s", String(Math.round(175 * (vo.win.settings.speakRate || 1))), "--",
                     vo.text.slice(s.start, s.end)];
    voice.running = true;
  }
  // the page or the chapter done: the next one, or the end
  function onward() {
    const p = vo.page;
    if (p.paged) {
      if (vo.pdfPage >= p.pageCount - 1) { vo.stop(); vo.said("The end of the book", false); return; }
      p.goTo({ page: vo.pdfPage + 1 });
      vo.pdfPage++;
      vo.text = p.pageText(vo.pdfPage);
      vo.queue = M.sentences(vo.text);
      vo.at = 0;
      vo.next();
      return;
    }
    if (p.where.chapter >= p.pageCount - 1) { vo.stop(); vo.said("The end of the book", false); return; }
    vo.waitChapter = true;
    p.chapterBy(1);
  }
  property bool waitChapter: false
  Connections {
    target: vo.page
    ignoreUnknownSignals: true
    function onChapterShown() { if (vo.waitChapter && vo.on) { vo.waitChapter = false; vo.load(false); } }
  }
  // the book closed or changed under it
  onPageChanged: if (vo.on) vo.stop()

  Process {
    id: voice
    onExited: {
      if (vo.again) { vo.again = false; vo.next(); return; }
      if (vo.on && !vo.paused) { vo.at++; vo.next(); }
    }
  }
}
