-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

local function screenshot(mode)
  -- The pictures directory from user-dirs.dirs, not a spelled-out ~/Pictures.
  -- xdg-user-dir answers $HOME itself when nothing is configured, and that
  -- is not somewhere to drop screenshots, so it falls back to ~/Pictures.
  local script = [[
set -e
pics=$(xdg-user-dir PICTURES 2>/dev/null || true)
{ [ -n "$pics" ] && [ "$pics" != "$HOME" ]; } || pics="$HOME/Pictures"
dir="$pics/Screenshots"
mkdir -p "$dir"

case "${1}" in
  screen)
    monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)
    [ -n "$monitor" ] || exit 1
    file="$dir/$(date +'%Y-%m-%d-%H%M%S')-$monitor.png"
    grim -o "$monitor" "$file"
    ;;
  region)
    file="$dir/$(date +'%Y-%m-%d-%H%M%S')_region.png"
    geometry=$(slurp -d)
    [ -n "$geometry" ] || exit 0
    grim -g "$geometry" "$file"
    ;;
  window)
    file="$dir/$(date +'%Y-%m-%d-%H%M%S')_window.png"
    geometry=$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
    # jq prints the literal "null,null nullxnull" when nothing is focused, which
    # is non-empty and would sail past a -n test straight into a grim parse error
    [ "$geometry" != "null,null nullxnull" ] || exit 1
    grim -g "$geometry" "$file"
    ;;
esac

wl-copy < "$file"
notify-send -i "$file" "Screenshot saved" "Saved to $file and copied to clipboard"
]]
  hl.exec_cmd("bash -c '" .. script:gsub("'", "'\"'\"'" ) .. "' -- " .. mode)
end

local function screen()
  screenshot("screen")
end

local function region()
  screenshot("region")
end

local function window()
  screenshot("window")
end

-- BINDS
hl.bind("SUPER + SHIFT + PRINT",  region)
hl.bind("SUPER + PRINT",          window)
hl.bind("PRINT",                  screen)
