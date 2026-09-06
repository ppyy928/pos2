import QtQuick
import FluentControls
import Mizan

/*
 * The trailing action column of a DataTable: open / pay / delete and friends,
 * one icon per action. Ported from pos/app/widgets/action_delegate.py.
 *
 *   Columns.column({ key: "actions", actions: [
 *       { id: "edit" },
 *       { id: "adjust", enabled: app.session.can("products.manage") },
 *       { id: "delete", enabled: function (r) { return r.deletable } }
 *   ]})
 *
 * An action is `{ id, glyph?, tone?, label?, enabled? }` and only `id` is
 * required — the seven ids pos uses carry their own glyph, tint and English
 * label below, so a page names the action and nothing else.
 *
 * A NOTE ON `view`
 *
 * It is still defined, and the sales and returns pages still use it: a sale and a
 * return are documents, and looking at one is all there is to do with it. It is
 * *not* what opens a customer, a supplier, a product or a purchase invoice any
 * more — those are records with an editor, so `edit` opens them and the eye that
 * used to sit beside it, opening a read-only copy of the same thing, is gone. Two
 * icons on one row leading to one record is a column doing one job twice.
 *
 * WHAT THE PORT DROPS
 *
 * pos paints these by hand in a QStyledItemDelegate: an icon cache keyed by
 * (name, enabled, colour), hand-computed 48px hit slots, hit-testing in
 * editorEvent, tooltips in helpEvent, and a slot order reversed for RTL. Its
 * docstring says why — "no setIndexWidget anywhere — pure painting stays fast on
 * large tables", because a widget per row on a 1000-row table is 4000 widgets.
 *
 * A ListView only instantiates the rows it can show, so the same four buttons on
 * the same 1000-row table are ~60 items, and all of that machinery collapses
 * into a Row of IconButtons: hit slots become the buttons' own geometry, the
 * tooltip and the accessible name come free with IconButton.tooltip, and the RTL
 * slot reversal is what a Row does under mirroring anyway.
 *
 * Nothing is instantiated for a column that declares no actions: an empty model
 * makes the Repeater create zero items, so this costs one Item and one Row in
 * every ordinary cell and no buttons at all.
 */
Item {
    id: cellActions

    // =====================================================================
    // API
    // =====================================================================
    property var actions: []

    /* The row this cell belongs to, for the row-dependent `enabled` form. */
    property var rowData: null

    /* "The operator pressed <id> on this row." The page acts; this asks. */
    signal triggered(string action)

    // =====================================================================
    // DEFAULTS PER ACTION ID
    // =====================================================================
    /*
     * pos's _glyph_color map, with a glyph and an English fallback label added
     * so a page can write `{ id: "delete" }` and get a red bin with a tooltip.
     *
     * The tones are semantic and worth keeping consistent across pages: an
     * operator learns that the red icon is the destructive one once, not per
     * screen. `delete` and `return` are reserved words but perfectly legal as
     * property names, and they are read through the id string anyway.
     *
     * Every glyph name here is checked against FluentSystemIcons-Index.js. The
     * font is _20_ only — one spelling at every rendered size — and an unknown
     * name draws nothing at all rather than failing, so a typo would be a blank
     * cell nobody could explain.
     */
    readonly property var defaults: ({
        "view":   { glyph: "ic_fluent_eye_20_regular",        tone: "info",    label: "View" },
        "edit":   { glyph: "ic_fluent_edit_20_regular",       tone: "primary", label: "Edit" },
        "delete": { glyph: "ic_fluent_delete_20_regular",     tone: "danger",  label: "Delete" },
        "print":  { glyph: "ic_fluent_print_20_regular",      tone: "warning", label: "Print" },
        "return": { glyph: "ic_fluent_arrow_undo_20_regular", tone: "warning", label: "Return" },
        "pay":    { glyph: "ic_fluent_money_20_regular",      tone: "success", label: "Pay" },
        "adjust": { glyph: "ic_fluent_arrow_swap_20_regular", tone: "primary", label: "Adjust" }
    })

    function defaultsFor(action) {
        var id = action && action.id ? action.id : ""
        return defaults[id] !== undefined ? defaults[id]
                                          : { glyph: "", tone: "primary", label: id }
    }

    function glyphOf(action) {
        return action.glyph !== undefined ? action.glyph : defaultsFor(action).glyph
    }

    function toneOf(action) {
        return action.tone !== undefined ? action.tone : defaultsFor(action).tone
    }

    /* pos keys the tooltip off the action id — tr(f"action.{action_id}") — so
       these share the catalogue entries with every button that does the same
       thing elsewhere on the page.

       An explicit `label` wins, because the seven ids are shared vocabulary and a
       caller with an id of its own has nothing in the catalogue under that name: the
       saved-carts list says "Open" for a cart it restores, where `action.open` is the
       catalogue's "Open / Manage" for a record. Documented in the header as part of
       an action, and until now silently ignored. */
    function labelOf(action) {
        if (action && action.label !== undefined && action.label !== "")
            return action.label
        var id = action && action.id ? action.id : ""
        return Strings.t("action." + id, defaultsFor(action).label)
    }

    /*
     * `enabled` is a bool, a function of the row, or absent.
     *
     * pos gates only on a permission, which is a plain bool by the time it gets
     * here. The function form covers what pos has to handle inside the page
     * instead: an invoice that is already paid has nothing to pay, a sale that
     * was returned cannot be returned again. Same shape as Column.tone, which is
     * also either a value or a function of the row.
     */
    function enabledOf(action) {
        var gate = action.enabled
        if (gate === undefined)
            return true
        if (typeof gate === "function")
            return gate(cellActions.rowData) === true
        return gate === true
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    Row {
        /* Centred, because distribute() may hand this column up to 1.75x its
           declared width and the strip should gain padding on both sides rather
           than drift away from its header. pos centres for the same reason
           (`left = rect.x() + (rect.width() - strip) // 2`).

           No spacing: an IconButton is already a 48px square, so the glyphs land
           48px apart exactly as pos's ICON_SLOT puts them. */
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: cellActions.actions

            IconButton {
                required property var modelData

                glyph: cellActions.glyphOf(modelData)
                enabled: cellActions.enabledOf(modelData)
                tooltip: cellActions.labelOf(modelData)

                /* Tinted while it is available, flat grey when it is not — pos
                   dims a gated action to border_strong rather than hiding it, so
                   the row keeps the same shape whoever is signed in and an
                   operator can see there is something they may not do. */
                glyphColor: enabled ? Tokens.toneInk(cellActions.toneOf(modelData))
                                    : Fluent.textDisabled

                /* The button is a later sibling than the row's MouseArea, so it
                   is above it and takes the press: clicking an icon does not
                   also select the row. That is pos's behaviour too, where
                   editorEvent returns true to consume the click. */
                onClicked: cellActions.triggered(modelData.id)
            }
        }
    }
}
