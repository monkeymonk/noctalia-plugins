import QtQuick
import Quickshell
import Quickshell.Io
import "lib/kdl.js" as Kdl
import "lib/config.js" as Cfg

// Non-visual: loads niri's config graph (main + includes), parses each file,
// and exposes section lookups. Read-only — writing is done by Panel's save flow.
Item {
    id: root

    property var pluginApi: null

    readonly property string home: Quickshell.env("HOME") || ""
    property string configDir: home + "/.config/niri"
    readonly property string mainPath: configDir + "/config.kdl"

    property bool niriInstalled: true
    property bool loaded: false
    property string error: ""

    // files: [{ path, text, doc }]
    property var files: []

    // staged (un-applied) edits: path -> newText. The in-memory file is updated
    // immediately so the UI reflects pending changes; disk write happens on Apply.
    property var staged: ({})
    property int pendingCount: 0

    signal loadFinished()

    function load() {
        loaded = false;
        error = "";
        checkProcess.running = true;
    }

    // Stage an edit (no disk write). Updates the in-memory file so sections show it.
    function stage(path, newText) {
        var found = false;
        for (var i = 0; i < files.length; i++) {
            if (files[i].path === path) { files[i].text = newText; files[i].doc = Kdl.parse(newText); found = true; break; }
        }
        if (!found) files.push({ path: path, text: newText, doc: Kdl.parse(newText) });
        files = files.slice();
        staged[path] = newText;
        pendingCount = Object.keys(staged).length;
        loadFinished();
    }

    function stagedList() {
        var out = [];
        for (var p in staged) out.push({ path: p, text: staged[p] });
        return out;
    }

    function clearStaged() { staged = {}; pendingCount = 0; }
    function discardStaged() { clearStaged(); load(); }

    // Find the file + node owning a top-level section (e.g. "binds", "input", "layout").
    function owner(nodeName) {
        return Cfg.findOwner(files, nodeName);
    }

    // All files that contain any of nodeNames (e.g. ["output"], ["window-rule","layer-rule"]).
    function owners(nodeNames) {
        return Cfg.findAllOwners(files, nodeNames);
    }

    function textOf(path) {
        for (var i = 0; i < files.length; i++) if (files[i].path === path) return files[i].text;
        return "";
    }

    function fileEntry(path) {
        for (var i = 0; i < files.length; i++) if (files[i].path === path) return files[i];
        return null;
    }

    // ---------- loading pipeline ----------

    Process {
        id: checkProcess
        command: ["sh", "-c", "command -v niri"]
        onExited: (code) => {
            root.niriInstalled = (code === 0);
            readMain.running = true;
        }
    }

    Process {
        id: readMain
        command: ["cat", root.mainPath]
        property string text: ""
        stdout: StdioCollector { onStreamFinished: readMain.text = this.text }
        onExited: (code) => {
            if (code !== 0) { root.error = "Cannot read " + root.mainPath; root.loaded = true; root.loadFinished(); return; }
            var mainDoc = Kdl.parse(readMain.text);
            var includes = Cfg.includePaths(mainDoc, root.configDir, root.home);
            var all = [root.mainPath].concat(includes);
            readMain._mainText = readMain.text;
            readMain._paths = all;
            readAll.command = Cfg.readBlobCmd(all);
            readAll.running = true;
        }
        property string _mainText: ""
        property var _paths: []
    }

    Process {
        id: readAll
        property string text: ""
        stdout: StdioCollector { onStreamFinished: readAll.text = this.text }
        onExited: (code) => {
            var map = Cfg.splitFileBlob(readAll.text);
            var out = [];
            var paths = readMain._paths;
            for (var i = 0; i < paths.length; i++) {
                var p = paths[i];
                var t = map[p] !== undefined ? map[p] : (p === root.mainPath ? readMain._mainText : "");
                out.push({ path: p, text: t, doc: Kdl.parse(t) });
            }
            root.staged = {};
            root.pendingCount = 0;
            root.files = out;
            root.loaded = true;
            root.loadFinished();
        }
    }
}
