import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The pager under a DataTable.
 *
 *   ┌──────────────────────────────────────────────────────────────────────┐
 *   │  1–100 of 2,999        ⟨‹‹ ‹  Page 1 of 30  › ››⟩        100 / page  │
 *   └──────────────────────────────────────────────────────────────────────┘
 *
 * WHAT THIS LOOKED LIKE BEFORE, AND WHY IT CHANGED
 *
 * Five loose chips, the word "Show", a 150px editable combo and a sentence, spread
 * across the full width of the page with nothing holding them together — three
 * groups floating under a table, none of them looking like it belonged to the other
 * two. Three changes:
 *
 *   ONE SURFACE. The bar is a contained strip now, the same tinted-with-a-border
 *   recipe the Reports period bar uses. It reads as the table's footer rather than
 *   as leftover controls.
 *
 *   ONE NAVIGATOR. The four chevrons and the page counter sit inside a single pill
 *   track, so they are one control with a readout in the middle instead of five
 *   things in a row. Centred, because that is where the eye looks for it.
 *
 *   NO TYPED PAGE SIZE. The combo was editable, with `maxRows`, a strict integer
 *   parse and a re-sync on every commit — machinery for a number nobody types. The
 *   presets are the page sizes a page size is ever set to, so it is a plain combo
 *   reading "100 / page", and the word "Show" is gone with it.
 *
 * WHO OWNS THE PAGE NUMBER
 *
 * Not this component. `page`, `total` and `pageSize` are inputs, and a click *asks*
 * for a change through pageRequested/pageSizeRequested — it does not move the pager.
 * That is pos's contract (`page_requested` then `set_state`) and it is also what
 * keeps the pager safe to bind: a component that assigned to its own `page` would
 * destroy the page's binding the first time it was clicked, and from then on the
 * pager and the data it describes would drift apart. The page loads the rows and
 * reports back; until it does, the pager keeps showing what is actually on screen.
 */
Item {
    id: root

    // =====================================================================
    // API
    // =====================================================================
    /* State, as reported by the page. Clamped on read rather than on write, so a
       page can bind these straight to its own loader state without this component
       ever writing back. */
    property int page: 1
    property int total: 0
    property int pageSize: 100

    /* Hide the rows control for a fixed page size (pos: `per_page_host`). */
    property bool showPageSize: true

    /* "Give me page N." The handler loads the rows, then updates `page`. */
    signal pageRequested(int page)

    /*
     * "Show N rows per page." The handler is expected to reload from page 1 — pos
     * resets the page itself before emitting, and a handler that kept the old page
     * number would land the operator on a page that may no longer exist.
     *
     * Named ...Requested and not ...Changed on purpose: `pageSizeChanged` is already
     * the automatic notifier for the `pageSize` property above, and declaring a
     * signal with that name would collide with it.
     */
    signal pageSizeRequested(int size)

    /* 25 and 50 are here because a page that shows its table inside a page-level
       scroll cannot afford a hundred rows — the Reports screen asks for 50. */
    readonly property var rowsPresets: [25, 50, 100, 200, 500, 1000]

    // =====================================================================
    // DERIVED STATE
    // =====================================================================
    /* pos clamps inside set_state; here the clamp is part of the read, which means
       nothing has to be written back and a nonsense input cannot become persistent
       state. */
    readonly property int currentPage: Math.max(1, page)
    readonly property int rowCount: Math.max(0, total)
    readonly property int rowsPerPage: Math.max(1, pageSize)

    /* Always at least 1: an empty table is "1 of 1", not "1 of 0". */
    readonly property int maxPage: Math.max(1, Math.ceil(rowCount / rowsPerPage))

    readonly property bool atFirst: currentPage <= 1
    readonly property bool atLast: currentPage >= maxPage

    readonly property int firstShown: rowCount > 0
                                      ? (currentPage - 1) * rowsPerPage + 1 : 0
    readonly property int lastShown: rowCount > 0
                                     ? Math.min(currentPage * rowsPerPage, rowCount) : 0

    readonly property bool rtl: Strings.rtl

    implicitHeight: Tokens.size.control + Tokens.spacing.sm

    // =====================================================================
    // HELPERS
    // =====================================================================
    /* Clamp, then ask — and stay quiet if the answer is the page we are already on,
       so holding down "next" at the end does not fire a reload per click. */
    function go(target) {
        var wanted = Math.min(Math.max(1, target), maxPage)
        if (wanted !== currentPage)
            pageRequested(wanted)
    }

    /* Thousands separators, matching pos's `f"{n:,}"`. Deliberately not
       Number.toLocaleString(): that follows the system locale, which is not the
       language the operator picked in this app, so a French UI on an English Windows
       would group one way in the pager and another way in the money column right
       above it. */
    function grouped(value) {
        var digits = "" + Math.round(value)
        var out = ""
        while (digits.length > 3) {
            out = "," + digits.slice(-3) + out
            digits = digits.slice(0, -3)
        }
        return digits + out
    }

    function indexOfSize(size) {
        for (var i = 0; i < rowsPresets.length; i++)
            if (rowsPresets[i] === size)
                return i
        return -1
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Tokens.spacing.sm
        radius: Tokens.radius.md
        color: Fluent.subtleSecondary
        border.width: 1
        border.color: Fluent.dividerBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacing.md
            anchors.rightMargin: Tokens.spacing.md
            spacing: Tokens.spacing.md

            // ---- what is on screen ---------------------------------------
            /* The fact, on the reading edge. The range is what an operator checks
               against — "am I looking at all of it" — and it is the only part of this
               bar that is information rather than a control. */
            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: root.width / 3
                text: Strings.tf("pagination.showing",
                                 "{from}–{to} of {total}", {
                    from: root.grouped(root.firstShown),
                    to: root.grouped(root.lastShown),
                    total: root.grouped(root.rowCount)
                })
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                /* Tabular figures: the counts change as the operator pages, and
                   proportional digits make the whole line jump because a 1 is
                   narrower than a 0 in this typeface. */
                font.features: Tokens.figures
                color: Fluent.textSecondary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Item { Layout.fillWidth: true }

            // ---- the navigator -------------------------------------------
            /* One track, five parts. A pill around them is what turns four chevrons
               and a number into a single control. */
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: nav.implicitWidth + Tokens.spacing.xs
                implicitHeight: Tokens.size.controlSmall + Tokens.spacing.xs
                radius: Tokens.radius.pill
                color: Fluent.cardBackground
                border.width: 1
                border.color: Fluent.dividerBorder
                visible: root.maxPage > 1

                Row {
                    id: nav
                    anchors.centerIn: parent
                    spacing: 0

                    /* The chevrons are swapped in Arabic, not just repositioned. The
                       Row mirrors, so "first" already moves to the right-hand end;
                       but a chip that still pointed left there would be pointing
                       *forward* through the list. In RTL the sequence runs right to
                       left, so first and previous point right. pos does the same
                       swap. */
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.rtl ? "ic_fluent_chevron_double_right_20_regular"
                                        : "ic_fluent_chevron_double_left_20_regular"
                        glyphSize: Tokens.icon.sm
                        enabled: !root.atFirst
                        tooltip: Strings.t("pagination.first", "First page")
                        onClicked: root.go(1)
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.rtl ? "ic_fluent_chevron_right_20_regular"
                                        : "ic_fluent_chevron_left_20_regular"
                        glyphSize: Tokens.icon.sm
                        enabled: !root.atFirst
                        tooltip: Strings.t("pagination.prev", "Prev")
                        onClicked: root.go(root.currentPage - 1)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        /* Width grows with the digit count and never shrinks below a
                           sensible minimum, so paging from 9 to 10 does not shift the
                           chevrons either side of it. */
                        width: Math.max(implicitWidth + 2 * Tokens.spacing.sm, 96)
                        horizontalAlignment: Text.AlignHCenter
                        text: Strings.tf("pagination.page_of", "Page {page} of {pages}",
                                         { page: root.currentPage, pages: root.maxPage })
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        font.weight: Font.DemiBold
                        font.features: Tokens.figures
                        color: Fluent.textPrimary
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.rtl ? "ic_fluent_chevron_left_20_regular"
                                        : "ic_fluent_chevron_right_20_regular"
                        glyphSize: Tokens.icon.sm
                        enabled: !root.atLast
                        tooltip: Strings.t("pagination.next", "Next")
                        onClicked: root.go(root.currentPage + 1)
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.rtl ? "ic_fluent_chevron_double_left_20_regular"
                                        : "ic_fluent_chevron_double_right_20_regular"
                        glyphSize: Tokens.icon.sm
                        enabled: !root.atLast
                        tooltip: Strings.t("pagination.last", "Last page")
                        onClicked: root.go(root.maxPage)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // ---- rows per page -------------------------------------------
            QC.ComboBox {
                id: rowsCombo
                Layout.alignment: Qt.AlignVCenter
                /* Wide enough for the longest preset label the model carries
                   — "1000 / page" — at the largest font scale this app runs
                   at, plus the padding and the indicator arrow the style
                   draws inside the control. At 150 the arrow sat on the last
                   two characters: the label was clipped, not elided, because
                   the Fluent style's content item is not the one that elides. */
                Layout.preferredWidth: 200
                Layout.preferredHeight: Tokens.size.controlSmall + Tokens.spacing.xs
                visible: root.showPageSize
                model: root.rowsPresets
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption

                /* "100 / page" rather than a bare 100 beside the word "Show": the
                   unit belongs to the value, and it saves a label. */
                displayText: Strings.tf("pagination.per_page", "{n} / page",
                                        { n: root.rowsPerPage })

                onActivated: (index) => root.pageSizeRequested(root.rowsPresets[index])
            }

            /* ComboBox writes its own currentIndex on activation, which destroys a
               declarative binding — so the link back from `pageSize` is a Binding
               element, which re-applies however many times that has happened. */
            Binding {
                target: rowsCombo
                property: "currentIndex"
                value: root.indexOfSize(root.rowsPerPage)
                restoreMode: Binding.RestoreNone
            }
        }
    }
}
