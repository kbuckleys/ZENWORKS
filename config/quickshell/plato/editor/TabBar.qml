// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The tabs: one per open buffer — the suite's strip (morpheus/TabStrip,
// lifted out of this file 2026-10-18), fed plato's buffers.
//
// A TAB IS A BUFFER. nvim keeps the open files, which one is showing and which
// have unsaved changes; the ORDER is plato's (EditorState.tabOrder), since
// nvim's cannot be rearranged. Closing a tab with unsaved changes is refused
// by nvim, and says so in the status line.
//
// Hidden while there is only one buffer: a single tab is just the window, and
// a strip saying so is a strip of nothing.
//
// What it reads of plato: `tabs`, `moveTab`, `tabOrderChanged`, `bufShow`,
// `bufClose`.
import QtQuick
import "../../morpheus"
import "../../terminus/terminus.js" as Terminus
import "../../morpheus/icons.js" as Icons

TabStrip {
  id: tabBar
  required property var ed
  required property var client

  // each buffer with its file's glyph and ink, as a terminus listing row
  // wears them (Terminus.glyphOf / inkKeyOf, by name)
  tabs: tabBar.ed.tabs.map((b) => {
    const f = { name: String(b.name || ""), isDir: false };
    return Object.assign({}, b, { glyph: Terminus.glyphOf(f, Icons), glyphInk: Zenon[Terminus.inkKeyOf(f)] });
  })
  tipText: (t) => t.path || "New file — unsaved"
  onPicked: (id) => tabBar.client.bufShow(id)
  onClosed: (id) => tabBar.client.bufClose(id, false)
  onMoved: (from, to) => tabBar.ed.moveTab(from, to)

  Connections {
    target: tabBar.ed
    function onTabOrderChanged() { tabBar.endDrag(); }
  }
}
