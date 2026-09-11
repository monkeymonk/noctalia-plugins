import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Modal confirmation for a destructive action. The owning section supplies the
// already-translated `message` and an opaque `payload`; on confirm the payload
// comes back untouched via confirmed(payload). Knows nothing about what it deletes.
Item {
    id: root

    property var translate: null
    property string confirmText: tr("action.delete", "Delete")

    property var payload: null
    property string message: ""

    signal confirmed(var payload)

    function tr(k, f, p) { return translate ? translate(k, f, p) : f; }

    function openFor(p, msg) { payload = p; message = msg; pop.open(); }

    visible: false

    Popup {
        id: pop
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 380; padding: Style.marginL
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mError; border.width: 1 }
        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM
            NText {
                Layout.fillWidth: true
                text: root.message
                font.weight: Style.fontWeightBold; color: Color.mError; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                NButton { text: root.tr("action.cancel", "Cancel"); onClicked: pop.close() }
                NButton {
                    text: root.confirmText
                    backgroundColor: Color.mError; textColor: Color.mOnError
                    onClicked: {
                        var p = root.payload;
                        pop.close();
                        root.confirmed(p);
                    }
                }
            }
        }
    }
}
