import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Add a config block for a monitor by name (typically one that isn't currently
// connected). Emits accepted(name) with the trimmed connector/model name.
Item {
    id: root

    property var translate: null

    signal accepted(string name)

    function tr(k, f, p) { return translate ? translate(k, f, p) : f; }

    function openCreate() { pop.open(); }

    visible: false

    Popup {
        id: pop
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 380; padding: Style.marginL
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }
        onOpened: addName.text = ""
        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM
            NText { text: root.tr("monitors.add-title", "Add monitor config"); font.weight: Style.fontWeightBold; font.pointSize: Style.fontSizeL }
            NText {
                Layout.fillWidth: true
                text: root.tr("monitors.add-hint", "Use the exact connector or model name (run `niri msg outputs`).")
                color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeS; wrapMode: Text.WordWrap
            }
            NTextInput { id: addName; Layout.fillWidth: true; placeholderText: 'DP-2 or "Maker Model …"' }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                NButton { text: root.tr("action.cancel", "Cancel"); onClicked: pop.close() }
                NButton {
                    text: root.tr("action.add-shortcut", "Add")
                    backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                    enabled: addName.text.trim() !== ""
                    onClicked: {
                        var n = addName.text.trim();
                        pop.close();
                        root.accepted(n);
                    }
                }
            }
        }
    }
}
