import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One multi-unit: the pack or the case, with its own barcode and its own price.
 *
 *     ┌ Add multi-unit ─────────────────────────┐
 *     │ Product      Coca-Cola 1.5L   [ Find ]  │
 *     │ Unit name *                             │
 *     │ [ Pack of 6                          ]  │
 *     │ Units inside *        Price             │
 *     │ [ 6            ]      [ 550.00       ]  │
 *     │ Barcode                                 │
 *     │ [ 6133273409991                      ]  │
 *     │                        Cancel    Save   │
 *     └─────────────────────────────────────────┘
 *
 * WHY IT LEFT THE LIST
 *
 * Four fields and a product picker were a single row under the list, and that row
 * was both the add form and the editor of whichever line was selected. A pack of 6
 * added while the case of 24 happened to be selected overwrote the case — including
 * its barcode, which is what the till scans.
 *
 * The barcode is optional in the form and pointless in practice: the till's lookup
 * is what makes a multi-unit worth having, so the list marks the ones without it.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property var catalogueProducts: (typeof app !== "undefined" && app)
                                             ? app.products : null

    /* Set by the host when this was opened from one product's record: the product
       is then not a question. */
    property int lockedProduct: 0

    /* The multi-unit being edited. 0 adds one. */
    property int unitId: 0

    property int targetProduct: 0
    property string targetName: ""

    readonly property bool creating: unitId === 0
    readonly property int measure: 520

    preferredWidth: 680

    title: creating ? Strings.t("mu.add_title", "Add multi-unit")
                    : Strings.t("mu.edit_title", "Edit multi-unit")

    signal committed()

    component Field: ColumnLayout {
        id: field
        property string label: ""

        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: field.label
            elide: Text.ElideRight
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Fluent.textSecondary
        }
    }

    function edit(row) {
        unitId = row && row.id ? row.id : 0
        name.text = row && row.name ? row.name : ""
        qty.text = row ? String(row.base_qty) : ""
        price.text = row ? String(row.price) : ""
        barcode.text = row && row.barcode ? row.barcode : ""
        targetProduct = row && row.product_id ? row.product_id : lockedProduct
        targetName = row && row.product ? row.product : ""
        error.text = ""
        open()
        name.forceActiveFocus()
        name.selectAll()
    }

    Component.onCompleted: {
        if (context && context.product_id)
            lockedProduct = context.product_id
        targetProduct = lockedProduct
        name.forceActiveFocus()
    }

    function save() {
        error.text = ""
        if (!ctrl)
            return
        if (!targetProduct) {
            error.text = Strings.t("mu.product.required",
                                   "Choose the product this unit belongs to.")
            return
        }
        if (name.text.trim() === "") {
            error.text = Strings.t("mu.name.required", "Give the unit a name.")
            name.forceActiveFocus()
            return
        }
        ctrl.saveMultiUnit({
            product_id: targetProduct,
            name: name.text,
            base_qty: qty.text,
            price: price.text,
            barcode: barcode.text
        }, unitId)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onChanged() {
            if (!dialog.visible)
                return
            dialog.committed()
            dialog.close()
        }

        function onRejected(message) {
            if (dialog.visible)
                error.text = message
        }
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

        // -- which product this belongs to
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            visible: dialog.lockedProduct === 0
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

        Field {
            Layout.preferredWidth: dialog.measure
            label: Strings.t("mu.name", "Unit name (pack of 6)") + " *"

            QC.TextField {
                id: name
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                onAccepted: dialog.save()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Field {
                label: Strings.t("mu.qty", "Units inside") + " *"

                NumberField {
                    id: qty
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    horizontalAlignment: TextInput.AlignHCenter
                    onAccepted: dialog.save()
                }
            }

            Field {
                label: Strings.t("mu.price", "Price")

                NumberField {
                    id: price
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    onAccepted: dialog.save()
                }
            }
        }

        Field {
            Layout.preferredWidth: dialog.measure
            label: Strings.t("mu.barcode", "Barcode")

            QC.TextField {
                id: barcode
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                horizontalAlignment: TextInput.AlignLeft
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            visible: barcode.text.trim() === ""
            text: Strings.t("mu.barcode.hint",
                            "Without a barcode of its own, the till cannot scan this unit.")
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.warning
        }

        Text {
            id: error
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.danger
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_save_20_regular"
                text: Strings.t("action.save", "Save")
                highlighted: true
                enabled: name.text.trim() !== "" && qty.text !== ""
                onClicked: dialog.save()
            }
        }
    }
}
