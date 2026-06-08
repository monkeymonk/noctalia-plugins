.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// monique.js — optional integration with the `monique` CLI (monitor profile
// engine). If the CLI is present we surface its profiles in the Monitors tab;
// if not, the plugin manages monitor config directly. Pure command builders +
// parser; QML runs the processes. Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

function checkCmd() { return ["sh", "-c", "command -v monique"]; }
function listProfilesCmd() { return ["monique", "--list-profiles"]; }
function currentProfileCmd() { return ["monique", "--current-profile"]; }
function switchProfileCmd(name) { return ["monique", "--switch-profile", name]; }

function parseProfiles(text) {
    try {
        var a = JSON.parse(String(text || "[]").trim());
        return Array.isArray(a) ? a : [];
    } catch (e) {
        return [];
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        checkCmd: checkCmd, listProfilesCmd: listProfilesCmd, currentProfileCmd: currentProfileCmd,
        switchProfileCmd: switchProfileCmd, parseProfiles: parseProfiles
    };
}
