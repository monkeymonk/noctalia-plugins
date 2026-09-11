import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../lib/scripts.js" as Scripts
import "../Components"
import qs.Commons
import qs.Widgets

// Scripts: create/edit/delete named helper scripts in ~/.config/niri/scripts/.
// They become referenceable from binds as spawn "/…/scripts/<name>". Ships a
// focus-or-spawn (app-toggle) template. Writes are gated by the write-mode setting.
ColumnLayout {
    id: root

    required property var panel
    required property var configModel

    property string dir: Scripts.scriptsDir(configModel.configDir)
    property var scripts: []
    property string sectionFile: dir  // the scripts folder (Edit-file opens it); per-script edit buttons too

    spacing: Style.marginM

    Component.onCompleted: refresh()
    Connections {
        target: root.panel
        function onRawFileChanged(path) { root.refresh(); }
    }

    function refresh() { if (dir) listProcess.running = true; }

    function saveScript(name, content) {
        var path = dir + "/" + name;
        panel.writeFileNow(path, content, panel.tr("scripts.summary", "script {n}", { n: name }),
                           { executable: true });
    }
    function removeScript(entry) {
        panel.deleteFile(entry.path, panel.tr("scripts.summary-del", "delete {n}", { n: entry.name }));
    }

    Process {
        id: listProcess
        command: Scripts.listCmd(root.dir)
        property string text: ""
        stdout: StdioCollector { onStreamFinished: listProcess.text = this.text }
        onExited: { root.scripts = Scripts.parseList(listProcess.text, root.dir); }
    }
    Process {
        id: catProcess
        property string text: ""
        property string name: ""
        stdout: StdioCollector { onStreamFinished: catProcess.text = this.text }
        onExited: { scriptEditor.openEdit(catProcess.name, catProcess.text); }
    }

    // ----- header -----
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NText { text: panel.tr("scripts.count", "{n} scripts", { n: root.scripts.length }); font.weight: Style.fontWeightBold }
        Item { Layout.fillWidth: true }
        NButton { icon: "plus"; text: panel.tr("scripts.new", "New script"); onClicked: scriptEditor.openCreate() }
    }
    NText {
        Layout.fillWidth: true
        text: panel.tr("scripts.hint", "Saved to ~/.config/niri/scripts/ and made executable. Reference one from a shortcut as a spawn command.")
        color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeS; wrapMode: Text.WordWrap
    }

    // ----- list -----
    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginXS
            NText { visible: root.scripts.length === 0; text: panel.tr("scripts.none", "No scripts yet."); color: Color.mOnSurfaceVariant }
            Repeater {
                model: root.scripts
                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: sRow.implicitHeight + Style.marginS * 2
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    RowLayout {
                        id: sRow
                        anchors.fill: parent
                        anchors.margins: Style.marginS
                        spacing: Style.marginM
                        NIcon { icon: modelData.executable ? "file-code" : "file"; pointSize: Style.fontSizeL; color: modelData.executable ? Color.mPrimary : Color.mError }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            NText { text: modelData.name; font.weight: Style.fontWeightMedium; font.family: "monospace"; font.pointSize: Style.fontSizeS }
                            NText { text: modelData.path; color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        }
                        NIconButton { icon: "edit"; tooltipText: panel.tr("action.edit", "Edit"); onClicked: { catProcess.name = modelData.name; catProcess.command = ["cat", modelData.path]; catProcess.running = true; } }
                        NIconButton { icon: "external-link"; tooltipText: panel.tr("action.open-editor", "Open in editor"); onClicked: panel.openInEditor(modelData.path) }
                        NIconButton { icon: "trash"; tooltipText: panel.tr("action.delete", "Delete"); onClicked: root.removeScript(modelData) }
                    }
                }
            }
        }
    }

    ScriptEditor {
        id: scriptEditor
        translate: root.panel.tr
        onAccepted: (name, content) => root.saveScript(name, content)
    }
}
