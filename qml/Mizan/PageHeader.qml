import QtQuick
import FluentControls
import Mizan

/*
 * The title row every page starts with. Ported from
 * pos/app/widgets/header.py::PageHeader.
 *
 *   Products  ·  843 items in 12 categories        [+ Add]  [Arrange]  [...]
 *
 * Title, an optional muted description beside it, and a trailing action block.
 * Pages list the actions as an assignment:
 *
 *     PageHeader {
 *         title: Strings.t("products.title", "Products")
 *         description: ...
 *         actionItems: [
 *             QC.Button { text: ... },
 *             IconButton { glyph: ... }
 *         ]
 *     }
 *
 * `actionItems` is a plain alias and not the default property on purpose. A
 * default property alias captures *every* unnamed child, which would include
 * this file's own title row and action row — the action row would be assigned
 * into itself. Naming the assignment costs one line in the caller and keeps the
 * component's own structure out of it.
 *
 * WRAPPING
 *
 * pos wraps the actions onto a second line, as one block, when the title and
 * the buttons cannot share a line — otherwise a narrow window clips the last
 * button to "Add Produc…". That matters more here than it did there, because
 * every label is set 1.5x larger.
 *
 * pos measures size hints inside resizeEvent and reparents the buttons between
 * two layouts. Here it is two anchor bindings: the action row is anchored to the
 * trailing edge either beside the title or beneath it, and `wrapped` decides
 * which. Nothing is reparented and nothing is measured by hand — implicitWidth
 * already is the measurement, and it updates itself when the language changes
 * and every label's width changes with it.
 */
Item {
    id: header

    property string title: ""
    property string description: ""

    /* Actions land here. Not `default` — see the note above. */
    property alias actionItems: actions.data

    /* Gap between the title and the first action when they share a line. Also
       the wrap threshold's breathing room, so the decision is not made on the
       exact pixel where they would touch. */
    readonly property int gap: Tokens.spacing.xl

    /* True when title + actions do not fit on one line. Guarded on width so the
       header does not start life wrapped, before it has been given a size.

       No binding loop: this reads the two blocks' *implicit* widths, and neither
       block's implicit width depends on where it is put. */
    readonly property bool wrapped: width > 0
                                    && titleBlock.implicitWidth + gap + actions.implicitWidth > width

    implicitHeight: wrapped ? titleBlock.height + Tokens.spacing.sm + actions.height
                            : Math.max(titleBlock.height, actions.height)

    Row {
        id: titleBlock
        /* Leading edge. anchors mirror, so this is the right-hand side in
           Arabic without being asked. */
        anchors.left: header.left
        spacing: Tokens.spacing.md

        /*
         * VERTICALLY POSITIONED BY `y`, NOT BY AN ANCHOR, AND THAT IS THE POINT
         *
         * This block and the action row have to sit on one line when they fit and
         * stack when they do not, which means their vertical placement changes with
         * the width. Two earlier versions tried to do that by toggling anchors —
         * `anchors.top: wrapped ? titleBlock.bottom : undefined` paired with a
         * conditional verticalCenter — and both broke, in two different ways:
         *
         *   1. `titleBlock.height: Math.max(titleText.height, actions.height)` with
         *      the action row centred on titleBlock closed a real loop
         *      (titleBlock.height -> actions.height -> anchor on titleBlock ->
         *      titleBlock.height). Qt reported it on every page carrying both a
         *      description and actions and broke it by leaving one side unresolved.
         *
         *   2. Releasing an anchor with `undefined` and re-establishing the other
         *      one does not survive a resize: after the header had once been narrow
         *      the action row came back with a NEGATIVE height, which is what two
         *      vertical anchors in force at once computes to.
         *
         * `y` has none of that. It is an ordinary property with an ordinary
         * binding — no set/release semantics, no pair of anchors that can both be
         * live, and no way to get stuck in the state it was born in. The horizontal
         * anchors stay anchors, because those are the ones that have to mirror for
         * Arabic; nothing about a vertical offset does.
         *
         * No loop: this reads `header.height` and its own `height`. `header.height`
         * comes from `implicitHeight` above, which reads the two blocks' heights —
         * and a Row's height is its tallest child, never its y.
         */
        y: header.wrapped ? 0 : Math.round((header.height - height) / 2)

        Text {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            text: header.title
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.title
            font.weight: Font.DemiBold
            color: Fluent.textPrimary
        }

        Text {
            /* Sits on the title's baseline rather than its centre — 17px text
               centred against 32px text reads as though it slipped. A Row sets
               only x, so anchoring vertically inside one is fine. */
            anchors.baseline: titleText.baseline
            visible: header.description !== ""
            text: header.description
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textSecondary
        }
    }

    Row {
        id: actions
        spacing: Tokens.spacing.sm

        /* Trailing edge, and the same `y` binding as the title block for the same
           reason — see the note above. Under the title when wrapped, on its line
           when not. */
        anchors.right: header.right
        y: header.wrapped ? titleBlock.height + Tokens.spacing.sm
                          : Math.round((header.height - height) / 2)
    }
}
