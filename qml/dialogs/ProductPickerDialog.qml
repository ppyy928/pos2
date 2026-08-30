import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Find a product — the whole catalogue, in one list, filtered as you type.
 *
 *   ┌──────────────────────────────────────────────────────────┐
 *   │ [ atlas det                                            ] │
 *   │ ┌──────────────────────────────────────────────────────┐ │
 *   │ │ Atlas Detergent 1L          138      3,934.43        │ │
 *   │ │ 6133012345678 · Cleaning                             │ │
 *   │ │ Atlas Detergent 250ml  [Hidden]  65   2,003.21       │ │
 *   │ └──────────────────────────────────────────────────────┘ │
 *   │ 10 of 2,999                                    [Close]   │
 *   └──────────────────────────────────────────────────────────┘
 *
 * WHY EVERYTHING AT ONCE
 *
 * The catalogue is loaded once, when the dialog opens, and filtered in JavaScript.
 * No paging, no lazy loading, no query per keystroke.
 *
 * That is a deliberate reversal of what the two existing inline product popups do —
 * PurchaseFormDialog and MultiUnitsDialog both call `app.products.load(text, 1, 8, 0)`
 * on every keystroke and show the first eight matches. Eight is enough to recognise
 * a product you can already name. It is useless for the question this dialog exists
 * to answer, which is "what was that thing called" — and a hard eight-row ceiling
 * means the row you wanted may never appear no matter how you refine the query.
 *
 * The cost is one call returning every product: about 200 bytes a row, so a
 * 3000-product shop hands over half a megabyte, once. A JavaScript pass over 3000
 * rows takes well under a millisecond, so the list narrows on the keystroke rather
 * than after a round trip, and ListView instantiates only the dozen delegates it can
 * actually show. Till.CATALOGUE_MAX is the fuse on that reasoning.
 *
 * It also does not touch `app.products`, which those two popups do — that controller
 * backs the Products screen, and borrowing it overwrites the rows, the total and the
 * stored query that screen is bound to.
 *
 * WHAT IT SHOWS THAT THE TILE WALL CANNOT
 *
 * Every product, including the ones kept off the till (`show_on_pos = 0`) and the
 * ones out of stock. Both are marked. A hidden product is perfectly sellable — the
 * barcode scanner has always found them — so refusing to list them here would leave
 * the operator no way to sell something that is sitting on the shelf.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var till: (typeof app !== "undefined" && app) ? app.pos : null

    preferredWidth: 1040
    preferredHeight: 860

    title: Strings.t("product_select.title", "Find a product")

    /* The catalogue, as handed over once. Never re-fetched while the dialog is
       open: a price or a stock figure changing under the operator mid-search would
       reorder the list they are reading. */
    property var all: []
    property string query: ""

    /* Which row Enter takes. Reset whenever the query changes, because row 4 of the
       old list is a different product from row 4 of the new one. */
    property int selected: 0

    Component.onCompleted: {
        all = till ? till.catalogue() : []
        field.forceActiveFocus()
    }

    /*
     * The filter.
     *
     * Name OR barcode, which is what `fetch_products` matches in SQL — so typing
     * part of a code finds the product the same way typing part of a name does, and
     * this dialog agrees with the dropdown behind it.
     *
     * `toLowerCase` rather than a locale-aware fold: SQLite's ILIKE is itself only
     * ASCII-case-insensitive, so matching JavaScript's default here keeps the two
     * paths returning the same set rather than making this one subtly cleverer.
     */
    readonly property var rows: {
        var src = dialog.all || []
        var q = dialog.query.trim().toLowerCase()
        if (q === "")
            return src

        var out = []
        for (var i = 0; i < src.length; i++) {
            var row = src[i]
            if (String(row.name).toLowerCase().indexOf(q) >= 0
                    || (row.barcode !== ""
                        && String(row.barcode).toLowerCase().indexOf(q) >= 0))
                out.push(row)
        }
        return out
    }

    onQueryChanged: {
        dialog.selected = 0
        list.positionViewAtBeginning()
    }

    /* Add and close. One tap, one product, one outcome — the dropdown under the
       till's own search field is the tool for adding three things in a row.

       Out of stock is reported rather than refused, the same rule the tile wall
       follows: the row stays tappable precisely so the sentence has somewhere to be
       said. */
    function take(index) {
        var list_ = dialog.rows
        if (index < 0 || index >= list_.length)
            return
        var row = list_[index]
        if (row.stock <= 0) {
            error.text = row.name + " — "
                       + Strings.t("pos.tile.out_of_stock", "Out of stock")
            return
        }
        if (dialog.till)
            dialog.till.add(row.id)
        dialog.close()
    }

    /* Enter. Narrowed to one row, that row is obviously what was meant — pos does
       the same, and it is what makes the dialog usable without the mouse. */
    function submit() {
        if (dialog.rows.length === 1)
            dialog.take(0)
        else
            dialog.take(dialog.selected)
    }

    function step(delta) {
        var n = dialog.rows.length
        if (n === 0)
            return
        var next = dialog.selected + delta
        dialog.selected = next < 0 ? 0 : (next > n - 1 ? n - 1 : next)
        list.positionViewAtIndex(dialog.selected, ListView.Contain)
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        QC.TextField {
            id: field
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.size.control
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.bodyLarge
            placeholderText: Strings.t("products.search.ph",
                                       "Search by name or barcode")
            onTextChanged: dialog.query = text
            onAccepted: dialog.submit()

            /* The arrows move the selection while the field keeps focus, so the
               whole dialog is one text field as far as the hands are concerned. */
            Keys.onDownPressed: dialog.step(1)
            Keys.onUpPressed: dialog.step(-1)
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_PageDown) {
                    dialog.step(10)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    dialog.step(-10)
                    event.accepted = true
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 360
            color: Fluent.cardBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: Tokens.spacing.xs
                clip: true
                model: dialog.rows
                boundsBehavior: Flickable.StopAtBounds
                /* A few rows either side of the viewport, so arrowing through a long
                   list does not build a delegate on every key. */
                cacheBuffer: 4 * Tokens.size.tableRow

                QC.ScrollBar.vertical: FluentScrollBar { }

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index

                    width: list.width
                    height: Tokens.size.tableRow
                    radius: Tokens.radius.sm
                    color: dialog.selected === row.index ? Tokens.brandTint
                         : rowHover.hovered ? Fluent.subtleSecondary : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.sm

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                text: row.modelData.name
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                color: row.modelData.stock > 0 ? Fluent.textPrimary
                                                               : Fluent.textTertiary
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                horizontalAlignment: Text.AlignLeft
                                /* The barcode first, because it is why a partial
                                   code finds anything and the operator may be
                                   checking which one matched. The category second,
                                   because two products often share a name. */
                                text: {
                                    var parts = []
                                    if (row.modelData.barcode !== "")
                                        parts.push("\u200e" + row.modelData.barcode)
                                    if (row.modelData.category !== "")
                                        parts.push(row.modelData.category)
                                    return parts.join("  ·  ")
                                }
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.overline
                                color: Fluent.textTertiary
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        Tag {
                            Layout.alignment: Qt.AlignVCenter
                            visible: row.modelData.hidden === true
                            label: Strings.t("products.hidden_on_pos",
                                             "Hidden on the till")
                            tone: "warning"
                        }

                        Tag {
                            Layout.alignment: Qt.AlignVCenter
                            visible: row.modelData.stock <= 0
                            label: Strings.t("pos.tile.out_of_stock", "Out of stock")
                            tone: "danger"
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.minimumWidth: 90
                            horizontalAlignment: Text.AlignRight
                            text: "\u200e" + row.modelData.stock_text
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textSecondary
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.minimumWidth: 130
                            horizontalAlignment: Text.AlignRight
                            text: "\u200e" + row.modelData.price_text
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.bodyLarge
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                        }
                    }

                    HoverHandler { id: rowHover }

                    TapHandler {
                        onTapped: {
                            dialog.selected = row.index
                            dialog.take(row.index)
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: dialog.rows.length === 0
                variant: "empty"
                title: dialog.query !== ""
                       ? Strings.t("state.no_results.title", "No matches")
                       : Strings.t("state.empty.title", "Nothing here yet")
                body: dialog.query !== ""
                      ? Strings.t("state.no_results.body",
                                  "Try fewer letters, or part of the barcode.")
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

            /* The count, because "everything" is a claim worth backing with a
               number — and because "12 of 2,999" tells the operator whether to
               refine the query or start scrolling. */
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: dialog.query === ""
                      ? "\u200e" + dialog.rows.length
                      : "\u200e" + dialog.rows.length + " / " + (dialog.all || []).length
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textSecondary
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

    /* Same pill as the till's search dropdown, for the same two facts. There is no
       Badge component in Mizan to borrow, and PosPage builds its own the same way —
       Tokens.toneFill outside, Tokens.toneInk on the text. */
    component Tag: Rectangle {
        property string label: ""
        property string tone: "warning"

        implicitWidth: tagText.implicitWidth + Tokens.spacing.sm
        implicitHeight: tagText.implicitHeight + Tokens.spacing.xs
        radius: Tokens.radius.pill
        color: Tokens.toneFill(tone)

        Text {
            id: tagText
            anchors.centerIn: parent
            text: parent.label
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.weight: Font.DemiBold
            color: Tokens.toneInk(parent.tone)
        }
    }
}
