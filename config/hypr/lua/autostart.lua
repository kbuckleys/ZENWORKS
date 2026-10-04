-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

hl.on("hyprland.start", function()
    -- -n: exit if a shell for this config is already up, so a reload
    -- of this file cannot leave two shells fighting over the same layer
    -- surfaces and the same state files.
    --
    -- Through the shell's launcher, which decides the GPU and allocator
    -- environment for whatever machine this is — see scripts/launch.sh.
    local xdg = os.getenv("XDG_CONFIG_HOME")
    local config = (xdg and xdg ~= "") and xdg or (os.getenv("HOME") .. "/.config")
    hl.exec_cmd(config .. "/quickshell/scripts/launch.sh -n")
    hl.exec_cmd("wl-clip-persist --clipboard regular")
    -- --systemd covers the user manager too, so no separate (and deprecated)
    -- argument-less `systemctl --user import-environment` is needed
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
