import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/outputs.js" as Outputs
import qs.Commons
import qs.Widgets

// Modal editor for one monitor. Emits previewRequested(name, settings),
// accepted(model, configured) and removeRequested(configured).
Item {
    id: root

    property var panel: null

    property string name: ""
    property var det: null            // detected (live) info or null
    property var cfg: null            // { model, node, path } or null
    property var modes: []

    property string edMode: ""
    property string edScale: "1"
    property string edTransform: "Normal"
    property string edX: "0"
    property string edY: "0"
    property bool edVrr: false
    property bool edVrrOnDemand: false
    property bool edOff: false
    property bool edFocusStartup: false
    property string edBackdrop: ""

    signal previewRequested(string name, var settings)
    signal accepted(var model, var configured)
    signal removeRequested(var configured)

    function tr(k, f) { return panel ? panel.tr(k, f) : f; }

    function openFor(m) {
        name = m.name; det = m.detected || null; cfg = m.configured || null;
        modes = det ? det.modes : [];
        var cm = cfg ? cfg.model : null;
        edMode = (cm && cm.mode) || (det ? det.currentModeLabel : "");
        edScale = (cm && cm.scale != null) ? String(cm.scale) : (det ? String(det.scale) : "1");
        edTransform = (cm && cm.transform) || (det ? det.transform : "Normal");
        edX = (cm && cm.x != null) ? String(cm.x) : (det ? String(det.x) : "0");
        edY = (cm && cm.y != null) ? String(cm.y) : (det ? String(det.y) : "0");
        edVrr = cm ? cm.vrr : (det ? det.vrrEnabled : false);
        edVrrOnDemand = cm ? cm.vrrOnDemand : false;
        edOff = cm ? cm.off : false;
        edFocusStartup = cm ? cm.focusAtStartup : false;
        edBackdrop = cm ? cm.backdropColor : "";
        popup.open();
    }

    function buildModel() {
        return {
            name: name, off: edOff, mode: edMode,
            scale: (edScale === "" || isNaN(parseFloat(edScale))) ? null : parseFloat(edScale),
            x: (edX === "" || isNaN(parseInt(edX))) ? null : parseInt(edX),
            y: (edY === "" || isNaN(parseInt(edY))) ? null : parseInt(edY),
            transform: edTransform, vrr: edVrr, vrrOnDemand: edVrrOnDemand,
            focusAtStartup: edFocusStartup, backdropColor: edBackdrop
        };
    }

    visible: false

    Popup {
        id: popup
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - Style.marginXL : 540, 540)
        padding: Style.marginL
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            NText { text: root.name; font.pointSize: Style.fontSizeL; font.weight: Style.fontWeightBold }
            NText {
                text: root.det ? ((root.det.make + " " + root.det.model).trim() || root.tr("monitors.connected", "connected"))
                               : root.tr("monitors.disconnected", "not connected")
                color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS
            }

            NComboBox {
                visible: root.modes.length > 0
                Layout.fillWidth: true
                label: root.tr("monitors.mode", "Resolution & refresh")
                model: root.modes.map(function (m) { return { key: m.label, name: m.label + (m.preferred ? "  ★" : "") }; })
                currentKey: root.edMode
                onSelected: key => root.edMode = key
            }
            NTextInput {
                visible: root.modes.length === 0
                Layout.fillWidth: true
                label: root.tr("monitors.mode", "Resolution & refresh")
                text: root.edMode; placeholderText: "1920x1080@60.000"; onTextChanged: root.edMode = text
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: root.tr("monitors.scale", "Scale"); text: root.edScale; placeholderText: "1.0"; onTextChanged: root.edScale = text }
                NComboBox {
                    Layout.fillWidth: true
                    label: root.tr("monitors.transform", "Transform")
                    model: Outputs.TRANSFORMS.map(function (t) { return { key: t, name: t }; })
                    currentKey: root.edTransform; onSelected: key => root.edTransform = key
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: root.tr("monitors.posx", "Position X"); text: root.edX; placeholderText: "0"; onTextChanged: root.edX = text }
                NTextInput { Layout.fillWidth: true; label: root.tr("monitors.posy", "Position Y"); text: root.edY; placeholderText: "0"; onTextChanged: root.edY = text }
            }
            NToggle { Layout.fillWidth: true; visible: !root.det || root.det.vrrSupported; label: root.tr("monitors.vrr", "Variable refresh rate (VRR)"); checked: root.edVrr; onToggled: v => root.edVrr = v }
            NToggle { Layout.fillWidth: true; visible: root.edVrr && (!root.det || root.det.vrrSupported); label: root.tr("monitors.vrr-ondemand", "VRR on-demand only"); checked: root.edVrrOnDemand; onToggled: v => root.edVrrOnDemand = v }
            NTextInput { Layout.fillWidth: true; label: root.tr("monitors.backdrop", "Backdrop color"); text: root.edBackdrop; placeholderText: "#000000"; onTextChanged: root.edBackdrop = text }
            NToggle { Layout.fillWidth: true; label: root.tr("monitors.focus-startup", "Focus at startup"); checked: root.edFocusStartup; onToggled: v => root.edFocusStartup = v }
            NToggle { Layout.fillWidth: true; label: root.tr("monitors.off", "Disable this output (off)"); checked: root.edOff; onToggled: v => root.edOff = v }

            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NButton {
                    text: root.tr("monitors.preview", "Preview live")
                    outlined: true
                    visible: !!root.det
                    onClicked: root.previewRequested(root.name, root.buildModel())
                }
                Item { Layout.fillWidth: true }
                NButton {
                    text: root.tr("monitors.remove", "Remove config")
                    visible: !!root.cfg
                    backgroundColor: Color.mError; textColor: Color.mOnError
                    onClicked: { var c = root.cfg; popup.close(); root.removeRequested(c); }
                }
                NButton {
                    text: root.tr("action.save", "Save")
                    backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                    onClicked: { var m = root.buildModel(), c = root.cfg; popup.close(); root.accepted(m, c); }
                }
            }
        }
    }
}
