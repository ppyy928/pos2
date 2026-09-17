import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * On-screen numeric keypad. A pure view: it holds no buffer and no business
 * logic, it reports presses and lets the page decide what they mean.
 *
 *     Numpad {
 *         onKeyPressed: (key) => page.feed(key)
 *     }
 *
 * THREE SHAPES, ONE COMPONENT
 *
 * THE TILL'S PAD — `modes: ["qty", "plus", "minus"]`. The entry-mode column
 * beside the digits, exactly as the till shipped: a quantity, and the two
 * money modes that ride the total as a free line —
 *
 *     ┌────────┬─────┬─────┬─────┐
 *     │ # Qty  │  7  │  8  │  9  │
 *     ├────────┼─────┼─────┼─────┤
 *     │   +    │  4  │  5  │  6  │
 *     ├────────┼─────┼─────┼─────┤
 *     │   −    │  1  │  2  │  3  │
 *     ├────────┼─────┼─────┼─────┤
 *     │   C    │  0  │  .  │  ⌫  │
 *     └────────┴─────┴─────┴─────┘
 *
 * THE ENTRY SHEETS' PAD — the same shape with the sheet's own modes, which
 * is how a delivery line's Cost / Sell / Qty pad is built:
 *
 *     ┌────────┬─────┬─────┬─────┐
 *     │ # QTY  │  7  │  8  │  9  │
 *     ├────────┼─────┼─────┼─────┤
 *     │ COST   │  4  │  5  │  6  │
 *     ├────────┼─────┼─────┼─────┤
 *     │ SELL   │  1  │  2  │  3  │
 *     ├────────┼─────┼─────┼─────┤
 *     │        │  0  │  .  │  ⌫  │
 *     └────────┴─────┴─────┴─────┘
 *
 * THE PLAIN PAD — `modes: []`. Digits over a utility row that leads with
 * Clear, which is all a payment sheet needs:
 *
 *     ┌─────┬─────┬─────┐
 *     │  7  │  8  │  9  │
 *     ├─────┼─────┼─────┤
 *     │  4  │  5  │  6  │
 *     ├─────┼─────┼─────┤
 *     │  1  │  2  │  3  │
 *     ├─────┼─────┼─────┤
 *     │  0  │  .  │  ⌫  │
 *     └─────┴─────┴─────┘
 *
 * The whole pad mirrors in Arabic, because it is built from Layouts, which
 * mirror — a mirrored numpad is correct, the digit order being a reading
 * order rather than a fixed spatial arrangement.
 *
 * WHY + AND − ARE MODE TOGGLES, NOT STEPPERS
 *
 * On the till they are not "one more / one less of the selected line" —
 * that is the row's own stepper in the cart, and it never left. They are
 * the money modes: + types a free charge line ADDED to the total, − a
 * cart-level discount line SUBTRACTED from it, both committed as a new
 * free line (qty 1) by the page's Submit through the bridge's
 * addFreeAmount. As toggles they ride the same `modeRequested` signal the
 * sheets' modes do — the page owns keypadMode, the key only asks, and the
 * highlighted key is the mode the typed number will take.
 *
 * WHY + AND − ARE GLYPHS ALONE
 *
 * The icon is already a plus; a "+ AMT" under it printed the plus twice,
 * and the mode it names is the lit key one row over. The word stays in
 * the tooltip and the accessible name, so a first-time operator still
 * gets the whole sentence — the face just stops repeating it.
 *
 * Clear is the entry's eraser and nothing else: the same keyPressed("clear")
 * the backspace emits when held, which the page turns into an empty buffer.
 * It never touches the cart, and the word it prints is never the word the
 * destructive toolbar button prints.
 *
 * WHY THE MODE BUTTONS ARE NOT `checkable`
 *
 * An AbstractButton with `checkable: true` assigns its own `checked` on click,
 * which destroys any binding on it — the same trap as ComboBox.currentIndex.
 * So the mode column is stateless: `highlighted` is bound to activeMode, and a
 * click only *asks* for the change. The page owns the state, the keypad shows
 * it, and there is no second copy to fall out of step. That also makes an
 * exclusive ButtonGroup unnecessary — one bound comparison cannot elect two
 * winners.
 *
 * WHY NO KEY REPLACES ITS `background`
 *
 * Every key here is a plain styled Button. Colour is carried in the *ink* only.
 * Substituting a Rectangle background would have been the obvious way to tint
 * the modes, and it would have cost the style's focus ring, its hover and
 * pressed fills, and — because padding, insets and implicitHeight all come from
 * the same `__config` table the vendoring scaler multiplied — quietly opted
 * these keys out of the app-wide scale. Tinting the glyph and label instead
 * reaches the same "coloured" goal and keeps all of that intact.
 *
 * THE DECIMAL KEY
 *
 * `decimalEnabled` is the page's answer to whether a fraction is a legal
 * entry: the till enables it in QTY only while the selected line sells a
 * weighted or fractional unit (a money amount always may have one), the
 * money sheets leave it on. A disabled "." is the cheapest validation
 * there is — the value that cannot be typed is the value that cannot be
 * applied to the wrong line.
 */
Item {
    id: root

    // =====================================================================
    // API
    // =====================================================================
    /* Which entry-mode toggles the side column carries, in order. The entry
       sheets pass their own — a delivery line's ["qty", "cost", "price"];
       the till passes its three: ["qty", "plus", "minus"]. */
    property var modes: ["qty"]

    /* The mode currently in force, owned by the page. */
    property string activeMode: "qty"

    /* Digits "0".."9", ".", "back", "clear". Same vocabulary as pos.
       "clear" empties the entry; "back" also empties it when held. */
    signal keyPressed(string key)
    signal modeRequested(string mode)

    /* Whether the decimal key accepts presses. See THE DECIMAL KEY above. */
    property bool decimalEnabled: true

    /* Whether the side column carries a C key under the modes: the whole
        entry erased in one tap, in the spare row three modes leave. The
        till asks for it; the sheets' pads either fill the column with a
        fourth mode or already have Clear in the utility row. */
    property bool clearKey: false

    /* The height of one key. The modal sheets keep the 72 the token holds;
        the till's permanent pad lives inside the transaction panel's width
        and height budget, so it passes 48 — the merchant's own range — and
        the pad scales itself around that. */
    property int keySize: Tokens.size.numpadKey

    readonly property int gap: Tokens.spacing.xs

    /* Four rows of keys in every shape, and across: the side column is 1.4
       keys wide (see its Layout.preferredWidth) plus three digit columns,
       with one gap between the two blocks and two inside the grid. The
       plain pad's utility row carries four keys across the same width, so
       one number serves all three shapes. */
    implicitHeight: 4 * keySize + 3 * gap
    implicitWidth: Math.round(keySize * 4.4) + 3 * gap

    // =====================================================================
    // MODE VOCABULARY
    // =====================================================================
    /* Label, glyph and tone per mode. The glyph carries the meaning at a glance
        — an operator reaching for the cost finds the tag before they read the
        word, which matters at speed and in a second language. The tone is the
        same one the rest of the app already uses for that meaning.

        `iconOnly` drops the word from the face: for a mode whose glyph IS
        the word — a plus is a plus — the label said the same thing twice,
        and the active mode is already the lit key. The word survives in the
        tooltip and the accessible name. */
    readonly property var modeSpecs: ({
        "qty":   { key: "pos.numpad.qty",   fallback: "Qty",
                   glyph: "ic_fluent_number_symbol_20_regular", tone: "info" },
        /* THE MONEY MODES, restored as they shipped: + is a free charge
            line added to the total, − a cart-level discount line. They
            are TOGGLES, not steppers — the page keeps keypadMode and the
            typed number becomes the amount, which is why they ride the mode
            signal rather than emitting a step. The tones are the meanings
            the rest of the app already uses: an added amount is money the
            customer owes (caution), a discount is money leaving (danger). */
        "plus":  { key: "pos.numpad.plus",  fallback: "+ AMT",
                   glyph: "ic_fluent_add_20_regular",           tone: "warning",
                   iconOnly: true },
        "minus": { key: "pos.numpad.minus", fallback: "− DISC",
                   glyph: "ic_fluent_subtract_20_regular",      tone: "danger",
                   iconOnly: true },
        /* A delivery screen edits what a thing COST, which a sale screen never
           does — its prices come off the shelf. Same pad, two more stops pulled
           out: `price` is what it will be sold for, which the line entry sheet
           asks for beside the cost so the margin between them is in view. */
        "cost":  { key: "pos.numpad.cost",  fallback: "COST",
                   glyph: "ic_fluent_tag_20_regular",           tone: "primary" },
        "price": { key: "pos.numpad.price", fallback: "SELL",
                   glyph: "ic_fluent_arrow_trending_20_regular", tone: "success" },
        /* The sheets' spare key: empty the ENTRY, not the cart. pos's own
           catalogue already carries the word. */
        "clear": { key: "pos.numpad.clear", fallback: "CLEAR",
                   glyph: "ic_fluent_eraser_20_regular",        tone: "" }
    })

    function specFor(mode) {
        var spec = modeSpecs[mode]
        return spec !== undefined ? spec
             : { key: "", fallback: mode, glyph: "", tone: "" }
    }

    // =====================================================================
    // THE SHARED DIGIT BLOCK
    // =====================================================================
    /* The digit block the two column pads share: 7-8-9 / 4-5-6 / 1-2-3 /
       0-.-⌫, one GridLayout so all twelve cells come out the same size —
       a hand that has learned where 7 is must find it the same size as 1,
       and the same size as the 0 under it. Declared before first use: an
       inline component referenced above its own declaration is not
       reliably resolved. */
    component DigitBlock: GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: 3
        columnSpacing: root.gap
        rowSpacing: root.gap

        /* Rows read 7-8-9 / 4-5-6 / 1-2-3 / 0-.-⌫ — telephone order, which
           is what every till and calculator uses.

           "." and "back" come from the same list as the digits rather than
           being appended as separate items, so all twelve cells are placed
           by one rule and none can drift out of position. */
        Repeater {
            model: ["7", "8", "9", "4", "5", "6", "1", "2", "3",
                    "0", ".", "back"]

            delegate: QC.Button {
                id: digitKey
                required property string modelData

                readonly property bool isBack: modelData === "back"
                readonly property bool isDecimal: modelData === "."

                Layout.fillWidth: true
                Layout.fillHeight: true
                /* Equal preferred sizes on every cell is what makes the
                   three columns equal: the layout starts from the preferred
                   and shares the surplus, and twelve identical preferreds
                   cannot produce a fat column. */
                Layout.preferredWidth: root.keySize
                Layout.preferredHeight: root.keySize

                /* The decimal obeys the page's fraction rule — default on,
                   so the money sheets never notice. */
                enabled: !isDecimal || root.decimalEnabled
                text: isBack ? "" : modelData
                onClicked: root.keyPressed(modelData)

                /* Hold backspace to clear. pos has no clear key at all — it
                   clears from Escape, which a till with no keyboard does not
                   have, so emptying a mis-scanned 13-digit barcode there is
                   thirteen taps. autoRepeat would have been the other way to
                   soften that, but Qt suppresses pressAndHold when it is on,
                   and one gesture that empties the buffer beats a fast
                   repeat that still has to run the whole way. */
                onPressAndHold: if (isBack) root.keyPressed("clear")

                Accessible.name: isBack
                    ? Strings.t("pos.numpad.back", "Backspace") : text

                QC.ToolTip.text: Strings.t("pos.numpad.back.hint",
                                           "Backspace — hold to clear")
                QC.ToolTip.visible: isBack && hovered
                QC.ToolTip.delay: 700

                /* 32px digits. This is the one place in the app where type
                   size is a usability requirement rather than a style
                   choice: the key is struck without looking, so the digit
                   has to be legible in peripheral vision. */
                font.pixelSize: Tokens.font.title
                font.weight: Font.Medium

                contentItem: Item {
                    implicitWidth: digitKey.isBack
                        ? backGlyph.implicitWidth : digitLabel.implicitWidth
                    implicitHeight: digitKey.isBack
                        ? backGlyph.implicitHeight : digitLabel.implicitHeight

                    Icon {
                        id: backGlyph
                        anchors.centerIn: parent
                        visible: digitKey.isBack
                        icon: "ic_fluent_backspace_20_regular"
                        size: Tokens.icon.lg
                        color: digitKey.icon.color
                    }

                    Text {
                        id: digitLabel
                        anchors.centerIn: parent
                        visible: !digitKey.isBack
                        text: digitKey.text
                        font: digitKey.font
                        color: digitKey.icon.color
                    }
                }
            }
        }
    }

    // =====================================================================
    // LAYOUT — THE PLAIN PAD
    // =====================================================================
    /* Digits over a utility row, for the payment sheets: one field, no
       modes — a mode would be a control with one setting. Shown when no
       modes are passed; the till and the entry sheets pass theirs and get
       the mode column below. */
    ColumnLayout {
        anchors.fill: parent
        visible: root.modes.length === 0
        spacing: root.gap

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            columnSpacing: root.gap
            rowSpacing: root.gap

            /* Rows read 7-8-9 / 4-5-6 / 1-2-3 — telephone order, which is
               what every till and calculator uses. */
            Repeater {
                model: ["7", "8", "9", "4", "5", "6", "1", "2", "3"]

                delegate: QC.Button {
                    id: plainDigitKey
                    required property string modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.keySize
                    Layout.preferredHeight: root.keySize

                    text: modelData
                    onClicked: root.keyPressed(modelData)

                    /* 32px digits. This is the one place in the app where type
                       size is a usability requirement rather than a style
                       choice: the key is struck without looking, so the digit
                       has to be legible in peripheral vision. */
                    font.pixelSize: Tokens.font.title
                    font.weight: Font.Medium

                    contentItem: Item {
                        implicitWidth: plainDigitLabel.implicitWidth
                        implicitHeight: plainDigitLabel.implicitHeight

                        Text {
                            id: plainDigitLabel
                            anchors.centerIn: parent
                            text: plainDigitKey.text
                            font: plainDigitKey.font
                            color: plainDigitKey.icon.color
                        }
                    }
                }
            }
        }

        /* The utility row: Clear, 0, the decimal, Backspace. Clear and
           Backspace are visually distinct from the digits — an icon and a
           small word, not a fat numeral — but not aggressive: nothing here
           is destructive, Clear empties the ENTRY and nothing else. */
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.keySize
            spacing: root.gap

            QC.Button {
                id: clearKey

                Layout.fillWidth: true
                Layout.fillHeight: true

                onClicked: root.keyPressed("clear")

                QC.ToolTip.text: Strings.t("pos.numpad.clear", "Clear")
                QC.ToolTip.visible: hovered
                QC.ToolTip.delay: 700

                /* An Item around a centred Column, not the Column itself.
                   Control assigns contentItem the full available width AND
                   height, so a Column used directly would be stretched and
                   stack its children from the top edge. The wrapper absorbs
                   the stretch and forwards the Column's own implicit size so
                   the button still measures from content. */
                contentItem: Item {
                    implicitWidth: clearStack.implicitWidth
                    implicitHeight: clearStack.implicitHeight

                    Column {
                        id: clearStack
                        anchors.centerIn: parent
                        spacing: 2

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            icon: "ic_fluent_eraser_20_regular"
                            size: Tokens.icon.sm
                            color: clearKey.icon.color
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Strings.t("pos.numpad.clear", "Clear")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            color: clearKey.icon.color
                        }
                    }
                }
            }

            QC.Button {
                id: zeroKey

                Layout.fillWidth: true
                Layout.fillHeight: true

                text: "0"
                onClicked: root.keyPressed("0")

                font.pixelSize: Tokens.font.title
                font.weight: Font.Medium

                contentItem: Item {
                    implicitWidth: zeroLabel.implicitWidth
                    implicitHeight: zeroLabel.implicitHeight

                    Text {
                        id: zeroLabel
                        anchors.centerIn: parent
                        text: zeroKey.text
                        font: zeroKey.font
                        color: zeroKey.icon.color
                    }
                }
            }

            QC.Button {
                id: decimalKey

                Layout.fillWidth: true
                Layout.fillHeight: true

                /* Enabled only while a fraction is a legal entry — see the
                   header. The disabled look belongs to the style, which owns
                   greyed-out. */
                enabled: root.decimalEnabled
                text: "."
                onClicked: root.keyPressed(".")

                QC.ToolTip.text: Strings.t("pos.numpad.decimal",
                                           "Decimal point")
                QC.ToolTip.visible: hovered
                QC.ToolTip.delay: 700

                font.pixelSize: Tokens.font.title
                font.weight: Font.Medium

                contentItem: Item {
                    implicitWidth: decimalLabel.implicitWidth
                    implicitHeight: decimalLabel.implicitHeight

                    Text {
                        id: decimalLabel
                        anchors.centerIn: parent
                        text: decimalKey.text
                        font: decimalKey.font
                        color: decimalKey.icon.color
                    }
                }
            }

            QC.Button {
                id: backKey

                Layout.fillWidth: true
                Layout.fillHeight: true

                onClicked: root.keyPressed("back")

                /* Hold backspace to clear. pos has no clear key at all — it
                   clears from Escape, which a till with no keyboard does not
                   have, so emptying a mis-scanned 13-digit barcode there is
                   thirteen taps. autoRepeat would have been the other way to
                   soften that, but Qt suppresses pressAndHold when it is on,
                   and one gesture that empties the buffer beats a fast
                   repeat that still has to run the whole way. */
                onPressAndHold: root.keyPressed("clear")

                Accessible.name: Strings.t("pos.numpad.back", "Backspace")

                QC.ToolTip.text: Strings.t("pos.numpad.back.hint",
                                           "Backspace — hold to clear")
                QC.ToolTip.visible: hovered
                QC.ToolTip.delay: 700

                contentItem: Item {
                    implicitWidth: backGlyph2.implicitWidth
                    implicitHeight: backGlyph2.implicitHeight

                    Icon {
                        id: backGlyph2
                        anchors.centerIn: parent
                        icon: "ic_fluent_backspace_20_regular"
                        size: Tokens.icon.lg
                        color: backKey.icon.color
                    }
                }
            }
        }
    }

    // =====================================================================
    // LAYOUT — THE SHEETS' PAD
    // =====================================================================
    /* A mode column beside the shared digit block, unchanged in behaviour:
       LineEntry passes ["qty", "cost", "price"] and the payment sheet passes
       [] with no quantity column. */
    RowLayout {
        anchors.fill: parent
        visible: root.modes.length > 0
        spacing: root.gap

        // -----------------------------------------------------------------
        // side column: the entry modes
        // -----------------------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            /* A little wider than one digit key. The side labels are words, not
               single characters, so a straight quarter of the width would elide
               "الكمية" at 15px. 1.4 fits it and still reads as one column. */
            Layout.preferredWidth: root.keySize * 1.4
            spacing: root.gap

            Repeater {
                model: root.modes

                delegate: QC.Button {
                    id: modeKey
                    required property string modelData

                    readonly property var spec: root.specFor(modelData)

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: root.keySize
                    /* Exactly one key tall, never more: the spacer below takes
                       whatever the column's rows do not use, so the keys line
                       up with the digit rows beside them. */
                    Layout.maximumHeight: root.keySize

                    /* Not checkable — see the header. */
                    highlighted: root.activeMode === modelData
                    onClicked: root.modeRequested(modelData)

                    /* The whole sentence for hover and screen readers, even
                       where the face draws only the glyph. */
                    Accessible.name: Strings.t(modeKey.spec.key,
                                               modeKey.spec.fallback)

                    QC.ToolTip.text: Strings.t(spec.key, spec.fallback)
                    QC.ToolTip.visible: hovered
                    QC.ToolTip.delay: 700

                    /* Tone-coloured while inactive so the modes are told
                        apart before any is chosen. Active or disabled, the style
                        owns the colour: on an accent fill `icon.color` is already
                        the correct on-accent ink, and greyed-out is greyed-out. */
                    readonly property color ink: (highlighted || !enabled)
                        ? icon.color : Tokens.toneInk(spec.tone)

                    /* An Item around a centred Column, not the Column itself.
                        Control assigns contentItem both the full available width
                        AND height, so a Column used directly would be stretched
                        to 72px and stack its children from the top edge. The
                        wrapper absorbs the stretch and forwards the Column's own
                        implicit size so the button still measures from content. */
                    contentItem: Item {
                        implicitWidth: modeStack.implicitWidth
                        implicitHeight: modeStack.implicitHeight

                        Column {
                            id: modeStack
                            anchors.centerIn: parent
                            spacing: 2

                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: modeKey.spec.glyph !== ""
                                icon: modeKey.spec.glyph
                                size: Tokens.icon.md
                                color: modeKey.ink
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: !modeKey.spec.iconOnly
                                text: Strings.t(modeKey.spec.key, modeKey.spec.fallback)
                                font.pixelSize: Tokens.font.caption
                                font.weight: Font.DemiBold
                                color: modeKey.ink
                            }
                        }
                    }
                }
            }

            /*
             * THE C KEY — the whole entry, gone in one tap.
             *
             * Backspace still eats a digit at a time; C is for the thirteen
             * digits a mis-scan left in the buffer. It rides the same
             * keyPressed("clear") vocabulary the plain pad's Clear key and a
             * held backspace already speak, so every pad erases identically
             * and the page never learns a second word. In the side column's
             * spare row — bottom of the column, beside the 0 . ⌫ row, where
             * a calculator has always kept it.
             */
            QC.Button {
                id: sideClearKey

                visible: root.clearKey
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: root.keySize
                Layout.maximumHeight: root.keySize

                onClicked: root.keyPressed("clear")

                Accessible.name: Strings.t("pos.numpad.clear", "Clear")

                QC.ToolTip.text: Strings.t("pos.numpad.clear", "Clear")
                QC.ToolTip.visible: hovered
                QC.ToolTip.delay: 700

                /* The calculator's own letter, at the digits' own size: one
                   tap, one meaning, legible in peripheral vision. */
                text: "C"
                font.pixelSize: Tokens.font.title
                font.weight: Font.Medium

                /* Ink on a saturated fill, from the theme's own pairing: white
                   on the deep red of the light theme, near-black on the light
                   red of the dark one. A literal white would burn in dark mode
                   and a literal red would vanish in light — this is the token
                   the submit key already reads on its emerald. */
                readonly property color ink: Tokens.onBrand

                /* DESTRUCTIVE, AND IT SAYS SO IN COLOUR.
                 *
                 * The same crimson the app paints Clear cart with — the one
                 * act that throws work away — here as a SOLID fill rather than
                 * Clear cart's tint, because a key on a pad is read at a
                 * glance from among light-grey digits and a tint would
                 * disappear into them. Same red, same meaning; the tone the
                 * bottom bar spends on words, the pad spends on a letter. */
                background: Rectangle {
                    radius: Tokens.radius.sm
                    color: !sideClearKey.enabled ? Fluent.subtleSecondary
                         : sideClearKey.down ? Qt.darker(Tokens.danger, 1.10)
                         : sideClearKey.hovered ? Qt.lighter(Tokens.danger, 1.06)
                         : Tokens.danger
                    Behavior on color { ColorAnimation { duration: Fluent.anim.fast } }
                }

                contentItem: Item {
                    implicitWidth: sideClearLabel.implicitWidth
                    implicitHeight: sideClearLabel.implicitHeight

                    Text {
                        id: sideClearLabel
                        anchors.centerIn: parent
                        text: sideClearKey.text
                        font: sideClearKey.font
                        color: sideClearKey.ink
                    }
                }
            }

            /* Absorbs the rows the side column does not use: with three modes
                and the C key it is zero-height, with fewer modes it keeps them
                key-sized at the top instead of stretching each one down a
                third of the pad. */
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        DigitBlock { }
    }
}
