pragma Singleton
import QtQuick
import FluentControls

/*
 * MIZAN design tokens — the single source of truth for colour and metrics.
 *
 * Layering, and why:
 *   FluentControls/Fluent   surfaces, elevation, control fills, focus rings.
 *                           Untouched — it is the Fluent look the product is
 *                           built on, already scaled up by tools/scale_fluent.py.
 *   Mizan.Tokens (here)     brand accent, the semantic *channel* palette, and
 *                           the POS-specific metrics Fluent has no concept of
 *                           (cart rows, totals hero, numpad keys, pay heroes).
 *
 * Two merchant requirements drive every value below:
 *   BIGGER   every interactive height starts at 48 and climbs from there; the
 *            POS rail and keypad sit at 64 because they are hit with a finger
 *            at speed, often without looking.
 *   COLOURED colour is not decoration here — each module and each money
 *            movement owns a hue, so an operator identifies a screen and a
 *            number by colour before reading a single word. Every ink/tint
 *            pair below clears 4.5:1 against its own surface.
 */
QtObject {
    id: tokens

    readonly property bool isDark: Fluent.isDark

    // =====================================================================
    // BRAND
    // =====================================================================
    // The one emerald. White-on-accent clears 4.5:1 at the text sizes this
    // app draws it at, so it is safe as a filled CTA. The hover/pressed pair
    // are the same hue stepped in lightness — a button that shifts hue under
    // the thumb reads as a different button.
    readonly property color brand:        isDark ? "#3ECF7A" : "#087F5B"
    readonly property color brandHover:   isDark ? "#62DB94" : "#066B4D"
    readonly property color brandPressed: isDark ? "#2AB867" : "#05573F"
    readonly property color brandTint:    isDark ? "#12351F" : "#E8F5EF"
    readonly property color onBrand:      isDark ? "#06240F" : "#FFFFFF"

    /* A disabled PRIMARY, drawn by this app rather than borrowed from the
       style: the vendored Fluent has no controlFillDisabled at all (a
       binding that names it silently keeps the last valid colour — an
       emerald button that never greys), and Fluent's own answer for a
       disabled accent button is the accent fill with pale text, which the
       brief forbids: "disabled must visibly look disabled, not like an
       active green button with faded text". Neutral grey, clearly inert. */
    readonly property color disabledFill: isDark ? "#2E3742" : "#C7CDD5"

    // =====================================================================
    // CHANNEL PALETTE — the "coloured" half of the brief
    // =====================================================================
    // Eight hues in one lightness band so they read as a family rather than a
    // rainbow. Each is an ink (text/icon/border on light surfaces) paired with
    // a tint (fill behind that ink). Assigned by MEANING, never by position:
    // a module keeps its hue everywhere it appears — nav, KPI, chart series,
    // badge, receipt.
    readonly property QtObject hue: QtObject {
        // The first entry is the brand's own hue — one accent, not two greens.
        readonly property color emerald: isDark ? "#3ECF7A" : "#087F5B"   // money in, cash, confirm
        readonly property color indigo:  isDark ? "#8C9EFF" : "#3949AB"   // card, sales
        readonly property color teal:    isDark ? "#4FD1C5" : "#14707C"   // stock, info
        readonly property color amber:   isDark ? "#E8B04B" : "#B0700F"   // credit, due, warning
        readonly property color crimson: isDark ? "#F87171" : "#C42B1C"   // money out, loss, destroy
        readonly property color violet:  isDark ? "#B69BE8" : "#6A3AAF"   // analytics, reports
        readonly property color rose:    isDark ? "#EE8FB4" : "#B02A63"   // customers, debts
        readonly property color slate:   isDark ? "#9FB0C9" : "#46556E"   // neutral, archived
    }

    readonly property QtObject tint: QtObject {
        readonly property color emerald: isDark ? "#12351F" : "#E8F5EF"
        readonly property color indigo:  isDark ? "#191E3F" : "#E8EAF7"
        readonly property color teal:    isDark ? "#0F2E2B" : "#DFEFF1"
        readonly property color amber:   isDark ? "#3A2C10" : "#FBEEDB"
        readonly property color crimson: isDark ? "#3D1C1C" : "#FAE7E5"
        readonly property color violet:  isDark ? "#241A38" : "#EFE8F9"
        readonly property color rose:    isDark ? "#37121F" : "#FBE6EF"
        readonly property color slate:   isDark ? "#222B41" : "#EDF1F6"
    }

    // Module -> hue. One lookup so nav, dashboard tiles, page headers and
    // chart series can never disagree about what colour "purchases" is.
    readonly property var moduleHue: ({
        "dashboard": hue.violet,
        "pos":       hue.emerald,
        "sales":     hue.indigo,
        "products":  hue.teal,
        "purchases": hue.amber,
        "customers": hue.rose,
        "payments":  hue.emerald,
        "cash":      hue.emerald,
        "employees": hue.slate,
        "reports":   hue.violet,
        "settings":  hue.slate,
        "backup":    hue.slate
    })

    readonly property var moduleTint: ({
        "dashboard": tint.violet,
        "pos":       tint.emerald,
        "sales":     tint.indigo,
        "products":  tint.teal,
        "purchases": tint.amber,
        "customers": tint.rose,
        "payments":  tint.emerald,
        "cash":      tint.emerald,
        "employees": tint.slate,
        "reports":   tint.violet,
        "settings":  tint.slate,
        "backup":    tint.slate
    })

    function hueFor(moduleKey) {
        return moduleHue[moduleKey] !== undefined ? moduleHue[moduleKey] : hue.slate
    }

    function tintFor(moduleKey) {
        return moduleTint[moduleKey] !== undefined ? moduleTint[moduleKey] : tint.slate
    }

    // The channel hues again, but pinned to their light-on-dark variants and
    // NOT switched on the theme. The nav rail and the POS totals dock stay dark
    // in both themes, so a theme-switched hue would put #127A4B emerald on
    // #24304E navy in light mode — invisible. Same reasoning that already
    // produced onChromeDanger / onChromeSuccess below; this generalises it.
    readonly property QtObject chromeHue: QtObject {
        readonly property color emerald: "#3ECF7A"
        readonly property color indigo:  "#8C9EFF"
        readonly property color teal:    "#4FD1C5"
        readonly property color amber:   "#E8B04B"
        readonly property color crimson: "#F87171"
        readonly property color violet:  "#B69BE8"
        readonly property color rose:    "#EE8FB4"
        readonly property color slate:   "#9FB0C9"
    }

    readonly property var moduleChromeHue: ({
        "dashboard": chromeHue.violet,
        "pos":       chromeHue.emerald,
        "sales":     chromeHue.indigo,
        "products":  chromeHue.teal,
        "purchases": chromeHue.amber,
        "customers": chromeHue.rose,
        "payments":  chromeHue.emerald,
        "cash":      chromeHue.emerald,
        "employees": chromeHue.slate,
        "reports":   chromeHue.violet,
        "settings":  chromeHue.slate,
        "backup":    chromeHue.slate
    })

    /* Module hue for use on the permanently-dark chrome (rail, dock). */
    function chromeHueFor(moduleKey) {
        return moduleChromeHue[moduleKey] !== undefined
            ? moduleChromeHue[moduleKey] : chromeHue.slate
    }

    // =====================================================================
    // SEMANTICS — tone is earned by the VALUE, never by the position
    // =====================================================================
    readonly property color success: hue.emerald
    readonly property color info:    hue.teal
    readonly property color warning: hue.amber
    readonly property color danger:  hue.crimson

    readonly property color successTint: tint.emerald
    readonly property color infoTint:    tint.teal
    readonly property color warningTint: tint.amber
    readonly property color dangerTint:  tint.crimson

    /* Tone *names* -> colour. pos's tables and badges are driven by the five
       names "success" | "info" | "warning" | "danger" | "primary", decided per
       row by the page, so the name is what crosses the boundary and this is
       where it turns back into a colour. An empty or unknown name is neutral
       rather than an error: a row with nothing remarkable about it is the
       common case, not a mistake.

       `toneInk` is text and icons, `toneFill` the soft background behind them. */
    function toneInk(name) {
        switch (name) {
        case "success": return success
        case "info":    return info
        case "warning": return warning
        case "danger":  return danger
        case "primary": return brand
        }
        return Fluent.textSecondary
    }

    function toneFill(name) {
        switch (name) {
        case "success": return successTint
        case "info":    return infoTint
        case "warning": return warningTint
        case "danger":  return dangerTint
        case "primary": return brandTint
        }
        return Fluent.subtleSecondary
    }

    /* Pick a tone for a signed amount. Zero is deliberately neutral — a 0.00
       balance is not a success and not a problem. */
    function toneForAmount(amount) {
        if (amount > 0) return success
        if (amount < 0) return danger
        return Fluent.textSecondary
    }

    // =====================================================================
    // WORKSPACE — the quiet canvas the Login and POS screens sit on
    // =====================================================================
    /* The POS's two greys: a cool app canvas and a product workspace one step
       lighter, so the white tiles and the white transaction panel both have
       something to sit against. The structural border is the one every edge
       on those two screens shares — strong enough to be seen at a counter,
       quiet enough that sixty tiles do not read as sixty boxes. Opaque on
       purpose — Fluent's card surfaces are translucent for Mica, and a
       translucent card over a flat canvas is a card nobody can see the edge
       of. */
    readonly property QtObject workspace: QtObject {
        readonly property color canvas:  isDark ? "#1B1F27" : "#E9EDF2"
        readonly property color surface: isDark ? "#232830" : "#FFFFFF"
        readonly property color inset:   isDark ? "#2A303A" : "#F0F2F5"
        readonly property color shelf:   isDark ? "#1F242C" : "#F2F4F7"
        readonly property color border:  isDark ? "#333A45" : "#CBD3DD"
        readonly property color text:    isDark ? "#E7ECF6" : "#182230"
        readonly property color textSub: isDark ? "#97A3BD" : "#566579"
    }

    // =====================================================================
    // THE NAVIGATION SIDEBAR — dark navy, in both themes
    // =====================================================================
    /* The merchant's first requirement: the rail must be distinguishable from
       the workspace at a glance, by surface colour and not by a hairline. A
       navy #142033 family that stays dark whichever theme the pages wear, so
       the separation never depends on the operator's theme choice. Hover and
       active are the merchant's own steps of the same hue; the emerald marker
       is the brand's, pinned light because it sits on navy in both themes. */
    readonly property QtObject navy: QtObject {
        readonly property color base:    isDark ? "#101A29" : "#142033"
        readonly property color hover:   isDark ? "#1B2C44" : "#1D2E47"
        readonly property color active:  isDark ? "#203649" : "#223A4D"
        readonly property color border:  isDark ? "#0B1421" : "#0D1626"
        readonly property color caption: "#7E90AC"
        readonly property color text:    "#E7ECF6"
        readonly property color muted:   "#9AAAC2"
        readonly property color mark:    "#3ECF7A"
    }

    // =====================================================================
    // THE TOTAL BLOCK — dark petrol, the anchor of the transaction panel
    // =====================================================================
    /* The final amount is the one figure on the till read from a metre away,
       standing up, by somebody about to hand over money for it. A dark petrol
       surface makes it unmistakable without shouting: darker than the white
       cart, lighter than the navy rail, with a cool emerald accent for the
       label and pure white for the figure itself. */
    readonly property QtObject totalBlock: QtObject {
        readonly property color base:    isDark ? "#0F222C" : "#142B38"
        readonly property color edge:    isDark ? "#1E3A48" : "#1D3D4D"
        readonly property color label:   "#75E2BC"
        readonly property color amount:  "#FFFFFF"
        readonly property color meta:    "#8FA9B8"
    }

    // =====================================================================
    // DARK CHROME — nav rail and the POS totals dock
    // =====================================================================
    // The dock stays dark in both themes (the purchase dialog still uses it);
    // the rail is light now, so only the dock family reads from here.
    readonly property color chromeFrom:   "#141C30"
    readonly property color chromeTo:     "#0F1526"
    readonly property color chromeHover:  "#1D2740"
    readonly property color chromeActive: "#24304E"
    readonly property color chromeBorder: "#232E49"
    readonly property color onChrome:     "#E7ECF6"
    readonly property color onChromeMuted:"#97A3BD"

    // Ink tuned for the dark dock specifically — plain crimson/emerald fail
    // contrast on navy, these clear 4.5:1.
    readonly property color onChromeDanger:  "#FFB4AB"
    readonly property color onChromeSuccess: "#7BE3AE"

    readonly property color dockFrom: "#16233A"
    readonly property color dockTo:   "#0F1930"

    // Login backdrop. Fixed in both themes — it is the product's front door.
    // A navy-to-petrol run with light held in the middle rather than fading
    // to black at the bottom: the lower half of the old teal-to-black
    // gradient read as dead space, and a front door should not trail off.
    readonly property color loginFrom: "#101C2E"
    readonly property color loginMid:  "#12303B"
    readonly property color loginTo:   "#143B45"

    /* The login card sits on that fixed dark gradient in BOTH themes, so its
       surfaces cannot come from Fluent.cardBackground: those are translucent by
       design (70% white in light, 5% white in dark) because they are meant to
       sit over Mica. Over dark teal, 70% white reads as murky sage and 5% white
       is invisible. These are opaque, and still follow the theme.

       FluentPySide has no shadow of any kind — no MultiEffect, no layer.effect,
       nothing — so depth here is built the way the library builds it: opaque
       surface against translucent backdrop, a 1px border, and a lighter rim
       along the top edge. No new import, and it matches the rest of the UI. */
    readonly property color loginSurface: isDark ? "#141A22" : "#FFFFFF"
    readonly property color loginBorder:  isDark ? "#26303C" : "#14000000"
    readonly property color loginRim:     isDark ? "#33404F" : "#FFFFFF"

    // =====================================================================
    // METRICS — bigger than the desktop Fluent defaults, on purpose
    // =====================================================================
    readonly property QtObject size: QtObject {
        // Interactive heights. 48 is the floor; nothing an operator taps is
        // ever smaller, including inside dense tables.
        readonly property int controlSmall:  40   // filters, chrome-only tools
        readonly property int control:       48   // every field and button
        readonly property int command:       56   // command bars, dialog primaries
        readonly property int posCommand:    64   // POS rail, keypad, pay heroes
        readonly property int posHero:       80   // the two payment heroes

        // Surfaces.
        readonly property int topBar:        64
        readonly property int taskHeader:    72
        /* 224, not 300: the rail is navigation, not a page. 224 holds every
           destination label in all three languages (the previous 300 spent its
           surplus on air beside the labels), and the 76 pixels it gives back
           are two thirds of a product-tile column on the selling screen. */
        readonly property int navExpanded:  224
        readonly property int navCompact:    68

        // POS.
        /* cartRow carries an inline quantity stepper, which pos does not have:
            there, changing a quantity means selecting the line and retyping it on
            the numpad, or opening a dialog. A 48px −/+ pair on the row itself is the
            single biggest touch win available here, and it sets the floor.

            The row is two lines: the name with the line total on the first,
            the unit price, the stepper and Remove on the second —
              name line (23) + gap (2) + stepper (48) + hair = 74
            — so six rows fit where five did at 88 and four at the original
            120. The floor is the stepper's 48 and the name line is type, so
            it cannot go lower without giving one of those up.

            Scaled with the text, for the tile's reason: the name line is type, and
            a 21px name under a fixed 74 would push the stepper out of the card. */
        readonly property int cartRow:      Math.round(74 * tokens.fontScale)

        /*
         * COMPACT, TEXT-FIRST TILES.
         *
         *     padding      12
         *     name         44   two lines of font.tileName (17px → 22 each)
         *     gap           6
         *     price        28   one line of font.tilePrice (20px)
         *     padding      12
         *                ----
         *                102
         *
         * The card leads with its text. A product without a photo is the
         * normal case, not a degraded one, so the no-photo tile IS the tile;
         * a photo is a compact band this card grows above the name, sized for
         * recognition rather than display. The large framed placeholder this
         * replaced reserved 40% of every card for a picture most products do
         * not have.
         *
         * tileMin is a floor, not a fixed width, and `tileColumns` is the
         * count the wall aims for: the grid takes the smaller of the two, so
         * a narrow window drops to three or two and a wide one stays at four
         * with the surplus spread between the tiles rather than baked into
         * them.
         *
         * THE TEXT ZONES SCALE WITH THE TEXT SIZE. The tile is a container
         * for type, not a touch target: at `ui.font_scale` large the name
         * needs its two lines and the price needs a wider card to stay on one
         * line, and fixed values would clip both. So tile, tileName, tileMin,
         * tileMax and the photo band all grow with `fontScale`; the paddings
         * are the one thing held constant — they are the frame around the
         * type, not the type. */
        readonly property int tile:         Math.round(102 * tokens.fontScale)
        readonly property int tileName:     Math.round(44 * tokens.fontScale)
        readonly property int tileMin:      Math.round(160 * tokens.fontScale)

         /*
          * The ARRANGE screen's column count, and the text tile's ceiling.
          *
          * The till's own wall flows its columns from the width it is
          * given now — a card with both a floor and a ceiling makes the
          * arithmetic safe, and a wider window simply shows more products.
          * The arrange screen keeps the fixed count: it is a picture of
          * the wall as the till shows it, and the count is part of the
          * answer "which tile is where?" it exists to edit.
          *
          * `tileMax` remains the text tile's ceiling on the till — the
          * surplus of a wide cell is gutter, never a wider card.
          *
          * Scaled with the text, for tileMin's reason: the cap is the widest a
          * card draws, and a card at a larger text size is a wider card.
          */
        readonly property int tileColumns:    4
        readonly property int tileMax:      Math.round(192 * tokens.fontScale)

        /* The image card is HORIZONTAL now: a true square on the leading edge,
         * the product's words beside it.
         *
         *     ┌────────┬────────────────────────────┐
         *     │        │ Atlas Detergent 5Kg        │
         *     │ square │ 1,017.13          Stock 70│
         *     └────────┴────────────────────────────┘
         *
         * The square is the recognition target — 84 is inside the 72–88 band a
         * photo needs to be told apart from its neighbour at a glance — and
         * the card's height is its CONTENT's: two name lines plus one money
         * line plus the paddings. The square fills the card's full height
         * (the merchant's rule: the photo's height IS the card's, no empty
         * strips above or below), and the words centre vertically beside it.
         *
         * The card's padding is Tokens.spacing.sm on all four sides, equal
         * by design for the WORDS' column; the square's edge spans border to
         * border on its own side.
         *
         * tileMediaMin is the width at which that composition still reads:
         * the square, the frame's padding, and a text column wide enough
         * for a wrapped name. The wall drops to the compact text tile
         * below two columns of this — one fat card is a wall with nothing
         * on it. tileMediaMax is the ceiling: past it the surplus goes to
         * the gutter, never to a wider card.
         *
         * Scaled with the text, like every other part of the card's shape: a
         * larger text size is a taller name, a wider price, a bigger square. */
        readonly property int tileImage:     Math.round(84 * tokens.fontScale)
        readonly property int tileMedia:     Math.round(94 * tokens.fontScale)
        /* PosTile's height in its photo face, for a GridView that has to pick
         * a cell height BEFORE the first card exists. The same terms the card
         * itself sums — two paddings, the two-line name band, the money block
         * — written once here so the till's wall and the arrange screen size
         * their cells from the identical number, and neither can drift from
         * the card those cells hold. */
        readonly property int tileMediaHeight: {
            var money = Math.round(tokens.font.tilePrice * 1.35)
                        + (tokens.spacing.xs
                           + Math.round(tokens.font.caption * 1.4))
            return 2 * tokens.spacing.sm + tileName + money
        }
        /* A LITTLE WIDER than the first cut (200), then wider again: at 200
           a two-word name still wrapped under itself, and at 210 the wall
           still paid for every column in wrapped second lines — the merchant
           asked for cards wide enough that one-line names are the norm, not
           the lucky case. 220 raw holds THREE columns in the 1096px
           workspace at this shop's font scale with room left for wider
           cells: the grid settles at 3 × ~355px cards, the words' column
           beside the photo runs ~213px, and a two-word name sits on one
           line. The column the fourth bench used to occupy was never worth
           the wrap it cost. */
        readonly property int tileMediaMin:  Math.round(220 * tokens.fontScale)
        readonly property int tileMediaMax:  Math.round(360 * tokens.fontScale)

        /* The form's own thumbnail. Square, because that is the shape of the
           question "which picture is this?" and it sits beside a column of
           fields whose height it has to match. */
        readonly property int thumb:        168

        readonly property int numpadKey:     72
        /* The till's own pad, drawn inside the transaction panel rather than
            in a modal. 56: the merchant's own range after a round of "the
            digits are too small to strike without looking" — every key is
            struck in peripheral vision, and the pad now fills the panel's
            width beside the readout, so height is the only lever left for
            hit area. The modal sheets keep the 72 above. */
        readonly property int keypadKey:     56
        /* The sale-action toolbar's buttons: icon and label both, at a size an
           arm's-length tap can find. 56 after the merchant's round: 46 fit
           the word and the glyph but read as chrome rather than as a command
           — the same height the app gives every primary control. */
        readonly property int actionKey:     56
        /* The Cash / Debt row's height inside the payment heroes, and the
           full-width payment bar the total and the heroes share at the
           screen's foot — one row, one height, the two decisions a till
           makes a hundred times a day. Taller than the last cut (76/84):
           the merchant asked for a bar that reads even better from standing
           height — the total figure at 54px and both buttons near 84 tall —
           and the pay bar is the last thing on the screen, so the height it
           spends is height the tile wall above it could not keep anyway. */
        readonly property int payRow:        84
        readonly property int payBar:        92
        readonly property int dock:         180   // totals dock

        /* The transaction panel's width, pinned. 420: wide enough for a
           six-figure line total beside a name and a stepper, a 3-key-wide
           keypad with its mode column, and the Cash / Partial row — and no
           wider, because every pixel past it is a pixel taken from the
           product wall. */
        readonly property int cartColumn:   Math.round(420 * tokens.fontScale)

        // Tables — 56 not 48, because a finger scrolls these.
        readonly property int tableRow:      56
        readonly property int tableHeader:   48

        /* The scrollbar's seat, reserved. The Fluent bar is an overlay
           pinned inside the view's trailing edge: 4px at rest, widening to
           12 the moment it is used — over whatever a row put there. A
           ListView's own `anchors.rightMargin` moves the view AND its rows
           together, so the old margin-only reservation still put the
           widened bar on top of the trailing figures. The seat is spent by
           the CONTENT instead (the row's own trailing margin, the
           delegate's width), leaving clear sheet for the bar to glide
           over; 16 is the 12px bar plus a hair of daylight. */
        readonly property int scrollSeat:    16

        // Padding.
        readonly property int pagePadding:   28
        readonly property int cardPadding:   20
        readonly property int gutter:        20
    }

    readonly property QtObject radius: QtObject {
        readonly property int sm:  6   // inputs, chips, small controls
        readonly property int md:  8   // tiles, buttons, cart rows
        readonly property int lg:  12  // major surfaces: cards, panels
        readonly property int pill: 9999
    }

    // Icon sizes. Fluent System Icons is a variable font, so these are free.
    readonly property QtObject icon: QtObject {
        /* 14 pairs with `font.overline` (13) — a table's sort arrow beside a 13px
           caps heading, and nothing larger fits on that line. */
        readonly property int xs: 14
        readonly property int sm: 18
        readonly property int md: 24
        readonly property int lg: 32
        readonly property int xl: 44   // pay heroes, empty states
    }

    /*
     * TABULAR FIGURES, for every number this product prints.
     *
     *     font.features: Tokens.figures
     *
     * Segoe UI Variable's default digits are PROPORTIONAL: measured at 34px, ten 1s
     * are 130px wide and ten 0s are 190px. So `1,111.11` and `8,888.88` are different
     * lengths, a money column never lines up under its own heading, and a total that
     * ticks from 999 to 1,000 physically moves. `tnum` switches the font to its
     * tabular set — every digit the same advance — which is what a figure that will
     * be compared against another figure needs.
     *
     * An OpenType feature rather than a bundled font: the typeface already has the
     * glyphs, and shipping a second family for numerals would mean a licence to
     * carry, a binary in the tree, and two typefaces in one total. `font.features`
     * needs Qt 6.7; this app runs 6.9.
     *
     * Money, quantities, counts, dates, page numbers — anything read as a quantity.
     * Not prose, where proportional digits are correct.
     */
    readonly property var figures: ({ "tnum": 1 })

    // =====================================================================
    // TYPE — POS-specific sizes on top of the scaled Fluent type ramp
    // =====================================================================
    /* The text-size setting, as a factor of normal. Every size in the `font`
       block below is multiplied by it, which is the whole implementation of
       `ui.font_scale`: there is no second type ramp to switch to, only one
       ramp drawn larger, and a Text that asks for body gets 17, 19 or 21
       depending on what the shop chose.

       Read off the settings controller rather than a context property so the
       switch is live — the controller re-notifies on the write, this binding
       re-runs, and every bound `font.pixelSize` in the app follows. Guarded,
       because tokens exist in builds without the bridge (qml_check, a bare
       preview) and must stand alone there.

       Geometry does NOT scale with it: the control heights and row metrics
       above are touch targets, chosen for a finger, and pos's own large sizes
       grew type inside fixed widget rows too. */
    readonly property real fontScale: (typeof app !== "undefined" && app
                                       && app.settings)
                                      ? app.settings.fontScale : 1.0

    readonly property QtObject font: QtObject {
        readonly property string family: Fluent.typography.fontFamily

        // Straight through from the scaled Fluent ramp, aliased so pages never
        // reach into two token objects for type.
        readonly property int caption:   Math.round(Fluent.typography.caption * tokens.fontScale)      // 15
        readonly property int body:      Math.round(Fluent.typography.body * tokens.fontScale)         // 17
        readonly property int bodyLarge: Math.round(Fluent.typography.bodyLarge * tokens.fontScale)    // 21
        readonly property int subtitle:  Math.round(Fluent.typography.subtitle * tokens.fontScale)     // 24
        readonly property int title:     Math.round(Fluent.typography.title * tokens.fontScale)        // 32

        // POS-only. The total is read from a metre away, standing up.
        readonly property int overline:   Math.round(13 * tokens.fontScale)  // table headers, KPI labels (caps)
        readonly property int tileName:   Math.round(17 * tokens.fontScale)
        readonly property int tilePrice:  Math.round(20 * tokens.fontScale)
        readonly property int amount:     Math.round(34 * tokens.fontScale)  // cart line totals, KPI values
        /* The pay bar's figure. 42 was still the merchant's "صغير" on the
           second look; 46 at a 72px bar still was on the third, standing
           two steps back from the counter. 50 in an 84px bar was the
           fourth cut, and 54 in the 92px bar is the fifth: same verdict,
           one more step back. The label and meta keep their own line — the
           number that is owed is unmissable from standing height without
           crowding the bar that carries it. */
        readonly property int posTotal:   Math.round(54 * tokens.fontScale)
        /* The cart line's own figure. Not `amount`: 34px on a 78px row crowded
           the name off its own line and rivalled the transaction total under it.
           19 is prominent at arm's length and visibly subordinate to posTotal —
           the line is one of six, the total is the one that is owed. */
        readonly property int lineTotal:  Math.round(19 * tokens.fontScale)
    }

    readonly property QtObject spacing: QtObject {
        readonly property int xs:   6
        readonly property int sm:  12
        readonly property int md:  16
        readonly property int lg:  20
        readonly property int xl:  24
        readonly property int xxl: 32
    }
}
