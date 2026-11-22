// Pure helpers for the card view: what kind of thing a clipboard entry is,
// how to describe its size, and how long ago it was copied. No QML here so it
// can be run under node.

// Parses a single CSS colour value. Returns {r,g,b,a,format} (0..1 floats) or null.
function parseColor(text) {
  var s = String(text || "").trim()
  if (!s || s.length > 64 || /[\r\n]/.test(s)) return null

  var m = s.match(/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i)
  if (m) {
    var h = m[1]
    if (h.length === 3 || h.length === 4) {
      var x = ""
      for (var i = 0; i < h.length; i++) x += h.charAt(i) + h.charAt(i)
      h = x
    }
    return {
      r: parseInt(h.substr(0, 2), 16) / 255,
      g: parseInt(h.substr(2, 2), 16) / 255,
      b: parseInt(h.substr(4, 2), 16) / 255,
      a: h.length === 8 ? parseInt(h.substr(6, 2), 16) / 255 : 1,
      format: "hex"
    }
  }

  m = s.match(/^rgba?\(\s*([\d.]+%?)\s*[,\s]\s*([\d.]+%?)\s*[,\s]\s*([\d.]+%?)\s*(?:[,\/]\s*([\d.]+%?)\s*)?\)$/i)
  if (m) {
    var ch = function(v) {
      var n = parseFloat(v)
      if (v.charAt(v.length - 1) === "%") n = n * 2.55
      return Math.max(0, Math.min(255, n)) / 255
    }
    var a = 1
    if (m[4] !== undefined) {
      a = parseFloat(m[4])
      if (m[4].charAt(m[4].length - 1) === "%") a = a / 100
      a = Math.max(0, Math.min(1, a))
    }
    return { r: ch(m[1]), g: ch(m[2]), b: ch(m[3]), a: a, format: "rgb" }
  }

  m = s.match(/^hsla?\(\s*([\d.]+)(?:deg)?\s*[,\s]\s*([\d.]+)%\s*[,\s]\s*([\d.]+)%\s*(?:[,\/]\s*([\d.]+%?)\s*)?\)$/i)
  if (m) {
    var hh = (((parseFloat(m[1]) % 360) + 360) % 360) / 360
    var ss = Math.max(0, Math.min(100, parseFloat(m[2]))) / 100
    var ll = Math.max(0, Math.min(100, parseFloat(m[3]))) / 100
    var aa = 1
    if (m[4] !== undefined) {
      aa = parseFloat(m[4])
      if (m[4].charAt(m[4].length - 1) === "%") aa = aa / 100
      aa = Math.max(0, Math.min(1, aa))
    }
    var q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss
    var p = 2 * ll - q
    var hue = function(t) {
      if (t < 0) t += 1
      if (t > 1) t -= 1
      if (t < 1 / 6) return p + (q - p) * 6 * t
      if (t < 1 / 2) return q
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
      return p
    }
    return ss === 0
      ? { r: ll, g: ll, b: ll, a: aa, format: "hsl" }
      : { r: hue(hh + 1 / 3), g: hue(hh), b: hue(hh - 1 / 3), a: aa, format: "hsl" }
  }

  return null
}

function rgbLabel(c) {
  if (!c) return ""
  var r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255)
  return c.a < 1
    ? "rgba(" + r + ", " + g + ", " + b + ", " + (Math.round(c.a * 100) / 100) + ")"
    : "rgb(" + r + ", " + g + ", " + b + ")"
}

// Relative luminance, 0..1, for picking readable text over a colour.
function luminance(r, g, b) {
  var f = function(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}

// Only http and https links count, with a host, and with no whitespace or
// control characters anywhere in the string.
function isUrl(text) {
  var s = String(text || "").trim()
  if (!s || s.length > 2048) return false
  return /^https?:\/\/[^\s\u0000-\u001f\u007f\/?#]+([\/?#][^\s\u0000-\u001f\u007f]*)?$/i.test(s)
}

function urlParts(text) {
  var s = String(text || "").trim()
  var m = s.match(/^(?:[a-z]+:\/\/)?([^\/?#]+)([\s\S]*)$/i)
  if (!m) return { host: s, rest: "" }
  var host = m[1].replace(/^[^@]*@/, "").replace(/^www\./i, "")
  var rest = m[2] || ""
  return { host: host, rest: rest }
}

function looksLikeCode(text) {
  var s = String(text || "")
  var lines = s.split(/\r?\n/).filter(function(l) { return l.trim().length > 0 })
  if (lines.length === 0) return false

  if (lines.length === 1) {
    var one = lines[0].trim()
    if (one.length > 300) return false
    if (/^(\$ |sudo |git |npm |pnpm |yarn |cd |ls |curl |ssh |scp |docker |pacman |yay |pip |cargo |make |systemctl |hyprctl |omarchy[- ])/.test(one)) return true
    if (/(=>|::|->|\(\)\s*[{;]|\);$|\{\s*$|^\s*(const|let|var|def|fn|func|import|from|class|return)\s+\S)/.test(one) && /[(){}=;]/.test(one)) return true
    return false
  }

  var punct = 0, indented = 0, keyword = 0
  var kw = /\b(function|const|let|var|def|class|import|from|return|if|else|elif|for|while|switch|case|export|public|private|static|void|int|string|bool|fn|func|impl|struct|enum|SELECT|INSERT|UPDATE|FROM|WHERE|echo|fi|done|then|local|print|println|require|use|package|namespace)\b/
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i]
    if (/[{};()\[\]=<>]\s*$|^\s*[}\])]|^\s*(\/\/|#|\/\*|\*|<\/?\w)/.test(l)) punct++
    if (/^(\s{2,}|\t)\S/.test(l)) indented++
    if (kw.test(l)) keyword++
  }
  var n = lines.length
  if (punct / n >= 0.5) return true
  if (indented / n >= 0.4 && (keyword > 0 || punct > 0)) return true
  if (keyword / n >= 0.4 && (punct > 0 || indented > 0)) return true
  return false
}

// kind is one of: image, file, colour, link, code, text.
function kindOf(row) {
  if (!row) return "text"
  if (row.entryType === "image") return "image"
  if (row.entryType === "file") return "file"
  var t = String(row.fullText || "")
  if (parseColor(t)) return "colour"
  if (isUrl(t)) return "link"
  if (looksLikeCode(t)) return "code"
  return "text"
}

var kindLabels = { text: "Text", link: "Link", image: "Image", colour: "Color", code: "Code", file: "Files" }

function kindLabel(kind) {
  return kindLabels[kind] || "Text"
}

function groupNumber(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function formatBytes(b) {
  var n = Number(b)
  if (!isFinite(n) || n <= 0) return ""
  if (n < 1024) return n + " B"
  if (n < 1024 * 1024) return (Math.round(n / 102.4) / 10) + " KB"
  return (Math.round(n / (1024 * 102.4)) / 10) + " MB"
}

// The history viewer caps very long entries at displayLimit characters.
function charsLabel(text, capped) {
  var len = String(text || "").length
  var lines = String(text || "").split(/\r?\n/).length
  var out = (capped ? groupNumber(len) + "+" : groupNumber(len)) + (len === 1 && !capped ? " char" : " chars")
  if (lines > 1) out += " · " + groupNumber(lines) + (capped ? "+" : "") + " lines"
  return out
}

function relativeTime(ms, now) {
  if (!ms) return "Earlier"
  var diff = Math.max(0, (now - ms) / 1000)
  if (diff < 45) return "Just now"
  if (diff < 3600) return Math.max(1, Math.round(diff / 60)) + "m ago"
  if (diff < 86400) return Math.round(diff / 3600) + "h ago"
  var days = Math.floor(diff / 86400)
  if (days === 1) return "Yesterday"
  if (days < 7) return days + "d ago"
  var d = new Date(ms)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[d.getMonth()] + " " + d.getDate()
}

// Small non-cryptographic keyed hash. The salt is random per install and kept in
// the plugin's private folder, so the labels in times.json cannot be matched
// against guesses of what was copied. The caller passes only a bounded prefix
// of the content; `length` stands in for the rest.
function hashKey(str, salt, length) {
  var s = String(salt || "") + "|" + String(str || "")
  var h1 = 5381, h2 = 52711
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    h1 = ((h1 * 33) ^ c) >>> 0
    h2 = ((h2 * 31) + c) >>> 0
  }
  return h1.toString(16) + h2.toString(16) + "." + Number(length || 0).toString(36)
}

// Identity of a history entry: a prefix of at most 2048 characters plus the
// length, never every character of a huge entry.
function entryFingerprint(entry, salt) {
  if (!entry) return ""
  if (entry.type === "image") {
    var p = String(entry.path || "")
    return hashKey("image:" + p.slice(0, 512), salt, p.length)
  }
  var t = String(entry.text || "")
  return hashKey("text:" + t.slice(0, 2048), salt, t.length)
}

// Pre-cut a code snippet for a fixed-width, no-wrap card: tabs expanded, each
// line trimmed to cols with an ellipsis, at most maxLines lines.
function codeLines(text, cols, maxLines) {
  var lines = String(text || "").replace(/\t/g, "  ").split(/\r?\n/)
  // Drop leading blank lines and the common left indent.
  while (lines.length && lines[0].trim() === "") lines.shift()
  var indent = Infinity
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() === "") continue
    var lead = lines[i].match(/^ */)[0].length
    if (lead < indent) indent = lead
  }
  if (!isFinite(indent)) indent = 0
  var out = []
  for (var j = 0; j < lines.length && out.length < maxLines; j++) {
    var l = lines[j].substring(indent).replace(/\s+$/, "")
    if (cols > 1 && l.length > cols) l = l.substring(0, cols - 1) + "…"
    out.push(l)
  }
  return out.join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseColor: parseColor, rgbLabel: rgbLabel, luminance: luminance, isUrl: isUrl,
    urlParts: urlParts, looksLikeCode: looksLikeCode, kindOf: kindOf, kindLabel: kindLabel,
    formatBytes: formatBytes, charsLabel: charsLabel, relativeTime: relativeTime,
    hashKey: hashKey, entryFingerprint: entryFingerprint, codeLines: codeLines, groupNumber: groupNumber
  }
}
