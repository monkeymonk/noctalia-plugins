--!nonstrict
-- Bar widget - a fingerprint glyph that toggles the panel. Mirrors v4's
-- BarWidget.qml; the v4 right-click "widget settings" context menu entry is
-- now the host's built-in middle-click binding, so no onRightClick is needed.

local PANEL_ID = "monkeymonk/fingerprint-manager:panel"

function update()
  noctalia.setUpdateInterval(30000)
  barWidget.setGlyph("fingerprint")
  barWidget.setGlyphColor(noctalia.getConfig("icon_color"))
  barWidget.setTooltip(noctalia.tr("bar.tooltip"))
end

function onClick()
  noctalia.togglePanel(PANEL_ID)
end
