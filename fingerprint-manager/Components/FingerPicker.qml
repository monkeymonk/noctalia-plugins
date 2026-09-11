import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../fprintUtils.js" as F
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property var enrolledFingers: []

    signal picked(string name)

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

    function open() {
        popup.open();
    }

    function close() {
        popup.close();
    }

    Popup {
        id: popup
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
                        popup.close();
                        root.picked(modelData);
                    }
                }
            }
        }
    }
}
