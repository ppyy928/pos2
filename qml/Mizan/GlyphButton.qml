import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * A button with a Fluent glyph beside its label — the shape every page header
 * uses ("＋ Add product", "⇅ Arrange", "⋯ More").
 *
 *     GlyphButton {
 *         glyph: "ic_fluent_add_20_regular"
 *         text: Strings.t("products.add", "Add product")
 *         highlighted: true          // accent fill, for the one primary action
 *         onClicked: ...
 *     }
 *
 * WHY THIS EXISTS
 *
 * pos writes `QPushButton(get_icon("plus"), tr("products.add"))` — an SVG
 * resource beside a label. Fluent's icons are not resources: they are glyphs in
 * FluentSystemIcons-Resizable.ttf, so `icon.source` has nothing to load and the
 * style's own IconLabel contentItem draws an empty box. FluentControls registers
 * fifty types and none of them is a glyph+text button (PillButton, ToggleButton
 * and DropDownButton are all label-only), so this is the missing piece rather
 * than a duplicate of one that exists.
 *
 * WHAT IT DELIBERATELY DOES NOT TOUCH
 *
 * Padding, insets, radius, background and implicitHeight all come from the
 * style's `__config`, which the vendoring scaler already multiplied — a
 * FluentWinUI3 button is 48px tall in this app because of that table, and
 * re-declaring any of it here would quietly opt this one control back out of
 * the scale. Only the font and the contentItem are replaced.
 *
 * WHY BOTH HALVES BIND TO icon.color
 *
 * The style drives its entire label colour through one property:
 *
 *     icon.color: __buttonText            // in FluentWinUI3/Button.qml
 *     contentItem: IconLabel { color: control.icon.color }
 *
 * and `__buttonText` is where hover, pressed, checked, highlighted, disabled and
 * Windows high-contrast are all resolved. Binding the glyph and the text to that
 * same property inherits every one of those states for free; reading
 * `palette.buttonText` directly instead — which DropDownButton does — would
 * leave the label the same colour on an accent button as on a plain one.
 */
QC.Button {
    id: control

    // =====================================================================
    // API
    // =====================================================================
    /* Named `glyph`, not `icon`: Control already owns an `icon` group and
       redeclaring that name would collide with it. Same choice as IconButton. */
    property string glyph: ""

    /* 18px against a 17px label. The glyph is an equal partner to the text here,
       not the whole content, so it takes icon.sm rather than IconButton's
       icon.md — a 24px glyph beside 17px type reads as an icon with a caption. */
    property int glyphSize: Tokens.icon.sm

    /* An icon-only GlyphButton (display: IconOnly, which a wrapped header uses
       to save a row) has no visible label, so it needs this to stay reachable.
       `text` is still set in that case, which is what keeps Accessible.name
       correct without another property. */
    property string tooltip: ""

    /*
     * Draw a visible frame around this button.
     *
     * WHY IT IS NEEDED
     *
     * FluentWinUI3's resting button is a near-white surface with a very faint
     * border, which is legible on the grey of a page and effectively invisible on
     * the white of a dialog. Every Close and Cancel in this app sat on a dialog, so
     * the one control an operator reaches for when they want OUT was the hardest one
     * to find on the screen.
     *
     * WHY A FRAME AND NOT A REPLACED BACKGROUND
     *
     * `background` is the style's own delegate and it is where hover, pressed,
     * disabled, `highlighted`'s accent fill and Windows high-contrast are all
     * resolved. Replacing it to add a border would opt this control out of all of
     * that — an accent primary button would lose its fill. So the frame is drawn
     * over it: transparent inside, so it adds an outline and takes nothing away.
     */
    property bool outlined: false

    Rectangle {
        anchors.fill: parent
        visible: control.outlined
        radius: Tokens.radius.md
        color: "transparent"
        border.width: control.activeFocus || control.hovered ? 2 : 1
        border.color: !control.enabled ? Fluent.dividerBorder
                    : control.down || control.hovered ? Tokens.brand
                    : Fluent.controlBorderStrong
    }

    // =====================================================================
    // TYPE
    // =====================================================================
    /* Nothing. Deliberately.
     *
     * run.py sets the application font to Fluent.typography.body (17px), which
     * is the same number Tokens.font.body resolves to, and a Control inherits
     * it. Re-declaring family and pixelSize here would only copy that value into
     * a second place to keep in step — and would quietly override a caller that
     * wants a larger action ("GlyphButton { font.pixelSize: Tokens.font.bodyLarge }"
     * still works precisely because this is left alone).
     */

    QC.ToolTip.text: tooltip
    QC.ToolTip.visible: hovered && tooltip !== ""
    QC.ToolTip.delay: 500

    // =====================================================================
    // CONTENT
    // =====================================================================
    /*
     * An Item wrapping a centred Row, rather than the Row itself.
     *
     * Control gives contentItem the whole area between its paddings, so a Row
     * used directly would be stretched to that width and pack its children
     * against the leading edge — off-centre in a button whose width came from a
     * Layout. The wrapper takes the stretch; the Row keeps its content size and
     * centres inside it. The wrapper's implicit size is forwarded from the Row so
     * the button still measures itself from its own label.
     */
    contentItem: Item {
        implicitWidth: strip.implicitWidth
        implicitHeight: strip.implicitHeight

        Row {
            id: strip
            anchors.centerIn: parent
            spacing: control.spacing

            /* Glyph on the trailing side in Arabic, which is where a leading
               icon belongs in an RTL line. A Row positions by x and reverses its
               children under mirroring, so this is the whole of the RTL work.
               Set from control.mirrored rather than left to inherit, because
               `mirrored` is what the style itself uses and it accounts for the
               control's locale as well as an ancestor's LayoutMirroring. */
            LayoutMirroring.enabled: control.mirrored

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.glyph !== ""
                         && control.display !== QC.AbstractButton.TextOnly
                icon: control.glyph
                size: control.glyphSize
                color: control.icon.color
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.text !== ""
                         && control.display !== QC.AbstractButton.IconOnly
                text: control.text
                font: control.font
                color: control.icon.color
                /* No elide and no width: a button sizes to its label. A header
                   action whose text does not fit is a layout to fix, not a word
                   to cut in half. */
            }
        }
    }
}
