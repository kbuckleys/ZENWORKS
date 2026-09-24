-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- THIS MACHINE'S OWN SETTINGS — an example.
--
-- Copy this file to lua/machine.lua and edit it there. machine.lua is not
-- committed (see ../.gitignore) and hyprland.lua loads it last, if it exists,
-- so it overrides everything before it. Without it the config still works:
-- every monitor gets its preferred mode and the cursor is Hyprland's default.
--
-- These are one desk's values: two monitors, an NVIDIA card, a particular
-- cursor theme, and a personal tool bound to two keys.

-- MONITORS
-- `hyprctl monitors` lists the names on this machine.
hl.monitor({ output = "DP-1",      mode = "2560x1440@180",  position = "auto", })
hl.monitor({ output = "HDMI-A-1",  mode = "1920x1080@100",  position = "auto", transform = 3, })

-- NVIDIA: a 20 GB shader cache, never trimmed. Does nothing on other GPUs.
hl.env("__GL_SHADER_DISK_CACHE_SIZE", "21474836480")
hl.env("__GL_SHADER_DISK_CACHE_SKIP_CLEANUP", "1")

-- CURSOR — the theme has to be installed
hl.env("HYPRCURSOR_THEME", "cz-Viator-Black-Hourglass")
hl.env("XCURSOR_THEME", "cz-Viator-Black-Hourglass")
hl.env("HYPRCURSOR_SIZE", "6")
hl.env("XCURSOR_SIZE", "6")

-- spoot, a personal project outside this repo
hl.bind("SUPER + M",          hl.dsp.exec_cmd("~/Projects/spoot/bin/spoot"))
hl.bind("SUPER + SHIFT + M",  hl.dsp.exec_cmd("~/Projects/spoot/bin/spoot --listen"))
