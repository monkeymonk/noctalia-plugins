--!nonstrict
-- monique.luau — optional integration with the `monique` CLI (monitor profile
-- engine). If present, the Monitors tab surfaces its profiles; otherwise the
-- plugin manages monitor config directly. Faithful port of lib/monique.js.
-- Pure command builders + parser; the caller runs the processes.

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

return M
