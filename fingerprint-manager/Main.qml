import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var pluginApi: null

    IpcHandler {
        target: "plugin:fingerprint-manager"

        function openPanel() {
            if (root.pluginApi) {
                root.pluginApi.withCurrentScreen(screen => {
                    root.pluginApi.openPanel(screen);
                });
            }
        }
    }
}
