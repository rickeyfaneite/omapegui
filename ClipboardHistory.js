// Reading side of Omarchy's clipboard history (clipboard-history.json).
// Derived from the built-in plugin's ClipboardHistory.js, cut down to what a
// view that never captures and never rewrites the file needs.

function normalizeEntry(value) {
  if (typeof value === "string")
    return value.trim().length > 0 ? { type: "text", text: value } : null

  if (!value || typeof value !== "object") return null

  var type = String(value.type || value.kind || "")
  if (type === "text") {
    var text = String(value.text || "")
    return text.trim().length > 0 ? { type: "text", text: text } : null
  }

  if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    return { type: "image", path: path, mime: String(value.mime || "image/png") }
  }

  return null
}

// Most entries kept in memory (the stock history keeps 500).
var maxEntries = 500

// Largest history or categories file that is read at all, in bytes.
var maxFileBytes = 16 * 1024 * 1024

// Entries the view can show, or null when the file is not a JSON array at all
// (a failed read must not look like an empty history).
function parseHistory(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw === undefined || raw === null ? "" : raw)) } catch (e) { return null }
  if (!Array.isArray(parsed)) return null

  var next = []
  for (var i = 0; i < parsed.length && next.length < maxEntries; i++) {
    var entry = normalizeEntry(parsed[i])
    if (entry) next.push(entry)
  }
  return next
}

function searchableText(entry, isFile) {
  if (!entry) return ""
  if (entry.type === "image") return "image screenshot " + String(entry.mime || "")
  return String(entry.text || "") + (isFile ? " " + fileNames(entry) : "")
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

// Paths of a copied file list. A text counts as one only if every non-empty
// line is a file:// URI; any other line makes it plain text, so nothing that
// would be pasted is hidden behind a Files card.
function filePaths(entry) {
  if (!entry || entry.type !== "text") return []

  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() === "") continue
    var path = decodeFileUri(lines[i])
    if (!path) return []
    paths.push(path)
  }
  return paths
}

// True only if the whole text is a file list: at least one non-empty line, and
// every non-empty line a file:// URI. Decided from the complete text, scanning
// line by line and stopping at the first line that is not one.
function isFileList(text) {
  var s = String(text || "")
  var pos = 0
  var any = false
  while (pos <= s.length) {
    var end = s.indexOf("\n", pos)
    if (end < 0) end = s.length
    var line = s.substring(pos, end)
    if (line.trim() !== "") {
      if (!decodeFileUri(line)) return false
      any = true
    }
    pos = end + 1
  }
  return any
}

// Whether two history entries are the same entry: complete content, not a
// fingerprint of a prefix (two long texts can share one).
function sameEntry(a, b) {
  if (!a || !b || a.type !== b.type) return false
  return a.type === "image" ? a.path === b.path : a.text === b.text
}

function fileNames(entry) {
  var paths = filePaths(entry)
  var names = []
  for (var i = 0; i < paths.length; i++) {
    var parts = paths[i].split("/")
    names.push(parts[parts.length - 1])
  }
  return names.join(" ")
}

// Only a prefix of an entry is ever searched or drawn, so scan and render just
// that much; a single huge paste would otherwise stall every keystroke.
var displayTextLimit = 8192

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  // Cut on a line break so a file:// URI never truncates into a bogus path.
  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  return { type: "text", text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit) }
}

// Rows for the cards. `index` is the position in the parsed list the caller
// holds; it is never handed to another process.
function displayRows(history, query, limit) {
  var values = Array.isArray(history) ? history : []
  var needle = String(query || "").trim().toLowerCase()
  var max = limit === undefined || limit === null ? 50 : Number(limit)
  if (isNaN(max)) max = 50
  if (max <= 0) return []

  var rows = []

  for (var i = 0; i < values.length; i++) {
    var full = normalizeEntry(values[i])
    if (!full) continue
    var entry = cappedEntry(full)
    // A Files card is decided from the complete text, not the display prefix:
    // a non-URI line anywhere makes it plain text.
    var isFile = full.type === "text" && isFileList(full.text)
    if (needle && searchableText(entry, isFile).toLowerCase().indexOf(needle) < 0) continue

    var isImage = entry.type === "image"
    // Only real image entries get a preview; clipboard text that happens to name
    // a file never makes the plugin open that file.
    rows.push({
      entryType: isFile ? "file" : entry.type,
      fullText: isImage ? "" : (isFile ? filePaths(entry).join("\n") : String(entry.text || "")),
      previewImage: isImage ? String(entry.path || "") : "",
      path: isImage ? String(entry.path || "") : "",
      mime: isImage ? String(entry.mime || "image/png") : "text/plain",
      index: i,
      // The history's own entry object, the identity actions are resolved by.
      source: values[i]
    })
    if (rows.length >= max) break
  }

  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeEntry: normalizeEntry,
    parseHistory: parseHistory,
    searchableText: searchableText,
    filePaths: filePaths,
    sameEntry: sameEntry,
    isFileList: isFileList,
    displayRows: displayRows
  }
}
