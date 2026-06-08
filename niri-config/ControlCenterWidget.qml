import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

NIconButton {
    id: root

    property ShellScreen screen
    property var pluginApi: null

    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    readonly property bool show: (cfg.showInControlCenter ?? defaults.showInControlCenter) ?? true

    visible: show
    icon: "device-desktop-cog"
    tooltipText: pluginApi?.tr("bar.tooltip")

    onClicked: {
        if (pluginApi) pluginApi.togglePanel(screen);
    }
}
