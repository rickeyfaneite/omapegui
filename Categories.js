// Pure data helpers for saved clips ("categories"). The store is
//   { version: 1, categories: [ { id, name, color, clips: [ clip ] } ] }
//   clip = { id, type: "text"|"image", text?, image?, mime?, savedAt }
// `image` is a file name inside the plugin's own images folder, so a saved
// clip owns a copy of its content and outlives Omarchy trimming its history.
// Every function returns a new object; nothing mutates its input.

// Role names in the theme's colors.toml, chosen to stay distinguishable in the
// shipped themes (several of its blue/magenta/cyan keys share a hue).
var colorCycle = ["orange", "cyan", "red", "foreground", "green", "yellow", "brown", "blue"]

function emptyData() {
  return { version: 1, categories: [] }
}

var imageNamePattern = /^[0-9a-f]{32,64}\.(png|jpg|webp|gif)$/
var imageMimes = ["image/png", "image/jpeg", "image/webp", "image/gif"]

// Largest text clip that may be saved, in UTF-8 bytes.
var maxClipBytes = 1024 * 1024

// Largest saved store, serialized, that a change may produce. The plugin refuses
// to read a file over 16 MiB, so this leaves headroom below it.
var maxStoreBytes = 12 * 1024 * 1024

var maxCategories = 50

function utf8Length(s, cap) {
  var str = String(s || "")
  var n = 0
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (c >= 0xD800 && c <= 0xDBFF) { n += 4; i++ }
    else n += 3
    if (cap && n > cap) return n
  }
  return n
}

function cleanClip(c) {
  if (!c || typeof c !== "object") return null
  var id = String(c.id || "")
  if (!id) return null
  var savedAt = Number(c.savedAt) || 0
  if (c.type === "text") {
    var text = String(c.text === undefined || c.text === null ? "" : c.text)
    if (text.length === 0) return null
    return { id: id, type: "text", text: text, savedAt: savedAt }
  }
  if (c.type === "image") {
    // Only names of the form the plugin itself generates, with a known image type.
    var image = String(c.image || "")
    var mime = String(c.mime || "image/png")
    if (!imageNamePattern.test(image) || imageMimes.indexOf(mime) < 0) return null
    return { id: id, type: "image", image: image, mime: mime, savedAt: savedAt }
  }
  return null
}

// The store, or null when the text is not a valid store at all. A missing file
// is the caller's business (an empty store); a damaged one must not be mistaken
// for it, or the next save would replace whatever is recoverable in it.
function parse(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw === undefined || raw === null ? "" : raw)) } catch (e) { return null }
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.categories)) return null

  var out = []
  var seen = {}
  for (var i = 0; i < parsed.categories.length; i++) {
    var c = parsed.categories[i]
    if (!c || typeof c !== "object") continue
    var id = String(c.id || "")
    var name = String(c.name || "").trim()
    if (!id || !name) continue
    // Two categories with one id, or two clips with one id in a category, would
    // make a card resolve to another one: refuse the file instead of guessing.
    if (seen[id]) return null
    seen[id] = true
    var clips = []
    var clipIds = {}
    var list = Array.isArray(c.clips) ? c.clips : []
    for (var j = 0; j < list.length; j++) {
      var clip = cleanClip(list[j])
      if (!clip) continue
      if (clipIds[clip.id]) return null
      clipIds[clip.id] = true
      clips.push(clip)
    }
    out.push({ id: id, name: name, color: String(c.color || colorCycle[out.length % colorCycle.length]), clips: clips })
  }
  return { version: 1, categories: out }
}

// The text a store is saved as; the same function decides whether two stores are
// the same (a no-op) and how large a save would be.
function serialize(store) {
  return JSON.stringify(store, null, 2) + "\n"
}

function newId(prefix) {
  return prefix + Date.now().toString(36) + Math.floor(Math.random() * 46656).toString(36)
}

function find(data, id) {
  for (var i = 0; i < data.categories.length; i++) if (data.categories[i].id === id) return data.categories[i]
  return null
}

function mapCategories(data, fn) {
  return { version: 1, categories: data.categories.map(fn) }
}

function addCategory(data, name, color) {
  var clean = String(name || "").trim().slice(0, 40)
  if (!clean) return { data: data, id: "", reason: "empty" }
  if (data.categories.length >= maxCategories) return { data: data, id: "", reason: "toomany" }
  var id = newId("c")
  var col = color || colorCycle[data.categories.length % colorCycle.length]
  var next = { version: 1, categories: data.categories.concat([{ id: id, name: clean, color: col, clips: [] }]) }
  return { data: next, id: id }
}

function renameCategory(data, id, name) {
  var clean = String(name || "").trim().slice(0, 40)
  if (!clean) return data
  return mapCategories(data, function(c) { return c.id === id ? { id: c.id, name: clean, color: c.color, clips: c.clips } : c })
}

function recolorCategory(data, id, color) {
  return mapCategories(data, function(c) { return c.id === id ? { id: c.id, name: c.name, color: color, clips: c.clips } : c })
}

function imagesInUse(data) {
  var used = {}
  for (var i = 0; i < data.categories.length; i++)
    for (var j = 0; j < data.categories[i].clips.length; j++) {
      var c = data.categories[i].clips[j]
      if (c.type === "image") used[c.image] = true
    }
  return used
}

// Image files that no category references any more.
function orphanedImages(before, after) {
  var used = imagesInUse(after)
  var gone = []
  var was = imagesInUse(before)
  for (var name in was) if (!used[name]) gone.push(name)
  return gone
}

function deleteCategory(data, id) {
  return { version: 1, categories: data.categories.filter(function(c) { return c.id !== id }) }
}

function sameContent(a, b) {
  if (a.type !== b.type) return false
  return a.type === "image" ? a.image === b.image : a.text === b.text
}

// New clips go first (newest on the left, like the history).
function addClip(data, catId, clip) {
  var cat = find(data, catId)
  if (!cat) return { data: data, added: false, reason: "missing" }
  var fresh = cleanClip(clip)
  if (!fresh) return { data: data, added: false, reason: "invalid" }
  if (fresh.type === "text" && utf8Length(fresh.text, maxClipBytes) > maxClipBytes) return { data: data, added: false, reason: "toolarge" }
  for (var i = 0; i < cat.clips.length; i++) if (sameContent(cat.clips[i], fresh)) return { data: data, added: false, reason: "duplicate" }
  var next = mapCategories(data, function(c) {
    return c.id === catId ? { id: c.id, name: c.name, color: c.color, clips: [fresh].concat(c.clips) } : c
  })
  return { data: next, added: true, reason: "" }
}

function removeClip(data, catId, clipId) {
  return mapCategories(data, function(c) {
    return c.id === catId
      ? { id: c.id, name: c.name, color: c.color, clips: c.clips.filter(function(k) { return k.id !== clipId }) }
      : c
  })
}

function moveClip(data, catId, clipId, delta) {
  return mapCategories(data, function(c) {
    if (c.id !== catId) return c
    var from = -1
    for (var i = 0; i < c.clips.length; i++) if (c.clips[i].id === clipId) from = i
    var to = from + delta
    if (from < 0 || to < 0 || to >= c.clips.length) return c
    var clips = c.clips.slice()
    var item = clips.splice(from, 1)[0]
    clips.splice(to, 0, item)
    return { id: c.id, name: c.name, color: c.color, clips: clips }
  })
}

function clipIndex(data, catId, clipId) {
  var cat = find(data, catId)
  if (!cat) return -1
  for (var i = 0; i < cat.clips.length; i++) if (cat.clips[i].id === clipId) return i
  return -1
}

function findClip(data, catId, clipId) {
  var cat = find(data, catId)
  if (!cat) return null
  for (var i = 0; i < cat.clips.length; i++) if (cat.clips[i].id === clipId) return cat.clips[i]
  return null
}

// Presentation limit, as for the history rows: a saved clip can be huge, but a
// card only ever draws and searches a prefix. Actions read the full clip by id.
var displayTextLimit = 8192

// A saved clip shaped like a display row of the history, so cards treat both
// the same way. historyIndex -1 = not in the history.
function clipRow(clip, imagesDir) {
  var isImage = clip.type === "image"
  var path = isImage ? imagesDir + "/" + clip.image : ""
  return {
    entryType: isImage ? "image" : "text",
    fullText: isImage ? "" : clip.text.slice(0, displayTextLimit),
    previewPath: isImage ? path : "",
    path: path,
    mime: isImage ? clip.mime : "text/plain",
    historyIndex: -1,
    // The complete saved clip this row was built from. Actions on the row use this,
    // never a fresh lookup by id, which could return a clip changed since.
    clip: clip,
    clipId: clip.id,
    savedAt: clip.savedAt,
    key: "k:" + clip.id,
    capped: !isImage && clip.text.length > displayTextLimit
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    colorCycle: colorCycle, emptyData: emptyData, parse: parse, newId: newId, find: find,
    addCategory: addCategory, renameCategory: renameCategory, recolorCategory: recolorCategory,
    deleteCategory: deleteCategory, addClip: addClip, removeClip: removeClip, moveClip: moveClip,
    clipIndex: clipIndex, clipRow: clipRow, findClip: findClip, orphanedImages: orphanedImages, utf8Length: utf8Length, maxClipBytes: maxClipBytes, maxStoreBytes: maxStoreBytes, maxCategories: maxCategories, serialize: serialize
  }
}
