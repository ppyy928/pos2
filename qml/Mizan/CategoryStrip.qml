import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * The till's tab strip: Favourites, then one chip per category. Ported from
 * pos/app/pages/pos.py::_add_chip and pos/app/widgets/h_scroll_strip.py.
 *
 *     ‹ [★ Favourites] [▌Drinks] [▌Bakery] [▌Household] ... ›
 *
 * WHY THERE IS NO "ALL" CHIP
 *
 * There is no chip that loads the whole catalogue, and that is pos's decision
 * rather than an omission: only the active tab's products are ever fetched, so a
 * shop with four thousand products never builds four thousand tiles. The strip
 * is the only way to change what the grid shows, which is why it sits directly
 * above it.
 *
 * WHY THE COLOUR IS A BAR AND A TINT, NEVER THE INK
 *
 * A category's colour is user data — any hue at any lightness. pos runs it
 * through a contrast helper to pick the text colour; here the colour is used for
 * a leading bar, a border and a faint tint of the surface, and the label stays in
 * the theme's own ink. That way legibility does not depend on what the merchant
 * picked, and a strip of eight categories still reads as one family. Same rule
 * PosTile applies to the same data.
 *
 * WHY THE CHEVRONS
 *
 * Twenty categories do not fit and a touch screen gives no scrollbar to grab.
 * The chevrons appear only when there is something past the edge, and they move
 * the strip by most of a page rather than a chip at a time — a cashier looking
 * for "Household" is scanning, not stepping.
 */
Item {
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
    /* Full control height. These are tapped as often as anything on the screen —
       a chip strip at a caption's height is the classic thing you cannot hit. */
    implicitHeight: Tokens.size.control

    readonly property int chevron: Tokens.size.controlSmall
    readonly property bool scrollable: view.contentWidth > view.width

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

        height: strip.height
        hoverEnabled: true

        Accessible.role: Accessible.Button
        Accessible.name: text

        background: Rectangle {
            radius: Tokens.radius.pill

            color: {
                if (chip.tinted) {
                    /* The category's own colour, at a strength that tells the
                       three states apart without ever competing with the label
                       on top of it. */
                    return Qt.tint(Fluent.cardBackground,
                                   Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b,
                                           chip.current ? 0.26
                                                        : chip.hovered ? 0.14 : 0.07))
                }
                return chip.current ? Tokens.brandTint
                     : chip.hovered ? Fluent.subtleSecondary
                                    : Fluent.cardBackground
            }
            Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

            border.width: 1
            border.color: chip.current
                ? (chip.tinted ? Qt.rgba(chip.accent.r, chip.accent.g,
                                         chip.accent.b, 0.85)
                               : Tokens.brand)
                : (chip.tinted ? Qt.rgba(chip.accent.r, chip.accent.g,
                                         chip.accent.b, 0.40)
                               : Fluent.dividerBorder)

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: Fluent.accent
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
                    /* The one place the category's colour becomes ink, and only
                       because a glyph is a shape rather than text: a hue that
                       would be unreadable as 15px type is still recognisable as
                       a star. Neutral when the entry carries no colour. */
                    color: chip.tinted ? chip.accent
                         : chip.current ? Tokens.brand : Fluent.textSecondary
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
    /* Anchors rather than a RowLayout: the chevrons overlay the ends of the strip
       instead of taking width from it, so the chips do not shift sideways the
       moment one more category arrives and makes the strip scrollable. */
    ListView {
        id: view
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: Tokens.spacing.sm
        clip: true
        /* No flick-past-the-end: a chip strip that bounces reads as a bug rather
           than as a gesture. */
        boundsBehavior: Flickable.StopAtBounds

        model: strip.model

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

    /* Both chevrons are anchored, so they swap sides in Arabic; each still moves
       the strip the way its arrow points, because contentX runs with the
       ListView's own direction. */
    IconButton {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: strip.chevron
        implicitHeight: strip.chevron
        visible: strip.scrollable && !view.atXBeginning
        glyph: "ic_fluent_chevron_left_20_regular"
        glyphSize: Tokens.icon.sm
        tooltip: Strings.t("action.scroll_back", "Back")
        onClicked: strip.scrollBy(-view.width * 0.8)
    }

    IconButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: strip.chevron
        implicitHeight: strip.chevron
        visible: strip.scrollable && !view.atXEnd
        glyph: "ic_fluent_chevron_right_20_regular"
        glyphSize: Tokens.icon.sm
        tooltip: Strings.t("action.scroll_forward", "Forward")
        onClicked: strip.scrollBy(view.width * 0.8)
    }
}
