--!nonstrict
-- shortcut.luau — control-center tile that toggles the Niri Config panel.
-- v5 placement (which bar/control-center a widget instance sits in) is
-- entirely host/user-owned — there is no plugin-side "show in control
-- center" visibility switch the way v4's single QML widget had one. The
-- `show_in_control_center` plugin setting is the closest honest equivalent
-- available through the shortcut.* API: it gates `setEnabled`, so a user who
-- has placed this tile but turned the setting off sees it present-but-
-- disabled rather than hidden (placing/removing the tile itself is done the
-- same way as any other control-center shortcut, via Settings → Control
-- Center shortcuts).

local function render()
	shortcut.setLabel("Niri Config")
	shortcut.setIcon("device-desktop-cog")
	local enabled = noctalia.getConfig("show_in_control_center")
	shortcut.setEnabled(enabled ~= false)
end

render()

function onClick()
	noctalia.togglePanel("monkeymonk/niri-config:panel")
end
