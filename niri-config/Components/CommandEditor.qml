import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Add/edit a startup spawn command. Emits accepted(entry, command):
//   entry === null → create; else → update that entry.
Item {
    id: root

    property var translate: null
    property string scriptsDir: ""     // resolved by the owning section
    property var entry: null

    signal accepted(var entry, string command)

    function tr(k, f, p) { return translate ? translate(k, f, p) : f; }

    function openCreate() { entry = null; cmdField.text = ""; pop.open(); }
    function openEdit(e) { entry = e; cmdField.text = e.cmd; pop.open(); }

    visible: false

    AppPicker {
        id: appPicker
        translate: root.tr
        scriptsDir: root.scriptsDir
        onPicked: (cmd) => cmdField.text = cmd
    }

    Popup {
        id: pop
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 460; padding: Style.marginL
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }
        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM
            NText { text: root.entry ? root.tr("autostart.editt", "Edit startup entry") : root.tr("autostart.newt", "New startup entry"); font.weight: Style.fontWeightBold; font.pointSize: Style.fontSizeL }
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                NTextInput { id: cmdField; Layout.fillWidth: true; placeholderText: root.tr("autostart.cmd-ph", "command to run") }
                NButton { text: root.tr("bindeditor.pick-app", "Pick app"); onClicked: appPicker.open() }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                NButton { text: root.tr("action.cancel", "Cancel"); onClicked: pop.close() }
                NButton {
                    text: root.tr("action.save", "Save")
                    backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                    enabled: cmdField.text.trim() !== ""
                    onClicked: {
                        var c = cmdField.text.trim();
                        pop.close();
                        root.accepted(root.entry, c);
                    }
                }
            }
        }
    }
}
