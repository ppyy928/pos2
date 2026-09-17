import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * ONE ACTION IN THE WINDOW'S TITLE BAR.
 *
 *     [＋ New customer] [＋ Add product F10] [▦ Arrange] [↻ Refresh F7] [▥ Barcodes F11]
 *
 * The actions around a sale that have no home in the sale itself — a new
 * customer, a new product, arranging the tiles, reloading the wall, the label
 * sheet — used to be icons pinned to other people's fields (the add-customer
 * button on the customer select's shoulder, the arrange icon on the search
 * bar's), and then a row of their own under the title bar. Neither is right:
 * a control on an input's shoulder reads as part of the input, and a full row
 * of chrome for five buttons spends 56px of a till screen on nothing.
 *
 * So they live IN the title bar row, next to the app's own name. The chrome
 * that is already there is the cheapest place to put them: the row exists on
 * every screen, it is the same height either way, and the space they take was
 * dead drag area. What is left of that area still drags the window — an
 * ordinary Item does not accept mouse events, and neither does this RowLayout.
 *
 * WHY A CHIP AND NOT A PLAIN TOOL BUTTON
 *
 * The window controls at the far end of the bar are 48px squares of icon. A
 * row of those — five glyphs with no words — cannot say "Add product" to
 * anybody; these are actions of the SCREEN, not of the window, and they are
 * read once a shift by the operator who needs them. So they keep the shape the
 * command toolbar at the foot of the till uses — glyph, word, and the function
 * key trailing in the same overline hint ("F7", "F11") — one rank smaller
 * (controlSmall, caption type), because a title bar is chrome, not a keyboard.
 */
QC.Button {
    id: action

    property string glyph: ""
    property string label: ""
    property string shortcut: ""

    readonly property color ink: enabled ? Fluent.textPrimary
                                         : Fluent.textDisabled

    implicitHeight: Tokens.size.controlSmall
    /* Declared, not hoped for: a bare Button in a RowLayout resolves its
       implicit width during the layout pass, after the row has already asked. */
    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    leftPadding: Tokens.spacing.sm
    rightPadding: Tokens.spacing.sm
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: label + (shortcut !== "" ? " (" + shortcut + ")" : "")

    background: Rectangle {
        radius: Tokens.radius.sm
        /* The surface tone, not a glyph on bare chrome: the title bar is the
           window's frame and a row of sit-on-top controls inside it needs its
           own edges to read as buttons rather than as stray letters. */
        color: !action.enabled ? Fluent.subtleSecondary
             : action.down ? Fluent.subtleTertiary
             : action.hovered ? Fluent.subtleSecondary
             : Tokens.workspace.surface
        border.width: 1
        border.color: action.enabled && action.hovered
                      ? Fluent.controlBorderStrong : Tokens.workspace.border
        Behavior on color { ColorAnimation { duration: Fluent.anim.fast } }
    }

    contentItem: RowLayout {
        spacing: Tokens.spacing.xs

        Icon {
            Layout.alignment: Qt.AlignVCenter
            icon: action.glyph
            size: Tokens.icon.sm
            color: action.ink
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            /* Fillable inside the chip so a squeezed title bar compresses the
               WORD rather than clipping the chip: the row's other children are
               fixed-size, and a control half off the window edge is worse than
               one that says "Add cust…" for a moment. The chip's own implicit
               width still comes from the label's preferred width, so nothing
               changes until the space actually runs out. */
            Layout.fillWidth: true
            text: action.label
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: action.ink
            elide: Text.ElideRight
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: action.shortcut !== ""
            text: action.shortcut
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.letterSpacing: 0.6
            color: action.enabled ? Tokens.workspace.textSub
                                  : Fluent.textDisabled
        }
    }
}
