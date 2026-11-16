--!nonstrict
-- input.luau — the `input {}` settings table plus read/diff/serialize/apply
-- for the Input tab. Faithful port of lib/input.js (niri-config v4).
-- One row per niri input option: kind = flag (bare node) | bool
-- (`name true|false`) | str | int | float.

local Kdl = require("./kdl.luau")

local M = {}

M.SETTINGS = {
	{ prop = "layout", path = { "keyboard", "xkb" }, name = "layout", kind = "str" },
	{ prop = "variant", path = { "keyboard", "xkb" }, name = "variant", kind = "str" },
	{ prop = "options", path = { "keyboard", "xkb" }, name = "options", kind = "str" },
	{ prop = "model", path = { "keyboard", "xkb" }, name = "model", kind = "str" },
	{ prop = "trackLayout", path = { "keyboard" }, name = "track-layout", kind = "str" },
	{ prop = "numlock", path = { "keyboard" }, name = "numlock", kind = "flag" },
	{ prop = "repeatDelay", path = { "keyboard" }, name = "repeat-delay", kind = "int" },
	{ prop = "repeatRate", path = { "keyboard" }, name = "repeat-rate", kind = "int" },

	{ prop = "tpOff", path = { "touchpad" }, name = "off", kind = "flag" },
	{ prop = "tpTap", path = { "touchpad" }, name = "tap", kind = "flag" },
	{ prop = "tpDwt", path = { "touchpad" }, name = "dwt", kind = "flag" },
	{ prop = "tpDwtp", path = { "touchpad" }, name = "dwtp", kind = "flag" },
	{ prop = "tpNatural", path = { "touchpad" }, name = "natural-scroll", kind = "flag" },
	{ prop = "tpDrag", path = { "touchpad" }, name = "drag", kind = "bool" },
	{ prop = "tpDragLock", path = { "touchpad" }, name = "drag-lock", kind = "flag" },
	{ prop = "tpMiddleEmu", path = { "touchpad" }, name = "middle-emulation", kind = "flag" },
	{ prop = "tpLeftHanded", path = { "touchpad" }, name = "left-handed", kind = "flag" },
	{ prop = "tpDisabledExt", path = { "touchpad" }, name = "disabled-on-external-mouse", kind = "flag" },
	{ prop = "tpAccel", path = { "touchpad" }, name = "accel-speed", kind = "float" },
	{ prop = "tpAccelProfile", path = { "touchpad" }, name = "accel-profile", kind = "str" },
	{ prop = "tpScrollMethod", path = { "touchpad" }, name = "scroll-method", kind = "str" },
	{ prop = "tpClickMethod", path = { "touchpad" }, name = "click-method", kind = "str" },
	{ prop = "tpTapButtonMap", path = { "touchpad" }, name = "tap-button-map", kind = "str" },

	{ prop = "msOff", path = { "mouse" }, name = "off", kind = "flag" },
	{ prop = "msNatural", path = { "mouse" }, name = "natural-scroll", kind = "flag" },
	{ prop = "msMiddleEmu", path = { "mouse" }, name = "middle-emulation", kind = "flag" },
	{ prop = "msLeftHanded", path = { "mouse" }, name = "left-handed", kind = "flag" },
	{ prop = "msAccel", path = { "mouse" }, name = "accel-speed", kind = "float" },
	{ prop = "msAccelProfile", path = { "mouse" }, name = "accel-profile", kind = "str" },
	{ prop = "msScrollMethod", path = { "mouse" }, name = "scroll-method", kind = "str" },

	{ prop = "focusFollowsMouse", path = {}, name = "focus-follows-mouse", kind = "flag" },
	{ prop = "warpMouse", path = {}, name = "warp-mouse-to-focus", kind = "flag" },
	{ prop = "wsBackAndForth", path = {}, name = "workspace-auto-back-and-forth", kind = "flag" },
	{ prop = "disablePowerKey", path = {}, name = "disable-power-key-handling", kind = "flag" },
	{ prop = "modKey", path = {}, name = "mod-key", kind = "str" },
}

-- ── read ─────────────────────────────────────────────────────────────────

local function blockAt(node, pathArr)
	local cur = node
	for i = 1, #pathArr do
		if not cur then
			break
		end
		cur = Kdl.childNamed(cur, pathArr[i])
	end
	return cur
end

local function readSetting(inputNode, d)
	local b = blockAt(inputNode, d.path)
	local n = b and Kdl.childNamed(b, d.name) or nil
	if d.kind == "flag" then
		return n ~= nil
	end
	-- bool-valued node (e.g. `drag true`): value if present, true if bare,
	-- false if absent
	if d.kind == "bool" then
		if not n then
			return false
		end
		if n.args[1] then
			return n.args[1].value == true
		end
		return true
	end
	if n and n.args[1] then
		return tostring(n.args[1].value)
	end
	return ""
end

-- Parse an `input` node (one walk per setting) → flat model keyed by `prop`.
function M.parse(inputNode)
	local m = {}
	for _, d in ipairs(M.SETTINGS) do
		m[d.prop] = readSetting(inputNode, d)
	end
	return m
end

-- ── write ────────────────────────────────────────────────────────────────

-- Rows whose value differs from the loaded snapshot.
function M.diff(model, orig)
	local out = {}
	if not model or not orig then
		return out
	end
	for _, d in ipairs(M.SETTINGS) do
		if model[d.prop] ~= orig[d.prop] then
			table.insert(out, { prop = d.prop, path = d.path, name = d.name, kind = d.kind, value = model[d.prop] })
		end
	end
	return out
end

-- JS `parseInt`/`parseFloat` parse a leading numeric prefix and ignore any
-- trailing garbage ("600px" -> 600); Lua's `tonumber` requires the whole
-- string to be numeric. These two helpers restore that leniency for the int/
-- float kinds, matching input.test.js's "edits int uses parseInt prefix".
local function parseIntPrefix(s)
	local m = tostring(s):match("^%s*[+-]?%d+")
	if not m then
		return nil
	end
	return tonumber(m)
end

local function parseFloatPrefix(s)
	local m = tostring(s):match("^%s*[+-]?%d+%.?%d*")
	if not m then
		return nil
	end
	return tonumber(m)
end

-- The finished KDL source line for one changed row, or nil to remove the child.
local function lineFor(d, v)
	if d.kind == "flag" then
		if v then
			return d.name
		end
		return nil
	end
	if d.kind == "bool" then
		return d.name .. " " .. (v and "true" or "false")
	end
	if d.kind == "int" then
		local n = parseIntPrefix(v)
		if v == "" or n == nil then
			return nil
		end
		return d.name .. " " .. tostring(math.floor(n))
	end
	if d.kind == "float" then
		local n = parseFloatPrefix(v)
		if v == "" or n == nil then
			return nil
		end
		return d.name .. " " .. tostring(n)
	end
	if v and v ~= "" then
		return d.name .. ' "' .. v .. '"'
	end
	return nil
end

-- Changed rows → the edit list Kdl.applyChildEdits consumes.
function M.edits(changed)
	local out = {}
	for _, c in ipairs(changed or {}) do
		table.insert(out, { path = c.path, name = c.name, line = lineFor(c, c.value) })
	end
	return out
end

-- Apply every changed row to the config text in a single batched edit.
function M.apply(text, changed)
	return Kdl.applyChildEdits(text, "input", M.edits(changed))
end

return M
