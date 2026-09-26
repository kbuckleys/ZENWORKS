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
