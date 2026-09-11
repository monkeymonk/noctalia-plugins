import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import "../lib/layout.js" as LayoutModel
import qs.Commons
import qs.Widgets

// Layout editor — full documented coverage except color gradients (use the
// "Edit file" button for active-gradient/inactive-gradient blocks). Surgical
// batched save: only changed settings are written.
ColumnLayout {
    id: root

    required property var panel
    required property var configModel

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

    function recompute() {
        if (!(configModel && configModel.loaded)) return;
        var own = configModel.ownerOf("layout");
        if (!own) { layoutPath = ""; return; }
        layoutPath = own.path;
        var m = LayoutModel.parse(own.nodes[0], Kdl);
        for (var k in m) root[k] = m[k];
        orig = snapshot();
    }
    function snapshot() {
        var s = {}, defs = LayoutModel.SETTINGS;
        for (var i = 0; i < defs.length; i++) s[defs[i].prop] = root[defs[i].prop];
        return s;
    }

    Component.onCompleted: recompute()
    Connections { target: root.configModel; function onConfigChanged() { root.recompute(); } }

    readonly property bool dirty: {
        if (!orig) return false;
        var s = snapshot();
        for (var k in s) if (s[k] !== orig[k]) return true;
        return false;
    }

    // ---- write: one batched child-edit pass + the preset rewrites ----
    function save() {
        var t = LayoutModel.apply(configModel.textOf(layoutPath), LayoutModel.diff(snapshot(), orig), Kdl);
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
