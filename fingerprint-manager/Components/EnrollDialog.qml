import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../fprintUtils.js" as F
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property string finger: ""
    property int stagesPassed: 0
    property int totalStages: 10   // typical for Goodix 609c; refined as we observe
    property string hint: ""
    property bool active: false

    signal finished(bool ok)

    function tr(k, fallback, params) {
        var s = null;
        if (pluginApi && pluginApi.tr) {
            var v = pluginApi.tr(k);
            if (v && v !== k && !/^!!.*!!$/.test(v)) s = v;
        }
        if (s === null) s = fallback;
        if (params) {
            for (var key in params) s = s.replace("{" + key + "}", params[key]);
        }
        return s;
    }

    function fingerLabel(name) {
        return tr("finger." + name, F.labelOf(name));
    }

    function openFor(name) {
        finger = name;
        stagesPassed = 0;
        hint = tr("enroll.hint.touch", "Place your finger on the sensor.");
        active = true;
        enrollProcess.command = ["fprintd-enroll", "-f", name];
        enrollProcess.running = true;
        popup.open();
    }

    function cancel() {
        if (enrollProcess.running) enrollProcess.signal(15); // SIGTERM
        active = false;
        popup.close();
        finished(false);
    }

    visible: active

    Process {
        id: enrollProcess
        stdout: SplitParser {
            onRead: line => {
                var k = F.classifyEnrollLine(line);
                if (k === "stage-pass") {
                    root.stagesPassed += 1;
                    root.hint = root.tr("enroll.hint.again", "Good — lift and place again.");
                } else if (k === "retry") {
                    root.hint = root.tr("enroll.hint.retry", "Adjust position and try again.");
                } else if (k === "completed") {
                    root.active = false;
                    popup.close();
                    root.finished(true);
                } else if (k === "failed") {
                    root.active = false;
                    popup.close();
                    root.finished(false);
                }
            }
        }
        onExited: (code) => {
            if (root.active) {
                root.active = false;
                popup.close();
                root.finished(code === 0);
            }
        }
    }

    Popup {
        id: popup
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        anchors.centerIn: parent
        padding: Style.marginL
        width: Math.min(parent ? parent.width - Style.marginXL * 2 : 400, 440)

        background: Rectangle {
            color: Color.mSurface
            radius: Style.radiusM
            border.color: Color.mOutline
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            NText {
                text: root.tr("enroll.title", "Enrolling {finger}", { finger: root.fingerLabel(root.finger) })
                font.pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
            }

            NIcon {
                Layout.alignment: Qt.AlignHCenter
                icon: "fingerprint"
                pointSize: 64
                color: Color.mPrimary
            }

            ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: root.totalStages
                value: Math.min(root.stagesPassed, root.totalStages)
            }

            NText {
                Layout.fillWidth: true
                text: root.stagesPassed + " / " + root.totalStages
                horizontalAlignment: Text.AlignHCenter
                color: Color.mOnSurfaceVariant
                font.pointSize: Style.fontSizeS
            }

            NText {
                Layout.fillWidth: true
                text: root.hint
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                NButton {
                    text: root.tr("action.cancel", "Cancel")
                    onClicked: root.cancel()
                }
            }
        }
    }
}
