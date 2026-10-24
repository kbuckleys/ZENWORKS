// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A GLYPH FOR EVERY ROW OF TERMINUS' MENUS (user, 2026-10-15), by its
// words: one table here rather than a glyph written into each of the menus
// that build rows (RowMenu, the crumbs' in Opening, the sidebar's, the
// disks'). A row that brings its own `glyph` keeps it — the sort menu's
// tick, Open with's app marks — even an empty one. A row the table does not
// know is drawn with an empty glyph, so its words still line up.
//
// Material Design glyphs (nf-md), looked up by name in Alexandria's
// glyphnames.json, not guessed.

.pragma library

const exact = {
  "Open": "\u{F0770}",                       // folder_open
  "Open directory": "\u{F0770}",
  "Open in new tab": "\u{F075C}",            // tab_plus
  "New tab": "\u{F075C}",
  "Close tab": "\u{F0156}",                  // close
  "Close": "\u{F0156}",
  "Open with": "\u{F003B}",                  // apps
  "Choose program": "\u{F003B}",
  "Add another…": "\u{F0614}",          // application_outline
  "Open terminal here": "\u{F018D}",         // console
  "Quick look": "\u{F0208}",                 // eye
  "Go to…": "\u{F0969}",                // folder_search_outline
  "Paste path and go": "\u{F19EF}",          // folder_arrow_right_outline
  "Go to containing directory": "\u{F19EF}",
  "Step into other pane": "\u{F0054}",       // arrow_right
  "Back": "\u{F004D}",                       // arrow_left
  "Cut": "\u{F0190}",                        // content_cut
  "Copy": "\u{F018F}",                       // content_copy
  "Copy path": "\u{F018F}",
  "Copy full path": "\u{F018F}",
  "Copy name": "\u{F018F}",
  "Copy device path": "\u{F018F}",
  "Copy mount point": "\u{F018F}",
  "Copy to": "\u{F018F}",
  "Copy here": "\u{F018F}",
  "Copy to other pane": "\u{F018F}",
  "Move to": "\u{F1031}",                    // file_move_outline
  "Move here": "\u{F1031}",
  "Move to other pane": "\u{F1031}",
  "Paste here": "\u{F0192}",                 // content_paste
  "Paste as symlink": "\u{F0339}",           // link_variant
  "Paste as hard link": "\u{F1178}",         // file_link_outline
  "Make symlink": "\u{F0339}",
  "Duplicate": "\u{F0191}",                  // content_duplicate
  // the batch rename card's own mark, so one rename reads as the same act
  // as many (user, 2026-10-17)
  "Rename": "\u{EC61}",
  "Trash": "\u{F0A7A}",                      // trash_can_outline
  "Empty the trash": "\u{F00E2}",            // broom
  "Empty trash…": "\u{F00E2}",
  "Restore": "\u{F099B}",                    // restore
  "New directory": "\u{F0257}",              // folder_plus
  "New directory with selection": "\u{F0257}",
  "New file": "\u{F0EED}",                   // file_plus_outline
  "New collection": "\u{F0B9F}",             // folder_star_outline
  "Select all": "\u{F0486}",                 // select_all
  "Sort by": "\u{F04BA}",                    // sort
  "Ascending": "\u{F04BC}",                  // sort_ascending
  "Descending": "\u{F04BD}",                 // sort_descending
  "View": "\u{F0570}",                       // view_grid
  "List": "\u{F0572}",                       // view_list
  "Grid": "\u{F0570}",
  "Columns": "\u{F056D}",                    // view_column
  "Hidden files": "\u{F0208}",               // eye
  "Hide hidden files": "\u{F06D1}",          // eye_off_outline
  "Split view": "\u{F0BCC}",                 // view_split_vertical
  "Second pane": "\u{F0BCC}",
  "Close second pane": "\u{F0BCC}",
  "Swap sides": "\u{F04E1}",                 // swap_horizontal
  "Sidebar": "\u{F10AA}",                    // dock_left
  "Hide sidebar": "\u{F10AA}",
  "Group headings": "\u{F1860}",             // format_list_group
  "Hide group headings": "\u{F1860}",
  "Disk usage": "\u{F07AF}",                 // chart_donut
  "Leave disk usage": "\u{F07AF}",
  "Git status": "\u{F02A2}",                 // git
  "Leave git status": "\u{F02A2}",
  "Calculate size": "\u{F00EC}",             // calculator
  "Info": "\u{F064E}",                       // information_variant
  "Tag": "\u{F04FC}",                        // tag_outline
  "Tags": "\u{F12F7}",                       // tag_multiple_outline
  "Manage tags": "\u{F12F7}",
  "Reindex tags": "\u{F1634}",               // database_refresh_outline
  "Bookmark": "\uF461",                       // oct-bookmark (user, 2026-10-24)
  "Bookmark this directory": "\uF461",
  "Add to bookmarks": "\uF461",
  "Remove bookmark": "\uF47A",           // oct-bookmark_fill: it is one
  "Archive": "\u{F120E}",                    // archive_outline
  "Extract here": "\u{F1259}",               // archive_arrow_down
  "Extract audio": "\u{F0387}",              // music_note
  "Convert to": "\u{F0B33}",                 // file_replace_outline
  "Set as background": "\u{F02E9}",          // image
  "Annotate": "\u{F090C}",                   // square_edit_outline
  "Quick edit": "\u{F0190}",                 // content_cut
  "Rotate left": "\u{F0465}",                // rotate_left
  "Rotate right": "\u{F0467}",               // rotate_right
  "Install font": "\u{F06D6}",               // format_font
  "Open in Delphi": "\u{F062C}",             // source_branch
  "History in Delphi": "\u{F062C}",
  "Who wrote this": "\u{F0FFB}",             // account_edit_outline
  "Stage": "\u{F012C}",                      // check
  "Unstage": "\u{F0156}",
  "Discard changes": "\u{F01FE}",            // eraser
  "Revert": "\u{F01FE}",
  "Mount": "\u{F02CA}",                      // harddisk
  "Unmount": "\u{F01EA}",                    // eject
  "Safely remove": "\u{F01EA}",
  "Check and repair…": "\u{F0BE0}",     // wrench_outline
  "Format…": "\u{F01FE}",
  "Settings": "\u{F0493}",                   // cog
  "Keys & commands": "\u{F097B}"             // keyboard_outline
};

// the rows whose words change with what they are about
const prefixes = [
  ["Undo", "\u{F054C}"],                     // undo
  ["Rename", "\u{EC61}"],                    // "Rename (9)"
  ["Background on", "\u{F02E9}"],
  ["Bookmark", "\uF461"],
  ["Remove bookmark", "\uF47A"],
  ["Open ", "\u{F0770}"],
  ["Close ", "\u{F0156}"]
];

function of(item) {
  if (!item || item.sep || item.swatch) return "";
  if (item.glyph !== undefined) return String(item.glyph || "");
  const l = String(item.label || "");
  if (l in exact) return exact[l];
  for (const p of prefixes) if (l.startsWith(p[0])) return p[1];
  return "";
}

// the bookmark wears the theme's accent wherever it is drawn (user,
// 2026-10-24); the menus ask this for the color of a row's glyph
function accented(item) {
  const g = of(item);
  return g === "\uF461" || g === "\uF47A";
}
