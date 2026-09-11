import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "../lib/kdl.js" as Kdl
import "../lib/input.js" as Input
import "../lib/xkb.js" as Xkb
import qs.Commons
import qs.Widgets

// Input editor: keyboard / touchpad / mouse / general. Covers the documented
// niri input options (device sub-blocks like tablet/trackpoint and xkb rules/
// file are left to the "Edit file" button). Surgical batched save — only changed
// settings are touched, preserving comments and untouched lines.
ColumnLayout {
    id: root

    required property var panel
    required property var configModel

    property string inputPath: ""
    property string sectionFile: inputPath
    property var orig: ({})

    // keyboard
    property string layout: ""
    property string variant: ""
    property string options: ""
    property string model: ""
    property string trackLayout: ""
    property bool numlock: false
    property string repeatDelay: ""
    property string repeatRate: ""
    // touchpad
    property bool tpOff: false
    property bool tpTap: false
    property bool tpDwt: false
    property bool tpDwtp: false
    property bool tpNatural: false
    property bool tpDrag: false
    property bool tpDragLock: false
    property bool tpMiddleEmu: false
    property bool tpLeftHanded: false
    property bool tpDisabledExt: false
    property string tpAccel: ""
    property string tpAccelProfile: ""
    property string tpScrollMethod: ""
    property string tpClickMethod: ""
    property string tpTapButtonMap: ""
    // mouse
    property bool msOff: false
    property bool msNatural: false
    property bool msMiddleEmu: false
    property bool msLeftHanded: false
    property string msAccel: ""
    property string msAccelProfile: ""
    property string msScrollMethod: ""
    // general
    property bool focusFollowsMouse: false
    property bool warpMouse: false
    property bool wsBackAndForth: false
    property bool disablePowerKey: false
    property string modKey: ""

    readonly property var accelProfiles: [{ key: "", name: "(default)" }, { key: "adaptive", name: "adaptive" }, { key: "flat", name: "flat" }]
    readonly property var scrollMethods: [{ key: "", name: "(default)" }, { key: "no-scroll", name: "no-scroll" }, { key: "two-finger", name: "two-finger" }, { key: "edge", name: "edge" }, { key: "on-button-down", name: "on-button-down" }]
    readonly property var clickMethods: [{ key: "", name: "(default)" }, { key: "button-areas", name: "button-areas" }, { key: "clickfinger", name: "clickfinger" }]
    readonly property var tapMaps: [{ key: "", name: "(default)" }, { key: "left-right-middle", name: "left-right-middle" }, { key: "left-middle-right", name: "left-middle-right" }]
    readonly property var trackLayouts: [{ key: "", name: "(default)" }, { key: "global", name: "global" }, { key: "window", name: "window" }]
    readonly property var modKeys: [{ key: "", name: "(default)" }, { key: "Super", name: "Super" }, { key: "Alt", name: "Alt" }, { key: "Ctrl", name: "Ctrl" }, { key: "Shift", name: "Shift" }, { key: "Mod3", name: "Mod3" }, { key: "Mod5", name: "Mod5" }]

    spacing: Style.marginM

    // ---- settings table lives in lib/input.js (one row per option) ----
    readonly property var settingDefs: Input.SETTINGS

    // ---- xkb catalogue (evdev.lst); falls back to a curated subset ----
    property var xkbData: Xkb.parseEvdevList("")
    readonly property string primaryLayout: (root.layout.split(",")[0] || "").trim()

    readonly property var modelItems: root.modelPickerItems(root.xkbData.models, root.model)
    readonly property var layoutItems: root.pickerItems(root.xkbData.layouts, "(add layout…)")
    readonly property var optionItems: root.pickerItems(root.xkbData.options, "(add option…)")
    readonly property var variantItems: root.pickerItems(Xkb.variantsForLayout(root.xkbData, root.primaryLayout), "(none)")

    // Inserter combo model: a leading no-op/clear entry, then code → description.
    function pickerItems(list, firstName) {
        var out = [{ key: "", name: firstName }];
        for (var i = 0; i < (list || []).length; i++) out.push({ key: list[i].code, name: list[i].desc || list[i].code });
        return out;
    }
    // Single-valued: "(default)" + every known model, plus the configured code
    // when evdev.lst does not list it (so a save never drops it).
    function modelPickerItems(list, current) {
        var out = [{ key: "", name: "(default)" }], seen = {};
        for (var i = 0; i < (list || []).length; i++) {
            out.push({ key: list[i].code, name: list[i].desc || list[i].code });
            seen[list[i].code] = true;
        }
        if (current !== "" && !seen[current]) out.push({ key: current, name: current });
        return out;
    }
    // niri's layout/options/variant are comma-separated lists — append, never replace.
    function csvAdd(cur, code) {
        if (!code) return cur;
        var parts = cur === "" ? [] : cur.split(",");
        for (var i = 0; i < parts.length; i++) if (parts[i].trim() === code) return cur;
        parts.push(code);
        return parts.join(",");
    }

    Process {
        id: xkbProcess
        command: ["cat", "/usr/share/X11/xkb/rules/evdev.lst"]
        property string text: ""
        stdout: StdioCollector { onStreamFinished: xkbProcess.text = this.text }
        stderr: StdioCollector {}
        // unreadable file → parse("") → the module's fallback layouts
        onExited: (code) => { root.xkbData = Xkb.parseEvdevList(code === 0 ? xkbProcess.text : ""); }
    }

    // ---- read ----
    function recompute() {
        if (!(configModel && configModel.loaded)) return;
        var own = configModel.ownerOf("input");
        if (!own) { inputPath = ""; return; }
        inputPath = own.path;
        var m = Input.parse(own.nodes[0], Kdl), defs = settingDefs;
        for (var i = 0; i < defs.length; i++) root[defs[i].prop] = m[defs[i].prop];
        orig = snapshot();
    }
    function snapshot() {
        var s = {}, defs = settingDefs;
        for (var i = 0; i < defs.length; i++) s[defs[i].prop] = root[defs[i].prop];
        return s;
    }

    Component.onCompleted: { recompute(); xkbProcess.running = true; }
    Connections { target: root.configModel; function onConfigChanged() { root.recompute(); } }

    readonly property bool dirty: {
        if (!orig) return false;
        var s = snapshot();
        for (var k in s) if (s[k] !== orig[k]) return true;
        return false;
    }

    // ---- write (one parse for the whole batch, inside Kdl) ----
    function save() {
        var t = Input.apply(configModel.textOf(inputPath), Input.diff(snapshot(), orig), Kdl);
        panel.requestSave(inputPath, t, panel.tr("input.summary", "input settings"));
    }

    // ---- UI ----
    RowLayout {
        Layout.fillWidth: true
        NText { text: panel.tr("section.input", "Input"); font.weight: Style.fontWeightBold; Layout.fillWidth: true }
        NButton {
            text: panel.tr("input.save", "Save changes")
            backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
            enabled: root.dirty && root.inputPath !== ""
            onClicked: root.save()
        }
    }
    NText { visible: root.inputPath === ""; text: panel.tr("input.none", "No input {} block found."); color: Color.mError }

    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginM

            // Keyboard
            NText { text: panel.tr("input.keyboard", "Keyboard"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { id: layoutInput; Layout.fillWidth: true; label: panel.tr("input.layout", "Layout"); text: root.layout; placeholderText: "us,de"; onTextChanged: root.layout = text }
                NComboBox {
                    Layout.fillWidth: true
                    label: panel.tr("input.layout-add", "Add layout")
                    model: root.layoutItems
                    currentKey: ""
                    onSelected: key => layoutInput.text = root.csvAdd(layoutInput.text, key)
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { id: variantInput; Layout.fillWidth: true; label: panel.tr("input.variant", "Variant"); text: root.variant; placeholderText: "intl"; onTextChanged: root.variant = text }
                NComboBox {
                    Layout.fillWidth: true
                    label: panel.tr("input.variant-add", "Add variant")
                    model: root.variantItems
                    currentKey: ""
                    onSelected: key => variantInput.text = (key === "" ? "" : root.csvAdd(variantInput.text, key))
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { id: optionsInput; Layout.fillWidth: true; label: panel.tr("input.options", "XKB options"); text: root.options; placeholderText: "compose:ralt,ctrl:nocaps"; onTextChanged: root.options = text }
                NComboBox {
                    Layout.fillWidth: true
                    label: panel.tr("input.options-add", "Add option")
                    model: root.optionItems
                    currentKey: ""
                    onSelected: key => optionsInput.text = root.csvAdd(optionsInput.text, key)
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NComboBox { Layout.fillWidth: true; label: panel.tr("input.model", "XKB model"); model: root.modelItems; currentKey: root.model; onSelected: key => root.model = key }
                NComboBox { Layout.fillWidth: true; label: panel.tr("input.track-layout", "Track layout"); model: root.trackLayouts; currentKey: root.trackLayout; onSelected: key => root.trackLayout = key }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("input.repeat-delay", "Repeat delay (ms)"); text: root.repeatDelay; placeholderText: "600"; onTextChanged: root.repeatDelay = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("input.repeat-rate", "Repeat rate"); text: root.repeatRate; placeholderText: "25"; onTextChanged: root.repeatRate = text }
            }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.numlock", "Enable numlock at startup"); checked: root.numlock; onToggled: v => root.numlock = v }

            NDivider { Layout.fillWidth: true }

            // Touchpad
            NText { text: panel.tr("input.touchpad", "Touchpad"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.tp-off", "Disable touchpad"); checked: root.tpOff; onToggled: v => root.tpOff = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.tap", "Tap to click"); checked: root.tpTap; onToggled: v => root.tpTap = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.dwt", "Disable while typing"); checked: root.tpDwt; onToggled: v => root.tpDwt = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.dwtp", "Disable while trackpointing"); checked: root.tpDwtp; onToggled: v => root.tpDwtp = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.natural", "Natural scrolling"); checked: root.tpNatural; onToggled: v => root.tpNatural = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.drag", "Tap-and-drag"); checked: root.tpDrag; onToggled: v => root.tpDrag = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.drag-lock", "Drag lock"); checked: root.tpDragLock; onToggled: v => root.tpDragLock = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.middle-emu", "Middle-click emulation"); checked: root.tpMiddleEmu; onToggled: v => root.tpMiddleEmu = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.left-handed", "Left-handed"); checked: root.tpLeftHanded; onToggled: v => root.tpLeftHanded = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.disabled-ext", "Disable when external mouse present"); checked: root.tpDisabledExt; onToggled: v => root.tpDisabledExt = v }
            NTextInput { Layout.fillWidth: true; label: panel.tr("input.accel", "Acceleration (-1.0 … 1.0)"); text: root.tpAccel; placeholderText: "0.0"; onTextChanged: root.tpAccel = text }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NComboBox { Layout.fillWidth: true; label: panel.tr("input.accel-profile", "Accel profile"); model: root.accelProfiles; currentKey: root.tpAccelProfile; onSelected: key => root.tpAccelProfile = key }
                NComboBox { Layout.fillWidth: true; label: panel.tr("input.scroll-method", "Scroll method"); model: root.scrollMethods; currentKey: root.tpScrollMethod; onSelected: key => root.tpScrollMethod = key }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NComboBox { Layout.fillWidth: true; label: panel.tr("input.click-method", "Click method"); model: root.clickMethods; currentKey: root.tpClickMethod; onSelected: key => root.tpClickMethod = key }
                NComboBox { Layout.fillWidth: true; label: panel.tr("input.tap-map", "Tap button map"); model: root.tapMaps; currentKey: root.tpTapButtonMap; onSelected: key => root.tpTapButtonMap = key }
            }

            NDivider { Layout.fillWidth: true }

            // Mouse
            NText { text: panel.tr("input.mouse", "Mouse"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.ms-off", "Disable mouse"); checked: root.msOff; onToggled: v => root.msOff = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.natural", "Natural scrolling"); checked: root.msNatural; onToggled: v => root.msNatural = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.middle-emu", "Middle-click emulation"); checked: root.msMiddleEmu; onToggled: v => root.msMiddleEmu = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.left-handed", "Left-handed"); checked: root.msLeftHanded; onToggled: v => root.msLeftHanded = v }
            NTextInput { Layout.fillWidth: true; label: panel.tr("input.accel", "Acceleration (-1.0 … 1.0)"); text: root.msAccel; placeholderText: "0.0"; onTextChanged: root.msAccel = text }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NComboBox { Layout.fillWidth: true; label: panel.tr("input.accel-profile", "Accel profile"); model: root.accelProfiles; currentKey: root.msAccelProfile; onSelected: key => root.msAccelProfile = key }
                NComboBox { Layout.fillWidth: true; label: panel.tr("input.scroll-method", "Scroll method"); model: root.scrollMethods; currentKey: root.msScrollMethod; onSelected: key => root.msScrollMethod = key }
            }

            NDivider { Layout.fillWidth: true }

            // General
            NText { text: panel.tr("input.general", "General"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NComboBox { Layout.fillWidth: true; label: panel.tr("input.mod-key", "Mod key"); model: root.modKeys; currentKey: root.modKey; onSelected: key => root.modKey = key }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.ffm", "Focus follows mouse"); checked: root.focusFollowsMouse; onToggled: v => root.focusFollowsMouse = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.warp", "Warp mouse to focus"); checked: root.warpMouse; onToggled: v => root.warpMouse = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.ws-baf", "Workspace back-and-forth"); checked: root.wsBackAndForth; onToggled: v => root.wsBackAndForth = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("input.power-key", "Disable power key handling"); checked: root.disablePowerKey; onToggled: v => root.disablePowerKey = v }
        }
    }
}
