--!strict
-- Pure finger-list logic, ported from the v4 plugin's fprintUtils.js.
-- No noctalia.* / ui.* calls here - required from panel.luau.

local M = {}

M.ALL_FINGERS = {
  "left-thumb",
  "left-index-finger",
  "left-middle-finger",
  "left-ring-finger",
  "left-little-finger",
  "right-thumb",
  "right-index-finger",
  "right-middle-finger",
  "right-ring-finger",
  "right-little-finger",
}

local FINGER_ICONS = {
  ["left-thumb"] = "hand-three-fingers",
  ["left-index-finger"] = "hand-finger",
  ["left-middle-finger"] = "hand-middle-finger",
  ["left-ring-finger"] = "hand-ring-finger",
  ["left-little-finger"] = "hand-little-finger",
  ["right-thumb"] = "hand-three-fingers",
  ["right-index-finger"] = "hand-finger",
  ["right-middle-finger"] = "hand-middle-finger",
  ["right-ring-finger"] = "hand-ring-finger",
  ["right-little-finger"] = "hand-little-finger",
}

function M.iconOf(name: string): string
  return FINGER_ICONS[name] or "fingerprint"
end

-- Parses `fprintd-list "$USER"` output. Lines of interest look like
-- "  - #0: right-index-finger". Returns an array of finger-name strings.
function M.parseList(text: string?): { string }
  local out = {}
  if text == nil or text == "" then
    return out
  end
  for line in text:gmatch("[^\n]+") do
    local finger = line:match("#%d+:%s*([%a%-]+)")
    if finger ~= nil then
      table.insert(out, finger)
    end
  end
  return out
end

-- Fingers from ALL_FINGERS that are not present in `enrolled`.
function M.availableForEnroll(enrolled: { string }): { string }
  local set = {}
  for _, name in ipairs(enrolled) do
    set[name] = true
  end
  local out = {}
  for _, name in ipairs(M.ALL_FINGERS) do
    if not set[name] then
      table.insert(out, name)
    end
  end
  return out
end

local function containsAny(haystack: string, needles: { string }): boolean
  for _, needle in ipairs(needles) do
    if haystack:find(needle, 1, true) then
      return true
    end
  end
  return false
end

-- Classifies one stdout line from `fprintd-enroll`.
-- Returns "stage-pass" | "retry" | "completed" | "failed" | nil.
function M.classifyEnrollLine(line: string?): string?
  if line == nil then
    return nil
  end
  local l = line:lower()
  if l:find("enroll-completed", 1, true) then
    return "completed"
  elseif l:find("enroll-failed", 1, true) then
    return "failed"
  elseif l:find("enroll-stage-passed", 1, true) then
    return "stage-pass"
  elseif containsAny(l, {
    "enroll-retry",
    "enroll-finger-not-centered",
    "enroll-remove-and-retry",
    "enroll-swipe-too-short",
    "enroll-finger-not-removed",
  }) then
    return "retry"
  end
  return nil
end

-- Classifies one stdout line from `fprintd-verify`.
-- Returns "match" | "no-match" | "retry" | nil.
function M.classifyVerifyLine(line: string?): string?
  if line == nil then
    return nil
  end
  local l = line:lower()
  if l:find("verify-match", 1, true) then
    return "match"
  elseif l:find("verify-no-match", 1, true) then
    return "no-match"
  elseif containsAny(l, {
    "verify-retry-scan",
    "verify-swipe-too-short",
    "verify-finger-not-centered",
    "verify-remove-and-retry",
  }) then
    return "retry"
  end
  return nil
end

return M
