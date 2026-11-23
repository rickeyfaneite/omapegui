// The pure parts of "copy to category": which windows are terminals, how the
// helper's answer is read, and what the picker lists.

// Window classes where Ctrl+C would interrupt the program, so the highlighted
// text (the PRIMARY selection) is used instead. Compared exactly, ignoring case.
var terminalClasses = [
  "alacritty", "kitty", "foot", "footclient", "ghostty", "wezterm",
  "com.mitchellh.ghostty", "org.wezfurlong.wezterm"
]

function isTerminal(windowClass) {
  var c = String(windowClass === undefined || windowClass === null ? "" : windowClass).toLowerCase()
  return c !== "" && terminalClasses.indexOf(c) >= 0
}

// The helper (grab.sh) answers with one header line, then, for text, the text:
//   OMAPEGUI-GRAB kind=text src=primary
//   OMAPEGUI-GRAB kind=image src=clipboard mime=image/png name=<64 hex>.png
//   OMAPEGUI-GRAB kind=none
// Returns { kind, src, mime, name, text } or null when it is not that shape.
var imageNamePattern = /^[0-9a-f]{32,64}\.(png|jpg|webp|gif)$/
var imageMimes = ["image/png", "image/jpeg", "image/webp", "image/gif"]

function parseGrab(output) {
  var s = String(output === undefined || output === null ? "" : output)
  var nl = s.indexOf("\n")
  var head = nl < 0 ? s : s.substring(0, nl)
  var body = nl < 0 ? "" : s.substring(nl + 1)
  if (head.indexOf("OMAPEGUI-GRAB ") !== 0) return null
  var fields = {}
  var parts = head.substring(14).split(" ")
  for (var i = 0; i < parts.length; i++) {
    var eq = parts[i].indexOf("=")
    if (eq > 0) fields[parts[i].substring(0, eq)] = parts[i].substring(eq + 1)
  }
  var src = fields.src === "primary" ? "primary" : "clipboard"
  if (fields.kind === "none") return { kind: "none", src: src, mime: "", name: "", text: "" }
  if (fields.kind === "text") {
    if (body.trim() === "") return { kind: "none", src: src, mime: "", name: "", text: "" }
    return { kind: "text", src: src, mime: "text/plain", name: "", text: body }
  }
  if (fields.kind === "image") {
    if (!imageNamePattern.test(String(fields.name || "")) || imageMimes.indexOf(String(fields.mime || "")) < 0) return null
    return { kind: "image", src: src, mime: fields.mime, name: fields.name, text: "" }
  }
  return null
}

// What the picker shows: the categories whose name contains the typed text, then
// "New category". With nothing matching, only the last remains.
function pickerItems(categories, query, colorOf) {
  var needle = String(query || "").trim().toLowerCase()
  var items = []
  for (var i = 0; i < categories.length; i++) {
    var c = categories[i]
    if (needle && String(c.name).toLowerCase().indexOf(needle) < 0) continue
    items.push({ id: "cat:" + c.id, label: c.name, swatch: colorOf ? colorOf(c) : undefined })
  }
  if (items.length > 0) items.push({ separator: true })
  items.push({ id: "new", label: "New category…" })
  return items
}

// A short description of what is about to be saved, one line.
function describe(item) {
  if (!item) return ""
  if (item.kind === "image") return "Image"
  var t = String(item.text || "").replace(/\s+/g, " ").trim()
  return t.length > 48 ? t.slice(0, 47) + "…" : t
}

if (typeof module !== "undefined") {
  module.exports = { isTerminal: isTerminal, terminalClasses: terminalClasses, parseGrab: parseGrab, pickerItems: pickerItems, describe: describe }
}
