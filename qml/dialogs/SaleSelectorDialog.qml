import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Find a sale. Ported from pos/app/dialogs/selectors.py::SaleSelectorDialog,
 * which the till opens on F1 to start a return.
 *
 * What happens after the pick depends on why it was opened: `purpose: "return"`
 * goes straight to the return dialog, anything else opens the sale. The till asks
 * for the first; the shell could ask for the second without this dialog changing.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.sales : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null
    readonly property string purpose: context && context.purpose ? context.purpose : ""
    readonly property int measure: 820
    readonly property int listHeight: 380

    preferredWidth: 1100
    title: purpose === "return"
           ? Strings.t("return.select_sale", "Select a sale to return")
           : Strings.t("sales.title", "Sales")

    property int selected: -1

    Component.onCompleted: {
        if (ctrl)
            ctrl.load("", "", 1, 100, "", "")
        search.forceActiveFocus()
    }

    function choose(index) {
        var row = ctrl ? ctrl.rowAt(index) : null
        if (!row)
            return
        if (workflows)
            workflows.open(purpose === "return" ? "return_create" : "sale_transaction",
                           { sale_id: row.id })
        dialog.close()
    }

    function submit() {
        if (ctrl && ctrl.rows.length === 1)
            choose(0)
        else
            choose(selected)
    }

    component Cell: Text {
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.body
        color: Fluent.textPrimary
        elide: Text.ElideRight
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        QC.TextField {
            id: search
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            Layout.preferredHeight: Tokens.size.control
            placeholderText: Strings.t("sales.search.ph", "Search number or customer")
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body

            onTextChanged: {
                dialog.selected = -1
                if (dialog.ctrl)
                    dialog.ctrl.load(text, "", 1, 100, "", "")
            }
            onAccepted: dialog.submit()
        }

        Rectangle {
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
                model: dialog.ctrl ? dialog.ctrl.rows : null

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
                    TapHandler {
                        onTapped: dialog.selected = row.index
                        onDoubleTapped: dialog.choose(row.index)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.md

                        Cell {
                            Layout.preferredWidth: 160
                            text: "\u200e" + row.modelData.number
                            font.weight: Font.DemiBold
                        }

                        Cell {
                            Layout.preferredWidth: 200
                            text: "\u200e" + row.modelData.when
                            color: Fluent.textSecondary
                        }

                        Cell {
                            Layout.fillWidth: true
                            text: row.modelData.customer
                        }

                        Cell {
                            Layout.preferredWidth: 120
                            text: row.modelData.payment
                            color: Fluent.textSecondary
                        }

                        Cell {
                            Layout.preferredWidth: 160
                            text: "\u200e" + row.modelData.total
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: list.count === 0
                variant: search.text !== "" ? "no_results" : "empty"
            }
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
                glyph: "ic_fluent_checkmark_20_regular"
                text: Strings.t("select_customer.select", "Select")
                highlighted: true
                enabled: dialog.selected >= 0
                         || (dialog.ctrl && dialog.ctrl.rows.length === 1)
                onClicked: dialog.submit()
            }
        }
    }
}
