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

  // ---- injected / derived chrome -----------------------------------------
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var rows: service.models.length ? Model.summarize(service.models, settingsSortBy(), service.maxModels) : []
  readonly property double peakTokens: Model.maxTokenTotal(rows)
  readonly property bool hasData: rows.length > 0
  // null-safe totals for first-paint bindings
  readonly property var safeTotals: service.totals || { messages: 0, tokens: 0, cost: 0 }
  property double nowMs: Date.now()

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  function settingsSortBy() {
    var v = String(root.settings && root.settings.sortBy !== undefined ? root.settings.sortBy : "cost")
    return ["cost", "tokens", "messages"].indexOf(v) >= 0 ? v : "cost"
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

  // ---- bar pill -----------------------------------------------------------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // "·" sentinel: with text "" hasVisualContent is false and WidgetButton
    // zeroes the pill's opacity -> invisible AND dead to clicks. The middot
    // keeps hasVisualContent true (opacity 1) while labelVisible hides it.
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
      source: Qt.resolvedUrl("assets/opencode-usage.png")
    }
  }

  // ---- popout -------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(560))

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

          // header row — everything inline for compactness
          Item {
            width: parent.width
            implicitHeight: Math.max(headerTitle.implicitHeight, headerMeta.implicitHeight)

            Text {
              textFormat: Text.PlainText
              id: headerTitle
              anchors.left: parent.left
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

          Text {
            textFormat: Text.PlainText
            visible: !service.refreshing && !root.hasData && service.lastError === ""
            width: parent.width
            text: "No Go usage logged in the last " + service.windowDays + " day(s)."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // ---- OpenCode Go limit windows (5h / weekly / monthly) ----
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
                  id: bar
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
            width: parent.width
            text: "Best value on Go: MiMo-V2.5 (stretches $ limits furthest)"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // totals strip: three inline figures instead of cards
          Row {
            width: parent.width

            Column {
              width: parent.width / 3
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.hasData ? Model.tokenCount(root.safeTotals.tokens) : "—"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; textFormat: Text.PlainText }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "tokens"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
            }
            Column {
              width: parent.width / 3
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.hasData ? String(root.safeTotals.messages) : "—"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; textFormat: Text.PlainText }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "messages"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
            }
            Column {
              width: parent.width / 3
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.hasData ? Model.money(root.safeTotals.cost) : "—"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; textFormat: Text.PlainText }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "cost"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // tokens by day — one column per day: value on top, bar, weekday below
          Row {
            id: dayChart
            width: parent.width

            readonly property var days: service.days
            readonly property int dayCount: days.length
            readonly property double peak: Math.max(1, Model.recentPeak(days))
            readonly property double colWidth: dayCount > 0 ? width / dayCount : width
            readonly property int barArea: Style.space(26)
            // monospace advance is ~0.6em; drop the captions before they collide
            // (windowDays goes up to 30, which leaves each column ~12px wide)
            readonly property bool showValues: colWidth >= Style.font.caption * 3.6
            readonly property bool showLabels: colWidth >= Style.font.caption * 2.4

            Repeater {
              model: dayChart.days

              delegate: Column {
                id: dayCol
                required property var modelData
                required property int index
                readonly property bool isToday: index === dayChart.dayCount - 1
                readonly property double tokens: Model.dayTokens(modelData)

                width: dayChart.colWidth
                spacing: Style.space(3)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: dayChart.showValues
                  horizontalAlignment: Text.AlignHCenter
                  text: Model.tokenCount(dayCol.tokens)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Item {
                  width: parent.width
                  height: dayChart.barArea

                  Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(2, dayChart.colWidth * 0.42)
                    // idle days stay empty; any traffic at all keeps a hairline
                    height: dayCol.tokens > 0
                      ? Math.max(1, dayChart.barArea * dayCol.tokens / dayChart.peak)
                      : 0
                    radius: Style.space(1)
                    color: dayCol.isToday ? root.foreground : root.dim
                    Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: dayChart.showLabels
                  horizontalAlignment: Text.AlignHCenter
                  text: Model.dayLabel(dayCol.modelData.date)
                  color: dayCol.isToday ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // models by cost/tokens/messages
          Item {
            width: parent.width
            implicitHeight: Math.max(modelsHeader.implicitHeight, sortLabel.implicitHeight)

            Text {
              textFormat: Text.PlainText
              id: modelsHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "BY MODEL"
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
              text: root.settingsSortBy() + " ↓"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.rows

            delegate: RowLayout {
              id: modelRow
              required property var modelData
              width: body.width
              spacing: Style.space(6)

              Column {
                Layout.preferredWidth: root.nameColWidth(modelRow.modelData.displayName)
                Layout.alignment: Qt.AlignVCenter

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: modelData.displayName
                  color: modelData.isOther ? root.dim : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: !modelData.isOther
                  text: Model.providerTag(modelData.provider)
                  color: root.dim
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
                  text: Model.tokenCount(modelData.tokens.total) + " tok"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: !modelData.isOther
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  text: modelData.isOther
                    ? Model.tokenCount(modelData.messages) + " msgs"
                    : (Model.money(modelData.cost) + " · " + Model.providerTag(modelData.provider))
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.rows.length && !service.refreshing
            width: parent.width
            text: "No models."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  function nameColWidth(name) {
    return Math.min(Style.space(150), Style.space(9) * String(name).length + Style.space(20))
  }
}
