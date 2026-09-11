import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/scripts.js" as Scripts
import qs.Commons
import qs.Widgets

// Create/edit a helper script. Emits accepted(name, content):
//   editName === "" → create; else → overwrite that script.
Item {
    id: root

    property var translate: null
    property string editName: ""

    signal accepted(string name, string content)

    function tr(k, f, p) { return translate ? translate(k, f, p) : f; }

    function openCreate() {
        editName = "";
        nameF.text = "";
        bodyArea.text = Scripts.blankTemplate();
        appIdF.text = "";
        cmdF.text = "";
        pop.open();
    }

    function openEdit(name, content) {
        editName = name;
        nameF.text = name;
        bodyArea.text = content;
        pop.open();
    }

    visible: false

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
            NText { text: root.editName ? root.tr("scripts.edit", "Edit script") : root.tr("scripts.create", "New script"); font.weight: Style.fontWeightBold; font.pointSize: Style.fontSizeL }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                NTextInput { id: nameF; Layout.fillWidth: true; readOnly: root.editName !== ""; label: root.tr("scripts.name", "Name"); placeholderText: "toggle-foo" }
                NComboBox {
                    Layout.preferredWidth: 220
                    visible: root.editName === ""
                    label: root.tr("scripts.template", "Template")
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
                NTextInput { id: appIdF; Layout.fillWidth: true; label: root.tr("scripts.appid", "app-id"); placeholderText: "org.foo.Bar"; onTextChanged: bodyArea.text = Scripts.buildTemplate("focus-or-spawn", { appId: appIdF.text, command: cmdF.text }) }
                NTextInput { id: cmdF; Layout.fillWidth: true; label: root.tr("scripts.command", "launch command"); placeholderText: "foo"; onTextChanged: bodyArea.text = Scripts.buildTemplate("focus-or-spawn", { appId: appIdF.text, command: cmdF.text }) }
            }

            NText { text: root.tr("scripts.body", "Script"); font.pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
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
                NButton { text: root.tr("action.cancel", "Cancel"); onClicked: pop.close() }
                NButton {
                    text: root.tr("action.save", "Save")
                    backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                    enabled: nameF.text.trim() !== ""
                    onClicked: { var n = nameF.text.trim(), b = bodyArea.text; pop.close(); root.accepted(n, b); }
                }
            }
        }
    }
}
