import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * A scan that matched nothing. Ported from
 * pos/app/dialogs/pos_dialogs.py::UnknownBarcodeDialog.
 *
 * The code is shown on its own line, selectable and forced left-to-right, because
 * the next thing that happens is somebody reading it back off the packaging — and
 * a barcode reversed by an Arabic paragraph is unreadable for exactly that.
 *
 * Two ways out, both real: try again (the scanner may have misread) or create the
 * product now, with the code already filled in. pos offers the same pair and puts
 * "search again" first, because a misread is the common case.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null
    readonly property string code: context && context.code ? context.code : ""
    readonly property int measure: 520

    preferredWidth: 660
    title: Strings.t("unknown.title", "Unknown barcode")

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Text {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            text: Strings.tf("unknown.body",
                             "The scanned code \"{code}\" does not match any item in the inventory.",
                             { code: dialog.code })
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textPrimary
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Tokens.size.control
            radius: Tokens.radius.sm
            color: Fluent.subtleSecondary
            border.width: 1
            border.color: Fluent.dividerBorder

            QC.TextField {
                anchors.fill: parent
                anchors.margins: 1
                readOnly: true
                selectByMouse: true
                background: null
                /* The code exactly as it arrived, left to right. */
                text: "\u200e" + dialog.code
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                horizontalAlignment: TextInput.AlignHCenter
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_add_20_regular"
                text: Strings.t("unknown.add_product", "Add new product")
                onClicked: {
                    /* Hands over to the quick-add form and closes: the question this
                       dialog asks is answered, so it is not a layer to come back to.
                       DialogHost stacks by default — a dialog that means to replace
                       its opener says so, like this. */
                    if (dialog.workflows)
                        dialog.workflows.open("quick_add_product",
                                              { code: dialog.code })
                    dialog.close()
                }
            }

            GlyphButton {
                glyph: "ic_fluent_search_20_regular"
                text: Strings.t("unknown.search_again", "Search again")
                highlighted: true
                onClicked: dialog.close()
            }
        }
    }
}
