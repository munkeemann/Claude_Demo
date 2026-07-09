/**
 * Builds the self-contained index.html for the ParcelTrace demo.
 *
 * Inlines styles.css, data/packages.js, and app.js into a single file so the
 * app renders fully (styled, with data) no matter how it's opened — served,
 * double-clicked from disk, or previewed by a viewer that won't fetch
 * sibling files.
 *
 * Edit src/index.template.html / styles.css / app.js, then re-run:
 *   node scripts/build-app.js
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");

const template = read("src/index.template.html");
const css = read("styles.css");
const data = read("data/packages.js");
const app = read("app.js");

const html = template
  .replace("<!--INLINE_CSS-->", "<style>\n" + css + "\n</style>")
  .replace("<!--INLINE_DATA-->", "<script>\n" + data + "\n</script>")
  .replace("<!--INLINE_APP-->", "<script>\n" + app + "\n</script>");

fs.writeFileSync(path.join(ROOT, "index.html"), html);
const kb = Math.round(Buffer.byteLength(html) / 1024);
console.log("Built index.html (" + kb + " KB, fully self-contained)");
