import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "fprintUtils.js" as F
import "Components"
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    property real contentPreferredWidth: 520 * Style.uiScaleRatio
    property real contentPreferredHeight: 560 * Style.uiScaleRatio

    property var enrolledFingers: []
    property bool fprintdInstalled: true
    property bool fprintdAvailable: true
    property string busyMessage: ""
    property string statusMessage: ""
    property color statusColor: Color.mOnSurfaceVariant
    property string pendingDeleteFinger: ""

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

    function refreshList() {
        if (fprintdInstalled) listProcess.running = true;
    }

    function requestDeleteFinger(name) {
        pendingDeleteFinger = name;
        confirmDeleteFinger.open();
    }

    function deleteFinger(name) {
        statusMessage = "";
        busyMessage = tr("status.deleting", "Deleting {finger}…", { finger: fingerLabel(name) });
        deleteProcess.command = ["fprintd-delete", Quickshell.env("USER") || "", "-f", name];
        deleteProcess.running = true;
    }

    function deleteAll() {
        statusMessage = "";
        busyMessage = tr("status.deleting-all", "Deleting all fingerprints…");
        deleteAllProcess.command = ["fprintd-delete", Quickshell.env("USER") || ""];
        deleteAllProcess.running = true;
    }

    function startEnroll(finger) {
        enrollDialog.openFor(finger);
    }

    Component.onCompleted: checkProcess.running = true

    Timer {
        interval: 30000
        repeat: true
        running: root.fprintdInstalled
        onTriggered: root.refreshList()
    }

    // ---------- Processes ----------

    Process {
        id: checkProcess
        command: ["sh", "-c", "command -v fprintd-list"]
        onExited: (code) => {
            root.fprintdInstalled = (code === 0);
            if (root.fprintdInstalled) root.refreshList();
        }
    }

    Process {
        id: listProcess
        command: ["fprintd-list", Quickshell.env("USER") || ""]

        property string stdoutText: ""
        property string stderrText: ""

        stdout: StdioCollector { onStreamFinished: listProcess.stdoutText = this.text }
        stderr: StdioCollector { onStreamFinished: listProcess.stderrText = this.text }

        onExited: (code) => {
            var err = (listProcess.stderrText || "").toLowerCase();
            if (err.indexOf("no devices") !== -1 || err.indexOf("no such device") !== -1) {
                root.fprintdAvailable = false;
            } else if (code === 0) {
                root.enrolledFingers = F.parseList(listProcess.stdoutText);
                root.fprintdAvailable = true;
            }
        }
    }

    Process {
        id: deleteProcess
        onExited: (code) => {
            root.busyMessage = "";
            if (code === 0) {
                root.statusMessage = root.tr("status.deleted", "Fingerprint deleted.");
                root.statusColor = Color.mPrimary;
            } else {
                root.statusMessage = root.tr("status.delete-failed", "Delete failed.");
                root.statusColor = Color.mError;
            }
            root.refreshList();
        }
    }

    Process {
        id: deleteAllProcess
        onExited: (code) => {
            root.busyMessage = "";
            if (code === 0) {
                root.statusMessage = root.tr("status.deleted-all", "All fingerprints deleted.");
                root.statusColor = Color.mPrimary;
            } else {
                root.statusMessage = root.tr("status.delete-failed", "Delete failed.");
                root.statusColor = Color.mError;
            }
            root.refreshList();
        }
    }

    Process {
        id: verifyProcess
        command: ["fprintd-verify"]
        stdout: SplitParser {
            onRead: line => {
                var k = F.classifyVerifyLine(line);
                if (k === "match") {
                    root.busyMessage = "";
                    root.statusMessage = root.tr("status.match", "Match — fingerprint recognised.");
                    root.statusColor = Color.mPrimary;
                } else if (k === "no-match") {
                    root.busyMessage = "";
                    root.statusMessage = root.tr("status.no-match", "No match.");
                    root.statusColor = Color.mError;
                } else if (k === "retry") {
                    root.busyMessage = root.tr("status.verify-retry", "Try again — keep finger steady.");
                }
            }
        }
        onExited: { root.busyMessage = ""; }
    }

    // ---------- UI ----------

    Item {
        id: panelContainer
        anchors.fill: parent
        anchors.margins: Style.marginL

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                NIcon {
                    icon: "fingerprint"
                    pointSize: Style.fontSizeXXL
                    color: Color.mPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    NText {
                        text: root.tr("title", "Fingerprint Manager")
                        font.pointSize: Style.fontSizeL
                        font.weight: Style.fontWeightBold
                    }
                    NText {
                        text: root.tr("subtitle.summary", "{user} · {count}/{max} enrolled", {
                            user: Quickshell.env("USER") || "?",
                            count: root.enrolledFingers.length,
                            max: F.ALL_FINGERS.length
                        })
                        color: Color.mOnSurfaceVariant
                        font.pointSize: Style.fontSizeS
                    }
                }
                NIconButton {
                    icon: "refresh"
                    tooltipText: root.tr("action.refresh", "Refresh")
                    onClicked: root.refreshList()
                }
            }

            NDivider { Layout.fillWidth: true }

            // Empty / unavailable states
            Item {
                Layout.fillWidth: true
                visible: !root.fprintdInstalled || !root.fprintdAvailable
                Layout.preferredHeight: 80
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Style.marginS
                    NIcon { icon: "alert-triangle"; color: Color.mError; pointSize: Style.fontSizeXL; Layout.alignment: Qt.AlignHCenter }
                    NText {
                        text: !root.fprintdInstalled
                            ? root.tr("error.no-fprintd", "fprintd is not installed. See the plugin README for setup.")
                            : root.tr("error.no-device", "No fingerprint device found. Is fprintd running?")
                        color: Color.mError
                        wrapMode: Text.WordWrap
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: parent.width
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // Enrolled list
            NScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.fprintdInstalled && root.fprintdAvailable

                ColumnLayout {
                    width: parent.width
                    spacing: Style.marginXS

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        visible: root.enrolledFingers.length === 0
                        NText {
                            anchors.centerIn: parent
                            text: root.tr("empty", "No fingerprints enrolled yet.")
                            color: Color.mOnSurfaceVariant
                        }
                    }

                    Repeater {
                        model: root.enrolledFingers
                        delegate: FingerCard {
                            Layout.fillWidth: true
                            fingerName: modelData
                            label: root.fingerLabel(modelData)
                            iconName: F.iconOf(modelData)
                            deleteTooltip: root.tr("action.delete", "Delete")
                            onDeleteRequested: root.requestDeleteFinger(modelData)
                        }
                    }
                }
            }

            // Status / busy line
            NText {
                Layout.fillWidth: true
                visible: root.busyMessage !== "" || root.statusMessage !== ""
                text: root.busyMessage !== "" ? root.busyMessage : root.statusMessage
                color: root.busyMessage !== "" ? Color.mOnSurfaceVariant : root.statusColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            NDivider { Layout.fillWidth: true; visible: root.fprintdInstalled && root.fprintdAvailable }

            // Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                visible: root.fprintdInstalled && root.fprintdAvailable

                NButton {
                    icon: "plus"
                    text: root.tr("action.enroll", "Enroll finger")
                    enabled: root.enrolledFingers.length < F.ALL_FINGERS.length && root.busyMessage === ""
                    onClicked: fingerPickerPopup.open()
                }
                NButton {
                    icon: "fingerprint"
                    text: root.tr("action.test", "Test match")
                    enabled: root.enrolledFingers.length > 0 && root.busyMessage === ""
                    onClicked: {
                        root.statusMessage = "";
                        root.busyMessage = root.tr("status.verify-start", "Place finger on the sensor…");
                        verifyProcess.running = true;
                    }
                }
                Item { Layout.fillWidth: true }
                NButton {
                    icon: "trash"
                    text: root.tr("action.delete-all", "Delete all")
                    backgroundColor: Color.mError
                    textColor: Color.mOnError
                    enabled: root.enrolledFingers.length > 0 && root.busyMessage === ""
                    onClicked: confirmDeleteAll.open()
                }
            }
        }
    }

    // ---------- Enroll dialog ----------

    EnrollDialog {
        id: enrollDialog
        anchors.fill: parent
        pluginApi: root.pluginApi
        onFinished: (ok) => {
            if (ok) {
                root.statusMessage = root.tr("status.enrolled", "Enrollment successful.");
                root.statusColor = Color.mPrimary;
            } else {
                root.statusMessage = root.tr("status.enroll-failed", "Enrollment cancelled or failed.");
                root.statusColor = Color.mError;
            }
            root.refreshList();
        }
    }

    // ---------- Finger picker popup ----------

    Popup {
        id: fingerPickerPopup
        modal: true
        focus: true
        anchors.centerIn: parent
        padding: Style.marginM
        background: Rectangle {
            color: Color.mSurface
            radius: Style.radiusM
            border.color: Color.mOutline
            border.width: 1
        }

        ColumnLayout {
            spacing: Style.marginS
            NText {
                text: root.tr("picker.title", "Pick a finger to enroll")
                font.weight: Style.fontWeightBold
            }
            Repeater {
                model: F.availableForEnroll(root.enrolledFingers)
                delegate: NButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 240
                    icon: F.iconOf(modelData)
                    text: root.fingerLabel(modelData)
                    onClicked: {
                        fingerPickerPopup.close();
                        root.startEnroll(modelData);
                    }
                }
            }
        }
    }

    // ---------- Confirm delete-all ----------

    Popup {
        id: confirmDeleteAll
        modal: true
        focus: true
        anchors.centerIn: parent
        padding: Style.marginM
        background: Rectangle {
            color: Color.mSurface
            radius: Style.radiusM
            border.color: Color.mError
            border.width: 1
        }
        ColumnLayout {
            spacing: Style.marginM
            NText {
                text: root.tr("confirm.delete-all", "Delete ALL enrolled fingerprints?")
                font.weight: Style.fontWeightBold
                color: Color.mError
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                Item { Layout.fillWidth: true }
                NButton {
                    text: root.tr("action.cancel", "Cancel")
                    onClicked: confirmDeleteAll.close()
                }
                NButton {
                    text: root.tr("action.delete", "Delete")
                    backgroundColor: Color.mError
                    textColor: Color.mOnError
                    onClicked: { confirmDeleteAll.close(); root.deleteAll(); }
                }
            }
        }
    }

    // ---------- Confirm delete single finger ----------

    Popup {
        id: confirmDeleteFinger
        modal: true
        focus: true
        anchors.centerIn: parent
        padding: Style.marginM
        background: Rectangle {
            color: Color.mSurface
            radius: Style.radiusM
            border.color: Color.mError
            border.width: 1
        }
        onClosed: root.pendingDeleteFinger = ""
        ColumnLayout {
            spacing: Style.marginM
            NText {
                text: root.tr("confirm.delete-finger", "Delete the fingerprint for {finger}?", {
                    finger: root.pendingDeleteFinger ? root.fingerLabel(root.pendingDeleteFinger) : ""
                })
                font.weight: Style.fontWeightBold
                color: Color.mError
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                Item { Layout.fillWidth: true }
                NButton {
                    text: root.tr("action.cancel", "Cancel")
                    onClicked: confirmDeleteFinger.close()
                }
                NButton {
                    text: root.tr("action.delete", "Delete")
                    backgroundColor: Color.mError
                    textColor: Color.mOnError
                    onClicked: {
                        var f = root.pendingDeleteFinger;
                        confirmDeleteFinger.close();
                        if (f) root.deleteFinger(f);
                    }
                }
            }
        }
    }
}
