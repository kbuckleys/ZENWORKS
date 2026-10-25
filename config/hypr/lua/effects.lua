-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- EFFECTS
-- Written by oracle (Look's Window shadows, Motion's Window animations,
-- the window rows under Windows), and read back by it; base.lua lays
-- it over its own. Gaps and border in pixels; dim_inactive 0 is off.

return {
	shadows          = true,
	animations       = true,
	gaps_out         = 8,
	gaps_in          = 2,
	special_gaps     = 30,
	border_size      = 1,
	layout           = "dwindle",
	resize_on_border = false,
	dim_inactive     = 0,
	inactive_opacity = 1,
}
