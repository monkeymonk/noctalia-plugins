import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../lib/desktop.js" as Desktop
import "../lib/config.js" as Cfg
import "../lib/scripts.js" as Scripts
import qs.Commons
import qs.Widgets

// Lists the user's niri scripts + installed .desktop apps (+ a raw command
// field). Emits picked(command).
Item {
    id: root

    property var panel: null
    property var apps: []          // [{name, exec, icon, comment}]
    property var scripts: []       // [{name, path, executable}]
    property bool loaded: false
    property string filter: ""
    readonly property string home: Quickshell.env("HOME") || ""

    signal picked(string command)

    function tr(k, f) { return panel ? panel.tr(k, f) : f; }

    function open() {
        if (!loaded) loadProcess.running = true;
        scriptsProcess.running = true;
        popup.open();
    }

    visible: false

    Process {
        id: scriptsProcess
        command: Scripts.listCmd(Scripts.scriptsDir(root.home))
        property string text: ""
        stdout: StdioCollector { onStreamFinished: scriptsProcess.text = this.text }
        onExited: { root.scripts = Scripts.parseList(scriptsProcess.text, Scripts.scriptsDir(root.home)); }
    }

    Process {
        id: loadProcess
        command: ["sh", "-c",
            'for d in /usr/share/applications /usr/local/share/applications "$HOME/.local/share/applications"; do ' +
            '[ -d "$d" ] && for f in "$d"/*.desktop; do [ -f "$f" ] && { printf "%s%s>>>>\\n" "' + Cfg.FILE_MARKER + '" "$f"; cat "$f"; printf "\\n"; }; done; done']
        property string text: ""
        stdout: StdioCollector { onStreamFinished: loadProcess.text = this.text }
        onExited: {
            var map = Cfg.splitFileBlob(loadProcess.text);
            var seen = {}, list = [];
            for (var p in map) {
                var e = Desktop.parseDesktopEntry(map[p]);
                if (e && !seen[e.name + "|" + e.exec]) { seen[e.name + "|" + e.exec] = 1; list.push(e); }
            }
            list.sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1; });
            root.apps = list;
            root.loaded = true;
        }
    }

    Popup {
        id: popup
        modal: true
        focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - Style.marginXL : 520, 520)
        height: Math.min(parent ? parent.height - Style.marginXL : 480, 480)
        padding: Style.marginL
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mOutline; border.width: 1 }

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            NText {
                text: root.tr("apppicker.title", "Pick an application")
                font.pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
            }

            NTextInput {
                Layout.fillWidth: true
                placeholderText: root.tr("apppicker.search", "Search apps…")
                onTextChanged: root.filter = text
            }

            NScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    width: parent.width
                    spacing: Style.marginXS

                    NText {
                        visible: root.scripts.length > 0
                        text: root.tr("apppicker.scripts", "Your scripts")
                        font.pointSize: Style.fontSizeXS; font.weight: Style.fontWeightBold; color: Color.mPrimary
                    }
                    Repeater {
                        model: root.scripts
                        delegate: Rectangle {
                            property bool show: !root.filter || modelData.name.toLowerCase().indexOf(root.filter.toLowerCase()) !== -1
                            Layout.fillWidth: true
                            visible: show
                            implicitHeight: show ? (scRow.implicitHeight + Style.marginS * 2) : 0
                            radius: Style.radiusM
                            color: scMouse.containsMouse ? Color.mHover : Color.mSurfaceVariant
                            RowLayout {
                                id: scRow
                                anchors.fill: parent; anchors.margins: Style.marginS; spacing: Style.marginM
                                NIcon { icon: "file-code"; pointSize: Style.fontSizeL; color: Color.mPrimary }
                                NText { Layout.fillWidth: true; text: modelData.name; font.family: "monospace"; font.pointSize: Style.fontSizeS; elide: Text.ElideRight }
                            }
                            MouseArea { id: scMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { popup.close(); root.picked(modelData.path); } }
                        }
                    }
                    NDivider { Layout.fillWidth: true; visible: root.scripts.length > 0 }

                    NText {
                        visible: !root.loaded
                        text: root.tr("apppicker.loading", "Loading apps…")
                        color: Color.mOnSurfaceVariant
                    }

                    Repeater {
                        model: root.apps
                        delegate: Rectangle {
                            property bool show: !root.filter || modelData.name.toLowerCase().indexOf(root.filter.toLowerCase()) !== -1
                            Layout.fillWidth: true
                            visible: show
                            implicitHeight: show ? (appRow.implicitHeight + Style.marginS * 2) : 0
                            radius: Style.radiusM
                            color: appMouse.containsMouse ? Color.mHover : Color.mSurfaceVariant
                            RowLayout {
                                id: appRow
                                anchors.fill: parent
                                anchors.margins: Style.marginS
                                spacing: Style.marginM
                                NIcon { icon: "app-window"; pointSize: Style.fontSizeL; color: Color.mPrimary }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    NText { text: modelData.name; font.weight: Style.fontWeightMedium; elide: Text.ElideRight; Layout.fillWidth: true }
                                    NText { text: modelData.exec; color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; font.family: "monospace"; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                            MouseArea {
                                id: appMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { popup.close(); root.picked(modelData.exec); }
                            }
                        }
                    }
                }
            }

            // raw command entry
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                NTextInput {
                    id: rawCmd
                    Layout.fillWidth: true
                    placeholderText: root.tr("apppicker.raw", "…or type a command")
                    onAccepted: if (text) { popup.close(); root.picked(text); }
                }
                NButton {
                    text: root.tr("action.use", "Use")
                    enabled: rawCmd.text !== ""
                    onClicked: { var c = rawCmd.text; popup.close(); root.picked(c); }
                }
            }
        }
    }
}
