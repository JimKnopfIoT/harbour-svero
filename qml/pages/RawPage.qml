import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height

        PullDownMenu {
            MenuItem {
                text: veroval.busy ? qsTr("Downloading…") : qsTr("Download from device")
                enabled: !veroval.busy
                onClicked: veroval.download()
            }
        }

        Column {
            id: col
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Raw data / tuning") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("If the parsed values look wrong for your device, adjust the "
                         + "record start offset and length and re-parse. Default: base 3, "
                         + "length 14 (Veroval BPM25).")
            }

            Slider {
                id: baseSlider
                width: parent.width
                minimumValue: 0; maximumValue: 32; stepSize: 1
                value: 3
                label: qsTr("Record base offset")
                valueText: value
            }
            Slider {
                id: lenSlider
                width: parent.width
                minimumValue: 8; maximumValue: 32; stepSize: 1
                value: 14
                label: qsTr("Record length")
                valueText: value
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Re-parse (%1 found)").arg(veroval.count)
                onClicked: veroval.reparse(baseSlider.value, lenSlider.value)
            }

            SectionHeader { text: qsTr("Raw capture (%1 hex bytes)").arg(veroval.rawHex.length > 0 ? (veroval.rawHex.split(" ").length) : 0) }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                font.family: "monospace"
                color: Theme.primaryColor
                wrapMode: Text.WrapAnywhere
                text: veroval.rawHex.length ? veroval.rawHex : qsTr("(nothing captured yet)")
            }
        }
        VerticalScrollDecorator {}
    }
}
