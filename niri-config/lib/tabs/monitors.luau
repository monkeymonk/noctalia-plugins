--!nonstrict
-- monitors.luau — the Monitors tab. Faithful port of MonitorsSection.qml +
-- MonitorEditor.qml + MonitorAddDialog.qml (niri-config v4) onto the v5
-- declarative-panel tab contract.
--
-- Two mutually-exclusive UIs, gated by `noctalia.commandExists("monique")`
-- (synchronous — lib/monique.luau dropped v4's separate async checkCmd):
--   * monique available: a list of Monique profiles, click to switch.
--   * monique unavailable: per-monitor cards merging live `niri msg
--     --json outputs` state with configured `output {}` blocks, each
--     editable via an in-tab "edit" screen (no native modal exists — see
--     panel.luau's header comment on the stack-navigation pattern).
--
-- Module-level locals hold cross-render state (same VM instance for the
-- panel's whole lifetime, exactly like panel.luau's own `currentSection`):
--   * live data caches (liveOutputs, moniqueAvailable, profiles, activeProfile)
--     populated by async noctalia.runAsync callbacks, never by M.recompute
--     (which stays synchronous/pure — only a first-render or explicit
--     refresh kicks off IO, per the task's "on first render (or manual
--     Refresh)" contract);
--   * `view` + the `ed*`/`addNameText` edit-form fields for the in-tab
--     screen swap.
local Kdl = require("../kdl.luau")
local Outputs = require("../outputs.luau")
local Niri = require("../niri.luau")
local Monique = require("../monique.luau")

local M = { icon = "device-desktop", label = "Monitors" }

-- ── cross-render state ──────────────────────────────────────────────────

local started = false -- guards the one-shot initial live-outputs/monique fetch
local liveOutputs = {} -- Niri.parseOutputs() result, refreshed async
local loadError = ""
local moniqueAvailable = false
local profiles = {} -- array of profile name strings
local activeProfile = ""

local previewCmds = {} -- queued argv arrays, drained one at a time
local previewBusy = false

-- "list" | "edit" | "add"
local view = "list"

-- edit-form fields (seeded by openEditFor)
local edTarget = nil -- the merged record {name, detected, configured} being edited
local edMode = ""
local edScale = "1"
local edTransform = "Normal"
local edX = "0"
local edY = "0"
local edVrr = false
local edVrrOnDemand = false
local edOff = false
local edFocusStartup = false
local edBackdrop = ""

-- add-by-name form field
local addNameText = ""
local addFormSeq = 0 -- bumped on each "add" open so the input gets a fresh
-- key, forcing a brand-new control instance (re-seeds its text and
-- re-grabs focus) instead of a stale one from a previous open — see
-- declarative-ui docs' "give it a fresh key to re-focus" guidance.

-- ── helpers ──────────────────────────────────────────────────────────────

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Where new `output {}` blocks get appended / Add-config writes: the
-- noctalia default cfg/display.kdl when loaded, else whichever loaded file
-- already owns `output` blocks, else the main config (always included).
local function displayFile(st)
	for _, f in ipairs(st.files) do
		if f.path:find("cfg/display.kdl", 1, true) ~= nil then
			return f.path
		end
	end
	local ow = st.ownerOf("output")
	if ow and ow.path then
		return ow.path
	end
	return st.mainPath
end

local function buildMerged(st)
	local byName = {}
	for _, o in ipairs(liveOutputs) do
		byName[o.name] = { name = o.name, detected = o, configured = nil }
	end
	if st.loaded then
		local owners = st.allOwners({ "output" })
		for _, ow in ipairs(owners) do
			for _, n in ipairs(ow.nodes) do
				if n.name == "output" and n.args[1] then
					local nm = tostring(n.args[1].value)
					if not byName[nm] then
						byName[nm] = { name = nm, detected = nil, configured = nil }
					end
					byName[nm].configured = { model = Outputs.parseOutput(n), node = n, path = ow.path }
				end
			end
		end
	end
	local merged = {}
	for _, v in pairs(byName) do
		table.insert(merged, v)
	end
	table.sort(merged, function(a, b)
		return a.name < b.name
	end)
	return merged
end

-- ── async data fetches ──────────────────────────────────────────────────

local function queryLiveOutputs(ctx)
	noctalia.runAsync(Niri.jsonCmd("outputs"), function(result)
		if result.exitCode == 0 then
			liveOutputs = Niri.parseOutputs(result.stdout or "")
			loadError = ""
		else
			loadError = "Could not query niri outputs."
		end
		ctx.recompute()
		ctx.rerender()
	end)
end

local function refreshProfiles(ctx)
	if not moniqueAvailable then
		return
	end
	noctalia.runAsync(Monique.listProfilesCmd(), function(result)
		profiles = Monique.parseProfiles(result.stdout or "")
		ctx.recompute()
		ctx.rerender()
	end)
	noctalia.runAsync(Monique.currentProfileCmd(), function(result)
		activeProfile = (result.exitCode == 0) and trim(result.stdout or "") or ""
		ctx.recompute()
		ctx.rerender()
	end)
end

-- One-shot kickoff: live outputs + monique availability are independent,
-- each re-renders on its own completion rather than waiting on the other.
local function ensureStarted(ctx)
	if started then
		return
	end
	started = true
	moniqueAvailable = noctalia.commandExists("monique")
	queryLiveOutputs(ctx)
	if moniqueAvailable then
		refreshProfiles(ctx)
	end
end

local function switchProfile(ctx, name)
	if name == activeProfile then
		return
	end
	noctalia.runAsync(Monique.switchProfileCmd(name), function(result)
		if result.exitCode ~= 0 then
			return
		end
		activeProfile = name
		-- monique rewrote the monitor file on disk — refresh our own live
		-- snapshot so the tab's state is current (we have no access to the
		-- panel chrome's own reloadConfig()).
		queryLiveOutputs(ctx)
	end)
end

-- ── live preview queue (ported faithfully from previewCmds/previewBusy/
-- previewNext in MonitorsSection.qml) ──────────────────────────────────

local function previewNext()
	if previewBusy or #previewCmds == 0 then
		return
	end
	previewBusy = true
	local cmd = table.remove(previewCmds, 1)
	local launched = noctalia.runAsync(cmd, function(result)
		previewBusy = false
		if result.exitCode ~= 0 then
			loadError = "Preview failed — niri rejected a monitor change."
		end
		previewNext()
	end)
	if not launched then
		-- never actually spawned — would otherwise wedge the queue forever.
		previewBusy = false
	end
end

local function previewProp(name, prop, value)
	local cmd = Niri.outputCmd(name, prop, value)
	if not cmd then
		return
	end
	table.insert(previewCmds, cmd)
	previewNext()
end

-- A fresh preview run drops anything still queued from a previous click;
-- an already-in-flight command (previewBusy) is left to finish.
local function previewSettings(name, s)
	previewCmds = {}
	previewProp(name, "mode", s.mode)
	previewProp(name, "scale", s.scale ~= nil and tostring(s.scale) or "")
	previewProp(name, "transform", s.transform)
	previewProp(name, "position", { s.x ~= nil and tostring(s.x) or "", s.y ~= nil and tostring(s.y) or "" })
	previewProp(name, "vrr", s.vrr and "on" or "off")
end

-- ── persistence ──────────────────────────────────────────────────────────

local function persist(ctx, model)
	local st = ctx.st
	local path, newText
	if edTarget and edTarget.configured then
		local cfg = edTarget.configured
		local src = st.textOf(cfg.path)
		local indent = Kdl.leadingIndent(src, cfg.node.range)
		newText = Kdl.replaceNodeLine(src, cfg.node, indent .. Outputs.serializeOutput(model, "    "))
		path = cfg.path
	else
		path = displayFile(st)
		newText = Kdl.appendNode(st.textOf(path), Outputs.serializeOutput(model, "    "))
	end
	view = "list"
	ctx.requestSave(path, newText, "monitor " .. model.name)
end

local function removeConfig(ctx, configured)
	local st = ctx.st
	local text = Kdl.removeNodeLine(st.textOf(configured.path), configured.node)
	view = "list"
	ctx.requestSave(configured.path, text, "remove monitor config")
end

local function addConfig(ctx, name)
	local st = ctx.st
	local path = displayFile(st)
	local text = Kdl.appendNode(st.textOf(path), 'output "' .. name .. '" {\n}')
	view = "list"
	ctx.requestSave(path, text, "add monitor " .. name)
end

-- ── edit-form seeding + model build (ports MonitorEditor.openFor/buildModel) ──

local function openEditFor(rec)
	edTarget = rec
	local det = rec.detected
	local cfg = rec.configured
	local cm = cfg and cfg.model or nil

	if cm and cm.mode ~= "" then
		edMode = cm.mode
	elseif det then
		edMode = det.currentModeLabel
	else
		edMode = ""
	end

	if cm and cm.scale ~= nil then
		edScale = tostring(cm.scale)
	elseif det then
		edScale = tostring(det.scale)
	else
		edScale = "1"
	end

	if cm and cm.transform then
		edTransform = cm.transform
	elseif det then
		edTransform = det.transform
	else
		edTransform = "Normal"
	end

	if cm and cm.x ~= nil then
		edX = tostring(cm.x)
	elseif det then
		edX = tostring(det.x)
	else
		edX = "0"
	end

	if cm and cm.y ~= nil then
		edY = tostring(cm.y)
	elseif det then
		edY = tostring(det.y)
	else
		edY = "0"
	end

	if cm then
		edVrr = cm.vrr
		edVrrOnDemand = cm.vrrOnDemand
		edOff = cm.off
		edFocusStartup = cm.focusAtStartup
		edBackdrop = cm.backdropColor or ""
	else
		edVrr = det ~= nil and det.vrrEnabled or false
		edVrrOnDemand = false
		edOff = false
		edFocusStartup = false
		edBackdrop = ""
	end

	view = "edit"
end

local function parseIntField(s)
	if s == nil or s == "" then
		return nil
	end
	local n = tonumber(s)
	if n == nil then
		return nil
	end
	-- parseInt-style truncation toward zero (not math.floor, which rounds
	-- negative values the wrong way).
	return n >= 0 and math.floor(n) or math.ceil(n)
end

local function parseFloatField(s)
	if s == nil or s == "" then
		return nil
	end
	return tonumber(s)
end

local function buildModel(name)
	return {
		name = name,
		off = edOff,
		mode = edMode,
		scale = parseFloatField(edScale),
		x = parseIntField(edX),
		y = parseIntField(edY),
		transform = edTransform,
		vrr = edVrr,
		vrrOnDemand = edVrrOnDemand,
		focusAtStartup = edFocusStartup,
		backdropColor = edBackdrop,
	}
end

-- ── render: Monique profiles branch ─────────────────────────────────────

local function renderMonique(ctx, model)
	local body = {}

	table.insert(
		body,
		ui.row({ gap = 8, align = "center" }, {
			ui.label({ text = "Profiles (Monique)", fontWeight = "bold", color = "primary", flexGrow = 1 }),
			ui.button({
				text = "New / edit",
				glyph = "external-link",
				variant = "outline",
				onClick = function()
					noctalia.runAsync({ "monique" })
				end,
			}),
			ui.button({
				glyph = "refresh",
				variant = "ghost",
				tooltip = "Refresh",
				onClick = function()
					refreshProfiles(ctx)
					ctx.rerender()
				end,
			}),
		})
	)

	if model.loadError ~= "" then
		table.insert(body, ui.label({ text = model.loadError, color = "error", fontSize = 11 }))
	end

	local rows = {}
	if #model.profiles == 0 then
		table.insert(
			rows,
			ui.label({
				text = 'No profiles yet — use "New / edit" to create one in Monique.',
				color = "on_surface_variant",
				fontSize = 12,
			})
		)
	else
		for _, name in ipairs(model.profiles) do
			local isActive = name == model.activeProfile
			table.insert(
				rows,
				ui.row({
					key = "profile-" .. name,
					gap = 12,
					align = "center",
					padding = 8,
					radius = 8,
					fill = isActive and "primary" or "surface_variant",
					onClick = isActive and nil or function()
						switchProfile(ctx, name)
						ctx.rerender()
					end,
				}, {
					ui.glyph({ name = "device-desktop", size = 18, color = isActive and "on_primary" or "primary" }),
					ui.label({
						text = name,
						flexGrow = 1,
						color = isActive and "on_primary" or "on_surface",
						fontWeight = isActive and "bold" or "normal",
					}),
					ui.glyph({ name = "check", size = 18, color = "on_primary", visible = isActive }),
				})
			)
		end
		table.insert(
			rows,
			ui.label({
				text = 'Monitors are managed by Monique — pick a profile to apply it, or use "New / edit" to '
					.. "create/update profiles.",
				color = "on_surface_variant",
				fontSize = 10,
			})
		)
	end

	table.insert(body, ui.scroll({ flexGrow = 1, gap = 8 }, rows))

	return ui.column({ flexGrow = 1, gap = 10 }, body)
end

-- ── render: per-monitor card list (monique unavailable) ─────────────────

local function monitorSubtitle(det)
	if not det then
		return "not connected"
	end
	local mk = trim(((det.make or "") .. " " .. (det.model or "")))
	return mk ~= "" and mk or "connected"
end

local function renderList(ctx, model)
	local body = {}

	table.insert(
		body,
		ui.row({ gap = 8, align = "center" }, {
			ui.label({ text = tostring(#model.merged) .. " monitors", fontWeight = "bold", flexGrow = 1 }),
			ui.button({
				text = "Add config",
				glyph = "plus",
				enabled = ctx.st.loaded,
				onClick = function()
					addNameText = ""
					addFormSeq = addFormSeq + 1
					view = "add"
					ctx.rerender()
				end,
			}),
		})
	)

	table.insert(
		body,
		ui.label({
			text = "Preview applies live (reverts on reload). Save writes the output block; Add lets you "
				.. "configure a disconnected monitor for another setup.",
			color = "on_surface_variant",
			fontSize = 11,
		})
	)

	if model.loadError ~= "" then
		table.insert(body, ui.label({ text = model.loadError, color = "error" }))
	end

	local cards = {}
	if #model.merged == 0 then
		table.insert(cards, ui.label({ text = "No monitors.", color = "on_surface_variant" }))
	else
		for _, rec in ipairs(model.merged) do
			local rowChildren = {
				ui.glyph({
					name = "device-desktop",
					size = 18,
					color = rec.detected and "primary" or "on_surface_variant",
				}),
				ui.column({ flexGrow = 1, gap = 0 }, {
					ui.label({
						text = rec.name .. (rec.configured and "  ·  configured" or ""),
						fontWeight = "medium",
						maxLines = 1,
					}),
					ui.label({
						text = monitorSubtitle(rec.detected),
						color = "on_surface_variant",
						fontSize = 10,
						maxLines = 1,
					}),
				}),
				ui.button({
					glyph = "edit",
					variant = "ghost",
					tooltip = "Edit",
					onClick = function()
						openEditFor(rec)
						ctx.rerender()
					end,
				}),
			}
			if rec.configured then
				table.insert(
					rowChildren,
					ui.button({
						glyph = "trash",
						variant = "ghost",
						tooltip = "Remove config",
						onClick = function()
							removeConfig(ctx, rec.configured)
						end,
					})
				)
			end
			table.insert(
				cards,
				ui.row({
					key = "mon-" .. rec.name,
					gap = 12,
					align = "center",
					padding = 8,
					radius = 8,
					fill = "surface_variant",
					onClick = function()
						openEditFor(rec)
						ctx.rerender()
					end,
				}, rowChildren)
			)
		end
	end
	table.insert(body, ui.scroll({ flexGrow = 1, gap = 10 }, cards))

	return ui.column({ flexGrow = 1, gap = 10 }, body)
end

-- ── render: edit screen (monique unavailable) ────────────────────────────

local function field(labelText, control)
	return ui.column({ gap = 4 }, {
		ui.label({ text = labelText, fontSize = 11, color = "on_surface_variant" }),
		control,
	})
end

local function renderEditScreen(ctx, model)
	local rec = edTarget
	if not rec then
		view = "list"
		return renderList(ctx, model)
	end
	local det = rec.detected
	local cfg = rec.configured
	local children = {}

	table.insert(
		children,
		ui.row({ gap = 8, align = "center" }, {
			ui.button({
				glyph = "arrow-left",
				variant = "ghost",
				onClick = function()
					view = "list"
					ctx.rerender()
				end,
			}),
			ui.label({ text = rec.name, fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
		})
	)
	table.insert(children, ui.label({ text = monitorSubtitle(det), color = "on_surface_variant", fontSize = 10 }))

	-- mode: live select when modes are known, else a free-text fallback
	-- (e.g. pre-configuring a disconnected monitor).
	if det and #det.modes > 0 then
		local options = {}
		local selIdx = nil
		for i, m in ipairs(det.modes) do
			options[i] = m.label .. (m.preferred and "  ★" or "")
			if m.label == edMode then
				selIdx = i - 1
			end
		end
		table.insert(
			children,
			field(
				"Resolution & refresh",
				ui.select({
					options = options,
					selectedIndex = selIdx,
					onChange = function(idxStr)
						local idx = tonumber(idxStr)
						if idx ~= nil and det.modes[idx + 1] then
							edMode = det.modes[idx + 1].label
							ctx.rerender()
						end
					end,
				})
			)
		)
	else
		table.insert(
			children,
			field(
				"Resolution & refresh",
				ui.input({
					key = "mode-" .. rec.name,
					value = edMode,
					placeholder = "1920x1080@60.000",
					onChange = function(v)
						edMode = v
					end,
				})
			)
		)
	end

	local tIdx = 0
	for i, t in ipairs(Outputs.TRANSFORMS) do
		if t == edTransform then
			tIdx = i - 1
			break
		end
	end
	table.insert(
		children,
		ui.row({ gap = 10 }, {
			field(
				"Scale",
				ui.input({
					key = "scale-" .. rec.name,
					value = edScale,
					placeholder = "1.0",
					onChange = function(v)
						edScale = v
					end,
				})
			),
			field(
				"Transform",
				ui.select({
					options = Outputs.TRANSFORMS,
					selectedIndex = tIdx,
					onChange = function(idxStr)
						local idx = tonumber(idxStr)
						if idx ~= nil and Outputs.TRANSFORMS[idx + 1] then
							edTransform = Outputs.TRANSFORMS[idx + 1]
							ctx.rerender()
						end
					end,
				})
			),
		})
	)

	table.insert(
		children,
		ui.row({ gap = 10 }, {
			field(
				"Position X",
				ui.input({
					key = "posx-" .. rec.name,
					value = edX,
					placeholder = "0",
					onChange = function(v)
						edX = v
					end,
				})
			),
			field(
				"Position Y",
				ui.input({
					key = "posy-" .. rec.name,
					value = edY,
					placeholder = "0",
					onChange = function(v)
						edY = v
					end,
				})
			),
		})
	)

	local vrrVisible = (det == nil) or det.vrrSupported
	table.insert(
		children,
		ui.row({ align = "center", gap = 8, visible = vrrVisible }, {
			ui.label({ text = "Variable refresh rate (VRR)", flexGrow = 1 }),
			ui.toggle({
				checked = edVrr,
				onChange = function(v)
					edVrr = v == "true"
					ctx.rerender()
				end,
			}),
		})
	)
	table.insert(
		children,
		ui.row({ align = "center", gap = 8, visible = vrrVisible and edVrr }, {
			ui.label({ text = "VRR on-demand only", flexGrow = 1 }),
			ui.toggle({
				checked = edVrrOnDemand,
				onChange = function(v)
					edVrrOnDemand = v == "true"
				end,
			}),
		})
	)

	table.insert(
		children,
		field(
			"Backdrop color",
			ui.input({
				key = "backdrop-" .. rec.name,
				value = edBackdrop,
				placeholder = "#000000",
				onChange = function(v)
					edBackdrop = v
				end,
			})
		)
	)

	table.insert(
		children,
		ui.row({ align = "center", gap = 8 }, {
			ui.label({ text = "Focus at startup", flexGrow = 1 }),
			ui.toggle({
				checked = edFocusStartup,
				onChange = function(v)
					edFocusStartup = v == "true"
				end,
			}),
		})
	)
	table.insert(
		children,
		ui.row({ align = "center", gap = 8 }, {
			ui.label({ text = "Disable this output (off)", flexGrow = 1 }),
			ui.toggle({
				checked = edOff,
				onChange = function(v)
					edOff = v == "true"
				end,
			}),
		})
	)

	local actionButtons = {}
	if det then
		table.insert(
			actionButtons,
			ui.button({
				text = "Preview live",
				variant = "outline",
				onClick = function()
					previewSettings(rec.name, buildModel(rec.name))
				end,
			})
		)
	end
	table.insert(actionButtons, ui.spacer({ flexGrow = 1 }))
	if cfg then
		table.insert(
			actionButtons,
			ui.button({
				text = "Remove config",
				variant = "destructive",
				onClick = function()
					removeConfig(ctx, cfg)
				end,
			})
		)
	end
	table.insert(
		actionButtons,
		ui.button({
			text = "Save",
			variant = "primary",
			onClick = function()
				persist(ctx, buildModel(rec.name))
			end,
		})
	)
	table.insert(children, ui.row({ gap = 10 }, actionButtons))

	return ui.scroll({ flexGrow = 1, gap = 12 }, children)
end

-- ── render: add-by-name screen (monique unavailable) ─────────────────────

local function renderAddScreen(ctx, _model)
	local children = {}

	table.insert(
		children,
		ui.row({ gap = 8, align = "center" }, {
			ui.button({
				glyph = "arrow-left",
				variant = "ghost",
				onClick = function()
					view = "list"
					ctx.rerender()
				end,
			}),
			ui.label({ text = "Add monitor config", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
		})
	)
	table.insert(
		children,
		ui.label({
			text = "Use the exact connector or model name (run `niri msg outputs`).",
			color = "on_surface_variant",
			fontSize = 11,
		})
	)
	table.insert(
		children,
		ui.input({
			key = "add-" .. addFormSeq,
			value = addNameText,
			placeholder = 'DP-2 or "Maker Model …"',
			focus = true,
			onChange = function(v)
				addNameText = v
			end,
			onSubmit = function()
				local n = trim(addNameText)
				if n ~= "" then
					addConfig(ctx, n)
				end
			end,
		})
	)
	table.insert(
		children,
		ui.row({ gap = 10 }, {
			ui.spacer({ flexGrow = 1 }),
			ui.button({
				text = "Cancel",
				variant = "outline",
				onClick = function()
					view = "list"
					ctx.rerender()
				end,
			}),
			ui.button({
				text = "Add",
				variant = "primary",
				enabled = trim(addNameText) ~= "",
				onClick = function()
					local n = trim(addNameText)
					if n ~= "" then
						addConfig(ctx, n)
					end
				end,
			}),
		})
	)

	return ui.column({ gap = 12 }, children)
end

-- ── tab contract ─────────────────────────────────────────────────────────

function M.recompute(st)
	return {
		merged = buildMerged(st),
		loadError = loadError,
		moniqueAvailable = moniqueAvailable,
		profiles = profiles,
		activeProfile = activeProfile,
	}
end

-- Omitted-function semantics aren't reachable (monique availability is only
-- known after an async/sync probe at runtime, not at module-definition
-- time): return "" when monique manages monitors so the header's file-path
-- row simply doesn't render, which is the same visible effect as omitting
-- the function entirely.
function M.sectionFile(st, _model)
	if moniqueAvailable then
		return ""
	end
	return displayFile(st)
end

function M.render(ctx)
	ensureStarted(ctx)
	-- Recompute fresh rather than trusting `ctx.model`: `ensureStarted` may
	-- have just set `moniqueAvailable` synchronously (first open), and using
	-- the snapshot panel.luau captured BEFORE that call would show the
	-- per-monitor list for one frame even when Monique is installed.
	-- M.recompute is cheap (no reparse), so recomputing here is free.
	local model = M.recompute(ctx.st)

	if model.moniqueAvailable then
		return renderMonique(ctx, model)
	end
	if view == "edit" then
		return renderEditScreen(ctx, model)
	elseif view == "add" then
		return renderAddScreen(ctx, model)
	end
	return renderList(ctx, model)
end

return M
