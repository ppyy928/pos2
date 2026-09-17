import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Window
import FluentControls
import Mizan

/*
 * The till, in two storeys: find it, ring it — then, under everything,
 * take the money.
 *
 *   ┌ MIZAN POS  [＋Customer][＋Product F10][▦Arrange][↻F7][▥Labels F11] ─ ▢ ✕ ┐
 *   ├────────┬──────────────────────────────────────────────────────────┤
 *   │        │ [ Search products or scan a barcode… ]                  │
 *   │  navy  │ ‹ [★ Favourites] [• Drinks] [• Bakery] … ›              │
 *   │  rail  │ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐    │
 *   │        │ │▓ Coca-Cola 1.5L│ │▓ Fanta       │ │▓ Water        │    │
 *   │        │ │▓ 120 DA St 24 │ │▓ 120 DA St 12│ │▓ 60 DA  St 8  │    │
 *   │        │ └───────────────┘ └───────────────┘ └───────────────┘    │
 *   │        │ [Hold][Suspended][Return][Calc][Clear cart]             │
 *   │        │                                  │ ┌────────────────────┐│
 *   │        │                                  │ │ Walk-in customer ▾ ││
 *   │        │                                  │ │ Coca-Cola 1.5L      ││
 *   │        │                                  │ │      120 [− 2 +] 240││
 *   │        │                                  │ │ … (scrolls)        ││
 *   │        │                                  │ │ 6133            ➜   ││
 *   │        │                                  │ │ [ −  ][ 7 ][ 8 ][ 9]││
 *   │        │                                  │ │ [#Qty][ 4 ][ 5 ][ 6]││
 *   │        │                                  │ │ [ +  ][ 1 ][ 2 ][ 3]││
 *   │        │                                  │ │ [ C  ][ 0 ][ . ][ ⌫]││
 *   │        │                                  │ └────────────────────┘│
 *   │        │ ┌──────────────────────────────────────────────────────┐│
 *   │        │ │ TOTAL  Items 3 · Qty 5   12 480 DA │[Debt·F8][Cash·F9]││
 *   │        │ └──────────────────────────────────────────────────────┘│
 *   └────────┴──────────────────────────────────────────────────────────┘
 *
 * THE REGIONS
 *
 * The navy rail is the shell's. The page's own actions — a new customer, a new
 * product, arranging the tiles, reloading the wall, the label sheet — ride in
 * the WINDOW'S TITLE BAR row, next to the app's name (see `titleActions` and
 * TitleAction): chrome that exists on every screen, at a height the page pays
 * for anyway. They were a second full-width row under that bar for one round —
 * the row was honest and cost a till screen 56px of products to say five
 * words. The workspace is the cool grey the white cards and the white search
 * field sit on, and it carries the sale's maintenance toolbar at its foot,
 * UNDER the tiles — hold, suspended carts, return, calculator, clear cart:
 * things done AROUND a sale rather than as part of ringing one, so they live
 * where the eye that wants them is already looking, and none of them spends a
 * pixel of the panel. The transaction panel is ONE white surface holding the
 * sale itself — who it is for, the cart, the numeric entry — pinned at
 * Tokens.size.cartColumn, the cart filling every pixel above the keypad and
 * scrolling inside the panel with nothing between the keypad and the money
 * below it. The money — the total and the two ways to take it — is the
 * full-width bar across the foot of the page, under the products and the
 * cart both.
 *
 * THE PERMANENT KEYPAD
 *
 * The merchant's rule, restored: the numeric keypad never leaves the screen.
 * It is the input device for a till without a keyboard and the fast path for
 * one with one — a mode column beside the digits: [# Qty] the quantity for
 * the selected line, [+] and [−] the free money lines (a charge added to
 * the total, a cart-level discount subtracted from it) and [C] the whole
 * entry gone in one tap — solid crimson, the one destructive key on the pad.
 * Plus and minus are glyphs alone — an icon that is already a plus needs no
 * word under it — and the highlighted key is the mode the typed number will
 * take. The readout above the pad is one line: the number and the commit
 * arrow, nothing else. A physical keyboard works alongside the pad:
 * quantities in the row's own field, codes in the search box, and the
 * application-wide scanner burst needs no keypad at all.
 *
 * SECONDARY ACTIONS, IN WORDS
 *
 * Hold, suspended carts, return, calculator, and — separated by treatment,
 * because it is the destructive one — clear cart. Every one of them is a
 * labelled button with an icon a hand can find and a shortcut a keyboard
 * can use — never a row of unexplained glyphs. They sit in one compact
 * toolbar at the foot of the product wall — the products side's own bottom
 * edge, mirroring the payment bar's place under the whole page — where the
 * wall can spare the height and the panel cannot: the cart column keeps
 * its clean run down to its own two decisions, Debt and Cash. Each action
 * also carries its meaning in colour: hold in amber, suspended in teal,
 * return in violet, clear cart in pale red — the same ink/tint pairs the
 * rest of the app uses for those meanings, so the row reads as one group
 * of controls that differ where the acts differ.
 *
 * DEBT AND CASH, SIDE BY SIDE, UNDER EVERYTHING
 *
 * The row the merchant drew, in the order they asked for: the dark petrol
 * total taking the flexible width at the leading side, then Debt — the
 * secondary question, a tinted surface with the payment glyph at a fixed
 * comfortable width, opening the payment sheet EMPTY, for the "less than
 * the whole amount" question — then Cash on the trailing edge, the primary
 * emerald, wider than Debt, opening the same sheet SEEDED with the whole
 * total, so the ordinary cash sale is Cash, Enter, with the money
 * confirmed on screen before it is recorded. One bar, one decision, two
 * ways to answer it, spanning the foot of the page.
 *
 * WHAT app.pos HAS TO PROVIDE
 *
 *   read      busy, error, tiles, categories, lines,
 *             cartNumber, totalText, currencyText, itemsText, qtyText,
 *             discountText, customerName, customerPhone, hasCustomer,
 *             customerDebt, remainingText, paid, paidText, paidValid,
 *             allowPartial, allowDebt, imageCards, warnStock
 *   call      loadCategories(), loadTiles(tab), add(productId),
 *             addAnyway(productId), setQty(row, qty), setQtyAnyway(row, qty),
 *             remove(row), clear(), hold(), scan(code),
 *             setCustomer(customerId), setPaid(amount), payCash(),
 *             payPartial(), cancelEdit(), reloadPreferences(),
 *             setWarnStock(on)
 *   emits     invalidated(), lineTouched(row), resolved(text, added),
 *             scanMissed(code, barcode), saleFinished(number),
 *             stockBlocked(info), stockWarning(rows), rejected(message)
 *
 * A `tiles` row is {id, name, price_text, stock, stock_text, low_stock, color,
 * barcode, image}; a `lines` row is {name, qty, qty_text, price_text,
 * total_text, step}. Both read through the same `rowData` idiom DataTable
 * uses, so either a JS array or a role-based model works.
 *
 * THE TWO QUESTIONS ASKED OF A TYPED STRING
 *
 * A scanner burst or an Enter in the search box goes through `scan(code)`:
 * is this a barcode? If so, add it; if not, offer to create it. Digits for a
 * quantity go into the row's own field or the keypad, and the buffer always
 * names what it will change before it changes it.
 *
 * WHAT IS DELIBERATELY NOT HERE
 *
 * Return is a routed workflow (F1), not a mode this page enters — it opens
 * the sale selector over the screen and answers by creating a return, which
 * is the shape the sales module already owns. There is no "return mode"
 * state to draw, for the same reason.
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

    /* The customer list the panel's dropdown chooses from — the accounts
       controller, not the till: the till holds the ONE customer attached to this
       sale and knows nothing about the other three thousand. */
    readonly property var customers: (typeof app !== "undefined" && app)
                                     ? app.customers : null

    // =====================================================================
    // VIEW STATE — everything pos keeps on the page that is not money
    // =====================================================================
    /* "favorites", or a category id. Never null once the categories have
       arrived; null before that means "nothing to load yet". */
    property var activeTab: null

    property string search: ""

    /* -1 is "nothing chosen", not "row 0". */
    property int selectedRow: -1

    /* True from the press on the add button beside the customer field until the
       customer that press is making comes back. `saved` is emitted for every
       customer written anywhere in the app, so the gate is what keeps an
       unrelated write from landing on this sale. */
    property bool awaitingNewCustomer: false

    // =====================================================================
    // DERIVED
    // =====================================================================
    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property bool allowPartial: ctrl ? ctrl.allowPartial : true
    readonly property bool allowDebt: ctrl ? ctrl.allowDebt : true
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

    /* The permission the picker dialog was routed behind. Attaching a customer means
       reading the customer list, and moving that list from a routed dialog onto the
       till must not hand it to somebody the router would have refused — the defaults
       give every till role customers.view, but the permissions are per employee and
       an admin can take it away. Dimmed rather than hidden: a card that vanishes
       moves the cart up by 48px for one operator and not another.

       `session.revision` first, for canArrange's reason: can() is a slot, so a
       binding that only calls it never re-evaluates. */
    readonly property bool canPickCustomer: session
                                            && session.revision >= 0
                                            && session.can("customers.view")

    /* Whether the add button beside the customer field may be pressed: the same
       `customers.manage` the router checks on `customer_edit`, asked here so the
       button answers with a dim rather than a form whose Save would be refused.
       session.revision first, for canPickCustomer's reason. */
    readonly property bool canAddCustomer: session
                                           && session.revision >= 0
                                           && session.can("customers.manage")

    /* Whether the shelf question may offer to fix the shelf. Same right the
       `stock_adjust` workflow is routed behind, asked here so the button is absent
       for a cashier rather than present and answered with a refusal. It is the same
       expression as `canArrange` and deliberately not an alias of it: they are two
       different questions that happen to share a permission today, and one of them
       moving would silently move the other. */
    readonly property bool canAdjustStock: session
                                           && session.revision >= 0
                                           && session.can("products.manage")

    /* Whether the add-product shortcut may be pressed: the same `products.view`
       the router checks on `product_form` (the form's own Save asks for more),
       asked here so the chip is absent rather than present-and-refused. */
    readonly property bool canAddProduct: session
                                          && session.revision >= 0
                                          && session.can("products.view")

    /*
     * THE ACTIONS THIS PAGE LENDS THE WINDOW'S TITLE BAR.
     *
     * Five chips, in the order the operator reaches for them: a new customer,
     * a new product, arranging the tiles, reloading the wall, the label sheet.
     * They ride IN the title bar row — see TitleAction's header — because the
     * alternative was a second full-width row of chrome under it, and this
     * screen is a till: 56px of vertical space is a row of products.
     *
     * The descriptors are data, not buttons: the shell draws them (Main.qml)
     * and calls back into `titleAction(id)` below, so this page owns what each
     * action MEANS and the shell only owns where it sits. `visible`/`enabled`
     * travel with each one for the same reason the old row hid them — a
     * button that opens a door only to be refused at it is worse than no
     * button, and the permission is known here, not there.
     *
     * Nothing here repeats the command toolbar at the foot: hold, suspended,
     * return, calculator and clear cart act on the sale in front of the
     * operator, and those stay there. This list is everything else. */
    readonly property var titleActions: [
        {
            id: "customer",
            glyph: "ic_fluent_person_add_20_regular",
            label: Strings.t("customers.add", "New customer"),
            visible: root.canAddCustomer,
            enabled: root.canAddCustomer
        },
        {
            id: "product",
            glyph: "ic_fluent_add_20_regular",
            label: Strings.t("products.add", "Add product"),
            /* F10 was free the moment the reprint chip left this bar: the
               key now opens the new-product form. */
            shortcut: "F10",
            visible: root.canAddProduct,
            enabled: root.canAddProduct
        },
        {
            id: "arrange",
            glyph: "ic_fluent_grid_20_regular",
            label: Strings.t("products.arrange.action", "Arrange tiles"),
            visible: root.canArrange,
            enabled: root.canArrange
        },
        {
            id: "refresh",
            glyph: "ic_fluent_arrow_sync_20_regular",
            label: Strings.t("pos.action.refresh", "Refresh products"),
            shortcut: "F7"
        },
        {
            id: "labels",
            glyph: "ic_fluent_barcode_scanner_20_regular",
            label: Strings.t("products.hdr.barcode", "Barcode labels"),
            shortcut: "F11"
        }
    ]

    /* What one of the title bar's actions does. Switched on the ids above,
       because the shell hands back the descriptor's own id and nothing else —
       a signal would need a signal per action, and five signals for five
       buttons is five chances to forget one. */
    function titleAction(id) {
        if (id === "customer")
            root.newCustomer()
        else if (id === "product")
            root.requestOpen("product_form", {})
        else if (id === "arrange")
            root.requestOpen("products_arrange", {})
        else if (id === "refresh")
            root.reload()
        else if (id === "labels")
            root.requestOpen("barcode_labels", {})
    }

    /* Counted off the controller's list rather than a view: there are two
       cart views on this page (one per checkout arrangement), and the count
       must be one number that never depends on which is on screen. */
    readonly property int cartCount: {
        var lines = ctrl ? ctrl.lines : null
        return lines !== null ? lines.length : 0
    }
    readonly property int tileCount: tileGrid.count

    /* Do the cards carry a photo?
     *
     * The controller's answer, for the whole grid at once: the shop's
     * `ui.product_images` switch AND at least one photo in the catalogue. One
     * flag for every card in the grid, because a GridView has one cell size —
     * see PosTile's own header. A product with no photo of its own still gets
     * a photo card here, with the placeholder in it. */
    readonly property bool imageCards: ctrl ? ctrl.imageCards === true : false

    /* THE RAIL'S WIDTH, TAKEN OUT OF THE WALL'S ARITHMETIC.
     *
     * The nav rail is the one piece of chrome that changes this page's width
     * without the window changing — 224px expanded, 68px collapsed — and a
     * tile count that followed the page width would move a product a column
     * over every time the rail opened or closed. Muscle memory is the only
     * layout a till really has, so the count must not hear the toggle.
     *
     * Measured, not assumed: the rail's CURRENT width is the gap between
     * this page and the window's edge — from the left in LTR, from the right
     * in RTL, and `max` of the two reads the same number in both (the other
     * side is zero). What collapsing freed is `navExpanded - railNow`, never
     * negative, and the wall SUBTRACTS it: the figure below is the width the
     * page has with the rail EXPANDED — the narrower case — whatever the
     * rail is doing. With the rail expanded it is exactly zero and nothing
     * changes; collapsed, the width the rail gave back comes straight off,
     * and the freed space lands in the gutter instead of a fifth card.
     *
     * A genuine window resize moves the page AND the window together, and
     * the count follows it. */
    readonly property real railSlack: {
        /* `mine` is named BEFORE the mapping for a reason: mapToItem() reads
           positions through C++ accessors, which the binding engine does not
           watch — a binding built only on them never notices the rail moving.
           This page's own width DOES change when the rail collapses, and
           naming it here is what re-runs the arithmetic. The mapping is then
           read fresh, in the same layout pass the width changed in. */
        var mine = width
        var winW = Window.width
        if (winW <= 0 || mine <= 0)
            return 0
        var railNow = Math.max(mapToItem(null, 0, 0).x,
                               winW - mapToItem(null, mine, 0).x)
        return Math.max(0, Tokens.size.navExpanded - railNow)
    }

    /* Matches for the dropdown. Not tiles: this list can contain products the tile
       wall never shows, because a search means the whole catalogue. */
    readonly property var results: ctrl ? ctrl.results : []

    /* Rows the dropdown shows before it starts scrolling. Till.SEARCH_LIMIT caps
       what comes back at twelve; this caps what is on screen at once. */
    readonly property int searchRows: 6

    /* A one-word pill, for the two things a search result can be that a tile never
       is: out of stock, or kept off the tile wall entirely. Built from the same
       parts as PosTile's own stock pill (Tokens.toneFill on the outside,
       Tokens.toneInk on the text) so the two read as the same object — there is no
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

    /*
     * A SALE ACTION, AS A TOOLBAR KEY.
     *
     * The merchant's rule held wherever the actions live: every one of them
     * is a labelled button with an icon a hand can find and a shortcut a
     * keyboard can use — never a row of unexplained glyphs. They left the
     * transaction panel for a compact toolbar under the categories, so they
     * are one line now — icon, label, shortcut at the trailing edge — sized
     * to their content rather than stretched across the zone: a toolbar of
     * five equal benches would be a second category strip, and the wall
     * below is what the width is for.
     *
     * THE COLOUR IS THE MEANING, NOT THE DECORATION
     *
     * `tone` picks one of the app's semantic ink/tint pairs, the same ones
     * badges and pills already use, so a row of these reads as one Fluent
     * control group whose members differ exactly where the acts differ:
     *   hold       amber  — money paused on one side of the counter
     *   suspended  teal   — stored, waiting to be taken back up
     *   return     violet — goods moving the other way
     *   calculator ""     — a utility, the quiet white tile
     * Destructive (Clear cart) is the pale red surface with red ink — the one
     * action on this row that throws work away is the one that looks like it.
     * Every pair is the tone table's own, so contrast is the table's problem
     * and stays solved.
     */
    component ActionButton: T.AbstractButton {
        id: act

        property string glyph: ""
        property string label: ""
        property string shortcut: ""
        property string tone: ""
        property bool destructive: false

        /* The tone's ink and fill. An unknown tone is neutral on purpose —
           a name nobody maps is quiet, not broken. */
        readonly property color ink: !act.enabled ? Fluent.textDisabled
                                : act.destructive ? Tokens.danger
                                : act.tone === "warning" ? Tokens.warning
                                : act.tone === "info" ? Tokens.info
                                : act.tone === "violet" ? Tokens.hue.violet
                                : Fluent.textPrimary
        readonly property color fill: act.tone === "warning" ? Tokens.tint.amber
                                : act.tone === "info" ? Tokens.tint.teal
                                : act.tone === "violet" ? Tokens.tint.violet
                                : Tokens.workspace.surface

        /* A command height, not a chrome-only tool's: the merchant asked
           for buttons a hand can land on — 56, the app's command height
           (`actionKey`), with roomier side padding than a chip and a glyph
           at the medium size so the icon carries the meaning at a glance
           from standing height too. */
        implicitHeight: Tokens.size.actionKey
        /* The width is declared, not hoped for: a bare T.AbstractButton in
           a positioner does not reliably grow to a Layout contentItem's
           implicit size (it resolves during the layout pass, after the
           positioner has already asked). Binding to the RowLayout's own
           implicit size hands the Flow a real number in the pass it asks;
           contentItem.implicitWidth does not depend on this button's
           width, so the binding cannot loop. */
        implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
        leftPadding: Tokens.spacing.md
        rightPadding: Tokens.spacing.md
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus

        Accessible.role: Accessible.Button
        Accessible.name: label + (shortcut !== "" ? " (" + shortcut + ")" : "")

        background: Rectangle {
            radius: Tokens.radius.md
            /* Destructive keeps its own tinted fill; the tonal actions hold
               their fill at rest and deepen it through hover and press, the
               same shape of feedback the neutral tile's greys give. */
            color: !act.enabled
                   ? Fluent.subtleSecondary
                   : act.destructive
                     ? (act.down ? Qt.darker(Tokens.dangerTint, 1.06)
                        : act.hovered ? Qt.lighter(Tokens.dangerTint, 1.03)
                                      : Tokens.dangerTint)
                     : act.tone !== ""
                       ? (act.down ? Qt.darker(act.fill, 1.05)
                          : act.hovered ? Qt.darker(act.fill, 1.02)
                                        : act.fill)
                       : act.down ? Fluent.subtleTertiary
                       : act.hovered ? Fluent.subtleSecondary
                                     : Tokens.workspace.surface
            border.width: 1
            border.color: !act.enabled ? Fluent.dividerBorder
                         : act.destructive
                           ? Qt.rgba(Tokens.danger.r, Tokens.danger.g,
                                     Tokens.danger.b, 0.45)
                         : act.tone !== ""
                           ? Qt.rgba(act.ink.r, act.ink.g, act.ink.b, 0.30)
                         : act.hovered ? Fluent.controlBorderStrong
                                       : Tokens.workspace.border

            Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }
            Behavior on border.color { ColorAnimation { duration: Fluent.anim.appearance } }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                color: "transparent"
                border.width: 2
                border.color: act.destructive ? Tokens.danger : Tokens.brand
                visible: act.visualFocus
            }
        }

        contentItem: RowLayout {
            spacing: Tokens.spacing.xs

            Icon {
                Layout.alignment: Qt.AlignVCenter
                icon: act.glyph
                size: Tokens.icon.md
                color: act.ink
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: act.label
                font.family: Tokens.font.family
                /* body, not caption: the toolbar grew to command height and
                   the word grew with it — a label an arm's length away has
                   to be read without leaning in. */
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: act.ink
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }

            /* The shortcut, trailing: the key under the hand that has a
               keyboard. Always shown — an enabled/disabled width jump is
               its own flicker, and a greyed Hold with no "F5" is a button
               that forgot how it is reached. */
            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: act.shortcut !== ""
                text: act.shortcut
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.letterSpacing: 0.6
                color: !act.enabled ? Fluent.textDisabled
                     : act.destructive ? Qt.rgba(Tokens.danger.r, Tokens.danger.g,
                                                 Tokens.danger.b, 0.8)
                     : act.tone !== ""
                       ? Qt.rgba(act.ink.r, act.ink.g, act.ink.b, 0.75)
                       : Tokens.workspace.textSub
            }
        }
    }

    /*
     * THE PRIMARY PAYMENT — CASH.
     *
     * The emerald fill with white ink and the payment glyph, at command
     * height. It takes the majority of the row and sits on the trailing
     * side: the row is read in the order the decision is made — the
     * exception on the left, the ordinary sale on the right, at the end of
     * the panel where the total above it already put the eye.
     */
    component CashButton: T.AbstractButton {
        id: cash

        /* A label, not a key binding: shadowing the inherited QKeySequence
           `shortcut` with a string is what keeps "F9" printed on the button
           from also re-firing it when the page's own F9 Shortcut already
           did — the old CheckoutButton made the same choice. */
        property string shortcut: ""

        implicitHeight: Tokens.size.payRow
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus

        Accessible.role: Accessible.Button
        Accessible.name: text

        background: Rectangle {
            radius: Tokens.radius.md
            /* Tokens.disabledFill, not the style's missing
                controlFillDisabled — see Tokens' own note. An empty cart must
                show a button that looks inert, not an active green one. */
            color: !cash.enabled ? Tokens.disabledFill
                   : cash.down ? Tokens.brandPressed
                   : cash.hovered ? Tokens.brandHover
                   : Tokens.brand
            Behavior on color {
                ColorAnimation { duration: Fluent.anim.appearance }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: parent.radius + 3
                color: "transparent"
                border.width: 2
                border.color: Tokens.brand
                visible: cash.visualFocus
            }
        }

        /* CENTRED, NOT EDGE-ALIGNED: the primary's whole width is one
           gesture, so the word sits in the middle of it with the key
           badge inboard of the glyph — a single object that reads at a
           glance, rather than a row of parts pushed to the edges. */
        contentItem: RowLayout {
            spacing: Tokens.spacing.sm

            Item { Layout.fillWidth: true }

            Icon {
                Layout.alignment: Qt.AlignVCenter
                icon: "ic_fluent_money_20_regular"
                size: Tokens.icon.md
                color: cash.enabled ? Tokens.onBrand : Fluent.textDisabled
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: cash.text
                /* bodyLarge at Black weight: the primary of the whole
                   screen, set in emerald — the bar grew to 84px for exactly
                   this kind of presence, so the word keeps its seat at the
                   larger of the body sizes. */
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.Black
                color: cash.enabled ? Tokens.onBrand : Fluent.textDisabled
            }

            /* The key as a badge — a keycap, the shape a keyboard's F9
               already has, in the on-brand ink at low strength. */
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: cash.shortcut !== "" && cash.enabled
                implicitWidth: keyText.implicitWidth + 2 * Tokens.spacing.xs
                implicitHeight: keyText.implicitHeight + 2 * (Tokens.spacing.xs - 2)
                radius: Tokens.radius.sm
                color: Qt.rgba(Tokens.onBrand.r, Tokens.onBrand.g,
                               Tokens.onBrand.b, 0.16)

                Text {
                    id: keyText
                    anchors.centerIn: parent
                    text: cash.shortcut
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    font.letterSpacing: 0.8
                    color: Tokens.onBrand
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    /*
     * THE SECONDARY PAYMENT — DEBT.
     *
     * The "less than the whole amount" door into the payment sheet, and it
     * is a button, not a text link. The merchant's verdict on the old grey
     * ghost was plain — it did not look like a decision — so it wears the
     * amber the whole app already means by "money owed": the warning tone's
     * own fill and ink, the same pair Hold's toolbar button uses, so the
     * two money questions on the bar are told apart by colour before a
     * word of either is read. The label is one word — "Debt", in every
     * language short enough never to elide — and the command underneath is
     * unchanged: the same sheet Cash opens, seeded empty, the same F8, the
     * same Python that decides what was paid and what is owed.
     */
    component DebtButton: T.AbstractButton {
        id: debt

        /* For CashButton's reason: a printed hint, never a second binding. */
        property string shortcut: ""

        implicitHeight: Tokens.size.payRow
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus

        Accessible.role: Accessible.Button
        Accessible.name: text

        background: Rectangle {
            radius: Tokens.radius.md
            /* The warning tone's own tint, held at rest and deepened
               through hover and press — the same shape of feedback the
               toolbar's tonal buttons give, one row up. */
            color: !debt.enabled ? Fluent.subtleSecondary
                   : debt.down ? Qt.darker(Tokens.tint.amber, 1.06)
                   : debt.hovered ? Qt.darker(Tokens.tint.amber, 1.02)
                                  : Tokens.tint.amber
            border.width: 1
            border.color: !debt.enabled ? Fluent.dividerBorder
                         : Qt.rgba(Tokens.warning.r, Tokens.warning.g,
                                   Tokens.warning.b, 0.45)

            Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }
            Behavior on border.color { ColorAnimation { duration: Fluent.anim.appearance } }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                color: "transparent"
                border.width: 2
                border.color: Tokens.warning
                visible: debt.visualFocus
            }
        }

        /* Centred, for Cash's reason: one decision, one object. */
        contentItem: RowLayout {
            spacing: Tokens.spacing.sm

            Item { Layout.fillWidth: true }

            Icon {
                Layout.alignment: Qt.AlignVCenter
                icon: "ic_fluent_payment_20_regular"
                size: Tokens.icon.md
                color: debt.enabled ? Tokens.warning : Fluent.textDisabled
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: debt.text
                font.family: Tokens.font.family
                /* bodyLarge beside Cash's bodyLarge: the two questions on
                   the bar are one pair and read at one size — the primary's
                   extra weight is the whole of their hierarchy. */
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.DemiBold
                color: debt.enabled ? Tokens.warning : Fluent.textDisabled
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: debt.shortcut !== "" && debt.enabled
                implicitWidth: debtKeyText.implicitWidth + 2 * Tokens.spacing.xs
                implicitHeight: debtKeyText.implicitHeight
                                 + 2 * (Tokens.spacing.xs - 2)
                radius: Tokens.radius.sm
                color: Qt.rgba(Tokens.warning.r, Tokens.warning.g,
                               Tokens.warning.b, 0.12)

                Text {
                    id: debtKeyText
                    anchors.centerIn: parent
                    text: debt.shortcut
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    font.letterSpacing: 0.8
                    color: Qt.rgba(Tokens.warning.r, Tokens.warning.g,
                                   Tokens.warning.b, 0.9)
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    /*
     * THE CART, one arrangement-agnostic region.
     *
     * Owns the view, the empty state, and the scroll-to-line behaviour: a
     * line that was just added or scanned becomes the selected line and is
     * scrolled to, from inside whichever instance is on screen.
     */
    component CartArea: Item {
        id: area

        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
            id: view
            anchors.fill: parent
            clip: true
            /* No view-level right margin: a ListView's own margin moves the
               view and its rows together, so the Fluent overlay bar still
               widened ONTO the rows' trailing figures. The seat is spent by
               the rows instead (CartLine's trailing margin carries
               Tokens.size.scrollSeat), and the bar glides over clear sheet.
               Zero spacing: the rows draw their own hairline separators, so
               the list is as tall as the rows it shows — five lines in the
               space four gaps used to take. */
            spacing: 0
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

                width: view.width

                name: rowData ? rowData.name : ""
                priceText: rowData ? rowData.price_text : ""
                totalText: rowData ? rowData.total_text : ""
                qtyText: rowData ? rowData.qty_text : ""
                qty: rowData ? rowData.qty : 0
                step: rowData && rowData.step ? rowData.step : 1

                selected: index === root.selectedRow

                onClicked: root.selectedRow = index
                onQtyRequested: (value) => root.setQty(index, value)
                onRemoveRequested: root.removeLine(index)
            }
        }

        /* A compact empty state. This screen's empty cart is the state it is
           in BETWEEN sales, not a problem to explain — one line, and the
           keypad below it stays where it is, because the keypad is for the
           next sale, not this one's. */
        ColumnLayout {
            anchors.centerIn: parent
            visible: view.count === 0
            spacing: Tokens.spacing.xs

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Strings.t("pos.cart.ready.title",
                                "Ready for the next sale")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Strings.t("pos.cart.ready.body",
                                "Scan a barcode or choose a product to begin.")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textTertiary
            }
        }

        Connections {
            target: root.ctrl

            /* A line was added or bumped by an add or a scan. It becomes the
               active line and is scrolled to, so the keypad's QTY target and
               the Delete key act on what was just scanned — the feedback
               that the cart changed. */
            function onLineTouched(row) {
                root.selectedRow = row
                view.positionViewAtIndex(row, ListView.Contain)
            }
        }
    }

    /*
     * THE PERMANENT KEYPAD, one arrangement-agnostic block.
     *
     * Two pieces, top to bottom:
     *
     *   the readout   the number being typed, the line (or the total) it
     *                 will change, and the commit arrow at the trailing end
     *   the pad       the three-mode pad — the entry-mode column beside
     *                 the digits, all of it inside Numpad:
     *
     *                 [ # Qty] [ 7 ] [ 8 ] [ 9 ]
     *                 [   +  ] [ 4 ] [ 5 ] [ 6 ]
     *                 [   −  ] [ 1 ] [ 2 ] [ 3 ]
     *                 [   C  ] [ 0 ] [ . ] [ ⌫ ]
     *
     * The modes are the same act at three meanings: Qty for the selected
     * line's quantity, + a free charge line added to the total, − a
     * cart-level discount subtracted from it — the last two committed as
     * a new free line through the same bridge the rows go through. The
     * money modes are glyphs alone; the active mode is the lit key, which
     * is why the readout carries no pill repeating it. C empties the
     * whole entry in one tap. The pad is exactly the readout's width —
     * both fill the panel — so the two read as one column of entry, and
     * the side column and digit keys share the width between them.
     */
    component KeypadArea: ColumnLayout {
        id: area

        spacing: Tokens.spacing.xs

        // -- the number, its target, and the commit key
        KeypadDisplay {
            id: keypadDisplay
            objectName: "keypadDisplay"
            Layout.fillWidth: true

            text: root.buffer

            actionEnabled: root.keypadReady
            actionTooltip: root.keypadMode === "qty"
                ? Strings.t("pos.numpad.submit.qty", "Submit quantity")
                : Strings.t("pos.numpad.submit.amt", "Submit amount")
            onApplied: root.applyBuffer()
        }

        Numpad {
            id: posNumpad
            objectName: "posNumpad"
            Layout.fillWidth: true

            keySize: Tokens.size.keypadKey

            /* THE TILL'S THREE MODES, as it shipped: Qty — a quantity for
                the selected line — and the two money modes, + a free
                charge line added to the total and − a cart-level discount
                subtracted from it. The money keys are TOGGLES shown as
                glyphs alone: the page owns keypadMode, Submit commits the
                typed number as that mode's meaning (setQty for qty,
                addFreeAmount for the money modes — a new free line in the
                cart), and the highlighted key is the mode. */
            modes: ["qty", "plus", "minus"]

            activeMode: root.keypadMode

            /* The side column's spare fourth row: the whole-entry eraser.
                Three modes leave it empty, and C is what a mis-scanned
                thirteen-digit barcode wants. */
            clearKey: true

            /* The decimal key obeys the mode as much as the line: a
                quantity may carry a fraction only while the selected line
                sells a weighted or fractional unit; a MONEY amount always
                may have one. */
            decimalEnabled: root.keypadMode !== "qty" || root.keypadFractional

            onKeyPressed: (key) => root.feedKey(key)
            onModeRequested: (mode) => root.keypadMode = mode
        }
    }

    /* The state matrix for the grid. An error outranks emptiness. There is no
       "no results" state here any more: the grid shows the open category and
       nothing else, so an empty grid means an empty category — searching cannot
       empty it. Search results live in the dropdown under the field. */
    readonly property bool showTileState: !busy && tileCount === 0
    readonly property string tileState: errorText !== "" ? "error" : "empty"

    /* Is a text editor focused? The Delete shortcut below must not eat the key
       that erases a character in the search box — and `cursorPosition` is what a
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
       CategoryStrip draws as a dot and never as ink. */
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
        /* A category change swaps the wall's contents; the view must not
           keep the scroll of the category that left, or the operator lands
           mid-wall on a half-visible first row. */
        tileGrid.positionViewAtBeginning()
    }

    // =====================================================================
    // DATA
    // =====================================================================
    /* One category at a time, never the whole catalogue — pos's rule, and the
       reason a shop with four thousand products does not build four thousand
       tiles. `activeTab` is null only before the categories land. */
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
     * purpose (pos/app/data/db.py), because a shop sells the case that is still
     * on the pallet and because a count is often simply wrong — and refusing
     * left the operator with a product they can see on the shelf and no way to sell
     * it, on a screen that never explained the difference.
     *
     * So the sale goes through and the screen SAYS what it did. The tile already
     * shows the count and colours it below zero; this adds the sentence.
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
    // CART
    // =====================================================================
    function setQty(row, value) {
        /* The same rules as the row's own field, because it is the same edit:
           zero and out-of-range are refused and the row keeps what it had. */
        if (value <= 0 || !ctrl)
            return
        ctrl.setQty(row, value)
    }

    /*
     * Taking a line off the cart happens on the tap, with nothing asked.
     *
     * It used to open a confirmation. That was the wrong measure of the act: a cart
     * line is not a document, and putting it back is one scan of the same product —
     * the till's most practised gesture. A dialog in front of it costs a tap and a
     * read every single time to prevent a mistake that costs a scan once. Voiding the
     * whole sale still asks, because that one is not a scan to undo.
     */
    function removeLine(row) {
        if (row < 0 || row >= cartCount || !ctrl)
            return
        ctrl.remove(row)
    }

    function requireCart() {
        if (cartCount > 0)
            return true
        notify(Strings.t("pos.cart_empty", "The cart is empty"), Severity.caution)
        return false
    }

    // =====================================================================
    // THE PERMANENT KEYPAD — one buffer, one mode, a named target
    // =====================================================================
    /* The merchant's non-negotiable, restored: the numeric keypad never
       leaves the screen, and it never hides behind a popover or an empty
       cart. The buffer is page state, mirrored into the readout — pos's
       design, and the right one: one place holds "what have I typed".

        The entry is one of THREE things, and the mode toggle says which:
          qty         a quantity for the SELECTED line (setQty) — the mode
                      the pad opens in, the question it exists to answer
          plus (+)    a free charge line ADDED to the total, qty 1
          minus (−)   a cart-level discount line SUBTRACTED from the
                      total, qty 1
        The money modes are the free-line vocabulary pos itself shipped:
        both commit through the bridge's addFreeAmount as a new line in the
        cart, so the total they move is a total the eye can see moving.

       Validation is Python's where it can be: quantities are guarded by
       the stock question there, amounts by the bridge's own ceiling. This
       side only refuses what cannot even be sent: nothing typed, or zero. */
    property string keypadMode: "qty"
    property string buffer: ""

    /* The buffer as a number, or NaN. "1,5" is a French keyboard's one and
       a half, so the separator is normalised before it is parsed — the same
       rule CartLine's field applies to a typed quantity. */
    readonly property real bufferValue: parseFloat(buffer.replace(",", "."))

    readonly property bool bufferValid: buffer !== "" && !isNaN(bufferValue)
                                        && bufferValue > 0

    /* What Submit needs, by mode: a QTY needs a line to act on, a money
       amount needs only the cart to put its line in (and a free line may
       be the first thing on a sale — a delivery charge before the goods
       are rung). This is what the Submit key's enabled state reads, so
       the button itself explains what is missing. */
    readonly property bool keypadReady: bufferValid
                                        && (keypadMode !== "qty"
                                            || (selectedRow >= 0
                                                && selectedRow < cartCount))

    /* The selected line, when there is one: the stepper's target, and the
       row the readout's Submit will act on. Read from the controller's own
       list — the readout must act on the same row the cart has selected,
       and `lines` re-notifies on every change. */
    readonly property var selectedLine: {
        var lines = ctrl ? ctrl.lines : null
        return (lines !== null && selectedRow >= 0 && selectedRow < lines.length)
               ? lines[selectedRow] : null
    }

    /* The selected line's unit step — a 6-pack steps by 6, a weighted
       product by its fraction, everything else by one. The row's own
       stepper and the fraction rule both read it, so they can never
       disagree about what "one more" means. */
    readonly property real stepSize: {
        var line = selectedLine
        return (line !== null && line.step !== undefined && line.step > 0)
               ? line.step : 1
    }

    /* May the entry hold a fraction? The selected line's own unit decides:
       a weighted or fractional product steps by less than one and sells at
       1.5; anything else steps whole, and the decimal key goes quiet rather
       than accepting a value Submit would have to refuse. No line, no
       fractions — there is nothing to apply them to. */
    readonly property bool keypadFractional: {
        var line = selectedLine
        return line !== null && line.step !== undefined
               && line.step > 0 && line.step % 1 !== 0
    }

    /* A key from the pad. The pad is a pure view: it reports, this decides.
       "." is allowed — weighted goods sell at 1.5, and a MONEY amount may
       carry its cents — but only once, and the key itself is disabled when
       neither is true (a whole-stepping line in QTY mode). */
    function feedKey(key) {
        if (key === "back") {
            buffer = buffer.slice(0, Math.max(0, buffer.length - 1))
            return
        }
        if (key === "clear") {
            buffer = ""
            return
        }
        if (key === ".") {
            if (buffer.indexOf(".") >= 0)
                return
            buffer = buffer === "" ? "0." : buffer + "."
            return
        }
        buffer += key
    }

    function applyBuffer() {
        if (!keypadReady)
            return
        /* By the mode the toggle elected. QTY is the same wrapper the row's
           own field goes through — zero and out-of-range refused there, and
           the stock question opens from Python with this row and this
           quantity in hand. The money modes are the free line: +AMT a
           charge ADDED to the total, −DISC a discount SUBTRACTED from it,
           both a new line at qty 1 through the bridge's addFreeAmount
           (which owns the ceiling and the naming). */
        if (keypadMode === "qty") {
            setQty(selectedRow, bufferValue)
        } else if (ctrl) {
            ctrl.addFreeAmount(keypadMode === "plus" ? 1 : -1, bufferValue)
        }
        buffer = ""
    }

    /* A line leaving the cart cannot stay selected, and a QTY buffer aimed
       at a line that no longer exists must not silently retarget the row
       that took its place. */
    onCartCountChanged: {
        if (selectedRow >= cartCount)
            selectedRow = -1
    }

    /*
     * THE PANEL AND THE PAYMENT BAR.
     *
     * The page is two storeys. The upper storey is the familiar pair — the
     * product workspace and the transaction panel — and the panel is the
     * vertical column the merchant drew: customer, cart, readout, keypad,
     * stacked, the cart filling every pixel the rest leaves and scrolling
     * inside it.
     *
     * The ground storey is the payment bar: the total, Debt and Cash on ONE
     * full-width row under both regions, at the very bottom of the screen.
     * The total used to live in the panel's foot, and the panel's foot used
     * to be the reason a second, wide arrangement existed at all — with the
     * actions in a toolbar and the money in the bar, the panel's fixed
     * region is the keypad alone (~330px), the vertical cart keeps four to
     * seven rows at every supported size, and the wide variant had nothing
     * left to fix. One arrangement, the one the brief draws.
     *
     * The bar is where the eye lands last, which is the right place for the
     * figure that is owed and the two ways to take it — and being full
     * width, it puts the money under the products as well as under the
     * cart, so the layout reads left-to-right as "find it, ring it, take
     * it" in one sweep.
     */

    // =====================================================================
    // COMMANDS
    // =====================================================================
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
    /* Loaded whole, once, each time the dropdown opens: `search("")` is unpaged, so
       every keystroke after that is filtered in QML with no round trip. The paged
       load belongs to CustomersPage, which is a table with a pager; this is a list
       being typed into. */
    function loadCustomers() {
        if (customers)
            customers.search("")
    }

    function attachCustomer(party) {
        if (!ctrl || !party)
            return
        ctrl.setCustomer(party.id)
    }

    function removeCustomer() {
        if (!ctrl)
            return
        /* Nothing is committed until the payment is confirmed, so dropping the
           customer mid-sale needs no confirmation of its own. */
        ctrl.setCustomer(0)
    }

    /* The form, not the picker: the button beside the field is the whole route,
       so an operator who has decided to add a customer is never handed a table
       of the ones that already exist to click through. The flag is what brings
       the result back — see customerWritten. */
    function newCustomer() {
        awaitingNewCustomer = true
        requestOpen("customer_edit", {})
    }

    /* Created and attached in one step: the operator pressed that button to put
       a name on this sale, not to file a record. `saved` is the form's path (a
       new customer is a save with no id) and `created` the older quick-add one;
       both are funnelled here by the Connections below, which is exactly how
       the picker dialog did it when this flow was routed through it. */
    function customerWritten(customer) {
        if (!awaitingNewCustomer || !customer)
            return
        awaitingNewCustomer = false
        attachCustomer(customer)
    }

    // =====================================================================
    // CHECKOUT
    // =====================================================================
    /*
     * CASH OPENS THE PAYMENT, IT DOES NOT COMPLETE IT.
     *
     * The sheet shows the amount due, the keypad for what was received, and the
     * "left after this" figure as the number is typed; Confirm is what completes
     * the transaction. The sheet opens SEEDED with the whole total, so the
     * ordinary cash sale is Cash, Enter — two keystrokes, and the money is
     * confirmed on screen before it is recorded, which is the one thing an
     * instant-complete button never gave anybody.
     *
     * An invoice being rewritten opens the same sheet seeded with what it was
     * already recorded as paid — the sheet's own edit behaviour, unchanged.
     */
    function charge() {
        if (!requireCart())
            return
        payment.open()
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
        /* An underpayment is an account balance, whatever it is called, so a
           shop with accounts off has no use for this sheet — except to correct
           what an old invoice was recorded as paid, which is reconciliation
           and not a new debt. Python owns the refusal; this only keeps the
           button from opening a sheet whose every answer but "the whole
           total" is going to be one. */
        if (!allowDebt && editing === 0) {
            notify(Strings.t("pay.debt_off",
                             "Sales on account are switched off in Settings."),
                   Severity.caution)
            return
        }
        /* Seeded empty: this button is the "less than the whole amount"
           question, and pre-filling the total would pre-fill the one answer
           it is not for. ALL is one key away. */
        payment.seedAmount = 0
        payment.open()
    }

    // =====================================================================
    // ELSEWHERE
    // =====================================================================
    /* Every "open something else" through one funnel, and a sentence when the
       target is not in this build — a button that does nothing is
       indistinguishable from a broken one. ProductsPage's requestOpen, verbatim,
       because the reasoning is the same. */
    function requestOpen(key, context) {
        /* A different dialog opening from this page means the add-customer flow
           is over — cancelled, or superseded — so a customer saved by whatever
           opens next must not land on the sale as if it were that one. */
        if (key !== "customer_edit")
            awaitingNewCustomer = false
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
       burst lands before the application-wide decoder takes over, and where a
       typed query begins. */
    Component.onCompleted: {
        if (ctrl && ctrl.loadCategories)
            ctrl.loadCategories()
        repairTab()
        filters.focusSearch()
    }

    /*
     * THE WALL'S ANSWER, PUBLISHED.
     *
     * The arrange screen draws the till's own cards and must draw the same
     * NUMBER of them in a row — see TileMetrics, which explains why this is a
     * relay and not a second calculation. The bindings fire whenever the grid
     * recomputes (a resize, a font-scale change, the image setting), so a
     * dialog that is up cannot show a wall the till has stopped wearing.
     */
    Binding {
        target: TileMetrics
        property: "columns"
        value: tileGrid.columns
    }

    Binding {
        target: TileMetrics
        property: "mediaWall"
        value: tileGrid.mediaWall
    }

    /* `live` is what keeps the relay honest: the figures are trusted only
       while this page is the one on screen. PageHost destroys the page on a
       navigation — taking this binding with it — so the flag is cleared by
       hand at destruction rather than left true over a stale count. */
    Binding {
        target: TileMetrics
        property: "live"
        value: root.visible && tileGrid.visible
    }

    Component.onDestruction: TileMetrics.live = false

    Connections {
        target: root.ctrl

        /* A sale, a hold or a restore landed: stock moved, so the grid is stale.
           The cart itself is a model and updates on its own. */
        function onInvalidated() {
            root.reload()
        }

        /* onLineTouched lives inside CartArea: the selection is page state,
           but the scroll-to-line belongs to whichever view is on screen. */

        /* A scan or an Enter in the search box that matched nothing. `barcode`
           comes from Python because Python owns the digit normaliser that decides
           it — an Arabic-Indic ٠٦١٢ is a barcode and str.isdigit() alone does not
           say so. */
        function onScanMissed(code, barcode) {
            root.requestOpen(barcode ? "unknown_barcode" : "quick_add_product",
                             { code: code })
        }

        function onSaleFinished(number) {
            root.selectedRow = -1
            root.notify(Strings.tf("toast.sale_done", "Sale {number} recorded",
                                   { number: number }),
                        Severity.success)
        }

        /* Stock went below zero on that sale. The sale is done — pos never
           blocks one on stock — so this is a report, not a question, and it names
           the products because "stock went negative" is not actionable and
           "Coca-Cola 1.5L: −3" is. */
        function onStockWarning(rows) {
            belowZero.rows = rows
            belowZero.open()
        }

        /* The shelf cannot cover what was just asked for, and nothing has been added
           yet. Unlike the report above this is a question, because it arrives while
           there is still a decision to make: sell it anyway, put some stock on the
           shelf, or drop it. See Till's own note on why it asks rather than refuses. */
        function onStockBlocked(info) {
            shortStock.info = info
            shortStock.open()
        }

        /* The controller refused something and said why: an empty cart, a partial
           without a customer, a failed write. Its sentence, not ours. */
        function onRejected(message) {
            root.notify(message, Severity.caution)
        }
    }

    /* The accounts controller, for the add button's result: the form is a
       DialogHost object this page never sees, but its save is announced here.
       Gated by awaitingNewCustomer, for the reason on that property. */
    Connections {
        target: root.customers
        ignoreUnknownSignals: true

        function onSaved(customer) { root.customerWritten(customer) }
        function onCreated(customer) { root.customerWritten(customer) }
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
       that print them: a Shortcut declared inside the panel would keep firing
       while a dialog is on top of it. */
    Shortcut { sequence: "F2"; onActivated: filters.focusSearch() }
    /* F3 drops the customer list open with its search focused, which is the same
       keystroke it always was and one dialog less than it used to be. */
    Shortcut { sequence: "F3"; onActivated: customerSelect.open() }
    Shortcut { sequence: "F4"; onActivated: root.command("calculator") }
    Shortcut { sequence: "F1"; onActivated: root.command("return") }
    Shortcut { sequence: "F5"; onActivated: root.command("hold") }
    Shortcut { sequence: "F6"; onActivated: root.command("carts") }
    Shortcut {
        sequence: "F8"
        enabled: root.allowPartial && (root.allowDebt || root.editing > 0)
        onActivated: root.startPartial()
    }
    /* Charge, not instant cash: the same key opens the payment sheet that the
       primary button opens, and Confirm inside it completes the sale. */
    Shortcut { sequence: "F9"; onActivated: root.charge() }
    Shortcut { sequence: "F12"; onActivated: root.command("void") }

    /* The title bar actions' own keys. F7, F10 and F11 were free function keys
       — the till's own row is F1..F6, F8, F9, F12 — and each is printed on the
       chip it fires, so the bar is also the key map. Every one of them routes
       through `titleAction`, the same door the click uses: a shortcut that did
       its own thing would be a second definition of the action, and the two
       would drift the first time one of them changed. */
    Shortcut { sequence: "F7"; onActivated: root.titleAction("refresh") }
    Shortcut {
        sequence: "F10"
        enabled: root.canAddProduct
        onActivated: root.titleAction("product")
    }
    Shortcut { sequence: "F11"; onActivated: root.titleAction("labels") }

    /* Delete removes the SELECTED line — unless a text editor has focus, where
       Delete is how you erase a character. Two things wanting the same key is
       normally an ambiguous activation that fires neither; this one is resolved
       by asking what has focus.

       Deliberately not "the selected row, or the last one if nothing is
       selected": acting on a row that carries no visible selection was the
       trap the keypad's hidden target line spent years setting. A line is
       selected the moment it is added or scanned (`lineTouched`), so the
       gesture that matters — scan, press Delete — works exactly as before. */
    Shortcut {
        sequence: "Delete"
        enabled: !root.typing && root.selectedRow >= 0
                 && root.selectedRow < root.cartCount
        onActivated: root.removeLine(root.selectedRow)
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    /* Tighter than a list page's pagePadding: this screen is the one place where
       every pixel spent on margin is a pixel taken from the tile grid, and pos
       uses 12 here for the same reason.

       The page paints itself the cool product-workspace grey: the white
       tiles, the white search field and the white transaction panel all sit
       against it, which is what makes each of them read as its own surface —
       three neighbouring regions, three weights, no hairline doing the
       separating. */
    Rectangle {
        anchors.fill: parent
        color: Tokens.workspace.shelf
    }

    /* Two storeys: the selling row on top, the payment bar across the
       foot. The page's own margins and spacing wrap both, so the bar sits
       in the same frame as the workspace and the panel rather than
       touching the window's edge. */
    ColumnLayout {
        id: pageColumn
        objectName: "pageColumn"
        anchors.fill: parent
        anchors.margins: Tokens.spacing.md
        spacing: Tokens.spacing.md

        RowLayout {
            id: workspaceRow
            objectName: "workspaceRow"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.md

        // -----------------------------------------------------------------
        // THE WORKSPACE: search, categories, the wall
        // -----------------------------------------------------------------
        /* On the canvas, not inside a card: the tiles are white cards against
           the workspace grey, and a card around cards is a box in a box. The
           search bar and the filter row sit directly above the wall they
           steer. */
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.sm

            FilterBar {
                id: filters
                Layout.fillWidth: true
                placeholder: Strings.t("pos.search.ph",
                                       "Search products or scan a barcode")

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

                       `open` is a frame with an arrow leaving its
                       corner: the one shape a desktop operator already
                       reads as "a window opens". The same glyph is on
                       ProductFinder's browse button, so one shape means
                       one thing everywhere. */
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "ic_fluent_open_20_regular"
                        glyphSize: Tokens.icon.md
                        tooltip: Strings.t("selector.open_picker",
                                           "Browse all products")
                        onClicked: root.requestOpen("product_select", {})
                    }
                    /* Arranging the tiles is a title-bar action now — it
                       reorders the wall, not the query, and a control on an
                       input's shoulder reads as part of the input. */
                ]
            }

            CategoryStrip {
                id: categoryStrip
                objectName: "categoryStrip"
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
                    objectName: "tileGrid"
                    anchors.fill: parent
                    clip: true
                    visible: !root.showTileState
                    model: root.ctrl ? root.ctrl.tiles : null

                    /* THE COUNT IS THE ARRANGE SCREEN'S COUNT, AND THE RAIL
                        DOES NOT GET A VOTE. However wide the workspace grows
                        within one window size, a row holds at most
                        Tokens.size.tileColumns cards, because the planning
                        screen (ArrangeDialog) caps its own wall at the same
                        number and the hand that learned a tile's place there
                        must find it in the same column here.

                        Both the count and the card style below read
                        `stableWidth` — the wall's width with the rail's
                        collapse taken back off (see PosPage.railSlack) — so
                        collapsing the rail widens the GUTTER, not the
                        catalogue: the row keeps its cards and every cell
                        keeps its column. Only a genuinely narrower window
                        drops the count, exactly as the arrange screen does.

                        The floor still protects the narrow window: below
                        two image-card columns the wall falls back to the
                        compact text tile rather than show one fat card. */

                    readonly property int gap: Tokens.spacing.xs

                    /* The width the count and the card style are decided by:
                        this grid's own width less whatever the rail's
                        current collapse freed — the width the wall has with
                        the rail expanded, which is the narrower case and the
                        one every screenshot was taken in. With the rail
                        expanded the subtraction is exactly zero. */
                    readonly property real stableWidth:
                        Math.max(1, width - root.railSlack)

                    /* Do the cards carry a photo band? The shop's setting
                        AND the catalogue's photos AND room for two columns
                        of the horizontal card. Below two columns the wall
                        falls back to the compact text tile — one fat card
                        per row is a wall with nothing on it, and the text
                        tile is the card the no-photo shop has always had.
                        The flag is one answer for every cell, because a
                        GridView has one cell size — see PosTile's own
                        header. Read against stableWidth for the same reason
                        the count is: a collapse must not change the shape of
                        every card on the wall. */
                    readonly property bool mediaWall: root.imageCards
                        && Math.floor((stableWidth + gap)
                                      / (Tokens.size.tileMediaMin + gap)) >= 2

                    readonly property int tileFloor: mediaWall
                        ? Tokens.size.tileMediaMin : Tokens.size.tileMin
                    /* The ceiling per card: the surplus of a wide cell is
                        gutter, never card width. */
                    readonly property int tileCeil: mediaWall
                        ? Tokens.size.tileMediaMax : Tokens.size.tileMax
                    readonly property int columns:
                        Math.max(1, Math.min(Tokens.size.tileColumns,
                                             Math.floor((stableWidth + gap)
                                                        / (tileFloor + gap))))

                    /* The scrollbar's seat, paid where the gutter is already
                       made: the bar is an overlay pinned inside the grid's
                       trailing edge, so the LAST cell is the one it widens
                       over. Taking the seat out of the cell width (not a
                       grid-level margin, which would pull every column in
                       without ever clearing the bar) leaves the trailing
                       card clear of the bar, and the floor arithmetic above
                       still governs the honest column count. */
                    cellWidth: Math.max(1, Math.floor(
                        (width - Tokens.size.scrollSeat) / columns))
                    /* The card's height is its content's (PosTile's own
                       implicitHeight — two name lines and a money line for
                       the image card), so the row count follows the
                       content: the wall fits the most products it can
                       without a token guessing at the card's height. The
                       image card's height is a TOKEN, not arithmetic here:
                       the arrange screen has to size its cells from the same
                       number (see TileMetrics), and two sums that must agree
                       belong in one place. */
                    cellHeight: (mediaWall
                                 ? Tokens.size.tileMediaHeight
                                 : Tokens.size.tile) + gap

                    QC.ScrollBar.vertical: FluentScrollBar {
                        policy: QC.ScrollBar.AsNeeded
                    }

                    /* A cell, with the tile centred inside it. GridView has no
                       spacing of its own — the gutter has to come out of the
                       cell — and the tile takes its own implicit size, so a
                       wide cell shows the difference as gutter on both sides
                       rather than as one enormous card. */
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
                            id: posTile
                            anchors.centerIn: parent
                            width: Math.min(parent.width - tileGrid.gap,
                                            tileGrid.tileCeil)
                            /* The card's own content height — see the cell's
                               own note: the image card is as tall as its
                               words, and the photo spans all of it. */
                            height: tileGrid.mediaWall
                                     ? Tokens.size.tileMediaHeight
                                     : Tokens.size.tile

                            name: cell.rowData ? cell.rowData.name : ""
                            priceText: cell.rowData ? cell.rowData.price_text : ""
                            barcode: cell.rowData && cell.rowData.barcode
                                     ? cell.rowData.barcode : ""
                            stock: cell.rowData ? cell.rowData.stock : 0
                            stockText: cell.rowData ? cell.rowData.stock_text : ""
                            lowStock: cell.rowData
                                      ? cell.rowData.low_stock === true : false
                            /* The product's colour, or its category's — the
                               controller decides which. */
                            accent: cell.rowData && cell.rowData.color
                                    ? cell.rowData.color : "transparent"

                            /* The grid decides whether the card is the
                                horizontal image card or the text tile; the
                                row decides what is in it. "" is a product
                                with no photo, and the card draws the
                                placeholder square. */
                            showImage: tileGrid.mediaWall
                            imageSource: cell.rowData && cell.rowData.image
                                         ? cell.rowData.image : ""

                            /* The tap's receipt on the tile itself: a brief
                               emerald pulse on the border, beside the line
                               flashing into selection in the cart below. */
                            onClicked: {
                                posTile.added = true
                                root.pick(cell.rowData)
                            }
                        }
                    }

                    /* The wall's empty state. Tiles reloading under an empty
                       grid is a different thing from an empty category, and
                       the overlay says which: the variant owns the glyph and
                       the title, the error state carries the controller's
                       sentence. */
                    StateView {
                        anchors.fill: parent
                        visible: root.showTileState
                        variant: root.tileState
                        title: root.tileState === "empty"
                               ? Strings.t("pos.grid.empty",
                                           "No products in this category")
                               : ""
                        body: root.errorText
                        onRetryRequested: root.reload()
                    }

                    /* Tiles reloading with nothing on screen. */
                    LoadingOverlay {
                        visible: root.busy && root.tileCount === 0
                    }
                }
            }

            // -----------------------------------------------------------------
            // THE SALE-ACTION TOOLBAR — the products side's own foot
            // -----------------------------------------------------------------
            /* Hold, suspended carts, return, calculator, and the destructive
               clear — the acts done AROUND a sale, parked at the foot of the
               PRODUCT side only: the merchant's rule. The cart column keeps
               its clean run down to its own two decisions (Debt and Cash,
               which sit directly under it in the payment bar), and the two
               workspaces each own their bottom edge.

               A Flow, not a Row: on a narrow window the row wraps to two
               lines rather than eliding a single label — a cut-off "Susp…"
               is a label nobody can act on.

               The height is pinned to the Flow's own content, explicitly:
               `implicitHeight` is the Flow's settled answer once it has
               wrapped its (real, non-zero — see ActionButton) children, and
               naming it here guarantees the column reserves that much even
               if some future child measures late. What must NOT be fed back
               is childrenRect — that changes while the Flow is still
               positioning, and a Layout preferred size that moves during
               arrangement is the recursive-rearrange trap. */
            Flow {
                id: actionToolbar
                objectName: "actionToolbar"

                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                spacing: Tokens.spacing.xs

                ActionButton {
                    tone: "warning"
                    glyph: "ic_fluent_pause_20_regular"
                    label: Strings.t("pos.action.hold", "Hold")
                    shortcut: "F5"
                    enabled: root.cartCount > 0
                    onClicked: root.command("hold")
                }

                ActionButton {
                    tone: "info"
                    glyph: "ic_fluent_archive_20_regular"
                    label: Strings.t("pos.action.suspended", "Suspended")
                    shortcut: "F6"
                    onClicked: root.command("carts")
                }

                ActionButton {
                    tone: "violet"
                    glyph: "ic_fluent_arrow_hook_up_left_20_regular"
                    label: Strings.t("pos.rail.return", "Return")
                    shortcut: "F1"
                    onClicked: root.command("return")
                }

                ActionButton {
                    glyph: "ic_fluent_calculator_20_regular"
                    label: Strings.t("pos.action.calculator", "Calculator")
                    shortcut: "F4"
                    onClicked: root.command("calculator")
                }

                ActionButton {
                    glyph: "ic_fluent_delete_dismiss_20_regular"
                    label: Strings.t("pos.action.clear", "Clear cart")
                    shortcut: "F12"
                    destructive: true
                    enabled: root.cartCount > 0
                    onClicked: root.command("void")
                }
            }
        }

        // -----------------------------------------------------------------
        // THE TRANSACTION PANEL — one surface, the sale in hand
        // -----------------------------------------------------------------
        /* Everything about the sale except the money: who it is for, the
           lines, and the quantity entry. The total and the payment buttons
           moved to the full-width bar under the page — see THE PANEL AND
           THE PAYMENT BAR — so the panel's fixed region is the keypad
           alone, and the cart takes every pixel above it. */
        Rectangle {
            id: panel

            Layout.preferredWidth: Tokens.size.cartColumn
            Layout.minimumWidth: Tokens.size.cartColumn
            Layout.maximumWidth: Tokens.size.cartColumn
            Layout.fillHeight: true

            color: Tokens.workspace.surface
            radius: Tokens.radius.lg
            border.width: 1
            border.color: Tokens.workspace.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.size.cardPadding
                spacing: Tokens.spacing.sm

                // -- who it is for
                /* The field alone. The add-a-customer button used to sit on
                   its shoulder; it is a title-bar action now, where every
                   "do something else" of the screen is — a person-and-plus
                   glued to a customer dropdown asked to be read as part of
                   the dropdown. */
                PartySelect {
                    id: customerSelect
                    objectName: "customerSelect"

                    Layout.fillWidth: true
                    enabled: root.canPickCustomer
                    active: root.hasCustomer
                    /* ONE invitation, not two. The empty card used to
                       say "Walk-in customer" with "Tap to attach a
                       customer" beside it, and neither fit — the field
                       now asks its single question, the catalogue's
                       own "Select customer (F3)", with no subtitle
                       eating the width. A customer attached keeps the
                       name, with the phone as the trailing detail. */
                    title: root.hasCustomer && root.ctrl
                           ? root.ctrl.customerName
                           : Strings.t("pos.customer.hint",
                                       "Select customer")
                    subtitle: root.hasCustomer && root.ctrl
                              ? root.ctrl.customerPhone : ""
                    removeTip: Strings.t("pos.customer.remove",
                                         "Remove customer")

                    rows: root.customers ? root.customers.rows : []
                    placeholder: Strings.t("select_customer.search.ph",
                                           "Search name or phone")

                    onListRequested: root.loadCustomers()
                    onPicked: (party) => root.attachCustomer(party)
                    onRemoveRequested: root.removeCustomer()
                }

                // -- edit mode, said out loud
                /* A till holding a finished invoice commits to a different
                    document, so the one thing this mode must never be is quiet:
                    a full-width indigo row naming the invoice, with the way out
                    beside it. Navy ink on the indigo fill — the pairing the
                    payment heroes already use (PayButton's own note). */
                Rectangle {
                    id: editBar

                    Layout.fillWidth: true
                    visible: root.editing > 0
                    implicitHeight: editRow.implicitHeight + 2 * Tokens.spacing.xs
                    radius: Tokens.radius.md
                    color: Tokens.chromeHue.indigo

                    readonly property color ink: Tokens.chromeTo

                    RowLayout {
                        id: editRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.spacing.sm
                        anchors.rightMargin: Tokens.spacing.xs
                        spacing: Tokens.spacing.sm

                        Icon {
                            icon: "ic_fluent_edit_20_regular"
                            size: Tokens.icon.sm
                            color: editBar.ink
                        }

                        Text {
                            Layout.fillWidth: true
                            text: Strings.t("pos.edit.mode", "Editing an invoice")
                                  + "  \u200e" + root.editingNumber
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            color: editBar.ink
                            elide: Text.ElideRight
                        }

                        ChromeButton {
                            iconName: "ic_fluent_dismiss_20_regular"
                            iconSize: Tokens.icon.sm
                            iconColor: Qt.rgba(editBar.ink.r, editBar.ink.g,
                                               editBar.ink.b, 0.8)
                            iconColorActive: editBar.ink
                            fillHover: Qt.rgba(editBar.ink.r, editBar.ink.g,
                                               editBar.ink.b, 0.18)
                            fillDown: Qt.rgba(editBar.ink.r, editBar.ink.g,
                                              editBar.ink.b, 0.30)
                            tip: Strings.t("pos.edit.cancel",
                                           "Leave the invoice as it was")
                            onClicked: if (root.ctrl) root.ctrl.cancelEdit()
                        }
                    }
                }

                // -- the sale: the cart, then the quantity entry
                /* The cart starts directly under the customer and takes
                    every pixel the keypad leaves below it — the actions are
                    in the workspace toolbar at the foot of the product side,
                    and the money is in the full-width bar under the page, so
                    nothing else claims this column: the panel runs clean
                    from the customer to the keypad, and the keypad sits
                    directly above the payment bar's Debt and Cash — the
                    merchant's rule. A long cart scrolls inside the CartArea;
                    the keypad stays pinned at the panel's foot. */
                CartArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                KeypadArea {
                    id: keypadArea
                    Layout.fillWidth: true
                }
            }
        }
    }

        // -----------------------------------------------------------------
        // THE PAYMENT BAR — the total, Debt and Cash, across the foot
        // -----------------------------------------------------------------
        /* The money, under everything. One row, one height, full width:
           the dark petrol total on the leading side taking all the room
           the two buttons leave, Debt — the secondary question — beside
           it, and Cash, the primary, on the trailing edge. The bar is the
           last thing on the screen and the biggest decision on it; putting
           it under the products as well as the cart is what makes the
           whole page read left-to-right as find it, ring it, take it.

           The buttons' widths are fixed numbers derived from the panel
           token, not fractions of the row read back at layout time — a
           preferred width that depends on the width being laid out is the
           recursive-rearrange trap, and the row is wide enough that fixed
           comfortable widths leave the total everything else. */
        RowLayout {
            id: payBar
            objectName: "payBar"

            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.size.payBar
            /* THE HEIGHT IS A CEILING TOO, NOT JUST A PREFERENCE. The bar's
               implicit height (the taller of its buttons) and its preferred
               92 differ, and the page column's spare height is the
               workspace row's by right — but a layout that re-runs its
               distribution while a child's implicit size is still settling
               can hand a non-fill item more than it asked for and leave
               the mis-split standing (observed: a 262px bar squeezing the
               product wall by 200px). One row, one height: the maximum is
               the same token, so the bar can never be anything but the
               single 92px strip the brief draws, whatever the layout
               engine does between passes. */
            Layout.maximumHeight: Tokens.size.payBar
            spacing: Tokens.spacing.md

            // -- the total
            /* Dark petrol, unmistakable: darker than the white cart,
               lighter than the navy rail, the figure in pure white at the
               largest size the page carries. The label leads in the
               emerald accent, the meta (items, units, the cart's number,
               a discount when there is one) stays small and cool, and the
               amount sits right-aligned at the trailing edge — beside
               Debt, the first thing the eye meets after the figure. Every
               figure arrives formatted from Python, tabular. */
            Rectangle {
                id: totalBlock
                objectName: "totalBlock"

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.radius.md
                color: Tokens.totalBlock.base
                border.width: 1
                border.color: Tokens.totalBlock.edge

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacing.md
                    anchors.rightMargin: Tokens.spacing.md
                    spacing: Tokens.spacing.sm

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: Strings.t("pos.summary.total", "TOTAL")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.2
                        color: Tokens.totalBlock.label
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        text: Strings.t("pos.summary.items", "Items")
                              + " " + (root.ctrl ? root.ctrl.itemsText : "—")
                              + " · " + Strings.t("pos.summary.qty", "Qty")
                              + " " + (root.ctrl ? root.ctrl.qtyText : "—")
                              + (root.ctrl && root.ctrl.cartNumber !== ""
                                 ? " · \u200e" + root.ctrl.cartNumber : "")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.overline
                        font.features: Tokens.figures
                        color: Tokens.totalBlock.meta
                        elide: Text.ElideRight
                    }

                    /* PAID AND REMAINING, on an invoice being rewritten.
                       The dock's settled column, moved with the money into
                       the bar — between the meta and the figure, at reading
                       size, because the question while correcting a
                       customer's invoice is "how much is still owed after
                       this" and the bar is where the money is now read.

                       ONLY WHEN THERE IS A CUSTOMER, for the dock's own
                       reason: a guest invoice cannot owe anything, and
                       "Paid (the total again) / Remaining 0,00" on every
                       guest edit is a fake reading rather than an answer.
                       The figures are live — the payment sheet rewrites the
                       paid figure and this line moves with it. Remaining is
                       red only when something is actually owed; a settled
                       invoice's zero is good news and colouring it as a
                       warning would teach the operator to ignore the colour. */
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.editing > 0 && root.hasCustomer
                                 && root.ctrl
                                 && root.ctrl.paidText !== ""

                        spacing: Tokens.spacing.sm

                        Text {
                            anchors.baseline: paidFigure.baseline
                            text: Strings.t("invoice.paid", "Paid")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            font.weight: Font.DemiBold
                            color: Tokens.totalBlock.label
                        }

                        Text {
                            id: paidFigure
                            text: "\u200e" + (root.ctrl
                                              ? root.ctrl.paidText : "")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            font.features: Tokens.figures
                            color: Tokens.totalBlock.meta
                        }

                        Text {
                            anchors.baseline: paidFigure.baseline
                            text: Strings.t("invoice.fin.remaining",
                                            "Remaining")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            font.weight: Font.DemiBold
                            color: Tokens.totalBlock.label
                        }

                        Text {
                            text: "\u200e" + (root.ctrl
                                              ? root.ctrl.remainingText : "")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            font.features: Tokens.figures
                            /* Red only when something is actually owed —
                               the dock's own rule, verbatim. */
                            color: root.ctrl
                                   && root.ctrl.total - root.ctrl.paid
                                      > 0.005
                                   ? Tokens.onChromeDanger
                                   : Tokens.totalBlock.meta
                        }
                    }

                    /* Only when there is one: a sale with no discount
                       shows no discount line. Financially important, so it
                       is on the bar, not hidden. */
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.ctrl && root.ctrl.discountText !== ""
                        text: Strings.t("pos.summary.discount", "Discount")
                              + " −\u200e" + (root.ctrl
                                                   ? root.ctrl.discountText : "")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.overline
                        font.weight: Font.DemiBold
                        font.features: Tokens.figures
                        color: Tokens.totalBlock.label
                    }

                    /* The amount and its currency as one baseline-aligned
                       pair: posTotal for the number, body size for the
                       "DA", so the figure carries and the currency is
                       merely present. */
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: totalFigure.implicitWidth
                                       + (totalCurrency.visible
                                          ? totalCurrency.implicitWidth
                                            + Tokens.spacing.xs : 0)
                        implicitHeight: totalFigure.implicitHeight

                        Text {
                            id: totalFigure
                            anchors.right: totalCurrency.left
                            anchors.rightMargin: Tokens.spacing.xs
                            text: "\u200e" + (root.ctrl
                                                  ? root.ctrl.totalText : "—")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.posTotal
                            font.weight: Font.DemiBold
                            /* Tabular figures: the total ticks from
                               999 to 1,000 and must not slide. */
                            font.features: Tokens.figures
                            color: Tokens.totalBlock.amount
                        }

                        Text {
                            id: totalCurrency
                            anchors.right: parent.right
                            anchors.baseline: totalFigure.baseline
                            visible: root.ctrl
                                     && root.ctrl.currencyText !== ""
                            text: root.ctrl ? root.ctrl.currencyText : ""
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: Tokens.totalBlock.meta
                        }
                    }
                }
            }

            DebtButton {
                id: debtButton
                objectName: "debtButton"
                /* A fixed comfortable width, derived from the panel token
                   so it scales with the text: the word, the payment glyph
                   and the F8 hint in every language, without stealing the
                   primary's share. Hidden, not dimmed, when the shop's
                   settings take debt away entirely — Cash takes the
                   row with the total. */
                Layout.fillHeight: true
                Layout.preferredWidth: Math.round(
                    Tokens.size.cartColumn * 0.44)
                visible: root.allowPartial
                          && (root.allowDebt || root.editing > 0)
                enabled: root.cartCount > 0

                text: Strings.t("pos.pay.partial", "Debt")
                shortcut: "F8"

                onClicked: root.startPartial()
            }

            CashButton {
                id: cashButton
                objectName: "cashButton"
                /* The primary: wider than Debt by the same fixed
                   arithmetic, the emerald the whole app means by
                   "commit the money". */
                Layout.fillHeight: true
                Layout.preferredWidth: Math.round(
                    Tokens.size.cartColumn * 0.62)
                enabled: root.cartCount > 0

                text: root.editing > 0
                      ? Strings.t("pos.edit.save", "Save changes")
                      : Strings.t("pos.pay.cash", "Cash")
                shortcut: "F9"

                onClicked: root.charge()
            }
        }
    }

    // =====================================================================
    // CONFIRM
    // =====================================================================
    /*
     * Voiding asks; removing one line does not (see `removeLine`).
     *
     * The figures are the message: items and units, the total, and the customer
     * when there is one. And when the cart is a completed invoice being
     * rewritten, the dialog says the thing that actually matters — the invoice
     * on file is untouched, only this copy of it goes.
     */
    ConfirmDialog {
        id: confirmVoid

        readonly property bool editing: root.ctrl && root.ctrl.editing > 0

        glyph: "ic_fluent_delete_dismiss_20_regular"
        title: editing ? Strings.t("confirm.discard_edit.title",
                                   "Discard these changes?")
                       : Strings.t("confirm.void_sale.title", "Void this sale?")

        body: editing
              ? Strings.tf("confirm.discard_edit.body",
                           "Invoice {number} stays exactly as it is. Only the copy in the cart is discarded.",
                           { number: root.ctrl ? root.ctrl.editingNumber : "" })
              : Strings.t("confirm.void_sale.body",
                          "Nothing is recorded. The lines go, and the customer with them.")

        facts: [
            {
                label: Strings.t("pos.summary.items", "Items"),
                value: root.ctrl && root.ctrl.itemsText !== ""
                       ? root.ctrl.itemsText + " \u00b7 " + root.ctrl.qtyText : "",
                tone: ""
            },
            {
                label: Strings.t("pos.summary.total", "Total"),
                value: root.ctrl ? root.ctrl.totalText : "",
                tone: ""
            },
            {
                label: Strings.t("pos.customer", "Customer"),
                value: root.ctrl && root.ctrl.hasCustomer
                       ? root.ctrl.customerName : "",
                tone: ""
            }
        ]

        confirmText: editing ? Strings.t("confirm.discard_edit.action",
                                         "Discard the changes")
                             : Strings.t("confirm.void_sale.action", "Void the sale")
        cancelText: editing ? Strings.t("action.keep_editing", "Keep editing")
                            : Strings.t("action.keep_cart", "Keep the cart")

        onConfirmed: {
            root.selectedRow = -1
            if (root.ctrl)
                root.ctrl.clear()
        }
    }

    /*
     * BEFORE THE SHELF GOES NEGATIVE, WHILE THERE IS STILL A DECISION.
     *
     * The other stock dialog on this page (`belowZero`) is a receipt for
     * something that already happened. This one is the question, and the
     * difference is the whole point of it: the line has not been added, so
     * there are three real answers and it draws all three — sell it anyway,
     * put stock on the shelf, or leave it. Nothing here decides; the till
     * does, when the answer comes back through addAnyway / setQtyAnyway.
     */
    ConfirmDialog {
        id: shortStock

        /* The payload from `stockBlocked`, held rather than read out of a signal
           argument: the dialog outlives the emission and the answer needs the same
           product and the same figures the question was asked about. */
        property var info: null

        readonly property bool out: shortStock.info
                                    && shortStock.info.kind === "out"

        /* The tick and the answer both, in one place: the box is only honoured when
           the operator actually answered — see ConfirmDialog's note on why Cancel
           does not count. */
        function settle() {
            if (root.ctrl && shortStock.suppressed)
                root.ctrl.setWarnStock(false)
        }

        tone: "caution"
        glyph: "ic_fluent_warning_20_regular"

        title: shortStock.out
               ? Strings.t("stock.short.out.title", "Out of stock")
               : Strings.t("stock.short.title", "Not enough stock")

        body: shortStock.info
              ? (shortStock.out
                 ? Strings.tf("stock.short.out.body",
                              "{name} has nothing left on the shelf. It can still be sold — the count simply goes below zero.",
                              { name: shortStock.info.name })
                 : Strings.tf("stock.short.body",
                              "{name} does not have enough on the shelf for this line. It can still be sold — the count simply goes below zero.",
                              { name: shortStock.info.name }))
              : ""

        /* The two figures the decision is made on, and nothing else. The shelf is
           toned because it is the one that is wrong. */
        facts: shortStock.info ? [
            {
                label: Strings.t("stock.current", "On the shelf"),
                value: shortStock.info.stock_text,
                tone: shortStock.out ? "danger" : "warning"
            },
            {
                label: Strings.t("stock.short.wanted", "This line wants"),
                value: shortStock.info.wanted_text,
                tone: ""
            }
        ] : []

        confirmText: Strings.t("stock.short.sell", "Sell it anyway")
        cancelText: Strings.t("action.cancel", "Cancel")

        /* Absent, not dimmed, for an operator who may not adjust stock: a button
           that opens a refusal is worse than no button. */
        extraText: root.canAdjustStock ? Strings.t("stock.short.add", "Add stock")
                                       : ""
        extraGlyph: "ic_fluent_add_square_20_regular"

        /* pos's own wording for the same box on the report dialog. */
        suppressText: Strings.t("negstock.mute", "Do not show again")

        onConfirmed: {
            shortStock.settle()
            if (!root.ctrl || !shortStock.info)
                return
            /* A quantity typed into a line is not the same act as a tap on a tile,
               and the payload says which one asked: `row` is -1 for an add. Re-adding
               a unit to a line that already holds four would answer the wrong
               question. */
            if (shortStock.info.row >= 0)
                root.ctrl.setQtyAnyway(shortStock.info.row, shortStock.info.wanted)
            else
                root.ctrl.addAnyway(shortStock.info.product_id)
        }

        /* The adjustment sheet, stacked over this. Deliberately no automatic retry
           afterwards: the operator came here to sell one thing and is now correcting
           a shelf count, and a line appearing by itself when they close the sheet is
           a line they did not ask for. The tile is still where it was. */
        onExtraRequested: {
            shortStock.settle()
            if (shortStock.info)
                root.requestOpen("stock_adjust",
                                 { product_id: shortStock.info.product_id })
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
       declared here would serve exactly one message. Raised clear of the
       panel's checkout region. */
    ToastHost {
        id: toast
        bottomMargin: Tokens.spacing.xxl
    }

    /*
     * The matches, as a dropdown over the tiles.
     *
     * WHY A DROPDOWN AND NOT TILES
     *
     * Typing used to rebuild the tile wall from the results. That conflated two
     * different things: the wall is a layout the operator has learned — the
     * same product in the same place every time, which is the entire reason the
     * arrange screen exists — and a result list is a transient answer to a
     * question. Overwriting the first with the second cost the muscle memory
     * and left the category chip lying about what was on screen.
     *
     * WHY IT IS A POPUP AND NOT AN INLINE PANEL
     *
     * It has to be able to cover the tiles. An inline row would either push the
     * grid down as it grew, moving every tile while the operator is aiming at
     * one, or need a fixed height reserved whether or not anything is being
     * searched.
     *
     * `closePolicy: NoAutoClose` because the field keeps focus while this is
     * open — every keystroke goes to the search box, and a popup that closes
     * on the first key press is a popup that never opens.
     */
    QC.Popup {
        id: matches

        /* Anchored under the field rather than the bar: the bar also holds the
           picker button, and the list belongs to the thing being typed into. */
        parent: filters
        x: 0
        y: filters.height + Tokens.spacing.xs
        width: filters.width
        /* Sized from the MODEL, not from the list's contentHeight — reading
           contentHeight here is circular (the content is a child of the
           popup), and the row count is known before any of that. Snapped to
           whole rows: a sixth row sliced through the middle reads as a
           rendering fault rather than as "there is more, scroll". */
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
            /* THE SCROLLBAR'S SEAT, spent by the delegate's rows below. The
               Fluent bar is an overlay pinned inside the view's trailing
               edge that widens to 12px the moment it is used — over
               whatever a row put there. A view-level anchors.rightMargin
               binds nothing here (a ListView in a popup does not anchor;
               it fills the contentItem's box), so the rows pay the seat
               out of their own trailing padding instead — the same rule
               CartLine and PartySelect already follow — and the bar glides
               over clear sheet beside the prices. */
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
                    /* The scrollbar's seat, spent here (see the list's own
                       note): the prices stay a full seat clear of the edge
                       the bar widens over, on every row. Mirrors in Arabic,
                       as anchors do. */
                    anchors.rightMargin: Tokens.spacing.sm
                                          + Tokens.size.scrollSeat
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
                            /* The barcode is why a partial code typed by hand
                               finds anything, so it is worth showing which one
                               matched; the category comes second because two
                               products often share a name. */
                            text: {
                                var parts = []
                                if (hit.modelData.barcode)
                                    parts.push("\u200e" + hit.modelData.barcode)
                                if (hit.modelData.category)
                                    parts.push(hit.modelData.category)
                                return parts.join("  ·  ")
                            }
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            color: Fluent.textTertiary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    /* The one-word pill, for the two things a result can be
                       that a tile never is. */
                    Tag {
                        visible: hit.modelData.hidden === true
                        label: Strings.t("products.hidden_on_pos",
                                         "Hidden on the till")
                        tone: "warning"
                    }

                    Tag {
                        visible: hit.modelData.stock <= 0
                        label: Strings.t("pos.tile.out_of_stock",
                                         "Out of stock")
                        tone: "danger"
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.minimumWidth: 90
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
    // THE PAYMENT SHEET
    // =====================================================================
    /*
     * The shared payment sheet, told what this cart is worth and what the
     * customer already owes. It owns the keypad and the "left after this"
     * figure; this page owns only what to do with the answer.
     *
     * `allowZero` is on because nothing paid is a real answer at a till: it is
     * a debt sale, and Python decides that from the amount rather than from a
     * separate button.
     *
     * Seeded with the total for Cash, empty for Partial — the two doors into
     * the same sheet, one confirming the money and one asking about it.
     */
    PaymentEntry {
        id: payment

        heading: Strings.t("pos.partial.title", "Part payment")
        due: root.ctrl ? root.ctrl.total : 0
        allowZero: true
        confirmText: Strings.t("action.confirm", "Confirm")

        /* Rewriting an invoice: what is entered becomes the invoice's total paid,
           so the sheet opens on what was already paid and says out loud that a new
           figure replaces it. `update_sale` is explicit about the rule (db.py) and
           the mistake it prevents is a customer's debt moving the wrong way. */
        replaces: root.ctrl ? root.ctrl.editing > 0 : false
        alreadyPaid: root.ctrl ? root.ctrl.editingPaid : 0
        seedAmount: root.ctrl && root.ctrl.editing === 0
                    ? root.ctrl.total : 0

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
