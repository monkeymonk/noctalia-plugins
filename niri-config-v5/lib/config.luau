--!nonstrict
-- config.luau — resolve niri's `include` graph and map config sections to the
-- file that owns them. Faithful port of lib/config.js (niri-config v4).
-- Pure: callers do the file IO (noctalia.readFile) and pass docs/text in.

local M = {}

function M.dirname(p)
	local i = nil
	for idx = #p, 1, -1 do
		if p:sub(idx, idx) == "/" then
			i = idx
			break
		end
	end
	if i == nil or i <= 1 then
		return "/"
	end
	return p:sub(1, i - 1)
end

-- Resolve an include spec (relative/./~/absolute) against baseDir + home.
function M.resolveInclude(spec, baseDir, home)
	local s = (spec:gsub("^%s+", ""):gsub("%s+$", ""))
	if s:sub(1, 1) == "~" then
		return home .. s:sub(2)
	end
	if s:sub(1, 1) == "/" then
		return s
	end
	if s:sub(1, 2) == "./" then
		s = s:sub(3)
	end
	return baseDir .. "/" .. s
end

-- Given a parsed main config (kdl doc) → list of resolved include paths.
function M.includePaths(doc, baseDir, home)
	local out = {}
	for _, n in ipairs(doc.nodes or {}) do
		if n.name == "include" and n.args[1] then
			table.insert(out, M.resolveInclude(tostring(n.args[1].value), baseDir, home))
		end
	end
	return out
end

-- Across loaded files ({path, doc}), find the first file owning a top-level
-- node of `nodeName`. Returns {path, doc, nodes} (every top-level match in
-- that file) or nil.
function M.ownerOf(files, nodeName)
	for i = 1, #files do
		local matches = {}
		for _, n in ipairs(files[i].doc.nodes) do
			if n.name == nodeName then
				table.insert(matches, n)
			end
		end
		if #matches > 0 then
			return { path = files[i].path, doc = files[i].doc, nodes = matches }
		end
	end
	return nil
end

-- All files containing ANY node whose name is in `nodeNames`.
function M.allOwners(files, nodeNames)
	local set = {}
	for _, n in ipairs(nodeNames) do
		set[n] = true
	end
	local out = {}
	for _, f in ipairs(files) do
		local matches = {}
		for _, n in ipairs(f.doc.nodes) do
			if set[n.name] then
				table.insert(matches, n)
			end
		end
		if #matches > 0 then
			table.insert(out, { path = f.path, doc = f.doc, nodes = matches })
		end
	end
	return out
end

return M
