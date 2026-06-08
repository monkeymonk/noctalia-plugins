import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../lib/kdl.js" as Kdl
import "../lib/niri.js" as Niri
import "../lib/binds.js" as Binds
import "../Components"
import qs.Commons
import qs.Widgets

// Workspaces: lists named-workspace declarations from config (add/rename/delete)
// alongside the live workspaces reported by niri.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

    property var named: []          // [{ name, node, path }]
    property var live: []           // from `niri msg workspaces`
    property string wsFile: ""
    property string sectionFile: wsFile
    property string baseIndent: "    "

    spacing: Style.marginM

    function recompute() {
        var out = [];
        if (configModel && configModel.loaded) {
            var ows = configModel.owners(["workspace"]);
            ows.forEach(function (o) {
                o.nodes.forEach(function (n) {
                    if (n.name !== "workspace" || !n.args[0]) return;
                    var oo = "";
                    (n.children || []).forEach(function (c) { if (c.name === "open-on-output" && c.args[0]) oo = String(c.args[0].value); });
                    out.push({ name: String(n.args[0].value), node: n, path: o.path, output: oo });
                });
            });
            wsFile = ows.length ? ows[0].path : (configModel.configDir + "/cfg/workspaces.kdl");
            if (out.length) baseIndent = Kdl.leadingIndent(configModel.textOf(out[0].path), out[0].node.range);
        }
        named = out;
    }

    Component.onCompleted: { recompute(); liveProcess.running = true; }
    Connections {
        target: root.configModel
        function onLoadFinished() { root.recompute(); }
    }

    Process {
        id: liveProcess
        command: Niri.jsonCmd("workspaces")
        property string text: ""
        stdout: StdioCollector { onStreamFinished: liveProcess.text = this.text }
        onExited: { root.live = Niri.parseWorkspaces(liveProcess.text); }
    }

    function wsText(name, output) {
        if (!output) return 'workspace "' + name + '"';
        return 'workspace "' + name + '" {\n    open-on-output "' + output + '"\n}';
    }
    function indented(block, indent) { return indent + block.split("\n").join("\n" + indent); }
    function addWorkspace(name, output) {
        var src = configModel.textOf(wsFile);
        var text = Kdl.appendNode(src, indented(wsText(name, output), baseIndent));
        panel.requestSave(wsFile, text, panel.tr("ws.summary-add", "workspace {n}", { n: name }));
    }
    function renameWorkspace(entry, name, output) {
        var src = configModel.textOf(entry.path);
        var indent = Kdl.leadingIndent(src, entry.node.range);
        var text = Kdl.replaceNodeLine(src, entry.node, indented(wsText(name, output), indent));
        panel.requestSave(entry.path, text, panel.tr("ws.summary-rename", "rename workspace"));
    }
    function deleteWorkspace(entry) {
        var text = Kdl.removeNodeLine(configModel.textOf(entry.path), entry.node);
        panel.requestSave(entry.path, text, panel.tr("ws.summary-del", "delete {n}", { n: entry.name }));
    }

    // ----- header -----
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NText { text: panel.tr("ws.count", "{n} named workspaces", { n: root.named.length }); font.weight: Style.fontWeightBold }
        Item { Layout.fillWidth: true }
        NButton {
            icon: "plus"
            text: panel.tr("ws.add", "Add")
            enabled: root.configModel && root.configModel.loaded
            onClicked: addDialog.openCreate()
        }
    }
    NText {
        Layout.fillWidth: true
        text: panel.tr("ws.hint", "Named workspaces are created in order; niri boots onto the first one.")
        color: Color.mOnSurfaceVariant
        font.pointSize: Style.fontSizeS
        wrapMode: Text.WordWrap
    }

    // ----- list -----
    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginXS

            NText {
                visible: root.named.length === 0
                text: panel.tr("ws.none", "No named workspaces declared.")
                color: Color.mOnSurfaceVariant
            }

            Repeater {
                model: root.named
                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: wsRow.implicitHeight + Style.marginS * 2
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    RowLayout {
                        id: wsRow
                        anchors.fill: parent
                        anchors.margins: Style.marginS
                        spacing: Style.marginM
                        NIcon { icon: "layout-grid"; pointSize: Style.fontSizeL; color: Color.mPrimary }
                        NText { Layout.fillWidth: true; text: modelData.name; font.weight: Style.fontWeightMedium }
                        // live indicator
                        NText {
                            visible: root.liveInfo(modelData.name) !== ""
                            text: root.liveInfo(modelData.name)
                            color: Color.mOnSurfaceVariant
                            font.pointSize: Style.fontSizeXS
                        }
                        NIconButton { icon: "edit"; tooltipText: panel.tr("action.edit", "Rename"); onClicked: addDialog.openRename(modelData) }
                        NIconButton { icon: "trash"; tooltipText: panel.tr("action.delete", "Delete"); onClicked: root.deleteWorkspace(modelData) }
                    }
                }
            }
        }
    }

    function liveInfo(name) {
        for (var i = 0; i < live.length; i++)
            if (live[i].name === name) return (live[i].output || "") + (live[i].active ? " · active" : "");
        return "";
    }

    // ----- add/rename dialog -----
    Item {
        id: addDialog
        property var entry: null
        function openCreate() { entry = null; nameField.text = ""; outputField.text = ""; pop.open(); }
        function openRename(e) { entry = e; nameField.text = e.name; outputField.text = e.output || ""; pop.open(); }
        Popup {
            id: pop
            modal: true; focus: true
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: 360; padding: Style.marginL
            background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }
            ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginM
                NText {
                    text: addDialog.entry ? panel.tr("ws.rename", "Rename workspace") : panel.tr("ws.new", "New workspace")
                    font.weight: Style.fontWeightBold; font.pointSize: Style.fontSizeL
                }
                NTextInput { id: nameField; Layout.fillWidth: true; label: panel.tr("ws.name", "Name"); placeholderText: panel.tr("ws.name-ph", "workspace name") }
                NTextInput { id: outputField; Layout.fillWidth: true; label: panel.tr("ws.output", "Open on output (optional)"); placeholderText: "DP-1" }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    NButton { text: panel.tr("action.cancel", "Cancel"); onClicked: pop.close() }
                    NButton {
                        text: panel.tr("action.save", "Save")
                        backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                        enabled: nameField.text.trim() !== ""
                        onClicked: {
                            var n = nameField.text.trim(), o = outputField.text.trim();
                            pop.close();
                            if (addDialog.entry) root.renameWorkspace(addDialog.entry, n, o);
                            else root.addWorkspace(n, o);
                        }
                    }
                }
            }
        }
    }
}
