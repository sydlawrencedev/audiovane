// Checks that the admin page's Edit button does something.
//
// The Edit button was wired to a variable that was not in scope where the
// button was made, so pressing it threw and nothing happened — and nothing
// on the page said so, because a ReferenceError in a click handler is
// silent. The release check below runs the page's own script against a
// small DOM and presses the button, which is the only way to know.
//
//   node scripts/check-admin-page.mjs
//
// It exits non-zero if the button does nothing.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PAGE = path.join(ROOT, "site/admin.html");

/** A DOM node, only as much as the admin page uses. */
function element(tag) {
  return {
    tagName: (tag || "div").toUpperCase(),
    children: [],
    listeners: {},
    hidden: false,
    textContent: "",
    value: "",
    className: "",
    title: "",
    appendChild(child) { this.children.push(child); return child; },
    addEventListener(name, fn) { (this.listeners[name] = this.listeners[name] || []).push(fn); },
    removeEventListener() {},
    setAttribute() {},
    getAttribute() { return null; },
    focus() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: 100, height: 100 }; },
    click() { (this.listeners.click || []).forEach((fn) => fn({})); },
  };
}

const nodes = new Map();
global.document = {
  getElementById(id) {
    if (!nodes.has(id)) nodes.set(id, element("div"));
    return nodes.get(id);
  },
  createElement(tag) { return element(tag); },
  addEventListener() {},
};

// One share, so that there is a row to press the button on.
global.fetch = async () => ({
  ok: true,
  status: 200,
  json: async () => ({
    ok: true,
    shares: [{
      id: "abc123", name: "A Vibescape", author: "Somebody",
      url: "https://vibresia.com/s/abc123", imageUrl: null,
      inGallery: true, hasImage: false, sharedAt: 0,
    }],
  }),
});

const html = fs.readFileSync(PAGE, "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/);
if (!script) {
  console.error("site/admin.html has no script to check");
  process.exit(1);
}
eval(script[1]);

/** Every node in the tree that matches. */
function find(node, predicate, found = []) {
  if (predicate(node)) found.push(node);
  (node.children || []).forEach((child) => find(child, predicate, found));
  return found;
}

setTimeout(() => {
  // The list is drawn after the unlock button is pressed, and the unlock
  // needs a token in the field.
  nodes.get("token").value = "a-token";
  (nodes.get("unlock-button").listeners.click || []).forEach((fn) => fn({}));

  setTimeout(() => {
    const list = nodes.get("list");
    const edit = find(list, (n) => n.textContent === "Edit");
    if (!edit.length) {
      console.error("the admin page drew no Edit button");
      process.exit(1);
    }
    edit[0].click();

    const forms = find(list, (n) => (n.className || "").indexOf("share-edit") >= 0);
    if (!forms.length) {
      console.error("the admin page's Edit button did nothing");
      process.exit(1);
    }
    const fields = find(forms[0], (n) => n.tagName === "INPUT").length;
    if (fields < 2) {
      console.error("the admin page's edit form has no title and author fields");
      process.exit(1);
    }
    console.log("the admin page's Edit button opens the form");
    process.exit(0);
  }, 100);
}, 200);
