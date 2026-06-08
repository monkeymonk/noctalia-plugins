import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import "../lib/binds.js" as Binds
import "../Components"
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var panel: null
    property var configModel: null

    property var owner: null          // { path, node, doc }
    property var bindModels: []       // [{combo, attrs, actions, disabled, node}]
    property string filter: ""
    property var pendingDelete: null
    property string sectionFile: owner ? owner.path : ""

    spacing: Style.marginM

    function recompute() {
        owner = (configModel && configModel.loaded) ? configModel.owner("binds") : null;
        bindModels = owner ? Binds.parseBinds(owner.node) : [];
    }

    Component.onCompleted: recompute()
    Connections {
        target: root.configModel
        function onLoadFinished() { root.recompute(); }
    }

    function fileText() { return owner ? configModel.textOf(owner.path) : ""; }
    function padTo() { return Binds.alignColumnFor(bindModels); }
    function shortPath() { return owner ? owner.path.replace(configModel.home, "~") : ""; }

    function matches(b) {
        if (!filter) return true;
        var f = filter.toLowerCase();
        return b.combo.toLowerCase().indexOf(f) !== -1 || Binds.describeBind(b).toLowerCase().indexOf(f) !== -1;
    }

    // ----- mutations (produce new file text, route through panel.requestSave) -----

    function addBind(bind) {
        var line = Binds.serializeBind(bind, { padTo: padTo() });
        var text = Kdl.insertChildLine(fileText(), owner.node, line);
        panel.requestSave(owner.path, text, panel.tr("summary.add", "new shortcut {c}", { c: bind.combo }));
    }
    function updateBind(node, bind) {
        var src = fileText();
        var indent = Kdl.leadingIndent(src, node.range);
        var line = Binds.serializeBind(bind, { padTo: padTo() });
        var text = Kdl.replaceNodeLine(src, node, indent + line);
        panel.requestSave(owner.path, text, panel.tr("summary.edit", "shortcut {c}", { c: bind.combo }));
    }
    function deleteBind(b) {
        var text = Kdl.removeNodeLine(fileText(), b.node);
        panel.requestSave(owner.path, text, panel.tr("summary.delete", "delete {c}", { c: b.combo }));
    }
    function toggleBind(b) {
        var text = Kdl.setDisabled(fileText(), b.node, !b.disabled);
        panel.requestSave(owner.path, text,
            (b.disabled ? panel.tr("summary.enable", "enable {c}", { c: b.combo })
                        : panel.tr("summary.disable", "disable {c}", { c: b.combo })));
    }

    // ----- header -----
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NText {
            text: panel.tr("shortcuts.count", "{n} shortcuts", { n: root.bindModels.length })
            font.weight: Style.fontWeightBold
        }
        Item { Layout.fillWidth: true }
        NButton {
            icon: "plus"
            text: panel.tr("action.add-shortcut", "Add")
            enabled: root.owner !== null
            onClicked: bindEditor.openCreate(root.bindModels)
        }
    }
    NText {
        visible: root.owner === null
        Layout.fillWidth: true
        text: panel.tr("shortcuts.none", "No binds {} block found in your config.")
        color: Color.mError
        wrapMode: Text.WordWrap
    }

    // ----- search -----
    NTextInput {
        Layout.fillWidth: true
        visible: root.owner !== null
        placeholderText: panel.tr("shortcuts.search", "Filter shortcuts…")
        onTextChanged: root.filter = text
    }

    // ----- list -----
    NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        ColumnLayout {
            width: parent.width
            spacing: Style.marginXS
            Repeater {
                model: root.bindModels
                delegate: Rectangle {
                    Layout.fillWidth: true
                    visible: root.matches(modelData)
                    implicitHeight: visible ? (rowL.implicitHeight + Style.marginS * 2) : 0
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    opacity: modelData.disabled ? 0.5 : 1.0

                    RowLayout {
                        id: rowL
                        anchors.fill: parent
                        anchors.margins: Style.marginS
                        spacing: Style.marginM

                        Rectangle {
                            Layout.preferredWidth: 150 * Style.uiScaleRatio
                            implicitHeight: comboT.implicitHeight + Style.marginXS * 2
                            radius: Style.radiusS
                            color: Color.mSurface
                            border.color: Color.mOutline
                            border.width: 1
                            NText {
                                id: comboT
                                anchors.centerIn: parent
                                width: parent.width - Style.marginS
                                text: modelData.combo
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font.family: "monospace"
                                font.pointSize: Style.fontSizeS
                            }
                        }
                        NText {
                            Layout.fillWidth: true
                            text: (modelData.attrs && modelData.attrs["hotkey-overlay-title"]) || Binds.describeBind(modelData)
                            elide: Text.ElideRight
                            font.strikeout: modelData.disabled
                        }
                        NIconButton {
                            icon: modelData.disabled ? "eye-off" : "eye"
                            tooltipText: modelData.disabled ? panel.tr("action.enable", "Enable") : panel.tr("action.disable", "Disable")
                            onClicked: root.toggleBind(modelData)
                        }
                        NIconButton {
                            icon: "edit"
                            tooltipText: panel.tr("action.edit", "Edit")
                            onClicked: bindEditor.openEdit(modelData, root.bindModels)
                        }
                        NIconButton {
                            icon: "trash"
                            tooltipText: panel.tr("action.delete", "Delete")
                            onClicked: { root.pendingDelete = modelData; confirmDelete.open(); }
                        }
                    }
                }
            }
        }
    }

    BindEditor {
        id: bindEditor
        panel: root.panel
        configModel: root.configModel
        onAccepted: (node, bind) => {
            if (node) root.updateBind(node, bind);
            else root.addBind(bind);
        }
    }

    Popup {
        id: confirmDelete
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 380; padding: Style.marginL
        background: Rectangle { color: Color.mSurface; radius: Style.radiusM; border.color: Color.mError; border.width: 1 }
        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM
            NText {
                Layout.fillWidth: true
                text: panel.tr("shortcuts.confirm-del", "Delete shortcut {c}?", { c: root.pendingDelete ? root.pendingDelete.combo : "" })
                font.weight: Style.fontWeightBold; color: Color.mError; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                NButton { text: panel.tr("action.cancel", "Cancel"); onClicked: confirmDelete.close() }
                NButton {
                    text: panel.tr("action.delete", "Delete")
                    backgroundColor: Color.mError; textColor: Color.mOnError
                    onClicked: { var b = root.pendingDelete; confirmDelete.close(); if (b) root.deleteBind(b); }
                }
            }
        }
    }
}
