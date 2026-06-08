import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "lib/niri.js" as Niri
import "Sections"
import "Components"
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    property real contentPreferredWidth: 760 * Style.uiScaleRatio
    property real contentPreferredHeight: 620 * Style.uiScaleRatio

    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
    readonly property string externalEditor: cfg.externalEditor ?? defaults.externalEditor ?? ""

    // niri wiki doc page per section (opened via the header help button)
    readonly property var docUrls: ({
        "shortcuts": "https://github.com/YaLTeR/niri/wiki/Configuration:-Key-Bindings",
        "monitors": "https://github.com/YaLTeR/niri/wiki/Configuration:-Outputs",
        "input": "https://github.com/YaLTeR/niri/wiki/Configuration:-Input",
        "workspaces": "https://github.com/YaLTeR/niri/wiki/Configuration:-Workspaces",
        "rules": "https://github.com/YaLTeR/niri/wiki/Configuration:-Window-Rules",
        "layout": "https://github.com/YaLTeR/niri/wiki/Configuration:-Layout",
        "animation": "https://github.com/YaLTeR/niri/wiki/Configuration:-Animations",
        "autostart": "https://github.com/YaLTeR/niri/wiki/Configuration:-Miscellaneous",
        "scripts": "https://github.com/YaLTeR/niri/wiki/Configuration:-Key-Bindings",
        "misc": "https://github.com/YaLTeR/niri/wiki/Configuration:-Miscellaneous"
    })

    function openDoc() {
        var url = docUrls[currentSection];
        if (url) Quickshell.execDetached(["xdg-open", url]);
    }

    // Open the config for editing. With an explicit editor command set, run it on
    // the file (e.g. "ghostty -e nvim"); otherwise reveal the file's folder in the
    // file manager. execDetached so it survives this panel closing on focus loss
    // (a plain Process is killed when its QML owner is destroyed).
    function openInEditor(path) {
        if (root.externalEditor && root.externalEditor.length > 0) {
            Quickshell.execDetached(["sh", "-c", root.externalEditor + ' "$1"', "_", path]);
        } else {
            var p = String(path).replace(/\/+$/, "");
            var dir = p.lastIndexOf("/") > 0 ? p.substring(0, p.lastIndexOf("/")) : cfgModel.configDir;
            Quickshell.execDetached(["xdg-open", dir]);
        }
    }

    property string currentSection: "shortcuts"
    property string statusMessage: ""
    property color statusColor: Color.mOnSurfaceVariant
    property bool busy: false

    // file the current section edits (each section exposes `sectionFile`)
    readonly property string currentFile: (sectionLoader.item && sectionLoader.item.sectionFile)
        ? sectionLoader.item.sectionFile : ""

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

    // Notifies sections (e.g. Scripts) when a non-config file write completes.
    signal fileSaved(string path)

    property var appliedPaths: []      // last-applied files (for Undo)
    property bool canUndo: false

    // Sections request a save here. Config edits are STAGED (shown live in the UI,
    // written to disk only when you press Apply). Raw files (scripts) write now.
    function requestSave(path, newText, summary, opts) {
        if (opts && opts.raw) {
            doRawSave(path, newText, summary, opts);
        } else {
            cfgModel.stage(path, newText);
            root.statusMessage = root.tr("status.staged", "{what} staged — press Apply to write it.", { what: summary || "Change" });
            root.statusColor = Color.mOnSurfaceVariant;
        }
    }

    function doRawSave(path, newText, summary, opts) {
        root.busy = true;
        saveProcess._path = path;
        saveProcess._summary = summary || "";
        saveProcess.command = Niri.writeFileCmd(path, Qt.btoa(newText), !!(opts && opts.executable));
        saveProcess.running = true;
    }

    // Write all staged files atomically: .bak + write + niri validate + reload,
    // restoring every .bak if validation fails.
    function applyChanges() {
        var list = cfgModel.stagedList();
        if (!list.length) return;
        root.busy = true;
        root.statusMessage = root.tr("status.applying", "Applying {n} change(s)…", { n: list.length });
        root.statusColor = Color.mOnSurfaceVariant;
        root.appliedPaths = list.map(function (x) { return x.path; });
        var pairs = list.map(function (x) { return { path: x.path, b64: Qt.btoa(x.text) }; });
        applyProcess.command = Niri.applyCmd(cfgModel.mainPath, pairs);
        applyProcess.running = true;
    }

    function undoLast() {
        if (!root.appliedPaths.length) return;
        root.busy = true;
        undoProcess.command = Niri.undoCmd(root.appliedPaths);
        undoProcess.running = true;
    }

    // Delete a plugin-managed file (e.g. a script). Bypasses the validate gate.
    function deleteFile(path, summary) {
        root.busy = true;
        saveProcess._path = path;
        saveProcess._summary = summary || "";
        saveProcess._raw = true;
        saveProcess.command = Niri.deleteFileCmd(path);
        saveProcess.running = true;
    }

    Component.onCompleted: cfgModel.load()

    ConfigModel {
        id: cfgModel
        pluginApi: root.pluginApi
        onLoadFinished: {
            if (error) { root.statusMessage = error; root.statusColor = Color.mError; }
        }
    }

    // Raw file writes (scripts / delete) — immediate, no niri validate.
    Process {
        id: saveProcess
        property string _path: ""
        property string _summary: ""
        property string outText: ""
        stdout: StdioCollector { onStreamFinished: saveProcess.outText = this.text }
        onExited: (code) => {
            root.busy = false;
            if (saveProcess.outText.indexOf("OK") !== -1) {
                root.statusMessage = root.tr("status.saved-file", "Saved {what}.", { what: saveProcess._summary });
                root.statusColor = Color.mPrimary;
                root.fileSaved(saveProcess._path);
            } else {
                root.statusMessage = root.tr("status.write-failed", "Write failed: {what}.", { what: saveProcess._summary });
                root.statusColor = Color.mError;
            }
        }
    }

    // Apply staged config changes (validated + backed up).
    Process {
        id: applyProcess
        property string outText: ""
        property string errText: ""
        stdout: StdioCollector { onStreamFinished: applyProcess.outText = this.text }
        stderr: StdioCollector { onStreamFinished: applyProcess.errText = this.text }
        onExited: (code) => {
            root.busy = false;
            if (applyProcess.outText.indexOf("OK") !== -1) {
                root.statusMessage = root.tr("status.applied", "Applied — niri reloaded.");
                root.statusColor = Color.mPrimary;
                root.canUndo = true;
                cfgModel.load();   // re-read from disk, clears staged
            } else {
                var detail = (applyProcess.errText || "").trim();
                root.statusMessage = root.tr("status.apply-failed", "Rejected by niri validate — restored from backup. Fix and re-apply.")
                                     + (detail ? ("\n" + detail) : "");
                root.statusColor = Color.mError;   // staged changes kept so you can fix
            }
        }
    }

    Process {
        id: undoProcess
        property string outText: ""
        stdout: StdioCollector { onStreamFinished: undoProcess.outText = this.text }
        onExited: (code) => {
            root.busy = false;
            root.canUndo = false;
            root.statusMessage = root.tr("status.undone", "Reverted to the previous config.");
            root.statusColor = Color.mPrimary;
            cfgModel.load();
        }
    }

    readonly property var sections: [
        { key: "shortcuts", icon: "keyboard", label: root.tr("section.shortcuts", "Shortcuts") },
        { key: "monitors", icon: "device-desktop", label: root.tr("section.monitors", "Monitors") },
        { key: "input", icon: "mouse", label: root.tr("section.input", "Input") },
        { key: "workspaces", icon: "layout-grid", label: root.tr("section.workspaces", "Workspaces") },
        { key: "rules", icon: "app-window", label: root.tr("section.rules", "Window rules") },
        { key: "layout", icon: "layout", label: root.tr("section.layout", "Layout") },
        { key: "animation", icon: "movie", label: root.tr("section.animation", "Animation") },
        { key: "autostart", icon: "player-play", label: root.tr("section.autostart", "Autostart") },
        { key: "misc", icon: "settings", label: root.tr("section.misc", "Misc") },
        { key: "scripts", icon: "file-code", label: root.tr("section.scripts", "Scripts") }
    ]

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
                NIcon { icon: "device-desktop-cog"; pointSize: Style.fontSizeXXL; color: Color.mPrimary }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    NText {
                        text: root.tr("title", "Niri Config")
                        font.pointSize: Style.fontSizeL
                        font.weight: Style.fontWeightBold
                    }
                    NText {
                        text: !cfgModel.niriInstalled ? root.tr("error.no-niri", "niri not found on PATH")
                            : (cfgModel.pendingCount > 0
                                ? root.tr("subtitle.pending", "{n} unsaved change(s) — press Apply", { n: cfgModel.pendingCount })
                                : root.tr("subtitle.clean", "All changes applied · validated & backed up"))
                        color: cfgModel.pendingCount > 0 ? Color.mPrimary : Color.mOnSurfaceVariant
                        font.pointSize: Style.fontSizeS
                    }
                }
                NButton {
                    text: root.tr("action.apply", "Apply") + (cfgModel.pendingCount > 0 ? " (" + cfgModel.pendingCount + ")" : "")
                    backgroundColor: Color.mPrimary
                    textColor: Color.mOnPrimary
                    enabled: cfgModel.pendingCount > 0 && cfgModel.niriInstalled && !root.busy
                    onClicked: root.applyChanges()
                }
                NButton {
                    text: root.tr("action.undo", "Undo")
                    outlined: true
                    visible: root.canUndo && cfgModel.pendingCount === 0
                    enabled: !root.busy
                    onClicked: root.undoLast()
                }
                NIconButton {
                    icon: "help-circle"
                    tooltipText: root.tr("action.docs", "Open niri docs for this section")
                    visible: root.docUrls[root.currentSection] !== undefined
                    onClicked: root.openDoc()
                }
                NIconButton {
                    icon: "refresh"
                    tooltipText: root.tr("action.reload", "Reload / discard staged changes")
                    onClicked: cfgModel.discardStaged()
                }
            }

            NDivider { Layout.fillWidth: true }

            // Per-section file path + direct-edit escape hatch
            RowLayout {
                Layout.fillWidth: true
                visible: root.currentFile !== ""
                spacing: Style.marginS
                NIcon { icon: "file"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
                NText {
                    Layout.fillWidth: true
                    text: root.currentFile.replace(cfgModel.home, "~")
                    font.family: "monospace"
                    font.pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                    elide: Text.ElideMiddle
                }
                NButton {
                    text: root.externalEditor ? root.tr("action.edit-file", "Edit file") : root.tr("action.open-folder", "Open folder")
                    icon: root.externalEditor ? "external-link" : "folder"
                    outlined: true
                    fontSize: Style.fontSizeXS
                    onClicked: root.openInEditor(root.currentFile)
                }
            }

            // Body: nav rail + section host
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Style.marginM

                // Left nav
                NScrollView {
                    Layout.preferredWidth: 180 * Style.uiScaleRatio
                    Layout.fillHeight: true
                    ColumnLayout {
                        width: parent.width
                        spacing: Style.marginXS
                        Repeater {
                            model: root.sections
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: navRow.implicitHeight + Style.marginS * 2
                                radius: Style.radiusM
                                color: root.currentSection === modelData.key ? Color.mPrimary : "transparent"
                                RowLayout {
                                    id: navRow
                                    anchors.fill: parent
                                    anchors.margins: Style.marginS
                                    spacing: Style.marginS
                                    NIcon {
                                        icon: modelData.icon
                                        pointSize: Style.fontSizeL
                                        color: root.currentSection === modelData.key ? Color.mOnPrimary : Color.mOnSurface
                                    }
                                    NText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: root.currentSection === modelData.key ? Color.mOnPrimary : Color.mOnSurface
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentSection = modelData.key
                                }
                            }
                        }
                    }
                }

                NDivider { Layout.fillHeight: true; vertical: true }

                // Section host
                Loader {
                    id: sectionLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: {
                        switch (root.currentSection) {
                        case "shortcuts": return shortcutsComp;
                        case "monitors": return monitorsComp;
                        case "rules": return rulesComp;
                        case "workspaces": return workspacesComp;
                        case "autostart": return autostartComp;
                        case "scripts": return scriptsComp;
                        case "input": return inputComp;
                        case "layout": return layoutComp;
                        case "animation": return animationComp;
                        case "misc": return miscComp;
                        default: return rawComp;
                        }
                    }
                }
                Component { id: shortcutsComp; ShortcutsSection { panel: root; configModel: cfgModel } }
                Component { id: monitorsComp; MonitorsSection { panel: root; configModel: cfgModel } }
                Component { id: rulesComp; RulesSection { panel: root; configModel: cfgModel } }
                Component { id: workspacesComp; WorkspacesSection { panel: root; configModel: cfgModel } }
                Component { id: autostartComp; AutostartSection { panel: root; configModel: cfgModel } }
                Component { id: scriptsComp; ScriptsSection { panel: root; configModel: cfgModel } }
                Component { id: inputComp; InputSection { panel: root; configModel: cfgModel } }
                Component { id: layoutComp; LayoutSection { panel: root; configModel: cfgModel } }
                Component { id: animationComp; AnimationSection { panel: root; configModel: cfgModel } }
                Component { id: miscComp; MiscSection { panel: root; configModel: cfgModel } }
                Component { id: rawComp; RawSection { panel: root; configModel: cfgModel; sectionKey: root.currentSection } }
            }

            // Status line
            NText {
                Layout.fillWidth: true
                visible: root.statusMessage !== ""
                text: root.statusMessage
                color: root.statusColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

}
