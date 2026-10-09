-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

hl.window_rule({ match = { class = "org.quickshell", title = "ceres" },             float = true })
hl.window_rule({ match = { class = "org.quickshell", title = "oracle" },            float = true })
hl.window_rule({ match = { class = "org.quickshell", title = "terminus" },          float = true })
hl.window_rule({ match = { class = "org.quickshell", title = "alexandria" },        float = true })
hl.window_rule({ match = { class = "org.quickshell", title = "picasso-view" },      float = true })
hl.window_rule({ match = { class = "org.quickshell", title = "plato-capture" },     float = true, size = { 760, 460 }})
hl.window_rule({ match = { class = "org.quickshell", title = "terminus-picker" },   float = true })
hl.window_rule({ match = { class = "steam", title = "Steam Settings" },             float = true })
hl.window_rule({ match = { title = "^cynosure$" },                                  float = true, size = { 1000, 1000 }})
hl.window_rule({ match = { title = "^sysmon$" },                                    float = true, size = { 1000, 1100 }})
hl.window_rule({ match = { class = "net.davidotek.pupgui2" },                       float = true })
hl.window_rule({ match = { class = "mpv" },                                         float = true })

-- GLOBAL BLUR
hl.layer_rule({ match = { namespace = ".*" }, blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "morpheus-bar(-clear)?" }, animation = "none" })
-- the pill with oracle's Blur behind off: after the global rule, so it wins
hl.layer_rule({ match = { namespace = "morpheus-bar-clear" }, blur = false })

-- SPECIAL WORKSPACE
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })
