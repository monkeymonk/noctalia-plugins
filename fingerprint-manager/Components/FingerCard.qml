import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
    id: root

    property string fingerName: ""
    property string label: ""
    property string iconName: "fingerprint"
    property string deleteTooltip: "Delete"

    signal deleteRequested()

    implicitHeight: bg.implicitHeight

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Style.radiusM
        color: Color.mSurfaceVariant
        implicitHeight: row.implicitHeight + Style.marginM * 2

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            NIcon {
                icon: root.iconName
                pointSize: Style.fontSizeL
                color: Color.mPrimary
            }
            NText {
                Layout.fillWidth: true
                text: root.label
                font.pointSize: Style.fontSizeM
            }
            NIconButton {
                icon: "trash"
                tooltipText: root.deleteTooltip
                onClicked: root.deleteRequested()
            }
        }
    }
}
