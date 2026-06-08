import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import "../lib/rules.js" as Rules
import "../Components"
import qs.Commons
import qs.Widgets

// Window-rule editor: lists window-rule/layer-rule blocks; add (seeded by
// capturing a live window), edit, delete, enable/disable — surgical + gated.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

    property var ruleModels: []       // each: parseRule(node) + { path }
    property string rulesFile: ""
    property string sectionFile: rulesFile
    property string baseIndent: "    "

    spacing: Style.marginM

    function recompute() {
        var out = [];
        if (configModel && configModel.loaded) {
            var ows = configModel.owners(["window-rule", "layer-rule"]);
            ows.forEach(function (o) {
                o.nodes.forEach(function (n) {
                    if (n.name !== "window-rule" && n.name !== "layer-rule") return;
                    var r = Rules.parseRule(n, configModel.textOf(o.path));
                    r.path = o.path;
                    out.push(r);
                });
            });
            rulesFile = ows.length ? ows[0].path : (configModel.configDir + "/cfg/rules.kdl");
            if (out.length) baseIndent = Kdl.leadingIndent(configModel.textOf(out[0].path), out[0].node.range);
        }
        ruleModels = out;
    }

    Component.onCompleted: recompute()
    Connections {
        target: root.configModel
        function onLoadFinished() { root.recompute(); }
    }

    function shortPath(p) { return p ? p.replace(configModel.home, "~") : ""; }

    // ----- mutations -----
    function addRule(rule) {
        var src = configModel.textOf(rulesFile);
        var block = Rules.serializeRule(rule, "    ");
        if (baseIndent) block = baseIndent + block.split("\n").join("\n" + baseIndent);
        var text = Kdl.appendNode(src, block);
        panel.requestSave(rulesFile, text, panel.tr("rules.summary-add", "new window rule"));
    }
    function updateRule(rule) {
        var src = configModel.textOf(rule.path);
        var indent = Kdl.leadingIndent(src, rule.node.range);
        var block = Rules.serializeRule(rule, "    ");
        var text = Kdl.replaceNodeLine(src, rule.node, indent + block);
        panel.requestSave(rule.path, text, panel.tr("rules.summary-edit", "window rule"));
    }
    function deleteRule(r) {
        var text = Kdl.removeNodeLine(configModel.textOf(r.path), r.node);
        panel.requestSave(r.path, text, panel.tr("rules.summary-del", "delete rule"));
    }
    function toggleRule(r) {
        var text = Kdl.setDisabled(configModel.textOf(r.path), r.node, !r.disabled);
        panel.requestSave(r.path, text, r.disabled ? panel.tr("rules.summary-en", "enable rule")
                                                   : panel.tr("rules.summary-dis", "disable rule"));
    }

    // ----- header -----
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NText { text: panel.tr("rules.count", "{n} window rules", { n: root.ruleModels.length }); font.weight: Style.fontWeightBold }
        Item { Layout.fillWidth: true }
        NButton {
            icon: "plus"
            text: panel.tr("rules.add", "Add rule")
            enabled: root.configModel && root.configModel.loaded
            onClicked: ruleEditor.openCreate()
        }
    }
    NText {
        Layout.fillWidth: true
        text: panel.tr("rules.hint", "Add a rule by capturing a live window — its app-id/title pre-fill the match.")
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
                visible: root.ruleModels.length === 0
                text: panel.tr("rules.none", "No window rules yet.")
                color: Color.mOnSurfaceVariant
            }

            Repeater {
                model: root.ruleModels
                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: rRow.implicitHeight + Style.marginS * 2
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    opacity: modelData.disabled ? 0.5 : 1.0
                    RowLayout {
                        id: rRow
                        anchors.fill: parent
                        anchors.margins: Style.marginS
                        spacing: Style.marginM
                        NIcon { icon: modelData.kind === "layer-rule" ? "stack-2" : "app-window"; pointSize: Style.fontSizeL; color: Color.mPrimary }
                        NText {
                            Layout.fillWidth: true
                            text: Rules.describeRule(modelData)
                            elide: Text.ElideRight
                            font.strikeout: modelData.disabled
                        }
                        NIconButton {
                            icon: modelData.disabled ? "eye-off" : "eye"
                            tooltipText: modelData.disabled ? panel.tr("action.enable", "Enable") : panel.tr("action.disable", "Disable")
                            onClicked: root.toggleRule(modelData)
                        }
                        NIconButton {
                            icon: "edit"
                            tooltipText: panel.tr("action.edit", "Edit")
                            visible: modelData.kind === "window-rule"
                            onClicked: ruleEditor.openEdit(modelData)
                        }
                        NIconButton {
                            icon: "trash"
                            tooltipText: panel.tr("action.delete", "Delete")
                            onClicked: root.deleteRule(modelData)
                        }
                    }
                }
            }
        }
    }

    RuleEditor {
        id: ruleEditor
        panel: root.panel
        onAccepted: (node, rule) => {
            if (node) { rule.node = node; rule.path = root.findPath(node); root.updateRule(rule); }
            else root.addRule(rule);
        }
    }

    // map an edited node back to its file path
    function findPath(node) {
        for (var i = 0; i < ruleModels.length; i++) if (ruleModels[i].node === node) return ruleModels[i].path;
        return rulesFile;
    }
}
