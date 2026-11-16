--!nonstrict
-- shortcuts.luau — the Shortcuts tab: list/filter/enable/disable/delete every
-- bind in the `binds {}` block, plus an in-tab add/edit form with live combo
-- capture, a special-key picker, an action picker and an app/script picker.
-- Faithful port of ShortcutsSection.qml + BindEditor.qml + ActionPicker.qml +
-- AppPicker.qml + ConfirmPopup.qml (niri-config v4) onto the declarative UI /
-- tab module contract. There is no modal/Popup primitive in this toolkit, so
-- every v4 popup becomes an in-tab screen swap driven by the module-level
-- `view` local (see panel.luau's header comment for the pattern).
local Kdl = require("../kdl.luau")
local B = require("../binds.luau")
local Keys = require("../keys.luau")
local Desktop = require("../desktop.luau")
local Scripts = require("../scripts.luau")

local M = { icon = "keyboard", label = "Shortcuts" }

-- ── view state ───────────────────────────────────────────────────────────
-- "list" | "edit" | "confirm-delete" | "pick-special" | "pick-action" | "pick-app"
local view = "list"
local filterText = ""

-- ── add/edit form state ─────────────────────────────────────────────────
local editTarget = nil -- { path, node } of the edited bind, or nil for create
local formAllBinds = {} -- snapshot of every bind, for conflict checks + column alignment
local formCombo = ""
local formActionName = ""
local formActionArgType = "none"
local formActionArg = ""
local formCommand = ""
local formTitleAttr = ""
local formRepeatOff = false
local formAllowWhenLocked = false
local formRecording = false
local formTailActions = {} -- 2nd+ actions of a multi-action bind, preserved verbatim

-- Generations bump whenever a `ui.input` value changes from OUTSIDE typing
-- (reset, capture, picker pick) so the (uncontrolled) control is recreated
-- and actually picks up the new seed value instead of keeping stale text.
local comboGen = 0
local commandGen = 0
local argGen = 0
local titleGen = 0

-- ── delete confirmation ─────────────────────────────────────────────────
local deleteTarget = nil -- bind model pending delete
local deleteMessage = ""

-- ── action picker ────────────────────────────────────────────────────────
local actionFilterText = ""
local actionFilterGen = 0

-- ── app/script picker ────────────────────────────────────────────────────
local appFilterText = ""
local appFilterGen = 0
local appRawText = ""
local scriptsList = {}
local appsList = {}
local appsLoaded = false
local appsLoading = false

-- ── form helpers ─────────────────────────────────────────────────────────

local function resetForm()
	formCombo = ""
	formActionName = ""
	formActionArgType = "none"
	formActionArg = ""
	formCommand = ""
	formTitleAttr = ""
	formRepeatOff = false
	formAllowWhenLocked = false
	formRecording = false
	formTailActions = {}
	comboGen += 1
	commandGen += 1
	argGen += 1
	titleGen += 1
end

local function openCreate(allBinds)
	resetForm()
	editTarget = nil
	formAllBinds = allBinds or {}
	view = "edit"
end

local function openEdit(b, allBinds)
	resetForm()
	editTarget = { path = b.path, node = b.node }
	formAllBinds = allBinds or {}
	formCombo = b.combo
	local a = (b.actions and b.actions[1]) or { name = "", args = {} }
	if b.actions and #b.actions > 1 then
		for i = 2, #b.actions do
			table.insert(formTailActions, b.actions[i])
		end
	end
	formActionName = a.name
	local spec = B.actionSpec(a.name)
	if spec then
		formActionArgType = spec.arg
	elseif a.args and #a.args > 0 then
		formActionArgType = "string"
	else
		formActionArgType = "none"
	end
	if a.name == "spawn" or a.name == "spawn-sh" then
		local parts = {}
		for i, v in ipairs(a.args or {}) do
			parts[i] = tostring(v)
		end
		formCommand = table.concat(parts, " ")
	else
		formActionArg = (a.args and #a.args > 0) and tostring(a.args[1]) or ""
	end
	formTitleAttr = b.attrs["hotkey-overlay-title"] or ""
	formRepeatOff = b.attrs["repeat"] == false
	formAllowWhenLocked = b.attrs["allow-when-locked"] == true
	view = "edit"
end

local function isSpawn()
	return formActionName == "spawn" or formActionName == "spawn-sh"
end

local function canSave()
	if formCombo == "" or formActionName == "" then
		return false
	end
	if isSpawn() and formCommand == "" then
		return false
	end
	return true
end

local function buildBind()
	local attrs = {}
	if formTitleAttr ~= "" then
		attrs["hotkey-overlay-title"] = formTitleAttr
	end
	if formRepeatOff then
		attrs["repeat"] = false
	end
	if formAllowWhenLocked then
		attrs["allow-when-locked"] = true
	end
	local action
	if isSpawn() then
		action = Desktop.commandToAction(formCommand) or { name = "spawn", args = {} }
	elseif formActionArgType ~= "none" and formActionArg ~= "" then
		local v = formActionArg
		if v:match("^%-?%d+$") then
			v = tonumber(v)
		end
		action = { name = formActionName, args = { v } }
	else
		action = { name = formActionName, args = {} }
	end
	local actions = { action }
	for _, a in ipairs(formTailActions) do
		table.insert(actions, a)
	end
	return { combo = formCombo, attrs = attrs, actions = actions, disabled = false }
end

local function saveForm(ctx)
	if not canSave() then
		return
	end
	local bind = buildBind()
	local line = B.serializeBind(bind, { padTo = B.alignColumnFor(formAllBinds) })
	if editTarget then
		local src = ctx.st.textOf(editTarget.path)
		local indent = Kdl.leadingIndent(src, editTarget.node.range)
		local text = Kdl.replaceNodeLine(src, editTarget.node, indent .. line)
		view = "list"
		ctx.requestSave(editTarget.path, text, "shortcut " .. bind.combo)
	else
		local owner = ctx.model.owner
		local text = Kdl.insertChildLine(ctx.st.textOf(owner.path), owner.nodes[1], line)
		view = "list"
		ctx.requestSave(owner.path, text, "new shortcut " .. bind.combo)
	end
end

local function filterBinds(binds, filter)
	if filter == "" then
		return binds
	end
	local needle = filter:lower()
	local out = {}
	for _, b in ipairs(binds) do
		if b.combo:lower():find(needle, 1, true) ~= nil or b.desc:lower():find(needle, 1, true) ~= nil then
			table.insert(out, b)
		end
	end
	return out
end

-- ── app/script picker data ──────────────────────────────────────────────

local function loadScripts(ctx)
	local dir = Scripts.scriptsDir(ctx.st.configDir)
	noctalia.runAsync(Scripts.listCmd(dir), function(result)
		scriptsList = Scripts.parseList(result.stdout or "", dir)
		ctx.rerender()
	end)
end

local function loadApps(ctx)
	appsLoading = true
	local seen = {}
	local list = {}
	for _, d in ipairs(Desktop.APP_DIRS) do
		local dir = d
		if dir:sub(1, 1) == "~" then
			dir = ctx.st.home .. dir:sub(2)
		end
		local entries = noctalia.listDir(dir)
		if entries then
			for _, fname in ipairs(entries) do
				if fname:sub(-8) == ".desktop" then
					local text = noctalia.readFile(dir .. "/" .. fname)
					if text then
						local e = Desktop.parseDesktopEntry(text)
						if e then
							local key = e.name .. "|" .. e.exec
							if not seen[key] then
								seen[key] = true
								table.insert(list, e)
							end
						end
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	appsList = list
	appsLoaded = true
	appsLoading = false
end

local function openAppPicker(ctx)
	appFilterText = ""
	appRawText = ""
	appFilterGen += 1
	view = "pick-app"
	loadScripts(ctx)
	if not appsLoaded and not appsLoading then
		loadApps(ctx)
	end
end

-- ── screens ──────────────────────────────────────────────────────────────

local function renderConfirmDelete(ctx)
	return ui.column({ gap = 16, flexGrow = 1 }, {
		ui.label({ text = deleteMessage, fontWeight = "bold", color = "error", maxLines = 4 }),
		ui.row({ gap = 8, justify = "end" }, {
			ui.button({
				text = "Cancel",
				onClick = function()
					deleteTarget = nil
					view = "list"
					ctx.rerender()
				end,
			}),
			ui.button({
				text = "Delete",
				variant = "destructive",
				onClick = function()
					local target = deleteTarget
					deleteTarget = nil
					view = "list"
					local text = Kdl.removeNodeLine(ctx.st.textOf(target.path), target.node)
					ctx.requestSave(target.path, text, "delete " .. target.combo)
				end,
			}),
		}),
	})
end

local function renderSpecialPicker(ctx)
	local rows = {}
	local lastGroup = nil
	for i, item in ipairs(Keys.SPECIAL_KEYS) do
		if item.group ~= lastGroup then
			table.insert(rows, ui.label({
				text = (item.group:gsub("^%l", string.upper)),
				fontWeight = "bold",
				color = "primary",
				fontSize = 11,
			}))
			lastGroup = item.group
		end
		table.insert(
			rows,
			ui.row({
				key = "special-" .. i,
				gap = 8,
				align = "center",
				padding = 8,
				radius = 6,
				fill = "surface_variant",
				onClick = function()
					formCombo = item.token
					comboGen += 1
					view = "edit"
					ctx.rerender()
				end,
			}, {
				ui.label({ text = item.token, fontFamily = "monospace", flexGrow = 1 }),
			})
		)
	end
	return ui.column({ gap = 10, flexGrow = 1 }, {
		ui.label({ text = "Pick a special key", fontSize = 16, fontWeight = "bold" }),
		ui.scroll({ flexGrow = 1, gap = 4 }, rows),
		ui.row({ justify = "end" }, {
			ui.button({
				text = "Back",
				onClick = function()
					view = "edit"
					ctx.rerender()
				end,
			}),
		}),
	})
end

local function renderActionPicker(ctx)
	local filter = actionFilterText:lower()
	local rows = {}
	for _, a in ipairs(B.ACTIONS) do
		local show = filter == "" or a.name:lower():find(filter, 1, true) ~= nil or a.cat:lower():find(filter, 1, true) ~= nil
		if show then
			table.insert(
				rows,
				ui.row({
					key = "action-" .. a.name,
					gap = 10,
					align = "center",
					padding = 8,
					radius = 6,
					fill = "surface_variant",
					onClick = function()
						formActionName = a.name
						formActionArgType = a.arg
						formActionArg = ""
						argGen += 1
						if a.name ~= "spawn" and a.name ~= "spawn-sh" then
							formCommand = ""
							commandGen += 1
						end
						view = "edit"
						ctx.rerender()
					end,
				}, {
					ui.label({ text = (a.name:gsub("%-", " ")), flexGrow = 1, maxLines = 1 }),
					ui.label({ text = a.cat, color = "on_surface_variant", fontSize = 10 }),
					a.arg ~= "none" and ui.label({ text = "+arg", color = "primary", fontSize = 10 }) or ui.spacer({}),
				})
			)
		end
	end
	return ui.column({ gap = 10, flexGrow = 1 }, {
		ui.label({ text = "Pick an action", fontSize = 16, fontWeight = "bold" }),
		ui.input({
			key = "action-filter-" .. actionFilterGen,
			value = actionFilterText,
			placeholder = "Search actions…",
			onChange = function(v)
				actionFilterText = v
				ctx.rerender()
			end,
		}),
		ui.scroll({ flexGrow = 1, gap = 4 }, rows),
		ui.row({ justify = "end" }, {
			ui.button({
				text = "Back",
				onClick = function()
					view = "edit"
					ctx.rerender()
				end,
			}),
		}),
	})
end

local function renderAppPicker(ctx)
	local filter = appFilterText:lower()
	local listChildren = {}

	local scriptRows = {}
	for i, s in ipairs(scriptsList) do
		if filter == "" or s.name:lower():find(filter, 1, true) ~= nil then
			table.insert(
				scriptRows,
				ui.row({
					key = "script-" .. i,
					gap = 10,
					align = "center",
					padding = 8,
					radius = 6,
					fill = "surface_variant",
					onClick = function()
						formCommand = s.path
						commandGen += 1
						view = "edit"
						ctx.rerender()
					end,
				}, {
					ui.glyph({ name = "file-code", size = 16, color = "primary" }),
					ui.label({ text = s.name, fontFamily = "monospace", fontSize = 12, flexGrow = 1, maxLines = 1 }),
				})
			)
		end
	end
	if #scriptRows > 0 then
		table.insert(listChildren, ui.label({ text = "Your scripts", fontSize = 10, fontWeight = "bold", color = "primary" }))
		for _, r in ipairs(scriptRows) do
			table.insert(listChildren, r)
		end
		table.insert(listChildren, ui.separator({}))
	end

	if not appsLoaded then
		table.insert(listChildren, ui.label({ text = "Loading apps…", color = "on_surface_variant" }))
	end
	for i, a in ipairs(appsList) do
		if filter == "" or a.name:lower():find(filter, 1, true) ~= nil then
			table.insert(
				listChildren,
				ui.row({
					key = "app-" .. i,
					gap = 10,
					align = "center",
					padding = 8,
					radius = 6,
					fill = "surface_variant",
					onClick = function()
						formCommand = a.exec
						commandGen += 1
						view = "edit"
						ctx.rerender()
					end,
				}, {
					ui.glyph({ name = "app-window", size = 16, color = "primary" }),
					ui.column({ gap = 0, flexGrow = 1 }, {
						ui.label({ text = a.name, fontWeight = "medium", maxLines = 1 }),
						ui.label({ text = a.exec, color = "on_surface_variant", fontFamily = "monospace", fontSize = 10, maxLines = 1 }),
					}),
				})
			)
		end
	end

	return ui.column({ gap = 10, flexGrow = 1 }, {
		ui.label({ text = "Pick an application", fontSize = 16, fontWeight = "bold" }),
		ui.input({
			key = "app-filter-" .. appFilterGen,
			value = appFilterText,
			placeholder = "Search apps…",
			onChange = function(v)
				appFilterText = v
				ctx.rerender()
			end,
		}),
		ui.scroll({ flexGrow = 1, gap = 4 }, listChildren),
		ui.row({ gap = 8 }, {
			ui.input({
				key = "app-raw-" .. appFilterGen,
				value = appRawText,
				placeholder = "…or type a command",
				flexGrow = 1,
				onChange = function(v)
					appRawText = v
				end,
				onSubmit = function()
					if appRawText ~= "" then
						formCommand = appRawText
						commandGen += 1
						view = "edit"
						ctx.rerender()
					end
				end,
			}),
			ui.button({
				text = "Use",
				enabled = appRawText ~= "",
				onClick = function()
					formCommand = appRawText
					commandGen += 1
					view = "edit"
					ctx.rerender()
				end,
			}),
		}),
		ui.row({ justify = "end" }, {
			ui.button({
				text = "Back",
				onClick = function()
					view = "edit"
					ctx.rerender()
				end,
			}),
		}),
	})
end

local function renderEditScreen(ctx)
	local conflict = nil
	if formCombo ~= "" then
		conflict = B.findConflict(formAllBinds, formCombo, editTarget and editTarget.node or nil)
	end

	local children = {
		ui.label({ text = editTarget and "Edit shortcut" or "Add shortcut", fontSize = 16, fontWeight = "bold" }),
		ui.label({ text = "Key combination", fontWeight = "medium" }),
		ui.row({ gap = 8, align = "center" }, {
			ui.input({
				key = "shortcuts-combo-" .. comboGen,
				value = formCombo,
				placeholder = "e.g. Mod+Shift+T",
				flexGrow = 1,
				onChange = function(v)
					if not formRecording then
						formCombo = v
					end
				end,
			}),
			ui.button({
				text = formRecording and "Press keys…" or "Capture",
				variant = formRecording and "destructive" or "primary",
				onClick = function()
					formRecording = not formRecording
					ctx.rerender()
				end,
			}),
			ui.button({
				glyph = "keyboard",
				variant = "outline",
				tooltip = "Special key",
				onClick = function()
					view = "pick-special"
					ctx.rerender()
				end,
			}),
		}),
	}

	if conflict ~= nil then
		table.insert(children, ui.label({
			text = "⚠ Already bound: " .. B.describeBind(conflict),
			color = "error",
			fontSize = 11,
			maxLines = 2,
		}))
	end

	table.insert(children, ui.separator({}))
	table.insert(children, ui.label({ text = "Action", fontWeight = "medium" }))
	table.insert(
		children,
		ui.row({ gap = 8, align = "center" }, {
			ui.row({ fill = "surface_variant", radius = 6, padding = 8, flexGrow = 1 }, {
				ui.label({
					text = formActionName ~= "" and (formActionName:gsub("%-", " ")) or "(choose an action)",
					color = formActionName ~= "" and "on_surface" or "on_surface_variant",
					maxLines = 1,
				}),
			}),
			ui.button({
				text = "Choose",
				onClick = function()
					actionFilterText = ""
					actionFilterGen += 1
					view = "pick-action"
					ctx.rerender()
				end,
			}),
		})
	)

	if isSpawn() then
		table.insert(
			children,
			ui.row({ gap = 8 }, {
				ui.input({
					key = "shortcuts-command-" .. commandGen,
					value = formCommand,
					placeholder = "command to run",
					flexGrow = 1,
					onChange = function(v)
						formCommand = v
					end,
				}),
				ui.button({
					text = "Pick app/script",
					onClick = function()
						openAppPicker(ctx)
						ctx.rerender()
					end,
				}),
			})
		)
	elseif formActionArgType ~= "none" then
		local placeholder = "argument"
		if formActionArgType == "amount" then
			placeholder = "e.g. -10% or +10%"
		elseif formActionArgType == "workspaceRef" then
			placeholder = "workspace number or name"
		end
		table.insert(
			children,
			ui.input({
				key = "shortcuts-arg-" .. argGen,
				value = formActionArg,
				placeholder = placeholder,
				onChange = function(v)
					formActionArg = v
				end,
			})
		)
	end

	if #formTailActions > 0 then
		table.insert(children, ui.label({
			text = "+ " .. #formTailActions .. " more action(s) in this bind are preserved.",
			color = "on_surface_variant",
			fontSize = 11,
			maxLines = 3,
		}))
	end

	table.insert(children, ui.separator({}))
	table.insert(children, ui.label({ text = "Overlay title (optional)", fontWeight = "medium" }))
	table.insert(
		children,
		ui.input({
			key = "shortcuts-title-" .. titleGen,
			value = formTitleAttr,
			placeholder = "shown in the hotkey overlay",
			onChange = function(v)
				formTitleAttr = v
			end,
		})
	)
	table.insert(
		children,
		ui.row({ gap = 8, align = "center" }, {
			ui.toggle({
				checked = formRepeatOff,
				onChange = function(v)
					formRepeatOff = v == "true"
				end,
			}),
			ui.label({ text = "Disable key repeat" }),
		})
	)
	table.insert(
		children,
		ui.row({ gap = 8, align = "center" }, {
			ui.toggle({
				checked = formAllowWhenLocked,
				onChange = function(v)
					formAllowWhenLocked = v == "true"
				end,
			}),
			ui.label({ text = "Allow when screen locked" }),
		})
	)

	table.insert(
		children,
		ui.row({ gap = 8, justify = "end" }, {
			ui.button({
				text = "Cancel",
				onClick = function()
					formRecording = false
					view = "list"
					ctx.rerender()
				end,
			}),
			ui.button({
				text = "Save",
				variant = "primary",
				enabled = canSave(),
				onClick = function()
					saveForm(ctx)
				end,
			}),
		})
	)

	return ui.scroll({ flexGrow = 1, gap = 10 }, children)
end

local function renderList(ctx)
	local model = ctx.model
	local owner = model.owner
	local binds = model.binds

	local children = {
		ui.row({ gap = 8, align = "center" }, {
			ui.label({ text = #binds .. " shortcut" .. (#binds == 1 and "" or "s"), fontWeight = "bold" }),
			ui.spacer({ flexGrow = 1 }),
			ui.button({
				glyph = "plus",
				text = "Add",
				enabled = owner ~= nil,
				onClick = function()
					openCreate(binds)
					ctx.rerender()
				end,
			}),
		}),
	}

	if owner == nil then
		table.insert(children, ui.label({
			text = "No binds {} block found in your config.",
			color = "error",
			maxLines = 4,
		}))
		return ui.column({ gap = 10, flexGrow = 1 }, children)
	end

	table.insert(
		children,
		ui.input({
			key = "shortcuts-filter",
			value = filterText,
			placeholder = "Filter shortcuts…",
			onChange = function(v)
				filterText = v
				ctx.rerender()
			end,
		})
	)

	local visible = filterBinds(binds, filterText)
	local rows = {}
	for i, b in ipairs(visible) do
		local title = b.attrs["hotkey-overlay-title"]
		local label = (title ~= nil and title ~= "") and title or b.desc
		table.insert(
			rows,
			ui.row({
				key = "bind-" .. i,
				gap = 12,
				align = "center",
				padding = 8,
				radius = 8,
				fill = "surface_variant",
				opacity = b.disabled and 0.55 or 1.0,
			}, {
				ui.row({ fill = "surface", radius = 6, padding = 6, width = 150, justify = "center", border = "outline", borderWidth = 1 }, {
					ui.label({ text = b.combo, fontFamily = "monospace", fontSize = 11, maxLines = 1, textAlign = "center" }),
				}),
				ui.label({
					text = label,
					flexGrow = 1,
					maxLines = 1,
					color = b.disabled and "on_surface_variant" or "on_surface",
				}),
				ui.button({
					glyph = b.disabled and "eye-off" or "eye",
					variant = "ghost",
					tooltip = b.disabled and "Enable" or "Disable",
					onClick = function()
						local text = Kdl.setDisabled(ctx.st.textOf(b.path), b.node, not b.disabled)
						ctx.requestSave(b.path, text, (b.disabled and "enable " or "disable ") .. b.combo)
					end,
				}),
				ui.button({
					glyph = "edit",
					variant = "ghost",
					tooltip = "Edit",
					onClick = function()
						openEdit(b, binds)
						ctx.rerender()
					end,
				}),
				ui.button({
					glyph = "trash",
					variant = "ghost",
					tooltip = "Delete",
					onClick = function()
						deleteTarget = b
						deleteMessage = "Delete shortcut " .. b.combo .. "?"
						view = "confirm-delete"
						ctx.rerender()
					end,
				}),
			})
		)
	end

	table.insert(children, ui.scroll({ flexGrow = 1, gap = 6 }, rows))
	return ui.column({ gap = 10, flexGrow = 1 }, children)
end

-- ── tab module contract ─────────────────────────────────────────────────

function M.recompute(st)
	local owner = st.ownerOf("binds")
	local binds = {}
	if owner and owner.nodes[1] then
		binds = B.parseBinds(owner.nodes[1])
		for _, b in ipairs(binds) do
			b.desc = B.describeBind(b)
			b.path = owner.path
		end
	end
	return { owner = owner, binds = binds }
end

function M.sectionFile(st, model)
	local owner = st.ownerOf("binds")
	return owner and owner.path or ""
end

function M.render(ctx)
	if view == "edit" then
		return renderEditScreen(ctx)
	elseif view == "pick-action" then
		return renderActionPicker(ctx)
	elseif view == "pick-app" then
		return renderAppPicker(ctx)
	elseif view == "pick-special" then
		return renderSpecialPicker(ctx)
	elseif view == "confirm-delete" then
		return renderConfirmDelete(ctx)
	end
	return renderList(ctx)
end

function M.onKey(chord, pressed, ctx)
	if view ~= "edit" or not formRecording or not pressed then
		return
	end
	if chord == "Escape" then
		return
	end
	local combo = Keys.chordToCombo(chord)
	if combo then
		formCombo = combo
		comboGen += 1
		formRecording = false
		ctx.rerender()
	end
end

return M
