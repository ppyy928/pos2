import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * The till's category filter row: Favourites, then one chip per category.
 * Ported from pos/app/pages/pos.py::_add_chip and pos/app/widgets/h_scroll_strip.py.
 *
 *     │ ‹ [★ Favourites] [• Drinks] [• Bakery] [• Household] … › │
 *
 * WHY THERE IS NO "ALL" CHIP
 *
 * There is no chip that loads the whole catalogue, and that is pos's decision
 * rather than an omission: only the active tab's products are ever fetched, so
 * a shop with four thousand products never builds four thousand tiles. The strip
 * is the only way to change what the grid shows, which is why it sits directly
 * above it.
 *
 * A WHITE BAR, NOT A FLOATING ROW OF TEXT
 *
 * The version this replaces was a row of naked chips on the workspace grey —
 * category text floating over the product grid with nothing to say where the
 * filter ended and the goods began. The strip is now its own surface: a white
 * bar with a structural border, sitting on the grey of the workspace, so the
 * row reads as the toolbar it is.
 *
 * WHY THE CHEVRONS RESERVE THEIR SPACE
 *
 * Twenty categories do not fit and a touch screen gives no scrollbar to grab.
 * The chevrons appear only when there is something past the edge, and they move
 * the strip by most of a page rather than a chip at a time — a cashier looking
 * for "Household" is scanning, not stepping. When the row scrolls, a spacer the
 * width of a chevron sits at each end of the content, so a chip is never sliced
 * through its label by the edge of the bar: it is either fully in view or past
 * it. The space is constant rather than appearing with the arrow, so nothing
 * jumps when the strip starts or stops scrolling.
 */
Rectangle {
    id: strip

    // =====================================================================
    // API
    // =====================================================================
    /* [{ key, label, accent, glyph }] — `key` is whatever the page uses to
       identify a tab (pos's is the string "favorites" or a category id), and it
       is handed back untouched. `accent` and `glyph` are optional. */
    property var model: []

    /* The active tab, owned by the page. One-way, like NavRail's currentKey: the
       chips ask, the page decides, the strip reflects. A chip that checked itself
       could disagree with the grid under it. */
    property var currentKey: null

    signal activated(var key)

    // =====================================================================
    // GEOMETRY
    // =====================================================================
    /* A command bar's height, the app's own: the chips are 44px — real
       targets for a hand that taps them all day — centred with air above
       and below, and the bar carries its own boundary. */
    implicitHeight: 56
    radius: Tokens.radius.sm
    color: Tokens.workspace.surface
    border.width: 1
    border.color: Tokens.workspace.border

    readonly property int chipHeight: 44
    readonly property int chevron: Tokens.size.controlSmall
    /* Whether the chips need the bar's scroll. Compared against the plain
       content width — see `endRoom` for why nothing on this side may feed
       back into it. */
    readonly property bool scrollable: view.contentWidth > view.width
    /* The end spacer a scrolling strip keeps clear, so no label is ever cut
       by the bar's edge.

       A CONSTANT, DELIBERATELY. It was once `scrollable ? chevron + xs : 0`
       — reserved only while scrolling — and that was a binding loop Qt
       detected on every page load: scrollable reads view.contentWidth, the
       header and footer size themselves from endRoom, and their width is
       part of contentWidth, so the three properties form a closed circle
       (convergent, but Qt flags the shape, not the values). Reserving the
       room unconditionally breaks the circle: contentWidth no longer
       depends on anything that reads it. At rest the chips simply get the
       same breathing room on both ends, and the chevrons arrive exactly
       when the content would overflow the width that keeps those ends
       clear. */
    readonly property int endRoom: chevron + Tokens.spacing.xs

    function indexOfKey(key) {
        for (var i = 0; i < model.length; i++)
            if (model[i].key === key)
                return i
        return -1
    }

    /* Keep the active chip on screen. pos does this after every rebuild too,
       because rebuilding is also what a language change does — and the chip that
       was in view is not the chip that is in view once every label has changed
       width. */
    onCurrentKeyChanged: strip.revealCurrent()
    onModelChanged: strip.revealCurrent()

    function revealCurrent() {
        var index = indexOfKey(currentKey)
        if (index >= 0)
            view.positionViewAtIndex(index, ListView.Contain)
    }

    // =====================================================================
    // CHIP
    // =====================================================================
    component Chip: QC.AbstractButton {
        id: chip

        property var entry: ({})
        property bool current: false

        readonly property color accent: entry.accent !== undefined
                                        ? entry.accent : "transparent"
        readonly property bool tinted: accent.a > 0

        height: strip.chipHeight
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        hoverEnabled: true

        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.checked: current

        background: Rectangle {
            radius: Tokens.radius.md

            /* Selected is the brand tint with a brand border — a fill, a
               boundary and weight, so the active category is unmistakable
               without colour alone. Hover is the ordinary subtle fill. */
            color: chip.current ? Tokens.brandTint
                 : chip.hovered ? Fluent.subtleSecondary
                                : "transparent"
            Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

            border.width: chip.current ? 1 : 0
            border.color: Tokens.brand

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: Tokens.brand
                visible: chip.visualFocus
            }
        }

        contentItem: Item {
            implicitWidth: label.implicitWidth
            implicitHeight: label.implicitHeight

            Row {
                id: label
                anchors.centerIn: parent
                spacing: Tokens.spacing.xs

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: chip.entry.glyph !== undefined && chip.entry.glyph !== ""
                    icon: chip.entry.glyph !== undefined ? chip.entry.glyph : ""
                    size: Tokens.icon.sm
                    color: chip.current ? Tokens.brand : Fluent.textSecondary
                }

                /* The category's colour as a small dot — the merchant's key,
                    at a key's size, instead of the wash it used to be. Only
                    when the glyph slot is not already carrying an icon (the
                    Favourites star). */
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: chip.tinted
                           && !(chip.entry.glyph !== undefined
                                && chip.entry.glyph !== "")
                    width: 8
                    height: 8
                    radius: 4
                    color: chip.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.text
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    font.weight: chip.current ? Font.DemiBold : Font.Normal
                    color: chip.current ? Fluent.textPrimary : Fluent.textSecondary
                }
            }
        }

        /* Padding, not a width: a chip is as wide as its label, and the two
           numbers below are the only thing that decides how tight the strip
           looks. leftPadding is physical and so cannot be mirrored, but both
           sides are equal here, so there is nothing to swap. */
        leftPadding: Tokens.spacing.md
        rightPadding: Tokens.spacing.md
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    /* The chips, with a spacer at each end when the row scrolls — see the
       header. Anchors rather than a RowLayout: the chevrons overlay the ends
       of the bar instead of taking width from it, so the chips do not shift
       sideways the moment one more category arrives. */
    ListView {
        id: view
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacing.xs
        anchors.rightMargin: Tokens.spacing.xs
        orientation: ListView.Horizontal
        spacing: Tokens.spacing.xs
        clip: true
        /* No flick-past-the-end: a chip strip that bounces reads as a bug
           rather than as a gesture. */
        boundsBehavior: Flickable.StopAtBounds

        model: strip.model

        header: Item { width: strip.endRoom; height: 1 }
        footer: Item { width: strip.endRoom; height: 1 }

        delegate: Chip {
            required property var modelData
            required property int index

            entry: modelData
            text: modelData.label !== undefined ? modelData.label : ""
            current: modelData.key === strip.currentKey
            onClicked: strip.activated(modelData.key)
        }
    }

    /* Explicit, rather than a Behavior on contentX: a Behavior would also
       animate every pixel of a drag, which is how a flickable ends up feeling
       like it is running through treacle. */
    NumberAnimation {
        id: scroll
        target: view
        property: "contentX"
        duration: Fluent.anim.speed
        easing.type: Easing.OutQuint
    }

    function scrollBy(delta) {
        var limit = Math.max(0, view.contentWidth - view.width)
        scroll.stop()
        scroll.from = view.contentX
        scroll.to = Math.max(0, Math.min(limit, view.contentX + delta))
        scroll.start()
    }

    /* Both chevrons sit on a white backing rounded to the bar's own corner,
       so a chip passing beneath the arrow reads as passing under a button
       rather than colliding with a glyph; they swap sides in Arabic, and each
       still moves the strip the way its arrow points, because contentX runs
       with the ListView's own direction. */
    component Chevron: Rectangle {
        id: plate

        property string glyph: ""
        property string tip: ""
        property bool showing: false
        property int delta: 0

        width: strip.chevron
        height: strip.chevron
        radius: Tokens.radius.sm
        color: Tokens.workspace.surface
        visible: showing

        IconButton {
            anchors.centerIn: parent
            implicitWidth: strip.chevron
            implicitHeight: strip.chevron
            glyph: plate.glyph
            glyphSize: Tokens.icon.sm
            tooltip: plate.tip
            onClicked: strip.scrollBy(plate.delta)
        }
    }

    Chevron {
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        showing: strip.scrollable && !view.atXBeginning
        glyph: "ic_fluent_chevron_left_20_regular"
        tip: Strings.t("action.scroll_back", "Back")
        delta: -view.width * 0.8
    }

    Chevron {
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        showing: strip.scrollable && !view.atXEnd
        glyph: "ic_fluent_chevron_right_20_regular"
        tip: Strings.t("action.scroll_forward", "Forward")
        delta: view.width * 0.8
    }
}
