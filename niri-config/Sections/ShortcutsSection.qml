import QtQuick
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import "../lib/binds.js" as Binds
import "../lib/scripts.js" as Scripts
import "../Components"
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    required property var panel
    required property var configModel

    property var owner: null          // { path, doc, nodes }
    property var bindModels: []       // [{combo, attrs, actions, disabled, node, desc}]
    property string filter: ""
    property string sectionFile: owner ? owner.path : ""

    // Filtered view fed to the Repeater: an excluded bind costs no delegate.
    readonly property var visibleBinds: root.filterBinds(root.bindModels, root.filter)
    readonly property var emptyBind: ({ combo: "", desc: "", attrs: null, actions: [], disabled: false, node: null, path: "" })

    spacing: Style.marginM

    function recompute() {
        owner = (configModel && configModel.loaded) ? configModel.ownerOf("binds") : null;
        var parsed = owner ? Binds.parseBinds(owner.nodes[0]) : [];
        for (var i = 0; i < parsed.length; i++) {
            parsed[i].desc = Binds.describeBind(parsed[i]);
            parsed[i].path = owner.path;
        }
        bindModels = reconcile(bindModels, parsed);
    }

    // Content signature: everything a delegate renders. `node`/`path` are
    // excluded — the source range shifts on every save and no binding reads them.
    function rowKey(b) {
        return b.combo + "\u0000" + (b.disabled ? "1" : "0") + "\u0000" + b.desc
             + "\u0000" + JSON.stringify(b.attrs);
    }

    // Reuse the rows whose content is unchanged, so a one-bind mutation leaves the
    // other delegates (and the scroll position) alone instead of rebuilding all N.
    function reconcile(oldRows, newRows) {
        var pools = {}, i, k;
        for (i = 0; i < oldRows.length; i++) {
            k = rowKey(oldRows[i]);
            if (!pools[k]) pools[k] = [];
            pools[k].push(oldRows[i]);
        }
        var out = [], changed = oldRows.length !== newRows.length;
        for (i = 0; i < newRows.length; i++) {
            var pool = pools[rowKey(newRows[i])];
            var row = (pool && pool.length) ? pool.shift() : null;
            if (row) { row.node = newRows[i].node; row.path = newRows[i].path; }
            else row = newRows[i];
            if (row !== oldRows[i]) changed = true;
            out.push(row);
        }
        return changed ? out : oldRows;
    }

    Component.onCompleted: recompute()
    Connections {
        target: root.configModel
        function onConfigChanged() { root.recompute(); }
    }

    function fileText() { return owner ? configModel.textOf(owner.path) : ""; }
    function padTo() { return Binds.alignColumnFor(bindModels); }
    function shortPath() { return owner ? owner.path.replace(configModel.home, "~") : ""; }

    function filterBinds(list, f) {
        if (!f) return list;
        var needle = f.toLowerCase();
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var b = list[i];
            if (b.combo.toLowerCase().indexOf(needle) !== -1 || b.desc.toLowerCase().indexOf(needle) !== -1)
                out.push(b);
        }
        return out;
    }

    // ----- mutations (produce new file text, route through panel.requestSave) -----

    function addBind(bind) {
        var line = Binds.serializeBind(bind, { padTo: padTo() });
        var text = Kdl.insertChildLine(fileText(), owner.nodes[0], line);
        panel.requestSave(owner.path, text, panel.tr("summary.add", "new shortcut {c}", { c: bind.combo }));
    }
    function updateBind(target, bind) {
        var src = configModel.textOf(target.path);
        var indent = Kdl.leadingIndent(src, target.node.range);
        var line = Binds.serializeBind(bind, { padTo: padTo() });
        var text = Kdl.replaceNodeLine(src, target.node, indent + line);
        panel.requestSave(target.path, text, panel.tr("summary.edit", "shortcut {c}", { c: bind.combo }));
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
                model: root.visibleBinds.length
                delegate: Rectangle {
                    property var bind: root.visibleBinds[index] || root.emptyBind

                    Layout.fillWidth: true
                    implicitHeight: rowL.implicitHeight + Style.marginS * 2
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    opacity: bind.disabled ? 0.5 : 1.0

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
                                text: bind.combo
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font.family: "monospace"
                                font.pointSize: Style.fontSizeS
                            }
                        }
                        NText {
                            Layout.fillWidth: true
                            text: (bind.attrs && bind.attrs["hotkey-overlay-title"]) || bind.desc
                            elide: Text.ElideRight
                            font.strikeout: bind.disabled
                        }
                        NIconButton {
                            icon: bind.disabled ? "eye-off" : "eye"
                            tooltipText: bind.disabled ? panel.tr("action.enable", "Enable") : panel.tr("action.disable", "Disable")
                            onClicked: root.toggleBind(bind)
                        }
                        NIconButton {
                            icon: "edit"
                            tooltipText: panel.tr("action.edit", "Edit")
                            onClicked: bindEditor.openEdit(bind, root.bindModels)
                        }
                        NIconButton {
                            icon: "trash"
                            tooltipText: panel.tr("action.delete", "Delete")
                            onClicked: confirmPopup.openFor(bind, panel.tr("shortcuts.confirm-del", "Delete shortcut {c}?", { c: bind.combo }))
                        }
                    }
                }
            }
        }
    }

    BindEditor {
        id: bindEditor
        translate: root.panel.tr
        scriptsDir: Scripts.scriptsDir(root.configModel.configDir)
        onAccepted: (target, bind) => {
            if (target) root.updateBind(target, bind);
            else root.addBind(bind);
        }
    }

    ConfirmPopup {
        id: confirmPopup
        translate: root.panel.tr
        onConfirmed: (bind) => root.deleteBind(bind)
    }
}
