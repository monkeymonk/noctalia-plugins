import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Read-only viewer for sections that don't yet have a dedicated editor.
// Shows the owning file(s) verbatim so nothing is ever altered. Interactive
// editors (Monitors, Input, …) replace these incrementally.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null
    property string sectionKey: ""
    property string sectionFile: files.length ? files[0] : ""

    spacing: Style.marginM

    // sectionKey → node names that identify the owning file(s)
    readonly property var sectionNodes: ({
        "monitors": ["output"],
        "input": ["input"],
        "workspaces": ["workspace"],
        "rules": ["window-rule", "layer-rule"],
        "layout": ["layout"],
        "animation": ["animations"],
        "autostart": ["spawn-at-startup", "spawn-sh-at-startup"],
        "misc": ["prefer-no-csd", "cursor", "environment", "hotkey-overlay", "gestures", "screenshot-path", "overview", "clipboard"]
    })

    function targetFiles() {
        if (!configModel || !configModel.loaded) return [];
        var names = sectionNodes[sectionKey] || [];
        var owners = configModel.owners(names);
        // For monitors, also surface the conventional display files even if all-commented.
        var paths = {};
        var out = [];
        for (var i = 0; i < owners.length; i++) {
            if (!paths[owners[i].path]) { paths[owners[i].path] = 1; out.push(owners[i].path); }
        }
        if (out.length === 0 && configModel.files) {
            // fall back: any file whose name hints at this section
            for (var j = 0; j < configModel.files.length; j++) {
                var p = configModel.files[j].path;
                if (p.toLowerCase().indexOf(sectionKey === "monitors" ? "display" : sectionKey) !== -1
                    || (sectionKey === "monitors" && p.toLowerCase().indexOf("monitor") !== -1)) out.push(p);
            }
        }
        return out;
    }

    property var files: configModel && configModel.loaded ? targetFiles() : []

    Connections {
        target: root.configModel
        function onLoadFinished() { root.files = root.targetFiles(); }
    }

    NText {
        text: (panel ? panel.tr("raw.header", "Read-only view") : "Read-only view")
        font.weight: Style.fontWeightBold
    }
    NText {
        Layout.fillWidth: true
        text: panel ? panel.tr("raw.note", "A dedicated editor for this section is coming. For now it's shown verbatim and never modified.") : ""
        color: Color.mOnSurfaceVariant
        font.pointSize: Style.fontSizeS
        wrapMode: Text.WordWrap
    }

    NScrollView {
        id: rawScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: rawScroll.availableWidth
            spacing: Style.marginM

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                visible: root.files.length === 0
                NText {
                    anchors.centerIn: parent
                    text: panel ? panel.tr("raw.empty", "No configuration found for this section.") : ""
                    color: Color.mOnSurfaceVariant
                }
            }

            Repeater {
                model: root.files
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXS
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        NText {
                            Layout.fillWidth: true
                            text: modelData.replace((root.configModel ? root.configModel.home : "") , "~")
                            font.pointSize: Style.fontSizeS
                            color: Color.mPrimary
                            font.weight: Style.fontWeightBold
                            elide: Text.ElideMiddle
                        }
                        NIconButton {
                            icon: "edit"
                            tooltipText: panel ? panel.tr("action.open-editor", "Open in editor") : "Open in editor"
                            onClicked: if (panel) panel.openInEditor(modelData)
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        color: Color.mSurfaceVariant
                        radius: Style.radiusS
                        clip: true
                        implicitHeight: ta.implicitHeight + Style.marginM
                        TextArea {
                            id: ta
                            anchors.fill: parent
                            anchors.margins: Style.marginS
                            readOnly: true
                            wrapMode: TextArea.Wrap
                            text: root.configModel ? root.configModel.textOf(modelData) : ""
                            font.family: "monospace"
                            font.pointSize: Style.fontSizeS
                            color: Color.mOnSurface
                            background: null
                        }
                    }
                }
            }
        }
    }
}
