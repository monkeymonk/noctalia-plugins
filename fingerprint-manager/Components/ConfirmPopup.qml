import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property string titleText: ""
    property string confirmText: ""
    // Carried through to confirmed() so the caller does not need a closure.
    property string payload: ""

    signal confirmed(string payload)

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
            border.color: Color.mError
            border.width: 1
        }

        ColumnLayout {
            spacing: Style.marginM
            NText {
                text: root.titleText
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
                    onClicked: popup.close()
                }
                NButton {
                    text: root.confirmText
                    backgroundColor: Color.mError
                    textColor: Color.mOnError
                    onClicked: {
                        var p = root.payload;
                        popup.close();
                        root.confirmed(p);
                    }
                }
            }
        }
    }
}
