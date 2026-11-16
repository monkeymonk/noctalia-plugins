--!nonstrict
-- panel.luau — the [[panel]] entry: header chrome (Apply/Undo/Reload/docs,
-- pending-change subtitle, per-tab file path), a data-driven left nav, and
-- dispatch into one tab module's render() for the body. Faithful port of
-- Panel.qml's chrome (niri-config v4), minus the Scripts/Workspaces/Layout/
-- etc tabs this phase defers (see README).
--
-- Tab module contract (lib/tabs/<name>.luau), so adding a tab later is a
-- self-contained addition — append one TAB_MODULES entry + write the module,
-- no chrome change required:
--   M.icon          glyph name for the nav row
--   M.label         plain English nav label
--   M.recompute(st) -> model                 called after load/stage/apply/undo/reload
--   M.sectionFile(st, model) -> path | ""    optional; omit => no file-path row
--   M.render(ctx) -> ui.* tree               ctx = { st, model, requestSave, rerender, recompute }
--   M.onKey(chord, pressed, ctx)             optional; only a tab with live key capture needs this
--
-- UI pattern for sub-screens (add/edit forms, pickers): there is no native
-- modal/Popup primitive in the declarative UI vocabulary (panels ARE the
-- modal surface). Each tab that needs one keeps its own `view` local
-- ("list" | "edit" | "pick-action" | ...) and swaps its OWN render() output
-- between a list screen and a form screen, with a Cancel/Back button — a
-- single-tab "stack navigation", not an overlay. This keeps every tab
-- self-contained (the chrome doesn't know or care).
local State = require("./lib/state.luau")
local Cfg = require("./lib/config.luau")

-- niri wiki page per section (opened via the header help button).
local DOC_URLS = {
	shortcuts = "https://github.com/YaLTeR/niri/wiki/Configuration:-Key-Bindings",
	monitors = "https://github.com/YaLTeR/niri/wiki/Configuration:-Outputs",
	input = "https://github.com/YaLTeR/niri/wiki/Configuration:-Input",
}

-- Data-driven nav/tab registry. Phase 1 wires 3 of the eventual 10 sections;
-- the other 7 (Workspaces, Window rules, Layout, Animation, Autostart, Misc,
-- Scripts) are simply not listed here yet — appending their entries later is
-- the entire integration cost, nothing else in this file changes.
local TAB_MODULES = {
	{ key = "shortcuts", path = "./lib/tabs/shortcuts.luau" },
	{ key = "monitors", path = "./lib/tabs/monitors.luau" },
	{ key = "input", path = "./lib/tabs/input_tab.luau" },
}

local Tabs = {}
local TAB_ORDER = {}
for _, t in ipairs(TAB_MODULES) do
	Tabs[t.key] = require(t.path)
	table.insert(TAB_ORDER, t.key)
end

local st = State.new(nil) -- nil => the user's real ~/.config/niri (or $XDG_CONFIG_HOME/niri)
local currentSection = TAB_ORDER[1]
local statusMessage = ""
local statusColorRole = "on_surface_variant"
local tabModels = {}
local externalEditor = ""

local render -- forward decl

local function setStatus(msg, level)
	statusMessage = msg
	if level == "ok" then
		statusColorRole = "primary"
	elseif level == "error" then
		statusColorRole = "error"
	else
		statusColorRole = "on_surface_variant"
	end
end

local function recomputeTab(key)
	local mod = Tabs[key]
	if mod and mod.recompute then
		tabModels[key] = mod.recompute(st)
	end
end

local function recomputeAll()
	for _, key in ipairs(TAB_ORDER) do
		recomputeTab(key)
	end
end

local function loadSettings()
	local v = noctalia.getConfig("external_editor")
	externalEditor = (type(v) == "string") and v or ""
end

-- Stage an edit (shown live; written on Apply) and re-render.
local function requestSave(path, text, summary)
	st.stage(path, text)
	recomputeTab(currentSection)
	setStatus((summary or "Change") .. " staged — press Apply to write it.", "info")
	render()
end

local function rerender()
	render()
end

local function buildCtx()
	return {
		st = st,
		model = tabModels[currentSection],
		requestSave = requestSave,
		rerender = rerender,
		recompute = function()
			recomputeTab(currentSection)
		end,
	}
end

-- Open the config for editing: an explicit editor command runs on the file;
-- otherwise reveal the file's folder in the file manager (a bare terminal
-- $EDITOR can't launch without a TTY). Uses the plugin-trusted filesystem
-- path resolution, same as v4's execDetached so it survives panel close.
local function openInEditor(path)
	if externalEditor ~= "" then
		noctalia.runAsync({ "sh", "-c", externalEditor .. ' "$1"', "_", path })
	else
		local p = (path:gsub("/+$", ""))
		local dir = Cfg.dirname(p)
		noctalia.runAsync({ "xdg-open", dir })
	end
end

local function openDoc()
	local url = DOC_URLS[currentSection]
	if url then
		noctalia.runAsync({ "xdg-open", url })
	end
end

local function applyChanges()
	if st.pendingCount == 0 or st.busy then
		return
	end
	setStatus(`Applying {st.pendingCount} change(s)…`, "info")
	render()
	st.applyChanges(function(r)
		if r.ok then
			recomputeAll()
			setStatus("Applied — niri reloaded.", "ok")
		else
			local detail = r.detail or ""
			local msg = "Rejected by niri validate — restored from backup. Fix and re-apply."
			if detail ~= "" then
				msg = msg .. "\n" .. detail
			end
			setStatus(msg, "error")
		end
		render()
	end)
end

local function undoLast()
	if not st.canUndo or st.busy then
		return
	end
	render()
	st.undoLast(function(r)
		if r.ok then
			recomputeAll()
			if r.count and r.count > 0 then
				setStatus("Reverted to the previous config.", "ok")
			else
				setStatus("Nothing to revert — no backup found.", "info")
			end
		else
			setStatus("Undo failed: " .. (r.detail or "no output from the restore script"), "error")
		end
		render()
	end)
end

-- Explicit reload: discard staged edits and re-read from disk. Refuses while
-- edits are staged so it can never silently discard work.
local function reloadConfig()
	if st.pendingCount > 0 then
		setStatus(`Reload skipped — {st.pendingCount} staged change(s) would be lost. Apply them first.`, "error")
		render()
		return
	end
	st.load()
	recomputeAll()
	setStatus("Reloaded from disk.", "info")
	render()
end

local function switchSection(key)
	if key == currentSection then
		return
	end
	currentSection = key
	recomputeTab(key)
	render()
end

render = function()
	local mod = Tabs[currentSection]
	local sectionFile = ""
	if mod.sectionFile then
		sectionFile = mod.sectionFile(st, tabModels[currentSection]) or ""
	end

	local subtitle
	if not st.niriInstalled then
		subtitle = "niri not found on PATH"
	elseif st.pendingCount > 0 then
		subtitle = `{st.pendingCount} unsaved change(s) — press Apply`
	else
		subtitle = "All changes applied · validated & backed up"
	end

	-- nav
	local navItems = {}
	for _, key in ipairs(TAB_ORDER) do
		local t = Tabs[key]
		local selected = key == currentSection
		table.insert(
			navItems,
			ui.row({
				key = "nav-" .. key,
				gap = 8,
				align = "center",
				padding = 8,
				radius = 8,
				-- `or nil` here would OMIT the key from the table (Lua tables
				-- can't hold a nil value), not set fill to nil - the host's
				-- retained-mode reconciler then leaves whatever fill this row
				-- had from a previous render untouched instead of clearing it.
				-- That's why the previously-selected nav row kept showing
				-- highlighted after switching tabs. Always supply an explicit
				-- value so every render clears or sets it.
				fill = selected and "primary" or "on_surface/0",
				onClick = function()
					switchSection(key)
				end,
			}, {
				ui.glyph({ name = t.icon, size = 18, color = selected and "on_primary" or "on_surface" }),
				ui.label({ text = t.label, flexGrow = 1, color = selected and "on_primary" or "on_surface" }),
			})
		)
	end

	-- header buttons
	local headerButtons = {
		ui.label({ text = "Niri Config", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
	}
	table.insert(
		headerButtons,
		ui.button({
			text = st.pendingCount > 0 and `Apply ({st.pendingCount})` or "Apply",
			variant = "primary",
			enabled = st.pendingCount > 0 and st.niriInstalled and not st.busy,
			onClick = applyChanges,
		})
	)
	if st.canUndo and st.pendingCount == 0 then
		table.insert(
			headerButtons,
			ui.button({ text = "Undo", variant = "outline", enabled = not st.busy, onClick = undoLast })
		)
	end
	if DOC_URLS[currentSection] then
		table.insert(
			headerButtons,
			ui.button({
				glyph = "help-circle",
				variant = "ghost",
				tooltip = "Open niri docs for this section",
				onClick = openDoc,
			})
		)
	end
	table.insert(
		headerButtons,
		ui.button({
			glyph = "refresh",
			variant = "ghost",
			tooltip = "Reload / discard staged changes",
			onClick = reloadConfig,
		})
	)

	-- body children (top to bottom)
	local children = {}
	table.insert(children, ui.row({ gap = 12, align = "center" }, headerButtons))
	table.insert(
		children,
		ui.label({
			text = subtitle,
			fontSize = 11,
			color = st.pendingCount > 0 and "primary" or "on_surface_variant",
		})
	)
	if statusMessage ~= "" then
		table.insert(children, ui.label({ text = statusMessage, fontSize = 11, color = statusColorRole, maxLines = 4 }))
	end
	table.insert(children, ui.separator({}))

	if sectionFile ~= "" then
		local shortPath = sectionFile
		if st.home ~= "" and sectionFile:sub(1, #st.home) == st.home then
			shortPath = "~" .. sectionFile:sub(#st.home + 1)
		end
		table.insert(
			children,
			ui.row({ gap = 8, align = "center" }, {
				ui.glyph({ name = "file", size = 14, color = "on_surface_variant" }),
				ui.label({
					text = shortPath,
					fontFamily = "monospace",
					fontSize = 11,
					color = "on_surface_variant",
					flexGrow = 1,
					maxLines = 1,
				}),
				ui.button({
					text = externalEditor ~= "" and "Edit file" or "Open folder",
					glyph = externalEditor ~= "" and "external-link" or "folder",
					variant = "outline",
					controlSize = "sm",
					onClick = function()
						openInEditor(sectionFile)
					end,
				}),
			})
		)
	end

	-- nav rail + section body
	table.insert(
		children,
		ui.row({ flexGrow = 1, gap = 12 }, {
			ui.scroll({ width = 170, gap = 2, align = "stretch" }, navItems),
			ui.separator({ orientation = "vertical" }),
			ui.column({ flexGrow = 1, minWidth = 0 }, { mod.render(buildCtx()) }),
		})
	)

	panel.render(ui.column({ flexGrow = 1, gap = 10 }, children))
end

function onOpen(_context)
	loadSettings()
	if not st.loaded then
		st.load()
	end
	-- Defer the first recompute+render to a fresh callback: st.load() alone
	-- (parsing the whole include graph) plus recomputeAll() plus building the
	-- very first render (which, for a Shortcuts list of ~150 real binds,
	-- means ~150 ui.row/button/label host calls) measured well past a single
	-- callback's CPU budget when chained together. noctalia.runAsync with a
	-- trivial command is a reliable way to get a genuinely fresh callback
	-- invocation (same technique used to pace the save/undo pipeline's own
	-- tests) — the resulting one-tick delay before the panel first paints is
	-- imperceptible.
	noctalia.runAsync({ "true" }, function()
		recomputeAll()
		render()
	end)
end

function onKey(chord, pressed)
	local mod = Tabs[currentSection]
	if mod.onKey then
		mod.onKey(chord, pressed, buildCtx())
	end
end

-- A plugin setting changed (external editor command). Panels are rebuilt by
-- the host on a settings change, but keep the cache consistent regardless.
function onConfigChanged()
	loadSettings()
end
