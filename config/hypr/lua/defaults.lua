-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- DEFAULTS
-- Written by oracle's Default Apps section, and read back by it: change
-- one there or here, either way works.
--
-- terminal   the command the binds run; oracle also puts its entry first
--            in xdg-terminals.list, which terminal applications open in
-- browser    a desktop id, for Super+B and $BROWSER
-- editor     a command, for $EDITOR and $VISUAL
-- sysmon     "zeus", a command run in the terminal, or a desktop id
-- image_editor  a desktop id, offered in picasso as Edit in …
--
-- Every line after those is a kind of file and the desktop id that opens
-- it; oracle hands it to `gio mime`, so the whole desktop agrees.
-- "" leaves that one to the system.

return {
	terminal     = "kitty",
	browser      = "",
	editor       = "plato",
	sysmon       = "zeus",
	image_editor = "",

	mail         = "",
	files        = "terminus.desktop",
	text         = "",
	images       = "",
	video        = "",
	audio        = "",
	documents    = "",
	office       = "",
	archives     = "",
	torrents     = "",
	calendar     = "",
	fonts        = "",
}
