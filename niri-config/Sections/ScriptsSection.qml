import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../lib/scripts.js" as Scripts
import qs.Commons
import qs.Widgets

// Scripts: create/edit/delete named helper scripts in ~/.config/niri/scripts/.
// They become referenceable from binds as spawn "/…/scripts/<name>". Ships a
// focus-or-spawn (app-toggle) template. Writes are gated by the write-mode setting.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

    property string dir: (configModel ? Scripts.scriptsDir(configModel.home) : "")
    property var scripts: []
    property string sectionFile: dir  // the scripts folder (Edit-file opens it); per-script edit buttons too

    spacing: Style.marginM

    Component.onCompleted: refresh()
    Connections {
        target: root.panel
        function onFileSaved(path) { root.refresh(); }
    }

    function refresh() { if (dir) listProcess.running = true; }

    function saveScript(name, content) {
        var path = dir + "/" + name;
        panel.requestSave(path, content, panel.tr("scripts.summary", "script {n}", { n: name }),
                          { raw: true, executable: true });
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
        onExited: { editor.openEdit(catProcess.name, catProcess.text); }
    }

    // ----- header -----
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NText { text: panel.tr("scripts.count", "{n} scripts", { n: root.scripts.length }); font.weight: Style.fontWeightBold }
        Item { Layout.fillWidth: true }
        NButton { icon: "plus"; text: panel.tr("scripts.new", "New script"); onClicked: editor.openCreate() }
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

    // ----- editor dialog -----
    Item {
        id: editor
        property string original: ""
        function openCreate() { nameF.text = ""; nameF.readOnly = false; bodyArea.text = Scripts.blankTemplate(); appIdF.text = ""; cmdF.text = ""; pop.open(); }
        function openEdit(name, content) { nameF.text = name; nameF.readOnly = true; bodyArea.text = content; pop.open(); }

        Popup {
            id: pop
            modal: true; focus: true
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: Math.min(parent ? parent.width - Style.marginXL : 640, 640)
            height: Math.min(parent ? parent.height - Style.marginXL : 560, 560)
            padding: Style.marginL
            closePolicy: Popup.CloseOnEscape
            background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }

            ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginM
                NText { text: nameF.readOnly ? panel.tr("scripts.edit", "Edit script") : panel.tr("scripts.create", "New script"); font.weight: Style.fontWeightBold; font.pointSize: Style.fontSizeL }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    NTextInput { id: nameF; Layout.fillWidth: true; label: panel.tr("scripts.name", "Name"); placeholderText: "toggle-foo" }
                    NComboBox {
                        Layout.preferredWidth: 220
                        visible: !nameF.readOnly
                        label: panel.tr("scripts.template", "Template")
                        model: Scripts.templates().map(function (t) { return { key: t.key, name: t.name }; })
                        currentKey: "blank"
                        onSelected: key => {
                            bodyArea.text = Scripts.buildTemplate(key, { appId: appIdF.text, command: cmdF.text });
                            tplRow.visible = (key === "focus-or-spawn");
                        }
                    }
                }
                RowLayout {
                    id: tplRow
                    Layout.fillWidth: true
                    visible: false
                    spacing: Style.marginS
                    NTextInput { id: appIdF; Layout.fillWidth: true; label: panel.tr("scripts.appid", "app-id"); placeholderText: "org.foo.Bar"; onTextChanged: bodyArea.text = Scripts.buildTemplate("focus-or-spawn", { appId: appIdF.text, command: cmdF.text }) }
                    NTextInput { id: cmdF; Layout.fillWidth: true; label: panel.tr("scripts.command", "launch command"); placeholderText: "foo"; onTextChanged: bodyArea.text = Scripts.buildTemplate("focus-or-spawn", { appId: appIdF.text, command: cmdF.text }) }
                }

                NText { text: panel.tr("scripts.body", "Script"); font.pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Color.mSurfaceVariant
                    radius: Style.radiusS
                    clip: true
                    NScrollView {
                        anchors.fill: parent
                        anchors.margins: Style.marginXS
                        TextArea {
                            id: bodyArea
                            wrapMode: TextArea.NoWrap
                            font.family: "monospace"
                            font.pointSize: Style.fontSizeS
                            color: Color.mOnSurface
                            background: null
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    NButton { text: panel.tr("action.cancel", "Cancel"); onClicked: pop.close() }
                    NButton {
                        text: panel.tr("action.save", "Save")
                        backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                        enabled: nameF.text.trim() !== ""
                        onClicked: { var n = nameF.text.trim(), b = bodyArea.text; pop.close(); root.saveScript(n, b); }
                    }
                }
            }
        }
    }
}
