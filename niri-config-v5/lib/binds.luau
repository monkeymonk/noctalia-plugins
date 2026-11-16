--!nonstrict
-- binds.luau — model + serialization for niri `binds {}` entries, plus the
-- action vocabulary. Faithful port of lib/binds.js (niri-config v4). Operates
-- on lib/kdl.luau node tables (passed in); no other dependency.

local Kdl = require("./kdl.luau")

local M = {}

-- Modifier canonical names + display order for normalization/conflict detection.
M.MOD_ORDER = { "Mod", "Super", "Ctrl", "Alt", "Shift", "ISO_Level3_Shift", "Mod5" }
local MOD_ALIASES = {
	control = "Ctrl", ctrl = "Ctrl", super = "Super", win = "Super", windows = "Super",
	alt = "Alt", shift = "Shift", mod = "Mod", mod5 = "Mod5", altgr = "ISO_Level3_Shift",
	iso_level3_shift = "ISO_Level3_Shift",
}

-- Recognized bind-line attributes (KDL props on the bind node).
M.BIND_ATTRS = { "hotkey-overlay-title", "repeat", "cooldown-ms", "allow-when-locked", "allow-inhibiting", "hotkey-overlay-hidden" }

-- ── parsing ──────────────────────────────────────────────────────────────

-- Turn a kdl bind node into a model. Keeps `node` for source ranges.
function M.parseBind(node)
	local actions = {}
	for _, c in ipairs(node.children or {}) do
		local args = {}
		for _, a in ipairs(c.args or {}) do
			table.insert(args, a.value)
		end
		table.insert(actions, { name = c.name, args = args })
	end
	return {
		node = node,
		combo = node.name,
		attrs = node.props or {},
		actions = actions,
		disabled = node.slashdash == true,
	}
end

-- All binds inside a parsed `binds {}` node.
function M.parseBinds(bindsNode)
	if not bindsNode or not bindsNode.children then
		return {}
	end
	local out = {}
	for _, n in ipairs(bindsNode.children) do
		table.insert(out, M.parseBind(n))
	end
	return out
end

-- ── combo normalization & conflicts ─────────────────────────────────────

function M.splitCombo(combo)
	local out = {}
	for part in tostring(combo):gmatch("[^+]+") do
		local trimmed = part:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			table.insert(out, trimmed)
		end
	end
	return out
end

-- Canonical string for conflict comparison: sorted mods + uppercased key.
function M.normalizeCombo(combo)
	local parts = M.splitCombo(combo)
	if #parts == 0 then
		return ""
	end
	local key = table.remove(parts)
	local mods = {}
	for i, m in ipairs(parts) do
		mods[i] = MOD_ALIASES[m:lower()] or m
	end
	local seen = {}
	local ordered = {}
	for _, m in ipairs(M.MOD_ORDER) do
		local found = false
		for _, mm in ipairs(mods) do
			if mm == m then found = true break end
		end
		if found and not seen[m] then
			table.insert(ordered, m)
			seen[m] = true
		end
	end
	for _, m in ipairs(mods) do
		if not seen[m] then
			table.insert(ordered, m)
			seen[m] = true
		end
	end
	table.insert(ordered, key:upper())
	return table.concat(ordered, "+")
end

-- Returns the first ENABLED bind whose combo conflicts, excluding `exceptNode`
-- (the bind being edited).
function M.findConflict(binds, combo, exceptNode)
	local norm = M.normalizeCombo(combo)
	local exRange = (exceptNode and exceptNode.range) and exceptNode.range[1] or -1
	for _, b in ipairs(binds) do
		if not b.disabled then
			local isExcepted = exceptNode ~= nil
				and (b.node == exceptNode or (b.node and b.node.range and b.node.range[1] == exRange))
			if not isExcepted and M.normalizeCombo(b.combo) == norm then
				return b
			end
		end
	end
	return nil
end

-- ── serialization ────────────────────────────────────────────────────────

function M.quoteString(s)
	local escaped = tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"')
	return '"' .. escaped .. '"'
end

function M.formatPropValue(v)
	if v == true then
		return "true"
	end
	if v == false then
		return "false"
	end
	if type(v) == "number" then
		return tostring(v)
	end
	if v == Kdl.NULL then
		return "null"
	end
	return M.quoteString(v)
end

-- Args for an action. Numbers stay bare (focus-workspace 1); strings get
-- quoted (spawn "ghostty", set-column-width "-10%").
local function formatActionArg(a)
	if type(a) == "number" then
		return tostring(a)
	end
	if a == true then
		return "true"
	end
	if a == false then
		return "false"
	end
	return M.quoteString(a)
end

local function formatAction(act)
	local s = act.name
	if act.args and #act.args > 0 then
		local parts = {}
		for i, a in ipairs(act.args) do
			parts[i] = formatActionArg(a)
		end
		s = s .. " " .. table.concat(parts, " ")
	end
	return s
end

-- Serialize one bind to a config line (no leading indent, no trailing
-- newline). opts.padTo pads the combo to a column for alignment.
function M.serializeBind(b, opts)
	opts = opts or {}
	local combo = b.combo
	local attrParts = {}
	for _, k in ipairs(M.BIND_ATTRS) do
		if b.attrs and b.attrs[k] ~= nil then
			table.insert(attrParts, k .. "=" .. M.formatPropValue(b.attrs[k]))
		end
	end
	if b.attrs then
		for k, v in pairs(b.attrs) do
			local known = false
			for _, kk in ipairs(M.BIND_ATTRS) do
				if kk == k then known = true break end
			end
			if not known then
				table.insert(attrParts, k .. "=" .. M.formatPropValue(v))
			end
		end
	end
	local head
	if opts.padTo and #combo < opts.padTo then
		head = combo .. string.rep(" ", opts.padTo - #combo)
	else
		head = combo .. " "
	end
	local attrStr = (#attrParts > 0) and (table.concat(attrParts, " ") .. " ") or ""
	local actParts = {}
	for i, a in ipairs(b.actions or {}) do
		actParts[i] = formatAction(a)
	end
	local actStr = table.concat(actParts, "; ")
	local line = head .. attrStr .. "{ " .. actStr .. (actStr ~= "" and "; " or "") .. "}"
	if b.disabled then
		line = "/-" .. line
	end
	return line
end

-- Suggest an alignment column from a set of binds (max combo length + 2, capped).
function M.alignColumnFor(binds)
	local max = 0
	for _, b in ipairs(binds or {}) do
		if #b.combo > max then
			max = #b.combo
		end
	end
	return math.min(math.max(max + 2, 20), 40)
end

-- ── human-readable description (for list UI) ────────────────────────────

function M.describeAction(act)
	if not act then
		return ""
	end
	if act.name == "spawn" or act.name == "spawn-sh" then
		if act.args and #act.args > 0 then
			local parts = {}
			for i, a in ipairs(act.args) do
				parts[i] = tostring(a)
			end
			return table.concat(parts, " ")
		end
		return act.name
	end
	local base = (act.name:gsub("%-", " "))
	if act.args and #act.args > 0 then
		local parts = {}
		for i, a in ipairs(act.args) do
			parts[i] = tostring(a)
		end
		base = base .. " " .. table.concat(parts, " ")
	end
	return base
end

function M.describeBind(b)
	return M.describeAction(b.actions and b.actions[1])
end

-- ── action vocabulary ────────────────────────────────────────────────────
-- arg types: "none" | "string" | "spawn" | "workspaceRef" | "amount" | "index"
M.ACTIONS = {
	-- Applications / system
	{ name = "spawn", cat = "system", arg = "spawn" },
	{ name = "spawn-sh", cat = "system", arg = "spawn" },
	{ name = "close-window", cat = "window", arg = "none" },
	{ name = "quit", cat = "system", arg = "none" },
	{ name = "show-hotkey-overlay", cat = "system", arg = "none" },
	{ name = "toggle-overview", cat = "system", arg = "none" },
	{ name = "power-off-monitors", cat = "system", arg = "none" },
	{ name = "power-on-monitors", cat = "system", arg = "none" },
	{ name = "screenshot", cat = "system", arg = "none" },
	{ name = "screenshot-screen", cat = "system", arg = "none" },
	{ name = "screenshot-window", cat = "system", arg = "none" },
	{ name = "toggle-keyboard-shortcuts-inhibit", cat = "system", arg = "none" },
	-- Window / floating / fullscreen
	{ name = "fullscreen-window", cat = "window", arg = "none" },
	{ name = "toggle-windowed-fullscreen", cat = "window", arg = "none" },
	{ name = "toggle-window-floating", cat = "window", arg = "none" },
	{ name = "switch-focus-between-floating-and-tiling", cat = "window", arg = "none" },
	{ name = "center-window", cat = "window", arg = "none" },
	-- Focus
	{ name = "focus-column-left", cat = "focus", arg = "none" },
	{ name = "focus-column-right", cat = "focus", arg = "none" },
	{ name = "focus-column-first", cat = "focus", arg = "none" },
	{ name = "focus-column-last", cat = "focus", arg = "none" },
	{ name = "focus-column-or-monitor-left", cat = "focus", arg = "none" },
	{ name = "focus-column-or-monitor-right", cat = "focus", arg = "none" },
	{ name = "focus-window-up", cat = "focus", arg = "none" },
	{ name = "focus-window-down", cat = "focus", arg = "none" },
	{ name = "focus-window-or-workspace-up", cat = "focus", arg = "none" },
	{ name = "focus-window-or-workspace-down", cat = "focus", arg = "none" },
	{ name = "focus-workspace-up", cat = "focus", arg = "none" },
	{ name = "focus-workspace-down", cat = "focus", arg = "none" },
	{ name = "focus-workspace-previous", cat = "focus", arg = "none" },
	{ name = "focus-workspace", cat = "focus", arg = "workspaceRef" },
	{ name = "focus-monitor-left", cat = "focus", arg = "none" },
	{ name = "focus-monitor-right", cat = "focus", arg = "none" },
	{ name = "focus-monitor-up", cat = "focus", arg = "none" },
	{ name = "focus-monitor-down", cat = "focus", arg = "none" },
	-- Move
	{ name = "move-column-left", cat = "move", arg = "none" },
	{ name = "move-column-right", cat = "move", arg = "none" },
	{ name = "move-column-to-first", cat = "move", arg = "none" },
	{ name = "move-column-to-last", cat = "move", arg = "none" },
	{ name = "move-column-left-or-to-monitor-left", cat = "move", arg = "none" },
	{ name = "move-column-right-or-to-monitor-right", cat = "move", arg = "none" },
	{ name = "move-window-up", cat = "move", arg = "none" },
	{ name = "move-window-down", cat = "move", arg = "none" },
	{ name = "move-window-up-or-to-workspace-up", cat = "move", arg = "none" },
	{ name = "move-window-down-or-to-workspace-down", cat = "move", arg = "none" },
	{ name = "move-column-to-workspace", cat = "move", arg = "workspaceRef" },
	{ name = "move-window-to-workspace", cat = "move", arg = "workspaceRef" },
	{ name = "move-column-to-monitor-left", cat = "move", arg = "none" },
	{ name = "move-column-to-monitor-right", cat = "move", arg = "none" },
	{ name = "move-column-to-monitor-up", cat = "move", arg = "none" },
	{ name = "move-column-to-monitor-down", cat = "move", arg = "none" },
	-- Sizing / layout
	{ name = "set-column-width", cat = "layout", arg = "amount" },
	{ name = "set-window-height", cat = "layout", arg = "amount" },
	{ name = "expand-column-to-available-width", cat = "layout", arg = "none" },
	{ name = "maximize-column", cat = "layout", arg = "none" },
	{ name = "center-column", cat = "layout", arg = "none" },
	{ name = "center-visible-columns", cat = "layout", arg = "none" },
	{ name = "switch-preset-column-width", cat = "layout", arg = "none" },
	{ name = "switch-preset-window-height", cat = "layout", arg = "none" },
	{ name = "toggle-column-tabbed-display", cat = "layout", arg = "none" },
	{ name = "consume-window-into-column", cat = "layout", arg = "none" },
	{ name = "expel-window-from-column", cat = "layout", arg = "none" },
	{ name = "consume-or-expel-window-left", cat = "layout", arg = "none" },
	{ name = "consume-or-expel-window-right", cat = "layout", arg = "none" },
}

function M.actionSpec(name)
	for _, a in ipairs(M.ACTIONS) do
		if a.name == name then
			return a
		end
	end
	return nil
end

return M
