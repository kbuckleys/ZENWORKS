// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// UNDO AND REDO, as snapshots. Clio's page, Clio's sketch pad and Picasso's
// marks each kept their own pair of lists and their own pop-and-push, and the
// Ceres search wanted a fourth (user, 2026-10-18). This is that pair, once:
//
//     UndoStack { id: history }
//     history.record(state)            // BEFORE a change: the state it leaves
//     const s = history.undo(current)  // the state to go back to, or undefined
//     const s = history.redo(current)  // the state to go forward to, or undefined
//
// A state is whatever the holder says it is — a string, an array of strokes,
// a page of blocks. It is kept as handed over, so hand over a copy, or an
// array the holder never mutates in place (the holders here replace theirs).
//
// JOINING: record(state, true) is a change that continues the last one — a
// letter typed after a letter, a keystroke within a second of the last — so
// no new step is made; the step already open still goes back to before all of
// it. An undo, a redo or a clear closes the step, so the next change after
// one is always a step of its own.
//
// In a directory of its own so a live reload finds it (a new morpheus/qmldir
// line needs a restart): import "../morpheus/undo".

import QtQuick

QtObject {
  id: stack

  // the most steps kept; the oldest go first
  property int limit: 200
  property var past: []
  property var future: []
  readonly property bool canUndo: stack.past.length > 0
  readonly property bool canRedo: stack.future.length > 0
  property bool _open: false

  function record(state, joins) {
    if (joins && stack._open && stack.past.length > 0) return;
    stack.past = stack.past.concat([state]).slice(-stack.limit);
    stack.future = [];
    stack._open = true;
  }
  function undo(current) {
    stack._open = false;
    if (stack.past.length === 0) return undefined;
    const s = stack.past[stack.past.length - 1];
    stack.past = stack.past.slice(0, -1);
    stack.future = stack.future.concat([current]);
    return s;
  }
  function redo(current) {
    stack._open = false;
    if (stack.future.length === 0) return undefined;
    const s = stack.future[stack.future.length - 1];
    stack.future = stack.future.slice(0, -1);
    stack.past = stack.past.concat([current]).slice(-stack.limit);
    return s;
  }
  function clear() {
    stack.past = [];
    stack.future = [];
    stack._open = false;
  }
}
