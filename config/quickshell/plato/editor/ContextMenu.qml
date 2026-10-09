// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The editor's right-click menu: morpheus' CardPopup, the same card every
// menu in the shell is.
//
// What is on it depends on what you clicked with. With a selection: what
// can be done to that text — copy, cut, comment, case, sort, search for it,
// and FORK, which copies it into a new unsaved tab in the same language (a
// scratch copy to take apart without touching the original). Without one:
// the word under the click — the language server's verbs — and the file's
// own (copy its path, or path:line to paste into a chat or an issue).
//
// Everything is done by nvim, as keys or as a request: the menu only names
// the things you would otherwise type, with the keys beside them so it
// teaches them too.
//
// PUT AWAY by a click anywhere outside it (morpheus' InputShield over the
// whole window, so the click is not also a click in the text) or by Esc —
// the card is its own surface and never has the keyboard, so the keys are
// caught here while it is up, and any other key closes it too.

import QtQuick
import Quickshell
import "../../morpheus"
import "actions.js" as Actions

Item {
  id: menu

  required property var ed
  required property var client
  property var ctx: null
  property var window: null

  readonly property bool visual: menu.ed.modeName === "visual"
  readonly property string path: menu.ed.file.replace(/^~/, Quickshell.env("HOME"))

  readonly property var selectionItems: [
    { text: "Copy", icon: "\u{F018F}", mark: "y", run: () => menu.client.input("y") },
    { text: "Cut", icon: "\u{F0190}", mark: "d", run: () => menu.client.input("d") },
    { text: "Paste over", icon: "\u{F0192}", mark: "P", run: () => menu.client.input("P") },
    { isSeparator: true },
    { text: "Fork to a new tab", icon: "\u{F0641}", run: () => menu.client.request("fork", {}) },
    { text: "Search for this", icon: "\u{F0349}", mark: "*", run: () => menu.client.input("*") },
    { text: "A cursor on each line", icon: "\u{F05E7}",
      run: () => menu.client.cmd("lua require('multicursor-nvim').visualToCursors()") },
    { text: "Cursors at every match", icon: "\u{F05E7}",
      run: () => menu.client.cmd("lua require('multicursor-nvim').matchAllAddCursors()") },
    { isSeparator: true },
    { text: "Toggle comment", icon: "\u{F0182}", mark: "gc", run: () => menu.client.input("gc") },
    { text: "Indent", icon: "\u{F0276}", mark: ">", run: () => menu.client.input(">") },
    { text: "Outdent", icon: "\u{F0275}", mark: "<", run: () => menu.client.input("<") },
    { text: "Reindent", icon: "\u{F0C2D}", mark: "=", run: () => menu.client.input("=") },
    { text: "UPPER CASE", icon: "\u{F0B26}", mark: "U", run: () => menu.client.input("U") },
    { text: "lower case", icon: "\u{F0B23}", mark: "u", run: () => menu.client.input("u") },
    { text: "Sort lines", icon: "\u{F04BB}", run: () => menu.client.input(":sort<CR>") },
    { text: "Join lines", icon: "\u{F0C8C}", mark: "J", run: () => menu.client.input("J") },
  ]
  readonly property var cursorItems: [
    { text: "Paste", icon: "\u{F0192}", mark: "p", run: () => menu.client.input("p") },
    { text: "Select all", icon: "\u{F0486}", mark: "ggVG", run: () => menu.client.input("ggVG") },
    { text: "Fork this line", icon: "\u{F0641}", run: () => menu.client.request("fork", {}) },
    { text: "New blank tab", icon: "\u{F0415}", mark: "space n", run: () => menu.client.cmd("enew") },
    { isSeparator: true },
    { text: "Peek definition", icon: "\u{F0208}", mark: "space l p",
      run: () => { if (menu.ctx) menu.ctx.peek(); } },
    { text: "Go to definition", icon: "\u{F05D8}", mark: "space l d",
      run: () => menu.client.cmd("lua vim.lsp.buf.definition()") },
    { text: "References", icon: "\u{F0CDB}", mark: "space l R",
      run: () => menu.client.cmd("lua require('plato.peek').references()") },
    { text: "Rename symbol", icon: "\u{F0CB5}", mark: "space l r",
      run: () => menu.client.cmd("lua vim.lsp.buf.rename()") },
    { text: "Code action", icon: "\u{F0336}", mark: "space l a",
      run: () => menu.client.cmd("lua vim.lsp.buf.code_action()") },
    { text: "Search for this word", icon: "\u{F0349}", mark: "*", run: () => menu.client.input("*") },
    { text: "Toggle comment", icon: "\u{F0182}", mark: "gcc", run: () => menu.client.input("gcc") },
    { isSeparator: true },
    { text: "Copy path", icon: "\u{F506}", enabled: menu.path !== "",
      run: () => Quickshell.execDetached(["wl-copy", menu.path]) },
    { text: "Copy path:line", icon: "\u{F506}", enabled: menu.path !== "",
      run: () => Quickshell.execDetached(["wl-copy", menu.path + ":" + menu.ed.line]) },
    { text: "Reveal in file tree", icon: "\u{F0645}", mark: "| r", enabled: menu.path !== "",
      run: () => { if (menu.ctx) menu.ctx.revealInTree(); } },
  ]

  property var items: []
  // the menu went away, chosen from or not: the keyboard goes back
  signal closed()

  function open(x, y) {
    menu.items = menu.visual ? menu.selectionItems : menu.cursorItems;
    card.at = menu.mapToItem(null, x, y);
    card.open = true;
    catcher.forceActiveFocus();
  }
  function close() {
    if (!card.open) return;
    card.open = false;
    menu.closed();
  }

  InputShield {
    parent: menu.window ? menu.window.contentItem : menu
    anchors.fill: parent
    visible: card.open
    z: 1000
    onClicked: menu.close()
  }
  Item {
    id: catcher
    Keys.onPressed: (event) => {
      event.accepted = true;
      menu.close();
    }
  }

  CardPopup {
    id: card
    window: menu.window
    fit: true
    cardWidth: 240
    model: menu.items.map((it) => it.isSeparator ? { isSeparator: true }
      : { text: it.text, icon: it.icon, hint: it.mark || "", enabled: it.enabled !== false })
    onChosen: (i) => {
      menu.close();
      const it = menu.items[i];
      if (it && it.run && it.enabled !== false) it.run();
    }
  }
}
