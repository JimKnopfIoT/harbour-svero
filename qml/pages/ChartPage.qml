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
    // The chart plots one person at a time; the P1/P2 toggle in the list is
    // what assigns readings, and the selection here is remembered.
    // Reading personRevision is what makes the bindings below re-run when a
    // reading is moved between P1 and P2: that leaves `measurements` itself
    // untouched, so it alone would never notify.
    function ofPerson() {
        var rev = veroval.personRevision
        var ms = veroval.measurements, out = []
        for (var i = 0; i < ms.length; ++i) {
            var p = ms[i].person === 2 ? 2 : 1
            if (p === veroval.chartPerson) out.push(ms[i])
        }
        return out
    }

    // Counted here rather than through a C++ method: a binding only re-runs
    // when a *property* it read changes, and veroval.measurements is one —
    // an invokable's result would go stale the moment an assignment changes.
    function countOf(p) {
        var rev = veroval.personRevision
        var ms = veroval.measurements, n = 0
        for (var i = 0; i < ms.length; ++i)
            if ((ms[i].person === 2 ? 2 : 1) === p) ++n
        return n
    }

    function dataRange() {
        var ms = page.ofPerson(), minE = -1, maxE = 0
        for (var i = 0; i < ms.length; ++i) {
            var e = ms[i].epoch
            if (e <= 0) continue
            if (minE < 0 || e < minE) minE = e
            if (e > maxE) maxE = e
        }
        return [minE, maxE]
    }
    // --- visible time window ------------------------------------------------
    // Fractions of the full span of the selected person's data, on the same
    // mirrored axis the chart draws: 0 = newest, 1 = oldest. Pinching the chart
    // changes how wide this window is, dragging moves it.
    property real winLeft: 0.0
    property real winRight: 1.0
    // Closest zoom, as a duration rather than a fraction of the span: the
    // archive covers years, so a fixed fraction bottoms out at a month or more
    // and gets worse the longer the archive grows.
    readonly property int minWinDays: 7
    function minWinFraction() {
        var mm = dataRange()
        var days = (mm[1] - mm[0]) / 86400        // epochs are seconds
        if (!(days > 0)) return 1
        return Math.min(1, page.minWinDays / days)
    }
    // Movement that separates a drag from a tap. Not Theme.startDragDistance:
    // this Silica does not have that property, and reading it would silently
    // yield undefined, making every tap count as a drag.
    // Small, so the horizontal drag is claimed before the page stack decides
    // the same swipe means "back to the list".
    readonly property real dragThreshold: Theme.paddingMedium

    function setWindow(l, r) {
        var span = Math.min(1, Math.max(page.minWinFraction(), r - l))
        if (l < 0) l = 0
        if (l + span > 1) l = 1 - span
        page.winLeft = l
        page.winRight = l + span
        repaintTimer.restart()
    }
    function resetWindow() {
        page.winLeft = 0
        page.winRight = 1
        chart.requestPaint()
    }

    // Repainting the whole canvas on every touch move is too much; one frame
    // behind is not noticeable and keeps the drag smooth.
    Timer { id: repaintTimer; interval: 30; onTriggered: chart.requestPaint() }

    function filtered() {
        var ms = page.ofPerson()
        var mm = dataRange(), minE = mm[0], maxE = mm[1]
        if (minE < 0 || maxE === 0) return []
        var span = (maxE === minE) ? 1 : (maxE - minE)
        var newer = maxE - page.winLeft * span
        var older = maxE - page.winRight * span
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
    // Selected data point (by epoch), shown in the detail box.
    property double selEpoch: 0
    function selM() {
        if (selEpoch <= 0) return null
        var ms = page.ofPerson()
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

            // No PageHeader: the page is reached by swiping from the list, so
            // the title earns nothing and costs a lot of height in landscape.
            // Just enough top padding to clear the pulley indicator.
            Item { width: 1; height: Theme.paddingLarge }


            // --- chart ----------------------------------------------------
            Rectangle {
                id: chartArea
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                // With the range bar and the summary line gone, the plot takes
                // what is left over the legend row.
                height: page.isPortrait ? page.height * 0.6 : page.height * 0.8
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
                        onChartPersonChanged: chart.requestPaint()
                        onPersonRevisionChanged: chart.requestPaint()
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

                        var data = page.filtered()

                        // 40-200 covers nearly everything, but a reading outside
                        // it would be drawn over the labels or clipped away, so
                        // the scale stretches to whatever is actually there.
                        // Pulse shares the axis and can sit below 40.
                        var ymin = 40, ymax = 200
                        for (var di = 0; di < data.length; ++di) {
                            var hi = Math.max(data[di].systolic, data[di].pulse)
                            var lo = Math.min(data[di].diastolic, data[di].pulse)
                            if (hi > ymax - 8) ymax = Math.ceil((hi + 8) / 20) * 20
                            if (lo < ymin + 8) ymin = Math.max(0, Math.floor((lo - 8) / 20) * 20)
                        }
                        function Y(v) { return mt + ph - (v - ymin) / (ymax - ymin) * ph }

                        // soft grid + y labels (both sides, larger)
                        ctx.font = "23px sans-serif"; ctx.textBaseline = "middle"
                        for (var v = Math.ceil(ymin / 40) * 40; v <= ymax; v += 40) {
                            var opt = (v === 80 || v === 120)   // ~ optimum 120/80
                            var g2 = (v === 160)                // grade 2 starts here
                            if (opt) { ctx.strokeStyle = "rgba(90,190,120,0.40)"; ctx.lineWidth = 2 }
                            else if (g2) { ctx.strokeStyle = "rgba(229,57,53,0.38)"; ctx.lineWidth = 2 }
                            else { ctx.strokeStyle = "rgba(255,255,255,0.07)"; ctx.lineWidth = 1 }
                            ctx.beginPath(); ctx.moveTo(ml, Y(v) + 0.5); ctx.lineTo(ml + pw, Y(v) + 0.5); ctx.stroke()
                            ctx.fillStyle = opt ? "rgba(120,205,150,0.85)"
                                               : g2 ? "rgba(239,120,116,0.85)"
                                                    : "rgba(255,255,255,0.6)"
                            ctx.textAlign = "left"; ctx.fillText("" + v, 2, Y(v))          // left
                            ctx.fillText("" + v, ml + pw + 8, Y(v))                        // right
                        }

                        // Grade 1 (140) and grade 3 (180), in the same colours
                        // the list uses to flag a reading. Fine dots, unlabelled:
                        // they are a reference for the eye, not a scale — the
                        // numbers stay on the 40-step grid. A touch more alpha
                        // than the solid 160 line, because dots read fainter.
                        // Stepped by hand: this Canvas has no ctx.setLineDash.
                        ctx.lineWidth = 2
                        ctx.lineCap = "round"          // 1px segment -> round dot
                        var marks = [{ v: 140, c: "rgba(251,140,0,0.42)" },   // orange
                                     { v: 180, c: "rgba(229,57,53,0.42)" }]   // red
                        for (var mi = 0; mi < marks.length; ++mi) {
                            var my = Y(marks[mi].v) + 0.5
                            ctx.strokeStyle = marks[mi].c
                            ctx.beginPath()
                            for (var mx = ml; mx < ml + pw; mx += 14) {
                                ctx.moveTo(mx, my)
                                ctx.lineTo(Math.min(mx + 1, ml + pw), my)
                            }
                            ctx.stroke()
                        }
                        ctx.lineCap = "butt"

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

                // Two fingers stretch the chart in time, one finger drags the
                // window along it, a tap still picks a reading. Vertical drags
                // are left alone so the page keeps scrolling and the pulley
                // menu keeps working.
                PinchArea {
                    anchors.fill: chart
                    property real startLeft: 0
                    property real startSpan: 1

                    onPinchStarted: {
                        startLeft = page.winLeft
                        startSpan = page.winRight - page.winLeft
                    }
                    onPinchUpdated: {
                        // Whatever sits under the middle of the two fingers
                        // stays put; only the width of the window changes.
                        var newSpan = startSpan / Math.max(0.05, pinch.scale)
                        var at = Math.max(0, Math.min(1, pinch.center.x / width))
                        var anchorF = startLeft + at * startSpan
                        page.setWindow(anchorF - at * newSpan,
                                       anchorF - at * newSpan + newSpan)
                    }
                    onPinchFinished: chart.requestPaint()

                    MouseArea {
                        anchors.fill: parent
                        property real pressX: 0
                        property real pressY: 0
                        property real startLeft: 0
                        property real startSpan: 1
                        property bool dragging: false

                        onPressed: {
                            pressX = mouse.x
                            pressY = mouse.y
                            startLeft = page.winLeft
                            startSpan = page.winRight - page.winLeft
                            dragging = false
                        }
                        onPositionChanged: {
                            var dx = mouse.x - pressX
                            var dy = mouse.y - pressY
                            if (!dragging) {
                                // Claim the gesture only once it is clearly
                                // horizontal. Until then the page keeps its own
                                // vertical scroll and the PinchArea can still
                                // take over on a second finger.
                                if (Math.abs(dx) < page.dragThreshold
                                        || Math.abs(dx) <= Math.abs(dy))
                                    return
                                dragging = true
                                // Without this the page stack reads the same
                                // swipe as "go back to the list".
                                preventStealing = true
                            }
                            // Mirrored axis — newest is on the left — so dragging
                            // to the right brings newer readings into view.
                            var df = -(dx / width) * startSpan
                            page.setWindow(startLeft + df, startLeft + df + startSpan)
                        }
                        onReleased: {
                            preventStealing = false
                            if (dragging) {
                                dragging = false
                                chart.requestPaint()
                                return
                            }
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
                        onCanceled: { dragging = false; preventStealing = false }
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

            // --- person selector + legend + averages -----------------------
            // One Flow, so everything that is not the plot shares a single line
            // wherever it fits (landscape) and wraps when it does not. Keeping
            // it all down here leaves the chart the full width.
            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingLarge

                // Person selector — mirrors the P1/P2 toggle in the list.
                Row {
                    id: personSelector
                    spacing: Theme.paddingMedium
                    Repeater {
                        model: [1, 2]
                        delegate: Rectangle {
                            width: Theme.itemSizeSmall * 1.3
                            height: Theme.itemSizeExtraSmall * 0.8
                            radius: height / 2
                            property bool active: veroval.chartPerson === modelData
                            color: active ? Theme.rgba(Theme.highlightColor, 0.35) : "transparent"
                            border.color: active ? Theme.highlightColor
                                                 : Theme.rgba(Theme.secondaryColor, 0.5)
                            border.width: 1
                            Label {
                                anchors.centerIn: parent
                                text: qsTr("P%1 (%2)").arg(modelData).arg(page.countOf(modelData))
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: parent.active ? Theme.primaryColor : Theme.secondaryColor
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    // The other person's readings span a
                                    // different period, so the zoom from this
                                    // one means nothing there.
                                    veroval.chartPerson = modelData
                                    page.selEpoch = 0
                                    page.resetWindow()
                                }
                            }
                        }
                    }
                }

                // Both of these line up with the middle of the P1/P2 pills
                // rather than their top edge.
                Row {
                    height: personSelector.height
                    spacing: Theme.paddingLarge
                    Label { anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("● Sys"); color: page.colSys; font.pixelSize: Theme.fontSizeExtraSmall }
                    Label { anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("● Dia"); color: page.colDia; font.pixelSize: Theme.fontSizeExtraSmall }
                    Label { anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("● Pulse"); color: page.colPulse; font.pixelSize: Theme.fontSizeExtraSmall }
                }
                Label {
                    height: personSelector.height
                    verticalAlignment: Text.AlignVCenter
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
        }
        VerticalScrollDecorator {}
    }
}
