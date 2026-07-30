import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    Component {
        id: filePicker
        FilePickerPage {
            title: qsTr("Select a saved archive")
            nameFilters: [ "*.json" ]
            onSelectedContentPropertiesChanged:
                veroval.loadFromFile(selectedContentProperties.filePath, true)
        }
    }

    // Colour code by hypertension grade (systolic).
    function sysColor(sys) {
        if (sys >= 160) return "#E53935"       // grade 2+
        if (sys >= 140) return "#FB8C00"       // grade 1
        if (sys >= 130) return "#FDD835"       // high-normal
        return "#43A047"                        // normal
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: veroval.measurements

        header: Column {
            width: list.width
            PageHeader { title: qsTr("Veroval") }

            Item {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: statusRow.height
                Row {
                    id: statusRow
                    spacing: Theme.paddingMedium
                    BusyIndicator { running: veroval.busy; size: BusyIndicatorSize.Small
                        anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: veroval.statusText
                        color: Theme.secondaryHighlightColor
                    }
                }
            }
            Item { width: 1; height: Theme.paddingMedium }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Chart / graph")
                visible: veroval.count > 0
                onClicked: pageStack.push(Qt.resolvedUrl("ChartPage.qml"))
            }
            MenuItem {
                text: qsTr("Raw data / tuning")
                onClicked: pageStack.push(Qt.resolvedUrl("RawPage.qml"))
            }
            MenuItem {
                text: qsTr("Export CSV")
                visible: veroval.count > 0
                onClicked: veroval.exportCsv()
            }
            MenuItem {
                text: qsTr("Load archive file…")
                onClicked: pageStack.push(filePicker)
            }
            MenuItem {
                text: qsTr("Save archive to file")
                visible: veroval.count > 0
                onClicked: veroval.saveToFile()
            }
            MenuItem {
                text: veroval.busy ? qsTr("Downloading…") : qsTr("Download from device")
                enabled: !veroval.busy
                onClicked: veroval.download()
            }
        }

        ViewPlaceholder {
            enabled: veroval.count === 0 && !veroval.busy
            text: qsTr("No measurements")
            hintText: qsTr("Connect the Veroval via USB (data cable), put it into "
                         + "PC/transfer mode, then pull down and download.")
        }

        delegate: ListItem {
            id: item
            width: list.width
            contentHeight: Theme.itemSizeMedium
            property var m: modelData

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingMedium

                Rectangle {
                    width: Theme.paddingSmall
                    height: Theme.itemSizeSmall
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: page.sysColor(item.m.systolic)
                }

                Column {
                    width: parent.width * 0.5
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        text: item.m.systolic + "/" + item.m.diastolic + " mmHg"
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    Label {
                        text: "P" + item.m.user + "  ·  " + item.m.timestamp
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                    }
                }

                Column {
                    width: parent.width * 0.35
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        text: "♥ " + item.m.pulse
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.highlightColor
                    }
                    Label {
                        visible: item.m.arrhythmia
                        text: qsTr("arrhythmia")
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: "#E53935"
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
