--!nonstrict
-- state.luau — the read+write config pipeline: load (main + include graph),
-- stage in-memory edits, and the validated apply/undo sequence. Faithful
-- port of ConfigModel.qml + SaveController.qml (niri-config v4) combined,
-- adapted to Luau's synchronous filesystem API:
--   * v4's ConfigModel read every file through a QML Process (`cat`, piped
--     through lib/fileblob.js's marker-delimited batching to avoid spawning
--     one process per file). `noctalia.readFile(path)` is a synchronous
--     in-process call, so that whole batching trick is unnecessary here —
--     `load()` below reads the main file + every include directly, no
--     subprocess at all. lib/fileblob.js has no Luau port for this reason.
--   * v4 checked `command -v niri` via a Process; `noctalia.commandExists`
--     replaces that synchronously too.
--   * Apply/Undo/raw-file-write still shell out (niri validate + the backup/
--     restore script), via `noctalia.runAsync` with lib/niri.luau's argv
--     builders.
--
-- `M.new(configRoot)` takes an explicit config-directory override so a test
-- harness can point an entire State instance at a /tmp sandbox copy instead
-- of ~/.config/niri — this is NOT exposed as a user-facing plugin setting
-- (the real plugin always edits the user's actual config); it exists solely
-- so the save/validate/rollback pipeline can be proven safe without ever
-- touching the user's real files (see test/save.sandbox.test.js in v4, and
-- this plugin's own sandbox_test.luau harness).

local Kdl = require("./kdl.luau")
local Cfg = require("./config.luau")
local Niri = require("./niri.luau")

local M = {}

function M.new(configRoot)
	local home = noctalia.getenv("HOME") or ""
	local xdgConfigHome = noctalia.getenv("XDG_CONFIG_HOME")
	local configBase = (xdgConfigHome ~= nil and xdgConfigHome ~= "") and xdgConfigHome or (home .. "/.config")
	local configDir = configRoot or (configBase .. "/niri")

	local self = {
		home = home,
		configDir = configDir,
		mainPath = configDir .. "/config.kdl",
		niriInstalled = noctalia.commandExists("niri"),
		loaded = false,
		error = "",
		files = {}, -- { {path=, text=, doc=}, ... }
		pendingCount = 0,
		appliedPaths = {},
		canUndo = false,
		busy = false,
	}
	local staged = {} -- path -> text (private; use stagedList()/pendingCount)

	-- Read the main config + its resolved include graph straight from disk.
	-- Synchronous: no subprocess, no async callback.
	function self.load()
		self.error = ""
		local mainText = noctalia.readFile(self.mainPath)
		if mainText == nil then
			self.error = "Cannot read " .. self.mainPath
			self.files = {}
			staged = {}
			self.pendingCount = 0
			self.loaded = true
			return
		end
		local mainDoc = Kdl.parse(mainText)
		local includes = Cfg.includePaths(mainDoc, self.configDir, self.home)
		local files = { { path = self.mainPath, text = mainText, doc = mainDoc } }
		for _, p in ipairs(includes) do
			local text = noctalia.readFile(p) or ""
			table.insert(files, { path = p, text = text, doc = Kdl.parse(text) })
		end
		self.files = files
		staged = {}
		self.pendingCount = 0
		self.loaded = true
	end

	-- Stage an edit (no disk write). Updates the in-memory file immediately so
	-- the UI reflects pending changes; disk write happens on applyChanges().
	function self.stage(path, newText)
		local found = false
		for _, f in ipairs(self.files) do
			if f.path == path then
				f.text = newText
				f.doc = Kdl.parse(newText)
				found = true
				break
			end
		end
		if not found then
			table.insert(self.files, { path = path, text = newText, doc = Kdl.parse(newText) })
		end
		staged[path] = newText
		local n = 0
		for _ in pairs(staged) do
			n += 1
		end
		self.pendingCount = n
	end

	function self.stagedList()
		local out = {}
		for p, t in pairs(staged) do
			table.insert(out, { path = p, text = t })
		end
		return out
	end

	-- Explicit discard: drop staged edits and re-read from disk.
	function self.discardStaged()
		self.load()
	end

	-- The file + every top-level node owning a section (e.g. "binds", "input").
	function self.ownerOf(nodeName)
		return Cfg.ownerOf(self.files, nodeName)
	end

	-- All files that contain any of nodeNames (e.g. {"output"}).
	function self.allOwners(nodeNames)
		return Cfg.allOwners(self.files, nodeNames)
	end

	function self.textOf(path)
		for _, f in ipairs(self.files) do
			if f.path == path then
				return f.text
			end
		end
		return ""
	end

	function self.fileEntry(path)
		for _, f in ipairs(self.files) do
			if f.path == path then
				return f
			end
		end
		return nil
	end

	-- ── write pipeline ───────────────────────────────────────────────────

	-- Write ALL staged files atomically: .bak + write + `niri validate` +
	-- reload; restores every .bak if validation fails. `onDone({ok, detail?})`.
	function self.applyChanges(onDone)
		local list = self.stagedList()
		if #list == 0 then
			if onDone then
				onDone({ ok = false, reason = "nothing-staged" })
			end
			return
		end
		self.busy = true
		local paths = {}
		for _, x in ipairs(list) do
			table.insert(paths, x.path)
		end
		noctalia.runAsync(Niri.applyCmd(self.mainPath, list), function(result)
			self.busy = false
			local out = result.stdout or ""
			if out:find("OK", 1, true) ~= nil then
				self.appliedPaths = paths
				self.canUndo = true
				self.load() -- re-read from disk, clears staged
				if onDone then
					onDone({ ok = true })
				end
			else
				local detail = (result.stderr or ""):gsub("^%s+", ""):gsub("%s+$", "")
				-- staged edits are left untouched so the caller can fix and re-apply
				if onDone then
					onDone({ ok = false, reason = "rejected", detail = detail })
				end
			end
		end)
	end

	-- Restore the .bak of every applied file (undo the last successful
	-- apply), then reload. `onDone({ok, count?, detail?})`.
	function self.undoLast(onDone)
		if #self.appliedPaths == 0 then
			if onDone then
				onDone({ ok = false, reason = "nothing-to-undo" })
			end
			return
		end
		self.busy = true
		noctalia.runAsync(Niri.undoCmd(self.appliedPaths), function(result)
			self.busy = false
			local out = (result.stdout or ""):gsub("^%s+", ""):gsub("%s+$", "")
			local n = out:match("RESTORED%s+(%d+)")
			if not n then
				local detail = (out:gsub("^ERR%s*", ""))
				self.load() -- a partial restore may have hit disk
				if onDone then
					onDone({ ok = false, reason = "undo-failed", detail = detail })
				end
				return
			end
			self.canUndo = false
			local count = tonumber(n)
			if count > 0 then
				self.load()
			end
			if onDone then
				onDone({ ok = true, count = count })
			end
		end)
	end

	-- Write a non-config file straight to disk: immediate, unvalidated, not
	-- undoable (e.g. a managed script). `onDone({ok})`.
	function self.writeFileNow(path, newText, executable, onDone)
		self.busy = true
		noctalia.runAsync(Niri.writeFileCmd(path, newText, executable), function(result)
			self.busy = false
			local ok = (result.stdout or ""):find("OK", 1, true) ~= nil
			if onDone then
				onDone({ ok = ok })
			end
		end)
	end

	-- Delete a plugin-managed file. Bypasses the validate gate. `onDone({ok})`.
	function self.deleteFile(path, onDone)
		self.busy = true
		noctalia.runAsync(Niri.deleteFileCmd(path), function(result)
			self.busy = false
			local ok = (result.stdout or ""):find("OK", 1, true) ~= nil
			if onDone then
				onDone({ ok = ok })
			end
		end)
	end

	return self
end

return M
