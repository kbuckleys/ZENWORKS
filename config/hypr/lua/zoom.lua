-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- KDE Plasma's screen zoom, replicated.
-- Constants below are KWin's own defaults, from kwin/src/plugins/zoom/zoom.kcfg.

local ZOOM_STEP = 1.2    -- ZoomFactor, applied multiplicatively
local MIN_ZOOM  = 1.0    -- std::clamp(value, 1.0, 100.0)
local MAX_ZOOM  = 100.0

-- Zoom drags the cursor between the hardware plane and the framebuffer: the
-- zoomLock in Hyprland's Renderer.cpp is a function-local static shared by
-- every monitor, so the unzoomed one runs unlockSoftwareAll() and clears it
-- every frame, undoing the lock the zoomed one just took. Each handover back to
-- the plane can strand a stale cursor on it -- unmagnified, surviving until
-- something else repaints, and invisible to screenshots because screencopy
-- never sees the cursor plane. Only DP-1 shows it; HDMI-A-1 is rotated, and
-- rotated outputs already fall back to software cursors.
--
-- Toggling this per zoom just moved the handover to zoom-out, so the cursor
-- stays composited full time and there is no handover left to strand anything.
local HW_CURSORS_OFF = 1

-- Damage is tracked against the unzoomed cursor rect, so a magnified pointer
-- outruns it. A whole-monitor repaint costs nothing we care about while zoomed.
local DAMAGE_MONITOR = 1  -- whole monitor damaged every frame
local DAMAGE_FULL    = 2  -- Hyprland's fine-grained default

-- cursor:zoom_factor is animated, so the render is still ramping down after we
-- write 1.0. Hold the full-damage frames until it lands.
local SETTLE_MS = 300

-- the shipped shader, beside this config (see hyprland.lua's ZENWORKS)
local SHADER = ZENWORKS.hypr .. "/shaders/zoom.frag"

-- THE COLOR FILTER (hermes' Control Hub › Display, 2026-10-22). Hyprland has
-- one screen shader and this file owns it, so a filter is a copy of zoom.frag
-- with the filter on what it samples (hermes.js filterShader): worn all the
-- time while a filter is on, the zoom included, since zoom.frag passes an
-- unzoomed screen through. filter.lua names it, for every start and reload;
-- hermes hands a new one over through `hyprctl eval` (zen_filter, below).
-- Guarded: a missing or broken file, or a shader gone missing, is no filter.
local function readFilter()
	local ok, f = pcall(dofile, ZENWORKS.user .. "/lua/filter.lua")
	if not (ok and type(f) == "table" and type(f.shader) == "string" and f.shader ~= "") then return "" end
	local fh = io.open(f.shader, "r")
	if not fh then return "" end
	fh:close()
	return f.shader
end
local okFilter, filter = pcall(readFilter)
if not okFilter or type(filter) ~= "string" then filter = "" end

-- A filter needs the whole monitor redrawn every frame, as the zoom does.
-- With fine-grained damage only the changed part is drawn again, over the
-- last frame, and the filter lands on pixels it already filtered: grayscale
-- twice is the same, but inverted twice is the original and the corrections
-- drift, so the screen flickered (user, 2026-10-22). It never did while
-- recording, because a capture damages the whole monitor.
local function idleDamage() return filter ~= "" and DAMAGE_MONITOR or DAMAGE_FULL end

hl.config({
	cursor = {
		zoom_factor = MIN_ZOOM,        -- InitialZoom; 1.0 is Hyprland's "off", not 0
		zoom_rigid = false,            -- == MouseTrackingProportional, KWin's default
		zoom_detached_camera = false,
		zoom_disable_aa = false,       -- the shader does the filtering, keep GL_LINEAR
		no_hardware_cursors = HW_CURSORS_OFF,
	},
	decoration = {
		screen_shader = filter,
	},
	debug = {
		damage_tracking = idleDamage(),
	},
})

-- KWin keeps m_targetZoom apart from the animating m_zoom; so do we, since the
-- compositor animates cursor:zoom_factor out from under us.
local target = hl.get_config("cursor.zoom_factor") or MIN_ZOOM
if target < MIN_ZOOM then target = MIN_ZOOM end

local zoomed = false
local settle = nil

local function cancelSettle()
	if not settle then return end
	pcall(function() settle:set_enabled(false) end)
	settle = nil
end

-- The shader picks the pixel grid or the sharp upscaler off its own
-- derivatives, so all this has to decide is whether the zoom is running.
local function applyZoomState(zoom)
	if zoom > MIN_ZOOM then
		cancelSettle()
		if zoomed then return end
		zoomed = true
		hl.config({
			decoration = { screen_shader = filter ~= "" and filter or SHADER },
			debug = { damage_tracking = DAMAGE_MONITOR },
		})
	elseif zoomed and not settle then
		settle = hl.timer(function()
			settle = nil
			zoomed = false
			hl.config({
				decoration = { screen_shader = filter },
				debug = { damage_tracking = idleDamage() },
			})
		end, { timeout = SETTLE_MS, type = "oneshot" })
	end
end

local function setTargetZoom(value)
	value = math.min(MAX_ZOOM, math.max(MIN_ZOOM, value))
	-- Stepping in and back out by the same count does not divide back to an
	-- exact 1.0 (twenty steps leaves 1.0000000000000007), and anything above
	-- MIN_ZOOM keeps the shader and whole-monitor damage on. Land it.
	if value - MIN_ZOOM < 1e-6 then value = MIN_ZOOM end
	if value == target then return end
	target = value
	hl.config({ cursor = { zoom_factor = value } })
	applyZoomState(value)
end

local function zoomIn()    setTargetZoom(target * ZOOM_STEP) end
local function zoomOut()   setTargetZoom(target / ZOOM_STEP) end
local function zoomReset() setTargetZoom(MIN_ZOOM) end

-- The zoom magnifies the session lock too. Cerberus parks it as the lock comes
-- in and hands it back as it goes, through `hyprctl eval` -- globals, since
-- eval runs in this same Lua state. A level already parked is kept: a second
-- park (a config reload under the lock) finds the zoom at MIN_ZOOM.
local parked = nil

function zoom_park()
	if target > MIN_ZOOM then
		parked = target
		zoomReset()
	end
end

function zoom_unpark()
	if not parked then return end
	local level = parked
	parked = nil
	setTargetZoom(level)
end

hl.bind("SUPER + CTRL + EQUAL",  zoomIn,  { repeating = true })
hl.bind("SUPER + CTRL + PLUS",   zoomIn,  { repeating = true })
hl.bind("SUPER + CTRL + MINUS",  zoomOut, { repeating = true })
hl.bind("SUPER + CTRL + 0",      zoomReset)

-- hermes' filter, changed: the path of a shader made from zoom.frag, or ""
-- for none. Worn at once, zoomed or not: the filter's shader zooms too.
function zen_filter(path)
	filter = type(path) == "string" and path or ""
	hl.config({
		decoration = { screen_shader = (zoomed and filter == "") and SHADER or filter },
		debug = { damage_tracking = zoomed and DAMAGE_MONITOR or idleDamage() },
	})
end

-- KWin's PointerAxisGestureModifiers defaults to Meta+Control.
hl.bind("SUPER + CTRL + mouse_up",    zoomIn)
hl.bind("SUPER + CTRL + mouse_down",  zoomOut)
hl.bind("SUPER + CTRL + mouse:274",   zoomReset)
