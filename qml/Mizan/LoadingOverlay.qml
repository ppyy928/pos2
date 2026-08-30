import QtQuick
import FluentControls
import Mizan

/*
 * The busy layer over a page, a card or a table while a load is in flight.
 * Ported from pos/app/widgets/states.py::LoadingOverlay.
 *
 *     LoadingOverlay { visible: page.loading }
 *
 * It anchors itself over whatever it is parented to — pos does the same thing
 * imperatively (setGeometry(parentWidget().rect()) from showEvent/resizeEvent) —
 * so a page only has to bind `visible`.
 *
 * NO BACKDROP, BUT A LEGIBLE INDICATOR
 *
 * pos is explicit that this layer does not dim and has no backdrop: a refresh
 * should not black out numbers the operator is still reading. That holds here.
 * What does not hold is pos's *static* indicator — the comment there says "NO
 * animated progress decoration", which follows pos's blanket no-animations rule
 * for Qt Widgets. This UI is Qt Quick and Fluent's own ProgressRing animates on
 * the compositor for free, so a stalled-looking still icon buys nothing.
 *
 * The ring and its caption sit on a small opaque pill instead. Without one, a
 * caption over table rows is text on text and reads as neither.
 *
 * The ring needs no colour override: ProgressRing draws itself in Fluent.accent,
 * and run.py applies the brand emerald as that accent at startup.
 */
Item {
    id: overlay

    property string message: ""

    anchors.fill: parent

    /* Swallow everything. This is the whole reason the layer exists: a second
       click on Refresh, or a click on a row that is about to be replaced, must
       not reach the page mid-load. */
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        /* A wait cursor here and not on the pill alone — the pointer is the
           fastest signal that the click did not land. */
        cursorShape: Qt.BusyCursor
    }

    Rectangle {
        anchors.centerIn: parent
        width: content.implicitWidth + 2 * Tokens.spacing.xl
        height: content.implicitHeight + 2 * Tokens.spacing.lg
        radius: Tokens.radius.lg
        /* Opaque, unlike Fluent.cardBackground — a translucent pill over table
           rows lets the text underneath show through the caption. */
        color: Fluent.isDark ? "#1B222C" : "#FFFFFF"
        border.width: 1
        border.color: Fluent.dividerBorder

        Column {
            id: content
            anchors.centerIn: parent
            spacing: Tokens.spacing.sm

            ProgressRing {
                anchors.horizontalCenter: parent.horizontalCenter
                /* Bound to the overlay rather than pinned true, so the ring's two
                   looping animations stop while it is off screen instead of
                   turning behind a hidden layer. `indeterminate` is the switch
                   that gates them (ProgressRing runs them on
                   `indeterminate && state === 0`) — a `running` property would
                   look more direct but does not exist on ProgressBar, and
                   assigning one that does not exist fails the whole page at
                   load. */
                indeterminate: overlay.visible
                ringSize: 48
                strokeWidth: 5
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: overlay.message !== "" ? overlay.message
                                             : Strings.t("state.loading", "Loading…")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
            }
        }
    }
}
