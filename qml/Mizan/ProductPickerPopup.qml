import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The select-product popup: the shared table, over whatever screen is asking.
 *
 *   ┌ All products                                     ✕ ┐
 *   │ [ search by name or barcode ....... ] [ All cats ▾ ] │
 *   │ NAME         BARCODE        STOCK      SALE PRICE    │
 *   │ …                                                    │
 *   │ 1–100 of 2,999     ‹‹ ‹ Page 1 of 30 › ››  100 / page │
 *   └──────────────────────────────────────────────────────┘
 *
 * A popup and not a workflow dialog, for the same reason ProductFinder's browse
 * list was: a picker is part of whatever screen is asking — a delivery, a
 * stocktake, a movement ledger, a multi-unit form — and it answers by handing a
 * product back rather than by emitting into the router. That is the
 * PaymentEntry / LineEntry shape: the shell owns the frame, `ProductPicker`
 * owns the table, and the caller owns the data and the answer.
 *
 * WHY THIS FILE EXISTS AT ALL
 *
 * Every one of those screens used to answer "which product?" with a list of its
 * own — a browse popup here, an eight-row name-only list there — and no two
 * agreed on what a row showed. There is one select-product surface now, and
 * this is how a screen that is not the till's own dialog opens it.
 */
QC.Popup {
    id: popup

    // =====================================================================
    // API
    // =====================================================================
    property string heading: Strings.t("selector.all_products", "All products")

    /* The caller's catalogue, loaded before `open()` — the same
       `stock.catalogue()` / `till.catalogue()` list the till's own picker
       dialog reads. */
    property var catalogue: []

    /* The till's rule, forwarded for a caller that sells rather than records.
       See ProductPicker for what it means. */
    property bool requireStock: false

    signal picked(var product)

    // =====================================================================
    // FRAME
    // =====================================================================
    parent: QC.Overlay.overlay
    anchors.centerIn: QC.Overlay.overlay
    /* Measured against the overlay it is parented to: the attached `Window`
       property only works on Items, and a Popup is not one. */
    width: Math.min(1040, (parent ? parent.width : 1100) - 2 * Tokens.spacing.xxl)
    height: Math.min(720, (parent ? parent.height : 800) - 2 * Tokens.spacing.xxl)
    padding: Tokens.spacing.md
    modal: true
    focus: true

    background: Rectangle {
        color: Fluent.popupBackground
        radius: Tokens.radius.lg
        border.width: 1
        border.color: Fluent.dividerBorder
    }

    onOpened: {
        body.reset()
        body.focusSearch()
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.sm

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Text {
                Layout.fillWidth: true
                text: popup.heading
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.subtitle
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }

            IconButton {
                glyph: "ic_fluent_dismiss_20_regular"
                glyphSize: Tokens.icon.sm
                tooltip: Strings.t("action.close", "Close")
                onClicked: popup.close()
            }
        }

        ProductPicker {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            catalogue: popup.catalogue
            requireStock: popup.requireStock

            /* Closed before the answer travels, so a caller that puts focus
               back on its own search field — which is every caller — is not
               fighting the popup's closing grab for it. */
            onPicked: (product) => {
                popup.close()
                popup.picked(product)
            }
        }
    }
}
