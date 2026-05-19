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

    spacing: Style.marginM

    NColorChoice {
        label: pluginApi?.tr("settings.iconColor.label")
        description: pluginApi?.tr("settings.iconColor.desc")
        currentKey: root.valueIconColor
        onSelected: key => root.valueIconColor = key
    }

    function saveSettings() {
        if (!pluginApi) return;
        pluginApi.pluginSettings.iconColor = root.valueIconColor;
        pluginApi.saveSettings();
    }
}
