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
    hl.exec_cmd(ZENWORKS.shell .. "/scripts/launch.sh -n")
    hl.exec_cmd("wl-clip-persist --clipboard regular")
    -- --systemd covers the user manager too, so no separate (and deprecated)
    -- argument-less `systemctl --user import-environment` is needed
    --
    -- The polkit agent only AFTER that: started beside it, it raced the
    -- import, found no WAYLAND_DISPLAY, failed five times in a second and
    -- systemd gave up on it for the session (start-limit-hit, 2026-10-20 —
    -- found by Hestia's overview). reset-failed clears an old give-up.
    --
    -- Portals left running by an earlier session (logging out does not
    -- always stop the user manager) keep that session's environment and
    -- config: switching from another desktop at the TTY left the file
    -- chooser running a trashed wrapper (2026-10-25). try-restart only
    -- touches ones already up; the rest start on demand with this env.
    hl.exec_cmd("sh -c 'dbus-update-activation-environment --systemd --all; "
        .. "systemctl --user try-restart xdg-desktop-portal-termfilechooser "
        .. "xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-desktop-portal; "
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
