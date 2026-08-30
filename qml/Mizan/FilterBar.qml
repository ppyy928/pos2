import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The one filter row every list page uses. Ported from
 * pos/app/widgets/filters.py::PageFilterBar and its SearchField.
 *
 *   [Category v]  [ Q  Search products…        x ]  [ Refresh ]
 *
 *   [filters...]  [search, fills the middle    ]  [actions...]
 *
 * Pages supply their filter combos and read `searchText`:
 *
 *     FilterBar {
 *         placeholder: Strings.t("products.search.ph", "Search products…")
 *         filterItems: [ QC.ComboBox { model: categories } ]
 *     }
 *
 * THERE IS NO REFRESH BUTTON, AND THAT IS DELIBERATE
 *
 * There was one, on eight pages, and on every one of them it re-ran a query that
 * had just been re-run: each of those controllers emits `invalidated` after any
 * write, and the pages already reload on it. A button whose work is already done
 * for it teaches an operator to distrust the screen — if refreshing is something
 * they have to remember, then what is in front of them might be stale, and it
 * never was.
 *
 * The three pages that had no `invalidated` path grew one instead of keeping the
 * button.
 *
 * `filterItems` is a plain alias rather than the default property: a default
 * property alias swallows every unnamed child, and this file's own RowLayout is
 * one of them — it would be assigned into the filter row instead of laying it
 * out.
 *
 * Timing stays with the page, exactly as in pos: the bar reports every
 * keystroke through `searchText` and reports Enter through `accepted()`, and the
 * page decides what to debounce. A 300ms timer baked in here would be wrong for
 * the pages that want the keystroke immediately.
 *
 * WHY THE MAGNIFIER IS NOT A TEXTFIELD FEATURE
 *
 * There is a SearchField in the Fluent style with all of this built in, and it
 * is registered at version 6.10 — a Qt that is newer than anything this project
 * declares (PySide6>=6.6). Importing a type the runtime does not have fails the
 * page at load, so the field is composed from TextField the way pos composes it
 * from QLineEdit.
 *
 * ARABIC
 *
 * Almost everything mirrors itself: the RowLayout reverses, so the filters end
 * up on the right and the actions on the left, and the two inline icons are
 * anchored (anchors mirror) so the magnifier stays on the leading edge.
 *
 * Padding is the exception. leftPadding and rightPadding are *not* mirrored —
 * they are physical — so the text inset has to be swapped by hand, or the text
 * would start underneath the magnifier in Arabic. That single conditional is the
 * only place in this file that asks which way the language runs.
 */
Item {
    id: bar

    // =====================================================================
    // API
    // =====================================================================
    property string placeholder: ""

    /* Live text. Bind to it; the page owns any debouncing. */
    readonly property alias searchText: field.text

    /* Enter in the search box. pos treats this as the barcode path — a scanner
       ends its burst with Return — so pages usually try an exact lookup here
       before falling back to a search. */
    signal accepted()

    /* Filter combos, before the search box. Not `default` — see the note above. */
    property alias filterItems: leadHost.data

    /* Trailing actions, after the search box. */
    property alias actionItems: trailHost.data

    /* The input itself, for the pages that need to reach into it — the barcode
       path selects all before a rescan. Named searchField, not field: an alias
       may not share its name with the id it points at. */
    readonly property alias searchField: field

    function clear() { field.clear() }
    function focusSearch() { field.forceActiveFocus() }

    // =====================================================================
    // INTERNALS
    // =====================================================================
    /* Inline buttons are one size down from the field they sit inside, with a
       small inset from its border. `reserve` is the text inset that keeps a
       value from running underneath one of them. */
    readonly property int inlineSize: Tokens.size.controlSmall
    readonly property int inlineInset: 4
    readonly property int reserve: inlineSize + 2 * inlineInset

    implicitHeight: Tokens.size.control

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.md

        Row {
            id: leadHost
            spacing: Tokens.spacing.sm
            Layout.alignment: Qt.AlignVCenter
        }

        QC.TextField {
            id: field
            Layout.fillWidth: true
            Layout.minimumWidth: 360   // 240 in pos, at this app's 1.5x geometry
            Layout.preferredHeight: Tokens.size.control
            Layout.alignment: Qt.AlignVCenter

            placeholderText: bar.placeholder
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body

            /* The one thing mirroring cannot do for us. Padding is physical, so
               the leading inset — the one that clears the magnifier — has to be
               named as left or right depending on the language. The magnifier
               itself is anchored, and anchors mirror, so it has already moved. */
            leftPadding: Strings.rtl ? trailingInset : bar.reserve
            rightPadding: Strings.rtl ? bar.reserve : trailingInset

            /* Room for the clear button only while there is something to clear;
               otherwise the ordinary text inset. */
            readonly property int trailingInset: text !== "" ? bar.reserve : Tokens.spacing.sm

            onAccepted: bar.accepted()

            Icon {
                /* Decoration, not a control: in pos it is a QToolButton with
                   nothing connected to it, which only invites a click that does
                   nothing. Leading edge, by anchor, so Arabic moves it. */
                anchors.left: parent.left
                anchors.leftMargin: bar.inlineInset
                anchors.verticalCenter: parent.verticalCenter
                width: bar.inlineSize
                height: bar.inlineSize
                icon: "ic_fluent_search_20_regular"
                size: Tokens.icon.md
                color: Fluent.textTertiary
            }

            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: bar.inlineInset
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: bar.inlineSize
                implicitHeight: bar.inlineSize
                visible: field.text !== ""
                glyph: "ic_fluent_dismiss_20_regular"
                glyphColor: Fluent.textTertiary
                /* Clearing must not also take the caret away: the operator is
                   mid-search, and the next thing they do is type. */
                onClicked: { field.clear(); field.forceActiveFocus() }
            }
        }

        Row {
            id: trailHost
            spacing: Tokens.spacing.sm
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
