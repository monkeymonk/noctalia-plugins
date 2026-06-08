import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../lib/niri.js" as Niri
import qs.Commons
import qs.Widgets

// Lists currently-open windows (live, via `niri msg windows`) so a rule can be
// seeded from a real window. Emits picked(appId, title).
Item {
    id: root

    property var panel: null
    property var windows: []
    property string filter: ""

    signal picked(string appId, string title)

    function tr(k, f) { return panel ? panel.tr(k, f) : f; }
    function open() { loadProcess.running = true; popup.open(); }

    visible: false

    Process {
        id: loadProcess
        command: Niri.jsonCmd("windows")
        property string text: ""
        stdout: StdioCollector { onStreamFinished: loadProcess.text = this.text }
        onExited: { root.windows = Niri.parseWindows(loadProcess.text); }
    }

    Popup {
        id: popup
        modal: true
        focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - Style.marginXL : 560, 560)
        height: Math.min(parent ? parent.height - Style.marginXL : 460, 460)
        padding: Style.marginL
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mOutline; border.width: 1 }

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            NText {
                text: root.tr("windowpicker.title", "Pick an open window")
                font.pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
            }
            NText {
                Layout.fillWidth: true
                text: root.tr("windowpicker.hint", "Its app-id and title will pre-fill the match.")
                color: Color.mOnSurfaceVariant
                font.pointSize: Style.fontSizeS
                wrapMode: Text.WordWrap
            }
            NTextInput {
                Layout.fillWidth: true
                placeholderText: root.tr("windowpicker.search", "Filter windows…")
                onTextChanged: root.filter = text
            }
            NScrollView {
                id: wpScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalPolicy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: wpScroll.availableWidth
                    spacing: Style.marginXS
                    NText {
                        visible: root.windows.length === 0
                        text: root.tr("windowpicker.none", "No open windows reported by niri.")
                        color: Color.mOnSurfaceVariant
                    }
                    Repeater {
                        model: root.windows
                        delegate: Rectangle {
                            property bool show: !root.filter
                                || (modelData.appId + " " + modelData.title).toLowerCase().indexOf(root.filter.toLowerCase()) !== -1
                            Layout.fillWidth: true
                            visible: show
                            implicitHeight: show ? (wRow.implicitHeight + Style.marginS * 2) : 0
                            radius: Style.radiusM
                            color: wMouse.containsMouse ? Color.mHover : Color.mSurfaceVariant
                            RowLayout {
                                id: wRow
                                anchors.fill: parent
                                anchors.margins: Style.marginS
                                spacing: Style.marginM
                                NIcon { icon: "app-window"; pointSize: Style.fontSizeL; color: Color.mPrimary }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    NText { text: modelData.appId || "—"; font.weight: Style.fontWeightMedium; font.family: "monospace"; font.pointSize: Style.fontSizeS; elide: Text.ElideRight; Layout.fillWidth: true }
                                    NText { text: modelData.title || ""; color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                            MouseArea {
                                id: wMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { popup.close(); root.picked(modelData.appId || "", modelData.title || ""); }
                            }
                        }
                    }
                }
            }
        }
    }
}
