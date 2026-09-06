import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The till's command column. Ported from pos/app/pages/pos.py::_build_rail, drawn
 * as the cards FluentPySide's own gallery uses for its categories:
 *
 *     ┌────────────────────────────┐
 *     │ ┌────┐  Payment calculator │
 *     │ │ 🖩  │  F4                 │
 *     │ └────┘                     │
 *     ├────────────────────────────┤
 *     │ ┌────┐  Cancel sale        │   ← ink and glyph both red: this one
 *     │ │ 🧹 │  F12                │      throws the sale away
 *     │ └────┘                     │
 *     └────────────────────────────┘
 *
 * Everything a cashier does that is not "add a product" lives here: the change
 * calculator, returns, holding a cart, reopening a held one, and voiding. pos calls
 * it the rail and puts it between the grid and the cart, which is where it stays —
 * those are the two things it acts on.
 *
 * WHY A CARD AND NOT A BUTTON
 *
 * A stack of five identical grey buttons tells the eye nothing: every one of them
 * is the same shape and weight, so finding "Cancel sale" means reading all five.
 * The gallery's card — a tinted glyph tile on the leading edge, the name in one
 * line, the shortcut under it — gives each command a colour and a silhouette, which
 * is what makes it findable without reading. Same idea as the dashboard's shortcut
 * cards, at a quarter the size.
 *
 * WHY THE WHOLE CARD TAKES THE TONE
 *
 * The glyph *and* the label are inked with the command's own tone, because the tone
 * is the meaning: red is "this destroys something", amber is "this parks
 * something", teal is "this only looks". A red glyph over black text says half of
 * it. Disabled drops back to the style's own ink, so an unavailable command reads
 * as unavailable rather than as a quiet colour.
 *
 * WHY THE CARD IS TINTED AND THE TILE IS SOLID
 *
 * It was a white card with a hairline divider border and a pale tile: on a white
 * page that is three shades of nearly-white, and at a counter — glanced at, from
 * standing height, under shop lighting — the column read as a grey list again, which
 * is the exact failure the card was introduced to fix. So the card now carries the
 * tone's tint, its border carries the tone itself, and the glyph tile is FILLED with
 * the tone with a light glyph on it. Each command is a coloured chip: findable by
 * colour and silhouette before a word of it is read, which is the whole point of not
 * using five grey buttons.
 *
 * Hover lifts the tint rather than replacing it, so the card that is about to be
 * pressed is the same object slightly brighter, not a different one.
 */
Item {
    id: rail

    // =====================================================================
    // API
    // =====================================================================
    /* [{ key, glyph, label, shortcut, tone, enabled }] — `tone` is one of the
       names Tokens.toneInk knows, `enabled` defaults to true, and `shortcut` is
       display text only. */
    property var commands: []

    signal triggered(string key)

    // =====================================================================
    // GEOMETRY
    // =====================================================================
    /* Wide enough for "Payment calculator" beside a 44px glyph tile in all three
       languages, narrow enough that it never competes with the tile grid on a
       1366px till — which is the whole reason pos pinned its rail rather than
       letting it stretch. */
    readonly property int minWidth: 232
    readonly property int cardHeight: 76

    implicitWidth: Math.max(minWidth, column.implicitWidth)
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Tokens.spacing.xs

        Repeater {
            model: rail.commands

            delegate: QC.AbstractButton {
                id: command
                required property var modelData

                readonly property string tone: modelData.tone !== undefined
                                               ? modelData.tone : ""
                readonly property string shortcut: modelData.shortcut !== undefined
                                                   ? modelData.shortcut : ""

                /* The one colour the card is built from. Disabled hands it back to
                   the theme, so "unavailable" is not a shade of "destructive". */
                readonly property color ink: !enabled ? Fluent.textDisabled
                                           : tone !== "" ? Tokens.toneInk(tone)
                                                         : Fluent.textPrimary

                /* The card's own fill, from the same tone. Held here rather than
                   inside the background so hover and down can step off it. */
                readonly property color fill: !enabled ? "transparent"
                                            : tone !== "" ? Tokens.toneFill(tone)
                                                          : Fluent.subtleSecondary

                Layout.fillWidth: true
                Layout.preferredHeight: rail.cardHeight

                hoverEnabled: true
                enabled: modelData.enabled !== false
                onClicked: rail.triggered(modelData.key)

                /* pos's own tooltip text, middle dot included. */
                QC.ToolTip.text: shortcut !== ""
                    ? modelData.label + " · " + shortcut : modelData.label
                QC.ToolTip.visible: hovered
                QC.ToolTip.delay: 700

                Accessible.role: Accessible.Button
                Accessible.name: modelData.label

                background: Rectangle {
                    radius: Tokens.radius.md
                    /* The tone's tint, not the card colour: on a white page a white
                       card with a hairline border is invisible from standing height.
                       Down and hover step it up rather than swapping it out. */
                    color: !command.enabled ? "transparent"
                         : command.down ? Qt.darker(command.fill, 1.06)
                         : command.hovered ? Qt.lighter(command.fill, 1.04)
                                           : command.fill
                    Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

                    /* The tone owns the edge too. 1px of the real colour at rest
                       (not a divider grey), thicker on hover, so the card that is
                       about to be pressed is unmistakable without moving. */
                    border.width: command.hovered && command.enabled ? 2 : 1
                    border.color: !command.enabled ? Fluent.dividerBorder
                                                   : command.ink
                }

                /* Padding on the control, once, rather than margins on each half:
                   Control hands contentItem exactly the area between its paddings.
                   It is also the one geometry LayoutMirroring does not flip, so the
                   leading inset asks `mirrored` — the same property the style uses,
                   which accounts for the control's locale as well as an ancestor's
                   mirroring. */
                leftPadding: Tokens.spacing.sm
                rightPadding: Tokens.spacing.sm
                topPadding: Tokens.spacing.xs
                bottomPadding: Tokens.spacing.xs

                contentItem: RowLayout {
                    spacing: Tokens.spacing.sm

                    /* The glyph tile, FILLED with the tone and carrying a light
                       glyph: the one solid block of colour on the card, which is
                       what gives each command its silhouette across a counter. A
                       Row mirrors, so it stays on the leading edge in Arabic. */
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Tokens.icon.lg + Tokens.spacing.md
                        implicitHeight: implicitWidth
                        radius: Tokens.radius.sm
                        color: command.enabled ? command.ink : Fluent.subtleSecondary

                        Icon {
                            anchors.centerIn: parent
                            visible: command.modelData.glyph !== undefined
                                     && command.modelData.glyph !== ""
                            icon: command.modelData.glyph !== undefined
                                  ? command.modelData.glyph : ""
                            size: Tokens.icon.md
                            /* On a filled tile the glyph cannot be the tone as
                               well. `onBrand` is the palette's answer to "ink on a
                               saturated fill" and follows the theme. */
                            color: command.enabled ? Tokens.onBrand
                                                   : Fluent.textDisabled
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: command.modelData.label !== undefined
                                  ? command.modelData.label : ""
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: command.ink
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            /* Logical alignment: mirrors to the right in Arabic.
                               Pinned rather than left to default, because a Text
                               with no explicit alignment follows its own content's
                               direction — which would put an English label on the
                               wrong edge of an Arabic rail. */
                            horizontalAlignment: Text.AlignLeft
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: command.shortcut !== ""
                            text: command.shortcut
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            font.letterSpacing: 0.6
                            color: command.ink
                            /* The hint, not the command. Dimmed rather than greyed
                               so it follows the card's own ink through hover and
                               disabled instead of holding one colour against
                               both. */
                            opacity: 0.7
                            horizontalAlignment: Text.AlignLeft
                        }
                    }
                }
            }
        }

        /* The commands sit at the top of the column; the slack belongs under them.
           pos ends its rail layout with the same stretch. */
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
