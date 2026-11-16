--!nonstrict
-- widget.luau — bar widget: a glyph that toggles the Niri Config panel.
-- Thin by design, matching v4's BarWidget.qml/ControlCenterWidget.qml: no
-- state of its own, just a click target.

local function render()
	barWidget.setGlyph("device-desktop-cog")
	barWidget.setTooltip("Niri Config")
	local color = noctalia.getConfig("icon_color")
	if type(color) == "string" and color ~= "" then
		barWidget.setGlyphColor(color)
	end
end

function update()
	noctalia.setUpdateInterval(60000) -- static glyph; settings rebuild the widget anyway
	render()
end

function onClick()
	noctalia.togglePanel("monkeymonk/niri-config:panel")
end

function onIpc(event, _payload)
	if event == "toggle" or event == "openPanel" then
		noctalia.togglePanel("monkeymonk/niri-config:panel")
	end
end
