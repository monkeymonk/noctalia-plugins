import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Add/rename a named workspace. Emits accepted(entry, name, output):
//   entry === null → create; else → rename that workspace.
Item {
    id: root

    property var translate: null
    property var entry: null

    signal accepted(var entry, string name, string output)

    function tr(k, f, p) { return translate ? translate(k, f, p) : f; }

    function openCreate() { entry = null; nameField.text = ""; outputField.text = ""; pop.open(); }
    function openRename(e) { entry = e; nameField.text = e.name; outputField.text = e.output || ""; pop.open(); }

    visible: false

    Popup {
        id: pop
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 360; padding: Style.marginL
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }
        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM
            NText {
                text: root.entry ? root.tr("ws.rename", "Rename workspace") : root.tr("ws.new", "New workspace")
                font.weight: Style.fontWeightBold; font.pointSize: Style.fontSizeL
            }
            NTextInput { id: nameField; Layout.fillWidth: true; label: root.tr("ws.name", "Name"); placeholderText: root.tr("ws.name-ph", "workspace name") }
            NTextInput { id: outputField; Layout.fillWidth: true; label: root.tr("ws.output", "Open on output (optional)"); placeholderText: "DP-1" }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                NButton { text: root.tr("action.cancel", "Cancel"); onClicked: pop.close() }
                NButton {
                    text: root.tr("action.save", "Save")
                    backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                    enabled: nameField.text.trim() !== ""
                    onClicked: {
                        var n = nameField.text.trim(), o = outputField.text.trim();
                        pop.close();
                        root.accepted(root.entry, n, o);
                    }
                }
            }
        }
    }
}
