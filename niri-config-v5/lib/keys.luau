--!nonstrict
-- keys.luau — the special-key vocabulary (media/brightness/system/wheel) niri
-- binds support that no keyboard capture can see, plus translation from a
-- Noctalia panel `onKey` chord string to a niri bind key token.
--
-- Faithful port of lib/keys.js's SPECIAL_KEYS list (same XF86/Wheel tokens).
-- The Qt-keyevent half of keys.js (QT_KEY_NAMES / SHIFT_SYMBOLS / modifier
-- bitmasks / comboFromEvent) has no Luau equivalent to port *from* — Noctalia
-- panels don't get raw Qt key events, they get a `chord` string from
-- `capture_keys`/`onKey` (plugin_api 13; see entries doc: "modifiers in the
-- order Ctrl, Alt, Shift, followed by the XKB key name", e.g. "space",
-- "ctrl+r", "shift+Return"). `chordToCombo` below is the Luau-side
-- equivalent of `comboFromEvent`: it re-derives the niri KEY-NAME SIDE of
-- that mapping (the side keys.js's QT_KEY_NAMES table encoded), translating
-- an XKB-style key name into niri's own bind vocabulary, which for
-- punctuation keys is a distinct PascalCase name (e.g. "Slash", not XKB's
-- "slash" — confirmed against this machine's real cfg/keybinds.kdl, which
-- uses "Mod+Shift+Slash").
--
-- PLATFORM LIMIT (see panel.luau / README): `capture_keys` chords are never
-- delivered for Super ("Mod" in niri terms) — "Super chords are rejected:
-- those belong to the compositor." niri's default mod-key is Super, so the
-- overwhelming majority of real-world binds (every one in this machine's own
-- config) use a combo the live-capture button cannot see. The combo field
-- stays a free-text fallback, exactly as it was in v4 ("the combo field stays
-- editable as a fallback for other layouts").

local M = {}

-- token, group — unchanged from keys.js (verified byte-for-byte against the
-- original file's XF86/Wheel identifiers).
M.SPECIAL_KEYS = {
	{ token = "XF86AudioRaiseVolume", group = "media" },
	{ token = "XF86AudioLowerVolume", group = "media" },
	{ token = "XF86AudioMute", group = "media" },
	{ token = "XF86AudioMicMute", group = "media" },
	{ token = "XF86AudioPlay", group = "media" },
	{ token = "XF86AudioPause", group = "media" },
	{ token = "XF86AudioNext", group = "media" },
	{ token = "XF86AudioPrev", group = "media" },
	{ token = "XF86AudioStop", group = "media" },
	{ token = "XF86MonBrightnessUp", group = "brightness" },
	{ token = "XF86MonBrightnessDown", group = "brightness" },
	{ token = "XF86KbdBrightnessUp", group = "brightness" },
	{ token = "XF86KbdBrightnessDown", group = "brightness" },
	{ token = "XF86Display", group = "system" },
	{ token = "XF86Search", group = "system" },
	{ token = "XF86Mail", group = "system" },
	{ token = "XF86HomePage", group = "system" },
	{ token = "WheelScrollUp", group = "wheel" },
	{ token = "WheelScrollDown", group = "wheel" },
	{ token = "WheelScrollLeft", group = "wheel" },
	{ token = "WheelScrollRight", group = "wheel" },
}

-- Named XKB key → niri bind key-name override, for names that differ from a
-- naive "capitalize the first letter" of the XKB name (ported 1:1 from
-- keys.js's QT_KEY_NAMES table, keyed by the XKB name instead of a Qt code).
local NAMED_KEY_OVERRIDES = {
	backspace = "BackSpace",
	["return"] = "Return",
	escape = "Escape",
	tab = "Tab",
	space = "Space",
	home = "Home",
	["end"] = "End",
	left = "Left",
	right = "Right",
	up = "Up",
	down = "Down",
	prior = "Prior",
	pageup = "Prior",
	next = "Next",
	pagedown = "Next",
	insert = "Insert",
	delete = "Delete",
	print = "Print",
	minus = "Minus",
	equal = "Equal",
	slash = "Slash",
	backslash = "Backslash",
	comma = "Comma",
	period = "Period",
	semicolon = "Semicolon",
	apostrophe = "Apostrophe",
	grave = "Grave",
	bracketleft = "BracketLeft",
	bracketright = "BracketRight",
}

local MOD_MAP = { ctrl = "Ctrl", alt = "Alt", shift = "Shift" }

-- Translate one XKB-style key name (as delivered in an onKey chord) to the
-- niri bind key-name token.
function M.translateKeyName(xkbName)
	if #xkbName == 1 then
		if xkbName:match("%a") then
			return xkbName:upper()
		end
		return xkbName
	end
	local lower = xkbName:lower()
	local override = NAMED_KEY_OVERRIDES[lower]
	if override then
		return override
	end
	if lower:match("^f%d+$") then
		return lower:upper()
	end
	return xkbName:sub(1, 1):upper() .. xkbName:sub(2)
end

-- Compose a niri combo string ("Ctrl+Alt+T") from a captured onKey chord
-- ("ctrl+alt+t"), or nil if the chord is empty/unparseable. Bare modifier
-- presses never reach onKey as a standalone chord (capture_keys only lists
-- full chords), so there is no "is this just a modifier" check to port.
function M.chordToCombo(chord)
	local parts = {}
	for p in tostring(chord):gmatch("[^+]+") do
		table.insert(parts, p)
	end
	if #parts == 0 then
		return nil
	end
	local key = parts[#parts]
	local mods = {}
	for i = 1, #parts - 1 do
		local m = MOD_MAP[parts[i]:lower()]
		if m then
			table.insert(mods, m)
		end
	end
	table.insert(mods, M.translateKeyName(key))
	return table.concat(mods, "+")
end

-- The exact key/modifier-combo vocabulary declared as `capture_keys` in
-- plugin.toml (kept here so the declared list and the runtime parser can
-- never drift silently out of sync — panel.luau asserts against this at
-- load in dev builds via selftest; see scripts note in README). Deliberately
-- excludes any Super/"Mod" combination: the host rejects those outright.
local CAPTURE_BASE_KEYS = {
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
	"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
	"Return", "BackSpace", "Escape", "Tab", "space", "Home", "End",
	"Left", "Right", "Up", "Down", "Prior", "Next", "Insert", "Delete", "Print",
	"minus", "equal", "slash", "backslash", "comma", "period",
	"semicolon", "apostrophe", "grave", "bracketleft", "bracketright",
}

function M.buildCaptureKeys()
	local out = {}
	local prefixes = { "", "ctrl+", "alt+", "shift+" }
	for _, key in ipairs(CAPTURE_BASE_KEYS) do
		for _, prefix in ipairs(prefixes) do
			table.insert(out, prefix .. key)
		end
	end
	return out
end

return M
