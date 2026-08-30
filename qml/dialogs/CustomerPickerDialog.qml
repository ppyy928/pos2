import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Who is this sale for. Ported from
 * pos/app/dialogs/pos_dialogs.py::CustomerSelectionDialog.
 *
 *   ┌────────────────────────────────────────────────────┐
 *   │ Select customer                                    │
 *   │ [ 🔍 Search name or phone                        ] │
 *   │ ┌────────────────────────────────────────────────┐ │
 *   │ │ Amine Bekkar          0661 20 41 88   4 500,00 │ │
 *   │ │ Walid Kaci            0770 11 22 33        —   │ │
 *   │ └────────────────────────────────────────────────┘ │
 *   │ ＋ New customer                    [Cancel][Select]│
 *   └────────────────────────────────────────────────────┘
 *
 * ONE DIALOG, NOT TWO
 *
 * pos opens a second dialog to add a customer who is standing at the counter.
 * Here the same dialog grows two fields, because the second dialog only ever
 * existed to hold them — and a cashier who has just searched for a name should
 * not have to retype it into a new window. The name typed in the search box seeds
 * the new-customer field for that reason.
 *
 * DEBT IS THE POINT OF THE LIST
 *
 * The debt column is why this dialog is wide: a customer who already owes money
 * changes what the operator does next. It is inked with the danger tone when
 * there is any, and shows an em dash when there is none, so a clean account reads
 * as clean rather than as zero.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.customers : null
    readonly property var till: (typeof app !== "undefined" && app) ? app.pos : null

    readonly property int measure: 760
    readonly property int listHeight: 360

    modal: true
    /* Escape closes a picker. FluentDialog defaults to NoAutoClose, which is
       right for a confirmation and wrong for a search. */
    closePolicy: QC.Popup.CloseOnEscape
    preferredWidth: 1000
    title: Strings.t("select_customer.title", "Select customer")

    property bool adding: false
    property int selected: -1

    Component.onCompleted: {
        if (ctrl)
            ctrl.search("")
        search.forceActiveFocus()
    }

    function choose(index) {
        var rows = ctrl ? ctrl.rows : []
        if (index < 0 || index >= rows.length)
            return
        if (till)
            till.setCustomer(rows[index].id)
        dialog.close()
    }

    function submit() {
        var rows = ctrl ? ctrl.rows : []
        /* Enter on a search that narrowed to one is the whole point of typing:
           pos does the same, and it is what makes the dialog keyboard-only. */
        if (rows.length === 1)
            choose(0)
        else
            choose(selected)
    }

    function saveNew() {
        if (ctrl)
            ctrl.quickAdd(newName.text, newPhone.text)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        /* Created and attached in one step: the operator opened this to put a
           name on the sale, not to file a customer record. */
        function onCreated(customer) {
            if (dialog.till)
                dialog.till.setCustomer(customer.id)
            dialog.close()
        }

        function onRejected(message) {
            error.text = message
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        QC.TextField {
            id: search
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            Layout.preferredHeight: Tokens.size.control
            placeholderText: Strings.t("select_customer.search.ph",
                                       "Search name or phone")
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body

            onTextChanged: {
                dialog.selected = -1
                if (dialog.ctrl)
                    dialog.ctrl.search(text)
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
                            Layout.preferredWidth: 180
                            /* A phone number is an LTR island in an Arabic row. */
                            text: "\u200e" + row.modelData.phone
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textSecondary
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                        }

                        Text {
                            Layout.preferredWidth: 150
                            text: row.modelData.debt > 0
                                  ? "\u200e" + row.modelData.debt_text : "—"
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: row.modelData.debt > 0 ? Tokens.danger
                                                          : Fluent.textTertiary
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: list.count === 0
                variant: search.text !== "" ? "no_results" : "empty"
                title: search.text !== ""
                       ? Strings.t("state.no_results.title", "No matches")
                       : Strings.t("qcustomer.title", "Quick Add Customer")
                body: search.text !== ""
                      ? Strings.t("selector.no_match", "Nothing matches that.")
                      : ""
            }
        }

        // -----------------------------------------------------------------
        // new customer, in place
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            visible: dialog.adding
            spacing: Tokens.spacing.sm

            QC.TextField {
                id: newName
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("qcustomer.name", "Customer name")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.saveNew()
            }

            QC.TextField {
                id: newPhone
                Layout.preferredWidth: 240
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("qcustomer.phone", "Phone")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                inputMethodHints: Qt.ImhDialableCharactersOnly
                onAccepted: dialog.saveNew()
            }

            GlyphButton {
                glyph: "ic_fluent_checkmark_20_regular"
                text: Strings.t("action.save", "Save")
                highlighted: true
                onClicked: dialog.saveNew()
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
                visible: !dialog.adding
                glyph: "ic_fluent_person_add_20_regular"
                text: Strings.t("qcustomer.title", "Quick Add Customer")
                onClicked: {
                    dialog.adding = true
                    /* The search box already holds what the operator typed —
                       almost always the name they are about to create. */
                    newName.text = search.text
                    newName.forceActiveFocus()
                }
            }

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
