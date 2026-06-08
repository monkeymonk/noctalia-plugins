// Loads a Noctalia ".pragma library" JS module under plain Node by stripping the
// QML-only `.pragma library` directive and evaluating the rest as a CommonJS module.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

function loadLib(relPath) {
    const abs = path.resolve(__dirname, "..", relPath);
    let src = fs.readFileSync(abs, "utf8");
    src = src.replace(/^\s*\.pragma\s+library\s*$/m, "");
    const module = { exports: {} };
    const sandbox = { module, exports: module.exports, console, require };
    vm.runInNewContext(src, sandbox, { filename: abs });
    return module.exports;
}

module.exports = { loadLib };
