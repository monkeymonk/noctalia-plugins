import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    property string valueIconColor: cfg.iconColor ?? defaults.iconColor
    property bool valueShowInControlCenter: (cfg.showInControlCenter ?? defaults.showInControlCenter) ?? true

    spacing: Style.marginM

    NColorChoice {
        label: pluginApi?.tr("settings.iconColor.label")
        description: pluginApi?.tr("settings.iconColor.desc")
        currentKey: root.valueIconColor
        onSelected: key => root.valueIconColor = key
    }

    NToggle {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.controlCenter.label")
        description: pluginApi?.tr("settings.controlCenter.desc")
        checked: root.valueShowInControlCenter
        onToggled: v => root.valueShowInControlCenter = v
    }

    function saveSettings() {
        if (!pluginApi) return;
        pluginApi.pluginSettings.iconColor = root.valueIconColor;
        pluginApi.pluginSettings.showInControlCenter = root.valueShowInControlCenter;
        pluginApi.saveSettings();
    }
}
