import QtQuick
import qs.Commons
import qs.Ui
import "Classify.js" as Classify

// One clipboard entry as a card: kind header, preview body, size footer.
// Pure presentation; selection and paste are handled by the strip.
Item {
  id: card

  property var row: null
  property bool selected: false

  property color cardColor: "#202020"
  property color textColor: "#dddddd"
  property color accent: "#ffffff"
  property color headerColor: "#888888"
  property color headerText: "#000000"
  property string fontFamily: "monospace"
  property string monoFamily: "monospace"
  property int radius: 8

  property string timeText: ""
  property string footerText: ""
  property string shortcutText: ""
  property url imageUrl: ""
  property string toast: ""
  property bool imageCrop: true
  property string imageNote: ""

  // Dimmed cards are drawn as one flattened layer, so overlapping parts of the
  // header do not show through each other.
  layer.enabled: opacity < 1

  readonly property string kind: row ? row.kind : "text"
  readonly property string clipName: row && row.name ? String(row.name) : ""
  readonly property string full: row ? String(row.fullText || "") : ""
  readonly property int pad: Style.space(12)
  readonly property int headerHeight: Style.space(28)
  readonly property int footerHeight: Style.space(26)
  readonly property color clearColor: Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0)

  Rectangle {
    id: face
    anchors.fill: parent
    radius: card.radius
    color: card.cardColor

    // Header band, rounded on top only.
    Item {
      id: header
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: card.headerHeight

      Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: card.headerColor
      }
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: card.radius
        color: card.headerColor
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: card.pad
        anchors.verticalCenter: parent.verticalCenter
        // A saved clip's own name takes the place of the kind label.
        width: Math.max(0, header.width - timeLabel.width - card.pad * 3)
        elide: Text.ElideRight
        text: card.clipName ? card.clipName : Classify.kindLabel(card.kind)
        color: card.headerText
        font.family: card.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        textFormat: Text.PlainText
      }

      Text {
        id: timeLabel
        anchors.right: parent.right
        anchors.rightMargin: card.pad
        anchors.verticalCenter: parent.verticalCenter
        text: card.timeText
        color: card.headerText
        opacity: 0.78
        font.family: card.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }

    // Body: swapped by kind so image and swatch machinery only exists where used.
    Item {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: header.bottom
      anchors.bottom: footer.top
      clip: true

      Loader {
        anchors.fill: parent
        sourceComponent: {
          switch (card.kind) {
          case "image": return imageBody
          case "colour": return colourBody
          case "link": return linkBody
          case "code": return codeBody
          case "file": return fileBody
          default: return textBody
          }
        }
      }

      // Soft fade where text or code runs out of room.
      Rectangle {
        visible: card.kind === "text" || card.kind === "code" || card.kind === "link" || card.kind === "file"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(44)
        gradient: Gradient {
          GradientStop { position: 0.0; color: card.clearColor }
          GradientStop { position: 1.0; color: card.cardColor }
        }
      }
    }

    Item {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: card.footerHeight

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Util.alpha(card.textColor, 0.1)
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: card.pad
        anchors.right: shortcut.visible ? shortcut.left : parent.right
        anchors.rightMargin: card.pad
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 1
        text: card.footerText
        color: card.textColor
        opacity: 0.6
        elide: Text.ElideRight
        font.family: card.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Text {
        id: shortcut
        visible: card.shortcutText.length > 0
        anchors.right: parent.right
        anchors.rightMargin: card.pad
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 1
        text: card.shortcutText
        color: card.textColor
        opacity: 0.45
        font.family: card.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }
  }

  // Short confirmation ("Copied", "Saved to ...") over the card body.
  Rectangle {
    id: toastPill
    visible: card.toast.length > 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(parent.width - card.pad * 2, toastText.implicitWidth + Style.space(28))
    height: Style.space(34)
    radius: height / 2
    color: card.accent
    border.width: 1
    border.color: Util.alpha(card.cardColor, 0.5)
    Text {
      id: toastText
      anchors.centerIn: parent
      width: parent.width - Style.space(20)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: "\u2713  " + card.toast
      color: card.cardColor
      font.family: card.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      textFormat: Text.PlainText
    }
  }

  // Ring: accent when selected, a faint edge otherwise.
  Rectangle {
    anchors.fill: parent
    radius: card.radius
    color: "transparent"
    border.width: card.selected ? 2 : 1
    border.color: card.selected ? card.accent : Util.alpha(card.textColor, 0.12)
  }

  // ---------------------------------------------------------------- bodies

  Component {
    id: textBody
    Item {
      // A few words fill a card better set larger and centred than as a
      // tiny line at the top with the rest empty.
      readonly property string shown: card.full.slice(0, 600).replace(/\n{3,}/g, "\n\n").trim()
      readonly property bool short: shown.length <= 90 && shown.split("\n").length <= 3
      readonly property int size: shown.length <= 28 ? Style.font.display : (shown.length <= 90 ? Style.font.heading + 2 : Style.font.body)

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: card.pad
        anchors.rightMargin: card.pad
        anchors.top: parent.short ? undefined : parent.top
        anchors.topMargin: Style.space(10)
        anchors.verticalCenter: parent.short ? parent.verticalCenter : undefined
        height: parent.short ? implicitHeight : parent.height - Style.space(10)
        text: parent.shown
        color: card.textColor
        wrapMode: Text.Wrap
        lineHeight: 1.22
        font.family: card.fontFamily
        font.pixelSize: parent.size
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignTop
        horizontalAlignment: parent.short ? Text.AlignHCenter : Text.AlignLeft
        clip: true
      }
    }
  }

  Component {
    id: codeBody
    Item {
      TextMetrics {
        id: metrics
        font.family: card.monoFamily
        font.pixelSize: Style.font.bodySmall
        text: "MMMMMMMMMM"
      }
      readonly property real charWidth: Math.max(1, metrics.advanceWidth / 10)

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: 0
        radius: Math.max(3, card.radius - 3)
        color: Util.alpha(card.textColor, 0.06)

        Text {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          text: Classify.codeLines(card.full.slice(0, 1200), Math.floor((width) / parent.parent.charWidth), 16)
          color: card.textColor
          wrapMode: Text.NoWrap
          lineHeight: 1.18
          font.family: card.monoFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          verticalAlignment: Text.AlignTop
          clip: true
        }
      }
    }
  }

  Component {
    id: linkBody
    Item {
      readonly property var parts: Classify.urlParts(card.full)

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: card.pad
        anchors.rightMargin: card.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: "\u{f0337}"
          color: card.headerColor
          font.family: card.fontFamily
          font.pixelSize: Style.font.display
          textFormat: Text.PlainText
        }

        Text {
          width: parent.width
          text: parent.parent.parts.host
          color: card.textColor
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 2
          elide: Text.ElideRight
          font.family: card.fontFamily
          font.pixelSize: parent.parent.parts.host.length <= 16 ? Style.font.display : Style.font.heading
          font.bold: true
          textFormat: Text.PlainText
        }

        Text {
          width: parent.width
          visible: text.length > 0
          text: parent.parent.parts.rest.replace(/^\/$/, "")
          color: card.textColor
          opacity: 0.6
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 5
          elide: Text.ElideRight
          font.family: card.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
      }
    }
  }

  Component {
    id: colourBody
    Item {
      readonly property var parsed: Classify.parseColor(card.full)
      readonly property string alt: {
        if (!parsed) return ""
        if (parsed.format !== "hex") {
          var h = function(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
          return "#" + h(parsed.r) + h(parsed.g) + h(parsed.b) + (parsed.a < 1 ? h(parsed.a) : "")
        }
        return Classify.rgbLabel(parsed)
      }

      Rectangle {
        id: swatch
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: valueColumn.top
        anchors.margins: Style.space(10)
        anchors.bottomMargin: Style.space(8)
        radius: Math.max(3, card.radius - 3)
        color: parent.parsed ? Qt.rgba(parent.parsed.r, parent.parsed.g, parent.parsed.b, parent.parsed.a) : "transparent"
        border.width: 1
        border.color: Util.alpha(card.textColor, 0.18)
      }

      Column {
        id: valueColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: card.pad
        anchors.rightMargin: card.pad
        anchors.bottomMargin: Style.space(10)
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: card.full.trim()
          color: card.textColor
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          font.family: card.monoFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          textFormat: Text.PlainText
        }
        Text {
          width: parent.width
          text: parent.parent.alt
          color: card.textColor
          opacity: 0.6
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          font.family: card.monoFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
      }
    }
  }

  Component {
    id: imageBody
    Item {
      Rectangle {
        anchors.fill: parent
        color: Util.alpha(card.textColor, 0.05)
        visible: !card.imageCrop || card.imageUrl == ""
      }
      SizedImage {
        anchors.fill: parent
        crop: card.imageCrop
        url: card.imageUrl
        asynchronous: true
        smooth: true
      }
      // Shown instead of a preview that is not loaded (too large, or unreadable).
      Text {
        visible: card.imageUrl == "" && card.imageNote.length > 0
        anchors.centerIn: parent
        width: parent.width - card.pad * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: card.imageNote
        color: card.textColor
        opacity: 0.6
        font.family: card.fontFamily
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }
    }
  }

  Component {
    id: fileBody
    Item {
      readonly property var names: {
        var out = []
        var lines = card.full.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("/")
          var name = parts[parts.length - 1] || lines[i]
          if (name) out.push(name)
        }
        return out
      }

      Text {
        anchors.fill: parent
        anchors.leftMargin: card.pad
        anchors.rightMargin: card.pad
        anchors.topMargin: Style.space(10)
        text: parent.names.slice(0, 7).map(function(n) { return "\u{f0214}  " + n }).join("\n")
        color: card.textColor
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        lineHeight: 1.3
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignTop
        clip: true
      }
    }
  }
}
