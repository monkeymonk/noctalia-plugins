--!nonstrict
-- Control-center shortcut - mirrors v4's ControlCenterWidget.qml. A plain
-- panel-opening tile, not a toggle state, so setActive always stays false.
-- Visibility is controlled natively via Settings -> Control Center Shortcuts.

local PANEL_ID = "monkeymonk/fingerprint-manager:panel"

local function render()
  shortcut.setLabel(noctalia.tr("bar.tooltip"))
  shortcut.setIcon("fingerprint")
  shortcut.setActive(false)
  shortcut.setEnabled(true)
end

render()

function onClick()
  noctalia.togglePanel(PANEL_ID)
end
