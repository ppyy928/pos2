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
    // Deep emerald. Carried over from MIZAN's audited palette: white-on-accent
    // is ~5.4:1, so it is safe as a filled CTA, which #605ed2 (Fluent's
    // default) is not at this text size.
    readonly property color brand:        isDark ? "#3ECF7A" : "#127A4B"
    readonly property color brandHover:   isDark ? "#62DB94" : "#0E6B42"
    readonly property color brandPressed: isDark ? "#2AB867" : "#0B5C38"
    readonly property color brandTint:    isDark ? "#12351F" : "#E7F2EB"
    readonly property color onBrand:      isDark ? "#06240F" : "#FFFFFF"

    // =====================================================================
    // CHANNEL PALETTE — the "coloured" half of the brief
    // =====================================================================
    // Eight hues in one lightness band so they read as a family rather than a
    // rainbow. Each is an ink (text/icon/border on light surfaces) paired with
    // a tint (fill behind that ink). Assigned by MEANING, never by position:
    // a module keeps its hue everywhere it appears — nav, KPI, chart series,
    // badge, receipt.
    readonly property QtObject hue: QtObject {
        readonly property color emerald: isDark ? "#3ECF7A" : "#127A4B"   // money in, cash, confirm
        readonly property color indigo:  isDark ? "#8C9EFF" : "#3949AB"   // card, sales
        readonly property color teal:    isDark ? "#4FD1C5" : "#14707C"   // stock, info
        readonly property color amber:   isDark ? "#E8B04B" : "#B0700F"   // credit, due, warning
        readonly property color crimson: isDark ? "#F87171" : "#C4342B"   // money out, loss, destroy
        readonly property color violet:  isDark ? "#B69BE8" : "#6A3AAF"   // analytics, reports
        readonly property color rose:    isDark ? "#EE8FB4" : "#B02A63"   // customers, debts
        readonly property color slate:   isDark ? "#9FB0C9" : "#46556E"   // neutral, archived
    }

    readonly property QtObject tint: QtObject {
        readonly property color emerald: isDark ? "#12351F" : "#E7F2EB"
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
    // DARK CHROME — nav rail and the POS totals dock
    // =====================================================================
    // The rail and the dock are the two surfaces that stay dark in both
    // themes. They anchor the layout and make the coloured content pop.
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
    readonly property color loginFrom: "#0C4A4E"
    readonly property color loginTo:   "#05090F"

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
        readonly property int navExpanded:  300
        readonly property int navCompact:    68

        // POS.
        /* cartRow carries an inline quantity stepper, which pos does not have:
           there, changing a quantity means selecting the line and retyping it on
           the numpad, or opening a dialog. A 48px −/+ pair on the row itself is
           the single biggest touch win available here, and it sets the floor:
           name line (23) + gap (2) + stepper (48) + padding (2×6) = 85.

           It was 120, which left 35px of air per row and fitted three lines in the
           cart's column — a sale of four items had to be scrolled to be read, which
           is the one list on this screen an operator checks against the goods in
           front of them. 88 is the content plus a hair, and fits five. */
        readonly property int cartRow:       88

        /* Tile metrics are derived from their own content, not from a multiple
           of pos's 180×110 — that tile was sized around 12px type, and scaling
           the box by 1.5 while the type inside grows by 1.4 would just inherit
           its proportions by accident.

               padding      14
               name         52   two lines of font.tileName (18px → 26 each)
               gap           6
               price        34   one line of font.tilePrice (26px)
               padding      14
                          ----
                          120

           tileMin is a floor, not a fixed width, and `tileColumns` is the count the
           wall aims for: the grid takes the smaller of the two, so a narrow window
           drops to three or two and a wide one stays at four with the surplus spread
           between the tiles rather than baked into them.

           168 rather than the 200 this started at. 200 put three tiles across the
           till's product zone and left the fourth column's worth of space spread as
           padding inside them — a wall of big cards with fewer products on it, which
           is the opposite of what a tile wall is for. At 168 a name still gets two
           lines at 18px (about 15 characters a line, which covers "Coca-Cola 1.5L"
           and elides the pack size — the tooltip carries the untruncated name). */
        readonly property int tile:         120   // product tile total height
        readonly property int tileName:      52   // two lines of tile name
        readonly property int tileMin:      168   // narrowest a tile may flow to

        /*
         * The wall's column count, and the widest a tile draws.
         *
         * WHY THE COUNT IS FIXED AND NOT FLOWED
         *
         * It was flowed from `tileMin`, which meant the navigation rail decided it:
         * collapsing the rail widens the product zone by 240px, so the wall jumped
         * from four columns to five and every tile in it changed size and position
         * mid-sale. A cashier's hand learns where a product IS. Reflowing the whole
         * wall as a side effect of collapsing a menu is the kind of thing that makes
         * somebody tap the wrong tile.
         *
         * So four is the target at any width that can hold four, and the extra room
         * from a collapsed rail becomes gutter between the tiles instead of a fifth
         * column. `tileMax` is what caps them: without it, "not reflowing" would
         * just mean four increasingly enormous cards.
         *
         * 192 is what a tile is at the normal layout — the zone at 795px, four
         * columns, one gap out of each cell — so the cap does nothing until the rail
         * is collapsed and then holds the tiles exactly where they were.
         */
        readonly property int tileColumns:    4
        readonly property int tileMax:      192

        /* The photo card — the same tile with a picture above it.
         *
         *     padding      12
         *     photo        84   the band, inset by the card's own padding
         *     gap          12
         *     name         52
         *     slack        10   where a one-line name leaves its room
         *     price        34
         *     padding      12
         *                ----
         *                 216   = tile + tileImage + spacing.sm
         *
         * Derived from the compact tile rather than typed as a second number:
         * everything below the photo IS the compact tile, so a change to the name
         * or the price line moves both cards and cannot move only one.
         *
         * 84 is a deliberate band and not a square, and it came down from 112: a
         * square photo on a 192px card is 192px tall and pushes the price line off a
         * 1080p screen at three rows. It is also the honest size for a shop that has
         * photographed part of its catalogue — the band a product without a photo
         * shows is empty, and 84 wastes a third less of the card than 112 did while
         * still reading as a picture frame at about 2:1. */
        readonly property int tileImage:     84   // the photo band
        readonly property int tileMedia:    tile + tileImage + 12
        /* A photo needs more width than a name does before it reads as a photo
           rather than a stripe. 176 keeps the band at about 2:1 and takes four
           across the till's product zone, same as the compact card. */
        readonly property int tileMediaMin: 176

        /* The form's own thumbnail. Square, because that is the shape of the
           question "which picture is this?" and it sits beside a column of
           fields whose height it has to match. */
        readonly property int thumb:        168

        readonly property int numpadKey:     72
        readonly property int dock:         180   // totals dock

        /* The cart column is pinned, as it is in pos — but to 500, not pos's
           470. What sets the floor is the numpad: five columns (three digits,
           and the mode column pos puts the entry modes in) at numpadKey 72,
           with 8px gaps and 20px card padding, is 5×72 + 4×8 + 2×20 = 432.
           500 leaves the cart lines' amount column room to hold a six-figure
           total at font.amount without eliding. */
        readonly property int cartColumn:   500

        // Tables — 56 not 48, because a finger scrolls these.
        readonly property int tableRow:      56
        readonly property int tableHeader:   48

        // Padding.
        readonly property int pagePadding:   28
        readonly property int cardPadding:   20
        readonly property int gutter:        20
    }

    readonly property QtObject radius: QtObject {
        readonly property int sm:  6
        readonly property int md: 10
        readonly property int lg: 16
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
    readonly property QtObject font: QtObject {
        readonly property string family: Fluent.typography.fontFamily

        // Straight through from the scaled Fluent ramp, aliased so pages never
        // reach into two token objects for type.
        readonly property int caption:   Fluent.typography.caption      // 15
        readonly property int body:      Fluent.typography.body         // 17
        readonly property int bodyLarge: Fluent.typography.bodyLarge    // 21
        readonly property int subtitle:  Fluent.typography.subtitle     // 24
        readonly property int title:     Fluent.typography.title        // 32

        // POS-only. The total is read from a metre away, standing up.
        readonly property int overline:   13   // table headers, KPI labels (caps)
        readonly property int tileName:   18
        readonly property int tilePrice:  26
        readonly property int amount:     34   // cart line totals, KPI values
        readonly property int posTotal:   64
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
