// Tests for the pure JavaScript pieces. No Quickshell needed.   Usage: node tests/logic.js
const assert = require("assert")
const path = require("path")
const root = path.join(__dirname, "..")
const C = require(path.join(root, "Classify.js"))
const K = require(path.join(root, "Categories.js"))
const H = require(path.join(root, "ClipboardHistory.js"))

let passed = 0
function test(name, fn) {
  try { fn(); passed++; console.log("PASS " + name) }
  catch (e) { console.log("FAIL " + name + ": " + e.message); process.exitCode = 1 }
}

test("a bounded fingerprint collides on long texts with one prefix, identity does not", () => {
  const base = "x".repeat(2048)
  const approved = { type: "text", text: base + "APPROVED" }
  const rejected = { type: "text", text: base + "REJECTED" }
  assert.strictEqual(C.entryFingerprint(approved, "salt"), C.entryFingerprint(rejected, "salt"))
  assert.strictEqual(H.sameEntry(approved, rejected), false)
  assert.strictEqual(H.sameEntry(approved, { type: "text", text: base + "APPROVED" }), true)
})

test("images are the same entry by path, and never equal a text", () => {
  assert.strictEqual(H.sameEntry({ type: "image", path: "/a.png" }, { type: "image", path: "/a.png" }), true)
  assert.strictEqual(H.sameEntry({ type: "image", path: "/a.png" }, { type: "image", path: "/b.png" }), false)
  assert.strictEqual(H.sameEntry({ type: "image", path: "x" }, { type: "text", text: "x" }), false)
})

test("display rows keep the history's own entry object as their identity", () => {
  const entries = [{ type: "text", text: "one" }, { type: "text", text: "two" }]
  const rows = H.displayRows(entries, "", 10)
  assert.strictEqual(rows[1].source, entries[1])
})

test("duplicate clip ids in a category make the file unreadable", () => {
  const dup = { categories: [{ id: "c", name: "n", clips: [{ id: "k", type: "text", text: "FIRST" }, { id: "k", type: "text", text: "SECOND" }] }] }
  assert.strictEqual(K.parse(JSON.stringify(dup)), null)
  const ok = { categories: [{ id: "c", name: "n", clips: [{ id: "k1", type: "text", text: "A" }, { id: "k2", type: "text", text: "B" }] }] }
  assert.strictEqual(K.parse(JSON.stringify(ok)).categories[0].clips.length, 2)
})

test("duplicate category ids make the file unreadable", () => {
  const dup = { categories: [{ id: "c", name: "a", clips: [] }, { id: "c", name: "b", clips: [] }] }
  assert.strictEqual(K.parse(JSON.stringify(dup)), null)
})

test("a text is a Files card only if every non-empty line is a file URI", () => {
  const mixed = H.displayRows([{ type: "text", text: "file:///tmp/report.pdf\nTHIS ALSO GETS PASTED" }], "", 5)[0]
  assert.strictEqual(mixed.entryType, "text")
  assert.ok(mixed.fullText.indexOf("THIS ALSO GETS PASTED") >= 0)
  const files = H.displayRows([{ type: "text", text: "file:///tmp/a.pdf\n\nfile:///tmp/b.txt\n" }], "", 5)[0]
  assert.strictEqual(files.entryType, "file")
  assert.strictEqual(files.previewImage, "")
  const one = H.displayRows([{ type: "text", text: "file:///tmp/x.png" }], "", 5)[0]
  assert.strictEqual(one.entryType, "file")
  assert.strictEqual(one.previewImage, "", "a file path in text never gets an image preview")
})

test("a store that would be saved over the size limit is detected before it is applied", () => {
  let store = K.addCategory(K.emptyData(), "Big").data
  const id = store.categories[0].id
  // Control characters double in size when serialized as \u00XX escapes.
  const nasty = "\u0001".repeat(1000000)
  let refused = false
  for (let i = 0; i < 12; i++) {
    const r = K.addClip(store, id, { id: "k" + i, type: "text", text: nasty + i, savedAt: 1 })
    assert.ok(r.added)
    const text = K.serialize(r.data)
    if (K.utf8Length(text, K.maxStoreBytes) > K.maxStoreBytes) { refused = true; break }
    store = r.data
  }
  assert.ok(refused, "the limit was never reached")
  assert.ok(K.utf8Length(K.serialize(store)) <= K.maxStoreBytes)
  assert.ok(K.maxStoreBytes < 16 * 1024 * 1024, "headroom under the read limit")
})

test("saving the same store is recognised as a no-op", () => {
  const store = K.addCategory(K.emptyData(), "Work").data
  const onDisk = K.serialize(store)
  assert.strictEqual(K.serialize(K.renameCategory(store, store.categories[0].id, "Work")), onDisk)
  assert.strictEqual(K.serialize(K.recolorCategory(store, store.categories[0].id, store.categories[0].color)), onDisk)
  assert.notStrictEqual(K.serialize(K.renameCategory(store, store.categories[0].id, "Play")), onDisk)
})

test("at most 50 categories", () => {
  let d = K.emptyData()
  for (let i = 0; i < K.maxCategories; i++) d = K.addCategory(d, "c" + i).data
  const r = K.addCategory(d, "one more")
  assert.strictEqual(r.id, "")
  assert.strictEqual(r.reason, "toomany")
  assert.strictEqual(r.data.categories.length, K.maxCategories)
})

test("a text clip over 1 MiB is refused, exactly 1 MiB is accepted", () => {
  const store = K.addCategory(K.emptyData(), "X").data
  const id = store.categories[0].id
  assert.ok(K.addClip(store, id, { id: "a", type: "text", text: "a".repeat(1048576), savedAt: 1 }).added)
  assert.strictEqual(K.addClip(store, id, { id: "b", type: "text", text: "a".repeat(1048577), savedAt: 1 }).reason, "toolarge")
})

test("only http and https links, with no whitespace or control characters", () => {
  assert.ok(C.isUrl("https://example.com/a?b=1"))
  assert.ok(C.isUrl("http://example.com"))
  for (const bad of ["ftp://example.com/x", "www.example.com", "javascript:alert(1)", "https://a.b/ x", "https://a.b/\u0001", "https:///x"])
    assert.strictEqual(C.isUrl(bad), false, bad)
})

test("a saved row keeps the complete clip, display text stays capped, later store changes do not reach it", () => {
  const store = K.addCategory(K.emptyData(), "X").data
  const id = store.categories[0].id
  const big = "q".repeat(20000)
  const r = K.addClip(store, id, { id: "c1", type: "text", text: big, savedAt: 1 })
  assert.ok(r.added)
  const clip = K.findClip(r.data, id, "c1")
  const row = K.clipRow(clip, "/imgs")
  assert.strictEqual(row.clip.text.length, 20000)
  assert.ok(row.fullText.length < 20000)
  const later = K.removeClip ? K.removeClip(r.data, id, "c1") : r.data
  const again = K.addClip(later.data || later, id, { id: "c1", type: "text", text: "replaced", savedAt: 2 })
  assert.ok(K.findClip(again.data, id, "c1").text === "replaced")
  assert.strictEqual(row.clip.text, big)
})

test("a Files card is decided from the whole text, not the display prefix", () => {
  const uri = "file:///home/u/a.txt"
  const manyUris = Array.from({ length: 600 }, (_, i) => "file:///home/u/f" + i + ".txt").join("\n")
  const pre = manyUris + "\nnot a file line"
  assert.ok(pre.length > 8192)
  const rows = H.displayRows([{ type: "text", text: pre }, { type: "text", text: manyUris }, { type: "text", text: uri }], "", 50)
  assert.strictEqual(rows[0].entryType, "text")
  assert.strictEqual(rows[1].entryType, "file")
  assert.strictEqual(rows[2].entryType, "file")
  assert.strictEqual(H.isFileList(pre), false)
  assert.strictEqual(H.isFileList(""), false)
})

console.log(passed + " passed" + (process.exitCode ? ", some FAILED" : ""))
