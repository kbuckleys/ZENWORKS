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
    --
    -- The polkit agent only AFTER that: started beside it, it raced the
    -- import, found no WAYLAND_DISPLAY, failed five times in a second and
    -- systemd gave up on it for the session (start-limit-hit, 2026-10-20 —
    -- found by Hestia's overview). reset-failed clears an old give-up.
    hl.exec_cmd("sh -c 'dbus-update-activation-environment --systemd --all; "
        .. "systemctl --user reset-failed hyprpolkitagent 2>/dev/null; "
        .. "systemctl --user start hyprpolkitagent'")
    -- the session's ssh-agent, where base.lua points SSH_AUTH_SOCK: only when
    -- it points there (another agent is someone else's), openssh is
    -- installed, and nothing listens there yet
    hl.exec_cmd("sh -c '[ \"$SSH_AUTH_SOCK\" = \"$XDG_RUNTIME_DIR/ssh-agent.socket\" ] "
        .. "&& command -v ssh-agent >/dev/null && [ ! -S \"$SSH_AUTH_SOCK\" ] "
        .. "&& exec ssh-agent -D -a \"$SSH_AUTH_SOCK\"'")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- YOURS: startup.lua, which oracle's Windows section writes (Startup
    -- apps). The ones that are on, each `delay` seconds after this. Guarded
    -- like defaults.lua: a broken file costs only your own.
    local ok, apps = pcall(require, "lua.startup")
    if not ok or type(apps) ~= "table" then return end
    for _, a in ipairs(apps) do
        pcall(function()
            if type(a) ~= "table" or a.on == false or type(a.command) ~= "string" or a.command == "" then return end
            local d = tonumber(a.delay) or 0
            if d > 0 then
                local q = "'" .. a.command:gsub("'", "'\\''") .. "'"
                hl.exec_cmd("sh -c 'sleep " .. math.floor(d) .. "; exec sh -c \"$0\"' " .. q)
            else
                hl.exec_cmd(a.command)
            end
        end)
    end
end)
