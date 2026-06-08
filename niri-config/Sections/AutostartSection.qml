import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import "../lib/desktop.js" as Desktop
import "../lib/binds.js" as Binds
import "../Components"
import qs.Commons
import qs.Widgets

// Autostart: lists spawn-at-startup / spawn-sh-at-startup entries with
// add/edit/delete/enable-disable (via app picker or raw command).
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

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
            var ows = configModel.owners(["spawn-at-startup", "spawn-sh-at-startup"]);
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
        function onLoadFinished() { root.recompute(); }
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
        NButton { icon: "plus"; text: panel.tr("autostart.add", "Add"); enabled: root.configModel && root.configModel.loaded; onClicked: cmdDialog.openCreate() }
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
                        NIconButton { icon: "edit"; tooltipText: panel.tr("action.edit", "Edit"); onClicked: cmdDialog.openEdit(modelData) }
                        NIconButton { icon: "trash"; tooltipText: panel.tr("action.delete", "Delete"); onClicked: root.deleteEntry(modelData) }
                    }
                }
            }
        }
    }

    AppPicker {
        id: appPicker
        panel: root.panel
        onPicked: (cmd) => cmdField.text = cmd
    }

    Item {
        id: cmdDialog
        property var entry: null
        function openCreate() { entry = null; cmdField.text = ""; pop.open(); }
        function openEdit(e) { entry = e; cmdField.text = e.cmd; pop.open(); }
        Popup {
            id: pop
            modal: true; focus: true
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: 460; padding: Style.marginL
            background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }
            ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginM
                NText { text: cmdDialog.entry ? panel.tr("autostart.editt", "Edit startup entry") : panel.tr("autostart.newt", "New startup entry"); font.weight: Style.fontWeightBold; font.pointSize: Style.fontSizeL }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    NTextInput { id: cmdField; Layout.fillWidth: true; placeholderText: panel.tr("autostart.cmd-ph", "command to run") }
                    NButton { text: panel.tr("bindeditor.pick-app", "Pick app"); onClicked: appPicker.open() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    NButton { text: panel.tr("action.cancel", "Cancel"); onClicked: pop.close() }
                    NButton {
                        text: panel.tr("action.save", "Save")
                        backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                        enabled: cmdField.text.trim() !== ""
                        onClicked: {
                            var c = cmdField.text.trim(); pop.close();
                            if (cmdDialog.entry) root.updateEntry(cmdDialog.entry, c);
                            else root.addEntry(c);
                        }
                    }
                }
            }
        }
    }
}
