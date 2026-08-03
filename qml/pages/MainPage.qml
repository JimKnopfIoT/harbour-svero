import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // The chart hangs off this page as an attached page, so a left swipe opens
    // it. It only makes sense once there is something to plot, hence the
    // re-check whenever the archive changes rather than a one-shot attach.
    function updateAttachedChart() {
        if (status !== PageStatus.Active)
            return
        if (veroval.count > 0 && !pageStack.nextPage(page))
            pageStack.pushAttached(Qt.resolvedUrl("ChartPage.qml"))
    }

    onStatusChanged: updateAttachedChart()
    Component.onCompleted: updateAttachedChart()

    Connections {
        target: veroval
        onMeasurementsChanged: page.updateAttachedChart()
    }

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
                        text: item.m.timestamp
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                    }
                }

                Column {
                    width: parent.width * 0.22
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

                // P1/P2 toggle. The device files each reading under the memory
                // slot it was measured in, but readings do end up in the wrong
                // one; the override lives in the archive and survives further
                // downloads.
                Rectangle {
                    id: personToggle
                    anchors.verticalCenter: parent.verticalCenter
                    property int person: item.m.person === 2 ? 2 : 1
                    width: Theme.itemSizeExtraSmall * 1.15
                    height: Theme.itemSizeExtraSmall * 0.66
                    radius: height / 2
                    color: person === 2 ? Theme.rgba(Theme.highlightColor, 0.35)
                                        : Theme.rgba(Theme.secondaryColor, 0.18)
                    border.color: person === 2 ? Theme.highlightColor
                                               : Theme.rgba(Theme.secondaryColor, 0.5)
                    border.width: 1

                    Rectangle {
                        width: parent.height - 6
                        height: width
                        radius: width / 2
                        y: 3
                        x: personToggle.person === 2 ? parent.width - width - 3 : 3
                        color: personToggle.person === 2 ? Theme.highlightColor
                                                         : Theme.secondaryColor
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    Label {
                        // Sits on whichever side the knob is not, so the label
                        // stays readable instead of being covered by it.
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: personToggle.person === 2 ? parent.left : undefined
                        anchors.right: personToggle.person === 2 ? undefined : parent.right
                        anchors.leftMargin: Theme.paddingSmall
                        anchors.rightMargin: Theme.paddingSmall
                        text: personToggle.person === 2 ? "P2" : "P1"
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.primaryColor
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.paddingMedium   // easier to hit
                        onClicked: {
                            // Flip locally and tell C++. Nothing re-reads the
                            // model here, so the list stays exactly where the
                            // user is looking; a later reload (download, file
                            // import) recreates the delegate and its binding.
                            var p = personToggle.person === 2 ? 1 : 2
                            personToggle.person = p
                            veroval.assignPerson(index, p)
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
