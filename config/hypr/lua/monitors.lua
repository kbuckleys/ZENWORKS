-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- MONITORS
-- Written by oracle's Display section, and read back by it: change a
-- screen there or here, either way works. Rules name a monitor by its
-- description, so a screen keeps its setup whichever port it is in.

-- Any output without a rule of its own (another machine, a projector) gets
-- its preferred mode rather than being left unconfigured.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- HDMI-A-1 · Xiaomi Corporation P24FBA-RAGL
hl.monitor({ output = "desc:Xiaomi Corporation P24FBA-RAGL 5438300136789", mode = "1920x1080@100", position = "0x0", scale = 1, transform = 3 })
-- DP-1 · Xiaomi Corporation Mi Monitor
hl.monitor({ output = "desc:Xiaomi Corporation Mi Monitor 5745710099792", mode = "2560x1440@180", position = "1080x368", scale = 1 })
