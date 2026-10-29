-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- WINDOW DEFAULTS
-- The suite's own window rules, as data: rules.lua applies each one that
-- windows.lua does not replace, and oracle's Windows section lists them
-- beside yours. Same fields as windows.lua; `shipped` is the rule's name for
-- good — a rule in windows.lua with the same `shipped` stands in for it, which
-- is how changing (or turning off) one of these in oracle is kept. Edit this
-- file to change what ships, not what you have: oracle never writes it.
-- A title matches anywhere in the window's title; a suite window's
-- (org.quickshell) matches the whole title.

return {
	{ shipped = "kitty", name = "kitty", class = "kitty", float = true, persistent_size = true },
	{ shipped = "ceres", name = "Ceres", class = "org.quickshell", title = "ceres", float = true, persistent_size = true },
	{ shipped = "delphi", name = "Delphi", class = "org.quickshell", title = "delphi", float = true, persistent_size = true },
	{ shipped = "oracle", name = "Oracle", class = "org.quickshell", title = "oracle", float = true, persistent_size = true },
	{ shipped = "calypso", name = "Calypso", class = "org.quickshell", title = "calypso", float = true, persistent_size = true, border = "green" },
	{ shipped = "alexandria", name = "Alexandria", class = "org.quickshell", title = "alexandria", float = true, persistent_size = true },
	{ shipped = "clio", name = "Clio", class = "org.quickshell", title = "clio", float = true, persistent_size = true },
	{ shipped = "hermes", name = "Control Hub", class = "org.quickshell", title = "hermes", float = true, persistent_size = true },
	{ shipped = "argus", name = "Argus", class = "org.quickshell", title = "argus", float = true, persistent_size = true },
	-- keeps its own size, less its sidebar (MinervaWindow keepSize)
	{ shipped = "minerva", name = "Minerva", class = "org.quickshell", title = "minerva", float = true },
	{ shipped = "stylus", name = "Stylus", class = "org.quickshell", title = "stylus", float = true, persistent_size = true },
	{ shipped = "hestia", name = "Hestia", class = "org.quickshell", title = "hestia", float = true, persistent_size = true },
	{ shipped = "kairos", name = "Kairos", class = "org.quickshell", title = "kairos", float = true, persistent_size = true },
	{ shipped = "hygieia", name = "Tidy", class = "org.quickshell", title = "hygieia", float = true, persistent_size = true },
	{ shipped = "chronos", name = "Calendar", class = "org.quickshell", title = "chronos", float = true, persistent_size = true },
	{ shipped = "picasso-view", name = "Picasso", class = "org.quickshell", title = "picasso-view", float = true, persistent_size = true },
	{ shipped = "plato-capture", name = "Plato capture", class = "org.quickshell", title = "plato-capture", float = true, persistent_size = true },
	{ shipped = "terminus-picker", name = "Terminus picker", class = "org.quickshell", title = "terminus-picker", float = true, persistent_size = true },
	{ shipped = "steam-settings", name = "Steam", class = "steam", title = "Steam Settings", float = true, persistent_size = true },
	{ shipped = "mpv", name = "mpv", class = "mpv", float = true },
}
