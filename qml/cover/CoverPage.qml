import QtQuick 2.6
import Sailfish.Silica 1.0

CoverBackground {
    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "svero"
            font.pixelSize: Theme.fontSizeLarge
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: veroval.count > 0 ? veroval.count + qsTr(" readings")
                                    : qsTr("no data")
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    CoverActionList {
        CoverAction {
            iconSource: "image://theme/icon-cover-sync"
            onTriggered: veroval.download()
        }
    }
}
