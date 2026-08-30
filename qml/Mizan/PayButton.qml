import QtQuick
import QtQuick.Controls as QC
import QtQuick.Templates as T
import FluentControls
import Mizan

/*
 * A payment hero for the totals dock. Ported from
 * pos/app/widgets/buttons.py::make_pay_button.
 *
 *     ┌───────────────────────┐   ┌───────────────────────┐
 *     │  💵  Cash             │   │  🪙  Partial          │
 *     │      F9               │   │      F8               │
 *     └───────────────────────┘   └───────────────────────┘
 *          filled, primary            outlined, secondary
 *
 * WHY THIS IS NOT A STYLED BUTTON
 *
 * Everywhere else in this app a button is a FluentControls Button and its
 * background is left alone, because that background is what the vendoring scaler
 * multiplied. This one cannot be: it sits on the totals dock, which stays dark
 * navy in both themes, and every fill the style would draw comes from the
 * theme-switched palette — in light mode that is a near-white button on navy with
 * near-white text on top of it. It is the same reason Tokens keeps a `chromeHue`
 * block and ChromeButton draws its own states, and the same reason it is worth
 * spelling out: this is the exception, not the pattern.
 *
 * Geometry is not lost by drawing it: the height is Tokens.size.posHero and the
 * type comes from the same token ramp as everything else, so it scales with the
 * app rather than with the style table.
 *
 * WHY TWO WEIGHTS
 *
 * A till has one obvious action — take the money — and one that needs thinking
 * about. Filled and outlined is that hierarchy, and it survives being colour-blind
 * in a way that "emerald versus amber" does not.
 */
T.AbstractButton {
    id: hero

    // =====================================================================
    // API
    // =====================================================================
    property string glyph: ""

    /* Display text only. The page owns the Shortcut, for the same reason
       CommandRail does not own its own: a shortcut declared inside a control
       keeps firing while a dialog is on top of it. */
    property string shortcut: ""

    /* A colour, not a tone name. Tokens.toneInk is theme-switched and would hand
       back #127A4B emerald for use on navy, which is invisible; the dock's hues
       are the fixed light variants in Tokens.chromeHue. */
    property color hue: Tokens.chromeHue.emerald

    /* Filled when true, outlined when false. */
    /* One of the two is the answer nearly every time. `primary` says which is
       filled; `compact` says which one gets to be small. */
    property bool primary: false

    /*
     * HALF THE WIDTH, FOR THE ALTERNATIVE.
     *
     * The dock used to carry two of these at the same 180px minimum, side by side,
     * eating a third of it — two equally-shouted answers to a question that has a
     * default. Cash is the default; partial and debt are the exception. `compact`
     * gives the exception one line instead of two, a medium glyph instead of a large
     * one, and a 132px floor instead of 180 — still a real touch target, plainly
     * secondary, and the width it gives back goes to the figure it is paying.
     */
    property bool compact: false

    // =====================================================================
    // GEOMETRY
    // =====================================================================
    implicitHeight: Tokens.size.posHero
    implicitWidth: Math.max(hero.compact ? 132 : 180,
                            strip.implicitWidth + 2 * Tokens.spacing.lg)

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: text

    QC.ToolTip.text: shortcut !== "" ? text + " · " + shortcut : text
    QC.ToolTip.visible: hovered && text !== ""
    /* Sooner on a compact button: the shortcut is not on its face, so the tooltip
       is the only place it is written. */
    QC.ToolTip.delay: compact ? 400 : 700

    /* The ink both halves of the label use. On the filled hero it is the dock's
       own navy, which clears 4.5:1 against every hue in Tokens.chromeHue by
       construction; on the outlined one the hue is the ink. Disabled is the
       dock's muted ink rather than a faded hue — a greyed-out payment button has
       to look unavailable, not merely quiet. */
    readonly property color ink: !enabled ? Tokens.onChromeMuted
                               : primary ? Tokens.chromeTo
                                         : hue

    // =====================================================================
    // SURFACE
    // =====================================================================
    background: Rectangle {
        radius: Tokens.radius.md

        color: {
            if (!hero.enabled)
                return hero.primary ? Tokens.chromeActive : "transparent"
            if (hero.primary) {
                /* Pressed and hovered as a shade of the hue itself rather than a
                   separate colour: one number to change, and the button never
                   shifts hue under the thumb. */
                return hero.down ? Qt.darker(hero.hue, 1.18)
                     : hero.hovered ? Qt.lighter(hero.hue, 1.08)
                                    : hero.hue
            }
            return hero.down ? Qt.rgba(hero.hue.r, hero.hue.g, hero.hue.b, 0.28)
                 : hero.hovered ? Qt.rgba(hero.hue.r, hero.hue.g, hero.hue.b, 0.16)
                                : "transparent"
        }
        Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

        border.width: hero.primary ? 0 : 1
        border.color: hero.enabled ? hero.hue : Tokens.chromeBorder

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            border.width: 2
            /* The focus ring is the dock's ink, not Fluent.accent: on navy the
               brand emerald is one of the fills, and a ring in the same family as
               the thing it surrounds is not a ring. Drawn outside the edge so it
               reads on the filled hero too. */
            border.color: Tokens.onChrome
            visible: hero.visualFocus
        }
    }

    // =====================================================================
    // CONTENT
    // =====================================================================
    contentItem: Item {
        implicitWidth: strip.implicitWidth
        implicitHeight: strip.implicitHeight

        Row {
            id: strip
            anchors.centerIn: parent
            spacing: hero.compact ? Tokens.spacing.xs : Tokens.spacing.sm

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: hero.glyph !== ""
                icon: hero.glyph
                size: hero.compact ? Tokens.icon.md : Tokens.icon.lg
                color: hero.ink
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    text: hero.text
                    font.family: Tokens.font.family
                    font.pixelSize: hero.compact ? Tokens.font.body
                                                 : Tokens.font.bodyLarge
                    font.weight: Font.DemiBold
                    color: hero.ink
                }

                /* The shortcut is dropped on a compact button, not shrunk: it is the
                   least of the three things on the face and the tooltip still carries
                   it. */
                Text {
                    visible: hero.shortcut !== "" && !hero.compact
                    text: hero.shortcut
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    font.letterSpacing: 0.6
                    color: hero.ink
                    opacity: 0.75
                }
            }
        }
    }
}
