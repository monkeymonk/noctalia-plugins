import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import qs.Commons
import qs.Widgets

// Layout editor — full documented coverage except color gradients (use the
// "Edit file" button for active-gradient/inactive-gradient blocks). Surgical
// batched save: only changed settings are written.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

    property string layoutPath: ""
    property string sectionFile: layoutPath
    property var orig: ({})

    // scalars / enums / flags
    property string gaps: ""
    property string centerFocused: "never"
    property bool alwaysCenterSingle: false
    property bool emptyWsAbove: false
    property string defaultColDisplay: "normal"
    property string background: ""
    property string presetCols: ""
    property string presetHeights: ""
    property string defaultColWidth: ""
    // focus-ring
    property bool frDisabled: false
    property string frWidth: ""
    property string frActive: ""
    property string frInactive: ""
    property string frUrgent: ""
    // border
    property bool borderEnabled: false
    property string borderWidth: ""
    property string borderActive: ""
    property string borderInactive: ""
    // shadow
    property bool shadowEnabled: false
    property string shadowSoftness: ""
    property string shadowSpread: ""
    property string shadowColor: ""
    property bool shadowBehind: false
    // tab-indicator
    property bool tabDisabled: false
    property string tabWidth: ""
    property string tabGap: ""
    property string tabPosition: ""
    property bool tabHideSingle: false
    property string tabActive: ""
    property string tabInactive: ""
    // insert-hint
    property bool insertDisabled: false
    property string insertColor: ""
    // struts
    property string strutL: ""
    property string strutR: ""
    property string strutT: ""
    property string strutB: ""

    readonly property var centerOpts: [{ key: "never", name: "never" }, { key: "always", name: "always" }, { key: "on-overflow", name: "on-overflow" }]
    readonly property var displayOpts: [{ key: "normal", name: "normal" }, { key: "tabbed", name: "tabbed" }]
    readonly property var tabPosOpts: [{ key: "", name: "(default)" }, { key: "left", name: "left" }, { key: "right", name: "right" }, { key: "top", name: "top" }, { key: "bottom", name: "bottom" }]

    spacing: Style.marginM

    // ---- kdl helpers (rooted at "layout") ----
    function childNamed(node, name) {
        var k = node && node.children ? node.children : [];
        for (var i = 0; i < k.length; i++) if (k[i].name === name) return k[i];
        return null;
    }
    function block(text, pathArr) {
        var cur = Kdl.findNode(Kdl.parse(text), "layout");
        for (var i = 0; cur && i < pathArr.length; i++) cur = childNamed(cur, pathArr[i]);
        return cur;
    }
    function ensureBlock(text, pathArr) {
        if (!Kdl.findNode(Kdl.parse(text), "layout")) text = Kdl.appendNode(text, "layout {\n}");
        for (var i = 0; i < pathArr.length; i++) {
            var cur = Kdl.findNode(Kdl.parse(text), "layout");
            for (var j = 0; cur && j < i; j++) cur = childNamed(cur, pathArr[j]);
            if (cur && !childNamed(cur, pathArr[i])) text = Kdl.insertChildLine(text, cur, pathArr[i] + " {\n}");
        }
        return text;
    }
    function flagOf(node, name) { return !!childNamed(node, name); }
    function strOf(node, name) { var c = childNamed(node, name); return (c && c.args[0]) ? String(c.args[0].value) : ""; }
    function nestStr(text, pathArr, name) { var b = block(text, pathArr); return b ? strOf(b, name) : ""; }
    function nestFlag(text, pathArr, name) { var b = block(text, pathArr); return b ? flagOf(b, name) : false; }

    function presetToStr(node) {
        if (!node) return "";
        return (node.children || []).map(function (c) {
            if (c.name === "proportion" && c.args[0]) return String(c.args[0].value);
            if (c.name === "fixed" && c.args[0]) return c.args[0].value + "px";
            return "";
        }).filter(Boolean).join(", ");
    }

    function recompute() {
        if (!(configModel && configModel.loaded)) return;
        var own = configModel.owner("layout");
        if (!own) { layoutPath = ""; return; }
        layoutPath = own.path;
        var L = own.node;
        gaps = strOf(L, "gaps");
        centerFocused = strOf(L, "center-focused-column") || "never";
        alwaysCenterSingle = flagOf(L, "always-center-single-column");
        emptyWsAbove = flagOf(L, "empty-workspace-above-first");
        defaultColDisplay = strOf(L, "default-column-display") || "normal";
        background = strOf(L, "background-color");
        presetCols = presetToStr(childNamed(L, "preset-column-widths"));
        presetHeights = presetToStr(childNamed(L, "preset-window-heights"));
        defaultColWidth = presetToStr(childNamed(L, "default-column-width"));

        frDisabled = nestFlag(layoutPath ? configModel.textOf(layoutPath) : "", ["focus-ring"], "off");
        frWidth = nestStr(configModel.textOf(layoutPath), ["focus-ring"], "width");
        frActive = nestStr(configModel.textOf(layoutPath), ["focus-ring"], "active-color");
        frInactive = nestStr(configModel.textOf(layoutPath), ["focus-ring"], "inactive-color");
        frUrgent = nestStr(configModel.textOf(layoutPath), ["focus-ring"], "urgent-color");

        var t = configModel.textOf(layoutPath);
        borderEnabled = nestFlag(t, ["border"], "on");
        borderWidth = nestStr(t, ["border"], "width");
        borderActive = nestStr(t, ["border"], "active-color");
        borderInactive = nestStr(t, ["border"], "inactive-color");

        shadowEnabled = nestFlag(t, ["shadow"], "on");
        shadowSoftness = nestStr(t, ["shadow"], "softness");
        shadowSpread = nestStr(t, ["shadow"], "spread");
        shadowColor = nestStr(t, ["shadow"], "color");
        shadowBehind = nestFlag(t, ["shadow"], "draw-behind-window");

        tabDisabled = nestFlag(t, ["tab-indicator"], "off");
        tabWidth = nestStr(t, ["tab-indicator"], "width");
        tabGap = nestStr(t, ["tab-indicator"], "gap");
        tabPosition = nestStr(t, ["tab-indicator"], "position");
        tabHideSingle = nestFlag(t, ["tab-indicator"], "hide-when-single-tab");
        tabActive = nestStr(t, ["tab-indicator"], "active-color");
        tabInactive = nestStr(t, ["tab-indicator"], "inactive-color");

        insertDisabled = nestFlag(t, ["insert-hint"], "off");
        insertColor = nestStr(t, ["insert-hint"], "color");

        strutL = nestStr(t, ["struts"], "left");
        strutR = nestStr(t, ["struts"], "right");
        strutT = nestStr(t, ["struts"], "top");
        strutB = nestStr(t, ["struts"], "bottom");

        orig = snapshot();
    }
    function snapshot() {
        return {
            gaps: gaps, centerFocused: centerFocused, alwaysCenterSingle: alwaysCenterSingle, emptyWsAbove: emptyWsAbove,
            defaultColDisplay: defaultColDisplay, background: background, presetCols: presetCols, presetHeights: presetHeights,
            defaultColWidth: defaultColWidth, frDisabled: frDisabled, frWidth: frWidth, frActive: frActive, frInactive: frInactive, frUrgent: frUrgent,
            borderEnabled: borderEnabled, borderWidth: borderWidth, borderActive: borderActive, borderInactive: borderInactive,
            shadowEnabled: shadowEnabled, shadowSoftness: shadowSoftness, shadowSpread: shadowSpread, shadowColor: shadowColor, shadowBehind: shadowBehind,
            tabDisabled: tabDisabled, tabWidth: tabWidth, tabGap: tabGap, tabPosition: tabPosition, tabHideSingle: tabHideSingle, tabActive: tabActive, tabInactive: tabInactive,
            insertDisabled: insertDisabled, insertColor: insertColor, strutL: strutL, strutR: strutR, strutT: strutT, strutB: strutB
        };
    }

    Component.onCompleted: recompute()
    Connections { target: root.configModel; function onLoadFinished() { root.recompute(); } }

    readonly property bool dirty: {
        if (!orig) return false;
        var s = snapshot();
        for (var k in s) if (s[k] !== orig[k]) return true;
        return false;
    }

    // ---- surgical setters ----
    function existing(text, pathArr, name) { var b = block(text, pathArr); return b ? childNamed(b, name) : null; }
    function setFlag(text, pathArr, name, on) {
        if (!on) { var ex0 = existing(text, pathArr, name); return ex0 ? Kdl.removeNodeLine(text, ex0) : text; }
        text = ensureBlock(text, pathArr);
        return childNamed(block(text, pathArr), name) ? text : Kdl.insertChildLine(text, block(text, pathArr), name);
    }
    function setLine(text, pathArr, name, line) {
        var ex0 = existing(text, pathArr, name);
        if (line === null) return ex0 ? Kdl.removeNodeLine(text, ex0) : text;
        if (ex0) return Kdl.replaceNodeLine(text, ex0, Kdl.leadingIndent(text, ex0.range) + line);
        text = ensureBlock(text, pathArr);
        return Kdl.insertChildLine(text, block(text, pathArr), line);
    }
    function setNum(text, pathArr, name, v) { return setLine(text, pathArr, name, (v === "" || isNaN(parseFloat(v))) ? null : (name + " " + parseFloat(v))); }
    function setStr(text, pathArr, name, v) { return setLine(text, pathArr, name, v ? (name + ' "' + v + '"') : null); }
    function setBool(text, pathArr, name, v) { return setLine(text, pathArr, name, name + " " + (v ? "true" : "false")); }
    // replace/insert/remove a whole preset-style block from a "0.5, 1280px" string
    function setPreset(text, name, valuesStr) {
        var toks = valuesStr.split(",").map(function (s) { return s.trim(); }).filter(Boolean);
        var L = Kdl.findNode(Kdl.parse(text), "layout");
        var ex = L ? childNamed(L, name) : null;
        if (!toks.length) return ex ? Kdl.removeNodeLine(text, ex) : text;
        var inner = "    ";
        var lines = [name + " {"];
        toks.forEach(function (tk) {
            if (/px$/i.test(tk)) lines.push(inner + "fixed " + parseInt(tk));
            else lines.push(inner + "proportion " + parseFloat(tk));
        });
        lines.push("}");
        var blockText = lines.join("\n");
        if (ex) return Kdl.replaceNodeLine(text, ex, Kdl.leadingIndent(text, ex.range) + blockText);
        text = ensureBlock(text, []);
        return Kdl.insertChildLine(text, Kdl.findNode(Kdl.parse(text), "layout"), blockText);
    }

    function save() {
        var t = configModel.textOf(layoutPath), o = orig;
        if (gaps !== o.gaps) t = setNum(t, [], "gaps", gaps);
        if (centerFocused !== o.centerFocused) t = setStr(t, [], "center-focused-column", centerFocused);
        if (alwaysCenterSingle !== o.alwaysCenterSingle) t = setFlag(t, [], "always-center-single-column", alwaysCenterSingle);
        if (emptyWsAbove !== o.emptyWsAbove) t = setFlag(t, [], "empty-workspace-above-first", emptyWsAbove);
        if (defaultColDisplay !== o.defaultColDisplay) t = setStr(t, [], "default-column-display", defaultColDisplay === "normal" ? "" : defaultColDisplay);
        if (background !== o.background) t = setStr(t, [], "background-color", background);
        if (presetCols !== o.presetCols) t = setPreset(t, "preset-column-widths", presetCols);
        if (presetHeights !== o.presetHeights) t = setPreset(t, "preset-window-heights", presetHeights);
        if (defaultColWidth !== o.defaultColWidth) t = setPreset(t, "default-column-width", defaultColWidth);

        if (frDisabled !== o.frDisabled) t = setFlag(t, ["focus-ring"], "off", frDisabled);
        if (frWidth !== o.frWidth) t = setNum(t, ["focus-ring"], "width", frWidth);
        if (frActive !== o.frActive) t = setStr(t, ["focus-ring"], "active-color", frActive);
        if (frInactive !== o.frInactive) t = setStr(t, ["focus-ring"], "inactive-color", frInactive);
        if (frUrgent !== o.frUrgent) t = setStr(t, ["focus-ring"], "urgent-color", frUrgent);

        if (borderEnabled !== o.borderEnabled) t = setFlag(t, ["border"], "on", borderEnabled);
        if (borderWidth !== o.borderWidth) t = setNum(t, ["border"], "width", borderWidth);
        if (borderActive !== o.borderActive) t = setStr(t, ["border"], "active-color", borderActive);
        if (borderInactive !== o.borderInactive) t = setStr(t, ["border"], "inactive-color", borderInactive);

        if (shadowEnabled !== o.shadowEnabled) t = setFlag(t, ["shadow"], "on", shadowEnabled);
        if (shadowSoftness !== o.shadowSoftness) t = setNum(t, ["shadow"], "softness", shadowSoftness);
        if (shadowSpread !== o.shadowSpread) t = setNum(t, ["shadow"], "spread", shadowSpread);
        if (shadowColor !== o.shadowColor) t = setStr(t, ["shadow"], "color", shadowColor);
        if (shadowBehind !== o.shadowBehind) t = setBool(t, ["shadow"], "draw-behind-window", shadowBehind);

        if (tabDisabled !== o.tabDisabled) t = setFlag(t, ["tab-indicator"], "off", tabDisabled);
        if (tabWidth !== o.tabWidth) t = setNum(t, ["tab-indicator"], "width", tabWidth);
        if (tabGap !== o.tabGap) t = setNum(t, ["tab-indicator"], "gap", tabGap);
        if (tabPosition !== o.tabPosition) t = setStr(t, ["tab-indicator"], "position", tabPosition);
        if (tabHideSingle !== o.tabHideSingle) t = setFlag(t, ["tab-indicator"], "hide-when-single-tab", tabHideSingle);
        if (tabActive !== o.tabActive) t = setStr(t, ["tab-indicator"], "active-color", tabActive);
        if (tabInactive !== o.tabInactive) t = setStr(t, ["tab-indicator"], "inactive-color", tabInactive);

        if (insertDisabled !== o.insertDisabled) t = setFlag(t, ["insert-hint"], "off", insertDisabled);
        if (insertColor !== o.insertColor) t = setStr(t, ["insert-hint"], "color", insertColor);

        if (strutL !== o.strutL) t = setNum(t, ["struts"], "left", strutL);
        if (strutR !== o.strutR) t = setNum(t, ["struts"], "right", strutR);
        if (strutT !== o.strutT) t = setNum(t, ["struts"], "top", strutT);
        if (strutB !== o.strutB) t = setNum(t, ["struts"], "bottom", strutB);

        panel.requestSave(layoutPath, t, panel.tr("layout.summary", "layout settings"));
    }

    // ---- UI ----
    RowLayout {
        Layout.fillWidth: true
        NText { text: panel.tr("section.layout", "Layout"); font.weight: Style.fontWeightBold; Layout.fillWidth: true }
        NButton {
            text: panel.tr("input.save", "Save changes")
            backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
            enabled: root.dirty && root.layoutPath !== ""
            onClicked: root.save()
        }
    }
    NText { visible: root.layoutPath === ""; text: panel.tr("layout.none", "No layout {} block found."); color: Color.mError }

    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginM

            NText { text: panel.tr("layout.general", "General"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NTextInput { Layout.fillWidth: true; label: panel.tr("layout.gaps", "Gaps (px)"); text: root.gaps; placeholderText: "12"; onTextChanged: root.gaps = text }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NComboBox { Layout.fillWidth: true; label: panel.tr("layout.center", "Center focused column"); model: root.centerOpts; currentKey: root.centerFocused; onSelected: key => root.centerFocused = key }
                NComboBox { Layout.fillWidth: true; label: panel.tr("layout.coldisplay", "Default column display"); model: root.displayOpts; currentKey: root.defaultColDisplay; onSelected: key => root.defaultColDisplay = key }
            }
            NTextInput { Layout.fillWidth: true; label: panel.tr("layout.bg", "Background color"); text: root.background; placeholderText: "transparent"; onTextChanged: root.background = text }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.center-single", "Always center single column"); checked: root.alwaysCenterSingle; onToggled: v => root.alwaysCenterSingle = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.empty-above", "Empty workspace above first"); checked: root.emptyWsAbove; onToggled: v => root.emptyWsAbove = v }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("layout.presets", "Widths"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NTextInput { Layout.fillWidth: true; label: panel.tr("layout.preset-cols", "Preset column widths (e.g. 0.33, 0.5, 1280px)"); text: root.presetCols; onTextChanged: root.presetCols = text }
            NTextInput { Layout.fillWidth: true; label: panel.tr("layout.preset-heights", "Preset window heights"); text: root.presetHeights; onTextChanged: root.presetHeights = text }
            NTextInput { Layout.fillWidth: true; label: panel.tr("layout.default-col", "Default column width (0.5 or 1280px)"); text: root.defaultColWidth; onTextChanged: root.defaultColWidth = text }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("layout.focus-ring-h", "Focus ring"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.disabled", "Disabled"); checked: root.frDisabled; onToggled: v => root.frDisabled = v }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.width", "Width"); text: root.frWidth; placeholderText: "3"; onTextChanged: root.frWidth = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.active", "Active color"); text: root.frActive; placeholderText: "#7fc8ff"; onTextChanged: root.frActive = text }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.inactive", "Inactive color"); text: root.frInactive; onTextChanged: root.frInactive = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.urgent", "Urgent color"); text: root.frUrgent; onTextChanged: root.frUrgent = text }
            }
            NText { text: panel.tr("layout.gradient-hint", "Gradients (active-gradient…) — use the Edit file button."); color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; wrapMode: Text.WordWrap; Layout.fillWidth: true }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("layout.border-h", "Border"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.enabled", "Enabled"); checked: root.borderEnabled; onToggled: v => root.borderEnabled = v }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.width", "Width"); text: root.borderWidth; placeholderText: "2"; onTextChanged: root.borderWidth = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.active", "Active color"); text: root.borderActive; onTextChanged: root.borderActive = text }
            }
            NTextInput { Layout.fillWidth: true; label: panel.tr("layout.inactive", "Inactive color"); text: root.borderInactive; onTextChanged: root.borderInactive = text }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("layout.shadow-h", "Shadow"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.enabled", "Enabled"); checked: root.shadowEnabled; onToggled: v => root.shadowEnabled = v }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.softness", "Softness"); text: root.shadowSoftness; placeholderText: "30"; onTextChanged: root.shadowSoftness = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.spread", "Spread"); text: root.shadowSpread; placeholderText: "5"; onTextChanged: root.shadowSpread = text }
            }
            NTextInput { Layout.fillWidth: true; label: panel.tr("layout.shadow-color", "Color"); text: root.shadowColor; placeholderText: "#00000070"; onTextChanged: root.shadowColor = text }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.shadow-behind", "Draw behind window"); checked: root.shadowBehind; onToggled: v => root.shadowBehind = v }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("layout.tab-h", "Tab indicator"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.disabled", "Disabled"); checked: root.tabDisabled; onToggled: v => root.tabDisabled = v }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.width", "Width"); text: root.tabWidth; onTextChanged: root.tabWidth = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.gap", "Gap"); text: root.tabGap; onTextChanged: root.tabGap = text }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NComboBox { Layout.fillWidth: true; label: panel.tr("layout.position", "Position"); model: root.tabPosOpts; currentKey: root.tabPosition; onSelected: key => root.tabPosition = key }
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.active", "Active color"); text: root.tabActive; onTextChanged: root.tabActive = text }
            }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.tab-hide-single", "Hide when single tab"); checked: root.tabHideSingle; onToggled: v => root.tabHideSingle = v }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("layout.insert-h", "Insert hint"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("layout.disabled", "Disabled"); checked: root.insertDisabled; onToggled: v => root.insertDisabled = v }
            NTextInput { Layout.fillWidth: true; label: panel.tr("layout.color", "Color"); text: root.insertColor; onTextChanged: root.insertColor = text }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("layout.struts-h", "Struts"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.strut-l", "Left"); text: root.strutL; onTextChanged: root.strutL = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.strut-r", "Right"); text: root.strutR; onTextChanged: root.strutR = text }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.strut-t", "Top"); text: root.strutT; onTextChanged: root.strutT = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("layout.strut-b", "Bottom"); text: root.strutB; onTextChanged: root.strutB = text }
            }
        }
    }
}
