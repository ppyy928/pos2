import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Find one product: type, or scan, or browse.
 *
 *   ┌──────────────────────────────────────────────┐ ┌───┐
 *   │ yog                                          │ │ ▤ │
 *   └──────────────────────────────────────────────┘ └───┘
 *   ┌──────────────────────────────────────────────┐
 *   │ Yoghurt 1L        5449000996  · Dairy    24  │
 *   │ Yoghurt fraise    5449000521  · Dairy    12  │
 *   └──────────────────────────────────────────────┘
 *
 * WHY THIS IS A COMPONENT AND NOT A SEARCH BOX PER SCREEN
 *
 * The till already had this interaction — a field whose matches drop under it, and a
 * button that lists the whole catalogue when the name is only half remembered — and
 * the stocktake and the stock ledger need exactly the same thing. The first version
 * of those two screens did not have it: they listed every product in the shop and
 * left the operator to search, type, clear the search, and search again. Three
 * thousand rows to walk one shelf.
 *
 * So the interaction lives here once. The DATA does not: each caller searches its own
 * way, sets `results`, and receives `picked`. That split is what lets the same control
 * sit over a stocktake sheet and over a movement ledger without either of them
 * knowing about the other.
 *
 * WHY THE BROWSE LIST IS A POPUP INSIDE THIS COMPONENT
 *
 * It cannot be a workflow dialog: DialogHost shows one at a time, so opening a
 * picker from inside the stocktake would destroy the stocktake. It is the same list
 * as the dropdown, given room — one data path, two presentations.
 *
 * SCANNING
 *
 * A scanner types fast and ends with Return. `accepted` reports the raw text so a
 * caller can resolve a barcode exactly, and takes the single match when the text was
 * typed by a person instead. Nothing here debounces: the caller decides, because a
 * scan must not wait 300ms and a name should.
 */
Item {
    id: finder

    // =====================================================================
    // API
    // =====================================================================
    property string placeholder: ""

    /* What the caller found for the current query. Rows are plain objects; only
       `name` is required. `barcode`, `category` and `stock_text` are drawn when
       present, which is what makes one component fit a catalogue row and a
       stock row. */
    property var results: []

    /* Rows visible before the dropdown scrolls. Five is the till's number and the
       reason is the same: a list that covers half the screen to answer a
       three-letter query is worse than one that scrolls. */
    property int rows: 6

    /* Shown in the browse popup. Usually the caller's unfiltered list. */
    property var all: []

    readonly property alias query: field.text
    readonly property alias searchField: field

    property bool enabled: true

    /* The operator typed or cleared. The caller answers by setting `results`. */
    signal queried(string text)
    /* Return in the field: `text` is raw, for a caller that wants to try it as a
       barcode before falling back to the visible matches. */
    signal accepted(string text)
    /* One row was chosen, from the dropdown or from the browse list. */
    signal picked(var product)
    /* The browse popup is opening and wants its list. */
    signal browsed()

    function clear() {
        field.clear()
        finder.queried("")
    }

    function focusSearch() { field.forceActiveFocus() }

    function take(row) {
        if (!row)
            return
        finder.picked(row)
        /* Cleared after a pick, always. The next thing an operator does is find the
           next product, and a field still holding the last name is a field they have
           to empty first — which is the complaint this component exists to answer. */
        field.clear()
        finder.queried("")
        browse.close()
        field.forceActiveFocus()
    }

    implicitHeight: bar.implicitHeight

    // =====================================================================
    // THE BAR
    // =====================================================================
    RowLayout {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.sm

        QC.TextField {
            id: field
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.size.control
            enabled: finder.enabled
            placeholderText: finder.placeholder
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            onTextChanged: finder.queried(text)
            onAccepted: finder.accepted(text)
        }

        IconButton {
            glyph: "ic_fluent_apps_list_20_regular"
            glyphSize: Tokens.icon.md
            enabled: finder.enabled
            tooltip: Strings.t("selector.open_picker", "Browse all products")
            onClicked: {
                finder.browsed()
                browse.open()
            }
        }
    }

    // =====================================================================
    // THE DROPDOWN
    // =====================================================================
    /*
     * Anchored under the field, not the bar: the bar also holds the browse button,
     * and the list belongs to the thing being typed into.
     *
     * `NoAutoClose` because the field keeps focus while this is open — every
     * keystroke goes to the box, and a popup that closes on the first key press is a
     * popup that never opens.
     */
    QC.Popup {
        id: hits

        parent: field
        x: 0
        y: field.height + Tokens.spacing.xs
        width: field.width
        /* Sized from the model, not from the list's contentHeight: the content is a
           child of this popup, so it is not laid out until the popup opens, and the
           popup cannot open at a sensible height until it is. Row count and a row
           token need neither. Snapped to whole rows, because a sixth row sliced
           through the middle reads as a rendering fault. */
        implicitHeight: Math.min(finder.rows, finder.results.length)
                        * Tokens.size.tableRow + 2 * Tokens.spacing.xs
        padding: Tokens.spacing.xs
        modal: false
        focus: false
        closePolicy: QC.Popup.NoAutoClose
        visible: field.text !== "" && finder.results.length > 0 && !browse.visible

        background: Rectangle {
            color: Fluent.popupBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder
        }

        contentItem: ListView {
            clip: true
            model: finder.results
            boundsBehavior: Flickable.StopAtBounds
            QC.ScrollBar.vertical: FluentScrollBar { }
            delegate: Row_ { }
        }
    }

    // =====================================================================
    // THE BROWSE LIST
    // =====================================================================
    QC.Popup {
        id: browse

        parent: QC.Overlay.overlay
        anchors.centerIn: QC.Overlay.overlay
        width: Math.min(760, finder.Window.width - 2 * Tokens.spacing.xxl)
        height: Math.min(620, finder.Window.height - 2 * Tokens.spacing.xxl)
        padding: Tokens.spacing.md
        modal: true
        focus: true

        background: Rectangle {
            color: Fluent.popupBackground
            radius: Tokens.radius.lg
            border.width: 1
            border.color: Fluent.dividerBorder
        }

        onOpened: sieve.forceActiveFocus()

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.sm

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.sm

                Text {
                    Layout.fillWidth: true
                    text: Strings.t("selector.all_products", "All products")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.subtitle
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                IconButton {
                    glyph: "ic_fluent_dismiss_20_regular"
                    glyphSize: Tokens.icon.sm
                    onClicked: browse.close()
                }
            }

            /* Its own filter, over the caller's full list. Filtered here rather than
               by another round trip: the list is already in memory, and a browse
               popup that lags behind the keyboard is worse than the dropdown it was
               opened instead of. */
            QC.TextField {
                id: sieve
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("products.search.ph",
                                           "Search by name or barcode")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
            }

            ListView {
                id: shelf
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                QC.ScrollBar.vertical: FluentScrollBar { }

                model: {
                    var needle = sieve.text.trim().toLowerCase()
                    var source = finder.all.length > 0 ? finder.all : finder.results
                    if (needle === "")
                        return source
                    var out = []
                    for (var i = 0; i < source.length; i++) {
                        var row = source[i]
                        if (String(row.name).toLowerCase().indexOf(needle) >= 0
                                || String(row.barcode || "").toLowerCase()
                                   .indexOf(needle) >= 0)
                            out.push(row)
                    }
                    return out
                }

                delegate: Row_ { }
            }

            Text {
                Layout.fillWidth: true
                visible: shelf.count === 0
                horizontalAlignment: Text.AlignHCenter
                text: Strings.t("state.no_results.title", "No matches")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textTertiary
            }
        }
    }

    // =====================================================================
    // ONE ROW, BOTH LISTS
    // =====================================================================
    /* Declared once and used by the dropdown and the browse list, so a product
       reads identically wherever it is chosen from. */
    component Row_: Rectangle {
        id: hit

        required property var modelData

        width: ListView.view ? ListView.view.width : 0
        height: Tokens.size.tableRow
        radius: Tokens.radius.sm
        color: hover.hovered ? Fluent.subtleSecondary : "transparent"

        HoverHandler { id: hover }
        TapHandler { onTapped: finder.take(hit.modelData) }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacing.sm
            anchors.rightMargin: Tokens.spacing.sm
            spacing: Tokens.spacing.sm

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft
                    text: hit.modelData.name
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textPrimary
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    horizontalAlignment: Text.AlignLeft
                    /* The barcode is why a partly typed code finds anything, so it
                       is worth showing which one matched; the category comes second
                       because two products often share a name. */
                    text: {
                        var parts = []
                        if (hit.modelData.barcode)
                            parts.push("\u200e" + hit.modelData.barcode)
                        if (hit.modelData.category)
                            parts.push(hit.modelData.category)
                        return parts.join("  ·  ")
                    }
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    color: Fluent.textTertiary
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: text !== ""
                text: hit.modelData.stock_text !== undefined
                      ? "\u200e" + hit.modelData.stock_text : ""
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }
        }
    }
}
