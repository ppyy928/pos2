import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import QtQuick.Window
import FluentControls
import Mizan

/*
 * Point of Sale â€” the till. Ported from pos/app/pages/pos.py (1482 lines, the
 * largest file in that codebase) plus the widgets it owns: cart_list.py,
 * keypad_display.py, numpad.py, party.py, transaction.py and the tile builder
 * inside the page itself.
 *
 *  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”گ
 *  â”‚ [ ًں”چ search / scan                        ]     â”‚ ًں‘¤ Walk-in         â”‚
 *  â”‚ [âک… Favourites][â–ŒDrinks][â–ŒBakery]          â”Œâ”€â”€â”€â”گ â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
 *  â”‚ â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”گ â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”گ â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”گ          â”‚ًں–©  â”‚ â”‚ Coca-Cola 1.5L     â”‚
 *  â”‚ â”‚â–ŒCoca   â”‚ â”‚â–ŒFanta  â”‚ â”‚â–ŒWater  â”‚          â”‚Calâ”‚ â”‚ 120,00 [âˆ’2+] 240,00â”‚
 *  â”‚ â”‚ 120,00 â”‚ â”‚ 120,00 â”‚ â”‚  60,00 â”‚          â”œâ”€â”€â”€â”¤ â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
 *  â”‚ â””â”€â”€â”€â”€â”€â”€â”€â”€â”ک â””â”€â”€â”€â”€â”€â”€â”€â”€â”ک â””â”€â”€â”€â”€â”€â”€â”€â”€â”ک          â”‚â†©  â”‚ â”‚ ...                â”‚
 *  â”‚                                           â”‚Retâ”‚ â”‚                    â”‚
 *  â”‚                                           â”œâ”€â”€â”€â”¤ â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
 *  â”‚                                           â”‚âڈ¸  â”‚ â”‚ 6133273401  # QTY  â”‚
 *  â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”¤ â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
 *  â”‚ ًں§¾ Cart 001 â”‚      TOTAL      â”‚ [Cash] [Partial]â”‚ â”‚ #QTY â”‚7â”‚8â”‚9â”‚      â”‚
 *  â”‚ Items 4     â”‚   12 480,00 DA  â”‚                 â”‚ â”‚ +AMT â”‚4â”‚5â”‚6â”‚      â”‚
 *  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”ک
 *
 * WHERE THE STATE LIVES, AND WHY
 *
 * The cart is the controller's, not this page's. pos keeps `self._items` on the
 * page and computes the totals there â€” which it can, because fmt_money is one
 * import away. Here every amount on screen is a formatted string that arrived
 * from Python: the currency, the decimal count and the digit shapes for the
 * active language are all in fmt_money, and a second implementation in
 * JavaScript would be a second set of rules for the same money. So the cart, the
 * totals and the pricing are behind the bridge, and this page owns exactly what
 * pos's page owns that is *not* money: which tab is open, what has been typed,
 * which line is selected, and whether the payment panel is up.
 *
 * WHAT app.pos HAS TO PROVIDE
 *
 *   read      busy, error
 *             tiles, categories, lines
 *             cartNumber, totalText, currencyText, itemsText, qtyText,
 *             discountText
 *             customerName, customerPhone, hasCustomer
 *             remainingText, paidValid, allowPartial
 *   call      loadCategories(), loadTiles(tab, search)
 *             add(productId), setQty(row, qty), remove(row), clear(), hold()
 *             resolve(text), scan(code), addFreeAmount(sign, amount)
 *             setCustomer(customerId), setPaid(amount)
 *             payCash(), payPartial()
 *   emits     invalidated(), lineTouched(row)
 *             resolved(text, added), scanMissed(code, barcode)
 *             saleFinished(number), rejected(message)
 *
 * A `tiles` row is {id, name, price_text, stock, stock_text, low_stock, color,
 * barcode} â€” pos's fetch_pos_products row with the price already formatted and
 * the low-stock comparison already made. A `lines` row is {name, qty, qty_text,
 * price_text, total_text, step}. Both are read through the same `rowData` idiom
 * DataTable uses, so either a JS array or a role-based model works.
 *
 * THE TWO QUESTIONS ASKED OF A TYPED STRING
 *
 * pos asks the database twice about the same kind of text, and means something
 * different each time â€” that difference is the whole of the till's input model
 * and it is kept:
 *
 *   resolve()   the keypad's Apply. Is this a barcode? If so add it; if not it
 *               is a number and the active mode says what to do with it.
 *               `resolved(text, added)` carries the text back, so a slow lookup
 *               cannot apply a quantity the operator has since retyped.
 *   scan()      a scanner burst or Enter in the search box. Is this a barcode?
 *               If so add it; if not, offer to create it â€” never a quantity.
 *
 * WHAT THIS CHANGES ON PURPOSE
 *
 * 1. A partial payment is typed on the numpad, not into a text field. pos puts a
 *    MoneyEdit in the panel and routes physical digits into it through an
 *    application-wide event filter; a till with no keyboard cannot use it at all.
 *    Here the panel is open, the numpad's mode column is empty, and the buffer
 *    *is* the amount received â€” Apply confirms it. One entry mechanism for
 *    everything that is typed on this screen.
 *
 * 2. An out-of-stock tile is tappable and says why. pos disables it, and a dead
 *    rectangle on a touchscreen is indistinguishable from a frozen application.
 *    See PosTile's own header â€” this page is the other half of that decision.
 *
 * 3. The search box filters the grid instead of opening a dropdown. pos never
 *    builds tiles from a search, so its results live in a completer over the
 *    field; a grid that answers the search directly is one fewer surface, and the
 *    tiles are already the thing being pointed at.
 *
 * 4. Escape does not leave the page. pos's Escape closes the payment panel and
 *    otherwise navigates to the dashboard; navigation belongs to the shell here,
 *    and a cashier who taps Escape twice should not lose the screen they are
 *    selling from. It closes the panel, then clears the buffer, then nothing.
 *
 * WHAT IS DELIBERATELY NOT HERE
 *
 * pos decodes scanner bursts with an application-wide event filter over
 * layout-independent virtual key codes (BurstDecoder), because a USB scanner
 * types faster than a human and its digits must not land in whatever field has
 * focus. That decoder is Python, it already exists, and reimplementing the
 * timing heuristics in QML would be a second version of it. Until it is wired
 * in, the search box holds focus on arrival and a burst ending in Enter goes
 * through scan() â€” which is what a scanner does.
 */
Item {
    id: root

    // =====================================================================
    // BRIDGE
    // =====================================================================
    /* Guarded, so the screen lays out and is reviewable with no Python behind
       it: an empty grid, an empty cart, em-dash totals. Same guard LoginPage,
       ProductsPage and Strings already use. */
    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.pos : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app) ? app.workflows : null

    // =====================================================================
    // VIEW STATE â€” everything pos keeps on the page that is not money
    // =====================================================================
    /* "favorites", or a category id. Never null once the categories have
       arrived; null before that means "nothing to load yet". */
    property var activeTab: null

    property string search: ""

    /* The one input buffer. Every digit, wherever it came from, is appended here
       and rendered by KeypadDisplay â€” pos's single source of truth for "what have
       I typed", and worth keeping: two of those is how a quantity lands on the
       wrong line. */
    property string buffer: ""

    /* Which cart column Apply edits: "qty" | "plus" | "minus". The vocabulary is
       Numpad's; this is just the name of the one in force. */
    property string mode: "qty"

    /* -1 is "nothing chosen", not "row 0". */
    property int selectedRow: -1


    // =====================================================================
    // DERIVED
    // =====================================================================
    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property bool allowPartial: ctrl ? ctrl.allowPartial : true
    readonly property bool paidValid: ctrl ? ctrl.paidValid : false
    readonly property bool hasCustomer: ctrl ? ctrl.hasCustomer : false

    /* The invoice this till is holding, if any. Non-zero puts the screen in edit
       mode: same layout, same gestures, different chrome and a different commit. */
    readonly property int editing: ctrl ? ctrl.editing : 0
    readonly property string editingNumber: ctrl ? ctrl.editingNumber : ""

    /* Rearranging the tiles edits the catalogue's order, so it takes the
       catalogue's write permission — a cashier gets the grid, not the ability to
       redraw it. Hidden rather than dimmed: a disabled setup button on a till
       screen is noise for the operator who will never be allowed to press it.

       `session.revision` is read first and is not decoration. `can()` is a slot, so
       a binding that only calls it never re-evaluates — and this page is the default
       screen, built before anybody has logged in. Without the revision the icon
       evaluated against an empty session and stayed hidden for the whole shift,
       appearing only after navigating away and back rebuilt the page. */
    readonly property bool canArrange: session
                                       && session.revision >= 0
                                       && session.can("products.manage")

    /* Counted off the views rather than the controller: it is the same number,
       and asking the thing that is on screen cannot disagree with what is on
       screen. */
    readonly property int cartCount: cartView.count
    readonly property int tileCount: tileGrid.count

    /* Matches for the dropdown. Not tiles: this list can contain products the tile
       wall never shows, because a search means the whole catalogue. */
    readonly property var results: ctrl ? ctrl.results : []

    /* Rows the dropdown shows before it starts scrolling. Till.SEARCH_LIMIT caps
       what comes back at twelve; this caps what is on screen at once. */
    readonly property int searchRows: 6

    /* A one-word pill, for the two things a search result can be that a tile never
       is: out of stock, or kept off the tile wall entirely. Built from the same
       parts as PosTile's own stock pill (Tokens.toneFill on the outside,
       Tokens.toneInk on the text) so the two read as the same object â€” there is no
       Badge component in Mizan to borrow. Declared before its first use: an inline
       component referenced above its own declaration is not reliably resolved. */
    component Tag: Rectangle {
        property string label: ""
        property string tone: "warning"

        implicitWidth: tagText.implicitWidth + Tokens.spacing.sm
        implicitHeight: tagText.implicitHeight + Tokens.spacing.xs
        radius: Tokens.radius.pill
        color: Tokens.toneFill(tone)

        Text {
            id: tagText
            anchors.centerIn: parent
            text: parent.label
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.weight: Font.DemiBold
            color: Tokens.toneInk(parent.tone)
        }
    }

    /* pos's _selected_row: with nothing chosen, the keypad acts on the last line.
       That is what makes "scan, type 3, Apply" work without ever touching the
       cart â€” the line just added is the last one. */
    readonly property int targetRow: (selectedRow >= 0 && selectedRow < cartCount)
                                     ? selectedRow : cartCount - 1

    /* pos's _QTY_MAX. A ceiling on a typed quantity, not on a real one: three
       digits is a case of water, five is a typo. */
    readonly property real qtyMax: 9999

    readonly property var modeSpec: numpad.specFor(root.mode)

    /* The state matrix for the grid. An error outranks emptiness. There is no
       "no results" state here any more: the grid shows the open category and
       nothing else, so an empty grid means an empty category â€” searching cannot
       empty it. Search results live in the dropdown under the field. */
    readonly property bool showTileState: !busy && tileCount === 0
    readonly property string tileState: errorText !== "" ? "error" : "empty"

    /* Is a text editor focused? The Delete shortcut below must not eat the key
       that erases a character in the search box â€” and `cursorPosition` is what a
       TextField has and a tile does not. Window.activeFocusItem is the only way
       to ask this from outside the item that has focus. */
    readonly property bool typing: {
        var item = Window.activeFocusItem
        return item !== null && item !== undefined
               && item.cursorPosition !== undefined
    }

    // =====================================================================
    // TABS
    // =====================================================================
    /* Favourites, then one chip per category. A binding, so it retranslates and
       picks up new categories on its own; `color` is the category's own, which
       CategoryStrip uses for a bar and a tint and never for ink. */
    readonly property var tabs: {
        var out = [{
            key: "favorites",
            label: Strings.t("pos.tab.favorites", "Favourites"),
            glyph: "ic_fluent_star_20_regular"
        }]
        var src = ctrl ? ctrl.categories : null
        if (src)
            for (var i = 0; i < src.length; i++)
                out.push({
                    key: src[i].id,
                    label: src[i].name,
                    accent: src[i].color ? src[i].color : "transparent"
                })
        return out
    }

    onTabsChanged: repairTab()

    /* Choose or repair the open tab. pos defaults to the first *category* rather
       than to Favourites, and that is the right way round: a shop that has never
       used favourites would otherwise be shown an empty grid on the screen it
       sells from. Favourites is the fallback only when there is no category at
       all. */
    function repairTab() {
        for (var i = 0; i < tabs.length; i++)
            if (tabs[i].key === activeTab)
                return
        activeTab = tabs.length > 1 ? tabs[1].key : "favorites"
        reload()
    }

    function selectTab(key) {
        if (activeTab === key)
            return
        activeTab = key
        reload()
    }

    // =====================================================================
    // DATA
    // =====================================================================
    /* One category at a time, never the whole catalogue â€” pos's rule, and the
       reason a shop with four thousand products does not build four thousand
       tiles. `activeTab` is null only before the categories land.

       It no longer takes the search text. The grid used to be replaced by
       catalogue-wide results the moment three letters were typed: the open
       category emptied, its chip stayed highlighted in the strip as though it were
       still showing, and a wall of tiles became a result list. Searching is a
       separate question now, and it answers in a dropdown. */
    function reload() {
        if (ctrl && activeTab !== null)
            ctrl.loadTiles(activeTab)
    }

    /* Ask for matches. Called by the debounce and directly on Enter, because a
       scanner sends its burst and its Return faster than 300ms and the dropdown
       must not lag a whole interval behind the scan. */
    function flushSearch() {
        debounce.stop()
        search = filters.searchText
        if (ctrl)
            ctrl.search(search)
    }

    /* Clear the field, the query and the dropdown in one move: after a match is
       taken the search has been answered, and a list of alternatives left hanging
       over the tiles is in the way of the next scan. */
    function clearSearch() {
        debounce.stop()
        search = ""
        filters.clear()
        if (ctrl)
            ctrl.search("")
    }

    /* Take a row from the dropdown or the picker dialog. Unlike a tile, this row
       may be a product the tile wall never shows — Till.add looks it up in the
       database when it is not among the tiles. */
    function take(row) {
        if (!row)
            return
        if (ctrl)
            ctrl.add(row.id)
        warnIfShort(row)
        clearSearch()
    }

    // =====================================================================
    // TILES
    // =====================================================================
    /*
     * A tap on a tile. It always adds.
     *
     * Both of these used to refuse at `stock <= 0` and toast "out of stock". That
     * was the wrong rule twice over: `finalize_sale` lets stock go negative on
     * purpose (pos/app/data/db.py:1241-1243), because a shop sells the case that is
     * still on the pallet and because a count is often simply wrong — and refusing
     * left the operator with a product they can see on the shelf and no way to sell
     * it, on a screen that never explained the difference.
     *
     * So the sale goes through and the screen SAYS what it did. The tile already
     * shows the count and turns red below zero; this adds the sentence.
     */
    function pick(row) {
        if (!row)
            return
        if (ctrl)
            ctrl.add(row.id)
        warnIfShort(row)
    }

    /* Told, not stopped. `caution` rather than `warning`: the sale is fine, the
       stock record is what needs attention, and it needs it later. */
    function warnIfShort(row) {
        if (!row || row.stock === undefined)
            return
        if (row.stock > 0)
            return
        notify(row.name + " — "
               + Strings.t("pos.tile.oversold",
                           "sold below stock — the count is now negative"),
               Severity.caution)
    }

    // =====================================================================
    // KEYPAD
    // =====================================================================
    /* One numpad press. The vocabulary is Numpad's: digits, ".", "back",
       "clear" and "apply" â€” the three mode keys have their own signal. */
    function feed(key) {
        switch (key) {
        case "clear":
            buffer = ""
            return
        case "back":
            buffer = buffer.substring(0, buffer.length - 1)
            return
        case ".":
            /* A single separator, as pos does. Typed as "." whatever the
               language: this is a keypad, not a text field, and Python
               normalises the separator on the way in. */
            if (buffer.indexOf(".") < 0)
                buffer += "."
            return
        case "apply":
            applyEntry()
            return
        }
        if (key.length === 1 && key >= "0" && key <= "9")
            buffer += key
    }

    /* Apply, from the keypad or from Return. */
    function applyEntry() {
        if (buffer === "")
            return

        /* Cleared as it is submitted, and the text travels with the question:
           the lookup is a round trip to Python, and the operator may well have
           started typing the next thing before the answer comes back. */
        var text = buffer
        buffer = ""

        if (ctrl)
            ctrl.resolve(text)
        else
            applyNumber(text)   // nothing to look a barcode up in
    }

    /* The buffer was not a barcode, so it is a number and the mode says what it
       means. pos's _process_input from the ValueError branch down. */
    function applyNumber(text) {
        var value = parseFloat(String(text).replace(",", "."))
        if (isNaN(value) || value <= 0) {
            reject()
            return
        }

        if (mode === "qty") {
            if (targetRow < 0) {
                /* Nothing to apply it to. A warning rather than silence: the
                   operator has typed a number and pressed Apply, and the reason
                   nothing happened is not on screen anywhere else. */
                notify(Strings.t("pos.select_item", "Select a line first"),
                       Severity.caution)
                return
            }
            if (value > qtyMax) {
                reject()
                return
            }
            if (ctrl)
                ctrl.setQty(targetRow, value)
            return
        }

        /* + AMT is a charge line, âˆ’ DISC is a cart-level discount line. Both are
           free lines at آ±amount, qty 1 â€” pos's _add_free_amount, including the
           reason the cart has no per-line discount column. */
        if (ctrl)
            ctrl.addFreeAmount(mode === "plus" ? 1 : -1, value)
    }

    function reject() {
        notify(Strings.t("pos.input.invalid", "That value cannot be used here."),
               Severity.caution)
        buffer = ""
    }

    // =====================================================================
    // CART
    // =====================================================================
    function setQty(row, value) {
        /* The same rules as the QTY keypad mode, because it is the same edit:
           zero and out-of-range are refused and the row keeps what it had. */
        if (value <= 0 || value > qtyMax || !ctrl)
            return
        ctrl.setQty(row, value)
    }

    function askRemove(row) {
        if (row < 0 || row >= cartCount)
            return
        var line = cartView.itemAtIndex(row)
        confirmRemove.row = row
        confirmRemove.lineName = line ? line.name : ""
        confirmRemove.open()
    }

    function requireCart() {
        if (cartCount > 0)
            return true
        notify(Strings.t("pos.cart_empty", "The cart is empty"), Severity.caution)
        return false
    }

    // =====================================================================
    // COMMANDS
    // =====================================================================
    readonly property var commands: [
        {
            key: "calculator", tone: "info", shortcut: "F4",
            glyph: "ic_fluent_calculator_20_regular",
            label: Strings.t("pos.rail.calculator", "Calculator")
        },
        {
            /* Money goes back out of the till. */
            key: "return", tone: "warning", shortcut: "F1",
            glyph: "ic_fluent_arrow_hook_up_left_20_regular",
            label: Strings.t("pos.rail.return", "Return")
        },
        {
            /* Parked, not lost â€” the brand tone, because nothing is destroyed. */
            key: "hold", tone: "primary", shortcut: "F5",
            glyph: "ic_fluent_pause_20_regular",
            label: Strings.t("pos.rail.hold", "Hold"),
            enabled: root.cartCount > 0
        },
        {
            key: "carts", tone: "info", shortcut: "F6",
            glyph: "ic_fluent_archive_20_regular",
            label: Strings.t("pos.rail.carts", "Saved carts")
        },
        {
            key: "void", tone: "danger", shortcut: "F12",
            glyph: "ic_fluent_broom_20_regular",
            label: Strings.t("pos.rail.void", "Void"),
            enabled: root.cartCount > 0
        }
    ]

    function command(key) {
        switch (key) {
        case "calculator":
            /* Non-committing: it works out the change for the total on screen.
               The total is the controller's, so the workflow reads it there
               rather than being handed a number to re-format. */
            requestOpen("payment_calculator", {})
            return
        case "return":
            requestOpen("sale_select", { purpose: "return" })
            return
        case "hold":
            if (!requireCart())
                return
            dismiss()
            if (ctrl)
                ctrl.hold()
            return
        case "carts":
            requestOpen("saved_carts", {})
            return
        case "void":
            if (!requireCart())
                return
            confirmVoid.open()
            return
        }
    }

    // =====================================================================
    // CUSTOMER
    // =====================================================================
    function removeCustomer() {
        if (!ctrl)
            return
        /* Nothing is committed until Confirm, so dropping the customer while the
           panel is up needs no confirmation of its own â€” it just closes it. pos
           asks, because there the panel is where the debt is decided and it
           stays open. */
        dismiss()
        ctrl.setCustomer(0)
    }

    // =====================================================================
    // PAYMENT
    // =====================================================================
    function payCash() {
        if (!requireCart())
            return
        dismiss()
        if (ctrl)
            ctrl.payCash()
    }

    function startPartial() {
        if (!requireCart())
            return
        if (!allowPartial) {
            notify(Strings.t("pay.partial.off",
                             "Partial payment is switched off in settings."),
                   Severity.caution)
            return
        }
        /*
         * A dialog, not a mode on this screen.
         *
         * It used to turn the cart column into a payment panel: the keypad lost its
         * mode column, the buffer quietly became the amount received, and the
         * remaining figure appeared in a strip above the dock. It worked, and it was
         * the wrong shape for what is happening — somebody is standing at the counter
         * handing over less than the whole amount, and "so how much do I still owe?"
         * has to be asked at a size that is read across a counter. A panel wedged into
         * a 500px column could not, and a mode that silently repurposes the keypad is
         * a mode an operator can be in without noticing.
         *
         * PaymentEntry takes the screen for the moment it lasts, shows the customer's
         * existing debt beside this sale, and answers the question as the number is
         * typed. The same component the delivery screen uses.
         */
        payment.open()
    }

    function amountOf(text) {
        var value = parseFloat(String(text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    /* Not called escape(): QML refuses a method by that name â€” it collides with
       JavaScript's global escape() â€” with "Illegal method name" at load. */
    function dismiss() {
        buffer = ""
    }

    // =====================================================================
    // ELSEWHERE
    // =====================================================================
    /* Every "open something else" through one funnel, and a sentence when the
       target is not in this build â€” a button that does nothing is
       indistinguishable from a broken one. ProductsPage's requestOpen, verbatim,
       because the reasoning is the same. */
    function requestOpen(key, context) {
        if (workflows && workflows.open) {
            workflows.open(key, context || ({}))
            return
        }
        notify(Strings.t("workflow.not_ready",
                         "That screen is not part of this build yet."),
               Severity.info)
    }

    function notify(message, severity) {
        toast.show(message, severity)
    }

    // =====================================================================
    // LIFECYCLE
    // =====================================================================
    /* PageHost builds the page fresh on every navigation, so this is pos's
       activate(). The search box takes focus because that is where a scanner
       burst lands until the Python decoder is wired in. */
    Component.onCompleted: {
        if (ctrl && ctrl.loadCategories)
            ctrl.loadCategories()
        repairTab()
        filters.focusSearch()
    }

    Connections {
        target: root.ctrl

        /* A sale, a hold or a restore landed: stock moved, so the grid is stale.
           The cart itself is a model and updates on its own. */
        function onInvalidated() {
            root.reload()
        }

        /* A line was added or bumped by an add or a scan. It becomes the active
           line and is scrolled to, so "scan, type 3, Apply" works without the
           cart being touched â€” pos does the same two calls after add_product. */
        function onLineTouched(row) {
            root.selectedRow = row
            cartView.positionViewAtIndex(row, ListView.Contain)
        }

        /* The keypad's question, answered. Added means it was a barcode and it is
           already in the cart; otherwise the text was a number. */
        function onResolved(text, added) {
            if (!added)
                root.applyNumber(text)
        }

        /* A scan or an Enter in the search box that matched nothing. `barcode`
           comes from Python because Python owns the digit normaliser that decides
           it â€” an Arabic-Indic ظ ظ¦ظ،ظ¢ is a barcode and str.isdigit() alone does not
           say so. */
        function onScanMissed(code, barcode) {
            root.requestOpen(barcode ? "unknown_barcode" : "quick_add_product",
                             { code: code })
        }

        function onSaleFinished(number) {
            root.dismiss()
            root.selectedRow = -1
            root.notify(Strings.tf("toast.sale_done", "Sale {number} recorded",
                                   { number: number }),
                        Severity.success)
        }

        /* Stock went below zero on that sale. The sale is done â€” pos never
           blocks one on stock â€” so this is a report, not a question, and it names
           the products because "stock went negative" is not actionable and
           "Coca-Cola 1.5L: âˆ’3" is. */
        function onStockWarning(rows) {
            belowZero.rows = rows
            belowZero.open()
        }

        /* The controller refused something and said why: an empty cart, a partial
           without a customer, a failed write. Its sentence, not ours. */
        function onRejected(message) {
            root.notify(message, Severity.caution)
        }
    }

    /* pos's 300ms. Reads the field when it fires rather than carrying the text,
       so a burst of keystrokes collapses to one query for the final text. */
    Timer {
        id: debounce
        interval: 300
        onTriggered: root.flushSearch()
    }

    // =====================================================================
    // SHORTCUTS
    // =====================================================================
    /* pos's function keys, and they live on the page rather than on the controls
       that print them: a Shortcut declared inside the rail or a payment hero
       would keep firing while a dialog is on top of it. */
    Shortcut { sequence: "F2"; onActivated: filters.focusSearch() }
    Shortcut { sequence: "F3"; onActivated: root.requestOpen("customer_select", {}) }
    Shortcut { sequence: "F4"; onActivated: root.command("calculator") }
    Shortcut { sequence: "F1"; onActivated: root.command("return") }
    Shortcut { sequence: "F5"; onActivated: root.command("hold") }
    Shortcut { sequence: "F6"; onActivated: root.command("carts") }
    Shortcut {
        sequence: "F8"
        enabled: root.allowPartial
        onActivated: root.startPartial()
    }
    Shortcut { sequence: "F9"; onActivated: root.payCash() }
    Shortcut { sequence: "F12"; onActivated: root.command("void") }

    /* Delete removes the active line â€” unless a text editor has focus, where
       Delete is how you erase a character. Two things wanting the same key is
       normally an ambiguous activation that fires neither; this one is resolved
       by asking what has focus. */
    Shortcut {
        sequence: "Delete"
        enabled: !root.typing
        onActivated: root.askRemove(root.targetRow)
    }

    /* Escape closes the panel, then clears the buffer, then does nothing. It is
       enabled only when it has something to do, so it cannot collide with the
       shell's own Escape â€” two enabled shortcuts on one sequence fire neither. */
    Shortcut {
        sequence: "Escape"
        enabled: root.buffer !== ""
        onActivated: root.dismiss()
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    /* Tighter than a list page's pagePadding: this screen is the one place where
       every pixel spent on margin is a pixel taken from the tile grid, and pos
       uses 12 here for the same reason. */
    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacing.md
        spacing: Tokens.spacing.md

        // -----------------------------------------------------------------
        // products, commands, and the dock under both
        // -----------------------------------------------------------------
        /* The dock spans the grid and the rail but not the cart, which is what
           lets the cart column run the full height of the screen. pos moved it
           here deliberately and explains why in its own header. */
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.md

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.sm

                Rectangle {
                    id: zone
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Fluent.cardBackground
                    radius: Tokens.radius.lg
                    border.width: 1
                    border.color: Fluent.dividerBorder

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.size.cardPadding
                        spacing: Tokens.spacing.sm

                        FilterBar {
                            id: filters
                            Layout.fillWidth: true
                            placeholder: Strings.t("pos.search.placeholder",
                                                   "Scan a barcode, or search by name")


                            onSearchTextChanged: debounce.restart()
                            onAccepted: {
                                /* Enter means now: ask for matches without waiting
                                   out the debounce, then ask whether this was a
                                   code. A scanner's Return arrives faster than
                                   300ms. */
                                root.flushSearch()
                                var code = filters.searchText.trim()
                                if (code !== "" && root.ctrl)
                                    root.ctrl.scan(code)
                            }

                            actionItems: [
                                /* Tiles reloading under a grid that is already
                                   populated. No `running` property: ProgressRing
                                   derives from ProgressBar, which has none, and
                                   assigning a property a type does not have takes
                                   the page down at load. */
                                ProgressRing {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.busy && root.tileCount > 0
                                    indeterminate: true
                                    ringSize: 28
                                    strokeWidth: 3
                                },
                                /* The whole catalogue, listed, when the dropdown is
                                   the wrong shape for the question — a query that
                                   matches eighty products, or a name the operator
                                   only half remembers and wants to scroll for.

                                   A list glyph, not a magnifier: the field beside it
                                   is already the search, so a second magnifier said
                                   "search" twice and never said what this one does,
                                   which is *browse*. The same icon opens the same
                                   list on the stocktake and the stock ledger, so one
                                   shape means one thing everywhere. */
                                IconButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: "ic_fluent_apps_list_20_regular"
                                    glyphSize: Tokens.icon.md
                                    tooltip: Strings.t("selector.open_picker",
                                                       "Browse all products")
                                    onClicked: root.requestOpen("product_select", {})
                                },
                                /*
                                 * ARRANGE THE TILES — AND WHY IT LIVES HERE
                                 *
                                 * It used to be a labelled button in the Products
                                 * page header, which is the wrong screen: it does
                                 * not touch the catalogue at all. It reorders *this*
                                 * grid and this screen's favourites tab, and the
                                 * question it answers — "why is Coca-Cola not the
                                 * first tile?" — is asked while looking at the
                                 * tiles.
                                 *
                                 * NOT IN THE COMMAND RAIL, EITHER. Those five are
                                 * things done to the sale in front of the cashier,
                                 * on 76px cards sized for a thumb mid-transaction.
                                 * Arranging is a setup act performed once a month by
                                 * the owner, and putting it in that column both
                                 * dilutes what the rail means and puts it under the
                                 * thumb of someone ringing up a customer.
                                 *
                                 * This row already means "acts on the grid below":
                                 * it holds the grid's own search and its picker. An
                                 * icon here is one tap from the tiles, and never in
                                 * the way of a sale.
                                 */
                                IconButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.canArrange
                                    glyph: "ic_fluent_grid_20_regular"
                                    glyphSize: Tokens.icon.md
                                    tooltip: Strings.t("products.arrange.action",
                                                       "Arrange tiles")
                                    onClicked: root.requestOpen("products_arrange", {})
                                }
                            ]

                        }

                        CategoryStrip {
                            Layout.fillWidth: true
                            model: root.tabs
                            currentKey: root.activeTab
                            onActivated: (key) => root.selectTab(key)
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            GridView {
                                id: tileGrid
                                anchors.fill: parent
                                clip: true
                                visible: !root.showTileState
                                model: root.ctrl ? root.ctrl.tiles : null

                                /* The grid flows: a wider screen gets more
                                   columns, and the surplus is spread across the
                                   tiles rather than left as a ragged margin.
                                   tileMin is the floor a tile may shrink to, so
                                   this is the largest column count that keeps
                                   every tile at or above it â€” pos pins itself to
                                   four columns and shrinks the tiles instead,
                                   which wastes a 1920px screen. */
                                readonly property int gap: Tokens.spacing.sm
                                readonly property int columns:
                                    Math.max(1, Math.floor((width + gap)
                                                           / (Tokens.size.tileMin + gap)))

                                cellWidth: Math.max(1, Math.floor(width / columns))
                                cellHeight: Tokens.size.tile + gap

                                QC.ScrollBar.vertical: FluentScrollBar {
                                    policy: QC.ScrollBar.AsNeeded
                                }

                                /* A cell, with the tile inset inside it. GridView
                                   has no spacing of its own â€” the gutter has to
                                   come out of the cell, and an even inset on all
                                   four sides is the one version of that which
                                   needs no mirroring. */
                                delegate: Item {
                                    id: cell
                                    width: tileGrid.cellWidth
                                    height: tileGrid.cellHeight

                                    /* `modelData` is what a plain JS array or a
                                       role-less model provides; `model` is what a
                                       role-based one provides. Same idiom as
                                       DataTable, for the same reason. */
                                    readonly property var rowData:
                                        (typeof modelData !== "undefined"
                                         && modelData !== null
                                         && typeof modelData === "object")
                                        ? modelData : model

                                    PosTile {
                                        anchors.fill: parent
                                        anchors.margins: Math.round(tileGrid.gap / 2)

                                        name: cell.rowData ? cell.rowData.name : ""
                                        priceText: cell.rowData ? cell.rowData.price_text : ""
                                        barcode: cell.rowData && cell.rowData.barcode
                                                 ? cell.rowData.barcode : ""
                                        stock: cell.rowData ? cell.rowData.stock : 0
                                        stockText: cell.rowData ? cell.rowData.stock_text : ""
                                        lowStock: cell.rowData
                                                  ? cell.rowData.low_stock === true : false
                                        /* The product's colour, or its category's
                                           â€” the controller decides which, because
                                           almost nobody colours products one at a
                                           time and a wall of white tiles is the
                                           thing colour was meant to fix. */
                                        accent: cell.rowData && cell.rowData.color
                                                ? cell.rowData.color : "transparent"

                                        onClicked: root.pick(cell.rowData)
                                    }
                                }
                            }

                            StateView {
                                anchors.fill: parent
                                visible: root.showTileState
                                variant: root.tileState
                                body: root.tileState === "error"
                                      ? root.errorText
                                      : root.tileState === "empty"
                                        ? Strings.t("pos.tiles.hint",
                                                    "Nothing in this category yet.")
                                        : ""
                                onRetryRequested: root.reload()
                            }

                            /* First load only. Blanking a grid the operator is
                               reading in order to say it is being reread is the
                               wrong trade. */
                            LoadingOverlay {
                                visible: root.busy && root.tileCount === 0
                            }
                        }
                    }
                }

                CommandRail {
                    Layout.fillHeight: true
                    commands: root.commands
                    onTriggered: (key) => root.command(key)
                }
            }

            /*
             * EDIT MODE, SAID OUT LOUD.
             *
             * A till holding a finished invoice looks exactly like a till holding a
             * new sale, and the two commit to different documents — so the one thing
             * this mode must never be is quiet. A full-width indigo bar above the
             * dock names the invoice and offers the way out; the pay hero below turns
             * indigo and reads "Save changes". Two signals, one colour, and no change
             * to where anything is or how it is operated.
             */
            Rectangle {
                Layout.fillWidth: true
                visible: root.editing > 0
                implicitHeight: editRow.implicitHeight + Tokens.spacing.md
                radius: Tokens.radius.md
                color: Tokens.chromeHue.indigo

                RowLayout {
                    id: editRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.spacing.md
                    anchors.rightMargin: Tokens.spacing.sm
                    spacing: Tokens.spacing.sm

                    Icon {
                        icon: "ic_fluent_edit_20_regular"
                        size: Tokens.icon.md
                        color: Tokens.onChrome
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: Strings.t("pos.edit.mode", "Editing an invoice")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            color: Tokens.onChromeMuted
                        }

                        Text {
                            text: "\u200e" + root.editingNumber
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.bodyLarge
                            font.weight: Font.DemiBold
                            color: Tokens.onChrome
                        }
                    }

                    /* The way out, in the bar that announced the mode: an operator who
                       opened the wrong invoice looks for the exit where the warning
                       is, not in a menu. `iconName`, not `glyph` — ChromeButton is
                       the window-chrome button and names its icon differently from
                       the page-level GlyphButton. */
                    ChromeButton {
                        iconName: "ic_fluent_dismiss_20_regular"
                        tip: Strings.t("pos.edit.cancel",
                                       "Leave the invoice as it was")
                        onClicked: if (root.ctrl) root.ctrl.cancelEdit()
                    }
                }
            }

            TotalsDock {
                Layout.fillWidth: true

                cartNumber: root.ctrl ? root.ctrl.cartNumber : ""
                itemsText: root.ctrl ? root.ctrl.itemsText : ""
                qtyText: root.ctrl ? root.ctrl.qtyText : ""
                discountText: root.ctrl ? root.ctrl.discountText : ""
                totalText: root.ctrl ? root.ctrl.totalText : "â€”"
                currencyText: root.ctrl ? root.ctrl.currencyText : ""

                actionItems: [
                    /* Partial first, Cash last: the far edge is where a thumb
                       lands and cash is the common case. pos orders them the same
                       way. Hidden rather than disabled when the setting is off —
                       pos's apply_sale_settings does exactly that, and a
                       permanently dead hero on the dock is furniture.

                       And Partial is COMPACT. Two 180px heroes side by side took a
                       third of the dock to shout two answers at the same volume,
                       when the question has a default: cash. The exception keeps a
                       real target and a label, gives back the width, and stops
                       competing with the figure it is paying. */
                    PayButton {
                        visible: root.allowPartial
                        compact: true
                        text: Strings.t("pos.pay.partial", "Partial")
                        shortcut: "F8"
                        glyph: "ic_fluent_money_hand_20_regular"
                        hue: Tokens.chromeHue.amber
                        enabled: root.cartCount > 0
                        onClicked: root.startPartial()
                    },
                    PayButton {
                        /* The same button in both modes, saying which one it is in.
                           An invoice being corrected is committed by the same
                           gesture that rang it up — that is the whole reason the edit
                           happens here and not on a screen of its own — so what
                           changes is the word and the colour, never the position. */
                        text: root.editing > 0
                              ? Strings.t("pos.edit.save", "Save changes")
                              : Strings.t("pos.pay.cash", "Cash")
                        shortcut: "F9"
                        glyph: root.editing > 0 ? "ic_fluent_save_20_regular"
                                                : "ic_fluent_money_20_regular"
                        hue: root.editing > 0 ? Tokens.chromeHue.indigo
                                              : Tokens.chromeHue.emerald
                        primary: true
                        enabled: root.cartCount > 0
                        onClicked: root.payCash()
                    }
                ]
            }
        }

        // -----------------------------------------------------------------
        // the cart column
        // -----------------------------------------------------------------
        /* Pinned, as it is in pos: minimum and maximum are the same number, so
           the column is exactly as wide as the numpad and a six-figure line total
           need and every remaining pixel goes to the tiles. Tokens.size.cartColumn
           carries the arithmetic. */
        Rectangle {
            Layout.preferredWidth: Tokens.size.cartColumn
            Layout.minimumWidth: Tokens.size.cartColumn
            Layout.maximumWidth: Tokens.size.cartColumn
            Layout.fillHeight: true

            color: Fluent.cardBackground
            radius: Tokens.radius.lg
            border.width: 1
            border.color: Fluent.dividerBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.size.cardPadding
                spacing: Tokens.spacing.sm

                PartyCard {
                    Layout.fillWidth: true
                    active: root.hasCustomer
                    title: root.hasCustomer && root.ctrl
                           ? root.ctrl.customerName
                           : Strings.t("pos.walk_in", "Walk-in customer")
                    subtitle: root.hasCustomer && root.ctrl
                              ? root.ctrl.customerPhone
                              : Strings.t("pos.customer.hint",
                                          "Tap to attach a customer")
                    removeTip: Strings.t("pos.customer.remove", "Remove customer")
                    onClicked: root.requestOpen("customer_select", {})
                    onRemoveRequested: root.removeCustomer()
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: cartView
                        anchors.fill: parent
                        clip: true
                        spacing: Tokens.spacing.xs
                        model: root.ctrl ? root.ctrl.lines : null

                        QC.ScrollBar.vertical: FluentScrollBar {
                            policy: QC.ScrollBar.AsNeeded
                        }

                        delegate: CartLine {
                            id: cartRow

                            readonly property var rowData:
                                (typeof modelData !== "undefined"
                                 && modelData !== null
                                 && typeof modelData === "object")
                                ? modelData : model

                            width: cartView.width

                            name: rowData ? rowData.name : ""
                            priceText: rowData ? rowData.price_text : ""
                            totalText: rowData ? rowData.total_text : ""
                            qtyText: rowData ? rowData.qty_text : ""
                            qty: rowData ? rowData.qty : 0
                            step: rowData && rowData.step ? rowData.step : 1

                            selected: index === root.selectedRow

                            onClicked: root.selectedRow = index
                            onQtyRequested: (value) => root.setQty(index, value)
                            onRemoveRequested: root.askRemove(index)
                        }
                    }

                    StateView {
                        anchors.fill: parent
                        visible: cartView.count === 0
                        variant: "empty"
                        title: Strings.t("pos.cart.empty.title", "Nothing in the cart")
                        body: Strings.t("pos.cart.empty.body",
                                        "Scan a barcode or tap a product to start.")
                    }
                }

                KeypadDisplay {
                    Layout.fillWidth: true
                    text: root.buffer

                    /* The badge says what Apply will do. It used to also say
                       "received" while an inline payment was being confirmed; taking
                       a payment is the PaymentEntry sheet's job now, and this strip
                       has one meaning again. */
                    modeText: Strings.t(root.modeSpec.key, root.modeSpec.fallback)
                    modeGlyph: root.modeSpec.glyph
                    tone: root.modeSpec.tone

                    /* Apply, now the tick at the end of this strip rather than the
                       fourth key of the pad. Dead with an empty buffer: there is
                       nothing to apply, and a live button that does nothing is the
                       thing this app spent a whole pass removing. */
                    actionEnabled: root.buffer !== ""
                    onApplied: root.applyEntry()
                }

                Numpad {
                    id: numpad
                    Layout.fillWidth: true
                    modes: ["qty", "plus", "minus"]
                    activeMode: root.mode
                    onKeyPressed: (key) => root.feed(key)
                    onModeRequested: (mode) => root.mode = mode
                }
            }
        }
    }

    // =====================================================================
    // CONFIRM
    // =====================================================================
    /* Both dialogs state the measure rather than taking their width from the
       dialog: FluentDialog sizes itself from its content, so a wrapping Text that
       reads the dialog's width closes a binding loop. ProductsPage's header
       explains the arithmetic. */
    FluentDialog {
        id: confirmRemove

        property int row: -1
        property string lineName: ""
        readonly property int measure: 420

        modal: true
        title: Strings.t("confirm.delete_row.title", "Remove this line?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (root.ctrl) root.ctrl.remove(confirmRemove.row)

        contentItem: Column {
            spacing: Tokens.spacing.sm

            Text {
                width: confirmRemove.measure
                text: Strings.t("confirm.delete_row.body",
                                "It will be taken off this sale.")
                wrapMode: Text.WordWrap
                color: Fluent.textPrimary
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
            }

            /* The name on its own line rather than inside the question: a product
               called "500 g" is ambiguous in a sentence and unambiguous here, and
               the catalogue string needs no placeholder to be mistranslated. */
            Text {
                width: confirmRemove.measure
                text: confirmRemove.lineName
                visible: text !== ""
                wrapMode: Text.WordWrap
                color: Fluent.textPrimary
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
            }
        }
    }

    FluentDialog {
        id: confirmVoid
        readonly property int measure: 420

        modal: true
        title: Strings.t("confirm.empty_cart.title", "Void this sale?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: {
            root.dismiss()
            root.selectedRow = -1
            if (root.ctrl)
                root.ctrl.clear()
        }

        contentItem: Text {
            width: confirmVoid.measure
            text: Strings.t("confirm.empty_cart.body",
                            "Every line is removed and the customer is cleared.")
            wrapMode: Text.WordWrap
            color: Fluent.textPrimary
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
        }
    }

    /* After the money, never before it. */
    FluentDialog {
        id: belowZero

        property var rows: []
        readonly property int measure: 480

        modal: true
        title: Strings.t("negstock.title", "Negative stock")
        standardButtons: QC.Dialog.Ok

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.sm

            Text {
                Layout.preferredWidth: belowZero.measure
                Layout.fillWidth: true
                text: Strings.t("negstock.body",
                                "The sale was completed, but stock went below zero for:")
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }

            Repeater {
                model: belowZero.rows

                delegate: RowLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.md

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        font.weight: Font.DemiBold
                        color: Fluent.textPrimary
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "\u200e" + Strings.tf("negstock.remaining",
                                                    "remaining {stock}",
                                                    { stock: modelData.after_text })
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        font.weight: Font.DemiBold
                        color: Tokens.danger
                    }
                }
            }
        }
    }

    // =====================================================================
    // FEEDBACK
    // =====================================================================
    /* A host, not a Toast: the control destroys itself when it closes, so one
       declared here would serve exactly one message. Raised clear of the dock,
       which is 180px of the bottom of this screen. */
    ToastHost {
        id: toast
        bottomMargin: Tokens.size.dock + Tokens.spacing.xl
    }

    /*
     * The matches, as a dropdown over the tiles.
     *
     * WHY A DROPDOWN AND NOT TILES
     *
     * Typing used to rebuild the tile wall from the results. That
     * conflated two different things: the wall is a layout the
     * operator has learned â€” the same product in the same place
     * every time, which is the entire reason the arrange screen
     * exists â€” and a result list is a transient answer to a
     * question. Overwriting the first with the second cost the
     * muscle memory and left the category chip lying about what
     * was on screen.
     *
     * WHY IT IS A POPUP AND NOT AN INLINE PANEL
     *
     * It has to be able to cover the tiles. An inline row would
     * either push the grid down as it grew, moving every tile
     * while the operator is aiming at one, or need a fixed height
     * reserved whether or not anything is being searched.
     *
     * `closePolicy: NoAutoClose` because the field keeps focus
     * while this is open â€” every keystroke goes to the search
     * box, and a popup that closes on the first key press is a
     * popup that never opens.
     */
    QC.Popup {
        id: matches

        /* Anchored under the field rather than the bar: the bar
           also holds the picker button, and the list belongs to
           the thing being typed into. */
        parent: filters
        x: 0
        y: filters.height + Tokens.spacing.xs
        width: filters.width
        /*
         * Sized from the MODEL, not from the list's contentHeight.
         *
         * Reading `list.contentHeight` here is circular: the content is a child of
         * the popup, so it is not laid out until the popup opens, and the popup
         * cannot open at a sensible height until the content is laid out. It
         * resolves eventually, but "eventually" showed up as a 12px sliver instead
         * of a dropdown. The row count is known before any of that, and the row
         * height is a token, so this needs neither.
         *
         * Snapped to whole rows for the same reason: a sixth row sliced through the
         * middle reads as a rendering fault rather than as "there is more, scroll".
         */
        implicitHeight: Math.min(root.searchRows, root.results.length)
                        * Tokens.size.tableRow + 2 * Tokens.spacing.xs

        padding: Tokens.spacing.xs
        modal: false
        focus: false
        closePolicy: QC.Popup.NoAutoClose
        visible: root.search !== "" && root.results.length > 0

        background: Rectangle {
            color: Fluent.popupBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder
        }

        contentItem: ListView {
            id: list
            clip: true
            model: root.results
            boundsBehavior: Flickable.StopAtBounds

            QC.ScrollBar.vertical: FluentScrollBar { }

            delegate: Rectangle {
                id: hit

                required property var modelData
                required property int index

                width: list.width
                height: Tokens.size.tableRow
                radius: Tokens.radius.sm
                color: rowHover.hovered ? Fluent.subtleSecondary
                                        : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacing.sm
                    anchors.rightMargin: Tokens.spacing.sm
                    spacing: Tokens.spacing.sm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                            text: hit.modelData.name
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: hit.modelData.stock > 0
                                   ? Fluent.textPrimary
                                   : Fluent.textTertiary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            horizontalAlignment: Text.AlignLeft
                            /* The barcode is why a partial code
                               typed by hand finds anything, so it
                               is worth showing which one matched.
                               The category comes second because
                               two products often share a name. */
                            text: {
                                var parts = []
                                if (hit.modelData.barcode !== "")
                                    parts.push("\u200e" + hit.modelData.barcode)
                                if (hit.modelData.category !== "")
                                    parts.push(hit.modelData.category)
                                return parts.join("  آ·  ")
                            }
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            color: Fluent.textTertiary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    /* Not on the tile wall. Said here because
                       this list is the only place in the app
                       that finds those on purpose, and an
                       operator who cannot see why a product is
                       missing from the grid deserves the
                       answer. */
                    Tag {
                        Layout.alignment: Qt.AlignVCenter
                        visible: hit.modelData.hidden === true
                        label: Strings.t("products.hidden_on_pos",
                                         "Hidden on the till")
                        tone: "warning"
                    }

                    Tag {
                        Layout.alignment: Qt.AlignVCenter
                        visible: hit.modelData.stock <= 0
                        label: Strings.t("pos.tile.out_of_stock",
                                         "Out of stock")
                        tone: "danger"
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: "\u200e" + hit.modelData.stock_text
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Fluent.textSecondary
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.minimumWidth: 110
                        horizontalAlignment: Text.AlignRight
                        text: "\u200e" + hit.modelData.price_text
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        font.weight: Font.DemiBold
                        color: Fluent.textPrimary
                    }
                }

                HoverHandler { id: rowHover }

                TapHandler {
                    onTapped: root.take(hit.modelData)
                }
            }
        }
    }

    // =====================================================================
    // THE PARTIAL PAYMENT
    // =====================================================================
    /*
     * The shared payment sheet, told what this cart is worth and what the customer
     * already owes. It owns the keypad and the "left after this" figure; this page owns
     * only what to do with the answer.
     *
     * `allowZero` is on because nothing paid is a real answer at a till: it is a debt
     * sale, and Python decides that from the amount rather than from a separate button.
     */
    PaymentEntry {
        id: payment

        heading: Strings.t("pos.partial.title", "Part payment")
        due: root.ctrl ? root.ctrl.total : 0
        allowZero: true
        confirmText: Strings.t("action.confirm", "Confirm")

        facts: {
            var out = []
            if (root.hasCustomer && root.ctrl && root.ctrl.customerDebt > 0)
                out.push({
                    label: Strings.tf("pos.customer_owes", "{name} already owes",
                                      { name: root.ctrl.customerName }),
                    value: root.ctrl.moneyText(root.ctrl.customerDebt),
                    tone: "danger"
                })
            out.push({
                label: Strings.t("pos.partial.this_sale", "This sale"),
                value: root.ctrl ? root.ctrl.totalText : "",
                tone: ""
            })
            return out
        }

        onAccepted: (amount) => {
            if (!root.ctrl)
                return
            /* The split between cash, partial and full debt is Python's: it has the
               amounts, the customer and the settings, and it refuses through
               rejected() with a sentence rather than leaving the page to guess. */
            root.ctrl.setPaid(amount)
            root.ctrl.payPartial()
        }
    }
}
