import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "local.opencode-go-usage"
  ipcTarget: "local.opencode-go-usage"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var picks: service.picks
  readonly property var rows: service.catalog.length
    ? Model.summarizeCatalog(service.catalog, service.pricing, settingsSortBy(), service.maxModels, service.picks)
    : []
  readonly property bool hasCatalog: service.catalog.length > 0
  property double nowMs: Date.now()

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  function settingsSortBy() {
    var v = String(root.settings && root.settings.sortBy !== undefined ? root.settings.sortBy : "cost")
    return ["cost", "quota", "name"].indexOf(v) >= 0 ? v : "cost"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    service.refresh()
  }

  onOpenedChanged: if (opened) {
    if (!service.lastUpdated || (Date.now() - service.lastUpdated.getTime()) > service.refreshIntervalSec * 1000) root.refresh()
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "·"
    labelVisible: false
    fixedWidth: Style.space(32)
    tooltipText: Model.tooltipLimits(service.windows, root.nowMs)
    active: false
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }

    Image {
      anchors.centerIn: parent
      width: Style.space(13)
      height: width
      visible: status === Image.Ready
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      source: Qt.resolvedUrl("assets/opencode-go-usage.png")
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh() }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scroll.contentItem
          property: "interactive"
          value: body.implicitHeight > scroll.height
        }

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(7)

          Item {
            width: parent.width
            implicitHeight: Math.max(headerIcon.implicitHeight, headerTitle.implicitHeight, headerMeta.implicitHeight)

            // Hero icon — same pattern as the network panel: Nerd Font glyph at
            // display size left of the title. f0483 = mdi:speedometer.
            Text {
              textFormat: Text.PlainText
              id: headerIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "\uF0483"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle * 1.5
            }

            Text {
              textFormat: Text.PlainText
              id: headerTitle
              anchors.left: headerIcon.right
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              text: "OpenCode Go"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              id: headerMeta
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: (service.refreshing ? "…" : (service.lastUpdated ? Qt.formatTime(service.lastUpdated, "HH:mm") : "never"))
                + " · R refresh"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: service.lastError !== ""
            width: parent.width
            text: service.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Item {
            visible: !!service.windows
            width: parent.width
            implicitHeight: Math.max(limitHeader.implicitHeight, limitMeta.implicitHeight)

            Text {
              textFormat: Text.PlainText
              id: limitHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "LIMITS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              id: limitMeta
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: !!service.windows.weekly && service.windows.weekly.status === "rate-limited"
              text: "rate-limited"
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: [
              { key: "rolling", label: "5h" },
              { key: "weekly", label: "Weekly" },
              { key: "monthly", label: "Monthly" }
            ]

            delegate: Column {
              id: windowRow
              required property var modelData
              width: parent.width
              spacing: Style.space(2)
              readonly property var w: Model.normalizeWindow(service.windows ? service.windows[modelData.key] : null, modelData.key, root.nowMs)

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  Layout.preferredWidth: Style.space(52)
                  text: modelData.label
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  Layout.fillWidth: true
                  height: Style.space(5)
                  radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
                  Layout.alignment: Qt.AlignVCenter

                  Rectangle {
                    width: parent.width * (windowRow.w ? windowRow.w.percent : 0)
                    height: parent.height
                    radius: parent.radius
                    color: modelData.key === "weekly" && Model.behindPace(windowRow.w, root.nowMs) ? root.urgent : root.foreground
                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  Layout.preferredWidth: Style.space(44)
                  text: windowRow.w ? Model.percent(windowRow.w.percent) : "—"
                  horizontalAlignment: Text.AlignRight
                  color: windowRow.w && modelData.key === "weekly" && Model.behindPace(windowRow.w, root.nowMs) ? root.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                visible: !!windowRow.w
                text: "resets " + (windowRow.w ? Model.countdown(windowRow.w.resetMs, root.nowMs) : "")
                horizontalAlignment: Text.AlignRight
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - 1 < 8 ? 8 : Style.font.caption - 1
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !service.windows || !service.windows.rolling
            width: parent.width
            text: "Add opencode-go key in ~/.local/share/opencode/auth.json for limits."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: !!root.picks && !!root.picks.volume
            text: "Stretch quota: opencode-go/" + (root.picks && root.picks.volume ? root.picks.volume.id : "")
              + " · " + (root.picks && root.picks.volume ? Model.formatReq5h(root.picks.volume.requests5h) : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: !!root.picks && !!root.picks.value
            text: "Best value: opencode-go/" + (root.picks && root.picks.value ? root.picks.value.id : "")
              + " · " + (root.picks && root.picks.value ? Model.formatReq5h(root.picks.value.requests5h) : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Item {
            width: parent.width
            implicitHeight: Math.max(catalogHeader.implicitHeight, sortLabel.implicitHeight)

            Text {
              textFormat: Text.PlainText
              id: catalogHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "CATALOG"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              id: sortLabel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.settingsSortBy() + " ↑"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.rows

            delegate: RowLayout {
              id: catalogRow
              required property var modelData
              width: body.width
              spacing: Style.space(6)

              Column {
                Layout.preferredWidth: root.nameColWidth(catalogRow.modelData.displayName)
                Layout.alignment: Qt.AlignVCenter

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: modelData.isOther ? modelData.displayName : modelData.displayName
                    + (modelData.pick ? " · " + Model.pickLabel(modelData.pick) : "")
                  color: modelData.isOther ? root.dim : (modelData.pick ? root.foreground : root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: !!modelData.pick
                  elide: Text.ElideMiddle
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: !modelData.isOther && modelData.note !== ""
                  text: modelData.note
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1 < 8 ? 8 : Style.font.caption - 1
                }
              }

              Item { Layout.fillWidth: true }

              Column {
                Layout.alignment: Qt.AlignVCenter

                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  visible: !modelData.isOther
                  text: modelData.hasPricing
                    ? (Model.pricePer1M(modelData.inputPer1M) + " in · " + Model.pricePer1M(modelData.outputPer1M) + " out")
                    : "pricing unknown"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  visible: !modelData.isOther
                  text: Model.formatReq5h(modelData.requests5h)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.hasCatalog && !service.refreshing && service.lastError === ""
            width: parent.width
            text: "Could not load Go catalog."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  function nameColWidth(name) {
    return Math.min(Style.space(170), Style.space(9) * String(name).length + Style.space(24))
  }
}
