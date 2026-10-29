-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

hl.bind("SUPER + L", hl.dsp.window.swap({ next = true }))
hl.bind("SUPER + SHIFT + L", function ()
    local layouts = { "scrolling", "dwindle" }
    local workspace = hl.get_active_workspace()
	if hl.get_active_special_workspace() then
		workspace = hl.get_active_special_workspace()
	end

    local next_layout = "scrolling"

    if not workspace then
        return
    end

    for i = 1, #layouts do
        if layouts[i] == workspace.tiled_layout then
            local next_layout_idx = (i % #layouts) + 1
            next_layout = layouts[next_layout_idx]
            break
        end
    end

	-- the rule's selector: a numbered workspace is its number, a special one
	-- "special:x" (both its address); a named one has no id since 0.57 and
	-- is selected as "name:x"
	local selector = workspace.addressable_name
	if not workspace.special and workspace.id == nil then
		selector = "name:" .. selector
	end
	hl.workspace_rule({ workspace = selector, layout = next_layout })
end)
