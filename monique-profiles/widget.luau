--!nonstrict
-- widget.luau - bar glyph + current profile name. Click toggles the panel.
local Monique = require("./lib/monique.luau")

local activeProfile = ""

local function applyColor()
	local color = noctalia.getConfig("icon_color")
	if type(color) == "string" and color ~= "" then
		barWidget.setGlyphColor(color)
	end
end

local function refresh()
	noctalia.runAsync(Monique.currentProfileCmd(), function(result)
		activeProfile = (result.exitCode == 0) and Monique.trim(result.stdout) or ""
		barWidget.setGlyph("device-desktop")
		-- Default hidden: the glyph + tooltip carry the info; show_label opts
		-- into the text for anyone who wants the name visible at a glance.
		local showLabel = noctalia.getConfig("show_label") == true
		barWidget.setText(showLabel and (activeProfile ~= "" and activeProfile or "Monique") or "")
		barWidget.setTooltip(activeProfile ~= "" and ("Monique profile: " .. activeProfile) or "Monique: no active profile")
		applyColor()
	end)
end

function update()
	noctalia.setUpdateInterval(30000)
	refresh()
end

function onClick()
	noctalia.togglePanel("monkeymonk/monique-profiles:panel")
end
