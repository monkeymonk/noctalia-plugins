import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import qs.Commons
import qs.Widgets

// Animations editor. Global disable/slowdown, plus per-event enable (toggles
// `off`, preserving the spring/curve tuning) and duration-ms/curve for
// easing-based events. Surgical, gated saves.
ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

    property string animPath: ""
    property string sectionFile: animPath
    property var events: []          // [{ name, disabled, isSpring, durationMs, curve }]
    property bool globalOff: false
    property string slowdown: ""
    property bool origGlobalOff: false
    property string origSlowdown: ""

    readonly property var knownEvents: ["workspace-switch", "window-open", "window-close",
        "horizontal-view-movement", "window-movement", "window-resize",
        "config-notification-open-close", "screenshot-ui-open", "overview-open-close"]
    readonly property var curves: ["ease-out-quad", "ease-out-cubic", "ease-out-expo", "linear", "ease-in-out-cubic"]

    spacing: Style.marginM

    function childNamed(node, name) {
        var k = node && node.children ? node.children : [];
        for (var i = 0; i < k.length; i++) if (k[i].name === name) return k[i];
        return null;
    }
    function animNode(text) { return Kdl.findNode(Kdl.parse(text), "animations"); }

    function recompute() {
        if (!(configModel && configModel.loaded)) return;
        var own = configModel.owner("animations");
        if (!own) { animPath = ""; events = []; return; }
        animPath = own.path;
        var A = own.node;
        globalOff = !!childNamed(A, "off");
        var sd = childNamed(A, "slowdown");
        slowdown = (sd && sd.args[0]) ? String(sd.args[0].value) : "";
        origGlobalOff = globalOff; origSlowdown = slowdown;

        var evs = [];
        knownEvents.forEach(function (name) {
            var e = childNamed(A, name);
            if (!e) { evs.push({ name: name, present: false, disabled: false, isSpring: false, durationMs: "", curve: "ease-out-quad" }); return; }
            var dm = childNamed(e, "duration-ms");
            var cv = childNamed(e, "curve");
            var sp = childNamed(e, "spring");
            function sprop(k) { return (sp && sp.props && sp.props[k] != null) ? String(sp.props[k]) : ""; }
            evs.push({
                name: name, present: true,
                disabled: !!childNamed(e, "off"),
                isSpring: !!sp,
                durationMs: (dm && dm.args[0]) ? String(dm.args[0].value) : "",
                curve: (cv && cv.args[0]) ? String(cv.args[0].value) : "ease-out-quad",
                springDamping: sprop("damping-ratio"), springStiffness: sprop("stiffness"), springEpsilon: sprop("epsilon")
            });
        });
        events = evs;
    }

    Component.onCompleted: recompute()
    Connections { target: root.configModel; function onLoadFinished() { root.recompute(); } }

    // ---- surgical helpers rooted at "animations" ----
    function ensureBlock(text, pathArr) {
        if (!Kdl.findNode(Kdl.parse(text), "animations")) text = Kdl.appendNode(text, "animations {\n}");
        for (var i = 0; i < pathArr.length; i++) {
            var cur = Kdl.findNode(Kdl.parse(text), "animations");
            for (var j = 0; cur && j < i; j++) cur = childNamed(cur, pathArr[j]);
            if (cur && !childNamed(cur, pathArr[i])) text = Kdl.insertChildLine(text, cur, pathArr[i] + " {\n}");
        }
        return text;
    }
    function findBlock(text, pathArr) {
        var cur = Kdl.findNode(Kdl.parse(text), "animations");
        for (var i = 0; cur && i < pathArr.length; i++) cur = childNamed(cur, pathArr[i]);
        return cur;
    }
    function setFlag(text, pathArr, name, on) {
        var b = findBlock(text, pathArr); var ex = b ? childNamed(b, name) : null;
        if (!on) return ex ? Kdl.removeNodeLine(text, ex) : text;
        text = ensureBlock(text, pathArr);
        var b2 = findBlock(text, pathArr);
        return childNamed(b2, name) ? text : Kdl.insertChildLine(text, b2, name);
    }
    function setLine(text, pathArr, name, line) {
        var b = findBlock(text, pathArr); var ex = b ? childNamed(b, name) : null;
        if (line === null) return ex ? Kdl.removeNodeLine(text, ex) : text;
        if (ex) return Kdl.replaceNodeLine(text, ex, Kdl.leadingIndent(text, ex.range) + line);
        text = ensureBlock(text, pathArr);
        return Kdl.insertChildLine(text, findBlock(text, pathArr), line);
    }

    function saveGlobal() {
        var t = configModel.textOf(animPath);
        if (globalOff !== origGlobalOff) t = setFlag(t, [], "off", globalOff);
        if (slowdown !== origSlowdown) t = setLine(t, [], "slowdown", (slowdown === "" || isNaN(parseFloat(slowdown))) ? null : ("slowdown " + parseFloat(slowdown)));
        panel.requestSave(animPath, t, panel.tr("anim.summary-global", "animation settings"));
    }
    function saveEvent(ev, enabled, durationMs, curve, damping, stiffness, epsilon) {
        var t = configModel.textOf(animPath);
        t = setFlag(t, [ev.name], "off", !enabled);
        if (enabled && ev.isSpring) {
            if (damping !== "" && stiffness !== "" && epsilon !== "")
                t = setLine(t, [ev.name], "spring", "spring damping-ratio=" + parseFloat(damping) + " stiffness=" + parseFloat(stiffness) + " epsilon=" + parseFloat(epsilon));
        } else if (enabled) {
            t = setLine(t, [ev.name], "duration-ms", (durationMs === "" || isNaN(parseInt(durationMs))) ? null : ("duration-ms " + parseInt(durationMs)));
            t = setLine(t, [ev.name], "curve", curve ? ('curve "' + curve + '"') : null);
        }
        panel.requestSave(animPath, t, panel.tr("anim.summary-event", "{n} animation", { n: ev.name }));
    }

    // ---- UI ----
    NText { text: panel.tr("section.animation", "Animation"); font.weight: Style.fontWeightBold }
    NText { visible: root.animPath === ""; text: panel.tr("anim.none", "No animations {} block found."); color: Color.mError }

    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginM

            // global
            Rectangle {
                Layout.fillWidth: true
                radius: Style.radiusM
                color: Color.mSurfaceVariant
                implicitHeight: gCol.implicitHeight + Style.marginM * 2
                ColumnLayout {
                    id: gCol
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginS
                    NText { text: panel.tr("anim.global", "Global"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
                    NToggle { Layout.fillWidth: true; label: panel.tr("anim.off", "Disable all animations"); checked: root.globalOff; onToggled: v => root.globalOff = v }
                    NTextInput { Layout.fillWidth: true; label: panel.tr("anim.slowdown", "Slowdown (1.0 = normal)"); text: root.slowdown; placeholderText: "1.0"; onTextChanged: root.slowdown = text }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        NButton {
                            text: panel.tr("input.save", "Save changes")
                            backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                            enabled: root.animPath !== "" && (root.globalOff !== root.origGlobalOff || root.slowdown !== root.origSlowdown)
                            onClicked: root.saveGlobal()
                        }
                    }
                }
            }

            // per-event
            Repeater {
                model: root.events
                delegate: Rectangle {
                    Layout.fillWidth: true
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    implicitHeight: eCol.implicitHeight + Style.marginM * 2
                    property bool edEnabled: !modelData.disabled
                    property string edDuration: modelData.durationMs
                    property string edCurve: modelData.curve
                    property string edDamping: modelData.springDamping
                    property string edStiffness: modelData.springStiffness
                    property string edEpsilon: modelData.springEpsilon
                    ColumnLayout {
                        id: eCol
                        anchors.fill: parent
                        anchors.margins: Style.marginM
                        spacing: Style.marginS
                        RowLayout {
                            Layout.fillWidth: true
                            NText { Layout.fillWidth: true; text: modelData.name; font.weight: Style.fontWeightMedium }
                            NText {
                                text: modelData.isSpring ? "spring" : (modelData.present ? "easing" : "default")
                                color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS
                            }
                        }
                        NToggle { Layout.fillWidth: true; label: panel.tr("anim.enabled", "Enabled"); checked: edEnabled; onToggled: v => edEnabled = v }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: !modelData.isSpring && edEnabled
                            spacing: Style.marginS
                            NTextInput { Layout.fillWidth: true; label: panel.tr("anim.duration", "Duration (ms)"); text: edDuration; placeholderText: "200"; onTextChanged: edDuration = text }
                            NComboBox {
                                Layout.fillWidth: true
                                label: panel.tr("anim.curve", "Curve")
                                model: root.curves.map(function (c) { return { key: c, name: c }; })
                                currentKey: edCurve
                                onSelected: key => edCurve = key
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: modelData.isSpring && edEnabled
                            spacing: Style.marginXS
                            RowLayout {
                                Layout.fillWidth: true; spacing: Style.marginS
                                NTextInput { Layout.fillWidth: true; label: panel.tr("anim.damping", "Damping ratio"); text: edDamping; placeholderText: "1.0"; onTextChanged: edDamping = text }
                                NTextInput { Layout.fillWidth: true; label: panel.tr("anim.stiffness", "Stiffness"); text: edStiffness; placeholderText: "1000"; onTextChanged: edStiffness = text }
                                NTextInput { Layout.fillWidth: true; label: panel.tr("anim.epsilon", "Epsilon"); text: edEpsilon; placeholderText: "0.0001"; onTextChanged: edEpsilon = text }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            NButton {
                                text: panel.tr("action.save", "Save")
                                backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
                                enabled: root.animPath !== ""
                                onClicked: root.saveEvent(modelData, edEnabled, edDuration, edCurve, edDamping, edStiffness, edEpsilon)
                            }
                        }
                    }
                }
            }
        }
    }
}
