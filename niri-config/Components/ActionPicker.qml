import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/binds.js" as Binds
import qs.Commons
import qs.Widgets

// Lists the niri action vocabulary (grouped, filterable). Emits picked(name, argType).
Item {
    id: root

    property var panel: null
    property string filter: ""

    signal picked(string name, string argType)

    function tr(k, f) { return panel ? panel.tr(k, f) : f; }
    function open() { popup.open(); }

    visible: false

    readonly property var actions: Binds.ACTIONS

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
                text: root.tr("actionpicker.title", "Pick an action")
                font.pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
            }

            NTextInput {
                Layout.fillWidth: true
                placeholderText: root.tr("actionpicker.search", "Search actions…")
                onTextChanged: root.filter = text
            }

            NScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    width: parent.width
                    spacing: Style.marginXS

                    Repeater {
                        model: root.actions
                        delegate: Rectangle {
                            property bool show: !root.filter
                                || modelData.name.toLowerCase().indexOf(root.filter.toLowerCase()) !== -1
                                || modelData.cat.toLowerCase().indexOf(root.filter.toLowerCase()) !== -1
                            Layout.fillWidth: true
                            visible: show
                            implicitHeight: show ? (aRow.implicitHeight + Style.marginS * 2) : 0
                            radius: Style.radiusM
                            color: aMouse.containsMouse ? Color.mHover : Color.mSurfaceVariant
                            RowLayout {
                                id: aRow
                                anchors.fill: parent
                                anchors.margins: Style.marginS
                                spacing: Style.marginM
                                NText {
                                    Layout.fillWidth: true
                                    text: modelData.name.replace(/-/g, " ")
                                    elide: Text.ElideRight
                                }
                                NText {
                                    text: modelData.cat
                                    color: Color.mOnSurfaceVariant
                                    font.pointSize: Style.fontSizeXS
                                }
                                NText {
                                    visible: modelData.arg !== "none"
                                    text: "+arg"
                                    color: Color.mPrimary
                                    font.pointSize: Style.fontSizeXS
                                }
                            }
                            MouseArea {
                                id: aMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { popup.close(); root.picked(modelData.name, modelData.arg); }
                            }
                        }
                    }
                }
            }
        }
    }
}
