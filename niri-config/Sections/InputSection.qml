import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import qs.Commons
import qs.Widgets

// Input editor: keyboard / touchpad / mouse / general. Covers the documented
// niri input options (device sub-blocks like tablet/trackpoint and xkb rules/
// file are left to the "Edit file" button). Surgical batched save — only changed
// settings are touched, preserving comments and untouched lines.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

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

    // ---- kdl helpers ----
    function childNamed(node, name) {
        var k = node && node.children ? node.children : [];
        for (var i = 0; i < k.length; i++) if (k[i].name === name) return k[i];
        return null;
    }
    function findBlock(text, pathArr) {
        var cur = Kdl.findNode(Kdl.parse(text), "input");
        for (var i = 0; cur && i < pathArr.length; i++) cur = childNamed(cur, pathArr[i]);
        return cur;
    }
    function flagOf(node, name) { return !!childNamed(node, name); }
    // bool-valued node (e.g. `drag true`): value if present, true if bare, false if absent
    function boolOf(node, name) { var c = childNamed(node, name); if (!c) return false; return c.args[0] ? (c.args[0].value === true) : true; }
    function strOf(node, name) { var c = childNamed(node, name); return (c && c.args[0]) ? String(c.args[0].value) : ""; }

    function recompute() {
        if (!(configModel && configModel.loaded)) return;
        var own = configModel.owner("input");
        if (!own) { inputPath = ""; return; }
        inputPath = own.path;
        var input = own.node;
        var kb = childNamed(input, "keyboard");
        var xkb = kb ? childNamed(kb, "xkb") : null;
        var tp = childNamed(input, "touchpad");
        var ms = childNamed(input, "mouse");

        layout = xkb ? strOf(xkb, "layout") : "";
        variant = xkb ? strOf(xkb, "variant") : "";
        options = xkb ? strOf(xkb, "options") : "";
        model = xkb ? strOf(xkb, "model") : "";
        trackLayout = kb ? strOf(kb, "track-layout") : "";
        numlock = kb ? flagOf(kb, "numlock") : false;
        repeatDelay = kb ? strOf(kb, "repeat-delay") : "";
        repeatRate = kb ? strOf(kb, "repeat-rate") : "";

        tpOff = tp ? flagOf(tp, "off") : false;
        tpTap = tp ? flagOf(tp, "tap") : false;
        tpDwt = tp ? flagOf(tp, "dwt") : false;
        tpDwtp = tp ? flagOf(tp, "dwtp") : false;
        tpNatural = tp ? flagOf(tp, "natural-scroll") : false;
        tpDrag = tp ? boolOf(tp, "drag") : false;
        tpDragLock = tp ? flagOf(tp, "drag-lock") : false;
        tpMiddleEmu = tp ? flagOf(tp, "middle-emulation") : false;
        tpLeftHanded = tp ? flagOf(tp, "left-handed") : false;
        tpDisabledExt = tp ? flagOf(tp, "disabled-on-external-mouse") : false;
        tpAccel = tp ? strOf(tp, "accel-speed") : "";
        tpAccelProfile = tp ? strOf(tp, "accel-profile") : "";
        tpScrollMethod = tp ? strOf(tp, "scroll-method") : "";
        tpClickMethod = tp ? strOf(tp, "click-method") : "";
        tpTapButtonMap = tp ? strOf(tp, "tap-button-map") : "";

        msOff = ms ? flagOf(ms, "off") : false;
        msNatural = ms ? flagOf(ms, "natural-scroll") : false;
        msMiddleEmu = ms ? flagOf(ms, "middle-emulation") : false;
        msLeftHanded = ms ? flagOf(ms, "left-handed") : false;
        msAccel = ms ? strOf(ms, "accel-speed") : "";
        msAccelProfile = ms ? strOf(ms, "accel-profile") : "";
        msScrollMethod = ms ? strOf(ms, "scroll-method") : "";

        focusFollowsMouse = flagOf(input, "focus-follows-mouse");
        warpMouse = flagOf(input, "warp-mouse-to-focus");
        wsBackAndForth = flagOf(input, "workspace-auto-back-and-forth");
        disablePowerKey = flagOf(input, "disable-power-key-handling");
        modKey = strOf(input, "mod-key");

        orig = snapshot();
    }
    function snapshot() {
        return {
            layout: layout, variant: variant, options: options, model: model, trackLayout: trackLayout,
            numlock: numlock, repeatDelay: repeatDelay, repeatRate: repeatRate,
            tpOff: tpOff, tpTap: tpTap, tpDwt: tpDwt, tpDwtp: tpDwtp, tpNatural: tpNatural, tpDrag: tpDrag,
            tpDragLock: tpDragLock, tpMiddleEmu: tpMiddleEmu, tpLeftHanded: tpLeftHanded, tpDisabledExt: tpDisabledExt,
            tpAccel: tpAccel, tpAccelProfile: tpAccelProfile, tpScrollMethod: tpScrollMethod, tpClickMethod: tpClickMethod, tpTapButtonMap: tpTapButtonMap,
            msOff: msOff, msNatural: msNatural, msMiddleEmu: msMiddleEmu, msLeftHanded: msLeftHanded,
            msAccel: msAccel, msAccelProfile: msAccelProfile, msScrollMethod: msScrollMethod,
            focusFollowsMouse: focusFollowsMouse, warpMouse: warpMouse, wsBackAndForth: wsBackAndForth,
            disablePowerKey: disablePowerKey, modKey: modKey
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

    // ---- surgical ops ----
    function ensureBlock(text, pathArr) {
        if (!Kdl.findNode(Kdl.parse(text), "input")) text = Kdl.appendNode(text, "input {\n}");
        for (var i = 0; i < pathArr.length; i++) {
            var cur = Kdl.findNode(Kdl.parse(text), "input");
            for (var j = 0; cur && j < i; j++) cur = childNamed(cur, pathArr[j]);
            if (cur && !childNamed(cur, pathArr[i])) text = Kdl.insertChildLine(text, cur, pathArr[i] + " {\n}");
        }
        return text;
    }
    function existing(text, pathArr, name) { var b = findBlock(text, pathArr); return b ? childNamed(b, name) : null; }
    function setFlag(text, pathArr, name, on) {
        if (!on) { var ex0 = existing(text, pathArr, name); return ex0 ? Kdl.removeNodeLine(text, ex0) : text; }
        text = ensureBlock(text, pathArr);
        var block = findBlock(text, pathArr);
        return childNamed(block, name) ? text : Kdl.insertChildLine(text, block, name);
    }
    function setLine(text, pathArr, name, line) {
        var ex0 = existing(text, pathArr, name);
        if (line === null) return ex0 ? Kdl.removeNodeLine(text, ex0) : text;
        if (ex0) return Kdl.replaceNodeLine(text, ex0, Kdl.leadingIndent(text, ex0.range) + line);
        text = ensureBlock(text, pathArr);
        return Kdl.insertChildLine(text, findBlock(text, pathArr), line);
    }
    function setStr(text, pathArr, name, val) { return setLine(text, pathArr, name, val ? (name + ' "' + val + '"') : null); }
    function setBool(text, pathArr, name, val) { return setLine(text, pathArr, name, name + " " + (val ? "true" : "false")); }
    function setNum(text, pathArr, name, val) { return setLine(text, pathArr, name, (val === "" || isNaN(parseInt(val))) ? null : (name + " " + parseInt(val))); }
    function setFloat(text, pathArr, name, val) { return setLine(text, pathArr, name, (val === "" || isNaN(parseFloat(val))) ? null : (name + " " + parseFloat(val))); }

    function save() {
        var t = configModel.textOf(inputPath);
        var o = orig;
        if (layout !== o.layout) t = setStr(t, ["keyboard", "xkb"], "layout", layout);
        if (variant !== o.variant) t = setStr(t, ["keyboard", "xkb"], "variant", variant);
        if (options !== o.options) t = setStr(t, ["keyboard", "xkb"], "options", options);
        if (model !== o.model) t = setStr(t, ["keyboard", "xkb"], "model", model);
        if (trackLayout !== o.trackLayout) t = setStr(t, ["keyboard"], "track-layout", trackLayout);
        if (numlock !== o.numlock) t = setFlag(t, ["keyboard"], "numlock", numlock);
        if (repeatDelay !== o.repeatDelay) t = setNum(t, ["keyboard"], "repeat-delay", repeatDelay);
        if (repeatRate !== o.repeatRate) t = setNum(t, ["keyboard"], "repeat-rate", repeatRate);

        if (tpOff !== o.tpOff) t = setFlag(t, ["touchpad"], "off", tpOff);
        if (tpTap !== o.tpTap) t = setFlag(t, ["touchpad"], "tap", tpTap);
        if (tpDwt !== o.tpDwt) t = setFlag(t, ["touchpad"], "dwt", tpDwt);
        if (tpDwtp !== o.tpDwtp) t = setFlag(t, ["touchpad"], "dwtp", tpDwtp);
        if (tpNatural !== o.tpNatural) t = setFlag(t, ["touchpad"], "natural-scroll", tpNatural);
        if (tpDrag !== o.tpDrag) t = setBool(t, ["touchpad"], "drag", tpDrag);
        if (tpDragLock !== o.tpDragLock) t = setFlag(t, ["touchpad"], "drag-lock", tpDragLock);
        if (tpMiddleEmu !== o.tpMiddleEmu) t = setFlag(t, ["touchpad"], "middle-emulation", tpMiddleEmu);
        if (tpLeftHanded !== o.tpLeftHanded) t = setFlag(t, ["touchpad"], "left-handed", tpLeftHanded);
        if (tpDisabledExt !== o.tpDisabledExt) t = setFlag(t, ["touchpad"], "disabled-on-external-mouse", tpDisabledExt);
        if (tpAccel !== o.tpAccel) t = setFloat(t, ["touchpad"], "accel-speed", tpAccel);
        if (tpAccelProfile !== o.tpAccelProfile) t = setStr(t, ["touchpad"], "accel-profile", tpAccelProfile);
        if (tpScrollMethod !== o.tpScrollMethod) t = setStr(t, ["touchpad"], "scroll-method", tpScrollMethod);
        if (tpClickMethod !== o.tpClickMethod) t = setStr(t, ["touchpad"], "click-method", tpClickMethod);
        if (tpTapButtonMap !== o.tpTapButtonMap) t = setStr(t, ["touchpad"], "tap-button-map", tpTapButtonMap);

        if (msOff !== o.msOff) t = setFlag(t, ["mouse"], "off", msOff);
        if (msNatural !== o.msNatural) t = setFlag(t, ["mouse"], "natural-scroll", msNatural);
        if (msMiddleEmu !== o.msMiddleEmu) t = setFlag(t, ["mouse"], "middle-emulation", msMiddleEmu);
        if (msLeftHanded !== o.msLeftHanded) t = setFlag(t, ["mouse"], "left-handed", msLeftHanded);
        if (msAccel !== o.msAccel) t = setFloat(t, ["mouse"], "accel-speed", msAccel);
        if (msAccelProfile !== o.msAccelProfile) t = setStr(t, ["mouse"], "accel-profile", msAccelProfile);
        if (msScrollMethod !== o.msScrollMethod) t = setStr(t, ["mouse"], "scroll-method", msScrollMethod);

        if (focusFollowsMouse !== o.focusFollowsMouse) t = setFlag(t, [], "focus-follows-mouse", focusFollowsMouse);
        if (warpMouse !== o.warpMouse) t = setFlag(t, [], "warp-mouse-to-focus", warpMouse);
        if (wsBackAndForth !== o.wsBackAndForth) t = setFlag(t, [], "workspace-auto-back-and-forth", wsBackAndForth);
        if (disablePowerKey !== o.disablePowerKey) t = setFlag(t, [], "disable-power-key-handling", disablePowerKey);
        if (modKey !== o.modKey) t = setStr(t, [], "mod-key", modKey);

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
                NTextInput { Layout.fillWidth: true; label: panel.tr("input.layout", "Layout"); text: root.layout; placeholderText: "us"; onTextChanged: root.layout = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("input.variant", "Variant"); text: root.variant; placeholderText: "intl"; onTextChanged: root.variant = text }
            }
            NTextInput { Layout.fillWidth: true; label: panel.tr("input.options", "XKB options"); text: root.options; placeholderText: "compose:ralt,ctrl:nocaps"; onTextChanged: root.options = text }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("input.model", "XKB model"); text: root.model; placeholderText: "pc104"; onTextChanged: root.model = text }
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
