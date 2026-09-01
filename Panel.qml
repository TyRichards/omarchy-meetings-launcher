import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.tyrichards.meetings"
  ipcTarget: "io.github.tyrichards.meetings"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property color dimForeground: Qt.darker(contentForeground, 1.5)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/meetings.json"
  readonly property bool zoomWebClient: setting("zoomWebClient", true) !== false

  property var meetings: []
  property bool editMode: false
  property bool addOpen: false
  property bool cursorActive: false
  property int cursorIndex: 0

  function open() {
    root.controller.show()
  }

  function close() {
    root.cursorActive = false
    root.addOpen = false
    root.editMode = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function loadMeetings(raw) {
    meetings = Model.parseMeetings(raw)
    if (cursorIndex >= meetings.length) cursorIndex = Math.max(0, meetings.length - 1)
  }

  function saveMeetings(next) {
    meetings = next
    meetingsFile.setText(Model.serialize(next))
  }

  function addMeeting(name, url) {
    url = String(url || "").trim()
    if (!Model.isValidUrl(url)) return false
    var next = meetings.slice()
    next.push({
      name: String(name || "").trim() || Model.hostOf(url),
      url: url
    })
    saveMeetings(next)
    return true
  }

  function removeMeeting(index) {
    if (index < 0 || index >= meetings.length) return
    var next = meetings.slice()
    next.splice(index, 1)
    saveMeetings(next)
    if (cursorIndex >= next.length) cursorIndex = Math.max(0, next.length - 1)
  }

  function openMeeting(index) {
    var entry = meetings[index]
    if (!entry) return
    Quickshell.execDetached(["omarchy-launch-webapp", Model.launchUrl(entry.url, root.zoomWebClient)])
    root.close()
  }

  function editConfigFile() {
    Quickshell.execDetached(["omarchy", "launch", "config", "editor", root.configPath])
  }

  function moveCursor(dy) {
    if (meetings.length === 0) return
    if (!cursorActive) {
      cursorActive = true
      if (dy > 0) cursorIndex = 0
      return
    }
    cursorIndex = Math.max(0, Math.min(meetings.length - 1, cursorIndex + dy))
  }

  function openAddForm() {
    addOpen = true
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function submitAddForm() {
    if (addMeeting(nameField.text, urlField.text)) {
      nameField.text = ""
      urlField.text = ""
      addOpen = false
      keyCatcher.forceActiveFocus()
    }
  }

  function cancelAddForm() {
    nameField.text = ""
    urlField.text = ""
    addOpen = false
    keyCatcher.forceActiveFocus()
  }

  FileView {
    id: meetingsFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadMeetings(text())
    onLoadFailed: root.loadMeetings("")
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { meetingsFile.reload() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: nameField.activeFocus || urlField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.openMeeting(root.cursorIndex)
      onReturnRequested: if (root.cursorActive) root.openMeeting(root.cursorIndex)
      onDeleteRequested: if (root.cursorActive) root.removeMeeting(root.cursorIndex)
      onTextKey: function(text) {
        if (text === "a") root.openAddForm()
        else if (text === "e") root.editMode = !root.editMode
      }

      Flickable {
        id: listScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: listScroll.width
          spacing: Style.space(10)

          // ---------- Header ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(headerLabels.implicitHeight, headerActions.implicitHeight)

            Text {
              id: headerIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "󰕧"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
            }

            Column {
              id: headerLabels
              anchors.left: headerIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.right: headerActions.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: "Meetings"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.meetings.length === 1
                  ? "1 LINK"
                  : root.meetings.length + " LINKS"
                color: root.dimForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.2
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              GlyphButton {
                glyph: "󰐕"
                hint: "Add a meeting link (a)"
                active: root.addOpen
                onClicked: root.addOpen ? root.cancelAddForm() : root.openAddForm()
              }

              GlyphButton {
                glyph: "󰏫"
                hint: "Edit list (e)"
                active: root.editMode
                onClicked: root.editMode = !root.editMode
              }
            }
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          // ---------- Meeting rows ----------
          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.meetings.length > 0

            Repeater {
              model: root.meetings

              Rectangle {
                id: row
                required property var modelData
                required property int index

                readonly property bool hasCursor: root.cursorActive && root.cursorIndex === index
                readonly property bool hot: rowMouse.containsMouse || hasCursor

                width: parent.width
                implicitHeight: Style.space(46)
                radius: Style.cornerRadius
                color: hot ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openMeeting(row.index)
                }

                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: rowTrailing.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: row.modelData.name
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: Model.hostOf(row.modelData.url)
                    color: root.dimForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                  }
                }

                Row {
                  id: rowTrailing
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: chipText.implicitWidth + Style.space(14)
                    implicitHeight: Style.space(20)
                    radius: Style.cornerRadius > 0 ? implicitHeight / 2 : 0
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
                    border.width: Style.spacing.hairline
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                    Text {
                      id: chipText
                      anchors.centerIn: parent
                      text: Model.providerLabel(row.modelData.url)
                      color: root.dimForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  GlyphButton {
                    visible: root.editMode
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰅖"
                    hint: "Remove"
                    danger: true
                    onClicked: root.removeMeeting(row.index)
                  }
                }
              }
            }
          }

          // ---------- Empty state ----------
          Text {
            visible: root.meetings.length === 0 && !root.addOpen
            width: parent.width
            text: "No meeting links yet. Add your Zoom, Meet, or RingCentral rooms and they'll open here as tiled web apps."
            color: root.dimForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          // ---------- Add form ----------
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.addOpen

            TextField {
              id: nameField
              width: parent.width
              foreground: root.contentForeground
              placeholderText: "Name (e.g. Daily Standup)"
              onAccepted: urlField.forceActiveFocus()
              Keys.onEscapePressed: root.cancelAddForm()
            }

            TextField {
              id: urlField
              width: parent.width
              foreground: root.contentForeground
              placeholderText: "https://zoom.us/j/…"
              onAccepted: root.submitAddForm()
              Keys.onEscapePressed: root.cancelAddForm()
            }

            Row {
              spacing: Style.space(6)

              Button {
                text: "Add"
                bordered: true
                foreground: root.contentForeground
                enabled: Model.isValidUrl(urlField.text)
                opacity: enabled ? 1 : 0.4
                onClicked: root.submitAddForm()
              }

              Button {
                text: "Cancel"
                foreground: root.contentForeground
                onClicked: root.cancelAddForm()
              }
            }
          }

          // ---------- Footer hint ----------
          Text {
            width: parent.width
            text: "Links open as tiled web-app windows · right-click the bar icon to edit the JSON"
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component GlyphButton: Rectangle {
    id: glyphButton

    property string glyph: ""
    property string hint: ""
    property bool active: false
    property bool danger: false

    signal clicked()

    implicitWidth: Style.space(26)
    implicitHeight: Style.space(26)
    radius: Style.cornerRadius
    color: glyphMouse.containsMouse || active
      ? Style.hoverFillFor(root.contentForeground, Color.accent)
      : "transparent"

    Text {
      anchors.centerIn: parent
      text: glyphButton.glyph
      color: glyphButton.danger && glyphMouse.containsMouse
        ? root.urgentColor
        : (glyphMouse.containsMouse || glyphButton.active
          ? Style.hoverStateColor(root.contentForeground, Color.accent)
          : root.dimForeground)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: glyphMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: glyphButton.clicked()
    }

    PanelToolTip {
      visible: glyphMouse.containsMouse && glyphButton.hint !== ""
      text: glyphButton.hint
    }
  }
}
