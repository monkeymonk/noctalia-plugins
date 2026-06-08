import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../lib/kdl.js" as Kdl
import "../lib/niri.js" as Niri
import "../lib/outputs.js" as Outputs
import "../lib/monique.js" as Monique
import "../Components"
import qs.Commons
import qs.Widgets

// Monitors editor. Merges live-detected outputs (`niri msg outputs`) with the
// `output {}` blocks already in your config, so you can edit/remove existing
// configs and add a config for a monitor that isn't currently connected
// (different setups). Live preview is non-destructive; saves are gated.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

    property var outputs: []         // live, from niri
    property var merged: []          // [{ name, detected, configured:{model,node,path} }]
    property string loadError: ""
    // path bar always shows the niri/noctalia default monitor file (cfg/display.kdl)
    property string sectionFile: (configModel && configModel.loaded) ? displayFile() : ""

    // optional monique CLI integration (monitor profiles)
    property bool moniqueAvailable: false
    property var profiles: []
    property string activeProfile: ""

    spacing: Style.marginM

    Component.onCompleted: { recompute(); outputsProcess.running = true; checkMonique.running = true; }
    // the Panel's global "reload config" button drives this — re-detect + profiles too
    Connections { target: root.configModel; function onLoadFinished() { root.recompute(); outputsProcess.running = true; root.refreshProfiles(); } }

    function switchProfile(name) { switchProcess.profileName = name; switchProcess.running = true; }
    function refreshProfiles() { if (moniqueAvailable) { listProfiles.running = true; currentProfile.running = true; } }

    Process {
        id: checkMonique
        command: Monique.checkCmd()
        onExited: (code) => { root.moniqueAvailable = (code === 0); if (root.moniqueAvailable) root.refreshProfiles(); }
    }
    Process {
        id: listProfiles
        command: Monique.listProfilesCmd()
        property string text: ""
        stdout: StdioCollector { onStreamFinished: listProfiles.text = this.text }
        onExited: { root.profiles = Monique.parseProfiles(listProfiles.text); }
    }
    Process {
        id: currentProfile
        command: Monique.currentProfileCmd()
        property string text: ""
        stdout: StdioCollector { onStreamFinished: currentProfile.text = this.text }
        onExited: (code) => { root.activeProfile = (code === 0) ? currentProfile.text.trim() : ""; }
    }
    Process {
        id: switchProcess
        property string profileName: ""
        command: Monique.switchProfileCmd(profileName)
        onExited: (code) => {
            if (code === 0) {
                root.activeProfile = switchProcess.profileName;
                root.configModel.load();      // monitors.kdl changed
                outputsProcess.running = true;
            }
        }
    }

    function refresh() { outputsProcess.running = true; recompute(); }

    function recompute() {
        var byName = {};
        outputs.forEach(function (o) { byName[o.name] = { name: o.name, detected: o, configured: null }; });
        if (configModel && configModel.loaded) {
            configModel.owners(["output"]).forEach(function (ow) {
                ow.nodes.forEach(function (n) {
                    if (n.name !== "output" || !n.args[0]) return;
                    var nm = String(n.args[0].value);
                    if (!byName[nm]) byName[nm] = { name: nm, detected: null, configured: null };
                    byName[nm].configured = { model: Outputs.parseOutput(n), node: n, path: ow.path };
                });
            });
        }
        merged = Object.keys(byName).map(function (k) { return byName[k]; });
    }

    // execDetached so Monique survives this panel closing on focus loss.
    function openMonique() { Quickshell.execDetached(["monique"]); }

    // Where the plugin writes monitor config when it manages monitors directly
    // (i.e. Monique isn't installed) — the noctalia default cfg/display.kdl.
    function displayFile() {
        if (!configModel) return "";
        for (var i = 0; i < configModel.files.length; i++)
            if (configModel.files[i].path.indexOf("cfg/display.kdl") !== -1) return configModel.files[i].path;
        return configModel.configDir + "/cfg/display.kdl";
    }

    function previewProp(name, prop, value) { previewProcess.command = Niri.outputCmd(name, prop, value); previewProcess.running = true; }

    function persist(model, configured) {
        var path, newText;
        if (configured) {
            var src = configModel.textOf(configured.path);
            var indent = Kdl.leadingIndent(src, configured.node.range);
            newText = Kdl.replaceNodeLine(src, configured.node, indent + Outputs.serializeOutput(model, "    "));
            path = configured.path;
        } else {
            path = displayFile();
            newText = Kdl.appendNode(configModel.textOf(path), Outputs.serializeOutput(model, "    "));
        }
        panel.requestSave(path, newText, panel.tr("monitors.summary", "monitor {n}", { n: model.name }));
    }
    function removeConfig(configured) {
        var text = Kdl.removeNodeLine(configModel.textOf(configured.path), configured.node);
        panel.requestSave(configured.path, text, panel.tr("monitors.remove-summary", "remove monitor config"));
    }
    function addConfig(name) {
        var path = displayFile();
        var text = Kdl.appendNode(configModel.textOf(path), 'output "' + name + '" {\n}');
        panel.requestSave(path, text, panel.tr("monitors.add-summary", "add monitor {n}", { n: name }));
    }

    Process {
        id: outputsProcess
        command: Niri.jsonCmd("outputs")
        property string text: ""
        stdout: StdioCollector { onStreamFinished: outputsProcess.text = this.text }
        stderr: StdioCollector {}
        onExited: (code) => {
            if (code === 0) { root.outputs = Niri.parseOutputs(outputsProcess.text); root.loadError = ""; root.recompute(); }
            else root.loadError = root.panel.tr("monitors.error", "Could not query niri outputs.");
        }
    }
    Process { id: previewProcess }

    // ---- header ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NText { text: panel.tr("monitors.count2", "{n} monitors", { n: root.merged.length }); font.weight: Style.fontWeightBold }
        Item { Layout.fillWidth: true }
        NButton { icon: "plus"; text: panel.tr("monitors.add", "Add config"); visible: !root.moniqueAvailable; enabled: root.configModel && root.configModel.loaded; onClicked: addDialog.open() }
    }
    NText {
        Layout.fillWidth: true
        visible: !root.moniqueAvailable
        text: panel.tr("monitors.hint2", "Preview applies live (reverts on reload). Save writes the output block; Add lets you configure a disconnected monitor for another setup.")
        color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeS; wrapMode: Text.WordWrap
    }
    NText { visible: root.loadError !== ""; text: root.loadError; color: Color.mError }

    // ---- cards ----
    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginM

            // ---- Monique profiles (only when the CLI is installed) ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.moniqueAvailable
                spacing: Style.marginXS
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    NText { Layout.fillWidth: true; text: panel.tr("monitors.profiles", "Profiles (Monique)"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
                    NButton { icon: "external-link"; text: panel.tr("monitors.open-monique", "New / edit"); outlined: true; onClicked: root.openMonique() }
                    NIconButton { icon: "refresh"; tooltipText: panel.tr("action.reload", "Refresh"); onClicked: root.refreshProfiles() }
                }
                NText {
                    visible: root.profiles.length === 0
                    text: panel.tr("monitors.no-profiles", "No profiles yet — use “New / edit” to create one in Monique.")
                    color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeS; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                Repeater {
                    model: root.profiles
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: pRow.implicitHeight + Style.marginS * 2
                        radius: Style.radiusM
                        color: modelData === root.activeProfile ? Color.mPrimary : Color.mSurfaceVariant
                        RowLayout {
                            id: pRow
                            anchors.fill: parent
                            anchors.margins: Style.marginS
                            spacing: Style.marginM
                            NIcon { icon: "device-desktop"; pointSize: Style.fontSizeL; color: modelData === root.activeProfile ? Color.mOnPrimary : Color.mPrimary }
                            NText { Layout.fillWidth: true; text: modelData; elide: Text.ElideRight; color: modelData === root.activeProfile ? Color.mOnPrimary : Color.mOnSurface; font.weight: modelData === root.activeProfile ? Style.fontWeightBold : Style.fontWeightRegular }
                            NIcon { visible: modelData === root.activeProfile; icon: "check"; pointSize: Style.fontSizeL; color: Color.mOnPrimary }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: modelData !== root.activeProfile
                            onClicked: root.switchProfile(modelData)
                        }
                    }
                }
                NText {
                    Layout.fillWidth: true
                    visible: root.profiles.length > 0
                    text: panel.tr("monitors.profiles-hint", "Monitors are managed by Monique — pick a profile to apply it, or use “New / edit” to create/update profiles.")
                    color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; wrapMode: Text.WordWrap
                }
            }

            // Per-monitor editing — only when Monique isn't managing monitors.
            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.moniqueAvailable
                spacing: Style.marginM
                NText {
                    visible: root.merged.length === 0
                    text: panel.tr("monitors.none", "No monitors.")
                    color: Color.mOnSurfaceVariant
                }
                Repeater {
                    model: root.moniqueAvailable ? [] : root.merged
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: mRow.implicitHeight + Style.marginS * 2
                        radius: Style.radiusM
                        color: Color.mSurfaceVariant
                        RowLayout {
                            id: mRow
                            anchors.fill: parent
                            anchors.margins: Style.marginS
                            spacing: Style.marginM
                            NIcon { icon: "device-desktop"; pointSize: Style.fontSizeL; color: modelData.detected ? Color.mPrimary : Color.mOnSurfaceVariant }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                NText { text: modelData.name + (modelData.configured ? "  ·  configured" : ""); font.weight: Style.fontWeightMedium; elide: Text.ElideRight; Layout.fillWidth: true }
                                NText {
                                    text: modelData.detected ? ((modelData.detected.make + " " + modelData.detected.model).trim() || panel.tr("monitors.connected", "connected")) : panel.tr("monitors.disconnected", "not connected")
                                    color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }
                            NIconButton { icon: "edit"; tooltipText: panel.tr("action.edit", "Edit"); onClicked: monitorEditor.openFor(modelData) }
                            NIconButton { icon: "trash"; visible: !!modelData.configured; tooltipText: panel.tr("monitors.remove", "Remove config"); onClicked: root.removeConfig(modelData.configured) }
                        }
                    }
                }
            }
        }
    }

    MonitorEditor {
        id: monitorEditor
        panel: root.panel
        onPreviewRequested: (name, s) => {
            root.previewProp(name, "mode", s.mode);
            root.previewProp(name, "scale", s.scale != null ? String(s.scale) : "");
            root.previewProp(name, "transform", s.transform);
            root.previewProp(name, "position", [s.x != null ? String(s.x) : "", s.y != null ? String(s.y) : ""]);
            root.previewProp(name, "vrr", s.vrr ? "on" : "off");
        }
        onAccepted: (model, configured) => root.persist(model, configured)
        onRemoveRequested: (configured) => root.removeConfig(configured)
    }

    // ---- add-config dialog ----
    Popup {
        id: addDialog
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 380; padding: Style.marginL
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }
        onOpened: addName.text = ""
        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM
            NText { text: panel.tr("monitors.add-title", "Add monitor config"); font.weight: Style.fontWeightBold; font.pointSize: Style.fontSizeL }
            NText {
                Layout.fillWidth: true
                text: panel.tr("monitors.add-hint", "Use the exact connector or model name (run `niri msg outputs`).")
                color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeS; wrapMode: Text.WordWrap
            }
            NTextInput { id: addName; Layout.fillWidth: true; placeholderText: 'DP-2 or "Maker Model …"' }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                NButton { text: panel.tr("action.cancel", "Cancel"); onClicked: addDialog.close() }
                NButton {
                    text: panel.tr("action.add-shortcut", "Add")
                    backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                    enabled: addName.text.trim() !== ""
                    onClicked: { var n = addName.text.trim(); addDialog.close(); root.addConfig(n); }
                }
            }
        }
    }
}
