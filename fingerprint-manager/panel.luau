--!nonstrict
-- Fingerprint Manager panel - lists enrolled fingers, enrolls, deletes
-- (one or all, with an inline confirm row), and test-matches via fprintd.
-- Ported from v4's Panel.qml + Components/{EnrollDialog,FingerPicker,
-- ConfirmPopup,FingerCard}.qml.
--
-- noctalia.runStream() only accepts a shell-command string (no argv-array
-- form), so fprintd-enroll/-verify go through runStream with a shell-quoted
-- command; fprintd-list/-delete and the busctl stage-count lookup use the
-- argv-array form of runAsync (plugin_api 24) since they take dynamic
-- finger-name/username arguments. runStream exposes no handle to stop the
-- child, so cancelling an enroll kills it by command-line pattern with
-- pkill -f, the same technique the official screen_recorder/mpvpaper
-- plugins use for subprocesses they do not own a PID for.

local F = require("./fingers.luau")

local view = "list" -- "list" | "picker" | "enrolling"
local checkedInstalled = false
local fprintdInstalled = false
local fprintdAvailable = true
local enrolledFingers = {}
local busyMessage = ""
local statusMessage = ""
local statusColor = "on_surface_variant"

local pendingDeleteFinger = nil :: string?
local pendingDeleteAll = false

local enrollFinger = nil :: string?
local enrollStagesPassed = 0
local enrollTotalStages = 10
local enrollStagesResolved = false
local enrollHint = ""

local render -- forward declaration; assigned below, called from handlers above it

-- ---------- helpers ----------

local function shellQuote(s: string): string
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function currentUser(): string
  return noctalia.getenv("USER") or ""
end

local function fingerLabel(name: string): string
  return noctalia.tr("finger." .. name)
end

-- ---------- list / availability ----------

local function refreshList()
  if not fprintdInstalled then
    return
  end
  noctalia.runAsync({ "fprintd-list", currentUser() }, function(result)
    local err = (result.stderr or ""):lower()
    if err:find("no devices", 1, true) or err:find("no such device", 1, true) then
      fprintdAvailable = false
      enrolledFingers = {}
    elseif result.exitCode == 0 then
      fprintdAvailable = true
      enrolledFingers = F.parseList(result.stdout)
    end
    render()
  end, 10000)
end

local function checkInstalled()
  fprintdInstalled = noctalia.commandExists("fprintd-list")
  checkedInstalled = true
  if fprintdInstalled then
    refreshList()
  else
    render()
  end
end

-- ---------- delete ----------

local function deleteFinger(name: string)
  statusMessage = ""
  pendingDeleteFinger = nil
  busyMessage = noctalia.tr("status.deleting", { finger = fingerLabel(name) })
  render()
  noctalia.runAsync({ "fprintd-delete", currentUser(), "-f", name }, function(result)
    busyMessage = ""
    if result.exitCode == 0 then
      statusMessage = noctalia.tr("status.deleted")
      statusColor = "primary"
    else
      statusMessage = noctalia.tr("status.delete-failed")
      statusColor = "error"
    end
    refreshList()
  end, 15000)
end

local function deleteAll()
  statusMessage = ""
  pendingDeleteAll = false
  busyMessage = noctalia.tr("status.deleting-all")
  render()
  noctalia.runAsync({ "fprintd-delete", currentUser() }, function(result)
    busyMessage = ""
    if result.exitCode == 0 then
      statusMessage = noctalia.tr("status.deleted-all")
      statusColor = "primary"
    else
      statusMessage = noctalia.tr("status.delete-failed")
      statusColor = "error"
    end
    refreshList()
  end, 15000)
end

-- ---------- enroll ----------

-- fprintd exposes the device's stage count on D-Bus; the object path is
-- dynamic, so ask the manager for the default device first. Resolved once
-- and cached for the life of this panel runtime (10 is the fallback).
local function queryStageCount()
  if enrollStagesResolved then
    return
  end
  noctalia.runAsync({
    "busctl", "--system", "call", "net.reactivated.Fprint",
    "/net/reactivated/Fprint/Manager", "net.reactivated.Fprint.Manager", "GetDefaultDevice",
  }, function(result)
    if result.exitCode ~= 0 then
      return
    end
    local path = result.stdout:match('"([^"]+)"')
    if path == nil then
      return
    end
    noctalia.runAsync({
      "busctl", "--system", "get-property", "net.reactivated.Fprint", path,
      "net.reactivated.Fprint.Device", "num-enroll-stages",
    }, function(result2)
      if result2.exitCode ~= 0 then
        return
      end
      local n = tonumber(result2.stdout:match("(%-?%d+)"))
      if n ~= nil and n > 0 then
        enrollTotalStages = n
        enrollStagesResolved = true
      end
    end, 5000)
  end, 5000)
end

local function cancelEnroll()
  if enrollFinger ~= nil then
    noctalia.runAsync(`pkill -f -- {shellQuote("fprintd-enroll -f " .. enrollFinger)}`)
  end
  enrollFinger = nil
  view = "list"
  render()
end

local function startEnroll(name: string)
  enrollFinger = name
  enrollStagesPassed = 0
  enrollHint = noctalia.tr("enroll.hint.touch")
  view = "enrolling"
  queryStageCount()
  render()

  local started = noctalia.runStream(`fprintd-enroll -f {shellQuote(name)}`, function(line)
    local kind = F.classifyEnrollLine(line)
    if kind == "stage-pass" then
      enrollStagesPassed += 1
      enrollHint = noctalia.tr("enroll.hint.again")
      render()
    elseif kind == "retry" then
      enrollHint = noctalia.tr("enroll.hint.retry")
      render()
    elseif kind == "completed" then
      enrollFinger = nil
      view = "list"
      statusMessage = noctalia.tr("status.enrolled")
      statusColor = "primary"
      render()
      refreshList()
    elseif kind == "failed" then
      enrollFinger = nil
      view = "list"
      statusMessage = noctalia.tr("status.enroll-failed")
      statusColor = "error"
      render()
      refreshList()
    end
  end)

  if not started then
    enrollFinger = nil
    view = "list"
    statusMessage = noctalia.tr("status.enroll-failed")
    statusColor = "error"
    render()
  end
end

-- ---------- verify ----------

local function testMatch()
  statusMessage = ""
  busyMessage = noctalia.tr("status.verify-start")
  render()
  local started = noctalia.runStream("fprintd-verify", function(line)
    local kind = F.classifyVerifyLine(line)
    if kind == "match" then
      busyMessage = ""
      statusMessage = noctalia.tr("status.match")
      statusColor = "primary"
      render()
    elseif kind == "no-match" then
      busyMessage = ""
      statusMessage = noctalia.tr("status.no-match")
      statusColor = "error"
      render()
    elseif kind == "retry" then
      busyMessage = noctalia.tr("status.verify-retry")
      render()
    end
  end)
  if not started then
    busyMessage = ""
    statusMessage = noctalia.tr("status.verify-failed")
    statusColor = "error"
    render()
  end
end

-- ---------- render helpers ----------

local function statusLine()
  local text = busyMessage ~= "" and busyMessage or statusMessage
  if text == "" then
    return nil
  end
  return ui.label({
    text = text,
    color = busyMessage ~= "" and "on_surface_variant" or statusColor,
    textAlign = "center",
  })
end

local function fingerRow(name: string)
  local confirming = pendingDeleteFinger == name
  local children = {
    ui.glyph({ name = F.iconOf(name), size = 20, color = confirming and "error" or "primary" }),
    ui.label({
      text = confirming and noctalia.tr("confirm.delete-finger", { finger = fingerLabel(name) }) or fingerLabel(name),
      color = confirming and "error" or nil,
      flexGrow = 1,
    }),
  }
  if pendingDeleteFinger == name then
    table.insert(children, ui.button({
      glyph = "check",
      variant = "destructive",
      onClick = function()
        deleteFinger(name)
      end,
    }))
    table.insert(children, ui.button({
      glyph = "close",
      variant = "ghost",
      onClick = function()
        pendingDeleteFinger = nil
        render()
      end,
    }))
  else
    table.insert(children, ui.button({
      glyph = "trash",
      variant = "ghost",
      tooltip = noctalia.tr("action.delete"),
      onClick = function()
        pendingDeleteFinger = name
        render()
      end,
    }))
  end
  return ui.row({
    key = "finger-" .. name,
    gap = 10,
    align = "center",
    padding = 10,
    fill = "surface_variant",
    radius = 8,
  }, children)
end

local function listBody()
  if not fprintdInstalled or not fprintdAvailable then
    local message = not fprintdInstalled
      and noctalia.tr("error.no-fprintd")
      or noctalia.tr("error.no-device")
    return ui.column({ flexGrow = 1, gap = 8, align = "center", justify = "center" }, {
      ui.glyph({ name = "alert-triangle", size = 32, color = "error" }),
      ui.label({ text = message, color = "error", textAlign = "center", maxWidth = 360 }),
    })
  end

  local rows = {}
  for _, name in ipairs(enrolledFingers) do
    table.insert(rows, fingerRow(name))
  end
  if #enrolledFingers == 0 then
    table.insert(rows, ui.label({ text = noctalia.tr("empty"), color = "on_surface_variant" }))
  end
  return ui.scroll({ flexGrow = 1, gap = 6 }, rows)
end

local function pickerBody()
  local available = F.availableForEnroll(enrolledFingers)
  local rows = {}
  for _, name in ipairs(available) do
    table.insert(rows, ui.button({
      text = fingerLabel(name),
      glyph = F.iconOf(name),
      contentAlign = "start",
      onClick = function()
        startEnroll(name)
      end,
    }))
  end
  if #available == 0 then
    table.insert(rows, ui.label({ text = noctalia.tr("picker.empty"), color = "on_surface_variant" }))
  end
  return ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ align = "center", justify = "space_between" }, {
      ui.label({ text = noctalia.tr("picker.title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({
        glyph = "close",
        onClick = function()
          view = "list"
          render()
        end,
      }),
    }),
    ui.scroll({ flexGrow = 1, gap = 8 }, rows),
  })
end

local function enrollingBody()
  local progress = enrollTotalStages > 0 and math.min(enrollStagesPassed / enrollTotalStages, 1) or 0
  return ui.column({ flexGrow = 1, gap = 16, align = "center" }, {
    ui.label({
      text = noctalia.tr("enroll.title", { finger = fingerLabel(enrollFinger or "") }),
      fontSize = 16,
      fontWeight = "bold",
    }),
    ui.glyph({ name = "fingerprint", size = 64, color = "primary" }),
    ui.progress({ progress = progress, fill = "primary" }),
    ui.label({
      text = `{enrollStagesPassed} / {enrollTotalStages}`,
      color = "on_surface_variant",
      fontSize = 12,
    }),
    ui.label({ text = enrollHint, textAlign = "center" }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({ text = noctalia.tr("action.cancel"), onClick = cancelEnroll }),
  })
end

local function headerRow()
  local summary = noctalia.tr("subtitle.summary", {
    user = currentUser(),
    count = tostring(#enrolledFingers),
    max = tostring(#F.ALL_FINGERS),
  })
  return ui.row({ gap = 12, align = "center" }, {
    ui.glyph({ name = "fingerprint", size = 28, color = "primary" }),
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label({ text = noctalia.tr("title"), fontSize = 16, fontWeight = "bold" }),
      ui.label({ text = summary, fontSize = 12, color = "on_surface_variant" }),
    }),
    ui.button({
      glyph = "refresh",
      variant = "ghost",
      tooltip = noctalia.tr("action.refresh"),
      onClick = function()
        refreshList()
      end,
    }),
  })
end

local function actionsRow()
  if pendingDeleteAll then
    return ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = noctalia.tr("confirm.delete-all"), color = "error", flexGrow = 1 }),
      ui.button({
        glyph = "check",
        variant = "destructive",
        onClick = function()
          deleteAll()
        end,
      }),
      ui.button({
        glyph = "close",
        variant = "ghost",
        onClick = function()
          pendingDeleteAll = false
          render()
        end,
      }),
    })
  end

  local atMax = #enrolledFingers >= #F.ALL_FINGERS
  local busy = busyMessage ~= ""
  return ui.row({ gap = 8 }, {
    ui.button({
      glyph = "plus",
      text = noctalia.tr("action.enroll"),
      enabled = not atMax and not busy,
      onClick = function()
        view = "picker"
        render()
      end,
    }),
    ui.button({
      glyph = "fingerprint",
      text = noctalia.tr("action.test"),
      enabled = #enrolledFingers > 0 and not busy,
      onClick = function()
        testMatch()
      end,
    }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({
      glyph = "trash",
      text = noctalia.tr("action.delete-all"),
      variant = "destructive",
      enabled = #enrolledFingers > 0 and not busy,
      onClick = function()
        pendingDeleteAll = true
        render()
      end,
    }),
  })
end

-- ---------- render ----------

render = function()
  local body
  if view == "picker" then
    body = pickerBody()
  elseif view == "enrolling" then
    body = enrollingBody()
  else
    body = ui.column({ flexGrow = 1, gap = 12 }, {
      headerRow(),
      ui.separator({}),
      listBody(),
    })
  end

  local children = { body }

  if view == "list" then
    local status = statusLine()
    if status ~= nil then
      table.insert(children, status)
    end
    if fprintdInstalled and fprintdAvailable then
      table.insert(children, ui.separator({}))
      table.insert(children, actionsRow())
    end
  end

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, children))
end

-- ---------- lifecycle ----------

function onOpen(_context)
  noctalia.setUpdateInterval(30000)
  if enrollFinger == nil then
    view = "list"
  end
  pendingDeleteFinger = nil
  pendingDeleteAll = false
  if not checkedInstalled then
    checkInstalled()
  elseif view == "list" then
    refreshList()
  end
  render()
end

function update()
  if view == "list" and fprintdInstalled and fprintdAvailable then
    refreshList()
  end
end
