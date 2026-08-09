#!/usr/bin/env lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

local XDG_SESSION_ID = os.getenv("XDG_SESSION_ID") or ""

local entries = {
  { id="lockscreen", label="", cmd="hyprlock", confirm=false },
  { id="logout", label="󰍃", cmd="hyprshutdown -p 'loginctl terminate-session " .. XDG_SESSION_ID .. "'", confirm=true },
  { id="suspend", label="󰤄", cmd="systemctl suspend", confirm=true },
  { id="reboot", label="", cmd="hyprshutdown -p 'systemctl reboot'", confirm=true },
  { id="shutdown", label="⏻", cmd="hyprshutdown -p 'systemctl poweroff'", confirm=true },
}

local dryrun = false
local args = { ... }

if #args >= 1 and args[1] == "--dry-run" then
  dryrun = true
  table.remove(args, 1)
end

local CANCEL = '<span font_size="medium"></span>'

local function row(label)
  return string.format('<span font_size="medium">%s</span>', label)
end

local function shell_quote(s)
  return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function execute(id, cmd)
  if dryrun then
    io.stderr:write("Selected: " .. id .. "\n")
    return
  end
  os.execute(cmd .. " >/dev/null 2>&1 &")
end

local script_path = arg[0] or debug.getinfo(1, "S").source:match("^@(.+)$")

-- Resolve our own directory so the tree can live anywhere. rofi re-invokes us by
-- this path, so it must stay absolute even when we were run as ./session.lua.
local theme_dir = (script_path or ""):match("^(.*)/") or "."
if theme_dir:sub(1, 1) ~= "/" then
  if theme_dir == "." then
    theme_dir = os.getenv("PWD") or "."
  else
    theme_dir = (os.getenv("PWD") or ".") .. "/" .. theme_dir
  end
  script_path = theme_dir .. "/" .. (script_path:match("([^/]+)$") or "session.lua")
end
theme_dir = theme_dir .. "/"

-- Launched directly (not as a rofi modi): open the menu ourselves.
-- rofi sets ROFI_RETV on every script-mode call, including the first.
if not os.getenv("ROFI_RETV") and not dryrun then
  os.execute(string.format(
    'rofi -show power-menu -modi "power-menu:%s" -theme %s',
    script_path,
    shell_quote(theme_dir .. "session.rasi")
  ))
  os.exit(0)
end

io.write("\0no-custom\x1ftrue\n\0markup-rows\x1ftrue\n")

local confirm_action = os.getenv("SESSION_CONFIRM_ACTION")
if confirm_action and #args == 0 then
  for _, e in ipairs(entries) do
    if e.id == confirm_action then
      io.write("\0message\x1f" .. e.label, "\n", row(""), "\n", CANCEL)
      os.exit(0)
    end
  end
  io.stderr:write("Invalid confirm action: " .. confirm_action .. "\n")
  os.exit(1)
end

local selection = args[1] or ""

if selection == "" then
  local out = {"\0prompt\x1fPower Menu"}
  for _, e in ipairs(entries) do
    out[#out + 1] = row(e.label)
  end
  io.write(table.concat(out, "\n"))
  os.exit(0)
end

if selection == row("") and confirm_action then
  for _, e in ipairs(entries) do
    if e.id == confirm_action then
      execute(e.id, e.cmd)
      os.exit(0)
    end
  end
end

if selection == CANCEL then os.exit(0) end

for _, e in ipairs(entries) do
  if selection == row(e.label) then
    if e.id == "lockscreen" or not e.confirm then
      execute(e.id, e.cmd)
    else
      os.execute(string.format(
        'setsid sh -c "SESSION_CONFIRM_ACTION=%s exec rofi -show power-menu -modi \\"power-menu:%s\\" -theme %s" >/dev/null 2>&1 &',
        shell_quote(e.id),
        script_path,
        shell_quote(theme_dir .. "sessionok.rasi")
      ))
    end
    os.exit(0)
  end
end
io.stderr:write("Invalid selection: " .. selection .. "\n")
os.exit(1)
