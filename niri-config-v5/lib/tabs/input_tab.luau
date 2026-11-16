--!nonstrict
-- input_tab.luau — the Input tab: a single settings form (Keyboard / Touchpad /
-- Mouse / General) built from lib/input.luau's M.SETTINGS descriptor table.
-- Faithful port of InputSection.qml (niri-config v4) onto the declarative UI /
-- tab module contract.
--
-- Working-edit model: `vals` (module-level, keyed by Input.SETTINGS prop) holds
-- the user's in-progress edits. `ctx.model` (from M.recompute) only ever carries
-- `{ path, orig }` — the last snapshot read from `st`. `vals` is re-seeded from
-- `model.orig` whenever that snapshot actually changes (first open, tab
-- re-entry after an external load/apply/undo/reload, or right after our own
-- Save stages an edit) — never on a render that doesn't reflect new data, so a
-- re-render from a plain `ctx.rerender()` (every keystroke/toggle/picker pick)
-- never clobbers what the user is mid-typing.
local Input = require("../input.luau")
local Xkb = require("../xkb.luau")

local M = { icon = "mouse", label = "Input" }

-- ── static option tables (mirrors InputSection.qml's readonly property lists) ──

local ACCEL_PROFILES = {
	{ key = "", label = "(default)" },
	{ key = "adaptive", label = "adaptive" },
	{ key = "flat", label = "flat" },
}
local SCROLL_METHODS = {
	{ key = "", label = "(default)" },
	{ key = "no-scroll", label = "no-scroll" },
	{ key = "two-finger", label = "two-finger" },
	{ key = "edge", label = "edge" },
	{ key = "on-button-down", label = "on-button-down" },
}
local CLICK_METHODS = {
	{ key = "", label = "(default)" },
	{ key = "button-areas", label = "button-areas" },
	{ key = "clickfinger", label = "clickfinger" },
}
local TAP_MAPS = {
	{ key = "", label = "(default)" },
	{ key = "left-right-middle", label = "left-right-middle" },
	{ key = "left-middle-right", label = "left-middle-right" },
}
local TRACK_LAYOUTS = {
	{ key = "", label = "(default)" },
	{ key = "global", label = "global" },
	{ key = "window", label = "window" },
}
local MOD_KEYS = {
	{ key = "", label = "(default)" },
	{ key = "Super", label = "Super" },
	{ key = "Alt", label = "Alt" },
	{ key = "Ctrl", label = "Ctrl" },
	{ key = "Shift", label = "Shift" },
	{ key = "Mod3", label = "Mod3" },
	{ key = "Mod5", label = "Mod5" },
}

-- ── edit-buffer state ────────────────────────────────────────────────────────

local vals = {} -- current edit buffer, keyed by Input.SETTINGS prop
local seededOrig = nil -- the orig table `vals` was last seeded from
local editGen = 0 -- bumped whenever `vals` changes from OUTSIDE typing (reseed/picker), forces ui.input controls to pick up the new value

local xkbData = nil
local xkbLoaded = false
local xkbLoading = false
local EMPTY_XKB = { layouts = {}, variants = {}, options = {}, models = {} }

local function trim(s)
	return (s:match("^%s*(.-)%s*$"))
end

local function origsEqual(a, b)
	if a == nil or b == nil then
		return a == b
	end
	for _, d in ipairs(Input.SETTINGS) do
		if a[d.prop] ~= b[d.prop] then
			return false
		end
	end
	return true
end

local function seed(orig)
	local v = {}
	for _, d in ipairs(Input.SETTINGS) do
		v[d.prop] = orig[d.prop]
	end
	vals = v
	seededOrig = orig
	editGen += 1
end

local function isDirty(model)
	if model.path == "" then
		return false
	end
	for _, d in ipairs(Input.SETTINGS) do
		if vals[d.prop] ~= model.orig[d.prop] then
			return true
		end
	end
	return false
end

-- niri's layout/options/variant xkb fields are comma-separated lists — append,
-- never replace (lib/input.js's csvAdd, ported verbatim).
local function csvAdd(cur, code)
	if code == nil or code == "" then
		return cur
	end
	local parts = {}
	if cur ~= "" then
		for part in (cur .. ","):gmatch("([^,]*),") do
			table.insert(parts, part)
		end
	end
	for _, p in ipairs(parts) do
		if trim(p) == code then
			return cur
		end
	end
	table.insert(parts, code)
	return table.concat(parts, ",")
end

-- Reading evdev.lst (~45KB) is cheap; parsing all of it inline is not — even
-- deferred to a single fresh callback (see panel.luau's onOpen for the same
-- class of fix) the full parse still measurably exceeded that callback's own
-- CPU budget. So this drives Xkb's incremental newParser/feedLine/finish
-- across as many fresh callbacks as it takes, each bounded to one
-- CHUNK_BYTES slice (rounded out to the next line boundary so a line is
-- never split across chunks) — no single tick does more than a small,
-- fixed amount of work regardless of file size. The previous version set
-- xkbLoaded = true before the parse ran, so a budget-exceeded abort left it
-- permanently "loaded" with xkbData still nil — every later render then
-- crashed on xkbData.layouts instead of retrying. xkbLoaded now only flips
-- once xkbData is actually set, after the last chunk.
local XKB_CHUNK_BYTES = 1200

local function ensureXkb(ctx)
	if xkbLoaded or xkbLoading then
		return
	end
	xkbLoading = true
	noctalia.runAsync({ "true" }, function()
		local text = noctalia.readFile("/usr/share/X11/xkb/rules/evdev.lst")
		if type(text) ~= "string" then
			text = ""
		end
		text = text .. "\n"
		local len = #text
		local state = Xkb.newParser()
		local pos = 1

		local function step()
			local chunkEnd = math.min(pos + XKB_CHUNK_BYTES - 1, len)
			if chunkEnd < len then
				local nl = text:find("\n", chunkEnd, true)
				if nl then
					chunkEnd = nl
				end
			end
			local slice = text:sub(pos, chunkEnd)
			for line in slice:gmatch("([^\n]*)\n") do
				Xkb.feedLine(state, line)
			end
			pos = chunkEnd + 1
			if pos > len then
				xkbData = Xkb.finish(state)
				xkbLoaded = true
				xkbLoading = false
				if ctx and ctx.rerender then
					ctx.rerender()
				end
			else
				noctalia.runAsync({ "true" }, step)
			end
		end

		step()
	end)
end

-- Inserter combo model: a leading no-op/clear entry, then code → description.
local function pickerItems(list, firstLabel)
	local out = { { key = "", label = firstLabel } }
	for _, item in ipairs(list or {}) do
		local label = item.desc
		if label == nil or label == "" then
			label = item.code
		end
		table.insert(out, { key = item.code, label = label })
	end
	return out
end

-- Single-valued model picker: "(default)" + every known model, plus the
-- configured code when evdev.lst does not list it (so a save never drops it).
local function modelPickerItems(list, current)
	local out = { { key = "", label = "(default)" } }
	local seen = {}
	for _, item in ipairs(list or {}) do
		local label = item.desc
		if label == nil or label == "" then
			label = item.code
		end
		table.insert(out, { key = item.code, label = label })
		seen[item.code] = true
	end
	if current ~= "" and not seen[current] then
		table.insert(out, { key = current, label = current })
	end
	return out
end

-- ── small ui.* builders ──────────────────────────────────────────────────────

local function selectControl(options, currentKey, onPick)
	local labels = {}
	local selIdx = 0
	for i, opt in ipairs(options) do
		labels[i] = opt.label
		if opt.key == currentKey then
			selIdx = i - 1
		end
	end
	return ui.select({
		options = labels,
		selectedIndex = selIdx,
		onChange = function(indexStr)
			local i = tonumber(indexStr)
			if i == nil then
				return
			end
			local opt = options[i + 1]
			if opt then
				onPick(opt.key)
			end
		end,
	})
end

local function labeledCell(labelText, control)
	return ui.column({ gap = 4, flexGrow = 1 }, {
		ui.label({ text = labelText, fontSize = 11, color = "on_surface_variant" }),
		control,
	})
end

-- ── per-ctx row builders (closures capture ctx so callbacks can rerender) ────

local function toggleRow(ctx, prop, labelText)
	return ui.row({ gap = 8, align = "center" }, {
		ui.label({ text = labelText, flexGrow = 1 }),
		ui.toggle({
			checked = vals[prop] == true,
			onChange = function(v)
				vals[prop] = v == "true"
				ctx.rerender()
			end,
		}),
	})
end

local function textCell(ctx, prop, labelText, placeholder)
	return labeledCell(
		labelText,
		ui.input({
			key = prop .. "-" .. tostring(editGen),
			value = tostring(vals[prop] or ""),
			placeholder = placeholder,
			onChange = function(v)
				vals[prop] = v
				ctx.rerender()
			end,
		})
	)
end

local function selectCell(ctx, prop, labelText, options)
	return labeledCell(
		labelText,
		selectControl(options, vals[prop] or "", function(key)
			vals[prop] = key
			ctx.rerender()
		end)
	)
end

-- A text field paired with an "Add …" picker that appends the picked code to
-- the field's comma-separated value. `clearOnEmpty` is the variant field's
-- special case: its picker's first ("(none)") entry clears the field instead
-- of being a no-op.
local function appendableField(ctx, prop, labelText, placeholder, addLabel, addOptions, clearOnEmpty)
	return ui.row({ gap = 8 }, {
		textCell(ctx, prop, labelText, placeholder),
		labeledCell(
			addLabel,
			selectControl(addOptions, "", function(key)
				if clearOnEmpty and key == "" then
					vals[prop] = ""
				else
					vals[prop] = csvAdd(vals[prop] or "", key)
				end
				editGen += 1
				ctx.rerender()
			end)
		),
	})
end

local function doSave(ctx, model)
	if model.path == "" then
		return
	end
	local snapshot = {}
	for _, d in ipairs(Input.SETTINGS) do
		snapshot[d.prop] = vals[d.prop]
	end
	local changed = Input.diff(snapshot, model.orig)
	local newText = Input.apply(ctx.st.textOf(model.path), changed)
	ctx.requestSave(model.path, newText, "input settings")
end

-- ── tab module contract ──────────────────────────────────────────────────────

function M.recompute(st)
	local owner = st.ownerOf("input")
	if not owner then
		return { path = "", orig = {} }
	end
	return { path = owner.path, orig = Input.parse(owner.nodes[1]) }
end

function M.sectionFile(st, model)
	local owner = st.ownerOf("input")
	return owner and owner.path or ""
end

function M.render(ctx)
	local model = ctx.model or { path = "", orig = {} }
	if not origsEqual(model.orig, seededOrig) then
		seed(model.orig)
	end

	if model.path == "" then
		return ui.column({ gap = 10 }, {
			ui.label({ text = "Input", fontWeight = "bold" }),
			ui.label({ text = "No input {} block found.", color = "error" }),
		})
	end

	ensureXkb(ctx)

	local xkb = xkbData or EMPTY_XKB
	local primaryLayout = trim(tostring(vals.layout or ""):match("^[^,]*") or "")
	local layoutItems = pickerItems(xkb.layouts, "(add layout…)")
	local optionItems = pickerItems(xkb.options, "(add option…)")
	local variantItems = pickerItems(Xkb.variantsForLayout(xkb, primaryLayout), "(none)")
	local modelItems = modelPickerItems(xkb.models, vals.model or "")

	local dirty = isDirty(model)

	local children = {}

	-- Keyboard
	table.insert(children, ui.label({ text = "Keyboard", fontWeight = "bold", color = "primary" }))
	table.insert(children, appendableField(ctx, "layout", "Layout", "us,de", "Add layout", layoutItems, false))
	table.insert(children, appendableField(ctx, "variant", "Variant", "intl", "Add variant", variantItems, true))
	table.insert(
		children,
		appendableField(ctx, "options", "XKB options", "compose:ralt,ctrl:nocaps", "Add option", optionItems, false)
	)
	table.insert(
		children,
		ui.row({ gap = 8 }, {
			selectCell(ctx, "model", "XKB model", modelItems),
			selectCell(ctx, "trackLayout", "Track layout", TRACK_LAYOUTS),
		})
	)
	table.insert(
		children,
		ui.row({ gap = 8 }, {
			textCell(ctx, "repeatDelay", "Repeat delay (ms)", "600"),
			textCell(ctx, "repeatRate", "Repeat rate", "25"),
		})
	)
	table.insert(children, toggleRow(ctx, "numlock", "Enable numlock at startup"))
	table.insert(children, ui.separator({}))

	-- Touchpad
	table.insert(children, ui.label({ text = "Touchpad", fontWeight = "bold", color = "primary" }))
	table.insert(children, toggleRow(ctx, "tpOff", "Disable touchpad"))
	table.insert(children, toggleRow(ctx, "tpTap", "Tap to click"))
	table.insert(children, toggleRow(ctx, "tpDwt", "Disable while typing"))
	table.insert(children, toggleRow(ctx, "tpDwtp", "Disable while trackpointing"))
	table.insert(children, toggleRow(ctx, "tpNatural", "Natural scrolling"))
	table.insert(children, toggleRow(ctx, "tpDrag", "Tap-and-drag"))
	table.insert(children, toggleRow(ctx, "tpDragLock", "Drag lock"))
	table.insert(children, toggleRow(ctx, "tpMiddleEmu", "Middle-click emulation"))
	table.insert(children, toggleRow(ctx, "tpLeftHanded", "Left-handed"))
	table.insert(children, toggleRow(ctx, "tpDisabledExt", "Disable when external mouse present"))
	table.insert(children, textCell(ctx, "tpAccel", "Acceleration (-1.0 … 1.0)", "0.0"))
	table.insert(
		children,
		ui.row({ gap = 8 }, {
			selectCell(ctx, "tpAccelProfile", "Accel profile", ACCEL_PROFILES),
			selectCell(ctx, "tpScrollMethod", "Scroll method", SCROLL_METHODS),
		})
	)
	table.insert(
		children,
		ui.row({ gap = 8 }, {
			selectCell(ctx, "tpClickMethod", "Click method", CLICK_METHODS),
			selectCell(ctx, "tpTapButtonMap", "Tap button map", TAP_MAPS),
		})
	)
	table.insert(children, ui.separator({}))

	-- Mouse
	table.insert(children, ui.label({ text = "Mouse", fontWeight = "bold", color = "primary" }))
	table.insert(children, toggleRow(ctx, "msOff", "Disable mouse"))
	table.insert(children, toggleRow(ctx, "msNatural", "Natural scrolling"))
	table.insert(children, toggleRow(ctx, "msMiddleEmu", "Middle-click emulation"))
	table.insert(children, toggleRow(ctx, "msLeftHanded", "Left-handed"))
	table.insert(children, textCell(ctx, "msAccel", "Acceleration (-1.0 … 1.0)", "0.0"))
	table.insert(
		children,
		ui.row({ gap = 8 }, {
			selectCell(ctx, "msAccelProfile", "Accel profile", ACCEL_PROFILES),
			selectCell(ctx, "msScrollMethod", "Scroll method", SCROLL_METHODS),
		})
	)
	table.insert(children, ui.separator({}))

	-- General
	table.insert(children, ui.label({ text = "General", fontWeight = "bold", color = "primary" }))
	table.insert(children, selectCell(ctx, "modKey", "Mod key", MOD_KEYS))
	table.insert(children, toggleRow(ctx, "focusFollowsMouse", "Focus follows mouse"))
	table.insert(children, toggleRow(ctx, "warpMouse", "Warp mouse to focus"))
	table.insert(children, toggleRow(ctx, "wsBackAndForth", "Workspace back-and-forth"))
	table.insert(children, toggleRow(ctx, "disablePowerKey", "Disable power key handling"))

	return ui.column({ flexGrow = 1, gap = 10 }, {
		ui.row({ gap = 8, align = "center" }, {
			ui.label({ text = "Input", fontWeight = "bold", flexGrow = 1 }),
			ui.button({
				text = "Save changes",
				variant = "primary",
				enabled = dirty,
				onClick = function()
					doSave(ctx, model)
				end,
			}),
		}),
		ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, children),
	})
end

return M
