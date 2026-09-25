-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- General config
swayimg.mode = "viewer" -- mode at startup
swayimg.antialiasing = true -- anti-aliasing
swayimg.decoration = false -- window title/buttons/borders
swayimg.overlay = false -- window overlay mode
swayimg.dnd_button = "MouseRight" -- drag-and-drop mouse button

-- Image list configuration
swayimg.imagelist.order = "numeric" -- list order
swayimg.imagelist.reverse = false -- reverse order
swayimg.imagelist.recursive = false -- recursive directory reading
swayimg.imagelist.adjacent = true -- add adjacent files from same dir

-- Text overlay configuration
swayimg.text.font = "JetBrainsMono Nerd Font" -- font name
swayimg.text.size = 16 -- font size in pixels
--swayimg.text.spacing = 0 -- line spacing
swayimg.text.padding = 0 -- padding from window edge
swayimg.text.color = 0xffdfdfdd -- foreground text color
swayimg.text.background = 0x00000000 -- text background color
swayimg.text.shadow = 0x000000 -- text shadow color
swayimg.text.timeout = 5 -- layer hide timeout
swayimg.text.status_timeout = 3 -- status message hide timeout

-- Image viewer mode
swayimg.viewer.default_scale = "optimal" -- default image scale
swayimg.viewer.default_position = "center" -- default image position
swayimg.viewer.drag_button = "MouseLeft" -- mouse button to drag image
swayimg.viewer.set_window_background(0x80000000) -- window background color (50% alpha)
swayimg.viewer.set_image_background(0x80000000) -- transparent image background (50% alpha, matches window)
swayimg.viewer.autocenter = true -- enable automatic centering
swayimg.viewer.loop = true -- enable image list loop mode
swayimg.viewer.preload = 1 -- number of images to preload
--swayimg.viewer.history = 1 -- number of the history cache
swayimg.viewer.mark_color = 0xff808080 -- mark icon color
swayimg.viewer.set_text("topleft", { -- top left text block scheme
	"File: {name}",
	"Format: {format}",
	"File size: {sizehr}",
	"File time: {time}",
	"EXIF date: {meta.Exif.Photo.DateTimeOriginal}",
	"EXIF camera: {meta.Exif.Image.Model}",
})
swayimg.viewer.set_text("topright", { -- top right text block scheme
	"Image: {list.index} of {list.total}",
	"Frame: {frame.index} of {frame.total}",
	"Size: {frame.width}x{frame.height}",
})
swayimg.viewer.set_text("bottomleft", { -- bottom left text block scheme
	"Scale: {scale}",
})

-- Key and mouse bindings in viewer mode (example only, not all):

-- bind Escape key for exit
swayimg.viewer.on_key("Escape", function()
	swayimg.exit()
end)
-- bind the left arrow key to move the image to the left by 1/10 of the application window size
swayimg.viewer.on_key("Left", function()
	local wnd = swayimg.get_window_size()
	local pos = swayimg.viewer.get_position()
	swayimg.viewer.set_abs_position(math.floor(pos.x + wnd.width / 10), pos.y)
end)
-- bind mouse vertical scroll button with pressed Ctrl to zoom in the image at mouse pointer coordinates
swayimg.viewer.on_mouse("Ctrl-ScrollUp", function()
	local pos = swayimg.get_mouse_pos()
	local scale = swayimg.viewer.scale
	scale = scale + scale / 10
	swayimg.viewer.set_abs_scale(scale, pos.x, pos.y)
end)

-- Slide show mode, same config as for viewer mode with the following defaults:
swayimg.slideshow.timeout = 5 -- timeout to switch image
swayimg.slideshow.default_scale = "fit" -- default image scale
swayimg.slideshow.set_window_background("auto") -- window background mode
--swayimg.slideshow.history = 0 -- number of the history cache
swayimg.slideshow.set_text("topleft", { "{name}" }) -- top left text block scheme

-- Gallery mode
swayimg.gallery.aspect = "fill" -- thumbnail aspect ratio
swayimg.gallery.thumb_size = 200 -- thumbnail size in pixels
swayimg.gallery.padding_size = 10 -- padding between thumbnails
swayimg.gallery.border_size = 2 -- border size for selected thumbnail
swayimg.gallery.border_color = 0xffb6e0a4 -- border color for selected thumbnail
swayimg.gallery.selected_scale = 1.0 -- scale for selected thumbnail
swayimg.gallery.selected_color = 0xff20242a -- background color for selected thumbnail
swayimg.gallery.unselected_color = 0xff202020 -- background color for unselected thumbnail
swayimg.gallery.window_color = 0xff000000 -- window background color
swayimg.gallery.cache = 100 -- number of thumbnails stored in memory
swayimg.gallery.preload = false -- preloading invisible thumbnails
swayimg.gallery.pstore = false -- enable persistent storage for thumbnails
swayimg.gallery.set_text("topleft", { -- top left text block scheme
	"File: {name}",
})
swayimg.gallery.set_text("topright", { -- top right text block scheme
	"{list.index} of {list.total}",
})

-- Key and mouse bindings in gallery mode (example only, not all):

-- bind Enter key to open image in viewer
swayimg.gallery.on_key("Return", function()
	swayimg.mode = "viewer"
end)
-- bind the left arrow key to select thumbnail on the left side
swayimg.gallery.on_key("Left", function()
	swayimg.gallery.select("left")
end)

-- force set scale mode on window resize (useful for tiling compositors)
swayimg.on_window_resize(function()
	if swayimg.mode == "viewer" then
		swayimg.viewer.set_fix_scale("optimal")
	end
end)

-- bind the Delete key in slide show mode to delete the current file and display a status message
swayimg.slideshow.on_key("Delete", function()
	local image = swayimg.slideshow.get_image()
	os.remove(image.path)
	swayimg.text.status = "File " .. image.path .. " removed"
end)

-- set a custom window title in gallery mode
swayimg.gallery.on_image_change(function()
	local image = swayimg.gallery.get_image()
	swayimg.title = "Gallery: " .. image.path
end)

-- print paths to all marked files by pressing Ctrl-p in gallery mode
swayimg.gallery.on_key("Ctrl-p", function()
	local entries = swayimg.imagelist.get()
	for _, entry in ipairs(entries) do
		if entry.mark then
			print(entry.path)
		end
	end
end)
