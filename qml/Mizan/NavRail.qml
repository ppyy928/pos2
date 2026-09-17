import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import QtQuick.Window
import FluentControls
import Mizan

/*
 * The permanent navigation rail.
 *
 * Why permanent, when pos's own rules ban a permanent sidebar: that rule
 * existed because a fixed 240px sidebar ate a fifth of a 1366px screen. The
 * Fluent answer is the compact rail — 68px of icons that expands on demand —
 * which keeps the horizontal budget the rule was protecting while adopting
 * the shell idiom the product is built on. Collapsed is the default below
 * 1200px of window width.
 *
 * DARK NAVY, IN BOTH THEMES
 *
 * The merchant's first rule: the rail must be distinguishable from the
 * workspace at a glance. A quiet light rail one step off the page was tried
 * and read as the page — three neighbouring surfaces of nearly equal weight,
 * with a hairline doing the separating. The rail is now the navy family in
 * Tokens.navy: fixed dark whichever theme the pages wear, so navigation is a
 * region and not a column on a form. Active state is never colour alone:
 * the checked row carries a fill AND a leading marker AND weight.
 */
Rectangle {
    id: rail

    /* Destination key currently shown. */
    property string currentKey: ""
    property bool collapsed: false
    /* key -> count, e.g. {"products": 4} for low stock. Absent keys show none. */
    property var badges: ({})
    /* Below this window width the rail collapses itself. pos's minimum window
       is 1180 wide, so at minimum size the rail is collapsed and the selling
       screen keeps its width. */
    property int autoCollapseBelow: 1200

    signal activated(string key)

    implicitWidth: collapsed ? Tokens.size.navCompact : Tokens.size.navExpanded

    /* Narrowing the window collapses the rail; widening it again does NOT
       re-expand. One-way is deliberate — auto-expanding would overrule an
       operator who chose the compact rail, and NavigationBar's two-way version
       fights the user on every resize. */
    readonly property int windowWidth: Window.width
    onWindowWidthChanged: {
        if (windowWidth > 0 && windowWidth < autoCollapseBelow)
            collapsed = true
    }
    Component.onCompleted: {
        if (Window.width > 0 && Window.width < autoCollapseBelow)
            collapsed = true
    }

    color: Tokens.navy.base

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Fluent.anim.speed
            easing.type: Easing.OutQuint
        }
    }

    /* Trailing edge — the content side of the rail, flipped in RTL by
       LayoutMirroring like any anchor. A near-black line against navy: the
       rail separates by surface first, and this edge is the crisp finish on
       that separation rather than the thing carrying it. */
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Tokens.navy.border
    }

    /* Section caption: the label when expanded, a hairline when collapsed, so
       the grouping still reads as grouping with no text on screen. */
    component SectionCaption: Item {
        id: caption
        property string label: ""
        Layout.fillWidth: true
        implicitHeight: Tokens.size.controlSmall

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Tokens.spacing.md
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Tokens.spacing.xs
            text: caption.label
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: Tokens.navy.caption
            opacity: rail.collapsed ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Fluent.anim.appearance } }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Tokens.icon.md
            height: 1
            color: Tokens.navy.border
            opacity: rail.collapsed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Fluent.anim.appearance } }
        }
    }

    /* Each row carries the caption that precedes it, if it opens a section.
        Simpler than a two-kinds-of-row model and it keeps caption and first
        item in one delegate, so they can never be separated by the layout.

        The caption goes through Strings.t — inside this binding, so the read of
        `strings.map` is captured and the captions re-resolve on a language
        change like everything else on the rail. */
    readonly property var rows: {
        var out = []
        var items = Destinations.mainItems()
        var last = null
        for (var i = 0; i < items.length; i++) {
            var d = items[i]
            var caption = ""
            if (d.section !== last) {
                last = d.section
                if (d.section !== "")
                    caption = Strings.t(Destinations.sectionTitles[d.section] || "")
            }
            out.push({ destination: d, caption: caption })
        }
        return out
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.rightMargin: 1          // clear of the hairline
        spacing: 0

        /* Collapse toggle. Sits in the rail, not the title bar, so it stays
           next to what it controls. */
        Item {
            Layout.fillWidth: true
            implicitHeight: Tokens.size.command

            /* The rail's own ink and fills: light on navy, so the toggle
               reads as chrome of this panel and not of the pages beside it. */
            ChromeButton {
                anchors.left: parent.left
                anchors.leftMargin: Tokens.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                iconName: "ic_fluent_navigation_20_regular"
                iconColor: Tokens.navy.muted
                iconColorActive: Tokens.navy.text
                fillHover: Tokens.navy.hover
                fillDown: Tokens.navy.active
                /* Strings.t, not qsTr: nothing installs a QTranslator in this
                   app, so qsTr would show its argument verbatim in every
                   language. Same rule Strings.qml's own header states. */
                tip: rail.collapsed
                      ? Strings.t("nav.expand", "Expand menu")
                      : Strings.t("nav.collapse", "Collapse menu")
                onClicked: rail.collapsed = !rail.collapsed
            }
        }

        /*
         * A Flickable with a FluentScrollBar, not a QC.ScrollView.
         *
         * The vendored FluentWinUI3 ScrollView declares both of its scroll bars in
         * one document and their thumbs reference bare `vertical` / `horizontal`.
         * Those are ScrollBar properties, and a binding's scope reaches the object
         * it is on and the document's root — not the enclosing ScrollBar — so they
         * resolve to nothing: the thumb is left without a width and the console
         * fills with ReferenceErrors on every rail. FluentScrollBar attached to a
         * Flickable is the same scroll bar the data tables use, and it works.
         */
        Flickable {
            id: railScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: railItems.implicitHeight
            /* No flick-past-the-end: the rail is a menu, and a menu that bounces
               reads as a bug rather than as a gesture. */
            boundsBehavior: Flickable.StopAtBounds

            QC.ScrollBar.vertical: FluentScrollBar { policy: QC.ScrollBar.AsNeeded }

            ColumnLayout {
                id: railItems
                width: railScroll.width
                spacing: 0

                Repeater {
                    model: rail.rows

                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        SectionCaption {
                            label: modelData.caption
                            visible: modelData.caption !== ""
                        }

                        NavRailItem {
                            destination: modelData.destination
                            collapsed: rail.collapsed
                            checked: rail.currentKey === modelData.destination.key
                            badgeCount: rail.badges[modelData.destination.key] || 0
                            onClicked: rail.activated(modelData.destination.key)
                        }
                    }
                }

                Item { Layout.fillWidth: true; implicitHeight: Tokens.spacing.sm }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.spacing.sm
            Layout.rightMargin: Tokens.spacing.sm
            implicitHeight: 1
            color: Tokens.navy.border
        }

        /* Settings and Backup, pinned. */
        Repeater {
            model: Destinations.bottomItems()

            delegate: NavRailItem {
                required property var modelData
                Layout.fillWidth: true
                destination: modelData
                collapsed: rail.collapsed
                checked: rail.currentKey === modelData.key
                badgeCount: rail.badges[modelData.key] || 0
                onClicked: rail.activated(modelData.key)
            }
        }

        Item { Layout.fillWidth: true; implicitHeight: Tokens.spacing.xs }
    }
}
