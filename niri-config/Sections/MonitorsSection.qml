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

    required property var panel
    required property var configModel

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
    // Recompute on any in-memory change (staged edits included), but only
    // re-detect live outputs / monique profiles after a real disk reload —
    // the Panel's global "reload config" button drives that.
    Connections {
        target: root.configModel
        function onConfigChanged() { root.recompute(); }
        function onReloaded() { outputsProcess.running = true; root.refreshProfiles(); }
    }

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
                // monique rewrote the monitor file — reload through the panel so
                // staged edits in other sections aren't dropped without warning.
                root.panel.reloadConfig(root.panel.tr("reason.profile-switch", "monitor profile switch"));
                outputsProcess.running = true;
            }
        }
    }

    function refresh() { outputsProcess.running = true; }

    function recompute() {
        var byName = {};
        outputs.forEach(function (o) { byName[o.name] = { name: o.name, detected: o, configured: null }; });
        if (configModel && configModel.loaded) {
            configModel.allOwners(["output"]).forEach(function (ow) {
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
    // (i.e. Monique isn't installed): the noctalia default cfg/display.kdl when
    // the include graph actually loads it, else whichever loaded file already
    // owns `output` blocks, else the main config — which is always included.
    // Never a path outside the include graph: niri would ignore such a file
    // while `niri validate` still passes, so the setting would do nothing.
    function displayFile() {
        if (!configModel) return "";
        for (var i = 0; i < configModel.files.length; i++)
            if (configModel.files[i].path.indexOf("cfg/display.kdl") !== -1) return configModel.files[i].path;
        var ow = configModel.ownerOf("output");
        if (ow && ow.path) return ow.path;
        return configModel.mainPath;
    }

    // Live preview issues one `niri msg output` per property, and a single
    // Process runs one command at a time — so they drain through a queue.
    property var previewCmds: []
    property bool previewBusy: false

    // Starts a fresh preview run: a run still draining is dropped (newest
    // settings win), only its in-flight command is left to finish.
    function previewSettings(name, s) {
        previewCmds = [];
        // a command that never actually spawned would otherwise wedge the queue
        if (!previewProcess.running) previewBusy = false;
        previewProp(name, "mode", s.mode);
        previewProp(name, "scale", s.scale != null ? String(s.scale) : "");
        previewProp(name, "transform", s.transform);
        previewProp(name, "position", [s.x != null ? String(s.x) : "", s.y != null ? String(s.y) : ""]);
        previewProp(name, "vrr", s.vrr ? "on" : "off");
    }

    // outputCmd returns null when there is nothing to set (e.g. no position
    // configured at all) — a legitimate no-op, not an error.
    function previewProp(name, prop, value) {
        var cmd = Niri.outputCmd(name, prop, value);
        if (!cmd) return;
        previewCmds = previewCmds.concat([cmd]);
        previewNext();
    }

    function previewNext() {
        if (previewBusy || previewCmds.length === 0) return;
        previewBusy = true;
        previewProcess.command = previewCmds[0];
        previewCmds = previewCmds.slice(1);
        previewProcess.running = true;
    }

    function persist(target, model) {
        var path, newText;
        if (target) {
            var src = configModel.textOf(target.path);
            var indent = Kdl.leadingIndent(src, target.node.range);
            newText = Kdl.replaceNodeLine(src, target.node, indent + Outputs.serializeOutput(model, "    "));
            path = target.path;
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
            if (code === 0) { root.outputs = Niri.parseOutputs(outputsProcess.text); root.loadError = ""; }
            else root.loadError = root.panel.tr("monitors.error", "Could not query niri outputs.");
            root.recompute();
        }
    }
    Process {
        id: previewProcess
        stderr: StdioCollector {}
        onExited: (code) => {
            root.previewBusy = false;
            if (code !== 0) root.loadError = root.panel.tr("monitors.preview-error", "Preview failed — niri rejected a monitor change.");
            root.previewNext();
        }
    }

    // ---- header ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NText { text: panel.tr("monitors.count2", "{n} monitors", { n: root.merged.length }); font.weight: Style.fontWeightBold }
        Item { Layout.fillWidth: true }
        NButton { icon: "plus"; text: panel.tr("monitors.add", "Add config"); visible: !root.moniqueAvailable; enabled: root.configModel && root.configModel.loaded; onClicked: addDialog.openCreate() }
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
        translate: root.panel.tr
        onPreviewRequested: (name, s) => root.previewSettings(name, s)
        onAccepted: (target, model) => root.persist(target, model)
        onRemoveRequested: (configured) => root.removeConfig(configured)
    }

    MonitorAddDialog {
        id: addDialog
        translate: root.panel.tr
        onAccepted: (name) => root.addConfig(name)
    }
}
