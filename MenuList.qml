import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A popup list in the shell menu's own style: menu surface, border from the
// theme, selected row in the menu's selected colours. Items are plain objects:
//   { id, label, hint, sub, swatch, danger, checked } or { separator: true }
// Taller than maxHeight, it scrolls and keeps the cursor row in view.
BorderSurface {
  id: menu

  property var items: []
  property int cursor: -1
  property color textColor: "#ffffff"
  property color selectedBackground: "#333333"
  property color selectedText: "#ffffff"
  property color dangerColor: "#ff5555"
  property string fontFamily: "monospace"
  property bool shown: false
  property int menuWidth: Style.space(262)
  property int maxHeight: Style.space(400)

  signal chosen(int index)
  signal hovered(int index)

  readonly property int rowHeight: Style.space(30)
  readonly property int separatorHeight: Style.space(9)
  readonly property int inset: Style.space(6)
  readonly property int contentHeight: {
    var h = 0
    for (var i = 0; i < items.length; i++) h += items[i].separator ? separatorHeight : rowHeight
    return h
  }
  readonly property int chrome: (inset + borderTop) * 2

  // Top edge of an item inside the visible menu, for lining a submenu up with its parent.
  function rowTop(index) {
    var y = inset + borderTop
    for (var i = 0; i < index && i < items.length; i++) y += items[i].separator ? separatorHeight : rowHeight
    return y - scroller.contentY
  }

  function ensureVisible() {
    if (cursor < 0 || cursor >= items.length) return
    var top = 0
    for (var i = 0; i < cursor; i++) top += items[i].separator ? separatorHeight : rowHeight
    var bottom = top + rowHeight
    if (top < scroller.contentY) scroller.contentY = top
    else if (bottom > scroller.contentY + scroller.height) scroller.contentY = bottom - scroller.height
  }

  onCursorChanged: ensureVisible()
  onItemsChanged: scroller.contentY = 0

  visible: shown && items.length > 0
  width: shown ? menuWidth : 0
  height: shown ? Math.min(contentHeight + chrome, maxHeight) : 0
  radius: Math.max(Style.cornerRadius, Style.space(9))
  borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(1)))

  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: {} }

  Flickable {
    id: scroller
    x: menu.borderLeft + menu.inset
    y: menu.borderTop + menu.inset
    width: menu.width - (menu.borderLeft + menu.borderRight) - menu.inset * 2
    height: menu.height - menu.chrome
    contentWidth: width
    contentHeight: menu.contentHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: menu.contentHeight > height

    Column {
      width: scroller.width

      Repeater {
        model: menu.items

        delegate: Item {
          id: entry
          required property int index
          required property var modelData

          readonly property bool isSep: !!modelData.separator
          readonly property bool hot: !isSep && menu.cursor === index
          width: parent.width
          height: isSep ? menu.separatorHeight : menu.rowHeight

          Rectangle {
            visible: entry.isSep
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            height: 1
            color: Util.alpha(menu.textColor, 0.14)
          }

          Rectangle {
            visible: !entry.isSep
            anchors.fill: parent
            radius: Math.min(Style.cornerRadius, Style.space(4)) + Style.space(3)
            color: entry.hot ? menu.selectedBackground : "transparent"
          }

          Rectangle {
            id: swatch
            visible: !entry.isSep && entry.modelData.swatch !== undefined
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(10)
            height: width
            radius: width / 2
            color: entry.modelData.swatch !== undefined ? entry.modelData.swatch : "transparent"
          }

          Text {
            visible: !entry.isSep
            anchors.left: swatch.visible ? swatch.right : parent.left
            anchors.leftMargin: swatch.visible ? Style.space(9) : Style.space(12)
            anchors.right: trailing.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: entry.modelData.label || ""
            elide: Text.ElideRight
            color: entry.modelData.danger ? menu.dangerColor : (entry.hot ? menu.selectedText : menu.textColor)
            font.family: menu.fontFamily
            font.pixelSize: Style.font.title
            textFormat: Text.PlainText
          }

          Text {
            id: trailing
            visible: !entry.isSep
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: entry.modelData.sub ? "›" : (entry.modelData.checked ? "✓" : (entry.modelData.hint || ""))
            color: entry.hot ? menu.selectedText : menu.textColor
            opacity: entry.modelData.sub || entry.modelData.checked ? 0.9 : 0.5
            font.family: menu.fontFamily
            font.pixelSize: entry.modelData.sub ? Style.font.heading : Style.font.caption
            textFormat: Text.PlainText
          }

          MouseArea {
            anchors.fill: parent
            enabled: !entry.isSep
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: menu.hovered(entry.index)
            onClicked: menu.chosen(entry.index)
          }
        }
      }
    }
  }
}
