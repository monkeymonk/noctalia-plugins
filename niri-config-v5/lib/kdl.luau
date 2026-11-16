--!nonstrict
-- kdl.luau — tolerant KDL (v2) parser + surgical text-edit primitives.
--
-- Faithful Luau port of the original lib/kdl.js (niri-config v4, QML plugin).
-- The parser records the exact source BYTE range of every node so edits can be
-- applied to the ORIGINAL text without reformatting. Untouched bytes are never
-- rewritten — comments, alignment and section headers are preserved.
--
-- Porting notes (deliberate, documented deviations from kdl.js):
--  * Positions are 0-indexed byte offsets into the Luau string (mirrors the JS
--    `this.i` / range semantics 1:1 so the algorithm transcribes directly).
--  * The scanner reads BYTE CODES (`string.byte`, a number) at each position
--    rather than 1-character substrings (`string.sub`). `string.sub` would
--    allocate a new string object on every single character test; a KDL file
--    of a few hundred binds does that hundreds of thousands of times during
--    one parse, which measured well past the Luau host's per-callback CPU
--    budget (every write recomputes several files, so parsing has to stay
--    cheap). Byte-code comparison is allocation-free. `slice()`/`sub` are
--    still used, but only where a real substring is produced (token text,
--    splice results) — not in the character-by-character scan loops.
--  * Operating at the BYTE level (not the UTF-16-code-unit level JS uses) is
--    safe for UTF-8 content: continuation/lead bytes (0x80-0xFF) never alias
--    the ASCII delimiters this parser tests for, so multi-byte comments/
--    strings pass through untouched even though the scanner never decodes
--    them.
--  * kdl.js's `isWs` additionally tolerated a literal BOM (U+FEFF) and NBSP
--    (U+00A0) as inter-token whitespace. That tolerance is dropped here —
--    real niri/noctalia KDL files never contain either. Space/tab/CR are
--    still treated as whitespace exactly as before.
--  * KDL's `null` / `#null` value decodes to the sentinel table `M.NULL`
--    instead of Luau `nil`, because a table field holding Lua `nil` is
--    indistinguishable from an absent field (which the rest of this module,
--    and callers, use as "a value/line is omitted"). Compare with `== M.NULL`.
--
-- Node shape (identical field names to kdl.js):
--   {
--     name:        string,
--     args:        { {value=.., raw=.., range={s,e}}, ... },
--     props:       { [key] = decoded value, ... },   -- last-wins
--     propsList:   { {key=,value=,raw=,range={s,e},keyRange={s,e}}, ... },
--     children:    { Node, ... },
--     slashdash:   bool,
--     range:       {s, e},          -- whole node incl. children + terminator
--     headerRange: {s, e},          -- name + args + props (before "{" or terminator)
--     nameRange:   {s, e},
--     childrenRange: {s, e} | nil,  -- inside the "{ }" (excludes braces)
--   }

local M = {}

-- Sentinel for a decoded KDL `null` / `#null` value (see note above).
M.NULL = setmetatable({}, { __tostring = function() return "null" end })
local NULL = M.NULL

-- ── byte codes ───────────────────────────────────────────────────────────
local B_SP, B_TAB, B_CR, B_LF = 32, 9, 13, 10
local B_SEMI, B_LBRACE, B_RBRACE = 59, 123, 125
local B_LPAREN, B_RPAREN, B_EQ, B_BACKSLASH = 40, 41, 61, 92
local B_SLASH, B_STAR, B_DASH, B_UNDERSCORE = 47, 42, 45, 95
local B_QUOTE, B_HASH, B_R, B_U = 34, 35, 114, 117
local B_0, B_9, B_a, B_f, B_A, B_F = 48, 57, 97, 102, 65, 70
local B_PLUS = 43
local B_DOT = 46
local B_e, B_E = 101, 69

-- ── byte-string helpers (0-indexed, half-open, mirrors JS string ops) ──────

local sbyte = string.byte
local ssub = string.sub

-- Byte code (number) at 0-indexed position i, or nil past either end.
local function byteAt(t, i)
	if i < 0 or i >= #t then
		return nil
	end
	return sbyte(t, i + 1)
end

local function slice(t, s, e)
	local n = #t
	if e == nil then
		e = n
	end
	if s < 0 then
		s = 0
	end
	if e > n then
		e = n
	end
	if s >= e then
		return ""
	end
	return ssub(t, s + 1, e)
end

local function startsWithAt(t, needle, i)
	return ssub(t, i + 1, i + #needle) == needle
end

local function isWsB(c)
	return c == B_SP or c == B_TAB or c == B_CR
end

local function isDigitB(c)
	return c ~= nil and c >= B_0 and c <= B_9
end

local function isHexDigitB(c)
	if c == nil then
		return false
	end
	return (c >= B_0 and c <= B_9) or (c >= B_a and c <= B_f) or (c >= B_A and c <= B_F)
end

-- Minimal UTF-8 encoder for \u{XXXX} escapes (no external utf8 dependency).
local function utf8Encode(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
	elseif cp < 0x10000 then
		return string.char(
			0xE0 + math.floor(cp / 0x1000),
			0x80 + (math.floor(cp / 0x40) % 0x40),
			0x80 + (cp % 0x40)
		)
	else
		return string.char(
			0xF0 + math.floor(cp / 0x40000),
			0x80 + (math.floor(cp / 0x1000) % 0x40),
			0x80 + (math.floor(cp / 0x40) % 0x40),
			0x80 + (cp % 0x40)
		)
	end
end

-- `/^[+-]?(\d[\d_]*)(\.\d[\d_]*)?([eE][+-]?\d+)?$/` ported as a manual byte
-- scanner (Luau patterns have no alternation/groups suitable for this
-- grammar; this is also run once per bare token, not per character, so it
-- stays on a short local string rather than the full document).
local function matchesNumber(token)
	local n = #token
	local i = 1
	local c = sbyte(token, i)
	if c == B_PLUS or c == B_DASH then
		i = i + 1
	end
	c = sbyte(token, i)
	if i > n or not isDigitB(c) then
		return false
	end
	while i <= n do
		c = sbyte(token, i)
		if isDigitB(c) or c == B_UNDERSCORE then
			i = i + 1
		else
			break
		end
	end
	if i <= n and sbyte(token, i) == B_DOT then
		i = i + 1
		if i > n or not isDigitB(sbyte(token, i)) then
			return false
		end
		while i <= n do
			c = sbyte(token, i)
			if isDigitB(c) or c == B_UNDERSCORE then
				i = i + 1
			else
				break
			end
		end
	end
	if i <= n and (sbyte(token, i) == B_e or sbyte(token, i) == B_E) then
		i = i + 1
		c = sbyte(token, i)
		if c == B_PLUS or c == B_DASH then
			i = i + 1
		end
		if i > n or not isDigitB(sbyte(token, i)) then
			return false
		end
		while i <= n and isDigitB(sbyte(token, i)) do
			i = i + 1
		end
	end
	return i == n + 1
end

-- `/^0x[0-9a-fA-F_]+$/`
local function matchesHex(token)
	if ssub(token, 1, 2) ~= "0x" then
		return false
	end
	if #token <= 2 then
		return false
	end
	for i = 3, #token do
		local c = sbyte(token, i)
		if not (isHexDigitB(c) or c == B_UNDERSCORE) then
			return false
		end
	end
	return true
end

local ESCAPE_MAP = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", b = "\b", f = "\f", s = " " }

-- ── Parser (table {t=text, i=0-indexed pos, n=length}, free functions) ─────

local parseNode -- forward decl (recursive)

local function skipLineComment(p)
	local t, n = p.t, p.n
	while p.i < n and byteAt(t, p.i) ~= B_LF do
		p.i = p.i + 1
	end
end

local function skipBlockComment(p)
	local t = p.t
	p.i = p.i + 2
	local depth = 1
	while p.i < p.n and depth > 0 do
		local c = byteAt(t, p.i)
		if c == B_SLASH and byteAt(t, p.i + 1) == B_STAR then
			depth = depth + 1
			p.i = p.i + 2
		elseif c == B_STAR and byteAt(t, p.i + 1) == B_SLASH then
			depth = depth - 1
			p.i = p.i + 2
		else
			p.i = p.i + 1
		end
	end
end

-- Skip inline whitespace, line continuations (\ + newline) and comments, but
-- NOT bare newlines (those terminate a node).
local function skipInline(p)
	local t = p.t
	while p.i < p.n do
		local c = byteAt(t, p.i)
		if c == B_SP or c == B_TAB or c == B_CR then
			p.i = p.i + 1
		elseif c == B_BACKSLASH then
			local j = p.i + 1
			while j < p.n do
				local cj = byteAt(t, j)
				if cj == B_SP or cj == B_TAB or cj == B_CR then
					j = j + 1
				else
					break
				end
			end
			if byteAt(t, j) == B_LF then
				p.i = j + 1
			else
				return
			end
		elseif c == B_SLASH and byteAt(t, p.i + 1) == B_SLASH then
			skipLineComment(p)
			return
		elseif c == B_SLASH and byteAt(t, p.i + 1) == B_STAR then
			skipBlockComment(p)
		else
			return
		end
	end
end

-- Skip whitespace/newlines/comments freely (between nodes).
local function skipWsAndNewlines(p)
	local t = p.t
	while p.i < p.n do
		local c = byteAt(t, p.i)
		if isWsB(c) or c == B_LF then
			p.i = p.i + 1
		elseif c == B_BACKSLASH then
			p.i = p.i + 1
		elseif c == B_SLASH and byteAt(t, p.i + 1) == B_SLASH then
			skipLineComment(p)
		elseif c == B_SLASH and byteAt(t, p.i + 1) == B_STAR then
			skipBlockComment(p)
		else
			return
		end
	end
end

-- Read a string value: "..", #".."#, r".." or r#"..."# (niri uses r#"..."#).
-- Scans in CHUNKS (find the next backslash or closer, bulk-slice up to it)
-- rather than copying one byte at a time: a per-character table.insert loop
-- here was the dominant cost of a full-document parse (most of a bind line's
-- bytes live inside its quoted args/props) and was slow enough to exceed the
-- host's per-callback CPU budget on a real ~10KB keybinds.kdl.
local function readString(p)
	local t = p.t
	local start = p.i
	if byteAt(t, p.i) == B_R then
		p.i = p.i + 1
	end
	local hashes = 0
	while byteAt(t, p.i) == B_HASH do
		hashes = hashes + 1
		p.i = p.i + 1
	end
	if byteAt(t, p.i) ~= B_QUOTE then
		p.i = start
		return nil
	end
	local triple = byteAt(t, p.i + 1) == B_QUOTE and byteAt(t, p.i + 2) == B_QUOTE
	local closer = (triple and '"""' or '"') .. string.rep("#", hashes)
	p.i = p.i + (triple and 3 or 1)
	local raw = (byteAt(t, start) == B_R) or hashes > 0
	local out = {}

	if raw then
		-- No escapes possible: the whole body is one slice up to the closer.
		local closeAt = t:find(closer, p.i + 1, true)
		if closeAt then
			table.insert(out, ssub(t, p.i + 1, closeAt - 1))
			p.i = closeAt - 1 + #closer
		else
			table.insert(out, ssub(t, p.i + 1))
			p.i = p.n
		end
	else
		while p.i < p.n do
			local bsAt = t:find("\\", p.i + 1, true)
			local clAt = t:find(closer, p.i + 1, true)
			if clAt ~= nil and (bsAt == nil or clAt <= bsAt) then
				if clAt > p.i + 1 then
					table.insert(out, ssub(t, p.i + 1, clAt - 1))
				end
				p.i = clAt - 1 + #closer
				break
			elseif bsAt ~= nil then
				if bsAt > p.i + 1 then
					table.insert(out, ssub(t, p.i + 1, bsAt - 1))
				end
				p.i = bsAt - 1 -- 0-indexed position of the backslash itself
				local eb = byteAt(t, p.i + 1)
				local e = eb and string.char(eb) or nil
				local mapped = e ~= nil and ESCAPE_MAP[e] or nil
				if mapped ~= nil then
					table.insert(out, mapped)
					p.i = p.i + 2
				elseif eb == B_U and byteAt(t, p.i + 2) == B_LBRACE then
					local k = p.i + 3
					local hexStart = k
					while isHexDigitB(byteAt(t, k)) do
						k = k + 1
					end
					if byteAt(t, k) == B_RBRACE and k > hexStart then
						local hex = slice(t, hexStart, k)
						table.insert(out, utf8Encode(tonumber(hex, 16)))
						p.i = k + 1
					else
						table.insert(out, "u")
						p.i = p.i + 2
					end
				else
					table.insert(out, e or "")
					p.i = p.i + 2
				end
			else
				-- neither closer nor backslash found: unterminated to EOF
				table.insert(out, ssub(t, p.i + 1))
				p.i = p.n
				break
			end
		end
	end

	return { value = table.concat(out), raw = slice(t, start, p.i), range = { start, p.i } }
end

-- Read a bare / number / keyword value.
local function readBare(p)
	local t = p.t
	local start = p.i
	if byteAt(t, p.i) == B_LPAREN then
		local d = 1
		p.i = p.i + 1
		while p.i < p.n and d > 0 do
			local c = byteAt(t, p.i)
			if c == B_LPAREN then
				d = d + 1
			elseif c == B_RPAREN then
				d = d - 1
			end
			p.i = p.i + 1
		end
	end
	while p.i < p.n do
		local c = byteAt(t, p.i)
		if c == B_SLASH and (byteAt(t, p.i + 1) == B_SLASH or byteAt(t, p.i + 1) == B_STAR) then
			break
		end
		if
			isWsB(c)
			or c == B_LF
			or c == B_SEMI
			or c == B_LBRACE
			or c == B_RBRACE
			or c == B_EQ
			or c == B_BACKSLASH
		then
			break
		end
		p.i = p.i + 1
	end
	local raw = slice(t, start, p.i)
	local token = raw
	if ssub(token, 1, 1) == "(" then
		local tp = token:find(")", 1, true)
		if tp then
			token = token:sub(tp + 1)
		end
	end
	local value
	if token == "true" or token == "#true" then
		value = true
	elseif token == "false" or token == "#false" then
		value = false
	elseif token == "null" or token == "#null" then
		value = NULL
	elseif token == "#inf" or token == "#-inf" or token == "#nan" then
		value = token
	elseif matchesNumber(token) then
		value = tonumber((token:gsub("_", "")))
	elseif matchesHex(token) then
		value = tonumber((token:gsub("_", "")):sub(3), 16)
	else
		value = token
	end
	return { value = value, raw = raw, range = { start, p.i } }
end

-- Read one value (string or bare) at the cursor, or nil if none.
local function readValue(p)
	local t = p.t
	local c = byteAt(t, p.i)
	local c1 = byteAt(t, p.i + 1)
	if c == B_QUOTE or c == B_HASH or (c == B_R and (c1 == B_QUOTE or c1 == B_HASH)) then
		local s = readString(p)
		if s then
			return s
		end
	end
	if c == nil or isWsB(c) or c == B_LF or c == B_SEMI or c == B_LBRACE or c == B_RBRACE then
		return nil
	end
	return readBare(p)
end

-- Parse a single node at the cursor. Returns Node or nil (e.g. at "}" / EOF).
parseNode = function(p)
	local t = p.t
	skipWsAndNewlines(p)
	if p.i >= p.n or byteAt(t, p.i) == B_RBRACE then
		return nil
	end

	local nodeStart = p.i
	local slashdash = false
	if byteAt(t, p.i) == B_SLASH and byteAt(t, p.i + 1) == B_DASH then
		slashdash = true
		p.i = p.i + 2
		skipInline(p)
	end

	local nameVal = readValue(p)
	if not nameVal then
		if p.i < p.n then
			p.i = p.i + 1
		end
		return nil
	end

	local node = {
		name = tostring(nameVal.value),
		nameRange = { nameVal.range[1], nameVal.range[2] },
		args = {},
		props = {},
		propsList = {},
		children = {},
		slashdash = slashdash,
		range = { nodeStart, p.i },
		headerRange = { nameVal.range[1], p.i },
		childrenRange = nil,
	}

	while p.i < p.n do
		local iterStart = p.i
		skipInline(p)
		local c = byteAt(t, p.i)
		if c == nil or c == B_LF or c == B_SEMI then
			break
		end
		if c == B_RBRACE then
			break
		end
		if c == B_EQ or c == B_BACKSLASH then
			p.i = p.i + 1
			continue
		end
		if c == B_LBRACE then
			local braceOpen = p.i
			p.i = p.i + 1
			local childrenInnerStart = p.i
			local kids = {}
			while true do
				skipWsAndNewlines(p)
				if p.i >= p.n or byteAt(t, p.i) == B_RBRACE then
					break
				end
				local kid = parseNode(p)
				if kid then
					table.insert(kids, kid)
				else
					break
				end
			end
			local childrenInnerEnd = p.i
			if byteAt(t, p.i) == B_RBRACE then
				p.i = p.i + 1
			end
			node.children = kids
			node.childrenRange = { childrenInnerStart, childrenInnerEnd }
			node.headerRange[2] = braceOpen
			break
		end
		if c == B_SLASH and byteAt(t, p.i + 1) == B_DASH then
			p.i = p.i + 2
			skipInline(p)
			if byteAt(t, p.i) == B_LBRACE then
				p.i = p.i + 1
				local dd = 1
				while p.i < p.n and dd > 0 do
					local cc = byteAt(t, p.i)
					if cc == B_LBRACE then
						dd = dd + 1
					elseif cc == B_RBRACE then
						dd = dd - 1
					end
					p.i = p.i + 1
				end
			else
				readValue(p)
				if byteAt(t, p.i) == B_EQ then
					p.i = p.i + 1
					readValue(p)
				end
			end
			continue
		end
		local v = readValue(p)
		if not v then
			if p.i < p.n then
				p.i = p.i + 1
			end
			continue
		end
		if byteAt(t, p.i) == B_EQ then
			local keyEnd = p.i
			p.i = p.i + 1
			local pv = readValue(p)
			local key = tostring(v.value)
			local propValue, propRaw, propEnd
			if pv ~= nil then
				propValue, propRaw, propEnd = pv.value, pv.raw, pv.range[2]
			else
				propValue, propRaw, propEnd = NULL, "", p.i
			end
			node.props[key] = propValue
			table.insert(node.propsList, {
				key = key,
				value = propValue,
				raw = propRaw,
				range = { v.range[1], propEnd },
				keyRange = { v.range[1], keyEnd },
			})
		else
			table.insert(node.args, v)
		end
		if p.i == iterStart then
			p.i = p.i + 1
		end
	end

	if byteAt(t, p.i) == B_SEMI then
		p.i = p.i + 1
	end
	node.range[2] = p.i
	if node.headerRange[2] < node.nameRange[2] then
		node.headerRange[2] = node.nameRange[2]
	end
	return node
end

-- Parse a whole document → { text, nodes }
function M.parse(text)
	local p = { t = text, i = 0, n = #text }
	local nodes = {}
	local guard = 0
	while p.i < p.n do
		skipWsAndNewlines(p)
		if p.i >= p.n then
			break
		end
		local before = p.i
		local node = parseNode(p)
		if node then
			table.insert(nodes, node)
		end
		if p.i <= before then
			p.i = before + 1
		end
		guard = guard + 1
		if guard > 1000000 then
			break
		end
	end
	return { text = text, nodes = nodes }
end

-- ── tree helpers ─────────────────────────────────────────────────────────

-- Depth-first walk in document order. cb(node, parent) for every node.
function M.walk(nodes, cb, parent)
	for i = 1, #nodes do
		local n = nodes[i]
		cb(n, parent)
		if n.children and #n.children > 0 then
			M.walk(n.children, cb, n)
		end
	end
end

-- Find the first node matching name (case-insensitive), depth-first.
function M.findNode(doc, name, nodes)
	local target = name:lower()
	local roots = nodes or doc.nodes
	local stack = {}
	for i = #roots, 1, -1 do
		table.insert(stack, roots[i])
	end
	while #stack > 0 do
		local n = table.remove(stack)
		if n.name:lower() == target then
			return n
		end
		local kids = n.children
		if kids then
			for j = #kids, 1, -1 do
				table.insert(stack, kids[j])
			end
		end
	end
	return nil
end

-- ── surgical text edits (operate on raw text + ranges) ──────────────────

-- True when only whitespace separates pos from the start of its physical line.
local function startsLine(text, pos)
	while pos > 0 and byteAt(text, pos - 1) ~= B_LF do
		if not isWsB(byteAt(text, pos - 1)) then
			return false
		end
		pos = pos - 1
	end
	return true
end
M._startsLine = startsLine

-- Expand [start,end] to cover full physical lines (incl. leading indent and
-- the trailing newline) — but ONLY when those lines hold nothing but the node
-- itself. A node sharing its line with anything else keeps its own range
-- (minus trailing inter-token whitespace), so a line-oriented edit never
-- swallows a neighbour or the space before a brace.
function M.lineSpan(text, range)
	local s, e = range[1], range[2]
	while s > 0 and byteAt(text, s - 1) ~= B_LF do
		s = s - 1
	end
	while e < #text and byteAt(text, e) ~= B_LF do
		e = e + 1
	end
	local shared = not startsLine(text, range[1])
	if not shared then
		local i = range[2]
		while i < e do
			if not isWsB(byteAt(text, i)) then
				shared = true
				break
			end
			i = i + 1
		end
	end
	if shared then
		local ne = range[2]
		while ne > range[1] and isWsB(byteAt(text, ne - 1)) do
			ne = ne - 1
		end
		return { range[1], ne }
	end
	if e < #text then
		e = e + 1
	end
	return { s, e }
end

-- Indentation of the node's own line — "" when the node does not start the line.
function M.leadingIndent(text, range)
	if not startsLine(text, range[1]) then
		return ""
	end
	local s = range[1]
	while s > 0 and byteAt(text, s - 1) ~= B_LF do
		s = s - 1
	end
	return slice(text, s, range[1])
end

-- Replace the text covered by [start,end] with replacement.
function M.spliceText(text, range, replacement)
	return slice(text, 0, range[1]) .. replacement .. slice(text, range[2], #text)
end

-- Replace a node's whole line(s) with newLine (no trailing newline expected).
function M.replaceNodeLine(text, node, newLine)
	local span = M.lineSpan(text, node.range)
	local last = byteAt(text, span[2] - 1)
	local trailing = ""
	if last == B_LF then
		trailing = "\n"
	elseif last == B_SEMI and ssub(newLine, -1) ~= ";" then
		trailing = ";"
	end
	return M.spliceText(text, span, newLine .. trailing)
end

-- Remove a node entirely (full line span, or just itself when it shares a line).
function M.removeNodeLine(text, node)
	local span = M.lineSpan(text, node.range)
	local e = span[2]
	if byteAt(text, e - 1) ~= B_LF then
		while byteAt(text, e) == B_SP or byteAt(text, e) == B_TAB do
			e = e + 1
		end
	end
	return M.spliceText(text, { span[1], e }, "")
end

-- Insert newLine as a child of parent, just before its closing "}".
function M.insertChildLine(text, parent, newLine)
	if not parent.childrenRange then
		return text
	end
	local innerStart, innerEnd = parent.childrenRange[1], parent.childrenRange[2]
	local at = innerEnd
	while at > innerStart and (byteAt(text, at - 1) == B_SP or byteAt(text, at - 1) == B_TAB) do
		at = at - 1
	end

	if not slice(text, innerStart, innerEnd):find("\n", 1, true) then
		local sep
		if at == innerStart then
			sep = " "
		elseif byteAt(text, at - 1) == B_SEMI then
			sep = " "
		else
			sep = "; "
		end
		local collapsed = (newLine:gsub("%s*\n%s*", " "))
		return M.spliceText(text, { at, innerEnd }, sep .. collapsed .. " ")
	end

	local kids = parent.children or {}
	local last = (#kids > 0) and kids[#kids] or nil
	local indent
	if last and startsLine(text, last.range[1]) then
		indent = M.leadingIndent(text, last.range)
	else
		indent = M.leadingIndent(text, parent.range) .. "    "
	end
	if at > 0 and byteAt(text, at - 1) ~= B_LF then
		at = innerEnd
	end
	local prefix = ""
	if at > 0 and byteAt(text, at - 1) ~= B_LF then
		prefix = "\n"
	end
	local indented = (newLine:gsub("\n", "\n" .. indent))
	return M.spliceText(text, { at, at }, prefix .. indent .. indented .. "\n")
end

-- Enable/disable a node in place by adding/removing a leading "/-" slashdash.
function M.setDisabled(text, node, disabled)
	local start = node.range[1]
	local hasSlash = slice(text, start, start + 2) == "/-"
	if disabled and not hasSlash then
		return slice(text, 0, start) .. "/-" .. slice(text, start, #text)
	end
	if not disabled and hasSlash then
		return slice(text, 0, start) .. slice(text, start + 2, #text)
	end
	return text
end

-- Append a brand-new top-level node to the document text.
function M.appendNode(text, newText)
	local sep = (#text == 0 or ssub(text, -1) == "\n") and "" or "\n"
	local trail = (ssub(newText, -1) == "\n") and "" or "\n"
	return text .. sep .. newText .. trail
end

-- ── block editing (path-addressed children of a named root block) ───────

-- First child named exactly `name`, or nil.
function M.childNamed(node, name)
	local kids = node and node.children or nil
	if not kids then
		return nil
	end
	for i = 1, #kids do
		if kids[i].name == name then
			return kids[i]
		end
	end
	return nil
end

-- Parse text, find the `rootName` node, then descend pathArr by child name.
function M.blockPath(text, rootName, pathArr)
	local cur = M.findNode(M.parse(text), rootName)
	local path = pathArr or {}
	local i = 1
	while cur and i <= #path do
		cur = M.childNamed(cur, path[i])
		i = i + 1
	end
	return cur
end

-- Create every missing block along rootName + pathArr.
function M.ensurePath(text, rootName, pathArr)
	local path = pathArr or {}
	local root = M.findNode(M.parse(text), rootName)
	if not root then
		text = M.appendNode(text, rootName .. " {\n}")
		root = M.findNode(M.parse(text), rootName)
	end
	for i = 1, #path do
		local cur = root
		local j = 1
		while cur and j < i do
			cur = M.childNamed(cur, path[j])
			j = j + 1
		end
		if cur and not M.childNamed(cur, path[i]) then
			text = M.insertChildLine(text, cur, path[i] .. " {\n}")
			root = M.findNode(M.parse(text), rootName)
		end
	end
	return text
end

-- Set the child `name` of the block at rootName + pathArr to the finished
-- source line `line`. line == nil removes the child.
function M.setChildLine(text, rootName, pathArr, name, line)
	local block = M.blockPath(text, rootName, pathArr)
	local existing
	if block then
		existing = M.childNamed(block, name)
	end
	if line == nil then
		if existing then
			return M.removeNodeLine(text, existing)
		end
		return text
	end
	if existing then
		return M.replaceNodeLine(text, existing, M.leadingIndent(text, existing.range) .. line)
	end
	text = M.ensurePath(text, rootName, pathArr)
	block = M.blockPath(text, rootName, pathArr)
	if block then
		return M.insertChildLine(text, block, line)
	end
	return text
end

-- Add/remove a bare flag node (e.g. `numlock`) in the block at rootName + pathArr.
function M.setChildFlag(text, rootName, pathArr, name, on)
	local block = M.blockPath(text, rootName, pathArr)
	local existing
	if block then
		existing = M.childNamed(block, name)
	end
	if not on then
		if existing then
			return M.removeNodeLine(text, existing)
		end
		return text
	end
	if existing then
		return text
	end
	text = M.ensurePath(text, rootName, pathArr)
	block = M.blockPath(text, rootName, pathArr)
	if block then
		return M.insertChildLine(text, block, name)
	end
	return text
end

-- Apply many child edits to the same root block in one pass. `edits` is
--   { { path = {"keyboard","xkb"}, name = "layout", line = 'layout "us"' | nil }, ... }
-- Identical result to folding setChildLine over `edits`, but the document is
-- parsed once for every edit whose target node already exists — only a
-- first-time insert falls back to the sequential primitive. The caller must
-- not pass two edits with the same (path, name).
function M.applyChildEdits(text, rootName, edits)
	local list = edits or {}
	if #list == 0 then
		return text
	end

	local root = M.findNode(M.parse(text), rootName)
	if not root then
		for i = 1, #list do
			text = M.setChildLine(text, rootName, list[i].path, list[i].name, list[i].line)
		end
		return text
	end

	local splices = {}
	local deferred = {}
	for k = 1, #list do
		local e = list[k]
		local cur = root
		local path = e.path or {}
		local j = 1
		while cur and j <= #path do
			cur = M.childNamed(cur, path[j])
			j = j + 1
		end
		local existing
		if cur then
			existing = M.childNamed(cur, e.name)
		end
		if not existing then
			if e.line ~= nil then
				table.insert(deferred, e)
			end
		else
			table.insert(splices, { node = existing, line = e.line })
		end
	end

	-- Descending by range start: every splice leaves earlier ranges intact.
	table.sort(splices, function(a, b)
		return a.node.range[1] > b.node.range[1]
	end)
	for s = 1, #splices do
		local sp = splices[s]
		if sp.line == nil then
			text = M.removeNodeLine(text, sp.node)
		else
			text = M.replaceNodeLine(text, sp.node, M.leadingIndent(text, sp.node.range) .. sp.line)
		end
	end

	for d = 1, #deferred do
		local de = deferred[d]
		text = M.setChildLine(text, rootName, de.path, de.name, de.line)
	end
	return text
end

return M
