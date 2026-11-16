--!nonstrict
-- monique.luau - thin wrapper around the `monique` CLI (monitor profile
-- engine). Pure command builders + parser; the caller runs the processes.
-- Verbatim from niri-config-v5's lib/monique.luau (same tool, same contract).

local M = {}

function M.listProfilesCmd()
	return { "monique", "--list-profiles" }
end

function M.currentProfileCmd()
	return { "monique", "--current-profile" }
end

function M.switchProfileCmd(name)
	return { "monique", "--switch-profile", name }
end

function M.parseProfiles(text)
	local ok, a = pcall(noctalia.json.decode, (text or "[]"):gsub("^%s+", ""):gsub("%s+$", ""))
	if ok and type(a) == "table" then
		return a
	end
	return {}
end

function M.trim(s)
	return (s or ""):match("^%s*(.-)%s*$")
end

return M
