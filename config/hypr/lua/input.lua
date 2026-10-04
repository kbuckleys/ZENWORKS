-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- INPUT
-- Written by oracle's Input section, and read back by it: change one
-- there or here, either way works. base.lua hands these to hyprland's
-- input settings, each under its own name; touchpad_, tablet_,
-- tablettool_, touchdevice_ and virtualkeyboard_ ones go in the table
-- of that name. "" leaves a setting to hyprland.
--
-- kb_layout, kb_variant and kb_options are xkb's names: "us,de" is two
-- layouts, and kb_options is where the key that switches them goes
-- (grp:alt_shift_toggle).

return {
	-- keyboard
	kb_layout                                = "us",
	kb_variant                               = "",
	kb_options                               = "",
	kb_model                                 = "",
	kb_rules                                 = "",
	kb_file                                  = "",
	repeat_delay                             = 600,
	repeat_rate                              = 25,
	numlock_by_default                       = false,
	resolve_binds_by_sym                     = false,

	-- mouse
	accel_profile                            = "",
	sensitivity                              = 0,
	force_no_accel                           = false,
	left_handed                              = false,
	rotation                                 = 0,
	scroll_points                            = "",

	-- scrolling
	natural_scroll                           = false,
	scroll_factor                            = 1,
	scroll_method                            = "",
	scroll_button                            = 0,
	scroll_button_lock                       = false,
	emulate_discrete_scroll                  = 1,

	-- focus
	follow_mouse                             = 1,
	follow_mouse_threshold                   = 0,
	follow_mouse_shrink                      = 0,
	mouse_refocus                            = true,
	focus_on_close                           = 0,
	float_switch_override_focus              = 1,
	special_fallthrough                      = false,
	off_window_axis_events                   = 1,

	-- touchpad
	touchpad_tap_to_click                    = true,
	touchpad_tap_and_drag                    = true,
	touchpad_drag_lock                       = 0,
	touchpad_drag_3fg                        = 0,
	touchpad_tap_button_map                  = "",
	touchpad_clickfinger_behavior            = false,
	touchpad_middle_button_emulation         = false,
	touchpad_natural_scroll                  = false,
	touchpad_scroll_factor                   = 1,
	touchpad_disable_while_typing            = true,
	touchpad_flip_x                          = false,
	touchpad_flip_y                          = false,

	-- touch screen
	touchdevice_enabled                      = true,
	touchdevice_output                       = "[[Auto]]",
	touchdevice_transform                    = 0,

	-- drawing tablet
	tablet_output                            = "",
	tablet_transform                         = 0,
	tablet_left_handed                       = false,
	tablet_relative_input                    = false,
	tablet_region_position                   = "0 0",
	tablet_absolute_region_position          = false,
	tablet_region_size                       = "0 0",
	tablet_active_area_size                  = "0 0",
	tablet_active_area_position              = "0 0",

	-- tablet pen
	tablettool_eraser_button_mode            = 0,
	tablettool_eraser_button_override        = 0,
	tablettool_pressure_range_min            = -1,
	tablettool_pressure_range_max            = -1,

	-- on-screen keyboard
	virtualkeyboard_share_states             = 2,
	virtualkeyboard_release_pressed_on_close = false,
}
