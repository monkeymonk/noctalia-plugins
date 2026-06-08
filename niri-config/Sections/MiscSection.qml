import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import qs.Commons
import qs.Widgets

// Miscellaneous editor: prefer-no-csd, screenshot-path, cursor, hotkey-overlay,
// clipboard, overview. The environment block (and anything else) is left to the
// "Edit file" button. Surgical batched save over the owning file's top-level
// nodes / blocks.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

    property string miscFile: ""
    property string sectionFile: miscFile
    property var orig: ({})

    property bool preferNoCsd: false
    property string screenshotPath: ""
    property string cursorTheme: ""
    property string cursorSize: ""
    property bool cursorHideTyping: false
    property string cursorHideMs: ""
    property bool hkSkipStartup: false
    property bool hkHideNotBound: false
    property bool clipDisablePrimary: false
    property string overviewZoom: ""
    property string overviewBackdrop: ""

    spacing: Style.marginM

    function childNamed(node, name) {
        var k = node && node.children ? node.children : [];
        for (var i = 0; i < k.length; i++) if (k[i].name === name) return k[i];
        return null;
    }
    function topNode(text, name) {
        var d = Kdl.parse(text);
        for (var i = 0; i < d.nodes.length; i++) if (d.nodes[i].name === name) return d.nodes[i];
        return null;
    }
    function ensureTop(text, name) { return topNode(text, name) ? text : Kdl.appendNode(text, name + " {\n}"); }
    function topFlag(text, name) { return !!topNode(text, name); }
    function topStr(text, name) { var n = topNode(text, name); return (n && n.args[0]) ? String(n.args[0].value) : ""; }
    function blkFlag(text, blk, name) { var b = topNode(text, blk); return b ? !!childNamed(b, name) : false; }
    function blkStr(text, blk, name) { var b = topNode(text, blk); var c = b ? childNamed(b, name) : null; return (c && c.args[0]) ? String(c.args[0].value) : ""; }

    function recompute() {
        if (!(configModel && configModel.loaded)) return;
        var ow = configModel.owners(["prefer-no-csd", "screenshot-path", "cursor", "hotkey-overlay", "clipboard", "overview", "environment"]);
        miscFile = ow.length ? ow[0].path : (configModel.configDir + "/cfg/misc.kdl");
        var t = configModel.textOf(miscFile);
        preferNoCsd = topFlag(t, "prefer-no-csd");
        var sp = topNode(t, "screenshot-path");
        screenshotPath = sp ? (sp.args[0] ? (sp.args[0].value === null ? "null" : String(sp.args[0].value)) : "") : "";
        cursorTheme = blkStr(t, "cursor", "xcursor-theme");
        cursorSize = blkStr(t, "cursor", "xcursor-size");
        cursorHideTyping = blkFlag(t, "cursor", "hide-when-typing");
        cursorHideMs = blkStr(t, "cursor", "hide-after-inactive-ms");
        hkSkipStartup = blkFlag(t, "hotkey-overlay", "skip-at-startup");
        hkHideNotBound = blkFlag(t, "hotkey-overlay", "hide-not-bound");
        clipDisablePrimary = blkFlag(t, "clipboard", "disable-primary");
        overviewZoom = blkStr(t, "overview", "zoom");
        overviewBackdrop = blkStr(t, "overview", "backdrop-color");
        orig = snapshot();
    }
    function snapshot() {
        return { preferNoCsd: preferNoCsd, screenshotPath: screenshotPath, cursorTheme: cursorTheme, cursorSize: cursorSize,
                 cursorHideTyping: cursorHideTyping, cursorHideMs: cursorHideMs, hkSkipStartup: hkSkipStartup, hkHideNotBound: hkHideNotBound,
                 clipDisablePrimary: clipDisablePrimary, overviewZoom: overviewZoom, overviewBackdrop: overviewBackdrop };
    }

    Component.onCompleted: recompute()
    Connections { target: root.configModel; function onLoadFinished() { root.recompute(); } }

    readonly property bool dirty: {
        if (!orig) return false;
        var s = snapshot();
        for (var k in s) if (s[k] !== orig[k]) return true;
        return false;
    }

    // ---- setters ----
    function setTopFlag(text, name, on) {
        var ex = topNode(text, name);
        if (on) return ex ? text : Kdl.appendNode(text, name);
        return ex ? Kdl.removeNodeLine(text, ex) : text;
    }
    function setTopLine(text, name, line) {
        var ex = topNode(text, name);
        if (line === null) return ex ? Kdl.removeNodeLine(text, ex) : text;
        if (ex) return Kdl.replaceNodeLine(text, ex, Kdl.leadingIndent(text, ex.range) + line);
        return Kdl.appendNode(text, line);
    }
    function setBlkFlag(text, blk, name, on) {
        var b = topNode(text, blk); var ex = b ? childNamed(b, name) : null;
        if (!on) return ex ? Kdl.removeNodeLine(text, ex) : text;
        text = ensureTop(text, blk);
        return childNamed(topNode(text, blk), name) ? text : Kdl.insertChildLine(text, topNode(text, blk), name);
    }
    function setBlkLine(text, blk, name, line) {
        var b = topNode(text, blk); var ex = b ? childNamed(b, name) : null;
        if (line === null) return ex ? Kdl.removeNodeLine(text, ex) : text;
        if (ex) return Kdl.replaceNodeLine(text, ex, Kdl.leadingIndent(text, ex.range) + line);
        text = ensureTop(text, blk);
        return Kdl.insertChildLine(text, topNode(text, blk), line);
    }

    function save() {
        var t = configModel.textOf(miscFile), o = orig;
        if (preferNoCsd !== o.preferNoCsd) t = setTopFlag(t, "prefer-no-csd", preferNoCsd);
        if (screenshotPath !== o.screenshotPath) {
            var spLine = screenshotPath === "" ? null : (screenshotPath === "null" ? "screenshot-path null" : ('screenshot-path "' + screenshotPath + '"'));
            t = setTopLine(t, "screenshot-path", spLine);
        }
        if (cursorTheme !== o.cursorTheme) t = setBlkLine(t, "cursor", "xcursor-theme", cursorTheme ? ('xcursor-theme "' + cursorTheme + '"') : null);
        if (cursorSize !== o.cursorSize) t = setBlkLine(t, "cursor", "xcursor-size", (cursorSize === "" || isNaN(parseInt(cursorSize))) ? null : ("xcursor-size " + parseInt(cursorSize)));
        if (cursorHideTyping !== o.cursorHideTyping) t = setBlkFlag(t, "cursor", "hide-when-typing", cursorHideTyping);
        if (cursorHideMs !== o.cursorHideMs) t = setBlkLine(t, "cursor", "hide-after-inactive-ms", (cursorHideMs === "" || isNaN(parseInt(cursorHideMs))) ? null : ("hide-after-inactive-ms " + parseInt(cursorHideMs)));
        if (hkSkipStartup !== o.hkSkipStartup) t = setBlkFlag(t, "hotkey-overlay", "skip-at-startup", hkSkipStartup);
        if (hkHideNotBound !== o.hkHideNotBound) t = setBlkFlag(t, "hotkey-overlay", "hide-not-bound", hkHideNotBound);
        if (clipDisablePrimary !== o.clipDisablePrimary) t = setBlkFlag(t, "clipboard", "disable-primary", clipDisablePrimary);
        if (overviewZoom !== o.overviewZoom) t = setBlkLine(t, "overview", "zoom", (overviewZoom === "" || isNaN(parseFloat(overviewZoom))) ? null : ("zoom " + parseFloat(overviewZoom)));
        if (overviewBackdrop !== o.overviewBackdrop) t = setBlkLine(t, "overview", "backdrop-color", overviewBackdrop ? ('backdrop-color "' + overviewBackdrop + '"') : null);
        panel.requestSave(miscFile, t, panel.tr("misc.summary", "misc settings"));
    }

    // ---- UI ----
    RowLayout {
        Layout.fillWidth: true
        NText { text: panel.tr("section.misc", "Misc"); font.weight: Style.fontWeightBold; Layout.fillWidth: true }
        NButton {
            text: panel.tr("input.save", "Save changes")
            backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
            enabled: root.dirty && root.miscFile !== ""
            onClicked: root.save()
        }
    }

    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginM

            NText { text: panel.tr("misc.general", "General"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.csd", "Prefer no client-side decorations"); checked: root.preferNoCsd; onToggled: v => root.preferNoCsd = v }
            NTextInput { Layout.fillWidth: true; label: panel.tr("misc.screenshot", "Screenshot path (or 'null' to disable)"); text: root.screenshotPath; placeholderText: "~/Pictures/Screenshots/%Y-%m-%d.png"; onTextChanged: root.screenshotPath = text }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("misc.cursor", "Cursor"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("misc.cursor-theme", "Theme"); text: root.cursorTheme; placeholderText: "default"; onTextChanged: root.cursorTheme = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("misc.cursor-size", "Size"); text: root.cursorSize; placeholderText: "24"; onTextChanged: root.cursorSize = text }
            }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.cursor-hide-typing", "Hide while typing"); checked: root.cursorHideTyping; onToggled: v => root.cursorHideTyping = v }
            NTextInput { Layout.fillWidth: true; label: panel.tr("misc.cursor-hide-ms", "Hide after inactive (ms)"); text: root.cursorHideMs; onTextChanged: root.cursorHideMs = text }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("misc.hotkey", "Hotkey overlay"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.hk-skip", "Skip at startup"); checked: root.hkSkipStartup; onToggled: v => root.hkSkipStartup = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.hk-hide", "Hide unbound entries"); checked: root.hkHideNotBound; onToggled: v => root.hkHideNotBound = v }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("misc.overview", "Overview & clipboard"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("misc.zoom", "Overview zoom (0–0.75)"); text: root.overviewZoom; placeholderText: "0.5"; onTextChanged: root.overviewZoom = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("misc.ov-backdrop", "Overview backdrop color"); text: root.overviewBackdrop; onTextChanged: root.overviewBackdrop = text }
            }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.clip-primary", "Disable primary clipboard"); checked: root.clipDisablePrimary; onToggled: v => root.clipDisablePrimary = v }

            NText { text: panel.tr("misc.env-hint", "Environment variables and other blocks: use the Edit file button above."); color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
    }
}
