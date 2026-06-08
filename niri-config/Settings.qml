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
    property string valueExternalEditor: cfg.externalEditor ?? defaults.externalEditor ?? ""

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

    NDivider { Layout.fillWidth: true }

    NTextInput {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.editor.label") || "External editor command"
        description: pluginApi?.tr("settings.editor.desc") || "Command to edit config files, e.g. 'ghostty -e nvim' (a terminal + editor). Leave empty to open the file's folder in your file manager instead."
        text: root.valueExternalEditor
        placeholderText: "ghostty -e nvim"
        onTextChanged: root.valueExternalEditor = text
    }

    function saveSettings() {
        if (!pluginApi) return;
        pluginApi.pluginSettings.iconColor = root.valueIconColor;
        pluginApi.pluginSettings.showInControlCenter = root.valueShowInControlCenter;
        pluginApi.pluginSettings.externalEditor = root.valueExternalEditor;
        pluginApi.saveSettings();
    }
}
