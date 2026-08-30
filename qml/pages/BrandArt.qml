import QtQuick

/*
 * The MIZAN brand mark: a dot grid, two soft glows, a shopping bag and a coin.
 *
 * Ported from pos's BrandArt QPainter composition. Canvas rather than an image
 * so it scales with whatever panel it is dropped into, at any DPI, with no
 * asset to keep in sync. Everything is drawn in white at low alpha, so it works
 * on any dark surface without being recoloured.
 */
Canvas {
    antialiasing: true
    renderTarget: Canvas.Image

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (width <= 0 || height <= 0)
            return

        var w = width
        var h = height
        var cx = w / 2
        var cy = h / 2

        // Dot grid. The origin is offset by half the remainder so the pattern
        // stays centred and does not clip unevenly as the panel resizes.
        var step = 34
        var dot = 2.0
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.10)
        for (var x = (w % step) / 2; x < w; x += step) {
            for (var y = (h % step) / 2; y < h; y += step) {
                ctx.beginPath()
                ctx.arc(x, y, dot, 0, Math.PI * 2)
                ctx.fill()
            }
        }

        // Two concentric glows, wide and tight, so the mark sits in light rather
        // than on a flat field.
        var glowY = cy - h * 0.04
        var glows = [[Math.min(w, h) * 0.46, 0.10],
                     [Math.min(w, h) * 0.28, 0.14]]
        for (var i = 0; i < glows.length; i++) {
            var r = glows[i][0]
            var g = ctx.createRadialGradient(cx, glowY, 0, cx, glowY, r)
            g.addColorStop(0, Qt.rgba(1, 1, 1, glows[i][1]))
            g.addColorStop(1, Qt.rgba(1, 1, 1, 0))
            ctx.fillStyle = g
            ctx.beginPath()
            ctx.arc(cx, glowY, r, 0, Math.PI * 2)
            ctx.fill()
        }

        // Bag and coin, in units of `s` so they track the panel size.
        var s = Math.min(w, h) / 130
        ctx.lineWidth = Math.max(2, 2.6 * s)
        ctx.lineJoin = "round"
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.82)

        ctx.beginPath()
        ctx.moveTo(cx - 26 * s, cy - 2 * s)
        ctx.lineTo(cx - 22 * s, cy + 30 * s)
        ctx.lineTo(cx + 22 * s, cy + 30 * s)
        ctx.lineTo(cx + 26 * s, cy - 2 * s)
        ctx.closePath()
        ctx.stroke()

        // Handle: the top half of a circle. Canvas y grows downward, so sweeping
        // from PI to 0 passes through straight up, not straight down.
        ctx.beginPath()
        ctx.arc(cx, cy - 3 * s, 11 * s, Math.PI, 0)
        ctx.stroke()

        // Bag mouth, dimmer than the outline so it reads as an inner edge.
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.34)
        ctx.beginPath()
        ctx.moveTo(cx - 26 * s, cy - 2 * s)
        ctx.lineTo(cx + 26 * s, cy - 2 * s)
        ctx.stroke()

        var coinX = cx + 30 * s
        var coinY = cy + 24 * s
        var coinR = 9 * s
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.18)
        ctx.beginPath()
        ctx.arc(coinX, coinY, coinR, 0, Math.PI * 2)
        ctx.fill()
        ctx.lineWidth = Math.max(1.5, 1.8 * s)
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.55)
        ctx.stroke()
    }
}
