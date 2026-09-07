import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Attach a party by typing: the field, and the searchable list that drops under it.
 *
 *   ┌────────────────────────────────────────────┐
 *   │ 👤  Walk-in         Select customer (F3) ⌄ │   the field (PartyCard)
 *   └────────────────────────────────────────────┘
 *   ┌────────────────────────────────────────────┐
 *   │ ┌────────────────────────────────────────┐ │   the sheet
 *   │ │ bek                                    │ │   search, focused on open
 *   │ └────────────────────────────────────────┘ │
 *   │   Amine Bekkar                    4 500,00 │   the items, filtered
 *   │   0661 20 41 88                            │
 *   │   Bekkar Frères                            │
 *   └────────────────────────────────────────────┘
 *
 * WHY A DROPDOWN AND NOT THE DIALOG IT REPLACES
 *
 * Attaching a customer is one field of the sale, and it was costing a full-screen
 * modal: the till dimmed, the cart went behind an overlay, a 1000px dialog opened
 * over the numpad, and the operator picked a name and dismissed it. Same for the
 * supplier on a delivery, where the picker covered the note it was being attached
 * to. A dropdown answers the question next to the question — the cart and the
 * total stay on screen and stay readable while the list is down — and it is the
 * control the rest of the world uses for "one of these, and I know its name".
 *
 * The dialog is still the right shape when picking a customer IS the task —
 * CustomerPickerDialog stays registered for that route, with its own table, its
 * debt column and its new-customer form. Adding somebody who is not in the list is
 * not that task, and it is not a row in this sheet either — a row under the list
 * reads as one more party to choose. On the till it is a button beside this field,
 * which opens the form directly; the sheet stays a list and nothing else.
 *
 * WHY THE SEARCH BOX IS INSIDE THE SHEET AND NOT THE FIELD
 *
 * The field has to keep saying who is attached. An editable one cannot: the moment it
 * holds a query it has stopped showing the answer, and a half-typed name over a cart
 * that is on account is a lie about the state of the sale. So the field displays, the
 * sheet searches, and the two never occupy the same pixels. That is also why this is
 * PartyCard plus a popup rather than an editable ComboBox, which it now looks like.
 *
 * WHO FILTERS
 *
 * By default this does, in JavaScript, over `rows`: the caller loads the list once
 * when `listRequested` fires and every keystroke after that is instant. Set
 * `remote: true` when the list is too large to hold or the match needs SQL — then
 * `queried` is emitted per keystroke and `rows` is displayed exactly as given.
 *
 * WHAT A ROW NEEDS
 *
 * `name` only. `phone`, `contact` and `wilaya` are drawn and searched when
 * present, and `debt` with `debt_text` is drawn when it is above zero — which is
 * the one figure that changes which name gets picked, on both sides of the shop.
 */
Item {
    id: select

    // =====================================================================
    // API — the card
    // =====================================================================
    property string glyph: "ic_fluent_person_20_regular"
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property string removeTip: ""

    // =====================================================================
    // API — the sheet
    // =====================================================================
    /* Everything that can be chosen. Plain objects, as the bridges already hand
       them over: [{ id, name, phone, debt, debt_text }, ...]. */
    property var rows: []

    property string placeholder: ""
    property string emptyText: ""

    /* Items visible before the sheet scrolls. Six, for ProductFinder's reason: a
       list that covers half the screen to answer a three-letter query is worse
       than one that scrolls. */
    property int visibleRows: 6

    /* Leave the filtering to the caller. See WHO FILTERS above. */
    property bool remote: false

    // =====================================================================
    // SIGNALS
    // =====================================================================
    /* One row was chosen. The caller attaches it — this component does not know
       whether that means a cart, a delivery or a filter. */
    signal picked(var party)
    signal removeRequested()
    /* The sheet is opening and wants its list. Emitted before it is shown, so a
       synchronous load lands in time for the sheet to be sized by it. */
    signal listRequested()
    /* The query changed. Only a `remote` caller has to answer it. */
    signal queried(string text)

    readonly property bool expanded: sheet.visible

    // =====================================================================
    // BEHAVIOUR
    // =====================================================================
    function open() {
        if (!select.enabled)
            return
        select.listRequested()
        sheet.open()
    }

    function close() { sheet.close() }

    function toggle() {
        if (sheet.visible)
            sheet.close()
        else
            select.open()
    }

    function choose(party) {
        if (!party)
            return
        select.picked(party)
        sheet.close()
    }

    /* Move the mark, and carry the view with it. ListView does not scroll to a
       currentIndex that was assigned rather than reached by its own key handling —
       the arrows are pressed in the search box, which is what holds focus — so the
       positioning is explicit. Wraps at both ends: a list being driven from a text
       field has no "past the last row" to fall off. */
    function step(delta) {
        var count = sheet.shown.length
        if (count === 0)
            return
        var next = list.currentIndex + delta
        if (next < 0)
            next = count - 1
        else if (next >= count)
            next = 0
        list.currentIndex = next
        list.positionViewAtIndex(next, ListView.Contain)
    }

    /* Searched over the same three fields the SQL behind `remote` searches, so a
       local list and a remote one answer the same query the same way. */
    function fits(party, needle) {
        if (!party)
            return false
        return String(party.name || "").toLowerCase().indexOf(needle) >= 0
                || String(party.phone || "").toLowerCase().indexOf(needle) >= 0
                || String(party.contact || "").toLowerCase().indexOf(needle) >= 0
                || String(party.wilaya || "").toLowerCase().indexOf(needle) >= 0
    }

    /* The second line of a row. A phone number is an LTR island: without the mark,
       "0661 20 41 88" is reordered by the bidi algorithm inside an Arabic row. */
    function detailOf(party) {
        if (!party)
            return ""
        var parts = []
        if (party.phone)
            parts.push("\u200e" + party.phone)
        if (party.contact)
            parts.push(party.contact)
        if (party.wilaya)
            parts.push(party.wilaya)
        return parts.join("  ·  ")
    }

    implicitHeight: card.implicitHeight

    // =====================================================================
    // THE CARD
    // =====================================================================
    PartyCard {
        id: card

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        dropdown: true
        expanded: sheet.visible

        glyph: select.glyph
        title: select.title
        subtitle: select.subtitle
        active: select.active
        removeTip: select.removeTip

        onClicked: select.toggle()
        onRemoveRequested: select.removeRequested()
    }

    // =====================================================================
    // THE SHEET
    // =====================================================================
    /*
     * Anchored under the card and exactly as wide as it, so it reads as the card
     * having opened rather than as a popup that happens to be nearby. Both callers
     * give the card 440px or more, which is what makes a name, a phone number and
     * a debt fit on one line — a narrower host would need a minimum width here,
     * and a minimum width wider than the card would hang off the screen edge on
     * the till, where the card is already against it.
     *
     * `CloseOnPressOutsideParent`, not `CloseOnPressOutside`: the card is the
     * parent, so pressing it does not close the sheet by policy — it reaches
     * `toggle()`, which does. With the plain policy the press would close and the
     * click would reopen, and the card would look dead.
     */
    QC.Popup {
        id: sheet

        parent: card
        x: 0
        y: card.height + Tokens.spacing.xs
        width: card.width
        /* Four paddings, not `padding`. The style sets topPadding, bottomPadding,
           leftPadding and rightPadding individually — to 24 — and a grouped
           `padding` does not override any of them: it stays 6 while the real insets
           stay 24. That cost the list 36px of the height measured for it below and
           sliced the last row in half. */
        topPadding: Tokens.spacing.xs
        bottomPadding: Tokens.spacing.xs
        leftPadding: Tokens.spacing.xs
        rightPadding: Tokens.spacing.xs
        modal: false
        focus: true
        closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutsideParent

        /* What is on show, which is also what Enter picks and what the height is
           measured from. */
        readonly property var shown: {
            var source = select.rows !== undefined && select.rows !== null
                         ? select.rows : []
            if (select.remote)
                return source
            var needle = String(sieve.text).trim().toLowerCase()
            if (needle === "")
                return source
            var out = []
            for (var i = 0; i < source.length; i++) {
                if (select.fits(source[i], needle))
                    out.push(source[i])
            }
            return out
        }

        /* Sized from the model, not from the content's height: the content is a
           child of this popup, so it is not laid out until the popup opens, and the
           popup cannot open at a sensible height until it is. Snapped to whole
           rows, because a seventh row sliced through the middle reads as a
           rendering fault. One row's worth is kept when there is nothing to show,
           which is where the "no matches" line goes. */
        readonly property int listHeight:
            Math.min(select.visibleRows, Math.max(1, shown.length))
            * Tokens.size.tableRow

        /* Measured off the paddings that are in force rather than the ones asked
           for, so the arithmetic survives a style that has its own opinion. */
        implicitHeight: topPadding + bottomPadding
                        + Tokens.size.control + Tokens.spacing.xs
                        + listHeight

        background: Rectangle {
            color: Fluent.popupBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder
        }

        onOpened: sieve.forceActiveFocus()
        /* Emptied on the way out, not on the way in: a sheet reopened with the last
           query still in it is a sheet that has to be cleared before it can be
           used, and clearing here also resets a `remote` caller's list through
           `queried("")`. */
        onClosed: sieve.clear()

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.xs

            QC.TextField {
                id: sieve

                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: select.placeholder
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body

                onTextChanged: {
                    select.queried(text)
                    /* Back to the top on every change: the first match is what
                       Enter takes, and leaving the mark five rows down after the
                       list underneath it changed is how the wrong party gets
                       attached. */
                    list.currentIndex = sheet.shown.length > 0 ? 0 : -1
                }

                /* Enter takes the marked row — the first match, until the arrows
                   move it. Typing three letters and pressing Return is the whole
                   point of a searchable list, and it must not need the mouse to
                   finish. */
                onAccepted: select.choose(sheet.shown[list.currentIndex])

                Keys.onDownPressed: select.step(1)
                Keys.onUpPressed: select.step(-1)
            }

            /* The list and its empty line share one cell: the line is drawn over
               the list rather than under it, so nothing about the sheet's height
               depends on whether anything matched. */
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list

                    anchors.fill: parent
                    clip: true
                    model: sheet.shown
                    boundsBehavior: Flickable.StopAtBounds
                    QC.ScrollBar.vertical: FluentScrollBar {
                        policy: QC.ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: hit

                        required property var modelData
                        required property int index

                        width: list.width
                        height: Tokens.size.tableRow
                        radius: Tokens.radius.sm

                        /* The keyboard's mark is the brand tint and the mouse's is
                           the subtle fill: two ways of pointing at a row, which are
                           routinely on two different rows at once. */
                        color: hit.ListView.isCurrentItem ? Tokens.brandTint
                             : hover.hovered ? Fluent.subtleSecondary
                                             : "transparent"

                        HoverHandler { id: hover }
                        TapHandler {
                            onTapped: {
                                list.currentIndex = hit.index
                                select.choose(hit.modelData)
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacing.sm
                            anchors.rightMargin: Tokens.spacing.sm
                            spacing: Tokens.spacing.sm

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                /* Both lines pin AlignLeft, which mirrors to
                                   AlignRight in Arabic. Left to itself, a Text
                                   follows its own content's direction — and these
                                   two routinely disagree: an Arabic name over a
                                   phone number would sit on opposite edges. */
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    text: hit.modelData ? hit.modelData.name : ""
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.body
                                    font.weight: Font.DemiBold
                                    color: Fluent.textPrimary
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    horizontalAlignment: Text.AlignLeft
                                    text: select.detailOf(hit.modelData)
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.overline
                                    color: Fluent.textTertiary
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            /* What is already owed, on the trailing edge. Drawn
                               only when there is a debt: a 0.00 against every name
                               is noise, and this figure has to be the one thing
                               that stands out when it is there. */
                            Text {
                                visible: text !== ""
                                text: (hit.modelData && hit.modelData.debt > 0
                                       && hit.modelData.debt_text)
                                      ? "\u200e" + hit.modelData.debt_text : ""
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                font.weight: Font.DemiBold
                                font.features: Tokens.figures
                                color: Tokens.danger
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Tokens.spacing.sm
                    visible: sheet.shown.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: select.emptyText !== ""
                          ? select.emptyText
                          : Strings.t("state.no_results.title", "No matches")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textTertiary
                }
            }
        }
    }
}
