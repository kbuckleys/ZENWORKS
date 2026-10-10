-- guess-indent.nvim: each file's indentation read from the file itself —
-- tabs or spaces, and how many — so editing someone else's two-space file
-- does not add four-space lines to it. Plato's settings (tab width, spaces
-- or tabs) are what a new or unclear file gets. The status line shows what
-- the file got; a click there changes it.
-- Run by plato after the plugin loads; edit freely (plato's plugin panel,
-- "configure", opens this file).
require("guess-indent").setup({ auto_cmd = true, override_editorconfig = false })
