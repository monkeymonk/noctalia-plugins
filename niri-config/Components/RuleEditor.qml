import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/rules.js" as Rules
import qs.Commons
import qs.Widgets

// Add/edit a window-rule. Emits accepted(editNode, ruleModel). Covers the
// documented properties; styling blocks (focus-ring/border/shadow/effects) and
// extra match criteria are preserved verbatim across edits (rawExtras) — use the
// section's Edit-file button to tweak those.
Item {
    id: root

    property var panel: null

    // match
    property string appId: ""
    property string title: ""
    // open behavior (tri-state: "" unset / "true" / "false")
    property string floating: ""
    property string maximized: ""
    property string fullscreen: ""
    property string focused: ""
    property string maxToEdges: ""
    property string vrr: ""
    property string drawBorderBg: ""
    property string clipGeo: ""
    property string tiledState: ""
    property string babaFloat: ""
    // placement
    property string onWorkspace: ""
    property string onOutput: ""
    property string floatX: ""
    property string floatY: ""
    property string floatRel: ""
    // sizing
    property string colWidth: ""
    property string winHeight: ""
    property string minW: ""
    property string maxW: ""
    property string minH: ""
    property string maxH: ""
    // appearance
    property string winOpacity: ""
    property string scrollFactor: ""
    property string cornerRadius: ""
    property string colDisplay: ""
    property string blockOut: ""

    // preserved verbatim
    property var origMatches: []
    property var origExcludes: []
    property var origExtras: []
    property string origKind: "window-rule"
    property var editNode: null

    signal accepted(var editNode, var rule)

    function tr(k, f) { return panel ? panel.tr(k, f) : f; }

    readonly property var triOpts: [{ key: "", name: "(unset)" }, { key: "true", name: "yes" }, { key: "false", name: "no" }]
    readonly property var colDispOpts: [{ key: "", name: "(unset)" }, { key: "normal", name: "normal" }, { key: "tabbed", name: "tabbed" }]
    readonly property var blockOutOpts: [{ key: "", name: "(unset)" }, { key: "screencast", name: "screencast" }, { key: "screen-capture", name: "screen-capture" }]
    readonly property var relOpts: [{ key: "", name: "(default)" }, { key: "top-left", name: "top-left" }, { key: "top-right", name: "top-right" }, { key: "bottom-left", name: "bottom-left" }, { key: "bottom-right", name: "bottom-right" }]

    function triFrom(v) { return v === undefined ? "" : (v ? "true" : "false"); }
    function numFrom(v) { return (v === undefined || v === null) ? "" : String(v); }

    function reset() {
        appId = ""; title = "";
        floating = ""; maximized = ""; fullscreen = ""; focused = ""; maxToEdges = "";
        vrr = ""; drawBorderBg = ""; clipGeo = ""; tiledState = ""; babaFloat = "";
        onWorkspace = ""; onOutput = ""; floatX = ""; floatY = ""; floatRel = "";
        colWidth = ""; winHeight = ""; minW = ""; maxW = ""; minH = ""; maxH = "";
        winOpacity = ""; scrollFactor = ""; cornerRadius = ""; colDisplay = ""; blockOut = "";
        origMatches = []; origExcludes = []; origExtras = []; origKind = "window-rule";
    }

    function openCreate() { reset(); editNode = null; popup.open(); }

    function openEdit(r) {
        reset(); editNode = r.node;
        origMatches = r.matches || []; origExcludes = r.excludes || []; origExtras = r.rawExtras || [];
        origKind = r.kind || "window-rule";
        var m = (r.matches && r.matches[0]) || {};
        appId = m["app-id"] || ""; title = m.title || "";
        var p = r.props || {};
        floating = triFrom(p.openFloating); maximized = triFrom(p.openMaximized); fullscreen = triFrom(p.openFullscreen);
        focused = triFrom(p.openFocused); maxToEdges = triFrom(p.openMaxToEdges); vrr = triFrom(p.vrr);
        drawBorderBg = triFrom(p.drawBorderWithBg); clipGeo = triFrom(p.clipToGeometry); tiledState = triFrom(p.tiledState); babaFloat = triFrom(p.babaIsFloat);
        onWorkspace = p.openOnWorkspace || ""; onOutput = p.openOnOutput || "";
        if (p.floatPos) { floatX = numFrom(p.floatPos.x); floatY = numFrom(p.floatPos.y); floatRel = p.floatPos.relativeTo || ""; }
        colWidth = (p.colWidth != null) ? String(p.colWidth) : ""; winHeight = (p.winHeight != null) ? String(p.winHeight) : "";
        minW = numFrom(p.minWidth); maxW = numFrom(p.maxWidth); minH = numFrom(p.minHeight); maxH = numFrom(p.maxHeight);
        winOpacity = numFrom(p.opacity); scrollFactor = numFrom(p.scrollFactor); cornerRadius = p.cornerRadius || "";
        colDisplay = p.defaultColDisplay || ""; blockOut = p.blockOutFrom || "";
        popup.open();
    }

    function buildRule() {
        var match0 = {};
        var src = (origMatches && origMatches[0]) || {};
        for (var k in src) match0[k] = src[k];
        if (appId) match0["app-id"] = appId; else delete match0["app-id"];
        if (title) match0.title = title; else delete match0.title;
        var hasMatch0 = Object.keys(match0).length > 0;
        var matches = (origMatches && origMatches.length > 1) ? [match0].concat(origMatches.slice(1)) : (hasMatch0 ? [match0] : []);

        function tri(s) { return s === "" ? undefined : (s === "true"); }
        function fnum(s) { return (s !== "" && !isNaN(parseFloat(s))) ? parseFloat(s) : null; }
        function inum(s) { return (s !== "" && !isNaN(parseInt(s))) ? parseInt(s) : null; }
        var p = {};
        p.openFloating = tri(floating); p.openMaximized = tri(maximized); p.openFullscreen = tri(fullscreen);
        p.openFocused = tri(focused); p.openMaxToEdges = tri(maxToEdges); p.vrr = tri(vrr);
        p.drawBorderWithBg = tri(drawBorderBg); p.clipToGeometry = tri(clipGeo); p.tiledState = tri(tiledState); p.babaIsFloat = tri(babaFloat);
        if (onWorkspace) p.openOnWorkspace = onWorkspace;
        if (onOutput) p.openOnOutput = onOutput;
        if (colWidth && fnum(colWidth) != null) p.colWidth = fnum(colWidth);
        if (winHeight && fnum(winHeight) != null) p.winHeight = fnum(winHeight);
        p.minWidth = inum(minW); p.maxWidth = inum(maxW); p.minHeight = inum(minH); p.maxHeight = inum(maxH);
        if (fnum(winOpacity) != null) p.opacity = fnum(winOpacity);
        if (fnum(scrollFactor) != null) p.scrollFactor = fnum(scrollFactor);
        if (cornerRadius) p.cornerRadius = cornerRadius;
        if (colDisplay) p.defaultColDisplay = colDisplay;
        if (blockOut) p.blockOutFrom = blockOut;
        if (floatX !== "" || floatY !== "") p.floatPos = { x: inum(floatX) != null ? inum(floatX) : 0, y: inum(floatY) != null ? inum(floatY) : 0, relativeTo: floatRel };

        return { kind: origKind || "window-rule", matches: matches, excludes: origExcludes || [], props: p, rawExtras: origExtras || [], disabled: false };
    }

    readonly property bool canSave: (appId !== "" || title !== "")

    visible: false

    WindowPicker { id: windowPicker; panel: root.panel; onPicked: (a, t) => { root.appId = a; root.title = t; } }

    Popup {
        id: popup
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - Style.marginXL : 600, 600)
        height: Math.min(parent ? parent.height - Style.marginXL : 640, 640)
        padding: Style.marginL
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            NText {
                text: root.editNode ? root.tr("ruleeditor.edit", "Edit window rule") : root.tr("ruleeditor.add", "Add window rule")
                font.pointSize: Style.fontSizeL; font.weight: Style.fontWeightBold
            }

            NScrollView {
                id: sv
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalPolicy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: sv.availableWidth
                    spacing: Style.marginS

                    // match
                    RowLayout {
                        Layout.fillWidth: true
                        NText { text: root.tr("ruleeditor.match", "Match a window"); font.weight: Style.fontWeightMedium; Layout.fillWidth: true }
                        NButton { icon: "app-window"; text: root.tr("ruleeditor.capture", "Capture window"); onClicked: windowPicker.open() }
                    }
                    NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.appid", "app-id (regex)"); text: root.appId; placeholderText: "firefox"; onTextChanged: root.appId = text }
                    NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.title", "title (regex, optional)"); text: root.title; placeholderText: "Picture in picture"; onTextChanged: root.title = text }
                    NText { visible: (root.origMatches && root.origMatches.length > 1) || (root.origExcludes && root.origExcludes.length > 0); text: root.tr("ruleeditor.preserved", "Extra match/exclude criteria are preserved."); color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; Layout.fillWidth: true; wrapMode: Text.WordWrap }

                    NDivider { Layout.fillWidth: true }
                    NText { text: root.tr("ruleeditor.open", "Open behavior"); font.weight: Style.fontWeightMedium }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.floating", "Floating"); model: root.triOpts; currentKey: root.floating; onSelected: k => root.floating = k }
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.maximized", "Maximized"); model: root.triOpts; currentKey: root.maximized; onSelected: k => root.maximized = k }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.fullscreen", "Fullscreen"); model: root.triOpts; currentKey: root.fullscreen; onSelected: k => root.fullscreen = k }
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.focused", "Focused"); model: root.triOpts; currentKey: root.focused; onSelected: k => root.focused = k }
                    }

                    NDivider { Layout.fillWidth: true }
                    NText { text: root.tr("ruleeditor.place", "Placement"); font.weight: Style.fontWeightMedium }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.workspace", "On workspace"); text: root.onWorkspace; onTextChanged: root.onWorkspace = text }
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.output", "On output"); text: root.onOutput; onTextChanged: root.onOutput = text }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.floatx", "Float X"); text: root.floatX; onTextChanged: root.floatX = text }
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.floaty", "Float Y"); text: root.floatY; onTextChanged: root.floatY = text }
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.relto", "Relative to"); model: root.relOpts; currentKey: root.floatRel; onSelected: k => root.floatRel = k }
                    }

                    NDivider { Layout.fillWidth: true }
                    NText { text: root.tr("ruleeditor.size", "Sizing"); font.weight: Style.fontWeightMedium }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.colwidth", "Column width (0–1)"); text: root.colWidth; placeholderText: "0.5"; onTextChanged: root.colWidth = text }
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.winheight", "Window height (0–1)"); text: root.winHeight; placeholderText: "0.9"; onTextChanged: root.winHeight = text }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.minw", "Min width"); text: root.minW; onTextChanged: root.minW = text }
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.maxw", "Max width"); text: root.maxW; onTextChanged: root.maxW = text }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.minh", "Min height"); text: root.minH; onTextChanged: root.minH = text }
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.maxh", "Max height"); text: root.maxH; onTextChanged: root.maxH = text }
                    }

                    NDivider { Layout.fillWidth: true }
                    NText { text: root.tr("ruleeditor.appearance", "Appearance & behavior"); font.weight: Style.fontWeightMedium }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.opacity", "Opacity (0–1)"); text: root.winOpacity; placeholderText: "0.95"; onTextChanged: root.winOpacity = text }
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.corner", "Corner radius"); text: root.cornerRadius; placeholderText: "10"; onTextChanged: root.cornerRadius = text }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NTextInput { Layout.fillWidth: true; label: root.tr("ruleeditor.scrollfactor", "Scroll factor"); text: root.scrollFactor; onTextChanged: root.scrollFactor = text }
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.coldisplay", "Column display"); model: root.colDispOpts; currentKey: root.colDisplay; onSelected: k => root.colDisplay = k }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.clip", "Clip to geometry"); model: root.triOpts; currentKey: root.clipGeo; onSelected: k => root.clipGeo = k }
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.blockout", "Block out from"); model: root.blockOutOpts; currentKey: root.blockOut; onSelected: k => root.blockOut = k }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.marginS
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.vrr", "VRR"); model: root.triOpts; currentKey: root.vrr; onSelected: k => root.vrr = k }
                        NComboBox { Layout.fillWidth: true; label: root.tr("ruleeditor.tiled", "Tiled state"); model: root.triOpts; currentKey: root.tiledState; onSelected: k => root.tiledState = k }
                    }
                    NText { text: root.tr("ruleeditor.blocks-hint", "Per-rule focus-ring/border/shadow/effects are preserved — edit via the file."); color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                Item { Layout.fillWidth: true }
                NButton { text: root.tr("action.cancel", "Cancel"); onClicked: popup.close() }
                NButton {
                    text: root.tr("action.save", "Save")
                    backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                    enabled: root.canSave
                    onClicked: { var r = root.buildRule(); popup.close(); root.accepted(root.editNode, r); }
                }
            }
        }
    }
}
