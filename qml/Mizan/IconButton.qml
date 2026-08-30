import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * The icon-only button, used by the pager, the filter bar and every page
 * toolbar. pos spells this as a QToolButton with a repainted SVG; here the
 * glyph comes from Fluent's icon font.
 *
 * The property is `glyph`, not `icon`: Control already owns an `icon` group
 * (icon.name, icon.source, icon.color) for image icons, and redeclaring that
 * name would collide with it.
 *
 * The style's own contentItem is an IconLabel, which draws image icons — it is
 * replaced wholesale rather than fed, because Fluent's icons are glyphs in a
 * variable font and not resources an IconLabel can load.
 */
QC.ToolButton {
    id: button

    property string glyph: ""
    property int glyphSize: Tokens.icon.md
    property color glyphColor: button.enabled ? Fluent.textPrimary : Fluent.textDisabled

    /* One string drives both the tooltip and the accessible name — an icon-only
       button has no label, so without this it is unreachable by a screen reader
       and unexplainable to anyone who does not recognise the glyph. */
    property string tooltip: ""

    implicitWidth: Tokens.size.control
    implicitHeight: Tokens.size.control

    /* The glyph centres itself in whatever space it is given, so hand it the
       whole button. The style's default padding is sized for a text label and
       would crop a 24px icon inside a 48px square. */
    padding: 0

    QC.ToolTip.text: tooltip
    QC.ToolTip.visible: hovered && tooltip !== ""
    QC.ToolTip.delay: 500

    Accessible.role: Accessible.Button
    Accessible.name: tooltip

    /* No alignment properties on Icon: it is an Item whose glyph is already
       anchored centreIn, and assigning a property a type does not have is a
       load-time error that takes the whole page down, not a warning. */
    contentItem: Icon {
        icon: button.glyph
        size: button.glyphSize
        color: button.glyphColor
    }
}
