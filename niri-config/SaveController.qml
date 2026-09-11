import QtQuick
import Quickshell.Io
import "lib/niri.js" as Niri

// Non-visual: the WRITE half of the config pipeline (ConfigModel is the read
// half). Config edits are STAGED and only reach disk on applyChanges(), which
// backs up, writes, runs `niri validate` and rolls back on rejection. Raw
// plugin-managed files (scripts) bypass that gate via writeFileNow/deleteFile.
// Dependencies are injected — this never reaches for its parent.
Item {
    id: root

    property var pluginApi: null
    property var configModel: null

    property bool busy: false
    property bool canUndo: false
    property var appliedPaths: []      // last-applied files (for Undo)

    // level: "info" | "ok" | "error" — the host maps it to a colour.
    signal statusReport(string message, string level)

    // A raw (unvalidated) file write or delete completed.
    signal rawFileChanged(string path)

    function tr(k, fallback, params) {
        var s = null;
        if (pluginApi && pluginApi.tr) {
            var v = pluginApi.tr(k);
            if (v && v !== k && !/^!!.*!!$/.test(v)) s = v;
        }
        if (s === null) s = fallback;
        if (params) {
            for (var key in params) s = s.replace("{" + key + "}", params[key]);
        }
        return s;
    }

    // Stage a config edit: shown live in the UI, written on Apply.
    function requestSave(path, newText, summary) {
        configModel.stage(path, newText);
        root.statusReport(root.tr("status.staged", "{what} staged — press Apply to write it.",
                                  { what: summary || "Change" }), "info");
    }

    // Write a non-config file straight to disk: immediate, unvalidated and not
    // undoable. opts.executable also chmods +x.
    function writeFileNow(path, newText, summary, opts) {
        root.busy = true;
        saveProcess._path = path;
        saveProcess._summary = summary || "";
        saveProcess.command = Niri.writeFileCmd(path, Qt.btoa(newText), !!(opts && opts.executable));
        saveProcess.running = true;
    }

    // Write all staged files atomically: .bak + write + niri validate + reload,
    // restoring every .bak if validation fails.
    function applyChanges() {
        var list = configModel.stagedList();
        if (!list.length) return;
        root.busy = true;
        root.statusReport(root.tr("status.applying", "Applying {n} change(s)…", { n: list.length }), "info");
        applyProcess._paths = list.map(function (x) { return x.path; });
        var pairs = list.map(function (x) { return { path: x.path, b64: Qt.btoa(x.text) }; });
        applyProcess.command = Niri.applyCmd(configModel.mainPath, pairs);
        applyProcess.running = true;
    }

    function undoLast() {
        if (!root.appliedPaths.length) return;
        root.busy = true;
        undoProcess.command = Niri.undoCmd(root.appliedPaths);
        undoProcess.running = true;
    }

    // Delete a plugin-managed file (e.g. a script). Bypasses the validate gate.
    function deleteFile(path, summary) {
        root.busy = true;
        saveProcess._path = path;
        saveProcess._summary = summary || "";
        saveProcess.command = Niri.deleteFileCmd(path);
        saveProcess.running = true;
    }

    // Raw file writes / deletes — immediate, no niri validate.
    Process {
        id: saveProcess
        property string _path: ""
        property string _summary: ""
        property string outText: ""
        stdout: StdioCollector { onStreamFinished: saveProcess.outText = this.text }
        onExited: (code) => {
            root.busy = false;
            if (saveProcess.outText.indexOf("OK") !== -1) {
                root.statusReport(root.tr("status.saved-file", "Saved {what}.", { what: saveProcess._summary }), "ok");
                root.rawFileChanged(saveProcess._path);
            } else {
                root.statusReport(root.tr("status.write-failed", "Write failed: {what}.", { what: saveProcess._summary }), "error");
            }
        }
    }

    // Apply staged config changes (validated + backed up).
    Process {
        id: applyProcess
        property var _paths: []
        property string outText: ""
        property string errText: ""
        stdout: StdioCollector { onStreamFinished: applyProcess.outText = this.text }
        stderr: StdioCollector { onStreamFinished: applyProcess.errText = this.text }
        onExited: (code) => {
            root.busy = false;
            if (applyProcess.outText.indexOf("OK") !== -1) {
                root.appliedPaths = applyProcess._paths;   // only a run that actually applied
                root.canUndo = true;
                root.statusReport(root.tr("status.applied", "Applied — niri reloaded."), "ok");
                root.configModel.load();   // re-read from disk, clears staged
            } else {
                var detail = (applyProcess.errText || "").trim();
                root.statusReport(root.tr("status.apply-failed", "Rejected by niri validate — restored from backup. Fix and re-apply.")
                                  + (detail ? ("\n" + detail) : ""), "error");
                // staged changes kept so you can fix them
            }
        }
    }

    // Restore the .bak of every applied file. The script prints "RESTORED <n>"
    // or "ERR <msg>" — n === 0 means there was nothing to restore.
    Process {
        id: undoProcess
        property string outText: ""
        stdout: StdioCollector { onStreamFinished: undoProcess.outText = this.text }
        onExited: (code) => {
            root.busy = false;
            var out = (undoProcess.outText || "").trim();
            var m = /RESTORED[ \t]+([0-9]+)/.exec(out);
            if (!m) {
                var detail = out.replace(/^ERR[ \t]*/, "");
                root.statusReport(root.tr("status.undo-failed", "Undo failed: {what}",
                                          { what: detail || root.tr("status.undo-no-output", "no output from the restore script") }), "error");
                root.configModel.load();   // a partial restore may have hit disk
                return;
            }
            root.canUndo = false;
            var n = parseInt(m[1], 10);
            if (n > 0) {
                root.statusReport(root.tr("status.undone", "Reverted to the previous config."), "ok");
                root.configModel.load();
            } else {
                root.statusReport(root.tr("status.undo-empty", "Nothing to revert — no backup found."), "info");
            }
        }
    }
}
