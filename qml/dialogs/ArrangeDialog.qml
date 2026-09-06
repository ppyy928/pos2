import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Arrange — the till's own tiles, dragged into the order the shop wants them.
 *
 *   [★ Favourites] [▌Drinks] [▌Bakery] …
 *   ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
 *   │▌Coca   │ │▌Fanta  │ │▌Water  │ │ Pain   │   drag one onto another
 *   │ 120,00 │ │ 120,00 │ │  60,00 │ │  35,00 │   and they swap places
 *   └────────┘ └────────┘ └────────┘ └────────┘
 *
 * WHY TILES AND NOT A LIST
 *
 * This screen exists so a cashier's hand can go to the same place every time, and
 * the only honest way to arrange something for the eye is to show it as the eye
 * will meet it. A numbered list with up/down buttons describes the order; a grid of
 * the actual tiles *is* the order — same component, same size, same colours as the
 * till, so what is arranged here is what appears there.
 *
 * HOW REORDERING WORKS — TWO WAYS, ONE RULE
 *
 * The rule is always the same: two tiles change places and nothing else moves.
 *
 *   TAP, THEN TAP.  Tap a tile and it lifts and takes a ring — that is the one you
 *   picked. Tap a second tile and the two exchange. Tap the picked one again to let
 *   it go. This is the primary path, because it is the only one that works for a
 *   tile you have to scroll to find, needs no drag physics, and states plainly
 *   which tile is in hand.
 *
 *   DRAG.  Press and move, and the tile follows the finger while the tile under the
 *   POINTER takes an outline. Release to exchange with it. Faster for neighbours.
 *
 * Either way, both tiles keep a marker for a beat afterwards, so the answer to
 * "what did I just do" is on screen rather than in memory.
 *
 * WHAT THE PREVIOUS VERSION GOT WRONG, AND WHY THAT MATTERED
 *
 * It was drag-only, and the drag lost more often than it won:
 *
 *   THE GRID STOLE THE GESTURE.  A GridView is a Flickable, and it claims the
 *   pointer at the platform's drag distance (10px on Windows). The DragHandler asked
 *   for it at 12, and with no `grabPermissions` it could neither pre-empt the flick
 *   nor keep the grab afterwards. Sideways drags — same row, short — usually landed;
 *   anything with vertical travel scrolled the grid instead. That is precisely
 *   "it works with some and not with others".
 *
 *   THE TARGET WAS THE TILE'S CENTRE, NOT THE POINTER.  `Drag.hotSpot` was pinned
 *   to the middle of a 429px-wide tile, so grabbing near an edge aimed the drag up
 *   to a full column away from where the finger was.
 *
 *   THE LIFT WAS ON THE WRONG ITEM.  `z` was set on a child of the delegate, and z
 *   only orders siblings — so the dragged tile passed UNDER every tile created after
 *   it, and over every tile created before. Dragging left looked right and dragging
 *   right looked broken.
 *
 *   THERE WAS NOTHING BELOW THE FOLD.  Only twelve tiles fit; delegates outside the
 *   viewport are destroyed, and with them the drop areas. No auto-scroll, and the
 *   drag owned the pointer, so the thirteenth tile could not be reached at all.
 *
 *   AND NOTHING WAS EVER HIGHLIGHTED.  The tile face is `enabled: false`, which
 *   kills PosTile's own press states, and `dragFrom` was never bound to a single
 *   visual property. There was no way to see what you had hold of.
 *
 * So: no `Drag`, no `DropArea`. The target is computed from the pointer with
 * `GridView.indexAt`, the handler takes the grab and keeps it, the grid stops
 * flicking while a drag is live, the edges auto-scroll, and the lift is on the
 * delegate.
 *
 * Favourites are the same idea one level up: the first tab on the till, filled by
 * hand, for the twenty things that sell all day. The star both shows and sets.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null

    /*
     * AS WIDE AS FOUR TILES, AND NOT A PIXEL WIDER.
     *
     * This was 1420, and the tiles inside it were islands: four columns is a
     * deliberate cap (see `columns` below), a tile is capped at `tileMax`, and
     * 1420px divided four ways gives each cell 330px to hold a 192px card — so
     * every gap between two cards came out at 138px while the gap between two rows
     * stayed at 12. A wall of the shop's products with more air than product in it,
     * which is the opposite of what the operator is here to read.
     *
     * The room was the fault, not the gaps: the surplus had nowhere to go but into
     * the cells. So the dialog now asks for exactly the width its own wall needs —
     * four cells of a tile plus one gap, the grid's inset, and the dialog's
     * padding — and the leftover 138px per gap is simply not requested. Written as
     * the arithmetic rather than as the number it comes to, because every term in it
     * is a token that something else also reads.
     */
    preferredWidth: Tokens.size.tileColumns
                    * (Tokens.size.tileMax + Tokens.spacing.sm)
                    + 2 * Tokens.spacing.sm
                    + leftPadding + rightPadding
    preferredHeight: 900

    title: Strings.t("products.arrange.action", "Arrange tiles")

    /* "favorites" or a category id — the same tab vocabulary the till uses. */
    property var tab: "favorites"
    property var rows: []
    property var categories: []

    Component.onCompleted: {
        categories = ctrl ? ctrl.categories() : []
        reload()
    }

    readonly property var tabs: {
        var out = [{
            key: "favorites",
            label: Strings.t("pos.tab.favorites", "Favourites"),
            glyph: "ic_fluent_star_20_regular"
        }]
        for (var i = 0; i < categories.length; i++)
            out.push({ key: categories[i].id,
                       label: categories[i].name,
                       accent: categories[i].color !== "" ? categories[i].color
                                                          : "transparent" })
        return out
    }

    readonly property bool onFavorites: tab === "favorites"

    /* The favourite star's box, and the room every tile keeps clear for it. One
       number, because the two have to agree: a star wider than the reservation lands
       on the product name. */
    readonly property int starSize: 32

    function reload() {
        if (!ctrl) {
            rows = []
            return
        }
        rows = onFavorites ? ctrl.favorites() : ctrl.productsInCategory(tab)
    }

    function pick(key) {
        tab = key
        /* A pick in hand belongs to the tab it was picked on. */
        pickedId = -1
        flashIds = []
        reload()
    }

    // =====================================================================
    // WHAT IS IN HAND
    // =====================================================================
    /*
     * All four of these are PRODUCT IDS or derived from them, never bare indices.
     *
     * An index is only meaningful until the order changes, and the order changes on
     * every swap — and again a moment later, when the controller's `changed` signal
     * brings the list back from the database. Holding an index across either of those
     * points at whatever moved into that slot. An id is the tile.
     */
    property int pickedId: -1

    /* The pair that just exchanged, marked for a beat so the operator can see what
       moved where instead of having to remember. */
    property var flashIds: []

    /* Live drag state. These two ARE indices, because they only exist between press
       and release, during which nothing reorders anything. */
    property int dragIndex: -1
    property int overIndex: -1

    /* Where the finger is, in scene coordinates. Written by the handler on every
       move and read by the auto-scroll timer, which has no pointer of its own. */
    property point dragPoint: Qt.point(-1, -1)

    readonly property int pickedIndex: dialog.indexOfId(dialog.pickedId)

    function indexOfId(id) {
        if (id < 0)
            return -1
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === id)
                return i
        }
        return -1
    }

    function isFlashing(id) {
        for (var i = 0; i < dialog.flashIds.length; i++) {
            if (dialog.flashIds[i] === id)
                return true
        }
        return false
    }

    /*
     * Tap: pick, then swap.
     *
     * Three outcomes and no modes: nothing in hand -> this becomes the pick; this
     * one is already in hand -> put it down; something else is in hand -> exchange.
     */
    function tap(index) {
        if (index < 0 || index >= rows.length)
            return
        var id = rows[index].id
        if (dialog.pickedId === id) {
            dialog.pickedId = -1
            return
        }
        var from = dialog.pickedIndex
        if (from < 0) {
            dialog.pickedId = id
            dialog.flashIds = []
            return
        }
        dialog.exchange(from, index)
    }

    /*
     * Two tiles change places. Nothing else moves.
     *
     * This is pos's rule, quoted from product_cards.py: "Swap the two cards
     * directly. This is much easier to control than insert-before/after and
     * exactly matches the visual target highlight." An earlier version here shifted
     * the whole list as the finger crossed each cell, which is why a long drag
     * fought back — the layout moved under the cursor, so the tile the operator
     * was aiming at had already gone somewhere else.
     */
    function exchange(from, to) {
        if (from === to || from < 0 || to < 0 || from >= rows.length || to >= rows.length)
            return

        var next = rows.slice()
        var moved = next[from]
        next[from] = next[to]
        next[to] = moved

        /*
         * Where the grid was looking, saved across the model swap.
         *
         * `rows = next` reassigns GridView.model, which rebuilds every delegate and
         * lands the view back at the top. So a swap made on the ninth row used to
         * answer by throwing the operator to the first — and after a drag that had
         * auto-scrolled to get there, the pair of them reads as the list scrolling
         * away on its own and refusing to stop.
         *
         * Two tiles trading places cannot change the content height, so the old
         * offset is still exactly the right one.
         */
        var keepY = grid.contentY

        /* Captured before the assignment below, while these indices still mean
           what they meant when the operator chose them. */
        dialog.flashIds = [next[from].id, next[to].id]
        dialog.pickedId = -1
        rows = next
        dialog.holdScroll(keepY)
        dialog.pendingCommit = true
        flash.restart()

        /*
         * Qt.callLater, and this is load-bearing.
         *
         * `rows = next` has just replaced the model, which destroys every delegate —
         * including the one whose signal handler this call is standing inside when
         * the swap came from a drag or a tap. commit() then writes to the database
         * and the controller emits `changed` synchronously, which would rebuild them
         * a second time. Deferring the write to the next event loop pass lets this
         * stack unwind first.
         *
         * `pendingCommit` exists because deferring anything opens the question of
         * what happens if the dialog closes first. onClosed flushes it, and the flag
         * makes both paths idempotent — whichever runs first does the write, and the
         * other one finds nothing to do.
         */
        Qt.callLater(dialog.commit)
    }

    Timer {
        id: flash
        interval: 1400
        onTriggered: dialog.flashIds = []
    }

    /* Written once per exchange: the intermediate orders a drag passes through are
       not decisions. */
    property bool pendingCommit: false

    function commit() {
        if (!ctrl || !dialog.pendingCommit)
            return
        dialog.pendingCommit = false

        var order = []
        for (var i = 0; i < rows.length; i++)
            order.push(rows[i].id)

        dialog.committing = true
        if (onFavorites)
            ctrl.reorderFavorites(order)
        else
            ctrl.reorderProducts(tab, order)
        dialog.committing = false
    }

    /* The last swap, if it is still queued. A human cannot close a dialog inside the
       one event loop pass a callLater waits for, but "cannot" is not a guarantee to
       stake an order on. */
    onClosed: dialog.commit()

    /* True for exactly as long as one of our own writes is in flight. `changed` is
       emitted synchronously inside the reorder slot, so this is enough to tell our
       own echo from a real change made somewhere else. */
    property bool committing: false

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        /* Reload for the things that are not this swap: a favourite toggled, a
           category renamed elsewhere. Our own reorder comes back identical, and
           rebuilding forty delegates to learn that is a frame nobody needs. */
        function onChanged() {
            if (!dialog.committing)
                dialog.reload()
        }
        function onRejected(message) { error.text = message }
    }

    // =====================================================================
    // POINTER -> TILE
    // =====================================================================
    /*
     * Which tile is under a point, computed rather than hit-tested.
     *
     * `GridView.indexAt` only answers for items that currently exist, and a GridView
     * destroys the delegates outside its viewport — so during a drag towards the
     * bottom of a long category it would return -1 for exactly the tiles the
     * operator is reaching for. The cells are a regular grid of known size, so the
     * index is arithmetic, and arithmetic does not care whether anything has been
     * instantiated.
     *
     * The column is mirrored in Arabic because GridView lays its cells out
     * right-to-left there, and `p.x` is measured from the left edge either way.
     */
    function indexUnder(scenePos) {
        var p = grid.mapFromItem(null, scenePos.x, scenePos.y)
        if (p.x < 0 || p.y < 0 || p.x > grid.width || p.y > grid.height)
            return -1
        if (grid.cellWidth <= 0 || grid.cellHeight <= 0)
            return -1

        var cols = Math.max(1, Math.floor(grid.width / grid.cellWidth))
        var col = Math.floor(p.x / grid.cellWidth)
        if (col < 0 || col >= cols)
            return -1
        if (grid.effectiveLayoutDirection === Qt.RightToLeft)
            col = cols - 1 - col

        var row = Math.floor((p.y + grid.contentY) / grid.cellHeight)
        var index = row * cols + col
        return (row >= 0 && index >= 0 && index < rows.length) ? index : -1
    }

    /*
     * Auto-scroll while dragging near an edge.
     *
     * Without it the reachable targets are the twelve tiles that happen to be on
     * screen: the drag owns the pointer, so the grid cannot be flicked, and a
     * category with forty products cannot be rearranged past its fourth row. pos had
     * this (product_cards.py:88-104 — a 24ms timer, 18px steps, a 100px margin) and
     * it is the difference between a feature and a demo.
     *
     * IT HAS TO BE AIMABLE, WHICH MEANS PROPORTIONAL
     *
     * pos's version — and the first one here, which copied it — moved a fixed number
     * of pixels per tick the moment the pointer crossed into the margin. One pixel
     * inside the zone scrolled at the same 580px/s as the very edge, so in a 570px
     * viewport the whole list went past in two seconds with no slow setting to be
     * found. There was no way to nudge the view down one row; entering the zone at
     * all meant riding it to the end. That is the "it keeps scrolling and will not
     * stop" this replaces.
     *
     * So the speed ramps: zero at the inner edge of the margin, `scrollSpeed` at the
     * viewport edge, and squared in between — which spends most of the margin's
     * width on the slow half, where the aiming happens. And it is measured in pixels
     * per second against the real clock rather than pixels per tick, so a busy frame
     * cannot change how far the list travels.
     */
    property int scrollMargin: Math.round(Math.min(72, grid.height * 0.18))

    /* Pixels per second, and only at the extreme edge. About one viewport per
       second there; a third of that through the first half of the margin. */
    property int scrollSpeed: 640

    /* Timestamp of the last step, or 0 for "not scrolling". Also the flag that
       restarts the clock cleanly, so re-entering the margin does not bill the
       operator for the time they spent outside it. */
    property real scrollClock: 0

    function stepScroll() {
        if (dialog.dragIndex < 0) {
            dialog.scrollClock = 0
            return
        }
        var p = grid.mapFromItem(null, dialog.dragPoint.x, dialog.dragPoint.y)
        var margin = Math.max(1, dialog.scrollMargin)

        /* -1 at the top edge, +1 at the bottom edge, 0 anywhere in the middle. */
        var depth = 0
        if (p.y < margin)
            depth = (p.y - margin) / margin
        else if (p.y > grid.height - margin)
            depth = (p.y - (grid.height - margin)) / margin
        if (depth === 0) {
            dialog.scrollClock = 0
            return
        }
        /* Dragged past the edge entirely is still just "as fast as it goes". */
        depth = Math.max(-1, Math.min(1, depth))

        var now = Date.now()
        /* Capped: a stalled frame must not teleport the list. */
        var elapsed = dialog.scrollClock > 0
                      ? Math.min(64, now - dialog.scrollClock) : 16
        dialog.scrollClock = now

        var step = depth * Math.abs(depth) * dialog.scrollSpeed * elapsed / 1000
        var limit = Math.max(0, grid.contentHeight - grid.height)
        var next = Math.max(0, Math.min(limit, grid.contentY + step))
        if (Math.abs(next - grid.contentY) < 0.01)
            return

        grid.contentY = next
        /* The content moved under a finger that did not: whatever is beneath it now
           is a different tile. */
        dialog.overIndex = dialog.indexUnder(dialog.dragPoint)
    }

    /* Put the view back where it was looking after a model swap, once now and once
       after the view has relaid out — GridView moves contentY itself while
       rebuilding, and that happens after this stack unwinds. */
    function holdScroll(y) {
        grid.contentY = dialog.clampScroll(y)
        Qt.callLater(function () {
            grid.contentY = dialog.clampScroll(y)
        })
    }

    function clampScroll(y) {
        return Math.max(0, Math.min(Math.max(0, grid.contentHeight - grid.height), y))
    }

    Timer {
        running: dialog.dragIndex >= 0
        interval: 16
        repeat: true
        onTriggered: dialog.stepScroll()
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        CategoryStrip {
            Layout.fillWidth: true
            model: dialog.tabs
            currentKey: dialog.tab
            onActivated: (key) => dialog.pick(key)
        }

        Text {
            Layout.fillWidth: true
            text: Strings.t("products.arrange.hint2",
                            "Tap a tile, then tap another to swap them — or drag one onto another. The till shows them exactly like this.")
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Fluent.textTertiary
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Fluent.subtleSecondary
            radius: Tokens.radius.lg
            border.width: 1
            border.color: Fluent.dividerBorder

            GridView {
                id: grid
                anchors.fill: parent
                anchors.margins: Tokens.spacing.sm
                clip: true
                model: dialog.rows

                readonly property int gap: Tokens.spacing.sm
                /* The same count as the till's own wall, and the same cap on a tile's
                   width: this screen exists to show the arrangement as the cashier
                   will meet it, so a row here has to hold what a row there holds.
                   It was pinned to 3 and then briefly flowed — which put seven across
                   this dialog against the till's four, and an arrangement shown seven
                   to a row is not the arrangement being arranged. */
                readonly property int columns:
                    Math.max(1, Math.min(Tokens.size.tileColumns,
                                         Math.floor((width + gap)
                                                    / (Tokens.size.tileMin + gap))))

                cellWidth: Math.max(1, Math.floor(width / columns))
                cellHeight: Tokens.size.tile + gap

                /* A Flickable and a drag cannot both own the pointer. The handler
                   below takes the grab; this makes sure the grid does not try to
                   take it back halfway through and turn a swap into a scroll. */
                interactive: dialog.dragIndex < 0

                QC.ScrollBar.vertical: FluentScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index

                    width: grid.cellWidth
                    height: grid.cellHeight

                    readonly property bool dragging: dialog.dragIndex === cell.index
                    readonly property bool picked: dialog.pickedIndex === cell.index
                    readonly property bool over: dialog.overIndex === cell.index
                                                 && !cell.dragging
                    readonly property bool flashing: dialog.isFlashing(cell.modelData.id)

                    /*
                     * The lift, on the DELEGATE.
                     *
                     * z orders siblings, and the delegate's siblings are the other
                     * cells — which is the comparison that matters. Setting it on the
                     * tile inside the cell (which is what this used to do) only
                     * ordered the tile against its own cell's children, so a dragged
                     * tile still passed under every cell created after it.
                     */
                    z: cell.dragging ? 3 : (cell.picked ? 2 : 0)

                    Item {
                        id: floater
                        /* Capped and centred in the cell, like the till's tiles. The
                           cap does nothing at this dialog's own width — see
                           `preferredWidth`, which is chosen so a cell is a tile plus
                           one gap — and holds the cards at the till's size on a
                           window too narrow to grant the request. */
                        width: Math.min(grid.cellWidth - grid.gap,
                                        Tokens.size.tileMax)
                        height: grid.cellHeight - grid.gap
                        x: Math.round((grid.cellWidth - width) / 2)
                        y: Math.round(grid.gap / 2)

                        scale: cell.dragging ? 1.05 : (cell.picked ? 1.02 : 1)
                        opacity: cell.dragging ? 0.94 : 1

                        Behavior on scale {
                            NumberAnimation { duration: Fluent.anim.appearance }
                        }

                        PosTile {
                            anchors.fill: parent
                            name: cell.modelData.name
                            /* No price here — see Catalogue._card. This screen is
                               about order, and the figure it used to show was
                               always 0.00. */
                            priceText: ""
                            stock: 1            // arranging is not selling
                            accent: "transparent"
                            /* Keep the top trailing corner clear: the star below is
                               drawn over this tile, and these tiles are now as narrow
                               as the till's. */
                            nameTrailingRoom: dialog.starSize + Tokens.spacing.xs
                            /* Not a button here: a tap must not add anything to a
                               cart, and this screen owns the tap itself. */
                            enabled: false
                            opacity: 1
                        }

                        /*
                         * THE THREE STATES, AS RINGS AND NOTHING ELSE
                         *
                         *   in hand   emerald ring, and the position pill goes
                         *             emerald too
                         *   target    amber ring — "this is the one you would
                         *             displace"
                         *   swapped   teal ring and a teal pill, for a beat, on
                         *             both tiles that traded
                         *
                         * OUTLINES, NOT FILLS. The version before this painted a
                         * 55%-opaque wash over the drop target, and a first attempt
                         * at fixing it used 40% — both of them lighten the product
                         * name to the point of illegibility at exactly the moment
                         * the operator needs to read it and decide. A ring changes
                         * nothing inside the tile.
                         *
                         * THREE COLOURS, NOT ONE. A single accent would make "in
                         * hand" and "about to be displaced" identical, and those are
                         * the two things a swap is made of.
                         */
                        readonly property color ringColor: {
                            if (cell.dragging || cell.picked)
                                return Tokens.brand
                            if (cell.over)
                                return Tokens.warning
                            return Tokens.info
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.radius.md
                            color: "transparent"
                            border.width: {
                                if (cell.dragging || cell.picked)
                                    return 3
                                if (cell.over)
                                    return 4
                                return cell.flashing ? 3 : 0
                            }
                            border.color: floater.ringColor
                            visible: border.width > 0
                        }

                        /*
                         * Tap picks, and the second tap swaps. Declared before the
                         * DragHandler so a plain tap is a tap; the two do not
                         * compete, because a tap that travels becomes a drag and a
                         * drag that never moves is not reported as a tap.
                         */
                        TapHandler {
                            onTapped: dialog.tap(cell.index)
                        }

                        DragHandler {
                            id: handler

                            /*
                             * The whole grab, and nothing but the grab.
                             *
                             * CanTakeOverFromAnything lets this pre-empt the
                             * GridView's flick — which otherwise claims the pointer
                             * two pixels earlier and turns every vertical drag into
                             * a scroll. Leaving the Approves* bits out means nothing
                             * can take it back once it is held, which is the other
                             * half of the same bug.
                             */
                            grabPermissions: PointerHandler.CanTakeOverFromAnything

                            /* Where the finger is, in scene coordinates — the only
                               frame of reference that survives the grid scrolling
                               underneath it. */
                            readonly property point scenePoint: handler.centroid.scenePosition

                            onScenePointChanged: {
                                if (!handler.active)
                                    return
                                dialog.dragPoint = handler.scenePoint
                                dialog.overIndex = dialog.indexUnder(handler.scenePoint)
                            }

                            onActiveChanged: {
                                if (active) {
                                    dialog.dragIndex = cell.index
                                    dialog.overIndex = -1
                                    /* A drag supersedes a tap that was waiting for
                                       its partner: one gesture, one intent. */
                                    dialog.pickedId = -1
                                    dialog.flashIds = []
                                    dialog.dragPoint = handler.scenePoint
                                    dialog.scrollClock = 0
                                    return
                                }

                                var from = dialog.dragIndex
                                var to = dialog.overIndex
                                dialog.dragIndex = -1
                                dialog.overIndex = -1
                                dialog.scrollClock = 0

                                /* Back into its cell. Restored as a BINDING: the
                                   handler wrote x and y directly while dragging, and
                                   a plain assignment would leave them literal for
                                   the rest of this delegate's life. The x binding is
                                   the centring one declared above, not a margin —
                                   restoring the wrong expression would leave every
                                   dragged tile flush against its cell's leading
                                   edge while its neighbours stayed centred. */
                                floater.x = Qt.binding(function () {
                                    return Math.round((grid.cellWidth
                                                       - floater.width) / 2)
                                })
                                floater.y = Qt.binding(function () {
                                    return Math.round(grid.gap / 2)
                                })

                                if (to >= 0 && to !== from)
                                    dialog.exchange(from, to)
                            }
                        }

                        /* The star sits on the tile rather than beside it, because
                           the tile is the row now. Smaller than a toolbar button: on
                           a tile this size a 48px target would take a third of the
                           name's width away, and the tile reserves exactly this much
                           for it. */
                        IconButton {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Tokens.spacing.xs
                            width: dialog.starSize
                            height: dialog.starSize
                            glyph: cell.modelData.favorite
                                   ? "ic_fluent_star_20_filled"
                                   : "ic_fluent_star_20_regular"
                            glyphSize: Tokens.icon.sm
                            glyphColor: cell.modelData.favorite ? Tokens.warning
                                                                : Fluent.textSecondary
                            tooltip: cell.modelData.favorite
                                     ? Strings.t("products.remove_favorite",
                                                 "Remove from favourites")
                                     : Strings.t("products.add_favorite",
                                                 "Add to favourites")
                            onClicked: if (dialog.ctrl)
                                           dialog.ctrl.setFavorite(cell.modelData.id,
                                                                   !cell.modelData.favorite)
                        }

                        RowLayout {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Tokens.spacing.xs
                            spacing: Tokens.spacing.xs

                            /* A product the till does not show. It can still be
                               arranged — pos's own query for this screen includes
                               hidden products deliberately — so without the marker,
                               swapping one is a move that visibly does nothing on
                               the till, which is its own version of "it works for
                               some tiles and not others". */
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                visible: cell.modelData.hidden === true
                                implicitWidth: hiddenIcon.width + Tokens.spacing.sm
                                implicitHeight: hiddenIcon.height + Tokens.spacing.xs
                                radius: Tokens.radius.pill
                                color: Tokens.dangerTint

                                Icon {
                                    id: hiddenIcon
                                    anchors.centerIn: parent
                                    icon: "ic_fluent_eye_off_20_regular"
                                    size: Tokens.icon.sm
                                    color: Tokens.danger
                                }

                                QC.ToolTip {
                                    text: Strings.t("products.hidden_on_pos",
                                                    "Hidden on the till")
                                    visible: hiddenHover.hovered
                                    delay: 400
                                }

                                HoverHandler { id: hiddenHover }
                            }

                            Item { Layout.fillWidth: true }

                            /* Where it sits in the order, so the arrangement is
                               still countable — a grid of forty tiles is hard to
                               audit by eye alone. It also carries the state a second
                               time: the number is the thing that just changed, so
                               the pill is where the eye is already looking. */
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: position.implicitWidth + Tokens.spacing.sm
                                implicitHeight: position.implicitHeight + 2
                                radius: Tokens.radius.pill
                                readonly property bool marked: cell.picked || cell.dragging
                                                               || cell.flashing
                                color: marked ? floater.ringColor
                                              : Fluent.subtleTertiary

                                Text {
                                    id: position
                                    anchors.centerIn: parent
                                    text: "\u200e" + (cell.index + 1)
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.overline
                                    font.weight: Font.DemiBold
                                    color: parent.marked ? Tokens.onBrand
                                                         : Fluent.textSecondary
                                }
                            }
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: grid.count === 0
                variant: "empty"
                title: dialog.onFavorites
                       ? Strings.t("favorites.empty.title", "No favourites yet")
                       : Strings.t("state.empty.title", "Nothing here yet")
                body: dialog.onFavorites
                      ? Strings.t("favorites.empty.body",
                                  "Star the products that sell all day; they become the first tab on the till.")
                      : ""
            }
        }

        Text {
            id: error
            Layout.fillWidth: true
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.danger
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            GlyphButton {
                visible: dialog.onFavorites && dialog.rows.length > 0
                glyph: "ic_fluent_broom_20_regular"
                text: Strings.t("favorites.clear", "Clear favourites")
                onClicked: if (dialog.ctrl) dialog.ctrl.clearFavorites()
            }

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }
        }
    }
}
