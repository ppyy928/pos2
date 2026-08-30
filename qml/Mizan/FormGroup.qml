import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * A titled, tinted panel that holds a group of fields.
 *
 *   ┌─ 🏷  PRICING ──────────────────────── [ optional action ] ─┐
 *   │                                                            │
 *   │   Cost            Retail          Half            Whole    │
 *   │   [ 250.00 ]      [ 320.00 ]      [      ]        [      ] │
 *   │                                                            │
 *   └────────────────────────────────────────────────────────────┘
 *
 * WHY THIS EXISTS
 *
 * The forms in this app grouped their fields with a 10px uppercase caption and a gap.
 * On a screenshot that reads as one undifferentiated wall of labels: nothing tells the
 * eye where "what it costs" ends and "what there is" begins, so an operator filling a
 * product in reads every label to find the one they want. A caption is a *name* for a
 * group; it is not a group.
 *
 * A panel is. It gives the group an edge, a background one step off the dialog, and a
 * heading with an icon — three cues instead of one, and the one an eye uses first
 * (shape) instead of the one it uses last (small text).
 *
 * WHY THE TINT VARIES
 *
 * `tone` picks the hue, from the same eight-hue family the rest of the app uses. Not
 * decoration: a form is filled top to bottom, and after the first time an operator
 * learns that the green box is prices and the amber box is stock — which is faster
 * than reading either word. The tint is the palette's own `tint` band, so it stays a
 * whisper against the dialog and never competes with a field.
 *
 * WHAT IT DELIBERATELY DOES NOT DO
 *
 * It has no opinion about what is inside it. The content is a plain default-property
 * ColumnLayout, so a group is a row of fields, or three rows, or a table — and it
 * never grows a `fields` model that every caller then has to bend its layout to fit.
 */
Rectangle {
    id: group

    // =====================================================================
    // API
    // =====================================================================
    /* The group's name. Uppercased in the heading, so pass it in sentence case. */
    property string title: ""

    /* A Fluent glyph beside the title. Optional, and worth setting: on a form of four
       groups the icons are what the eye lands on before any word is read. */
    property string glyph: ""

    /* One of the app's tone names — "primary", "success", "warning", "danger", "info" —
       or "" for the neutral surface. Drives the tint, the border and the heading ink. */
    property string tone: ""

    /* A trailing slot in the heading, for the one action a group owns: "Add a unit" on
       the multi-units group, and nothing on most. Kept in the heading rather than under
       the fields, so it never moves when the group grows. */
    property alias actionItems: actionHost.data

    /* The fields. A ColumnLayout, so a caller stacks RowLayouts of fields into it. */
    default property alias content: body.data

    /* Vertical rhythm inside the panel, exposed because a group of one row wants less
       air than a group of four. */
    property int gap: Tokens.spacing.md

    // =====================================================================
    // SURFACE
    // =====================================================================
    readonly property color ink: tone !== "" ? Tokens.toneInk(tone)
                                             : Fluent.textSecondary

    Layout.fillWidth: true
    implicitHeight: frame.implicitHeight + 2 * Tokens.spacing.md
    radius: Tokens.radius.md

    /* The palette's tint band, which is a whisper: a group has to be visible as a shape
       without any field inside it losing contrast against it. */
    color: tone !== "" ? Tokens.toneFill(tone) : Fluent.subtleSecondary

    border.width: 1
    /* The border carries the hue at low strength — enough to separate two adjacent
       groups of different tones, not enough to draw a box around nothing. */
    border.color: tone !== "" ? Qt.rgba(ink.r, ink.g, ink.b, 0.22)
                              : Fluent.dividerBorder

    ColumnLayout {
        id: frame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Tokens.spacing.md
        anchors.rightMargin: Tokens.spacing.md
        anchors.topMargin: Tokens.spacing.md
        spacing: group.gap

        // -----------------------------------------------------------------
        // HEADING
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            visible: group.title !== "" || actionHost.children.length > 0
            spacing: Tokens.spacing.sm

            Icon {
                visible: group.glyph !== ""
                icon: group.glyph
                size: Tokens.icon.sm
                color: group.ink
            }

            Text {
                Layout.fillWidth: true
                text: group.title
                elide: Text.ElideRight
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1
                color: group.ink
            }

            /* A Row, so a group with two actions gets them side by side without the
               caller building a layout for one button. */
            Row {
                id: actionHost
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacing.xs
            }
        }

        // -----------------------------------------------------------------
        // FIELDS
        // -----------------------------------------------------------------
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: group.gap
        }
    }
}
