import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "lib/config.js" as Cfg
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
            var dir = Cfg.dirname(p) || cfgModel.configDir;
            Quickshell.execDetached(["xdg-open", dir]);
        }
    }

    property string currentSection: "shortcuts"
    property string statusMessage: ""
    property color statusColor: Color.mOnSurfaceVariant
    readonly property bool busy: saveCtl.busy
    readonly property bool canUndo: saveCtl.canUndo

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

    // Notifies sections (e.g. Scripts) when a raw (unvalidated) file write or
    // delete completed. Only ScriptsSection produces and consumes these.
    signal rawFileChanged(string path)

    function setStatus(message, level) {
        root.statusMessage = message;
        root.statusColor = level === "ok" ? Color.mPrimary
                         : level === "error" ? Color.mError
                         : Color.mOnSurfaceVariant;
    }

    // ---------- write pipeline (owned by SaveController) ----------

    // Stage a config edit — shown live in the UI, written on Apply.
    function requestSave(path, newText, summary) { saveCtl.requestSave(path, newText, summary); }

    // Write a non-config file (script) to disk now: unvalidated, not undoable.
    function writeFileNow(path, newText, summary, opts) { saveCtl.writeFileNow(path, newText, summary, opts); }

    function applyChanges() { saveCtl.applyChanges(); }
    function undoLast() { saveCtl.undoLast(); }
    function deleteFile(path, summary) { saveCtl.deleteFile(path, summary); }

    // Explicit user gesture: drop any staged edits and re-read from disk.
    // `reason` is an already-translated string.
    function discardAndReload(reason) {
        cfgModel.discardStaged();
        root.setStatus(root.tr("status.reloaded", "Reloaded from disk — {why}.", { why: reason }), "info");
    }

    // Programmatic reload (a section reloading as a side effect). Refuses while
    // edits are staged so it can never silently discard another section's work.
    function reloadConfig(reason) {
        if (cfgModel.pendingCount > 0) {
            root.setStatus(root.tr("status.reload-blocked",
                "Reload skipped — {n} staged change(s) would be lost. Apply them first.",
                { n: cfgModel.pendingCount }), "error");
            return;
        }
        root.discardAndReload(reason);
    }

    Component.onCompleted: cfgModel.load()

    ConfigModel {
        id: cfgModel
        pluginApi: root.pluginApi
        onReloaded: {
            if (error) root.setStatus(error, "error");
        }
    }

    SaveController {
        id: saveCtl
        pluginApi: root.pluginApi
        configModel: cfgModel
        onStatusReport: (message, level) => root.setStatus(message, level)
        onRawFileChanged: (path) => root.rawFileChanged(path)
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
                    onClicked: root.discardAndReload(root.tr("reason.refresh", "manual refresh"))
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
