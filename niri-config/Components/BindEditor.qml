import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/keys.js" as KeyMap
import "../lib/binds.js" as Binds
import "../lib/desktop.js" as Desktop
import qs.Commons
import qs.Widgets

// Add/edit a single niri bind. Emits accepted(editNode, bind):
//   editNode === null  → create; else → replace that node.
Item {
    id: root

    property var panel: null
    property var configModel: null
    property var existingBinds: []
    property var editNode: null

    // working state
    property string combo: ""
    property string actionName: ""
    property string actionArgType: "none"
    property string actionArg: ""
    property string command: ""
    property string titleAttr: ""
    property bool repeatOff: false
    property bool allowWhenLocked: false
    property bool recording: false
    property var tailActions: []        // 2nd+ actions of a multi-action bind, preserved verbatim

    signal accepted(var editNode, var bind)

    function tr(k, f, p) { return panel ? panel.tr(k, f, p) : f; }

    readonly property bool isSpawn: actionName === "spawn" || actionName === "spawn-sh"
    readonly property var conflict: combo ? Binds.findConflict(existingBinds, combo, editNode) : null

    function reset() {
        combo = ""; actionName = ""; actionArgType = "none"; actionArg = "";
        command = ""; titleAttr = ""; repeatOff = false; allowWhenLocked = false; recording = false;
        tailActions = [];
    }

    function openCreate(binds) {
        reset(); editNode = null; existingBinds = binds || [];
        popup.open();
    }

    function openEdit(b, binds) {
        reset(); editNode = b.node; existingBinds = binds || [];
        combo = b.combo;
        var a = (b.actions && b.actions[0]) || { name: "", args: [] };
        tailActions = (b.actions && b.actions.length > 1) ? b.actions.slice(1) : [];
        actionName = a.name;
        var spec = Binds.actionSpec(a.name);
        actionArgType = spec ? spec.arg : (a.args && a.args.length ? "string" : "none");
        if (a.name === "spawn" || a.name === "spawn-sh") command = (a.args || []).join(" ");
        else actionArg = (a.args && a.args.length) ? String(a.args[0]) : "";
        titleAttr = b.attrs["hotkey-overlay-title"] || "";
        repeatOff = b.attrs.repeat === false;
        allowWhenLocked = b.attrs["allow-when-locked"] === true;
        popup.open();
    }

    function buildBind() {
        var attrs = {};
        if (titleAttr) attrs["hotkey-overlay-title"] = titleAttr;
        if (repeatOff) attrs.repeat = false;
        if (allowWhenLocked) attrs["allow-when-locked"] = true;
        var action;
        if (isSpawn) {
            action = Desktop.commandToAction(command) || { name: "spawn", args: [] };
        } else if (actionArgType !== "none" && actionArg !== "") {
            var v = /^-?\d+$/.test(actionArg) ? Number(actionArg) : actionArg;
            action = { name: actionName, args: [v] };
        } else {
            action = { name: actionName, args: [] };
        }
        return { combo: combo, attrs: attrs, actions: [action].concat(tailActions || []), disabled: false };
    }

    readonly property bool canSave: combo !== "" && actionName !== "" && (!isSpawn || command !== "")

    visible: false

    ActionPicker {
        id: actionPicker
        panel: root.panel
        onPicked: (name, argType) => {
            root.actionName = name;
            root.actionArgType = argType;
            if (name !== "spawn" && name !== "spawn-sh") root.command = "";
            root.actionArg = "";
        }
    }
    AppPicker {
        id: appPicker
        panel: root.panel
        onPicked: (cmd) => { root.command = cmd; }
    }

    Popup {
        id: popup
        modal: true
        focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - Style.marginXL : 560, 560)
        padding: Style.marginL
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mPrimary; border.width: 1 }
        onClosed: root.recording = false

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            NText {
                text: root.editNode ? root.tr("bindeditor.edit", "Edit shortcut") : root.tr("bindeditor.add", "Add shortcut")
                font.pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
            }

            // ----- combo -----
            NText { text: root.tr("bindeditor.combo", "Key combination"); font.weight: Style.fontWeightMedium }
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                NTextInput {
                    id: comboInput
                    Layout.fillWidth: true
                    text: root.combo
                    placeholderText: root.tr("bindeditor.combo-ph", "e.g. Mod+Shift+T")
                    onTextChanged: if (!root.recording) root.combo = text
                }
                NButton {
                    text: root.recording ? root.tr("bindeditor.recording", "Press keys…") : root.tr("action.capture", "Capture")
                    backgroundColor: root.recording ? Color.mError : Color.mPrimary
                    textColor: root.recording ? Color.mOnError : Color.mOnPrimary
                    onClicked: { root.recording = true; captureArea.forceActiveFocus(); }
                }
                NIconButton {
                    icon: "keyboard"
                    tooltipText: root.tr("bindeditor.special", "Special key")
                    onClicked: specialMenu.open()
                }
            }

            // Hidden focus catcher for live key capture (QML Keys vs KeyMap import)
            Item {
                id: captureArea
                width: 1; height: 1
                Keys.onPressed: event => {
                    if (!root.recording) return;
                    event.accepted = true;
                    if (event.key === Qt.Key_Escape) { root.recording = false; return; }
                    var c = KeyMap.comboFromEvent(event.key, event.modifiers, event.text);
                    if (c) {
                        root.combo = c;
                        comboInput.text = c;
                        root.recording = false;
                    }
                }
            }

            NText {
                visible: root.conflict !== null
                Layout.fillWidth: true
                text: root.tr("bindeditor.conflict", "⚠ Already bound: {desc}", { desc: root.conflict ? Binds.describeBind(root.conflict) : "" })
                color: Color.mError
                font.pointSize: Style.fontSizeS
                wrapMode: Text.WordWrap
            }

            NDivider { Layout.fillWidth: true }

            // ----- action -----
            NText { text: root.tr("bindeditor.action", "Action"); font.weight: Style.fontWeightMedium }
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: actT.implicitHeight + Style.marginS * 2
                    radius: Style.radiusS
                    color: Color.mSurfaceVariant
                    NText {
                        id: actT
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.marginS
                        width: parent.width - Style.marginM
                        text: root.actionName ? root.actionName.replace(/-/g, " ") : root.tr("bindeditor.no-action", "(choose an action)")
                        color: root.actionName ? Color.mOnSurface : Color.mOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
                NButton {
                    text: root.tr("bindeditor.choose-action", "Choose")
                    onClicked: actionPicker.open()
                }
            }

            // spawn command
            RowLayout {
                Layout.fillWidth: true
                visible: root.isSpawn
                spacing: Style.marginS
                NTextInput {
                    Layout.fillWidth: true
                    text: root.command
                    placeholderText: root.tr("bindeditor.command-ph", "command to run")
                    onTextChanged: root.command = text
                }
                NButton {
                    text: root.tr("bindeditor.pick-app", "Pick app")
                    onClicked: appPicker.open()
                }
            }

            // generic arg
            NTextInput {
                Layout.fillWidth: true
                visible: !root.isSpawn && root.actionArgType !== "none"
                text: root.actionArg
                placeholderText: root.actionArgType === "amount" ? "e.g. -10% or +10%"
                    : (root.actionArgType === "workspaceRef" ? root.tr("bindeditor.arg-ws", "workspace number or name")
                       : root.tr("bindeditor.arg", "argument"))
                onTextChanged: root.actionArg = text
            }

            NText {
                visible: (root.tailActions || []).length > 0
                Layout.fillWidth: true
                text: root.tr("bindeditor.tail", "+ {n} more action(s) in this bind are preserved.", { n: (root.tailActions || []).length })
                color: Color.mOnSurfaceVariant
                font.pointSize: Style.fontSizeS
                wrapMode: Text.WordWrap
            }

            NDivider { Layout.fillWidth: true }

            // ----- attributes -----
            NTextInput {
                Layout.fillWidth: true
                label: root.tr("bindeditor.title-attr", "Overlay title (optional)")
                text: root.titleAttr
                placeholderText: root.tr("bindeditor.title-ph", "shown in the hotkey overlay")
                onTextChanged: root.titleAttr = text
            }
            NToggle {
                Layout.fillWidth: true
                label: root.tr("bindeditor.repeat-off", "Disable key repeat")
                checked: root.repeatOff
                onToggled: v => root.repeatOff = v
            }
            NToggle {
                Layout.fillWidth: true
                label: root.tr("bindeditor.allow-locked", "Allow when screen locked")
                checked: root.allowWhenLocked
                onToggled: v => root.allowWhenLocked = v
            }

            // ----- actions -----
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                Item { Layout.fillWidth: true }
                NButton {
                    text: root.tr("action.cancel", "Cancel")
                    onClicked: popup.close()
                }
                NButton {
                    text: root.tr("action.save", "Save")
                    backgroundColor: Color.mPrimary
                    textColor: Color.mOnPrimary
                    enabled: root.canSave
                    onClicked: { var b = root.buildBind(); popup.close(); root.accepted(root.editNode, b); }
                }
            }
        }

        // Special-key menu
        Popup {
            id: specialMenu
            modal: true
            focus: true
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: 320
            height: 380
            padding: Style.marginM
            background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mOutline; border.width: 1 }
            NScrollView {
                anchors.fill: parent
                ColumnLayout {
                    width: parent.width
                    spacing: Style.marginXS
                    Repeater {
                        model: KeyMap.SPECIAL_KEYS
                        delegate: NButton {
                            Layout.fillWidth: true
                            text: modelData.token
                            outlined: true
                            horizontalAlignment: Qt.AlignLeft
                            onClicked: { root.combo = modelData.token; comboInput.text = modelData.token; specialMenu.close(); }
                        }
                    }
                }
            }
        }
    }
}
