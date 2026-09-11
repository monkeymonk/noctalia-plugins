import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import "../lib/desktop.js" as Desktop
import "../lib/binds.js" as Binds
import "../lib/scripts.js" as Scripts
import "../Components"
import qs.Commons
import qs.Widgets

// Autostart: lists spawn-at-startup / spawn-sh-at-startup entries with
// add/edit/delete/enable-disable (via app picker or raw command).
ColumnLayout {
    id: root

    required property var panel
    required property var configModel

    property var entries: []        // [{ kind, cmd, node, path }]
    property string file: ""
    property string sectionFile: file
    property string baseIndent: "    "

    spacing: Style.marginM

    function serialize(kind, cmd) {
        var act = Desktop.commandToAction(cmd) || { name: "spawn", args: [cmd] };
        var name = (kind === "spawn-sh" || act.name === "spawn-sh") ? "spawn-sh-at-startup" : "spawn-at-startup";
        var args = (name === "spawn-sh-at-startup") ? [cmd] : act.args;
        return name + " " + args.map(function (a) { return Binds.quoteString(a); }).join(" ");
    }

    function recompute() {
        var out = [];
        if (configModel && configModel.loaded) {
            var ows = configModel.allOwners(["spawn-at-startup", "spawn-sh-at-startup"]);
            ows.forEach(function (o) {
                o.nodes.forEach(function (n) {
                    if (n.name !== "spawn-at-startup" && n.name !== "spawn-sh-at-startup") return;
                    out.push({
                        kind: n.name, node: n, path: o.path,
                        cmd: (n.args || []).map(function (a) { return String(a.value); }).join(" "),
                        disabled: !!n.slashdash
                    });
                });
            });
            file = ows.length ? ows[0].path : (configModel.configDir + "/cfg/autostart.kdl");
            if (out.length) baseIndent = Kdl.leadingIndent(configModel.textOf(out[0].path), out[0].node.range);
        }
        entries = out;
    }

    Component.onCompleted: recompute()
    Connections {
        target: root.configModel
        function onConfigChanged() { root.recompute(); }
    }

    function addEntry(cmd) {
        var src = configModel.textOf(file);
        var text = Kdl.appendNode(src, baseIndent + serialize("", cmd));
        panel.requestSave(file, text, panel.tr("autostart.summary-add", "autostart entry"));
    }
    function updateEntry(entry, cmd) {
        var src = configModel.textOf(entry.path);
        var indent = Kdl.leadingIndent(src, entry.node.range);
        var text = Kdl.replaceNodeLine(src, entry.node, indent + serialize(entry.kind === "spawn-sh-at-startup" ? "spawn-sh" : "", cmd));
        panel.requestSave(entry.path, text, panel.tr("autostart.summary-edit", "autostart entry"));
    }
    function deleteEntry(e) {
        var text = Kdl.removeNodeLine(configModel.textOf(e.path), e.node);
        panel.requestSave(e.path, text, panel.tr("autostart.summary-del", "delete entry"));
    }
    function toggleEntry(e) {
        var text = Kdl.setDisabled(configModel.textOf(e.path), e.node, !e.disabled);
        panel.requestSave(e.path, text, e.disabled ? panel.tr("autostart.summary-en", "enable entry")
                                                   : panel.tr("autostart.summary-dis", "disable entry"));
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NText { text: panel.tr("autostart.count", "{n} startup entries", { n: root.entries.length }); font.weight: Style.fontWeightBold }
        Item { Layout.fillWidth: true }
        NButton { icon: "plus"; text: panel.tr("autostart.add", "Add"); enabled: root.configModel && root.configModel.loaded; onClicked: cmdEditor.openCreate() }
    }
    NText {
        Layout.fillWidth: true
        text: panel.tr("autostart.hint", "Programs niri launches at startup. Pick an app or type a command.")
        color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeS; wrapMode: Text.WordWrap
    }

    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginXS
            NText { visible: root.entries.length === 0; text: panel.tr("autostart.none", "No startup entries."); color: Color.mOnSurfaceVariant }
            Repeater {
                model: root.entries
                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: aRow.implicitHeight + Style.marginS * 2
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    opacity: modelData.disabled ? 0.5 : 1.0
                    RowLayout {
                        id: aRow
                        anchors.fill: parent
                        anchors.margins: Style.marginS
                        spacing: Style.marginM
                        NIcon { icon: "player-play"; pointSize: Style.fontSizeL; color: Color.mPrimary }
                        NText { Layout.fillWidth: true; text: modelData.cmd; font.family: "monospace"; font.pointSize: Style.fontSizeS; elide: Text.ElideRight; font.strikeout: modelData.disabled }
                        NIconButton { icon: modelData.disabled ? "eye-off" : "eye"; tooltipText: modelData.disabled ? panel.tr("action.enable", "Enable") : panel.tr("action.disable", "Disable"); onClicked: root.toggleEntry(modelData) }
                        NIconButton { icon: "edit"; tooltipText: panel.tr("action.edit", "Edit"); onClicked: cmdEditor.openEdit(modelData) }
                        NIconButton { icon: "trash"; tooltipText: panel.tr("action.delete", "Delete"); onClicked: root.deleteEntry(modelData) }
                    }
                }
            }
        }
    }

    CommandEditor {
        id: cmdEditor
        translate: root.panel.tr
        scriptsDir: Scripts.scriptsDir(root.configModel.configDir)
        onAccepted: (entry, command) => {
            if (entry) root.updateEntry(entry, command);
            else root.addEntry(command);
        }
    }
}
