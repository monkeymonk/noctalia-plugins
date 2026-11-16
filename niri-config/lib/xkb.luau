--!nonstrict
-- xkb.luau — parse /usr/share/X11/xkb/rules/evdev.lst into layouts/variants/
-- options/models for the keyboard editor. Faithful port of lib/xkb.js. The
-- caller reads the file (noctalia.readFile); this only parses the text.
-- Falls back to a curated subset when the file is absent/unreadable, exactly
-- like the original.

local M = {}

M.FALLBACK_LAYOUTS = {
	{ code = "us", desc = "English (US)" },
	{ code = "gb", desc = "English (UK)" },
	{ code = "fr", desc = "French" },
	{ code = "de", desc = "German" },
	{ code = "es", desc = "Spanish" },
	{ code = "it", desc = "Italian" },
	{ code = "ca", desc = "French (Canada)" },
	{ code = "ch", desc = "Swiss" },
	{ code = "ru", desc = "Russian" },
	{ code = "jp", desc = "Japanese" },
}

local function trim(s)
	return (s:match("^%s*(.-)%s*$"))
end

local function withFallback(res)
	if #res.layouts == 0 then
		local copy = {}
		for i, v in ipairs(M.FALLBACK_LAYOUTS) do
			copy[i] = v
		end
		res.layouts = copy
	end
	return res
end

-- evdev.lst is sectioned: "! layout", "! variant", "! option", "! model".
-- Lines: "<code><whitespace><description>"; variant lines have a 3rd column
-- (the layout they belong to).
--
-- Split into an incremental newParser/feedLine/finish trio so a caller can
-- drive it across several callbacks (evdev.lst is ~45KB / ~1000 lines; even
-- the single-pass optimized version measurably exceeded one callback's CPU
-- budget on this host). parseEvdevList below is a non-chunked convenience
-- wrapper for callers (tests, small inputs) that don't need to spread the
-- work out.
function M.newParser()
	return { models = {}, layouts = {}, variants = {}, options = {}, section = nil }
end

function M.feedLine(state, line)
	local t = trim(line)
	if t == "" then
		return
	end
	if t:sub(1, 1) == "!" then
		local s = trim(t:sub(2)):lower()
		if s == "layout" or s == "variant" or s == "option" or s == "model" then
			state.section = s
		else
			state.section = nil
		end
		return
	end
	if not state.section then
		return
	end
	local code, rest = t:match("^(%S+)%s+(.*)$")
	if not code then
		return
	end
	rest = trim(rest)
	if state.section == "variant" then
		-- "<variant> <layout>: <description>" OR "<variant>  <description>"
		local layout, desc = rest:match("^(%S+):%s*(.*)$")
		if layout then
			table.insert(state.variants, { code = code, layout = layout, desc = desc })
		else
			table.insert(state.variants, { code = code, layout = nil, desc = rest })
		end
	elseif state.section == "layout" then
		table.insert(state.layouts, { code = code, desc = rest })
	elseif state.section == "option" then
		table.insert(state.options, { code = code, desc = rest })
	elseif state.section == "model" then
		table.insert(state.models, { code = code, desc = rest })
	end
end

function M.finish(state)
	return withFallback({
		models = state.models,
		layouts = state.layouts,
		variants = state.variants,
		options = state.options,
	})
end

function M.parseEvdevList(text)
	local state = M.newParser()
	if text and text ~= "" then
		for line in (text .. "\n"):gmatch("([^\n]*)\n") do
			M.feedLine(state, line)
		end
	end
	return M.finish(state)
end

function M.variantsForLayout(parsed, layoutCode)
	local out = {}
	for _, v in ipairs(parsed.variants or {}) do
		if v.layout == layoutCode then
			table.insert(out, v)
		end
	end
	return out
end

return M
