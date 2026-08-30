import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Barcode labels — the sheet that turns a shelf into printed prices.
 *
 *   ┌ search ─────────────────┐ ┌ preview ──────────────┐
 *   │ Atlas Beans   288582…   │ │   DZ-Retail Store     │
 *   │ Atlas Rice    288582…   │ │   Atlas Beans         │
 *   │ Atlas Salt    (no code) │ │   671.91 DA           │
 *   │ …                       │ │   ▍▍▎▍▎▍▍▎ 2885822…   │
 *   └─────────────────────────┘ ├───────────────────────┤
 *                               │ queue                 │
 *                               │ Atlas Beans   [-]4[+] │
 *                               │ Atlas Rice    [-]1[+] │
 *                               │ 5 labels     [ Print ]│
 *                               └───────────────────────┘
 *
 * WHY THIS SCREEN DID NOT EXIST
 *
 * `barcode_labels` was registered in workflows.py and had no file behind it, so the
 * button in the products page opened "this screen is not available yet". The
 * renderer was never the missing part — `label_printing.py` is 588 lines of working
 * TSPL, barcode rasterising and Arabic shaping — the surface was.
 *
 * WHY A QUEUE AND NOT A SELECTION
 *
 * A shelf label is printed in a *quantity*: eleven facings of the same tin means
 * eleven labels, and a delivery of one new product means one. A checkbox column
 * cannot say eleven. So the left pane is the catalogue and the right pane is a
 * queue with a count on every line — which is also the order the labels come off
 * the roll, so an operator can walk the shelf in the order they built it.
 *
 * WHY THE PREVIEW IS NOT OPTIONAL
 *
 * The failure this screen has is silent: a barcode that renders too dense for the
 * shop's scanner, or a name that overflows a 40mm label, and both look fine on
 * paper until someone tries to scan it at the till. The picture is the same
 * `render_label_image` call the print path makes, so what is on screen is what the
 * printer receives — one render earlier.
 *
 * WHAT CANNOT BE LABELLED
 *
 * A product with no barcode. It is listed anyway, dimmed and marked, because "why
 * is this one not here" is a worse question than a row that explains itself — and
 * the fix is one click away in the product record.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.printing : null
    readonly property var products: (typeof app !== "undefined" && app) ? app.products : null

    preferredWidth: 1420
    preferredHeight: 900

    title: Strings.t("products.hdr.barcode", "Barcode labels")

    // =====================================================================
    // STATE
    // =====================================================================
    /* The catalogue, label-ready: raw prices, and a flag for the ones that have no
       code to print. Loaded once per search rather than per keystroke. */
    property var candidates: []

    /* [{ id, name, barcode, price, price_text, copies }] — the sheet. */
    property var queue: []

    /* Which queue line the preview is of. An id, not an index: removing a line
       above it must not silently repoint the picture at a different product. */
    property int shownId: -1

    property string search: context && context.search ? context.search : ""
    property int categoryId: context && context.category_id ? context.category_id : 0

    property string notice: ""

    readonly property int totalLabels: {
        var n = 0
        for (var i = 0; i < queue.length; i++)
            n += queue[i].copies
        return n
    }

    Component.onCompleted: {
        if (products && products.loadCategories)
            products.loadCategories()
        reload()
        /* `searchText` is a read-only alias; the field itself is what is writable,
           and FilterBar exposes it for exactly this. Seeded rather than left blank
           because this dialog is opened from a products page that already had a
           filter set, and starting over would be work the operator already did. */
        if (search !== "")
            filter.searchField.text = search
    }

    function reload() {
        candidates = ctrl ? ctrl.labelCandidates(search, categoryId) : []
    }

    // -- the queue ---------------------------------------------------------
    function indexInQueue(id) {
        for (var i = 0; i < queue.length; i++)
            if (queue[i].id === id)
                return i
        return -1
    }

    /* Adding what is already queued raises its count instead of opening a second
       line — the till's own rule for the same reason: two lines for one product is
       a total the operator has to add up by eye. */
    function enqueue(row) {
        if (!row || !row.has_barcode)
            return
        var at = indexInQueue(row.id)
        var next = queue.slice()
        if (at >= 0) {
            next[at] = Object.assign({}, next[at], { copies: next[at].copies + 1 })
        } else {
            next.push({
                id: row.id, name: row.name, barcode: row.barcode,
                price: row.price, price_text: row.price_text, copies: 1
            })
        }
        queue = next
        show(row.id)
    }

    function setCopies(id, copies) {
        var at = indexInQueue(id)
        if (at < 0)
            return
        var value = Math.max(1, Math.min(999, Math.round(copies)))
        var next = queue.slice()
        next[at] = Object.assign({}, next[at], { copies: value })
        queue = next
    }

    function dequeue(id) {
        var at = indexInQueue(id)
        if (at < 0)
            return
        var next = queue.slice()
        next.splice(at, 1)
        queue = next
        if (shownId === id)
            show(next.length > 0 ? next[Math.min(at, next.length - 1)].id : -1)
    }

    function clearQueue() {
        queue = []
        show(-1)
        if (ctrl)
            ctrl.clearPreview()
    }

    /* Everything the current filter matched, one label each — the "new price list
       for this category" case, which is the one that makes this screen worth
       opening at all. */
    function enqueueAll() {
        var next = queue.slice()
        for (var i = 0; i < candidates.length; i++) {
            var row = candidates[i]
            if (!row.has_barcode)
                continue
            var at = -1
            for (var j = 0; j < next.length; j++)
                if (next[j].id === row.id) { at = j; break }
            if (at < 0)
                next.push({
                    id: row.id, name: row.name, barcode: row.barcode,
                    price: row.price, price_text: row.price_text, copies: 1
                })
        }
        queue = next
        if (next.length > 0 && shownId < 0)
            show(next[0].id)
    }

    // -- the picture -------------------------------------------------------
    function show(id) {
        shownId = id
        if (!ctrl)
            return
        var at = indexInQueue(id)
        if (at < 0) {
            ctrl.clearPreview()
            return
        }
        ctrl.previewLabel(queue[at])
    }

    /* Not print: QML reserves that name — a unction print() on an item is an
       illegal method name and the whole file fails to load. */
    function send() {
        notice = ""
        if (ctrl)
            ctrl.printLabels(queue)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onPrinted(result) {
            /* Stays open: the next thing an operator does after printing a shelf is
               print the next shelf, and the queue they just built is the starting
               point for it. */
            dialog.notice = Strings.tf("barcode.sent", "{count} labels sent to {printer}",
                                       { count: result.count,
                                         printer: dialog.ctrl.labelPrinter })
        }

        function onPrintFailed(message) {
            dialog.notice = ""
        }
    }

    // =====================================================================
    // COLUMNS
    // =====================================================================
    readonly property var candidateColumns: [
        {
            key: "name",
            header: Strings.t("products.col.name", "Product"),
            stretch: true,
            tone: function (r) { return r.has_barcode ? "" : "muted" }
        },
        {
            key: "barcode_text",
            header: Strings.t("products.col.barcode", "Barcode"),
            width: 220,
            ltr: true,
            /* The empty ones say so rather than showing a blank cell that could
               equally be a rendering fault — the sentence comes from the bridge,
               because DataTable renders a column's key verbatim. */
            tone: function (r) { return r.has_barcode ? "" : "danger" }
        },
        {
            key: "price_text",
            header: Strings.t("products.col.sale_price", "Price"),
            numeric: true,
            width: 160,
            ltr: true
        }
    ]

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            FilterBar {
                id: filter
                Layout.fillWidth: true
                placeholder: Strings.t("products.search.ph",
                                       "Search by name or barcode")
                onSearchTextChanged: debounce.restart()
            }

            QC.ComboBox {
                Layout.preferredWidth: 260
                Layout.preferredHeight: Tokens.size.control
                textRole: "name"
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                model: {
                    var out = [{ id: 0,
                                 name: Strings.t("products.filter.all_categories",
                                                 "All categories") }]
                    var src = dialog.products ? dialog.products.categories : null
                    if (src)
                        for (var i = 0; i < src.length; i++)
                            out.push(src[i])
                    return out
                }
                onActivated: (index) => {
                    dialog.categoryId = model[index].id
                    dialog.reload()
                }
            }

            GlyphButton {
                glyph: "ic_fluent_add_square_multiple_20_regular"
                text: Strings.t("barcode.add_all", "Queue all")
                enabled: dialog.candidates.length > 0
                onClicked: dialog.enqueueAll()
            }
        }

        Timer {
            id: debounce
            interval: 300
            onTriggered: {
                dialog.search = filter.searchText
                dialog.reload()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.md

            // -----------------------------------------------------------------
            // THE CATALOGUE
            // -----------------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.xs

                Text {
                    text: Strings.t("barcode.pick",
                                    "Tap a product to queue one label")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Fluent.textTertiary
                }

                DataTable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: dialog.candidateColumns
                    model: dialog.candidates
                    emptyIcon: "ic_fluent_barcode_scanner_20_regular"
                    emptyText: Strings.t("state.no_results.title", "No matches")
                    onRowActivated: (row) => {
                        if (row >= 0 && row < dialog.candidates.length)
                            dialog.enqueue(dialog.candidates[row])
                    }
                }
            }

            // -----------------------------------------------------------------
            // THE PICTURE AND THE SHEET
            // -----------------------------------------------------------------
            ColumnLayout {
                Layout.preferredWidth: 470
                Layout.maximumWidth: 470
                Layout.fillHeight: true
                spacing: Tokens.spacing.sm

                // -- what will come out of the printer
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    radius: Tokens.radius.md
                    color: Fluent.subtleSecondary
                    border.width: 1
                    border.color: Fluent.dividerBorder

                    Image {
                        anchors.centerIn: parent
                        /* Bounded by the panel, never enlarged past its own pixels:
                           a 320x160 label blown up to 470 wide would show the
                           operator a smoother barcode than the printer can make. */
                        width: Math.min(parent.width - 2 * Tokens.spacing.md,
                                        sourceSize.width > 0 ? sourceSize.width : 1)
                        height: sourceSize.width > 0
                                ? width * sourceSize.height / sourceSize.width : 0
                        visible: dialog.ctrl && dialog.ctrl.preview !== ""
                        source: dialog.ctrl ? dialog.ctrl.preview : ""
                        smooth: false
                        fillMode: Image.PreserveAspectFit
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !dialog.ctrl || dialog.ctrl.preview === ""
                        spacing: Tokens.spacing.xs

                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            icon: "ic_fluent_barcode_scanner_20_regular"
                            size: Tokens.icon.xl
                            color: Fluent.textTertiary
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Strings.t("barcode.preview.empty",
                                            "Queue a product to see its label")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textTertiary
                        }
                    }
                }

                // -- the sheet
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    Text {
                        Layout.fillWidth: true
                        text: Strings.tf("barcode.queue", "Sheet — {count} labels",
                                         { count: dialog.totalLabels })
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.overline
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.1
                        color: Fluent.textTertiary
                    }

                    IconButton {
                        visible: dialog.queue.length > 0
                        glyph: "ic_fluent_broom_20_regular"
                        glyphSize: Tokens.icon.sm
                        tooltip: Strings.t("action.clear", "Clear")
                        onClicked: dialog.clearQueue()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.radius.md
                    color: Fluent.subtleSecondary
                    border.width: 1
                    border.color: Fluent.dividerBorder
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 2 * Tokens.spacing.lg
                        visible: dialog.queue.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: Strings.t("barcode.queue.empty",
                                        "Nothing queued yet. Tap products on the left, or use Queue all.")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        color: Fluent.textTertiary
                    }

                    ListView {
                        id: sheet
                        anchors.fill: parent
                        anchors.margins: Tokens.spacing.xs
                        clip: true
                        model: dialog.queue
                        spacing: 2

                        QC.ScrollBar.vertical: FluentScrollBar {
                            policy: QC.ScrollBar.AsNeeded
                        }

                        delegate: Rectangle {
                            id: line
                            required property var modelData
                            required property int index

                            readonly property bool shown: dialog.shownId === line.modelData.id

                            width: sheet.width - Tokens.spacing.sm
                            height: Tokens.size.control + Tokens.spacing.sm
                            radius: Tokens.radius.sm
                            color: line.shown ? Tokens.brandTint
                                 : hover.hovered ? Fluent.subtleTertiary : "transparent"

                            HoverHandler { id: hover }

                            TapHandler {
                                /* Tapping a line points the preview at it — the one
                                   way to check a label without printing it. */
                                onTapped: dialog.show(line.modelData.id)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.spacing.sm
                                anchors.rightMargin: Tokens.spacing.xs
                                spacing: Tokens.spacing.xs

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: line.modelData.name
                                        elide: Text.ElideRight
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.body
                                        color: Fluent.textPrimary
                                    }

                                    Text {
                                        text: "\u200e" + line.modelData.price_text
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.caption
                                        color: Fluent.textTertiary
                                    }
                                }

                                /* A stepper, not a text field: the number is between
                                   one and a dozen almost every time, and a keyboard
                                   on a till is a step the shelf does not need. The
                                   field is still there for the case of fifty. */
                                IconButton {
                                    glyph: "ic_fluent_subtract_20_regular"
                                    glyphSize: Tokens.icon.sm
                                    enabled: line.modelData.copies > 1
                                    onClicked: dialog.setCopies(line.modelData.id,
                                                                line.modelData.copies - 1)
                                }

                                QC.TextField {
                                    Layout.preferredWidth: 56
                                    Layout.preferredHeight: Tokens.size.controlSmall
                                    text: String(line.modelData.copies)
                                    horizontalAlignment: TextInput.AlignHCenter
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.body
                                    onEditingFinished: dialog.setCopies(
                                        line.modelData.id, parseInt(text) || 1)
                                }

                                IconButton {
                                    glyph: "ic_fluent_add_20_regular"
                                    glyphSize: Tokens.icon.sm
                                    onClicked: dialog.setCopies(line.modelData.id,
                                                                line.modelData.copies + 1)
                                }

                                IconButton {
                                    glyph: "ic_fluent_dismiss_20_regular"
                                    glyphSize: Tokens.icon.sm
                                    glyphColor: Tokens.danger
                                    onClicked: dialog.dequeue(line.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        // WHERE IT GOES, AND GO
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            /* The destination, named. "Printed" with nothing coming out of a
               printer is this feature's most confusing outcome, and saying which
               device up front is most of the cure. */
            Text {
                Layout.fillWidth: true
                text: {
                    var name = dialog.ctrl ? dialog.ctrl.labelPrinter : ""
                    if (dialog.notice !== "")
                        return dialog.notice
                    if (dialog.ctrl && dialog.ctrl.error !== "")
                        return dialog.ctrl.error
                    return name !== ""
                           ? Strings.tf("barcode.printer", "Label printer: {printer}",
                                        { printer: name })
                           : Strings.t("barcode.no_printer",
                                       "No label printer is set in Settings.")
                }
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: dialog.notice !== "" ? Font.DemiBold : Font.Normal
                color: dialog.ctrl && dialog.ctrl.error !== "" ? Tokens.danger
                     : dialog.notice !== "" ? Tokens.success
                     : Fluent.textSecondary
            }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_print_20_regular"
                text: Strings.tf("barcode.print", "Print {count}",
                                 { count: dialog.totalLabels })
                highlighted: true
                enabled: dialog.queue.length > 0
                         && dialog.ctrl && dialog.ctrl.available
                         && !dialog.ctrl.busy
                onClicked: dialog.send()
            }
        }
    }
}
