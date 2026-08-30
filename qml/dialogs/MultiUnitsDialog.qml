import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Multi-units — the second way a product is sold. Ported from pos's multi-unit
 * management.
 *
 *   Coca-Cola 1.5L
 *     Pack of 6      × 6    550,00    6133273409991
 *     Case of 24     × 24  2 100,00   6133273409992
 *
 * This is not labelling. The till's barcode lookup returns a multi-unit hit with
 * its base quantity, so scanning the case's barcode adds twenty-four units at the
 * case's own price — one scan, one line, the right stock movement. That is why a
 * multi-unit needs a barcode of its own to be worth having.
 *
 * Opened from a product it lists that product's units; opened from the catalogue it
 * lists all of them and asks which product a new one belongs to.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property var catalogueProducts: (typeof app !== "undefined" && app)
                                             ? app.products : null

    readonly property int productId: context && context.product_id
                                     ? context.product_id : 0
    readonly property int measure: 820
    readonly property int listHeight: 320

    preferredWidth: 1120
    title: Strings.t("product.multi_units", "Multi-units")

    property var rows: []
    property int selected: -1
    readonly property var current: selected >= 0 && selected < rows.length
                                  ? rows[selected] : null

    /* Which product a new unit belongs to: the one this was opened for, or the one
       picked below. */
    property int targetProduct: productId
    property string targetName: ""

    Component.onCompleted: {
        reload()
        if (productId)
            name.forceActiveFocus()
    }

    function reload() {
        rows = ctrl ? ctrl.multiUnits(productId) : []
        if (selected >= rows.length)
            selected = -1
        fill()
    }

    function fill() {
        name.text = current ? current.name : ""
        qty.text = current ? String(current.base_qty) : ""
        price.text = current ? String(current.price) : ""
        barcode.text = current ? current.barcode : ""
        if (current) {
            targetProduct = current.product_id
            targetName = current.product
        }
    }

    onSelectedChanged: fill()

    function save() {
        error.text = ""
        if (!ctrl)
            return
        if (!targetProduct) {
            error.text = Strings.t("mu.product.required",
                                   "Choose the product this unit belongs to.")
            return
        }
        ctrl.saveMultiUnit({
            product_id: targetProduct,
            name: name.text,
            base_qty: qty.text,
            price: price.text,
            barcode: barcode.text
        }, current ? current.id : 0)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onChanged() { dialog.reload() }
        function onRejected(message) { error.text = message }
    }

    /* The same eight-match popup the purchase form uses, for the same reason:
       three thousand products do not go in a dropdown. */
    QC.Popup {
        id: picker
        width: 520
        height: 340
        modal: true
        focus: true
        anchors.centerIn: QC.Overlay.overlay

        background: Rectangle {
            color: Fluent.popupBackground
            border.color: Fluent.flyoutBorder
            border.width: 1
            radius: Tokens.radius.md
        }

        onOpened: query.forceActiveFocus()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacing.md
            spacing: Tokens.spacing.sm

            QC.TextField {
                id: query
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("products.search.ph",
                                           "Search name or barcode")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onTextChanged: if (dialog.catalogueProducts)
                                   dialog.catalogueProducts.load(text, 1, 8, 0)
            }

            ListView {
                id: matches
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: dialog.catalogueProducts ? dialog.catalogueProducts.rows : null

                QC.ScrollBar.vertical: FluentScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                }

                delegate: Rectangle {
                    id: hit
                    required property var modelData

                    width: matches.width
                    height: Tokens.size.control
                    color: hover.hovered ? Fluent.subtleSecondary : "transparent"

                    HoverHandler { id: hover }
                    TapHandler {
                        onTapped: {
                            dialog.targetProduct = hit.modelData.id
                            dialog.targetName = hit.modelData.name
                            picker.close()
                        }
                    }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.sm
                        anchors.rightMargin: Tokens.spacing.sm
                        verticalAlignment: Text.AlignVCenter
                        text: hit.modelData.name
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        color: Fluent.textPrimary
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Rectangle {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            Layout.preferredHeight: dialog.listHeight
            color: Fluent.cardBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: dialog.rows

                QC.ScrollBar.vertical: FluentScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    width: list.width
                    height: Tokens.size.tableRow
                    color: index === dialog.selected ? Tokens.brandTint
                         : hover.hovered ? Fluent.subtleSecondary : "transparent"

                    HoverHandler { id: hover }
                    TapHandler { onTapped: dialog.selected = row.index }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.xs
                        spacing: Tokens.spacing.md

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                font.weight: Font.DemiBold
                                color: Fluent.textPrimary
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: dialog.productId === 0
                                text: row.modelData.product
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.caption
                                color: Fluent.textSecondary
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.preferredWidth: 110
                            text: "\u200e× " + row.modelData.qty_text
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textSecondary
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            Layout.preferredWidth: 160
                            text: "\u200e" + row.modelData.price_text
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            Layout.preferredWidth: 220
                            text: "\u200e" + row.modelData.barcode
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: row.modelData.barcode === "" ? Tokens.warning
                                                                : Fluent.textSecondary
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                        }

                        IconButton {
                            glyph: "ic_fluent_delete_20_regular"
                            glyphSize: Tokens.icon.sm
                            glyphColor: Tokens.danger
                            tooltip: Strings.t("action.delete", "Delete")
                            onClicked: if (dialog.ctrl)
                                           dialog.ctrl.deleteMultiUnit(row.modelData.id)
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: list.count === 0
                variant: "empty"
                title: Strings.t("mu.empty.title", "No multi-units")
                body: Strings.t("mu.empty.body",
                                "Add one for a pack or a case that has its own barcode.")
            }
        }

        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            visible: dialog.productId === 0
            spacing: Tokens.spacing.sm

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: Strings.t("mu.product", "Product")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            Text {
                Layout.fillWidth: true
                text: dialog.targetName !== ""
                      ? dialog.targetName
                      : Strings.t("mu.product.required",
                                  "Choose the product this unit belongs to.")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: dialog.targetName !== "" ? Fluent.textPrimary
                                                : Fluent.textTertiary
                elide: Text.ElideRight
            }

            GlyphButton {
                glyph: "ic_fluent_search_20_regular"
                text: Strings.t("selector.open_picker", "Find a product")
                onClicked: picker.open()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            QC.TextField {
                id: name
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("mu.name", "Unit name (pack of 6)")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }

            QC.TextField {
                id: qty
                Layout.preferredWidth: 120
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("mu.qty", "× qty")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                horizontalAlignment: TextInput.AlignHCenter
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }

            QC.TextField {
                id: price
                Layout.preferredWidth: 160
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("mu.price", "Price")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                horizontalAlignment: TextInput.AlignRight
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }

            QC.TextField {
                id: barcode
                Layout.preferredWidth: 220
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("mu.barcode", "Barcode")
                horizontalAlignment: TextInput.AlignLeft
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }

            GlyphButton {
                glyph: "ic_fluent_save_20_regular"
                text: dialog.current ? Strings.t("action.save", "Save")
                                     : Strings.t("product.add_multi_unit", "Add")
                enabled: name.text.trim() !== "" && qty.text !== ""
                onClicked: dialog.save()
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
                visible: dialog.selected >= 0
                text: Strings.t("mu.new", "New multi-unit")
                onClicked: dialog.selected = -1
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
