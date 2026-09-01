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

  // Hero subheading, in the spirit of the tailscale panel's active
  // phrases. A random one is drawn per open and holds until the panel
  // closes.
  readonly property var claudisms: [
    "COULD'VE BEEN AN EMAIL",
    "CIRCLING BACK",
    "ALIGNING THE STAKEHOLDERS",
    "SYNERGY IN PROGRESS",
    "CAMERA ON, SOUL OFF",
    "YOU'RE STILL ON MUTE?",
    "HARD STOP AT...",
    "MOVING THE NEEDLE"
  ]
  property int phraseIndex: 0

  property var meetings: []
  property bool addOpen: false
  property bool reorderMode: false
  // Live drag state: the row being dragged and where it would land now,
  // so the rows in between can step aside while the drag is in flight.
  property int dragFrom: -1
  property int dragTo: -1
  property bool cursorActive: false
  property int cursorIndex: 0
  property int editingIndex: -1

  function open() {
    phraseIndex = Math.floor(Math.random() * claudisms.length)
    root.controller.show()
  }

  function close() {
    root.cursorActive = false
    root.addOpen = false
    root.editingIndex = -1
    root.reorderMode = false
    root.dragFrom = -1
    root.dragTo = -1
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

  function updateMeeting(index, name, url) {
    url = String(url || "").trim()
    if (index < 0 || index >= meetings.length || !Model.isValidUrl(url)) return false
    var next = meetings.slice()
    next[index] = {
      name: String(name || "").trim() || Model.hostOf(url),
      url: url
    }
    saveMeetings(next)
    editingIndex = -1
    keyCatcher.forceActiveFocus()
    return true
  }

  function startEdit(index) {
    addOpen = false
    editingIndex = index
  }

  function cancelEdit() {
    editingIndex = -1
    keyCatcher.forceActiveFocus()
  }

  function moveMeeting(from, to) {
    if (from === to || from < 0 || to < 0 || from >= meetings.length || to >= meetings.length) return
    var next = meetings.slice()
    var entry = next.splice(from, 1)[0]
    next.splice(to, 0, entry)
    saveMeetings(next)
  }

  function removeMeeting(index) {
    if (index === editingIndex) editingIndex = -1
    else if (editingIndex > index) editingIndex--
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

  function launchOneOff() {
    var url = Model.normalizeUrl(oneOffField.text)
    if (!Model.isValidUrl(url)) return
    Quickshell.execDetached(["omarchy-launch-webapp", Model.launchUrl(url, root.zoomWebClient)])
    oneOffField.text = ""
    root.close()
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
    editingIndex = -1
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
    function edit(index: int): void {
      root.open()
      root.startEdit(index)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    // The extra popupPadding doubles the negative space under the last
    // section relative to the panel's uniform inner padding.
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight + Style.spacing.popupPadding)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: nameField.activeFocus || urlField.activeFocus || oneOffField.activeFocus || root.editingIndex >= 0
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.openMeeting(root.cursorIndex)
      onReturnRequested: if (root.cursorActive) root.openMeeting(root.cursorIndex)
      onDeleteRequested: if (root.cursorActive) root.removeMeeting(root.cursorIndex)
      onTextKey: function(text) {
        if (text === "a") root.openAddForm()
        else if (text === "e" && root.cursorActive) root.startEdit(root.cursorIndex)
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
          spacing: Style.space(14)

          // ---------- Hero: meetings icon · title + count · actions ----------
          // Mirrors the Bluetooth panel's hero rhythm and the network panel's
          // hero action buttons.
          Item {
            width: parent.width
            implicitHeight: Math.max(headerIcon.implicitHeight, headerLabels.implicitHeight, headerActions.implicitHeight)

            Text {
              id: headerIcon
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
            }

            Column {
              id: headerLabels
              anchors.left: headerIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.rightMargin: headerActions.width > 0 ? headerActions.width + Style.space(12) : 0
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

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
                id: heroPhrase
                textFormat: Text.PlainText
                width: parent.width
                text: root.claudisms[root.phraseIndex % root.claudisms.length]
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Button {
                iconText: "󰏫"
                tooltipText: "Reorder & edit"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                active: root.reorderMode
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                  root.reorderMode = !root.reorderMode
                  if (root.reorderMode) root.cancelAddForm()
                }
              }

              Button {
                iconText: "󰐕"
                tooltipText: "Add a meeting link (a)"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                active: root.addOpen
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.addOpen ? root.cancelAddForm() : root.openAddForm()
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

              Item {
                id: row
                required property var modelData
                required property int index

                readonly property bool editing: root.editingIndex === index
                readonly property bool hasCursor: root.cursorActive && root.cursorIndex === index && !editing
                readonly property bool hot: rowMouse.containsMouse || hasCursor

                property real pressY: 0
                property real dragOffset: 0
                property bool dragging: false

                readonly property real reorderStep: Style.space(36) + Style.space(2)
                // Rows between the drag origin and its current landing slot
                // step aside by one slot to open a gap for the drop.
                // Not readonly: the Behavior needs write access to animate.
                property real reorderShift: {
                  if (root.dragFrom < 0 || root.dragFrom === index) return 0
                  if (root.dragFrom < index && index <= root.dragTo) return -reorderStep
                  if (root.dragTo <= index && index < root.dragFrom) return reorderStep
                  return 0
                }

                Behavior on reorderShift {
                  NumberAnimation { duration: 130; easing.type: Easing.OutQuad }
                }

                width: parent.width
                implicitHeight: editing ? rowEditor.implicitHeight + Style.space(8) : Style.space(36)
                z: dragging ? 10 : 0

                onEditingChanged: {
                  if (editing) {
                    editName.text = modelData.name
                    editUrl.text = modelData.url
                    Qt.callLater(function() {
                      editName.forceActiveFocus()
                      editName.selectAll()
                    })
                  }
                }

                // Reorder-mode wiggle: each beat picks a fresh random tilt
                // and a small side-to-side offset instead of rocking on a
                // fixed cycle, so every row jitters on its own pattern.
                readonly property real wiggleSeed: Math.random()
                readonly property real wiggleRange: 0.1 + wiggleSeed * 0.08
                readonly property int wiggleBeat: Math.round(11 + wiggleSeed * 7)
                property real wiggleX: 0
                property real wiggleY: 0

                Timer {
                  running: root.reorderMode && !row.editing
                  interval: row.wiggleBeat
                  repeat: true
                  triggeredOnStart: true
                  onTriggered: {
                    // Independent random X and Y each beat: sometimes purely
                    // horizontal, sometimes vertical, often diagonal.
                    row.rotation = (Math.random() * 2 - 1) * row.wiggleRange
                    row.wiggleX = (Math.random() * 2 - 1) * 1.2
                    row.wiggleY = (Math.random() * 2 - 1) * 1.2
                  }
                  onRunningChanged: {
                    if (!running) {
                      row.rotation = 0
                      row.wiggleX = 0
                      row.wiggleY = 0
                    }
                  }
                }

                Behavior on rotation {
                  NumberAnimation { duration: row.wiggleBeat; easing.type: Easing.InOutQuad }
                }

                Behavior on wiggleX {
                  NumberAnimation { duration: row.wiggleBeat; easing.type: Easing.InOutQuad }
                }

                Behavior on wiggleY {
                  NumberAnimation { duration: row.wiggleBeat; easing.type: Easing.InOutQuad }
                }

                Rectangle {
                  visible: !row.editing
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: row.hot ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                  // Translate, not y: the rows Column owns y, but transforms
                  // apply after layout, so the dragged row can follow the
                  // pointer without fighting the positioner.
                  transform: Translate { x: row.wiggleX; y: row.dragOffset + row.wiggleY + row.reorderShift }

                  // Leading glyph, mirroring the bluetooth panel's device
                  // icon placement (leftmost, heading size, dimmed idle).
                  Text {
                    id: rowIcon
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: root.dimForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.heading
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: rowIcon.right
                    anchors.leftMargin: Style.space(10)
                    anchors.right: rowTrailing.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  // Right-edge glyph, in the wifi panel's right-glyph
                  // treatment (subtitle size, 1.4-darkened foreground).
                  // Swaps to a pencil while reordering: any click on the
                  // row then opens its inline editor.
                  Text {
                    id: rowChevron
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.reorderMode ? "󰏫" : "󰁜"
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                  }

                  Row {
                    id: rowTrailing
                    anchors.right: rowChevron.left
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
                  }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  enabled: !row.editing
                  visible: enabled
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: root.reorderMode ? Qt.OpenHandCursor : Qt.PointingHandCursor

                  onPressed: function(mouse) {
                    row.pressY = mouse.y
                    row.dragOffset = 0
                    row.dragging = false
                  }

                  onPositionChanged: function(mouse) {
                    if (!pressed || !root.reorderMode) return
                    var dy = mouse.y - row.pressY
                    if (Math.abs(dy) > 6) row.dragging = true
                    if (row.dragging) {
                      row.dragOffset = dy
                      root.dragFrom = row.index
                      var delta = Math.round(dy / row.reorderStep)
                      root.dragTo = Math.max(0, Math.min(root.meetings.length - 1, row.index + delta))
                    }
                  }

                  onReleased: {
                    if (!root.reorderMode) return
                    if (row.dragging) {
                      if (root.dragTo >= 0) root.moveMeeting(row.index, root.dragTo)
                    } else {
                      root.startEdit(row.index)
                    }
                    root.dragFrom = -1
                    root.dragTo = -1
                    row.dragOffset = 0
                    row.dragging = false
                  }

                  onClicked: if (!root.reorderMode) root.openMeeting(row.index)
                }

                Column {
                  id: rowEditor
                  visible: row.editing
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  TextField {
                    id: editName
                    width: parent.width
                    foreground: root.contentForeground
                    placeholderText: "Name"
                    onAccepted: editUrl.forceActiveFocus()
                    Keys.onEscapePressed: root.cancelEdit()
                  }

                  TextField {
                    id: editUrl
                    width: parent.width
                    foreground: root.contentForeground
                    placeholderText: "https://…"
                    onAccepted: root.updateMeeting(row.index, editName.text, editUrl.text)
                    Keys.onEscapePressed: root.cancelEdit()
                  }

                  Item {
                    width: parent.width
                    implicitHeight: editFormButtons.implicitHeight

                    Row {
                      id: editFormButtons
                      anchors.left: parent.left
                      spacing: Style.space(6)

                      Button {
                        text: "Save"
                        bordered: true
                        foreground: root.contentForeground
                        enabled: Model.isValidUrl(editUrl.text)
                        opacity: enabled ? 1 : 0.4
                        onClicked: root.updateMeeting(row.index, editName.text, editUrl.text)
                      }

                      Button {
                        text: "Cancel"
                        foreground: root.contentForeground
                        onClicked: root.cancelEdit()
                      }
                    }

                    // Destructive action alone at the right edge, with the
                    // urgent hover treatment the row's ✕ used to carry.
                    Button {
                      anchors.right: parent.right
                      anchors.verticalCenter: editFormButtons.verticalCenter
                      iconText: "󰅖"
                      text: "Remove"
                      foreground: root.contentForeground
                      accent: root.urgentColor
                      onClicked: root.removeMeeting(row.index)
                    }
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

            PanelSectionHeader {
              text: "ADD NEW MEETING"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

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
                iconText: "󰐕"
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

          // ---------- One-off launcher ----------
          PanelSeparator {
            foreground: root.contentForeground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "LAUNCH MEETING"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: oneOffField
                width: parent.width - launchBtn.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                foreground: root.contentForeground
                placeholderText: "One-off meeting url"
                onAccepted: root.launchOneOff()
                Keys.onEscapePressed: {
                  oneOffField.text = ""
                  keyCatcher.forceActiveFocus()
                }
              }

              Button {
                id: launchBtn
                text: "Launch"
                bordered: true
                foreground: root.contentForeground
                anchors.verticalCenter: parent.verticalCenter
                enabled: Model.isValidUrl(Model.normalizeUrl(oneOffField.text))
                opacity: enabled ? 1 : 0.4
                onClicked: root.launchOneOff()
              }
            }
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
    readonly property bool hovering: glyphMouse.containsMouse

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
