--!nonstrict
-- outputs.luau — model + KDL serialization for `output "NAME" { … }` blocks.
-- Faithful port of lib/outputs.js (niri-config v4). Operates on lib/kdl.luau
-- node tables (passed in, not required here — this module stays decoupled
-- from the parser, matching the original's "zero deps beyond the nodes
-- caller passes in" shape).

local M = {}

M.TRANSFORMS = { "Normal", "90", "180", "270", "Flipped", "Flipped-90", "Flipped-180", "Flipped-270" }

-- Parse an `output` kdl node → editable model.
function M.parseOutput(node)
	local m = {
		name = node.args[1] and tostring(node.args[1].value) or "",
		node = node,
		off = false,
		mode = "",
		scale = nil,
		x = nil,
		y = nil,
		transform = nil,
		vrr = false,
		vrrOnDemand = false,
		focusAtStartup = false,
		backdropColor = "",
		maxBpc = nil,
	}
	for _, c in ipairs(node.children or {}) do
		if c.name == "off" then
			m.off = true
		elseif c.name == "mode" then
			if c.args[1] then
				m.mode = tostring(c.args[1].value)
			end
		elseif c.name == "scale" then
			if c.args[1] then
				m.scale = tonumber(c.args[1].value)
			end
		elseif c.name == "transform" then
			if c.args[1] then
				m.transform = tostring(c.args[1].value)
			end
		elseif c.name == "position" then
			m.x = (c.props.x ~= nil) and tonumber(c.props.x) or nil
			m.y = (c.props.y ~= nil) and tonumber(c.props.y) or nil
		elseif c.name == "variable-refresh-rate" then
			m.vrr = true
			m.vrrOnDemand = c.props and c.props["on-demand"] == true
		elseif c.name == "focus-at-startup" then
			m.focusAtStartup = true
		elseif c.name == "backdrop-color" then
			if c.args[1] then
				m.backdropColor = tostring(c.args[1].value)
			end
		elseif c.name == "max-bpc" then
			if c.args[1] then
				m.maxBpc = tonumber(c.args[1].value)
			end
		end
	end
	return m
end

-- Serialize a model → KDL block text (no leading indent on first line). A
-- disabled monitor uses `off` inside the block (niri's way), not slashdash.
function M.serializeOutput(m, indent)
	indent = indent or "    "
	local L = { 'output "' .. m.name .. '" {' }
	if m.off then
		table.insert(L, indent .. "off")
	end
	if m.mode and m.mode ~= "" then
		table.insert(L, indent .. 'mode "' .. m.mode .. '"')
	end
	if m.scale ~= nil then
		table.insert(L, indent .. "scale " .. tostring(m.scale))
	end
	if m.x ~= nil and m.y ~= nil then
		table.insert(L, indent .. "position x=" .. tostring(m.x) .. " y=" .. tostring(m.y))
	end
	if m.transform and m.transform ~= "" and m.transform ~= "Normal" then
		table.insert(L, indent .. 'transform "' .. m.transform .. '"')
	end
	if m.vrr then
		table.insert(L, indent .. "variable-refresh-rate" .. (m.vrrOnDemand and " on-demand=true" or ""))
	end
	if m.backdropColor and m.backdropColor ~= "" then
		table.insert(L, indent .. 'backdrop-color "' .. m.backdropColor .. '"')
	end
	if m.focusAtStartup then
		table.insert(L, indent .. "focus-at-startup")
	end
	table.insert(L, "}")
	return table.concat(L, "\n")
end

-- Parse a niri mode string "WxH@R" → {width,height,refresh}.
function M.parseMode(s)
	local str = tostring(s):gsub("^%s+", ""):gsub("%s+$", "")
	local w, h, r = str:match("^(%d+)x(%d+)@([%d%.]+)$")
	if w then
		return { width = tonumber(w), height = tonumber(h), refresh = tonumber(r) }
	end
	w, h = str:match("^(%d+)x(%d+)$")
	if w then
		return { width = tonumber(w), height = tonumber(h), refresh = nil }
	end
	return nil
end

return M
