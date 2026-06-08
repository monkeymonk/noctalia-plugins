.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// keys.js — translate captured Qt key events into niri bind tokens, and provide
// the special-key vocabulary (media / brightness / wheel) that Qt can't capture.
// Numeric Qt.Key_* values are hardcoded so this stays framework-agnostic and
// node-testable. Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

// Qt.KeyboardModifier flag bits.
var QT_SHIFT = 0x02000000, QT_CTRL = 0x04000000, QT_ALT = 0x08000000, QT_META = 0x10000000;

// Qt modifier-key codes that should NOT commit a combo on their own.
var BARE_MODIFIER_KEYS = {
    0x01000020: 1, // Shift
    0x01000021: 1, // Control
    0x01000022: 1, // Meta
    0x01000023: 1, // Alt
    0x01001103: 1, // AltGr
    0x01000024: 1, // CapsLock
    0x01000025: 1, // NumLock
    0x01000026: 1  // ScrollLock
};

// Qt.Key_* → niri key name. Letters/digits handled separately via text.
var QT_KEY_NAMES = {
    0x01000000: "Escape", 0x01000001: "Tab", 0x01000003: "BackSpace",
    0x01000004: "Return", 0x01000005: "Return", 0x01000006: "Insert",
    0x01000007: "Delete", 0x20: "Space",
    0x01000010: "Home", 0x01000011: "End",
    0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down",
    0x01000016: "Prior", 0x01000017: "Next", // PageUp / PageDown
    0x01000030: "F1", 0x01000031: "F2", 0x01000032: "F3", 0x01000033: "F4",
    0x01000034: "F5", 0x01000035: "F6", 0x01000036: "F7", 0x01000037: "F8",
    0x01000038: "F9", 0x01000039: "F10", 0x0100003a: "F11", 0x0100003b: "F12",
    0x2d: "Minus", 0x3d: "Equal", 0x2f: "Slash", 0x5c: "Backslash",
    0x2c: "Comma", 0x2e: "Period", 0x3b: "Semicolon", 0x27: "Apostrophe",
    0x60: "Grave", 0x5b: "BracketLeft", 0x5d: "BracketRight",
    0x01000009: "Print"
};

// Shifted symbols (Qt key == ASCII) → base niri keysym. niri binds use the
// UNSHIFTED key name, so Shift+1 must capture as "1", not "!". US-layout-centric;
// the combo field stays editable as a fallback for other layouts.
var SHIFT_SYMBOLS = {
    0x21: "1", 0x40: "2", 0x23: "3", 0x24: "4", 0x25: "5", 0x5e: "6", 0x26: "7",
    0x2a: "8", 0x28: "9", 0x29: "0", 0x5f: "Minus", 0x2b: "Equal", 0x3f: "Slash",
    0x3a: "Semicolon", 0x22: "Apostrophe", 0x3c: "Comma", 0x3e: "Period",
    0x7c: "Backslash", 0x7e: "Grave", 0x7b: "BracketLeft", 0x7d: "BracketRight"
};

// Build the modifier-token list (niri order is enforced later by binds.js).
// meta→"Mod" by default (matches typical niri configs that use "Mod").
function modifierTokens(qtMods, metaName) {
    var out = [];
    if (qtMods & QT_META) out.push(metaName || "Mod");
    if (qtMods & QT_CTRL) out.push("Ctrl");
    if (qtMods & QT_ALT) out.push("Alt");
    if (qtMods & QT_SHIFT) out.push("Shift");
    return out;
}

// True if the pressed key is only a modifier (don't commit yet).
function isBareModifier(qtKey) { return !!BARE_MODIFIER_KEYS[qtKey]; }

// Translate one Qt key code (+ its text) to a niri key token, or null.
function keyToken(qtKey, text) {
    if (isBareModifier(qtKey)) return null;
    if (QT_KEY_NAMES[qtKey]) return QT_KEY_NAMES[qtKey];
    if (SHIFT_SYMBOLS[qtKey]) return SHIFT_SYMBOLS[qtKey];
    // Letters A–Z / a–z → uppercase letter
    if (qtKey >= 0x41 && qtKey <= 0x5a) return String.fromCharCode(qtKey);
    if (qtKey >= 0x61 && qtKey <= 0x7a) return String.fromCharCode(qtKey).toUpperCase();
    // Digits 0–9
    if (qtKey >= 0x30 && qtKey <= 0x39) return String.fromCharCode(qtKey);
    // Fallback: printable text
    if (text && text.length === 1 && text !== " ") {
        var c = text.toUpperCase();
        var named = { "-": "Minus", "=": "Equal", "/": "Slash", "\\": "Backslash",
                      ",": "Comma", ".": "Period", ";": "Semicolon", "'": "Apostrophe",
                      "`": "Grave", "[": "BracketLeft", "]": "BracketRight" };
        return named[text] || c;
    }
    return null;
}

// Compose a full combo string from a captured event, or null if not committable.
function comboFromEvent(qtKey, qtMods, text, metaName) {
    var key = keyToken(qtKey, text);
    if (!key) return null;
    var mods = modifierTokens(qtMods, metaName);
    return mods.concat([key]).join("+");
}

// Keys that cannot be captured via a Qt keyboard grab — offered as a manual list.
var SPECIAL_KEYS = [
    { token: "XF86AudioRaiseVolume", group: "media" },
    { token: "XF86AudioLowerVolume", group: "media" },
    { token: "XF86AudioMute", group: "media" },
    { token: "XF86AudioMicMute", group: "media" },
    { token: "XF86AudioPlay", group: "media" },
    { token: "XF86AudioPause", group: "media" },
    { token: "XF86AudioNext", group: "media" },
    { token: "XF86AudioPrev", group: "media" },
    { token: "XF86AudioStop", group: "media" },
    { token: "XF86MonBrightnessUp", group: "brightness" },
    { token: "XF86MonBrightnessDown", group: "brightness" },
    { token: "XF86KbdBrightnessUp", group: "brightness" },
    { token: "XF86KbdBrightnessDown", group: "brightness" },
    { token: "XF86Display", group: "system" },
    { token: "XF86Search", group: "system" },
    { token: "XF86Mail", group: "system" },
    { token: "XF86HomePage", group: "system" },
    { token: "WheelScrollUp", group: "wheel" },
    { token: "WheelScrollDown", group: "wheel" },
    { token: "WheelScrollLeft", group: "wheel" },
    { token: "WheelScrollRight", group: "wheel" }
];

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        QT_SHIFT: QT_SHIFT, QT_CTRL: QT_CTRL, QT_ALT: QT_ALT, QT_META: QT_META,
        SHIFT_SYMBOLS: SHIFT_SYMBOLS,
        isBareModifier: isBareModifier, modifierTokens: modifierTokens,
        keyToken: keyToken, comboFromEvent: comboFromEvent, SPECIAL_KEYS: SPECIAL_KEYS
    };
}
