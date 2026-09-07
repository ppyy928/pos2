import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Barcode labels — the sheet that turns a shelf into printed prices.
 *
 *   ┌ search ────── [ category ]─┐ ┌ PREVIEW ────────── [⚙]┐
 *   │ Atlas Beans   288582…  [+] │ │   DZ-Retail Store     │
 *   │ Atlas Rice    288582…  [+] │ │   Atlas Beans         │
 *   │ Atlas Salt    (no code) [+] │ │   671.91 DA           │
 *   │ …                           │ │   ▍▍▎▍▎▍▍▎ 2885822…   │
 *   └─────────────────────────────┘ ├───────────────────────┤
 *                                   │ SHEET — 5      [🧹]   │
 *                                   │ Atlas Beans   [-]4[+] │
 *                                   │ Atlas Rice    [-]1[+] │
 *                                   │ 5 labels     [ Print ]│
 *                                   └───────────────────────┘
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
 * THE + ON THE ROW, AND WHY THE ROW ALSO HAS TO OPEN
 *
 * The explicit way onto the sheet is the + in the row's actions column — a picker
 * whose whole purpose is "put this one on the sheet" owes its primary action a hit
 * target of its own, and a double-click nobody can discover is not one. The row
 * still opens on Enter and double-click, because a keyboard-only pass through the
 * catalogue must not end at a dead row. There is no "queue all": a switch that
 * puts an unbounded number of labels on a roll in one press is a misfire with a
 * printer attached, and the operator who means it can hold the +.
 *
 * WHY THE PREVIEW IS NOT OPTIONAL
 *
 * The failure this screen has is silent: a barcode that renders too dense for the
 * shop's scanner, or a name that overflows a 40mm label, and both look fine on
 * paper until someone tries to scan it at the till. The picture is the same
 * `render_label_image` call the print path makes, so what is on screen is what the
 * printer receives — one render earlier. When the bars had to be squeezed to fit
 * the label, it says so under the picture rather than letting the till find out.
 *
 * THE TWO DESIGNS
 *
 * `classic_side` puts the price rotated in a band down the right-hand edge;
 * `bottom_price` puts it large along the bottom. Both print the same elements, so
 * the choice is one of shape, and the picture is the whole argument for either.
 * It is a setting rather than a per-print option — a shop prints one shape of
 * shelf label — which is why the settings page shows the same choice and the
 * older front end prints the same sticker.
 *
 * THE SETTINGS LIVE BEHIND THE GEAR ABOVE THE PICTURE
 *
 * Design, roll size and what the label carries are not a row of controls under
 * the picture — that row competed with the queue for the pane's height and read
 * as part of the sheet rather than as settings. One gear in the picture's header
 * row opens a small sheet with all three groups, written the moment they are
 * changed into the same `barcode.*` keys the Settings page holds: one store,
 * two doors, and the picture re-renders on every flip — the popup opens below
 * the picture, over the queue, never over the picture itself, so the consequence
 * of a switch is on screen while the switch still is.
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

    /* Nearly the window: this is a work surface, not a form — the catalogue
       wants its rows and the queue wants depth, and every pixel of margin is a
       row either list will not show. `breathing` comes down a notch with it
       (AppDialog's default is two xxl) for the same reason. */
    preferredWidth: 1560
    preferredHeight: 960
    breathing: 2 * Tokens.spacing.xl

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

    /* The designs the engine draws, in its own order. Their labels come from the
       catalogue; the keys never do. */
    readonly property var formats: ctrl ? ctrl.labelFormats : []

    readonly property var formatLabels: {
        var out = []
        for (var i = 0; i < formats.length; i++)
            out.push(Strings.t("barcode.tpl." + formats[i], formats[i]))
        return out
    }

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

    /* What the label carries, for the toggles below: a fresh JS object each
       time the controller re-notifies, which is what makes every switch the
       sheet writes re-render the switches themselves. */
    readonly property var flags: ctrl ? ctrl.labelFlags : ({})

    // -- the shape it is printed in ----------------------------------------
    function formatIndex() {
        var current = ctrl ? ctrl.labelFormat : ""
        for (var i = 0; i < formats.length; i++)
            if (formats[i] === current)
                return i
        return 0
    }

    function chooseFormat(index) {
        if (!ctrl || index < 0 || index >= formats.length)
            return
        if (formats[index] === ctrl.labelFormat)
            return
        ctrl.setLabelFormat(formats[index])
        /* Re-render at once: the picture is the entire reason to choose. */
        show(shownId)
    }

    /* One content switch, and the picture follows it — a switch whose effect
       only showed on the next preview would be a switch nobody trusts. The
       value is kept by the controller, in the store the Settings page reads. */
    function toggleFlag(key, on) {
        if (!ctrl)
            return
        ctrl.setLabelFlag(key, on)
        show(shownId)
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
    // THE SETTINGS POPUP
    // =====================================================================
    /* Everything that shapes the picture, in one small sheet: the design,
       the roll's size, and what is printed on it. Every change is written
       the moment it is made — the same keys the Settings page holds, so this
       is a second door into one store, never a second store — and the picture
       re-renders on each one, which is the whole reason to change a label
       here rather than in Settings.

       MODAL, WITH AN INVISIBLE SCRIM. A non-modal popup in the overlay can
       let a press near its edges — or after any future geometry change —
       land on the queue's stepper buttons underneath it, which is exactly
       the "I clicked the settings and a label count changed" this sheet
       must never do. `modal: true` puts the overlay's input grab in force:
       nothing behind the sheet is reachable while it is up. The scrim is
       replaced with a plain Item so nothing is dimmed — the preview above
       stays at full contrast, which is the whole reason to watch it while
       flipping switches — and each popup owns its own scrim, so the dialog
       underneath keeps its own dim. Clicking anywhere outside — the gear
       again, the catalogue, the queue — closes the sheet and is consumed by
       the scrim, so the queue can only be acted on once the sheet is gone.

       Positioned under the picture, never over it: what a switch changes is
       on screen while the switch is. */
    QC.Popup {
        id: labelSheet

        parent: frame
        /* Right edges aligned, dropping out of the gear's end of the row above
           the frame. */
        x: frame.width - width
        y: frame.height + Tokens.spacing.xs
        width: 400
        padding: Tokens.spacing.md
        modal: true
        /* A scrim that dims nothing. `Overlay.modal` is per popup: this one
           grabs input without painting over the preview, and the dialog below
           keeps its own. */
        QC.Overlay.modal: Item { }
        focus: true
        closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutside

        background: Rectangle {
            color: Fluent.popupBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder
        }

        onOpened: dialog.syncLabelSettings()

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.md

            Text {
                Layout.fillWidth: true
                text: Strings.t("barcode.settings", "Label settings")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.subtitle
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }

            // -- the design
            Text {
                text: Strings.t("barcode.format", "Label design")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1
                color: Fluent.textTertiary
            }

            Segmented {
                id: design

                Layout.fillWidth: true
                items: dialog.formatLabels

                /* Segmented assigns its own currentIndex from a MouseArea,
                    which would destroy a binding placed on it — the same trap
                    LoginPage's language picker documents. So the link to the
                    setting runs imperatively both ways; assigning an unchanged
                    value emits nothing, so it converges. */
                onCurrentIndexChanged: dialog.chooseFormat(currentIndex)
            }

            // -- the roll
            Text {
                text: Strings.t("barcode.size", "Label size")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1
                color: Fluent.textTertiary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.lg

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: Strings.t("barcode.width", "Width")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Fluent.textSecondary
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.xs

                        NumberField {
                            id: rollWidth

                            Layout.fillWidth: true
                            Layout.preferredHeight: Tokens.size.controlSmall
                            font.pixelSize: Tokens.font.body

                            /* Written on commit, and only when it moved: a
                               focus loss is not a decision, and re-writing the
                               same millimetres is a line in the log that says
                               nothing happened. Clamped by the controller, and
                               the field re-reads after the write so a value
                               that was pulled into range says so. */
                            onEditingFinished: {
                                if (!dialog.ctrl || blank)
                                    return
                                if (Math.abs(value - dialog.ctrl.labelWidth) < 0.05)
                                    return
                                dialog.ctrl.setLabelWidth(value)
                                text = String(dialog.ctrl.labelWidth)
                                dialog.show(dialog.shownId)
                            }
                        }

                        Text {
                            text: "mm"
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textTertiary
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: Strings.t("barcode.height", "Height")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Fluent.textSecondary
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.xs

                        NumberField {
                            id: rollHeight

                            Layout.fillWidth: true
                            Layout.preferredHeight: Tokens.size.controlSmall
                            font.pixelSize: Tokens.font.body

                            onEditingFinished: {
                                if (!dialog.ctrl || blank)
                                    return
                                if (Math.abs(value - dialog.ctrl.labelHeight) < 0.05)
                                    return
                                dialog.ctrl.setLabelHeight(value)
                                text = String(dialog.ctrl.labelHeight)
                                dialog.show(dialog.shownId)
                            }
                        }

                        Text {
                            text: "mm"
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textTertiary
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Fluent.dividerBorder
            }

            // -- what the label carries
            Text {
                text: Strings.t("barcode.contents", "On the label")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1
                color: Fluent.textTertiary
            }

            Repeater {
                model: [
                    { key: "show_store", label: Strings.t("settings.barcode.show_store",
                                                          "Print the shop name") },
                    { key: "show_name",  label: Strings.t("settings.barcode.show_name",
                                                          "Print the product name") },
                    { key: "show_price", label: Strings.t("settings.barcode.show_price",
                                                          "Print the price") }
                ]

                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        color: Fluent.textPrimary
                        elide: Text.ElideRight
                    }

                    QC.Switch {
                        checked: dialog.flags
                                 && dialog.flags[modelData.key] === true
                        onToggled: dialog.toggleFlag(modelData.key, checked)
                    }
                }
            }
        }
    }

    /* The popup's fields are set, not bound — typing in one breaks a binding,
       and the next open would show the first keystroke's ghost. Re-read from
       the store on every open instead, which is also what makes a change made
       in Settings show up here without this file knowing that screen exists. */
    function syncLabelSettings() {
        if (!ctrl)
            return
        design.currentIndex = formatIndex()
        rollWidth.text = String(ctrl.labelWidth)
        rollHeight.text = String(ctrl.labelHeight)
    }

    // =====================================================================
    // COLUMNS
    // =====================================================================
    /* The trailing + is the explicit way onto the sheet. The row still
       double-clicks (rowActivated below), but a picker whose whole purpose is
       "put this one on the sheet" owes its primary action a hit target of its
       own — the same conclusion every actions column in the app reached.

       One action per row, and it carries its own label because RowActions
       would otherwise look up "action.add" — "Add", which is true of nearly
       every button in the app and says nothing about this one. */
    readonly property var rowAction: [
        {
            id: "add",
            glyph: "ic_fluent_add_circle_20_regular",
            tone: "primary",
            label: Strings.t("barcode.enqueue", "Queue one label"),
            /* Dimmed, not hidden, for the products with no code: the row is
               listed and says why, and a + that vanished would leave the
               row's shape different for a reason nothing on it explains. */
            enabled: function (row) { return row && row.has_barcode }
        }
    ]

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
        },
        {
            key: "actions",
            actions: rowAction
        }
    ]

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

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
            // THE CATALOGUE — its own filters, directly above its own table
            // -----------------------------------------------------------------
            /* Search and category live in this column, not across the top of
               the dialog: the left pane is one self-contained surface — find,
               narrow, queue — and the row of controls that narrow the table
               belongs to the table. The right pane starts at the top of the
               split, which buys the picture the height the search row used to
               take off it. */
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.xs

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
                }

                Text {
                    text: Strings.t("barcode.pick",
                                    "Tap + on a product to queue one label")
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

                    /* The + on the row. Double-click and Enter still work —
                       rowActivated is the keyboard's way in. */
                    onActionTriggered: (row, action) => {
                        if (action !== "add")
                            return
                        if (row >= 0 && row < dialog.candidates.length)
                            dialog.enqueue(dialog.candidates[row])
                    }
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
                Layout.preferredWidth: 520
                Layout.maximumWidth: 520
                Layout.fillHeight: true
                spacing: Tokens.spacing.sm

                // -- the picture's header: its name, and its settings
                /* The gear ABOVE the container, not beside it: the picture
                   then takes the pane's full width, and the button reads as
                   heading the thing it settings, the same way the broom
                   heads the sheet below. The settings sheet it opens lands
                   under the picture — over the queue, never over the
                   picture — so what a switch changes is on screen while the
                   switch is. */
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    Text {
                        Layout.fillWidth: true
                        text: Strings.t("barcode.preview", "Preview")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.overline
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.1
                        color: Fluent.textTertiary
                    }

                    IconButton {
                        id: labelSettings

                        glyph: "ic_fluent_settings_20_regular"
                        glyphSize: Tokens.icon.sm
                        tooltip: Strings.t("barcode.settings", "Label settings")
                        onClicked: labelSheet.open()
                    }
                }

                // -- what will come out of the printer
                Rectangle {
                    id: frame

                    Layout.fillWidth: true
                    Layout.preferredHeight: 280
                    radius: Tokens.radius.md
                    color: Fluent.subtleSecondary
                    border.width: 1
                    border.color: Fluent.dividerBorder

                    Image {
                        anchors.centerIn: parent
                        /* Bounded by the panel, never enlarged past its own pixels:
                           a 320x160 label blown up to full width would show the
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

                // -- what the printer had to give up to fit the bars on
                Text {
                    Layout.fillWidth: true
                    visible: dialog.ctrl && dialog.ctrl.previewDegraded
                    text: Strings.t("barcode.degraded",
                                    "The barcode was squeezed to fit this label size — test one scan before printing the shelf.")
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Tokens.warning
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

                                NumberField {
                                    Layout.preferredWidth: 56
                                    Layout.preferredHeight: Tokens.size.controlSmall
                                    text: String(line.modelData.copies)
                                    horizontalAlignment: TextInput.AlignHCenter
                                    /* A count of sheets, so whole numbers only —
                                       half a label is not a thing to print. */
                                    inputMethodHints: Qt.ImhDigitsOnly
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
