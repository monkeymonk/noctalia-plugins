--!nonstrict
-- panel.luau - list every Monique profile, highlight the active one, switch
-- on click. No KDL parsing, no save/apply pipeline - monique itself owns
-- writing the monitor config; this just drives its CLI.
local Monique = require("./lib/monique.luau")

local profiles = {}
local activeProfile = ""
local loaded = false
local errorText = ""

local render -- forward decl

local function refresh()
	noctalia.runAsync(Monique.listProfilesCmd(), function(result)
		if result.exitCode == 0 then
			profiles = Monique.parseProfiles(result.stdout)
			errorText = ""
		else
			errorText = "Could not list Monique profiles."
		end
		loaded = true
		render()
	end)
	noctalia.runAsync(Monique.currentProfileCmd(), function(result)
		activeProfile = (result.exitCode == 0) and Monique.trim(result.stdout) or ""
		render()
	end)
end

local function switchTo(name)
	if name == activeProfile then
		return
	end
	noctalia.runAsync(Monique.switchProfileCmd(name), function(result)
		if result.exitCode == 0 then
			activeProfile = name
			errorText = ""
		else
			errorText = "Switching to \"" .. name .. "\" failed."
		end
		render()
	end)
end

local function iconColor()
	local c = noctalia.getConfig("icon_color")
	return (type(c) == "string" and c ~= "") and c or "on_surface"
end

render = function()
	local rows = {
		ui.row({ gap = 8, align = "center" }, {
			ui.glyph({ name = "device-desktop", size = 18, color = iconColor() }),
			ui.label({ text = "Monique Profiles", fontWeight = "bold", flexGrow = 1 }),
			ui.button({
				glyph = "external-link",
				variant = "ghost",
				controlSize = "sm",
				tooltip = "Open Monique (create / edit profiles)",
				onClick = function()
					noctalia.runAsync({ "monique" })
				end,
			}),
			ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = refresh }),
		}),
		ui.separator({}),
	}

	if not loaded then
		table.insert(rows, ui.label({ text = "Loading profiles…", color = "on_surface_variant" }))
	elseif errorText ~= "" then
		table.insert(rows, ui.label({ text = errorText, color = "error" }))
	elseif #profiles == 0 then
		table.insert(rows, ui.label({ text = "No Monique profiles found.", color = "on_surface_variant" }))
	else
		for _, name in ipairs(profiles) do
			local isActive = name == activeProfile
			table.insert(
				rows,
				ui.row({
					key = "profile-" .. name,
					gap = 8,
					align = "center",
					padding = 8,
					radius = 8,
					fill = isActive and "primary" or "on_surface/0",
					onClick = function()
						switchTo(name)
					end,
				}, {
					ui.glyph({ name = "device-desktop", size = 18, color = isActive and "on_primary" or "on_surface" }),
					ui.label({ text = name, flexGrow = 1, color = isActive and "on_primary" or "on_surface" }),
					ui.glyph({ name = "check", size = 16, color = "on_primary", visible = isActive }),
				})
			)
		end
	end

	panel.render(ui.column({ gap = 6, padding = 4, flexGrow = 1 }, rows))
end

function onOpen()
	loaded = false
	errorText = ""
	-- Fresh callback, same reasoning as niri-config-v5's panel.luau: keep the
	-- open-tick cheap, let the real data arrive via its own async callback.
	noctalia.runAsync({ "true" }, function()
		render()
		refresh()
	end)
end
