.pragma library

var ALL_FINGERS = [
    "left-thumb",
    "left-index-finger",
    "left-middle-finger",
    "left-ring-finger",
    "left-little-finger",
    "right-thumb",
    "right-index-finger",
    "right-middle-finger",
    "right-ring-finger",
    "right-little-finger"
];

var FINGER_LABELS = {
    "left-thumb":          "Left thumb",
    "left-index-finger":   "Left index",
    "left-middle-finger":  "Left middle",
    "left-ring-finger":    "Left ring",
    "left-little-finger":  "Left little",
    "right-thumb":         "Right thumb",
    "right-index-finger":  "Right index",
    "right-middle-finger": "Right middle",
    "right-ring-finger":   "Right ring",
    "right-little-finger": "Right little"
};

var FINGER_ICONS = {
    "left-thumb":          "hand-three-fingers",
    "left-index-finger":   "hand-finger",
    "left-middle-finger":  "hand-middle-finger",
    "left-ring-finger":    "hand-ring-finger",
    "left-little-finger":  "hand-little-finger",
    "right-thumb":         "hand-three-fingers",
    "right-index-finger":  "hand-finger",
    "right-middle-finger": "hand-middle-finger",
    "right-ring-finger":   "hand-ring-finger",
    "right-little-finger": "hand-little-finger"
};

function labelOf(name) {
    return FINGER_LABELS[name] || name;
}

function iconOf(name) {
    return FINGER_ICONS[name] || "fingerprint";
}

// Parse `fprintd-list "$USER"` output. Returns array of finger-name strings.
// Sample lines we care about:
//   "  - #0: right-index-finger"
function parseList(text) {
    var out = [];
    if (!text) return out;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var m = lines[i].match(/#\d+:\s*([a-z-]+)/);
        if (m) out.push(m[1]);
    }
    return out;
}

// Fingers from ALL_FINGERS that are not yet enrolled.
function availableForEnroll(enrolled) {
    var set = {};
    for (var i = 0; i < enrolled.length; ++i) set[enrolled[i]] = true;
    return ALL_FINGERS.filter(function (f) { return !set[f]; });
}

// Classify a stdout line from fprintd-enroll.
// Returns one of: "stage-pass", "retry", "completed", "failed", null
function classifyEnrollLine(line) {
    if (!line) return null;
    var l = line.toLowerCase();
    if (l.indexOf("enroll-completed") !== -1) return "completed";
    if (l.indexOf("enroll-failed") !== -1) return "failed";
    if (l.indexOf("enroll-stage-passed") !== -1) return "stage-pass";
    if (l.indexOf("enroll-retry") !== -1) return "retry";
    if (l.indexOf("enroll-finger-not-centered") !== -1) return "retry";
    if (l.indexOf("enroll-remove-and-retry") !== -1) return "retry";
    if (l.indexOf("enroll-swipe-too-short") !== -1) return "retry";
    if (l.indexOf("enroll-finger-not-removed") !== -1) return "retry";
    return null;
}

function classifyVerifyLine(line) {
    if (!line) return null;
    var l = line.toLowerCase();
    if (l.indexOf("verify-match") !== -1) return "match";
    if (l.indexOf("verify-no-match") !== -1) return "no-match";
    if (l.indexOf("verify-retry-scan") !== -1) return "retry";
    if (l.indexOf("verify-swipe-too-short") !== -1) return "retry";
    if (l.indexOf("verify-finger-not-centered") !== -1) return "retry";
    if (l.indexOf("verify-remove-and-retry") !== -1) return "retry";
    return null;
}
