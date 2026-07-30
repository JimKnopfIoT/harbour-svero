import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // Palette: systolic = light blue, diastolic = dark blue, pulse = white;
    // grey is used for grid / labels / the range track.
    readonly property color colSys: "#4FC3F7"
    readonly property color colDia: "#1E5AA8"
    readonly property color colPulse: "#ECEFF1"

    // --- data helpers ------------------------------------------------------
    function dataRange() {
        var ms = veroval.measurements, minE = -1, maxE = 0
        for (var i = 0; i < ms.length; ++i) {
            var e = ms[i].epoch
            if (e <= 0) continue
            if (minE < 0 || e < minE) minE = e
            if (e > maxE) maxE = e
        }
        return [minE, maxE]
    }
    // Window from the two-handle bar. Left handle (selLeft) is the newer bound,
    // right handle (selRight) the older bound (mirrored axis: newest = left).
    function filtered() {
        var ms = veroval.measurements
        var mm = dataRange(), minE = mm[0], maxE = mm[1]
        if (minE < 0 || maxE === 0) return []
        var span = (maxE === minE) ? 1 : (maxE - minE)
        var newer = maxE - rangeBar.selLeft * span
        var older = maxE - rangeBar.selRight * span
        var out = []
        for (var i = 0; i < ms.length; ++i) {
            var e = ms[i].epoch
            if (e > 0 && e >= older - 1 && e <= newer + 1) out.push(ms[i])
        }
        out.sort(function(a, b) { return a.epoch - b.epoch })
        return out
    }
    function avg(data, key) {
        if (!data.length) return 0
        var s = 0
        for (var i = 0; i < data.length; ++i) s += data[i][key]
        return s / data.length
    }
    function fmtDate(data, which) {
        if (!data.length) return "–"
        var d = which === "new" ? data[data.length - 1] : data[0]
        return d.timestamp.substr(0, 10)
    }

    // Selected data point (by epoch), shown in the detail box.
    property double selEpoch: 0
    function selM() {
        if (selEpoch <= 0) return null
        var ms = veroval.measurements
        for (var i = 0; i < ms.length; ++i)
            if (ms[i].epoch === selEpoch) return ms[i]
        return null
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Export image (JPG)")
                enabled: veroval.count > 0
                onClicked: chartArea.grabToImage(function(res) {
                    var p = veroval.reserveImagePath()
                    if (res.saveToFile(p)) veroval.notify(qsTr("Image saved: ") + p)
                    else veroval.notify(qsTr("Image export failed"))
                })
            }
            MenuItem {
                text: qsTr("Export CSV")
                enabled: veroval.count > 0
                onClicked: veroval.exportCsv()
            }
        }

        Column {
            id: col
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Chart") }

            // --- movable range bar (two handles) --------------------------
            Item {
                id: rangeBar
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.itemSizeMedium              // tall = easy to hit

                property real selLeft: 0.0    // newer bound (0 = newest)
                property real selRight: 1.0   // older bound (1 = oldest)
                readonly property real hw: Theme.itemSizeExtraSmall
                readonly property real span: width - hw
                property int active: -1       // 0 = left, 1 = right, -1 = none

                function fracFromX(mx) { return Math.max(0, Math.min(1, (mx - hw / 2) / span)) }
                function cx(f) { return hw / 2 + f * span }   // centre x of a fraction

                Timer { id: repaintTimer; interval: 30; onTriggered: chart.requestPaint() }

                Rectangle {   // track
                    anchors.verticalCenter: parent.verticalCenter
                    x: rangeBar.hw / 2; width: rangeBar.span; height: 6; radius: 3
                    color: Theme.rgba(Theme.secondaryColor, 0.4)
                }
                Rectangle {   // selected span (between handle centres)
                    anchors.verticalCenter: parent.verticalCenter
                    x: rangeBar.cx(rangeBar.selLeft)
                    width: Math.max(2, rangeBar.cx(rangeBar.selRight) - rangeBar.cx(rangeBar.selLeft))
                    height: 6; radius: 3
                    color: Theme.rgba(page.colSys, 0.7)
                }
                Rectangle {   // left handle (newer) — visual only
                    width: rangeBar.hw; height: rangeBar.hw; radius: width / 2
                    y: (rangeBar.height - height) / 2
                    x: rangeBar.selLeft * rangeBar.span
                    color: page.colSys
                    border.color: "white"; border.width: rangeBar.active === 0 ? 3 : 2
                    scale: rangeBar.active === 0 ? 1.2 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                }
                Rectangle {   // right handle (older) — visual only
                    width: rangeBar.hw; height: rangeBar.hw; radius: width / 2
                    y: (rangeBar.height - height) / 2
                    x: rangeBar.selRight * rangeBar.span
                    color: Theme.secondaryHighlightColor
                    border.color: "white"; border.width: rangeBar.active === 1 ? 3 : 2
                    scale: rangeBar.active === 1 ? 1.2 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                }

                MouseArea {
                    anchors.fill: parent
                    function apply(mx) {
                        var f = rangeBar.fracFromX(mx)
                        if (rangeBar.active === 0)
                            rangeBar.selLeft = Math.min(f, rangeBar.selRight - 0.02)
                        else if (rangeBar.active === 1)
                            rangeBar.selRight = Math.max(f, rangeBar.selLeft + 0.02)
                        repaintTimer.restart()
                    }
                    onPressed: {
                        var f = rangeBar.fracFromX(mouse.x)
                        rangeBar.active = (Math.abs(f - rangeBar.selLeft) <= Math.abs(f - rangeBar.selRight)) ? 0 : 1
                        apply(mouse.x)
                    }
                    onPositionChanged: if (rangeBar.active >= 0) apply(mouse.x)
                    onReleased: { rangeBar.active = -1; chart.requestPaint() }
                    onCanceled: rangeBar.active = -1
                }
            }

            // selected window summary
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                property var d: page.filtered()
                text: d.length
                      ? qsTr("Newest %1  ←→  oldest %2   (n=%3)")
                          .arg(page.fmtDate(d, "new")).arg(page.fmtDate(d, "old")).arg(d.length)
                      : qsTr("no data in range — drag the handles")
            }

            // --- chart ----------------------------------------------------
            Rectangle {
                id: chartArea
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: page.isPortrait ? page.height * 0.5 : page.height * 0.6
                radius: Theme.paddingLarge
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1b2733" }
                    GradientStop { position: 1.0; color: "#0a0e13" }
                }
                border.color: Theme.rgba("#ffffff", 0.06)
                border.width: 1

                Canvas {
                    id: chart
                    anchors.fill: parent
                    anchors.margins: Theme.paddingMedium
                    renderStrategy: Canvas.Immediate

                    // Screen-x of each plotted measurement, for tap hit-testing.
                    property var hits: []

                    Connections {
                        target: veroval
                        onMeasurementsChanged: chart.requestPaint()
                    }
                    Component.onCompleted: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var W = width, H = height
                        if (W <= 0 || H <= 0) return
                        var ml = 46, mr = 50, mt = 10, mb = 40
                        var pw = W - ml - mr, ph = H - mt - mb
                        var ymin = 40, ymax = 200
                        function Y(v) { return mt + ph - (v - ymin) / (ymax - ymin) * ph }

                        // soft grid + y labels (both sides, larger)
                        ctx.font = "23px sans-serif"; ctx.textBaseline = "middle"
                        for (var v = 40; v <= 200; v += 40) {
                            var opt = (v === 80 || v === 120)   // ~ optimum 120/80
                            if (opt) { ctx.strokeStyle = "rgba(90,190,120,0.40)"; ctx.lineWidth = 2 }
                            else { ctx.strokeStyle = "rgba(255,255,255,0.07)"; ctx.lineWidth = 1 }
                            ctx.beginPath(); ctx.moveTo(ml, Y(v) + 0.5); ctx.lineTo(ml + pw, Y(v) + 0.5); ctx.stroke()
                            ctx.fillStyle = opt ? "rgba(120,205,150,0.85)" : "rgba(255,255,255,0.6)"
                            ctx.textAlign = "left"; ctx.fillText("" + v, 2, Y(v))          // left
                            ctx.fillText("" + v, ml + pw + 8, Y(v))                        // right
                        }

                        var data = page.filtered()
                        if (data.length === 0) {
                            ctx.fillStyle = "rgba(255,255,255,0.55)"
                            ctx.fillText(qsTr("no data in range"), ml + 10, mt + ph / 2)
                            return
                        }
                        var tmin = data[0].epoch, tmax = data[data.length - 1].epoch
                        if (tmax === tmin) { tmin -= 1; tmax += 1 }
                        function X(t) { return ml + (tmax - t) / (tmax - tmin) * pw }  // newest left

                        // hit-test index: screen-x per measurement
                        hits = []
                        for (var hi = 0; hi < data.length; ++hi)
                            hits.push({ x: X(data[hi].epoch), epoch: data[hi].epoch })

                        // Straight segments (round joins/caps) — no overshoot on
                        // uneven time gaps, still modern with the glow + area fill.
                        function smoothPath(pts) {
                            ctx.moveTo(pts[0].x, pts[0].y)
                            for (var i = 1; i < pts.length; ++i)
                                ctx.lineTo(pts[i].x, pts[i].y)
                        }
                        function series(key, r, g, b) {
                            var pts = []
                            for (var i = 0; i < data.length; ++i)
                                pts.push({ x: X(data[i].epoch), y: Y(data[i][key]) })
                            var rgb = r + "," + g + "," + b
                            // area fill (gradient fading down) — no glow here
                            var grad = ctx.createLinearGradient(0, mt, 0, mt + ph)
                            grad.addColorStop(0, "rgba(" + rgb + ",0.28)")
                            grad.addColorStop(1, "rgba(" + rgb + ",0.02)")
                            ctx.beginPath(); smoothPath(pts)
                            ctx.lineTo(pts[pts.length - 1].x, mt + ph)
                            ctx.lineTo(pts[0].x, mt + ph); ctx.closePath()
                            ctx.fillStyle = grad; ctx.fill()
                            // cheap glow: a wide translucent underlay, then the
                            // crisp line on top (avoids the very costly shadowBlur).
                            ctx.lineJoin = "round"; ctx.lineCap = "round"
                            ctx.strokeStyle = "rgba(" + rgb + ",0.22)"; ctx.lineWidth = 8
                            ctx.beginPath(); smoothPath(pts); ctx.stroke()
                            ctx.strokeStyle = "rgb(" + rgb + ")"; ctx.lineWidth = 3
                            ctx.beginPath(); smoothPath(pts); ctx.stroke()
                            // round points with a subtle ring (bigger + tappable)
                            for (var j = 0; j < pts.length; ++j) {
                                var sel = (data[j].epoch === page.selEpoch)
                                var rad = sel ? 8 : 5
                                ctx.beginPath(); ctx.arc(pts[j].x, pts[j].y, rad, 0, 2 * Math.PI)
                                ctx.fillStyle = "rgb(" + rgb + ")"; ctx.fill()
                                ctx.beginPath(); ctx.arc(pts[j].x, pts[j].y, rad, 0, 2 * Math.PI)
                                ctx.strokeStyle = "rgba(255,255,255," + (sel ? 0.95 : 0.5) + ")"
                                ctx.lineWidth = sel ? 2 : 1; ctx.stroke()
                            }
                        }

                        // vertical marker for the selected measurement
                        if (page.selEpoch > 0) {
                            var sx = X(page.selEpoch)
                            ctx.strokeStyle = "rgba(255,255,255,0.35)"; ctx.lineWidth = 1
                            ctx.beginPath(); ctx.moveTo(sx, mt); ctx.lineTo(sx, mt + ph); ctx.stroke()
                        }

                        series("diastolic", 30, 90, 168)     // dark blue
                        series("pulse", 236, 239, 241)       // white
                        series("systolic", 79, 195, 247)     // light blue

                        // Larger, readable date labels: newest left, oldest right.
                        ctx.font = "26px sans-serif"
                        ctx.fillStyle = "rgba(255,255,255,0.85)"
                        ctx.textBaseline = "alphabetic"
                        ctx.textAlign = "left"
                        ctx.fillText("" + data[data.length - 1].timestamp.substr(0, 10), ml, H - 8)
                        ctx.textAlign = "right"
                        ctx.fillText("" + data[0].timestamp.substr(0, 10), ml + pw, H - 8)
                        ctx.textAlign = "left"
                    }
                }

                // Tap a column to select the nearest measurement. Flicks pass
                // through (the Flickable steals drags), taps select.
                MouseArea {
                    anchors.fill: chart
                    onClicked: {
                        var hs = chart.hits
                        if (!hs || hs.length === 0) return
                        var best = -1, bd = 1e9
                        for (var i = 0; i < hs.length; ++i) {
                            var d = Math.abs(hs[i].x - mouse.x)
                            if (d < bd) { bd = d; best = i }
                        }
                        page.selEpoch = (best >= 0 && bd < 44) ? hs[best].epoch : 0
                        chart.requestPaint()
                    }
                }

                // Detail box (bottom-right) for the tapped measurement.
                Rectangle {
                    visible: page.selEpoch > 0 && detailCol.m
                    anchors { right: chart.right; bottom: chart.bottom; margins: Theme.paddingSmall }
                    width: detailCol.width + 2 * Theme.paddingMedium
                    height: detailCol.height + 2 * Theme.paddingMedium
                    radius: Theme.paddingSmall
                    color: Theme.rgba("#000000", 0.7)
                    border.color: Theme.rgba("#ffffff", 0.18); border.width: 1
                    Column {
                        id: detailCol
                        property var m: page.selM()
                        anchors.centerIn: parent
                        spacing: 2
                        Label {
                            text: detailCol.m ? detailCol.m.timestamp : ""
                            font.pixelSize: Theme.fontSizeExtraSmall; color: "white"
                        }
                        Label {
                            text: detailCol.m ? (detailCol.m.systolic + "/" + detailCol.m.diastolic + " mmHg") : ""
                            font.pixelSize: Theme.fontSizeLarge; color: page.colSys
                        }
                        Label {
                            text: detailCol.m ? ("♥ " + detailCol.m.pulse + (detailCol.m.arrhythmia ? "   ⚠ Arrhythmie" : "")) : ""
                            font.pixelSize: Theme.fontSizeSmall; color: Theme.highlightColor
                        }
                    }
                }
            }

            // --- legend + averages ----------------------------------------
            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingLarge
                Label { text: qsTr("● Sys"); color: page.colSys; font.pixelSize: Theme.fontSizeExtraSmall }
                Label { text: qsTr("● Dia"); color: page.colDia; font.pixelSize: Theme.fontSizeExtraSmall }
                Label { text: qsTr("● Pulse"); color: page.colPulse; font.pixelSize: Theme.fontSizeExtraSmall }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                property var d: page.filtered()
                text: d.length
                      ? qsTr("Average: %1/%2 mmHg · ♥ %3 · n=%4")
                          .arg(Math.round(page.avg(d, "systolic")))
                          .arg(Math.round(page.avg(d, "diastolic")))
                          .arg(Math.round(page.avg(d, "pulse")))
                          .arg(d.length)
                      : qsTr("No measurements in this range")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }
        }
        VerticalScrollDecorator {}
    }
}
