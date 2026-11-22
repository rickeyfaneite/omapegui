import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory
import "Classify.js" as Classify
import "Categories.js" as Categories

// OmaPegui: a bottom-edge strip of clipboard cards.
//
// History comes from the file Omarchy's own clipboard plugin (omarchy.clipboard)
// writes; nothing here captures. Saved clips ("categories") live in this
// plugin's own folder, as their own copies.
//
// Every action works on a snapshot of the entry taken when the action was
// chosen (its identity and its full content). Clipboard text reaches the
// helper script on stdin, never as an argument or a history index.
Item {
  id: root

  // Handed in by the shell's plugin loader.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: (root.manifest && root.manifest.__sourceDir) ? String(root.manifest.__sourceDir) : root.home + "/.config/omarchy/plugins/io.github.rickeyfaneite.omapegui"
  readonly property string putScript: root.pluginDir + "/put.sh"
  readonly property string imgScript: root.pluginDir + "/img-save.sh"
  readonly property string imgRmScript: root.pluginDir + "/img-rm.sh"
  readonly property string imgPutScript: root.pluginDir + "/img-put.sh"
  readonly property string setupScript: root.pluginDir + "/setup.sh"
  readonly property string stockImagesDir: root.home + "/.local/state/omarchy/clipboard-images"
  readonly property string historyPath: root.home + "/.local/state/omarchy/clipboard-history.json"
  readonly property string stateDir: root.home + "/.local/state/omarchy/omapegui"
  readonly property string imagesDir: root.stateDir + "/images"
  readonly property string categoriesPath: root.stateDir + "/categories.json"
  readonly property string timesPath: root.stateDir + "/times.json"
  readonly property string themeColorsPath: root.home + "/.local/state/omarchy/current/theme/colors.toml"

  // ---------------------------------------------------------------- state
  property bool opened: false
  property int openGen: 0
  property string filterText: ""
  property int selectedIndex: 0
  property var history: []
  property var historyKeys: []
  property var rows: []
  property var times: ({})
  property bool timesLoaded: false
  property bool historySeen: false
  property string lastTopKey: ""
  property var imageMeta: ({})
  property double now: Date.now()
  property bool caretOn: true

  // The plugin's private state folder: `stateReady` once the setup helper has run,
  // `stateOK` only if it found the folder safe (a real directory we own, mode
  // 0700). Until then nothing is read from or written to it. The salt keys the
  // timestamp labels; without a safe folder a throwaway one is used.
  property string salt: ""
  property bool stateReady: false
  property bool stateOK: false

  // Saved clips and the open tab ("history" or a category id). When the file
  // cannot be read, nothing is allowed to write over it.
  // (Not named "data": that is the default property of every Item, and a property
  // of that name never took its initial value.)
  property var store: Categories.emptyData()
  property bool catsWritable: false
  property string catsError: ""
  property string tab: "history"
  readonly property var activeCat: root.tab === "history" ? null : Categories.find(root.store, root.tab)
  readonly property bool inCategory: root.activeCat !== null

  // Modal state: "" | "menu" | "name" | "confirm".
  property string modal: ""
  property string menuKind: "card"       // "card" | "tab"
  property var menuTarget: null          // entry snapshot (card) or category id (tab)
  property var menuItems: []
  property int menuCursor: 0
  property var subItems: []
  property int subCursor: 0
  property int subFor: -1
  property bool subOpen: false
  property real menuAnchorX: 0
  property real menuAnchorBottom: 0      // distance from the screen's bottom edge
  property string nameMode: ""           // "new" | "rename"
  property string nameInput: ""
  property var nameTarget: null          // category id for rename, entry snapshot for new-and-save
  property string confirmText: ""
  property string confirmAction: ""
  property var confirmTarget: null

  // "Copied" / "Saved to X" confirmation shown on a card, found by the entry's
  // complete content (or saved-clip id), never by a fingerprint.
  property var flashT: null
  property string flashText: ""

  // Rows are replaced only when nothing is mid-interaction: not while a menu or
  // dialog is open, nor while a mouse button is down on a card. `rowsGen` counts
  // replacements, so a press can tell whether the cards changed under it.
  property int rowsGen: 0
  property double rowsStamp: 0
  property bool rebuildPending: false
  property bool pressActive: false
  property int pendingSelect: -1

  property bool historyMissing: false
  property bool setupRunning: false
  property string storeText: ""
  property string notice: ""
  property string commitReason: ""

  // The helper process of a paste that has not fired yet.
  property var pendingPut: null

  // ---------------------------------------------------------------- tokens
  readonly property color panelColor: Commons.Color.menu.background
  readonly property color textColor: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property color cardColor: Qt.tint(panelColor, Util.alpha(textColor, 0.075))
  readonly property string fontFamily: Style.font.menuFamily
  readonly property string monoFamily: "monospace"
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(1)))
  readonly property int panelRadius: Math.max(Style.cornerRadius, Style.space(14))
  readonly property int cardRadius: Math.max(Style.cornerRadius, Style.space(9))

  readonly property int panelHeight: Style.space(332)
  readonly property int sidePad: Style.space(18)
  readonly property int cardWidth: Style.space(230)
  readonly property int cardGap: Style.space(14)
  readonly property int cardStep: cardWidth + cardGap
  readonly property int topRowHeight: Style.space(34)
  readonly property int displayLimit: 100

  // Palette: the theme's own colour roles, read from the current theme file.
  property var palette: ({})
  function rotated(hueShift, sat, light) {
    var h = (accent.hslHue + hueShift) % 1
    if (h < 0) h += 1
    return Qt.hsla(h, sat, light, 1)
  }
  function roleColor(name) {
    var v = root.palette[name]
    if (v) return v
    var fallbacks = { blue: rotated(0.58, 0.45, 0.50), cyan: rotated(0.46, 0.45, 0.55), green: rotated(0.33, 0.45, 0.45),
      orange: accent, yellow: rotated(0.12, 0.60, 0.55), magenta: rotated(0.80, 0.40, 0.45), red: Commons.Color.urgent,
      brown: rotated(0.05, 0.35, 0.30), foreground: Commons.Color.foreground }
    return fallbacks[name] || accent
  }
  // Kind header colours: roles that differ in hue or lightness in the shipped themes.
  readonly property var kindColors: ({
    text: roleColor("foreground"), link: roleColor("cyan"), image: roleColor("green"),
    colour: roleColor("orange"), code: roleColor("red"), file: roleColor("brown")
  })
  function catColor(cat) {
    return cat ? roleColor(cat.color) : accent
  }
  function headerTextFor(c) {
    var lum = Classify.luminance(c.r, c.g, c.b)
    return lum > 0.32 ? Qt.rgba(0, 0, 0, 0.82) : Qt.rgba(1, 1, 1, 0.94)
  }

  onModalChanged: {
    if (root.modal === "" && root.rebuildPending) root.rebuildIfOpen()
  }

  // ---------------------------------------------------------------- API
  function open(payloadJson) {
    root.openGen++
    closeTimer.stop()
    flashTimer.stop()
    // A paste started by the last session must not land in this one.
    if (root.pendingPut) {
      root.pendingPut.running = false
      root.pendingPut = null
    }
    // Always opens on History, with nothing typed and the first card selected.
    root.tab = "history"
    root.filterText = ""
    root.selectedIndex = 0
    root.modal = ""
    root.flashT = null
    root.now = Date.now()
    root.forgetFailedProbes()
    themeFile.reload()
    // Anything that failed at load gets another try: setup (the state folder),
    // the history (it may have appeared, shrunk, or been fixed) and the categories.
    if (!root.stateOK) root.runSetup()
    root.reloadHistory()
    root.reloadCats()
    root.rebuild(true, true)
    root.targetScreen = root.focusedScreen()
    root.opened = true
    // The rebuild above ran before the panel counted as open, so start the probes now.
    root.startProbe()
    list.contentX = -list.leftMargin
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    closeTimer.stop()
    root.probeQueue = []
    root.modal = ""
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ---------------------------------------------------------------- screen
  property var targetScreen: null

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    }
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  readonly property var targetMonitor: {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      if (targetScreen && monitors[i].name === targetScreen.name) return monitors[i]
    }
    return null
  }

  // ---------------------------------------------------------------- history
  // Watched and timestamped even while the strip is hidden; cards are only
  // built when it is open.
  function loadHistory(raw) {
    var parsed = ClipboardHistory.parseHistory(raw)
    // Not a history at all: keep what we had rather than treating it as empty.
    if (parsed === null) return

    var keys = []
    for (var i = 0; i < parsed.length; i++) keys.push(Classify.entryFingerprint(parsed[i], root.salt))
    var previousTop = root.lastTopKey
    var hadHistory = root.historySeen

    root.history = parsed
    root.historyKeys = keys
    root.historySeen = true
    root.lastTopKey = keys.length > 0 ? keys[0] : ""

    // Stamp "copied at" when a new item lands on top. The built-in history
    // keeps no timestamps, so this is observed, not recorded by the capture.
    if (hadHistory && root.timesLoaded && keys.length > 0 && keys[0] !== previousTop) {
      var wasPushedDown = previousTop === "" || (keys.length > 1 && keys[1] === previousTop)
      if (wasPushedDown) root.stampTime(keys[0], Date.now())
    }
    root.pruneTimes()
    root.rebuildIfOpen()
  }

  function stampTime(key, ms) {
    if (!root.stateOK) return
    var next = {}
    for (var k in root.times) next[k] = root.times[k]
    next[key] = ms
    root.times = next
    root.saveTimes()
  }

  function pruneTimes() {
    // Only against a history that was really read, and a times file that was.
    if (!root.historySeen || !root.timesLoaded) return
    var keep = {}
    for (var i = 0; i < root.historyKeys.length; i++) keep[root.historyKeys[i]] = true
    var next = {}
    var dropped = false
    for (var k in root.times) {
      if (keep[k]) next[k] = root.times[k]
      else dropped = true
    }
    if (dropped) {
      root.times = next
      root.saveTimes()
    }
  }

  function saveTimes() {
    if (!root.stateOK || !root.timesArmed) return
    timesFile.setText(JSON.stringify(root.times) + "\n")
    root.tightenSoon()
  }

  // Delete from the stock history, safely: check its size, read the file as it is
  // now, drop only the entry whose complete content is the held snapshot's, and
  // write it back atomically. The plugin's own copy of the history is never
  // written over the file.
  function deleteHistoryEntry(t, done) {
    if (!t || t.clipId) return
    root.fileSize(root.historyPath, function(info) {
      if (info.state !== "size" || info.size > root.maxFileBytes) return
      var raw = root.readFresh(root.historyPath)
      if (raw === null || raw.length > ClipboardHistory.maxFileBytes) return
      var arr
      try { arr = JSON.parse(raw) } catch (e) { return }
      if (!Array.isArray(arr)) return
      var want = t.entryType === "image" ? { type: "image", path: t.path } : { type: "text", text: t.text }
      var at = -1
      for (var i = 0; i < arr.length; i++) {
        var n = ClipboardHistory.normalizeEntry(arr[i])
        if (n && ClipboardHistory.sameEntry(n, want)) { at = i; break }
      }
      // Already gone (or the file moved on): nothing to do.
      if (at < 0) return
      arr.splice(at, 1)
      historyFile.setText(JSON.stringify(arr, null, 2) + "\n")
      if (done) done()
      historyFile.reload()
    })
  }

  // ---------------------------------------------------------------- rows
  function rebuildIfOpen() {
    if (root.opened) root.rebuild(false, false)
  }

  // Whether two rows are the same entry: a saved clip by its id, a history entry
  // by its complete content.
  function rowsSame(a, b) {
    if (!a || !b) return false
    if (a.clipId || b.clipId) return a.clipId === b.clipId
    return ClipboardHistory.sameEntry(a.entry, b.entry)
  }

  // Does the card still describe the entry a confirmation was shown for?
  function flashMatches(row) {
    var f = root.flashT
    if (!f || !row) return false
    if (f.clipId || row.clipId) return !!f.clipId && f.clipId === row.clipId
    var e = row.entry
    if (!e) return false
    if (f.entryType === "image") return e.type === "image" && e.path === f.path
    return e.type === "text" && e.text === f.text
  }

  // A history image is previewed and probed only if its path is inside Omarchy's
  // own image folder and is free of anything that could confuse the probe output.
  function isStockImagePath(p) {
    var path = String(p || "")
    return path.indexOf(root.stockImagesDir + "/") === 0 && path.indexOf("..") < 0 && !/[\u0000-\u001f\u007f]/.test(path)
  }

  // resetSel: start at the first card (a new tab, search or open). Otherwise the
  // selection follows the entry it was on, and is empty if that entry is gone.
  // force: replace the rows even mid-interaction (the caller ended it).
  function rebuild(resetSel, force) {
    if (!force && (root.modal !== "" || root.pressActive)) {
      root.rebuildPending = true
      return
    }
    root.rebuildPending = false
    var prevRow = (!resetSel && root.selectedIndex >= 0 && root.selectedIndex < root.rows.length) ? root.rows[root.selectedIndex] : null
    var out = []
    var wanted = []
    var seenPaths = {}

    if (root.inCategory) {
      var needle = root.filterText.trim().toLowerCase()
      var clips = root.activeCat.clips
      for (var c = 0; c < clips.length; c++) {
        var clip = clips[c]
        if (needle) {
          var hay = clip.type === "image" ? "image screenshot" : clip.text.slice(0, Categories.displayTextLimit).toLowerCase()
          if (hay.indexOf(needle) < 0) continue
        }
        var crow = Categories.clipRow(clip, root.imagesDir)
        crow.previewImage = crow.previewPath ? Util.fileUrl(crow.previewPath) : ""
        crow.kind = Classify.kindOf({ entryType: crow.entryType, fullText: crow.fullText, previewImage: crow.previewImage })
        out.push(crow)
        if (crow.previewPath) {
          seenPaths[crow.previewPath] = true
          if (!root.imageMeta[crow.previewPath]) wanted.push(crow.previewPath)
        }
        if (out.length >= root.displayLimit) break
      }
    } else {
      var raw = ClipboardHistory.displayRows(root.history, root.filterText, root.displayLimit)
      for (var i = 0; i < raw.length; i++) {
        var r = raw[i]
        var row = {
          entryType: r.entryType,
          fullText: r.fullText,
          previewImage: root.isStockImagePath(r.previewImage) ? Util.fileUrl(r.previewImage) : "",
          previewPath: root.isStockImagePath(r.previewImage) ? r.previewImage : "",
          path: r.path,
          mime: r.mime,
          historyIndex: r.index,
          entry: r.source,
          clipId: "",
          savedAt: 0,
          key: root.historyKeys[r.index] || ""
        }
        row.kind = Classify.kindOf(r)
        var source = root.history[r.index]
        row.capped = !!source && source.type === "text" && String(source.text || "").length > r.fullText.length
        out.push(row)
        if (row.previewPath) {
          seenPaths[row.previewPath] = true
          if (!root.imageMeta[row.previewPath]) wanted.push(row.previewPath)
        }
      }
    }
    root.rowsGen++
    root.rowsStamp = Date.now()
    root.rows = out
    root.shownPaths = seenPaths
    root.evictMeta(seenPaths)

    if (out.length === 0) {
      root.selectedIndex = 0
    } else if (resetSel) {
      root.selectedIndex = 0
    } else if (root.pendingSelect >= 0) {
      root.selectedIndex = Math.min(root.pendingSelect, out.length - 1)
    } else if (prevRow) {
      var found = -1
      for (var f = 0; f < out.length; f++) if (root.rowsSame(prevRow, out[f])) { found = f; break }
      root.selectedIndex = found
    } else if (root.selectedIndex >= out.length) {
      root.selectedIndex = out.length - 1
    }
    root.pendingSelect = -1

    if (wanted.length > 0) root.probeImages(wanted)
  }

  // ---------------------------------------------------------------- images
  property var probeQueue: []
  property bool probeRunning: false
  property var shownPaths: ({})

  // Metadata only for images being shown; anything else is dropped.
  function evictMeta(keep) {
    var drop = false
    for (var k in root.imageMeta) if (!keep[k]) { drop = true; break }
    if (!drop) return
    var next = {}
    for (var p in root.imageMeta) if (keep[p]) next[p] = root.imageMeta[p]
    root.imageMeta = next
  }

  function invalidateMeta(path) {
    if (!root.imageMeta[path]) return
    var next = {}
    for (var p in root.imageMeta) if (p !== path) next[p] = root.imageMeta[p]
    root.imageMeta = next
  }

  // A probe that failed is remembered while the strip stays open (so it is not
  // retried on every rebuild) and forgotten on the next open.
  function forgetFailedProbes() {
    var next = {}
    var changed = false
    for (var p in root.imageMeta) {
      if (root.imageMeta[p].failed) changed = true
      else next[p] = root.imageMeta[p]
    }
    if (changed) root.imageMeta = next
  }

  function probeImages(paths) {
    var merged = root.probeQueue.slice()
    for (var i = 0; i < paths.length; i++) if (merged.indexOf(paths[i]) < 0) merged.push(paths[i])
    root.probeQueue = merged
    if (!root.probeRunning) root.startProbe()
  }

  function startProbe() {
    // Nothing is probed for a panel that is not showing.
    if (!root.opened || root.probeQueue.length === 0) return
    var batch = root.probeQueue.slice(0, 40)
    root.probeQueue = root.probeQueue.slice(40)
    root.probeRunning = true
    // A probe that overruns its deadline, or fails, leaves its images without a preview.
    root.runCapture(["sh", "-c",
      "t=$(printf '\\t'); for f in \"$@\"; do printf '%s\\t' \"$f\"; if [ -f \"$f\" ] && [ ! -L \"$f\" ]; then stat -c \"%s$t%Y$t\" -- \"$f\" 2>/dev/null | tr -d '\\n'; file -b -- \"$f\" 2>/dev/null | head -1; else echo; fi; done",
      "probe"].concat(batch), 8000, function(ok, text) {
      root.probeRunning = false
      root.applyProbe(ok ? text : "", batch)
      root.startProbe()
    })
  }

  function applyProbe(text, batch) {
    var next = {}
    for (var k in root.imageMeta) next[k] = root.imageMeta[k]
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split("\t")
      if (f.length < 4) continue
      // A result for an image that is no longer shown is dropped, not cached.
      if (!root.shownPaths[f[0]]) continue
      var dims = f[3].match(/(\d+)\s*x\s*(\d+)/)
      if (!dims) continue
      next[f[0]] = {
        bytes: Number(f[1]) || 0,
        mtime: (Number(f[2]) || 0) * 1000,
        width: Number(dims[1]),
        height: Number(dims[2])
      }
    }
    for (var j = 0; j < batch.length; j++) {
      if (root.shownPaths[batch[j]] && !next[batch[j]]) next[batch[j]] = { failed: true, bytes: 0, mtime: 0, width: 0, height: 0 }
    }
    root.imageMeta = next
  }

  // ---------------------------------------------------------------- card text
  function timeFor(row) {
    var ms = row.clipId ? row.savedAt : root.times[row.key]
    if (!ms && row.previewPath) {
      var meta = root.imageMeta[row.previewPath]
      if (meta && meta.mtime) ms = meta.mtime
    }
    return Classify.relativeTime(ms, root.now)
  }

  // Largest image that is decoded for a preview.
  readonly property int previewMaxBytes: 20 * 1024 * 1024
  readonly property int previewMaxPixels: 40000000

  // The preview URL only once the probe has reported an image of sane size;
  // until then, or for a larger one, the card shows a plain placeholder.
  function previewUrlFor(row) {
    if (!row.previewImage) return ""
    var meta = root.imageMeta[row.previewPath]
    if (!meta || meta.failed || !meta.width || !meta.height) return ""
    if (meta.bytes > root.previewMaxBytes || meta.width * meta.height > root.previewMaxPixels) return ""
    return row.previewImage
  }

  function previewNoteFor(row) {
    if (!row.previewPath && row.kind === "image") return "No preview"
    var meta = root.imageMeta[row.previewPath]
    if (!meta) return ""
    if (meta.failed || !meta.width) return "No preview"
    if (meta.bytes > root.previewMaxBytes || meta.width * meta.height > root.previewMaxPixels)
      return "Too large to preview\n" + meta.width + " \u00d7 " + meta.height
    return ""
  }

  // Cover-crop an image only when its shape is close to the card's body;
  // very wide or tall ones are fitted whole so they stay recognisable.
  function imageCropFor(row) {
    var meta = root.imageMeta[row.previewPath || row.path]
    if (!meta || !meta.width || !meta.height) return true
    var ratio = meta.width / meta.height
    return ratio > 0.7 && ratio < 1.9
  }

  function footerFor(row) {
    if (row.kind === "image") {
      var meta = root.imageMeta[row.previewPath || row.path]
      if (!meta || !meta.width) return "Image"
      var size = Classify.formatBytes(meta.bytes)
      return meta.width + " × " + meta.height + (size ? " · " + size : "")
    }
    if (row.kind === "file") {
      var n = row.fullText ? row.fullText.split("\n").length : 0
      return n + (n === 1 ? " file" : " files")
    }
    if (row.kind === "colour") {
      var c = Classify.parseColor(row.fullText)
      return c ? c.format.toUpperCase() + " color" : "Color"
    }
    return Classify.charsLabel(row.fullText, row.capped)
  }

  // ---------------------------------------------------------------- entry snapshots
  // The identity and full content of a row at this moment, or null if it is
  // already gone. Everything that acts on an entry works from this, never from
  // a row position or an index that a later capture could shift.
  function targetOf(row) {
    if (!row) return null
    var t = {
      key: row.key, clipId: row.clipId || "", catId: row.clipId ? root.tab : "",
      entryType: row.entryType, kind: row.kind, mime: row.mime, path: row.path, text: ""
    }
    if (row.entryType === "image") return t
    if (row.clipId) {
      var clip = row.clip
      if (!clip || clip.type !== "text") return null
      t.text = clip.text
    } else {
      // The entry this card was painted from; its complete content is the identity.
      var e = row.entry
      if (!e || e.type !== "text") return null
      t.text = String(e.text || "")
    }
    return t
  }

  // ---------------------------------------------------------------- processes
  Component {
    id: procComponent
    Process {
      id: proc
      property string payload: ""
      property bool hasPayload: false
      property var finished: null
      property var deadlineTimer: null
      property bool settled: false
      stdinEnabled: hasPayload

      // Runs once per process, whether it exited, never started, or overran.
      function settle(ok) {
        if (settled) return
        settled = true
        if (deadlineTimer) deadlineTimer.destroy()
        if (root.pendingPut === proc) root.pendingPut = null
        var f = finished
        if (f) f(ok)
        destroy()
      }

      onStarted: {
        if (hasPayload) {
          write(payload)
          stdinEnabled = false   // closes stdin: the helper reads until EOF
        }
      }
      onExited: function(code, status) { settle(code === 0 && status === 0) }
      // A process that fails to start emits no exit, only this.
      onRunningChanged: {
        if (!running && !settled) Qt.callLater(function() { if (!proc.settled) proc.settle(false) })
      }

    }
  }

  Component {
    id: deadlineComponent
    Timer {
      property var proc: null
      running: true
      repeat: false
      onTriggered: {
        if (proc) {
          proc.running = false
          proc.settle(false)
        }
      }
    }
  }

  // Runs a command, optionally feeding it `text` on stdin; calls back with
  // whether it exited 0.
  function runCmd(command, text, cb, deadlineMs) {
    var p = procComponent.createObject(root, {
      command: command,
      payload: text === null ? "" : text,
      hasPayload: text !== null,
      finished: cb
    })
    // Overran: stop it and count it as failed, so a queue waiting on it moves on.
    if (deadlineMs) p.deadlineTimer = deadlineComponent.createObject(root, { interval: deadlineMs, proc: p })
    p.running = true
    return p
  }

  // ---------------------------------------------------------------- clip actions
  // Hide at once and release the keyboard: the helper types into whichever
  // window gets focus back, so the strip must not linger.
  function closeNow() {
    closeTimer.stop()
    root.modal = ""
    root.opened = false
    revealAnim.stop()
    root.reveal = 0
  }

  function pasteTarget(t) {
    if (!t) return
    root.closeNow()
    if (t.entryType === "image") root.pendingPut = root.runCmd([root.imgPutScript, t.mime, t.path], null, null)
    else root.pendingPut = root.runCmd([root.putScript, "paste"], t.text, null)
  }

  function pastePlainTarget(t) {
    if (!t || t.entryType === "image") return
    root.closeNow()
    // Copied as text/plain and pasted with the same Shift+Insert as any paste, so
    // a terminal's own paste protection applies; the text is never typed key by key.
    root.pendingPut = root.runCmd([root.putScript, "plain"], t.text, null)
  }

  function copyTarget(t, cb) {
    if (!t) return
    if (t.entryType === "image") root.runCmd([root.imgPutScript, "--copy-only", t.mime, t.path], null, cb)
    else root.runCmd([root.putScript, "copy"], t.text, cb)
  }

  // A click: copy, and only once that really worked say so on the card and close.
  function copyAndClose(t) {
    if (!t) return
    var gen = root.openGen
    root.copyTarget(t, function(ok) {
      if (gen !== root.openGen) return
      root.flash(t, ok ? "Copied" : "Copy failed", ok)
    })
  }

  function flash(t, text, thenClose) {
    root.flashT = t
    root.flashText = text
    flashTimer.interval = 1200
    flashTimer.restart()
    if (thenClose) {
      closeTimer.gen = root.openGen
      closeTimer.restart()
    }
  }

  function openLinkTarget(t) {
    if (!t || t.entryType === "image") return
    // The exact string handed to xdg-open is checked here, not only when the card
    // was classified: http or https, no whitespace, no control characters.
    var url = t.text.trim()
    if (!Classify.isUrl(url)) return
    root.closeNow()
    Quickshell.execDetached(["xdg-open", url])
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.rows.length) return
    root.pasteTarget(root.targetOf(root.rows[index]))
  }

  function removeIndex(index) {
    if (index < 0 || index >= root.rows.length) return
    var t = root.targetOf(root.rows[index])
    root.removeTarget(t)
  }

  function removeTarget(t) {
    if (!t) return
    // After a removal the selection goes to the neighbour, not to nothing.
    var keep = root.selectedIndex
    var rowAtStart = (keep >= 0 && keep < root.rows.length) ? root.rows[keep] : null
    if (t.clipId) {
      root.removeClipTarget(t)
      root.pendingSelect = keep
      root.rebuildIfOpen()
    } else {
      root.deleteHistoryEntry(t, function() {
        // Only if the selection is still on the card the delete started from;
        // if the user moved meanwhile, that choice stands.
        if (rowAtStart && root.selectedIndex === keep && root.rows[keep] === rowAtStart) root.pendingSelect = keep
      })
    }
  }

  // ---------------------------------------------------------------- categories
  // All category writes go through here. Image files follow the category file,
  // never lead it, and only through the serialised queue below.
  property var saveOutcome: null

  function showNotice(text) {
    root.notice = text
    noticeTimer.restart()
  }

  Timer {
    id: noticeTimer
    interval: 4000
    onTriggered: root.notice = ""
  }

  function commitData(next) {
    root.commitReason = ""
    if (!root.catsWritable) {
      root.commitReason = "blocked"
      return false
    }
    var text = Categories.serialize(next)
    // The same store as the one on disk: nothing to write, and not a failure.
    if (text === root.storeText) {
      root.store = next
      return true
    }
    // Refuse a store the plugin would not read back, before anything changes.
    if (Categories.utf8Length(text, Categories.maxStoreBytes) > Categories.maxStoreBytes) {
      root.commitReason = "toolarge"
      root.showNotice("Saved clips are full (12 MiB limit), nothing was saved.")
      return false
    }
    var before = root.store
    root.store = next
    root.saveOutcome = null
    root.lastOwnWrite = Date.now()
    categoriesFile.setText(text)
    // Writes are synchronous, so the outcome is known here. Anything but a
    // confirmed save counts as failed: undo the edit and stop further changes.
    if (root.saveOutcome !== true) {
      root.lastOwnWrite = 0   // nothing of ours reached the disk
      root.store = before
      root.catsWritable = false
      root.commitReason = "writefailed"
      root.catsError = "Saved clips could not be written, so changes are blocked until the file can be written."
      root.rebuildIfOpen()
      return false
    }
    root.storeText = text
    root.tightenSoon()
    var orphans = Categories.orphanedImages(before, next)
    if (orphans.length > 0) root.enqueueImageOp({ kind: "gc", names: orphans })
    return true
  }

  property var imageQueue: []
  property bool imageBusy: false

  function enqueueImageOp(op) {
    var q = root.imageQueue.slice()
    q.push(op)
    root.imageQueue = q
    root.pumpImageQueue()
  }

  function imageOpDone() {
    root.imageBusy = false
    root.pumpImageQueue()
  }

  function pumpImageQueue() {
    if (root.imageBusy || root.imageQueue.length === 0) return
    var q = root.imageQueue.slice()
    var op = q.shift()
    root.imageQueue = q
    root.imageBusy = true
    if (op.kind === "save") root.runImageSave(op)
    else root.runImageGc(op)
  }

  function runImageSave(op) {
    root.runCmd([root.imgScript, op.src, op.name], null, function(ok) {
      if (!ok) {
        root.flash(op.t, "Could not save", false)
        root.imageOpDone()
        return
      }
      // The file is in place; only now does the category learn about it.
      root.invalidateMeta(root.imagesDir + "/" + op.name)
      var r = Categories.addClip(root.store, op.catId, op.clip)
      if (r.added && root.commitData(r.data)) {
        root.flash(op.t, "Saved to " + op.catName, false)
      } else {
        root.flash(op.t, r.reason === "duplicate" ? "Already in " + op.catName : "Could not save", false)
        // The copy has no reference: let the checked cleanup decide about the file.
        root.enqueueImageOp({ kind: "gc", names: [op.name] })
      }
      root.rebuildIfOpen()
      root.imageOpDone()
    }, 10000)
  }

  // Removal of image files nothing refers to any more: checked again against the
  // category file as it is now, after the removal that queued this was saved.
  function runImageGc(op) {
    root.fileSize(root.categoriesPath, function(info) {
      // A missing, unreadable or oversized file says nothing about what is used.
      if (info.state !== "size" || info.size > root.maxFileBytes) { root.imageOpDone(); return }
      var raw = root.readFresh(root.categoriesPath)
      var current = (raw === null || raw.length > ClipboardHistory.maxFileBytes) ? null : Categories.parse(raw)
      if (current === null) { root.imageOpDone(); return }
      var used = Categories.imagesInUse(current)
      // The helper takes bare file names and deletes only inside the plugin's folder.
      var gone = [root.imgRmScript]
      for (var i = 0; i < op.names.length; i++) if (!used[op.names[i]]) gone.push(op.names[i])
      if (gone.length === 1) { root.imageOpDone(); return }
      root.runCmd(gone, null, function(ok) { root.imageOpDone() }, 10000)
    })
  }

  function setTab(id) {
    if (id !== "history" && !Categories.find(root.store, id)) id = "history"
    if (id === root.tab) return
    root.tab = id
    root.filterText = ""
    root.selectedIndex = 0
    root.modal = ""
    root.rebuild(true, true)
    list.contentX = -list.leftMargin
  }

  function cycleTab(delta) {
    var ids = ["history"]
    for (var i = 0; i < root.store.categories.length; i++) ids.push(root.store.categories[i].id)
    var at = Math.max(0, ids.indexOf(root.tab))
    root.setTab(ids[(at + delta + ids.length) % ids.length])
  }

  function createCategory(name, thenSave) {
    if (!root.catsWritable) return ""
    var r = Categories.addCategory(root.store, name)
    if (r.reason === "toomany") {
      root.showNotice("Up to " + Categories.maxCategories + " categories.")
      return ""
    }
    if (!r.id || !root.commitData(r.data)) return ""
    if (thenSave) root.saveTarget(thenSave, r.id)
    return r.id
  }

  // Saves the entry's own content into a category (a copy that outlives the history).
  function saveTarget(t, catId) {
    var cat = Categories.find(root.store, catId)
    if (!t || !cat || !root.catsWritable) return
    var clip = { id: Categories.newId("k"), savedAt: Date.now() }
    if (t.entryType === "image") {
      var name = t.path.substring(t.path.lastIndexOf("/") + 1)
      clip.type = "image"
      clip.image = name
      clip.mime = t.mime
      var probe = Categories.addClip(root.store, catId, clip)
      if (!probe.added) {
        root.flash(t, probe.reason === "duplicate" ? "Already in " + cat.name : "Could not save", false)
        return
      }
      root.enqueueImageOp({ kind: "save", src: t.path, name: name, catId: catId, catName: cat.name, clip: clip, t: t })
      return
    }
    clip.type = "text"
    clip.text = t.text
    var r = Categories.addClip(root.store, catId, clip)
    if (r.added && root.commitData(r.data)) {
      root.rebuildIfOpen()
      root.flash(t, "Saved to " + cat.name, false)
    } else if (r.reason === "toolarge") {
      root.flash(t, "Too large (1 MiB max)", false)
    } else if (root.commitReason === "toolarge") {
      root.flash(t, "Saved clips are full", false)
    } else {
      root.flash(t, r.reason === "duplicate" ? "Already in " + cat.name : "Could not save", false)
    }
  }

  function removeClipTarget(t) {
    if (!t || !t.clipId || !root.catsWritable) return
    // Gone already: nothing to do.
    if (Categories.clipIndex(root.store, t.catId, t.clipId) < 0) return
    root.commitData(Categories.removeClip(root.store, t.catId, t.clipId))
  }

  function moveClipTarget(t, delta) {
    if (!t || !t.clipId || root.filterText || !root.catsWritable) return
    var at = Categories.clipIndex(root.store, t.catId, t.clipId)
    var cat = Categories.find(root.store, t.catId)
    if (at < 0 || !cat || at + delta < 0 || at + delta >= cat.clips.length) return
    root.commitData(Categories.moveClip(root.store, t.catId, t.clipId, delta))
    root.rebuildIfOpen()
    root.scrollToSelected(true)
  }

  function askDeleteCategory(id) {
    var cat = Categories.find(root.store, id)
    if (!cat || !root.catsWritable) return
    closeTimer.stop()
    root.confirmTarget = id
    root.confirmAction = "deleteCategory"
    root.confirmText = "Delete “" + cat.name + "”" + (cat.clips.length > 0 ? " and its " + cat.clips.length + (cat.clips.length === 1 ? " clip" : " clips") : "") + "?"
    confirmDialog.selectedIndex = 0
    root.modal = "confirm"
  }

  function askName(mode, target, initial) {
    if (!root.catsWritable) return
    closeTimer.stop()
    root.nameMode = mode
    root.nameTarget = target
    root.nameInput = initial || ""
    root.modal = "name"
  }

  function finishName() {
    var name = root.nameInput.trim()
    var mode = root.nameMode
    var target = root.nameTarget
    root.modal = ""
    if (!name) return
    if (mode === "rename") {
      if (Categories.find(root.store, target)) root.commitData(Categories.renameCategory(root.store, target, name))
    } else {
      var id = root.createCategory(name, target)
      if (id && !target) root.setTab(id)
    }
  }

  function finishConfirm() {
    var action = root.confirmAction
    var target = root.confirmTarget
    root.modal = ""
    if (action === "deleteCategory" && Categories.find(root.store, target)) {
      if (root.tab === target) root.setTab("history")
      root.commitData(Categories.deleteCategory(root.store, target))
      root.rebuildIfOpen()
    }
  }

  // ---------------------------------------------------------------- menus
  function cardMenuItems(t) {
    var items = [{ id: "paste", label: "Paste", hint: "Enter" }, { id: "copy", label: "Copy", hint: "Click" }]
    if (t.entryType !== "image" && t.kind !== "file") items.push({ id: "plain", label: "Paste as plain text" })
    if (t.kind === "link") items.push({ id: "open", label: "Open link" })
    if (root.catsWritable) items.push({ id: "save", label: "Save to category", sub: true })
    items.push({ separator: true })
    if (t.clipId) {
      var at = Categories.clipIndex(root.store, t.catId, t.clipId)
      var cat = Categories.find(root.store, t.catId)
      var count = cat ? cat.clips.length : 0
      if (!root.filterText && at > 0) items.push({ id: "left", label: "Move left", hint: "Shift+←" })
      if (!root.filterText && at >= 0 && at < count - 1) items.push({ id: "right", label: "Move right", hint: "Shift+→" })
      items.push({ id: "remove", label: "Remove from this category" })
    }
    items.push({ id: "delete", label: "Delete", hint: "Del", danger: true })
    return items
  }

  function saveSubItems() {
    var items = []
    for (var i = 0; i < root.store.categories.length; i++) {
      var c = root.store.categories[i]
      if (root.inCategory && c.id === root.tab) continue
      items.push({ id: "cat:" + c.id, label: c.name, swatch: root.catColor(c) })
    }
    if (items.length > 0) items.push({ separator: true })
    items.push({ id: "newcat", label: "New category…" })
    return items
  }

  function colourSubItems(catId) {
    var cat = Categories.find(root.store, catId)
    var names = { blue: "Blue", orange: "Orange", green: "Teal", foreground: "Cream", cyan: "Mint", yellow: "Amber", red: "Red", brown: "Brown" }
    var items = []
    for (var i = 0; i < Categories.colorCycle.length; i++) {
      var key = Categories.colorCycle[i]
      items.push({ id: "color:" + key, label: names[key] || key, swatch: root.roleColor(key), checked: !!cat && cat.color === key })
    }
    return items
  }

  function openCardMenu(t, anchorX, anchorBottom) {
    if (!t) return
    closeTimer.stop()
    root.menuKind = "card"
    root.menuTarget = t
    root.menuItems = root.cardMenuItems(t)
    root.menuCursor = 0
    root.subOpen = false
    root.menuAnchorX = anchorX
    root.menuAnchorBottom = anchorBottom
    root.modal = "menu"
  }

  // Menu / Shift+F10: anchored on the selected card.
  function openCardMenuFromKeyboard() {
    if (root.rows.length === 0 || root.selectedIndex < 0) return
    var t = root.targetOf(root.rows[root.selectedIndex])
    var x = root.selectedIndex * root.cardStep + root.sidePad - list.contentX - list.leftMargin + root.cardWidth / 2 - Style.space(20)
    root.openCardMenu(t, Math.max(root.sidePad, x), root.panelHeight - list.y - Style.space(40))
  }

  function openTabMenu(catId, anchorX, anchorBottom) {
    if (!root.catsWritable) return
    closeTimer.stop()
    root.menuKind = "tab"
    root.menuTarget = catId
    root.menuItems = [
      { id: "rename", label: "Rename", hint: "F2" },
      { id: "colour", label: "Change color", sub: true },
      { separator: true },
      { id: "deletecat", label: "Delete", danger: true }
    ]
    root.menuCursor = 0
    root.subOpen = false
    root.menuAnchorX = anchorX
    root.menuAnchorBottom = anchorBottom
    root.modal = "menu"
  }

  function openSub() {
    var item = root.menuItems[root.menuCursor]
    if (!item || !item.sub) return false
    if (item.id === "save") root.subItems = root.saveSubItems()
    else if (item.id === "colour") root.subItems = root.colourSubItems(root.menuTarget)
    else return false
    root.subCursor = 0
    root.subFor = root.menuCursor
    root.subOpen = true
    return true
  }

  function moveMenuCursor(delta, sub) {
    var items = sub ? root.subItems : root.menuItems
    var at = sub ? root.subCursor : root.menuCursor
    for (var n = 0; n < items.length; n++) {
      at = (at + delta + items.length) % items.length
      if (!items[at].separator) break
    }
    if (sub) root.subCursor = at
    else root.menuCursor = at
  }

  function runMenuItem(item) {
    if (!item || item.separator) return
    var t = root.menuKind === "card" ? root.menuTarget : null
    var catId = root.menuKind === "tab" ? root.menuTarget : ""
    var id = String(item.id)
    root.modal = ""
    root.subOpen = false
    if (id === "paste") root.pasteTarget(t)
    else if (id === "copy") root.copyAndClose(t)
    else if (id === "plain") root.pastePlainTarget(t)
    else if (id === "open") root.openLinkTarget(t)
    else if (id === "left") root.moveClipTarget(t, -1)
    else if (id === "right") root.moveClipTarget(t, 1)
    else if (id === "remove" || id === "delete") root.removeTarget(t)
    else if (id === "newcat") root.askName("new", t)
    else if (id.indexOf("cat:") === 0) root.saveTarget(t, id.substring(4))
    else if (id === "rename") {
      var cat = Categories.find(root.store, catId)
      if (cat) root.askName("rename", catId, cat.name)
    } else if (id === "deletecat") root.askDeleteCategory(catId)
    else if (id.indexOf("color:") === 0) {
      if (Categories.find(root.store, catId)) root.commitData(Categories.recolorCategory(root.store, catId, id.substring(6)))
    }
  }

  // Enter: the open submenu's row, else the parent row.
  function activateMenu() {
    if (root.subOpen) {
      root.runMenuItem(root.subItems[root.subCursor])
      return
    }
    root.chooseParent(root.menuCursor)
  }

  // A parent-menu row (click or Enter): open its submenu, or run it. Clicking an
  // already open parent leaves its submenu as it is and runs nothing.
  function chooseParent(index) {
    root.menuCursor = index
    var item = root.menuItems[index]
    if (!item || item.separator) return
    if (item.sub) {
      if (!(root.subOpen && root.subFor === index)) root.openSub()
    } else {
      root.runMenuItem(item)
    }
  }

  function endPress() {
    root.pressActive = false
    if (root.rebuildPending) root.rebuildIfOpen()
  }

  // ---------------------------------------------------------------- selection
  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild(true, true)
    list.contentX = -list.leftMargin
  }

  function select(index) {
    if (root.rows.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(index, root.rows.length - 1))
    root.scrollToSelected(true)
  }

  // ---------------------------------------------------------------- scrolling
  function clampX(x) {
    var maxX = Math.max(-list.leftMargin, list.contentWidth - list.width + list.rightMargin)
    return Math.max(-list.leftMargin, Math.min(x, maxX))
  }

  function scrollToSelected(animate) {
    if (root.selectedIndex < 0) return
    var left = root.selectedIndex * root.cardStep
    var right = left + root.cardWidth
    var target = list.contentX
    if (left < list.contentX + list.leftMargin) target = left - list.leftMargin
    else if (right > list.contentX + list.width - list.rightMargin) target = right - list.width + list.rightMargin
    target = root.clampX(target)
    scrollAnim.stop()
    if (animate && Style.duration(1) > 0) {
      scrollAnim.to = target
      scrollAnim.start()
    } else {
      list.contentX = target
    }
  }

  // First card whose left edge is in view; Ctrl+1 pastes this one.
  readonly property int firstVisible: Math.max(0, Math.ceil((list.contentX - 4) / root.cardStep))
  function visibleCount() {
    var count = 0
    for (var i = firstVisible; i < root.rows.length; i++) {
      var right = i * root.cardStep + root.cardWidth
      if (right > list.contentX + list.width) break
      count++
    }
    return Math.min(9, count)
  }

  // ---------------------------------------------------------------- plumbing
  // Writes to the category file stay off from now until a load has parsed it (or
  // found it missing). Every reload switches them off first.
  property double lastOwnWrite: 0

  // A file is read at all only if it is no larger than this (bytes). The size is
  // asked of the file system first, so an oversized file is never loaded.
  readonly property int maxFileBytes: ClipboardHistory.maxFileBytes

  // A command whose output is wanted: settled exactly once, with (ok, text), on
  // normal exit, failed start, or a deadline. ok means it exited 0.
  Component {
    id: captureComponent
    Process {
      id: cap
      property var finished: null
      property var deadlineTimer: null
      property bool settled: false
      property bool gotExit: false
      property bool gotStream: false
      property int exitCode: -1
      property string out: ""

      function settle(ok, text) {
        if (settled) return
        settled = true
        if (deadlineTimer) deadlineTimer.destroy()
        var f = finished
        finished = null
        if (f) f(ok, text === undefined ? "" : text)
        destroy()
      }
      function maybeSettle() {
        if (gotExit && gotStream) settle(exitCode === 0, out)
      }

      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          cap.out = text
          cap.gotStream = true
          cap.maybeSettle()
        }
      }
      onExited: function(code, status) {
        cap.exitCode = status === 0 ? code : -1
        cap.gotExit = true
        cap.maybeSettle()
      }
      // A process that fails to start emits no exit, only this.
      onRunningChanged: {
        if (!running && !settled && !gotExit) Qt.callLater(function() { if (!cap.settled && !cap.gotExit) cap.settle(false, "") })
      }
    }
  }

  function runCapture(command, deadlineMs, cb) {
    var p = captureComponent.createObject(root, { command: command, finished: cb })
    p.deadlineTimer = deadlineComponent.createObject(root, { interval: deadlineMs || 5000, proc: p })
    p.running = true
  }

  // Calls back with { state: "size", size }, { state: "missing" } (the load then
  // reports that itself) or { state: "error" } (stat could not tell).
  function fileSize(path, cb) {
    root.runCapture(["sh", "-c", "if [ -e \"$1\" ] || [ -L \"$1\" ]; then stat -c %s -- \"$1\"; else echo missing; fi", "sh", path], 5000, function(ok, text) {
      var t = String(text).trim()
      if (!ok) { cb({ state: "error" }); return }
      if (t === "missing") { cb({ state: "missing" }); return }
      var n = Number(t)
      if (t === "" || !isFinite(n) || n < 0) { cb({ state: "error" }); return }
      cb({ state: "size", size: n })
    })
  }

  readonly property string tooBigMessage: "The saved clips file is too large to read (over 16 MiB), so saved clips are read-only until it is fixed."
  readonly property string unreadableMessage: "The saved clips file could not be read, so saved clips are read-only until it is fixed."

  // Files are armed (given their path, which loads them) only after a size
  // check; from then on a reload is requested the same way after each check.
  property bool historyArmed: false
  property bool catsArmed: false
  property bool timesArmed: false

  function reloadCats() {
    root.catsWritable = false
    if (!root.stateOK) return
    root.fileSize(root.categoriesPath, function(info) {
      if (info.state === "error") {
        root.catsError = root.unreadableMessage
        root.rebuildIfOpen()
        return
      }
      if (info.state === "size" && info.size > root.maxFileBytes) {
        root.catsError = root.tooBigMessage
        root.rebuildIfOpen()
        return
      }
      if (!root.catsArmed) root.catsArmed = true
      else categoriesFile.reload()
    })
  }

  // The stock history: loaded only if it is a size we are willing to read. Missing
  // means an empty history (and the stock plugin may not be enabled); too large or
  // unreadable keeps the previous snapshot. Until the file can be watched
  // (`historyArmed`), a timer asks again, so the panel recovers on its own.
  function reloadHistory() {
    if (!root.stateReady) return
    root.fileSize(root.historyPath, function(info) {
      if (info.state === "missing") {
        root.historyMissing = true
        root.loadHistory("[]")
        return
      }
      if (info.state !== "size" || info.size > root.maxFileBytes) return
      root.historyMissing = false
      if (!root.historyArmed) root.historyArmed = true
      else historyFile.reload()
    })
  }

  Timer {
    interval: 4000
    repeat: true
    running: root.stateReady && !root.historyArmed
    onTriggered: root.reloadHistory()
  }

  function reloadTimes() {
    if (!root.stateOK) return
    root.fileSize(root.timesPath, function(info) {
      // A missing file is armed too, so there is a path to write to; the load then
      // reports it missing and starts the timestamps empty.
      if (info.state !== "missing" && (info.state !== "size" || info.size > root.maxFileBytes)) return
      if (!root.timesArmed) root.timesArmed = true
      else timesFile.reload()
    })
  }

  // Modes of what the plugin wrote are tightened a moment after each write.
  function tightenSoon() {
    if (root.stateOK) permTimer.restart()
  }

  Timer {
    id: permTimer
    interval: 400
    onTriggered: root.runCmd([root.setupScript], null, null, 8000)
  }

  function randomSalt() {
    var s = ""
    for (var i = 0; i < 24; i++) s += ("0" + Math.floor(Math.random() * 256).toString(16)).slice(-2)
    return s
  }

  // Make the private folder (0700, ours, not a symlink) and get the random salt.
  // Only then is anything read from or written to it. The exit code decides; the
  // output is the salt. Run at load and again on every open until it succeeds.
  function runSetup() {
    if (root.setupRunning) return
    root.setupRunning = true
    root.runCapture([root.setupScript], 10000, function(ok, text) {
      root.setupRunning = false
      root.finishSetup(ok ? String(text).trim() : "", ok)
    })
  }

  function finishSetup(salt, exitedOk) {
    var good = exitedOk && /^[0-9a-f]{48}$/.test(salt)
    root.stateOK = good
    if (good) root.salt = salt
    else if (root.salt === "") root.salt = root.randomSalt()
    root.stateReady = true
    if (!good) {
      root.catsWritable = false
      root.catsError = "The plugin's data folder is missing or not safe to use, so saved clips are turned off."
    }
    // (Re)start the loads; the salt may have changed, so the history is read again.
    root.reloadHistory()
    if (good) {
      root.reloadCats()
      root.reloadTimes()
    }
  }

  Component.onCompleted: {
    root.runSetup()
    themeFile.reload()
  }

  FileView {
    id: historyFile
    // The path is set only after the file's size has been checked (see
    // reloadHistory), so a file over the limit is never loaded at construction.
    path: root.historyArmed ? root.historyPath : ""
    watchChanges: true
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: {
      var raw = text()
      if (raw.length > root.maxFileBytes) return
      root.loadHistory(raw)
    }
    // A missing file is an empty history; any other failure keeps what we had.
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) root.loadHistory("[]")
    }
    onFileChanged: root.reloadHistory()
  }

  // A brand-new blocking reader per use: a long-lived one would hand back what
  // it read when it was created, not what is on disk now.
  Component {
    id: freshReader
    FileView {
      blockLoading: true
      printErrors: false
    }
  }

  function readFresh(path) {
    var fv = freshReader.createObject(root, { path: path })
    var text = null
    try { text = fv.text() } catch (e) { text = null }
    fv.destroy()
    return text
  }

  // Saved clips. atomicWrites writes a temp file next to it and renames it over.
  FileView {
    id: categoriesFile
    path: root.catsArmed ? root.categoriesPath : ""
    atomicWrites: true
    // Synchronous, so the image cleanup that follows a save reads what was saved.
    blockWrites: true
    printErrors: false
    onSaved: root.saveOutcome = true
    onSaveFailed: root.saveOutcome = false
    // Changes made by someone else (not our own write, which lands just before
    // this fires) are re-read, with writes off until that read has finished.
    watchChanges: true
    onFileChanged: {
      if (Date.now() - root.lastOwnWrite < 700) return
      root.reloadCats()
    }
    onLoaded: {
      var raw = text()
      var d = raw.length > root.maxFileBytes ? null : Categories.parse(raw)
      if (d === null) {
        root.catsWritable = false
        root.catsError = raw.length > root.maxFileBytes ? root.tooBigMessage : root.unreadableMessage
      } else {
        root.store = d
        root.storeText = raw
        root.catsWritable = true
        root.catsError = ""
      }
      root.rebuildIfOpen()
    }
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) {
        root.store = Categories.emptyData()
        root.storeText = ""
        root.catsWritable = true
        root.catsError = ""
      } else {
        root.catsWritable = false
        root.catsError = root.unreadableMessage
      }
      root.rebuildIfOpen()
    }
  }

  FileView {
    id: timesFile
    path: root.timesArmed ? root.timesPath : ""
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: {
      var parsed = null
      var raw = text()
      if (raw.length <= root.maxFileBytes) {
        try { parsed = JSON.parse(raw || "{}") } catch (e) { parsed = null }
      }
      root.times = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
      root.timesLoaded = true
      root.pruneTimes()
    }
    onLoadFailed: function(error) {
      // Only a missing file starts empty; an unreadable one is left alone.
      if (error === FileViewError.FileNotFound) {
        root.times = {}
        root.timesLoaded = true
      }
    }
  }

  FileView {
    id: themeFile
    path: root.themeColorsPath
    printErrors: false
    onLoaded: {
      var next = {}
      var lines = text().split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
        if (m) next[m[1]] = m[2]
      }
      root.palette = next
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

  Timer {
    interval: 530
    repeat: true
    running: root.opened
    onTriggered: root.caretOn = !root.caretOn
  }

  Timer {
    id: flashTimer
    onTriggered: root.flashT = null
  }

  // Closes the strip shortly after a successful copy, but only the session that
  // asked for it, and only if nothing else has been opened in the meantime.
  Timer {
    id: closeTimer
    property int gen: 0
    interval: 520
    onTriggered: {
      if (gen === root.openGen && root.opened && root.modal === "") root.close()
    }
  }

  NumberAnimation {
    id: scrollAnim
    target: list
    property: "contentX"
    duration: Style.duration(160)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Style.easeOut
  }

  // 0 = fully below the screen edge, 1 = fully up.
  property real reveal: 0
  readonly property bool windowReady: win.visible && !!root.targetScreen && !!root.targetMonitor
    && win.width === root.targetScreen.width
    && Math.round(win.devicePixelRatio * 120) === Math.round(root.targetMonitor.scale * 120)
  readonly property real revealTarget: (root.opened && root.windowReady) ? 1 : 0
  onRevealTargetChanged: {
    revealAnim.stop()
    revealAnim.to = root.revealTarget
    if (root.reveal !== root.revealTarget) revealAnim.start()
  }
  onRevealChanged: {
    if (root.reveal <= 0 && !root.opened) root.targetScreen = null
  }

  NumberAnimation {
    id: revealAnim
    target: root
    property: "reveal"
    duration: Style.duration(180)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Style.easeOut
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: slide
  }

  // ---------------------------------------------------------------- window
  PanelWindow {
    id: win

    visible: (root.opened || root.reveal > 0) && !!root.targetScreen && !!root.targetMonitor
    screen: root.targetScreen
    // Full screen, like the shell's own overlays: the part above the strip is a
    // transparent click-catcher, so a click outside the strip closes it and is not
    // passed on to the window behind. Menus then have the whole height to use.
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // Same namespace as the built-in panel so Hyprland's layer rules for it
    // (no compositor animation, glassy toggle) apply here too.
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) Hyprland.refreshMonitors()

    // A press anywhere outside the strip closes it (and any menu or dialog); the
    // press is consumed here, so it never reaches the window behind. Wheel
    // events are not handled, so scrolling out there changes nothing.
    MouseArea {
      anchors.fill: parent
      z: -1
      acceptedButtons: Qt.AllButtons
      onPressed: root.close()
    }

    // With a menu open, a press elsewhere on the strip closes only the menu.
    MouseArea {
      x: slide.x
      y: slide.y
      width: slide.width
      height: slide.height
      z: 5
      enabled: root.modal === "menu"
      acceptedButtons: Qt.AllButtons
      onPressed: root.modal = ""
    }

    Item {
      id: slide
      width: parent.width
      height: root.panelHeight
      y: parent.height - root.panelHeight + (1 - root.reveal) * root.panelHeight
      visible: root.reveal > 0

      BorderSurface {
        id: surface
        // Extra height pushes the bottom corners and edge off screen.
        x: 0
        y: 0
        width: parent.width
        height: parent.height + root.panelRadius * 2
        radius: root.panelRadius
        color: root.panelColor
        borderSpec: root.borderSpec

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onClicked: {}
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          event.accepted = true
          var text = event.text
          var printable = text && text.length === 1 && text.charCodeAt(0) >= 32 && text.charCodeAt(0) !== 127
          var ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
          var shift = event.modifiers & Qt.ShiftModifier

          if (root.modal === "name") {
            if (event.key === Qt.Key_Escape) root.modal = ""
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.finishName()
            else if (event.key === Qt.Key_Backspace) root.nameInput = ctrl ? root.nameInput.replace(/\s+$/, "").replace(/\S+$/, "") : root.nameInput.slice(0, -1)
            else if (!ctrl && printable && root.nameInput.length < 40) root.nameInput += text
            return
          }

          if (root.modal === "confirm") {
            confirmDialog.handleKey(event)
            return
          }

          if (root.modal === "menu") {
            if (event.key === Qt.Key_Escape) {
              // Esc closes only the menu; a submenu first.
              if (root.subOpen) root.subOpen = false
              else root.modal = ""
            } else if (event.key === Qt.Key_Up) root.moveMenuCursor(-1, root.subOpen)
            else if (event.key === Qt.Key_Down) root.moveMenuCursor(1, root.subOpen)
            else if (event.key === Qt.Key_Right) { if (!root.subOpen) root.openSub() }
            else if (event.key === Qt.Key_Left) root.subOpen = false
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activateMenu()
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
          } else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && shift)) {
            root.openCardMenuFromKeyboard()
          } else if (event.key === Qt.Key_F2) {
            if (root.inCategory) root.askName("rename", root.tab, root.activeCat.name)
          } else if (event.key === Qt.Key_Tab) {
            root.cycleTab(1)
          } else if (event.key === Qt.Key_Backtab) {
            root.cycleTab(-1)
          } else if (ctrl && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            root.cycleTab(event.key === Qt.Key_Right ? 1 : -1)
          } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            var nth = event.key - Qt.Key_1
            // Only on cards that have been painted: with a rebuild waiting, apply it
            // and ignore this press; right after a replacement, ignore it too.
            if (root.rebuildPending) root.rebuildIfOpen()
            else if (Date.now() - root.rowsStamp > 150 && nth < root.visibleCount()) root.activateIndex(root.firstVisible + nth)
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (event.key === Qt.Key_Delete) {
            root.removeIndex(root.selectedIndex)
          } else if (shift && root.inCategory && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            if (root.selectedIndex >= 0 && root.selectedIndex < root.rows.length)
              root.moveClipTarget(root.targetOf(root.rows[root.selectedIndex]), event.key === Qt.Key_Right ? 1 : -1)
          } else if (event.key === Qt.Key_Left) {
            pointerGate.reset()
            root.select(root.selectedIndex + (Commons.I18n.rightToLeft ? 1 : -1))
          } else if (event.key === Qt.Key_Right) {
            pointerGate.reset()
            root.select(root.selectedIndex + (Commons.I18n.rightToLeft ? -1 : 1))
          } else if (event.key === Qt.Key_Home) {
            root.select(0)
          } else if (event.key === Qt.Key_End) {
            root.select(root.rows.length - 1)
          } else if (event.key === Qt.Key_PageUp) {
            root.select(root.selectedIndex - Math.max(1, Math.floor(list.width / root.cardStep) - 1))
          } else if (event.key === Qt.Key_PageDown) {
            root.select(root.selectedIndex + Math.max(1, Math.floor(list.width / root.cardStep) - 1))
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateIndex(root.selectedIndex)
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            // Nothing to move through vertically.
          } else if (!ctrl && printable) {
            root.setFilter(root.filterText + text)
          } else {
            event.accepted = false
          }
        }
      }

      // ------------------------------------------------------------ top row
      Item {
        id: topRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.sidePad
        anchors.rightMargin: root.sidePad
        anchors.topMargin: Style.space(16)
        height: root.topRowHeight

        // Tabs: History, the categories, then "+".
        Flickable {
          id: tabs
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          width: Math.min(tabRow.width, Math.max(Style.space(120), (parent.width - field.width) / 2 - Style.space(20)))
          contentWidth: tabRow.width
          contentHeight: height
          clip: true
          interactive: contentWidth > width
          boundsBehavior: Flickable.StopAtBounds

          Row {
            id: tabRow
            height: parent.height
            spacing: Style.space(6)

            Repeater {
              model: [{ id: "history", name: "History" }].concat(root.store.categories)

              delegate: Rectangle {
                id: tabItem
                required property var modelData
                readonly property bool active: !!modelData && root.tab === modelData.id
                readonly property bool isHistory: !!modelData && modelData.id === "history"
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(28)
                width: tabLabel.x + tabLabel.implicitWidth + Style.space(12)
                radius: height / 2
                color: active ? Util.alpha(root.textColor, 0.15) : (tabHover.containsMouse ? Util.alpha(root.textColor, 0.08) : "transparent")
                border.width: active ? 1 : 0
                border.color: Util.alpha(root.textColor, 0.14)

                Rectangle {
                  id: tabDot
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(11)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(9)
                  height: width
                  radius: width / 2
                  color: tabItem.isHistory ? "transparent" : root.catColor(tabItem.modelData)
                  border.width: tabItem.isHistory ? 1 : 0
                  border.color: Util.alpha(root.textColor, 0.55)
                }

                Text {
                  id: tabLabel
                  anchors.verticalCenter: parent.verticalCenter
                  x: tabDot.x + tabDot.width + Style.space(7)
                  text: tabItem.modelData ? tabItem.modelData.name : ""
                  color: root.textColor
                  opacity: tabItem.active ? 1 : 0.62
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: tabItem.active
                  textFormat: Text.PlainText
                }

                MouseArea {
                  id: tabHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      if (tabItem.isHistory) return
                      root.setTab(tabItem.modelData.id)
                      var p = tabItem.mapToItem(slide, 0, 0)
                      root.openTabMenu(tabItem.modelData.id, p.x, root.panelHeight - p.y + Style.space(8))
                    } else {
                      root.setTab(tabItem.modelData.id)
                    }
                  }
                }
              }
            }

            Rectangle {
              id: plus
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              height: width
              radius: width / 2
              opacity: root.catsWritable ? 1 : 0.4
              color: plusHover.containsMouse ? Util.alpha(root.textColor, 0.12) : "transparent"
              border.width: 1
              border.color: Util.alpha(root.textColor, 0.2)

              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: "+"
                color: root.textColor
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                textFormat: Text.PlainText
              }

              MouseArea {
                id: plusHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.askName("new", null)
              }
            }
          }
        }

        Rectangle {
          id: field
          anchors.centerIn: parent
          width: Math.min(Style.space(380), parent.width - Style.space(520))
          height: parent.height
          radius: height / 2
          color: Util.alpha(root.textColor, 0.07)
          border.width: 1
          border.color: root.filterText ? Util.alpha(root.accent, 0.85) : Util.alpha(root.textColor, 0.14)

          Text {
            id: glass
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0349}"
            color: root.textColor
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
            textFormat: Text.PlainText
          }

          Item {
            id: typed
            anchors.left: glass.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            clip: true

            Text {
              id: typedText
              anchors.verticalCenter: parent.verticalCenter
              // Keep the end of long queries in view.
              x: Math.min(0, typed.width - width - caret.width - 2)
              visible: root.filterText.length > 0
              text: root.filterText
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              textFormat: Text.PlainText
            }

            Rectangle {
              id: caret
              width: Math.max(1, Style.space(2))
              height: Style.font.title + 2
              anchors.verticalCenter: parent.verticalCenter
              x: root.filterText.length > 0 ? typedText.x + typedText.width + 1 : 0
              color: root.accent
              visible: root.opened && root.caretOn && root.modal === ""
            }

            Text {
              visible: root.filterText.length === 0
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: caret.width + Style.space(6)
              text: root.inCategory ? "Search " + root.activeCat.name : "Type to search"
              color: root.textColor
              opacity: 0.45
              elide: Text.ElideRight
              width: parent.width - caret.width - Style.space(6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              textFormat: Text.PlainText
            }
          }
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: root.textColor
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          textFormat: Text.PlainText
          text: {
            var total = root.inCategory ? root.activeCat.clips.length : root.history.length
            var shown = root.rows.length
            if (root.filterText) return shown + " of " + total
            return total + (total === 1 ? " item" : " items")
          }
        }
      }

      // One plain line when the saved clips file could not be read.
      Text {
        id: catsBanner
        visible: root.catsError.length > 0 || root.notice.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topRow.bottom
        anchors.leftMargin: root.sidePad
        anchors.rightMargin: root.sidePad
        anchors.topMargin: Style.space(8)
        elide: Text.ElideRight
        text: root.catsError.length > 0 ? root.catsError : root.notice
        color: root.catsError.length > 0 ? Commons.Color.urgent : root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      // ------------------------------------------------------------ strip
      ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topRow.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: (root.catsError.length > 0 || root.notice.length > 0) ? Style.space(30) : Style.space(10)
        anchors.bottomMargin: Style.space(14)
        orientation: ListView.Horizontal
        leftMargin: root.sidePad
        rightMargin: root.sidePad
        spacing: root.cardGap
        model: root.rows
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: root.cardStep * 3
        flickDeceleration: 4000
        maximumFlickVelocity: 6000
        reuseItems: false

        // Wheel: vertical or horizontal notches both slide the strip.
        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            var d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
            scrollAnim.stop()
            pointerGate.reset()
            list.contentX = root.clampX(list.contentX - d * 1.1)
          }
        }

        delegate: Item {
          id: slot
          required property int index
          required property var modelData

          readonly property bool isSelected: index === root.selectedIndex
          readonly property int rank: index - root.firstVisible
          // Taken on press: what a click acts on, and the state it was taken in.
          property var pressT: null
          property int pressGen: -1
          property string pressTab: ""
          width: root.cardWidth
          height: ListView.view.height

          Card {
            id: card
            width: parent.width
            height: parent.height - Style.space(8)
            y: slot.isSelected ? 0 : Style.space(8)
            opacity: slot.isSelected ? 1 : 0.8
            Behavior on y { NumberAnimation { duration: Style.duration(120); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut } }
            Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }

            row: slot.modelData
            selected: slot.isSelected
            cardColor: root.cardColor
            textColor: root.textColor
            accent: root.accent
            headerColor: root.kindColors[slot.modelData.kind] || root.accent
            headerText: root.headerTextFor(headerColor)
            fontFamily: root.fontFamily
            monoFamily: root.monoFamily
            radius: root.cardRadius
            imageUrl: root.previewUrlFor(slot.modelData)
            imageNote: root.previewNoteFor(slot.modelData)
            timeText: root.timeFor(slot.modelData)
            footerText: root.footerFor(slot.modelData)
            shortcutText: slot.rank >= 0 && slot.rank < root.visibleCount() ? "Ctrl+" + (slot.rank + 1) : ""
            toast: root.flashMatches(slot.modelData) ? root.flashText : ""
            imageCrop: root.imageCropFor(slot.modelData)
          }

          // Hover is the same as keyboard selection, so the card a click
          // will take is always the ringed one.
          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPositionChanged: function(mouse) {
              if (root.modal === "") {
                if (pointerGate.moved(hover, mouse)) root.selectedIndex = slot.index
              }
            }
            onPressed: function(mouse) {
              root.pressActive = true
              slot.pressT = root.targetOf(slot.modelData)
              slot.pressGen = root.rowsGen
              slot.pressTab = root.tab
            }
            // After the click handler (released comes first), so a rebuild held back
            // during the press cannot cancel it.
            onReleased: Qt.callLater(function() { root.endPress() })
            onCanceled: root.endPress()
            onClicked: function(mouse) {
              // The cards or the tab changed since the press: cancel, do not guess.
              if (slot.pressT === null || slot.pressGen !== root.rowsGen || slot.pressTab !== root.tab) return
              root.selectedIndex = slot.index
              var t = slot.pressT
              if (mouse.button === Qt.RightButton) {
                var p = hover.mapToItem(slide, mouse.x, mouse.y)
                root.openCardMenu(t, p.x, root.panelHeight - p.y)
              } else {
                root.copyAndClose(t)
              }
            }
          }
        }
      }

      // ------------------------------------------------------------ empty
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: list.verticalCenter
        width: parent.width - root.sidePad * 2
        visible: root.rows.length === 0
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: root.textColor
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        textFormat: Text.PlainText
        text: {
          if (root.filterText) return "No matches for “" + root.filterText + "”"
          if (root.inCategory) return "Nothing saved here yet"
          if (root.historyMissing) return "No clipboard history found. Omarchy's built-in clipboard plugin records it and must be enabled."
          return "Nothing copied yet"
        }
      }

      // ------------------------------------------------------------ dialogs
      // The shell's own confirmation dialog.
      ConfirmDialog {
        id: confirmDialog
        z: 30
        anchors.fill: parent
        opened: root.modal === "confirm"
        message: root.confirmText
        cancelText: "Cancel"
        confirmText: "Delete"
        background: root.cardColor
        foreground: root.textColor
        scrim: Util.alpha(root.panelColor, 0.72)
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: root.fontFamily
        cornerRadius: root.cardRadius
        onCanceled: root.modal = ""
        onConfirmed: root.finishConfirm()
      }

      Rectangle {
        anchors.fill: parent
        visible: root.modal === "name"
        radius: root.panelRadius
        color: Util.alpha(root.panelColor, 0.72)
        z: 20
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.modal = "" }
      }

      BorderSurface {
        id: dialog
        z: 21
        visible: root.modal === "name"
        width: Style.space(400)
        height: Style.space(136)
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.space(96)
        radius: root.cardRadius + Style.space(3)
        color: root.cardColor
        borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(1)))
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: {} }

        Text {
          id: dialogTitle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(18)
          text: root.nameMode === "rename" ? "Rename category" : "New category"
          color: root.textColor
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          textFormat: Text.PlainText
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: dialogTitle.bottom
          anchors.margins: Style.space(18)
          anchors.topMargin: Style.space(12)
          height: Style.space(34)
          radius: height / 2
          color: Util.alpha(root.textColor, 0.07)
          border.width: 1
          border.color: Util.alpha(root.accent, 0.85)

          Item {
            anchors.fill: parent
            anchors.leftMargin: Style.space(16)
            anchors.rightMargin: Style.space(16)
            clip: true

            Text {
              id: nameText
              anchors.verticalCenter: parent.verticalCenter
              x: Math.min(0, parent.width - width - nameCaret.width - 2)
              text: root.nameInput
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              textFormat: Text.PlainText
            }
            Rectangle {
              id: nameCaret
              anchors.verticalCenter: parent.verticalCenter
              x: nameText.x + nameText.width + 1
              width: Math.max(1, Style.space(2))
              height: Style.font.title + 2
              color: root.accent
              visible: root.caretOn
            }
            Text {
              visible: root.nameInput.length === 0
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              text: "Name"
              color: root.textColor
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              textFormat: Text.PlainText
            }
          }
        }

        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(18)
          text: "Enter to save · Esc to cancel"
          color: root.textColor
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }
    }

    // ------------------------------------------------------------ menus
    // Placed from the bottom edge so they stay put while the window grows.
    MenuList {
      id: menuBox
      z: 10
      shown: root.modal === "menu"
      items: root.menuItems
      cursor: root.menuCursor
      maxHeight: win.height - Style.space(16)
      textColor: root.textColor
      selectedBackground: Commons.Color.menu.selectedBackground
      selectedText: Commons.Color.menu.selectedText
      dangerColor: Commons.Color.urgent
      fontFamily: root.fontFamily
      color: root.cardColor
      x: Math.max(Style.space(8), Math.min(root.menuAnchorX, win.width - width - subBox.menuWidth - Style.space(12)))
      y: Math.max(Style.space(8), Math.min(win.height - root.menuAnchorBottom - height, win.height - height - Style.space(8)))
      onHovered: function(index) { if (root.menuCursor !== index) { root.menuCursor = index; root.subOpen = false } }
      onChosen: function(index) { root.chooseParent(index) }
    }

    MenuList {
      id: subBox
      z: 11
      shown: root.modal === "menu" && root.subOpen
      items: root.subItems
      cursor: root.subCursor
      maxHeight: win.height - Style.space(16)
      textColor: root.textColor
      selectedBackground: Commons.Color.menu.selectedBackground
      selectedText: Commons.Color.menu.selectedText
      dangerColor: Commons.Color.urgent
      fontFamily: root.fontFamily
      color: root.cardColor
      menuWidth: Style.space(220)
      x: menuBox.x + menuBox.width + Style.space(4)
      y: Math.max(Style.space(8), Math.min(menuBox.y + menuBox.rowTop(root.subFor) - Style.space(6), win.height - height - Style.space(8)))
      onHovered: function(index) { root.subCursor = index }
      onChosen: function(index) {
        root.subCursor = index
        root.runMenuItem(root.subItems[index])
      }
    }
  }
}
