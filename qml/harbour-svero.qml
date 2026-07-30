import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Notifications 1.0
import "pages"

ApplicationWindow {
    initialPage: Component { MainPage {} }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: Orientation.All

    Notification {
        id: banner
        isTransient: true
        appName: "svero"
    }
    function notify(msg) {
        banner.close()
        banner.previewSummary = "svero"
        banner.previewBody = msg
        banner.publish()
    }

    Connections {
        target: veroval
        onActionError: notify(message)
        onActionInfo: notify(message)
    }
}
