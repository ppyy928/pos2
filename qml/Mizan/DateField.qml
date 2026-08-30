import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * A date, chosen from a calendar rather than typed.
 *
 *     ┌──────────────────────────┐        ┌─────────────────────────┐
 *     │ 📅  28/08/2026        ✕  │  tap → │  ‹   August 2026    ›   │
 *     └──────────────────────────┘        │  M  T  W  T  F  S  S    │
 *                                         │              1  2  3    │
 *                                         │  4  5  6  7  8  9 10    │
 *                                         │            … 28 …       │
 *                                         │  [ Today ]     [ Clear ]│
 *                                         └─────────────────────────┘
 *
 * WHY NOT A TEXT FIELD
 *
 * "yyyy-mm-dd" typed by hand is three chances to be wrong — a month that does not
 * exist, a day past the end of it, the separator in the wrong place — and it asks
 * the operator to know the storage format. A month grid answers the question that
 * is actually being asked ("the 12th", "last Friday") in one tap, and it cannot
 * produce a date that is not a date.
 *
 * WHY CalendarView AND NOT FluentControls' DatePicker
 *
 * Both are in the library and both open a popup. DatePicker is three tumblers —
 * good for a birth date, where the year is far away; wrong for a report range,
 * where the answer is nearly always this month. CalendarView is the month grid, so
 * a day near today is one tap instead of three spins.
 *
 * ISO IN, LOCAL OUT
 *
 * `value` is "yyyy-MM-dd" because that is what every query in this app takes, and
 * what SQLite compares correctly as text. What is *shown* is the locale's own
 * order (28/08/2026), because nobody reads a date in ISO. Neither one is ever
 * parsed out of the display.
 */
QC.AbstractButton {
    id: field

    // =====================================================================
    // API
    // =====================================================================
    /* The date, as "yyyy-MM-dd". Empty means no date. */
    property string value: ""

    /* Shown when there is none. */
    property string placeholder: Strings.t("date.any", "Any date")

    /* True when the field may be emptied — a range's ends can be open, a single
       required date cannot. */
    property bool clearable: true

    /* Committed: the operator picked a day, or cleared it. Not emitted while the
       calendar is merely being browsed. */
    signal edited(string value)

    /* Whether the calendar is showing. Read-only, and public because a caller that
       wants to know — a form deciding whether Escape belongs to it or to this — has
       no other way to ask. */
    readonly property alias calendarOpen: popup.visible

    // =====================================================================
    // GEOMETRY
    // =====================================================================
    implicitWidth: 200
    implicitHeight: Tokens.size.control
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: value !== "" ? value : placeholder

    /* The display text, in the locale's short order. */
    readonly property string shown: {
        if (value === "")
            return placeholder
        var parsed = Date.fromLocaleString(Qt.locale(), value, "yyyy-MM-dd")
        return isNaN(parsed.getTime()) ? value : Qt.formatDate(parsed, "dd/MM/yyyy")
    }

    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd")
    }

    function commit(date) {
        var iso = Qt.formatDate(date, "yyyy-MM-dd")
        popup.close()
        if (iso === value)
            return
        value = iso
        field.edited(iso)
    }

    function clear() {
        popup.close()
        if (value === "")
            return
        value = ""
        field.edited("")
    }

    onClicked: {
        /* The calendar opens on the date in the field, or on this month when there
           is none — never on whatever month it was left showing. */
        var start = new Date()
        if (value !== "") {
            var parsed = Date.fromLocaleString(Qt.locale(), value, "yyyy-MM-dd")
            if (!isNaN(parsed.getTime()))
                start = parsed
        }
        calendar.selectedDate = start
        calendar.currentMonth = start.getMonth()
        calendar.currentYear = start.getFullYear()
        browsing = true
        popup.open()
    }

    /* Set while the popup is open, so seeding the calendar above does not read as
       a pick. */
    property bool browsing: false

    // =====================================================================
    // SURFACE
    // =====================================================================
    background: Rectangle {
        radius: Tokens.radius.sm
        color: field.down ? Fluent.subtleTertiary
             : field.hovered ? Fluent.subtleSecondary
                             : Fluent.controlFill
        Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

        border.width: 1
        border.color: popup.visible ? Fluent.accent : Fluent.dividerBorder

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: Fluent.accent
            visible: field.visualFocus
        }
    }

    leftPadding: Tokens.spacing.sm
    rightPadding: Tokens.spacing.xs

    contentItem: RowLayout {
        spacing: Tokens.spacing.xs

        Icon {
            Layout.alignment: Qt.AlignVCenter
            icon: "ic_fluent_calendar_ltr_20_regular"
            size: Tokens.icon.sm
            color: field.value !== "" ? Fluent.textSecondary : Fluent.textTertiary
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            /* A date is an LTR island: "28/08/2026" reordered by an Arabic
               paragraph is a different date. */
            text: "\u200e" + field.shown
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: field.value !== "" ? Fluent.textPrimary : Fluent.textTertiary
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }

        IconButton {
            Layout.alignment: Qt.AlignVCenter
            visible: field.clearable && field.value !== ""
            glyph: "ic_fluent_dismiss_20_regular"
            glyphSize: Tokens.icon.sm
            glyphColor: Fluent.textSecondary
            tooltip: Strings.t("date.clear", "Clear")
            onClicked: field.clear()
        }
    }

    // =====================================================================
    // THE POPUP
    // =====================================================================
    QC.Popup {
        id: popup

        /* Under the field, and pulled back on screen if that would hang off the
           right edge — which it does on the last filter in a row. */
        x: Math.min(0, field.Window.width - (field.mapToItem(null, 0, 0).x + implicitWidth)
                       - Tokens.spacing.md)
        y: field.height + Tokens.spacing.xs

        padding: Tokens.spacing.xs
        modal: false
        dim: false
        focus: true
        closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutsideParent

        onClosed: field.browsing = false

        background: Rectangle {
            color: Fluent.popupBackground
            border.color: Fluent.flyoutBorder
            border.width: 1
            radius: Tokens.radius.md
        }

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.xs

            CalendarView {
                id: calendar
                Layout.alignment: Qt.AlignHCenter
            }

            /* A tap on a day is the whole gesture — there is no OK button, because
               there is nothing else to decide. `browsing` keeps the seeding above
               from counting as one. */
            Connections {
                target: calendar
                function onSelectedDateChanged() {
                    if (field.browsing && popup.opened)
                        field.commit(calendar.selectedDate)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.xs

                QC.Button {
                    Layout.fillWidth: true
                    flat: true
                    text: Strings.t("date.today", "Today")
                    onClicked: field.commit(new Date())
                }

                QC.Button {
                    Layout.fillWidth: true
                    flat: true
                    visible: field.clearable
                    text: Strings.t("date.clear", "Clear")
                    onClicked: field.clear()
                }
            }
        }
    }
}
