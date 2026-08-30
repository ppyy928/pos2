import QtQuick
import FluentControls
import Mizan

/*
 * The section selector inside a detail screen: one pill per section, the live one
 * filled with brand.
 *
 *     SectionBar {
 *         sections: [
 *             { key: "sales",    label: "Sales",    glyph: "...", count: 12 },
 *             { key: "payments", label: "Payments", glyph: "...", count: 3 }
 *         ]
 *         onActivated: (key) => ...
 *     }
 *
 * WHY THIS AND NOT TABS
 *
 * A TabBar draws a heading strip: it belongs to the window and reads as "these are
 * the screens of this app". What these dialogs need is the opposite — a control
 * *inside* one record that says "you are looking at this record's payments now" —
 * and a segmented pill is the shape that says it. It also survives being narrow,
 * which a tab bar with a growing underline indicator does not: the pills keep
 * their 48px hit height and the track scrolls rather than the labels shrinking.
 *
 * WHY NOT FluentControls.SelectorBar
 *
 * FluentControls has one (a TabBar with an Indicator under the live item), and it
 * is close. Two things rule it out here: its live item is distinguished by a 2px
 * underline only — both states paint `Fluent.textPrimary`, which is a weak signal
 * on a dialog that already has a card row competing for attention — and it has
 * nowhere to put a count. The count is the reason an operator taps a section at
 * all ("are there payments on this account?"), so it has to be visible before the
 * tap, not after.
 *
 * ARABIC
 *
 * Nothing is reversed by hand. The pills sit in a Row, which mirrors, and the
 * track is anchored to `left`, which mirrors — so the first section lands on the
 * right under Arabic. The arrow keys are the one thing mirroring cannot decide,
 * because Left means "previous" in one direction and "next" in the other; that is
 * what the `Strings.rtl` test below is for.
 */
Item {
    id: bar

    // =====================================================================
    // API
    // =====================================================================
    /*
     * The sections, in display order. Plain JS objects:
     *
     *   key    string   what `activated` reports and `select()` looks up
     *   label  string   already translated by the caller
     *   glyph  string   optional Fluent icon name
     *   count  int      optional badge; omit or use -1 for none
     *
     * `count` of 0 is shown rather than hidden: "0 payments" is an answer, and a
     * badge that disappears at zero makes the operator tap to find that out.
     */
    property var sections: []

    /* Which one is live. Writable, so a caller can open a dialog straight on its
       payments section — which is what the "take a payment" row action does. */
    property int currentIndex: 0

    readonly property string currentKey: keyAt(currentIndex)

    /* The operator picked one. Not emitted for a programmatic `currentIndex`
       write: a caller that set the section already knows. */
    signal activated(string key)

    function keyAt(index) {
        var list = sections
        if (index < 0 || index >= list.length || !list[index])
            return ""
        return list[index].key !== undefined ? list[index].key : ""
    }

    function indexOfKey(key) {
        for (var i = 0; i < sections.length; i++)
            if (keyAt(i) === key)
                return i
        return -1
    }

    /* Move to a section by name, or leave things alone if there is no such
       section — a context that names one this dialog does not have is a caller to
       fix, not a reason to land the operator somewhere arbitrary. */
    function select(key) {
        var index = indexOfKey(key)
        if (index >= 0)
            currentIndex = index
    }

    /* Arrow-key movement, wrapping. Wrapping rather than stopping because there
       are two or three sections here, not twenty: the end of the list is one key
       press from its start either way. */
    function step(delta) {
        var count = sections.length
        if (count <= 0)
            return
        var next = (currentIndex + delta) % count
        if (next < 0)
            next += count
        currentIndex = next
        bar.activated(currentKey)
    }

    // =====================================================================
    // METRICS
    // =====================================================================
    /* The gap between the track's edge and a pill. Small on purpose: the track is
       a container, not a second button, and the pills are what gets tapped. */
    readonly property int inset: 4

    readonly property int pillHeight: Tokens.size.control

    implicitWidth: track.implicitWidth
    implicitHeight: track.implicitHeight

    // Reachable by Tab, then driveable by arrows — the same contract DataTable
    // offers, and for the same reason: a till gets used without a mouse.
    activeFocusOnTab: sections.length > 1
    Keys.onLeftPressed: bar.step(Strings.rtl ? 1 : -1)
    Keys.onRightPressed: bar.step(Strings.rtl ? -1 : 1)

    // =====================================================================
    // TRACK
    // =====================================================================
    Rectangle {
        id: track

        /* Leading edge, not centred: this sits under a hero and above a table,
           both of which start at the leading edge, and a centred selector would
           be the only thing on the dialog that does not line up with them.
           `left` is mirrored by LayoutMirroring, so Arabic puts it on the right. */
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        implicitWidth: strip.implicitWidth + 2 * bar.inset
        implicitHeight: bar.pillHeight + 2 * bar.inset

        /* Never wider than the room it was given: on a narrow dialog the track
           clips and the flick below takes over, rather than the pills being
           squeezed until their labels elide. */
        width: parent.width > 0 ? Math.min(parent.width, implicitWidth) : implicitWidth
        height: implicitHeight

        radius: Tokens.radius.pill
        color: Fluent.subtleSecondary
        border.width: 1
        border.color: bar.activeFocus ? Tokens.brand : Fluent.dividerBorder

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: bar.inset
            clip: true
            contentWidth: strip.implicitWidth
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width

            Row {
                id: strip
                height: flick.height
                spacing: 0

                Repeater {
                    model: bar.sections

                    delegate: Rectangle {
                        id: pill

                        required property var modelData
                        required property int index

                        readonly property bool live: index === bar.currentIndex
                        readonly property string label: modelData.label !== undefined
                                                        ? modelData.label : ""
                        readonly property string glyph: modelData.glyph !== undefined
                                                        ? modelData.glyph : ""
                        readonly property int count: modelData.count !== undefined
                                                     ? modelData.count : -1

                        /* Ink resolved once. Both the label and the glyph read it,
                           and so does the badge, so the three can never disagree
                           about which state the pill is in. */
                        readonly property color ink: live ? Tokens.brand
                                                          : Fluent.textSecondary

                        height: strip.height
                        width: content.implicitWidth + 2 * Tokens.spacing.lg
                        radius: Tokens.radius.pill

                        /*
                         * SELECTED IS A TINT, NOT A FILL.
                         *
                         * This used to be a solid Tokens.brand pill with white text
                         * on it. On a report screen it sits directly under
                         * CategoryStrip, whose selected chip is `Tokens.brandTint`
                         * with a brand border — so the same screen had two different
                         * answers to "what does selected look like", and the darker
                         * one read as a heavy blob rather than as a selection.
                         *
                         * Now both say it the same way: the brand at tint strength,
                         * a 1px brand border, and the label at full contrast. Three
                         * steps as everywhere else — selected, hover one step up from
                         * the track, resting the track itself showing through.
                         */
                        color: live ? Tokens.brandTint
                             : pointer.containsMouse ? Fluent.subtleTertiary
                             : "transparent"

                        border.width: live ? 1 : 0
                        border.color: Tokens.brand

                        Behavior on color {
                            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }

                        Row {
                            id: content
                            anchors.centerIn: parent
                            spacing: Tokens.spacing.sm

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pill.glyph !== ""
                                icon: pill.glyph
                                size: Tokens.icon.sm
                                color: pill.ink
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: pill.label
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                font.weight: pill.live ? Font.DemiBold : Font.Normal
                                /* Full contrast on the selected pill, secondary on
                                   the rest — the same split CategoryStrip's label
                                   makes, and what keeps a tinted pill legible where
                                   brand-on-tint would be thin at 17px. */
                                color: pill.live ? Fluent.textPrimary
                                                 : Fluent.textSecondary
                            }

                            /* The count, as a chip inside the pill. The ink at low
                               alpha rather than a second colour: anything opaque
                               there would be a third colour on a control that
                               already carries two. */
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pill.count >= 0
                                height: 26
                                width: Math.max(height, badge.implicitWidth
                                                        + Tokens.spacing.sm)
                                radius: Tokens.radius.pill
                                color: Qt.rgba(pill.ink.r, pill.ink.g, pill.ink.b,
                                               pill.live ? 0.16 : 0.10)

                                Text {
                                    id: badge
                                    anchors.centerIn: parent
                                    /* U+200E: a bare number inside an Arabic
                                       paragraph still has to read as a number. */
                                    text: "\u200e" + pill.count
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.caption
                                    font.weight: Font.DemiBold
                                    color: pill.ink
                                }
                            }
                        }

                        MouseArea {
                            id: pointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                bar.currentIndex = pill.index
                                bar.forceActiveFocus()
                                bar.activated(bar.currentKey)
                            }
                        }
                    }
                }
            }
        }
    }
}
