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
 *   │ │ CUSTOMER              PHONE               DEBT │ │
 *   │ │ Amine Bekkar          0661 20 41 88   4 500,00 │ │
 *   │ │ Walid Kaci            0770 11 22 33        —   │ │
 *   │ └────────────────────────────────────────────────┘ │
 *   │ ＋ New customer                    [Cancel][Select]│
 *   └────────────────────────────────────────────────────┘
 *
 * NEW CUSTOMER: THE REAL FORM, NOT TWO FIELDS
 *
 * This grew a name box and a phone box of its own along the bottom, on the theory
 * that a second window is friction a cashier holding up a queue does not need. The
 * friction was not the problem with it — the two fields were.
 *
 * A customer record carries a PRICE LEVEL and a CREDIT LIMIT, and both of them are
 * read by the till, for this sale, in the next few seconds: the level picks which of
 * the three counters the cart is priced from, and the limit is what refuses a sale on
 * account. A pair of boxes that can only capture a name and a phone silently creates
 * every new customer as retail with no ceiling — so the wholesaler who has just been
 * added is rung up at shelf prices on the very ticket they are standing there for,
 * and nothing on screen says so. Filling it in "later on the record" means noticing
 * later, which is after the money has changed hands.
 *
 * So the button opens `customer_edit` — the same form the Customers page opens, with
 * the same fields and the same Save — seeded with whatever is in the search box, and
 * DialogHost stacks it over this picker rather than replacing it. The saved customer
 * comes back through the controller and is attached to the cart exactly as before, so
 * the one thing the inline pair was right about — created and attached in one step —
 * is kept.
 *
 * DEBT IS THE POINT OF THE LIST
 *
 * The debt column is why this dialog is wide: a customer who already owes money
 * changes what the operator does next. It is inked with the danger tone when
 * there is any, and shows an em dash when there is none, so a clean account reads
 * as clean rather than as zero.
 *
 * Which is also why it is now named. A money figure on the right of a row is a
 * balance, a total, a credit limit or a last payment depending on the list it is
 * in, and this one is the reason the operator might refuse the sale — too much to
 * leave to the colour it is printed in. pos headed all three columns
 * (pos_dialogs.py:194); the port kept the columns and dropped the labels.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.customers : null
    readonly property var till: (typeof app !== "undefined" && app) ? app.pos : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    readonly property int measure: 760
    readonly property int listHeight: 360

    /* Column widths, in one place: the heading band and every row measure the
       same three columns, and a heading a few pixels out of step with the figures
       under it is worse than no heading. pos's widths, near enough
       (pos_dialogs.py:177-181). */
    readonly property int colPhone: 180
    readonly property int colDebt:  150

    modal: true
    /* Escape closes a picker. FluentDialog defaults to NoAutoClose, which is
       right for a confirmation and wrong for a search. */
    closePolicy: QC.Popup.CloseOnEscape
    preferredWidth: 1000
    title: Strings.t("select_customer.title", "Select customer")

    /* True from the moment the form is asked for until the customer it makes comes
       back. `saved` is emitted for every customer written anywhere in the app, so
       without this the picker would attach — and close over — an edit made on the
       record screen underneath it. */
    property bool awaitingNew: false
    property int selected: -1

    Component.onCompleted: {
        if (ctrl)
            ctrl.search("")
        search.forceActiveFocus()
    }

    /*
     * Who the answer goes to.
     *
     * The counter's use is "put this customer on the cart", so by default choosing
     * attaches it to the till. A filter's use is "tell me which customer" — it has no
     * cart to touch, and attaching one would change the sale being rung up while the
     * operator was only narrowing a list. So the record is always reported and the
     * attaching is opt-out.
     */
    property bool attach: true
    signal picked(var customer)

    function choose(index) {
        var rows = ctrl ? ctrl.rows : []
        if (index < 0 || index >= rows.length)
            return
        if (attach && till)
            till.setCustomer(rows[index].id)
        dialog.picked(rows[index])
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

    /*
     * The real form, over this picker, with the name already in it.
     *
     * `customer_edit` is the key the Customers page uses for the same act, so there
     * is one new-customer form in the app rather than two that drift. The router
     * checks `customers.manage` on it, which is the right gate: a cashier who may
     * read the list but not add to it gets the refusal instead of a form whose Save
     * would fail.
     */
    function addCustomer() {
        if (!workflows) {
            error.text = Strings.t("workflow.not_ready",
                                   "That screen is not part of this build yet.")
            return
        }
        error.text = ""
        dialog.awaitingNew = true
        workflows.open("customer_edit", { name: search.text })
    }

    /* Created and attached in one step: the operator opened this to put a name on
       the sale, not to file a customer record. A filter's picker has nothing to
       attach to and is only told who it is. */
    function attachNew(customer) {
        if (!dialog.awaitingNew || !customer)
            return
        dialog.awaitingNew = false
        if (dialog.attach && dialog.till)
            dialog.till.setCustomer(customer.id)
        dialog.picked(customer)
        dialog.close()
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        /* Two signals, one outcome. `saved` is what the form emits — a new customer
           is a save with no id — and `created` is the older quick-add path, kept
           wired so a caller that still uses it lands in the same place. Both are
           filtered by `awaitingNew`: see attachNew. */
        function onSaved(customer) { dialog.attachNew(customer) }
        function onCreated(customer) { dialog.attachNew(customer) }

        function onRejected(message) {
            /* The form draws its own refusals; this one would be behind it. */
            if (!dialog.awaitingNew)
                error.text = message
        }
    }

    /* The heading band's type, which is DataTable's: 13px caps, letter-spaced,
       secondary ink. Same component as SavedCartsDialog's, for the same reason —
       a hand-rolled list that looks like a table should read like one. */
    component Heading: Text {
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.overline
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
        color: Fluent.textSecondary
        elide: Text.ElideRight
        maximumLineCount: 1
        verticalAlignment: Text.AlignVCenter
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

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                /*
                 * DataTable's metrics, not invented ones — 48px, the subtle fill,
                 * 13px caps, the divider underneath — because this list is the same
                 * furniture as the tables on the pages. It cannot BE a DataTable:
                 * the rows select on a single tap and open on a double, which is a
                 * picker's contract rather than a grid's.
                 *
                 * The headings are labels and not buttons. The rows arrive in the
                 * controller's order for the search that produced them, and there is
                 * nothing here to sort by that a search box does not answer better.
                 */
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.tableHeader
                    color: Fluent.subtleSecondary

                    /* Square corners inside a 10px-radius card show as two nubs at
                       the top edge, because a rounded Rectangle clips to its
                       bounding box and not to its corner arcs. Per-corner radii are
                       the exact fix and Qt has had them since 6.7 (this runs 6.9.3).
                       Both corners take the same value, so mirroring has nothing to
                       do here. */
                    topLeftRadius: Tokens.radius.md - 1
                    topRightRadius: Tokens.radius.md - 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.md

                        /* `pos.customer`, not pos's own `qcustomer.name`: over there
                           the header borrowed a form field's label and came out as
                           "Customer Name" beside "Phone" and "Debt". The catalogue
                           has the shorter word, translated, and every other table in
                           this app heads the column with it. */
                        Heading {
                            Layout.fillWidth: true
                            text: Strings.t("pos.customer", "Customer")
                        }

                        Heading {
                            Layout.preferredWidth: dialog.colPhone
                            text: Strings.t("qcustomer.phone", "Phone")
                        }

                        /* Right-aligned over right-aligned values: a heading belongs
                           on the edge its column's digits sit on. */
                        Heading {
                            Layout.preferredWidth: dialog.colDebt
                            horizontalAlignment: Text.AlignRight
                            text: Strings.t("select_customer.col.debt", "Debt")
                        }
                    }

                    // On top of the fill, so the line reads as the boundary between
                    // heading and data rather than the bar's own edge.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Fluent.divider
                    }
                }

                /*
                 * The rows and the empty message share one box under the heading,
                 * which is why there is an Item around them: an anchor reaches a
                 * parent or a sibling and nothing else, so a StateView outside this
                 * wrapper could not be pinned to the list, and a second fillHeight
                 * child of the ColumnLayout would be handed half the height instead
                 * of lying over the rows.
                 */
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: list
                        anchors.fill: parent
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
                                    Layout.preferredWidth: dialog.colPhone
                                    /* A phone number is an LTR island in an Arabic
                                       row. */
                                    text: "\u200e" + row.modelData.phone
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.body
                                    color: Fluent.textSecondary
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignLeft
                                }

                                Text {
                                    Layout.preferredWidth: dialog.colDebt
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

                    /* Over the rows only. The headings stay up with nothing under
                       them — they say what the list would hold, and DataTable leaves
                       its own header standing on an empty table for the same
                       reason. */
                    StateView {
                        anchors.fill: parent
                        visible: list.count === 0
                        variant: search.text !== "" ? "no_results" : "empty"
                        /* It said "Quick Add Customer" here, which named a button
                           rather than the state: an operator reading it was being
                           told what to do next by a heading with no verb in it, and
                           the button is now below anyway. The state says what is
                           true, and carries the act as an act. */
                        title: search.text !== ""
                               ? Strings.t("state.no_results.title", "No matches")
                               : Strings.t("state.empty.title", "Nothing here yet")
                        /* `selector.no_match` is about products ("No product matches …"),
                           which is what this said until now — the wrong sentence, and
                           read through `t()` so its {text} slot showed up literally on
                           screen. This names what was typed, in the picker's own
                           words. */
                        body: search.text !== ""
                              ? Strings.tf("select_customer.no_match",
                                           "No customer matches \u201c{text}\u201d.",
                                           { text: search.text })
                              : ""
                        /* Create-on-empty, which is what a picker that found nobody
                           is for — and the same form the footer opens, seeded with
                           the same search text. */
                        actionText: Strings.t("customers.add", "New customer")
                        onActionRequested: dialog.addCustomer()
                    }
                }
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
                glyph: "ic_fluent_person_add_20_regular"
                /* The Customers page's own wording for the same act, because it
                   opens the same form. "Quick Add Customer" was the name of the two
                   fields that used to be here, and there is nothing quick about it
                   any more — there is one way to add a customer. */
                text: Strings.t("customers.add", "New customer")
                onClicked: dialog.addCustomer()
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
