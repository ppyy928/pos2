import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One amount, four jobs. Opens a cash session, closes one, or records money in or
 * out of the drawer — ported from pos's cash dialogs, which are the same form with
 * different words.
 *
 *     { purpose: "open" }      opening float in the drawer
 *     { purpose: "close" }     the counted cash, against what is expected
 *     { purpose: "cash_in" }   money put in
 *     { purpose: "expense" }   money spent out of the drawer
 *     { purpose: "cash_out" }  money taken out
 *
 * WHY CLOSING SHOWS THE EXPECTED FIGURE AND STILL ASKS FOR A COUNT
 *
 * The difference between the two is the only reason a shift is closed formally: it
 * is how a shop finds out that something went wrong on the day it went wrong. So
 * the expected figure is shown — hiding it would make the count a guessing game —
 * and the difference appears live as the number is typed, which is exactly when it
 * can still be recounted.
 *
 * WHY A MOVEMENT ASKS WHY AND A SESSION DOES NOT
 *
 * Opening and closing the drawer used to take a note as well. Nothing displayed it
 * on any screen in either front end, so it is gone with every other note in this
 * app: a shift is identified by its times and its figures.
 *
 * A movement still asks, and for an expense or a cash_out it insists. That text is
 * not a note — it is the only record of where the money went, and the expense
 * report has no categories, so identical reason text *is* the category. Money
 * leaving a drawer unexplained is the one thing a till must not allow.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.cash : null
    readonly property string purpose: context && context.purpose ? context.purpose : "cash_in"
    readonly property int measure: 520

    readonly property bool closing: purpose === "close"
    readonly property bool opening: purpose === "open"
    readonly property bool movement: !opening && !closing

    /* Out of the drawer, so it has to be accounted for. `cash_in` is money
       arriving and explaining it is a courtesy, not an audit requirement — pos
       draws the same line. */
    readonly property bool reasonRequired: purpose === "expense" || purpose === "cash_out"

    preferredWidth: 700
    title: {
        if (opening)
            return Strings.t("cash.open_session", "Open the drawer")
        if (closing)
            return Strings.t("cash.close_session", "Close the drawer")
        return Strings.t("cash.type." + purpose, "Cash movement")
    }

    readonly property real expected: {
        var totals = ctrl ? ctrl.totals : null
        return totals && totals.expected_raw !== undefined ? totals.expected_raw : 0
    }

    readonly property real entered: {
        var value = parseFloat(String(amount.text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    readonly property real difference: entered - expected
    /* Opening a drawer with nothing in it is legitimate; every other purpose needs
       a positive number. */
    readonly property bool validAmount: opening || closing ? entered >= 0 : entered > 0
    readonly property bool valid: validAmount
                                  && (!reasonRequired || reason.text.trim() !== "")

    Component.onCompleted: amount.forceActiveFocus()

    function money(value) {
        return ctrl ? ctrl.moneyText(value) : "—"
    }

    function confirm() {
        error.text = ""
        if (!ctrl || !validAmount) {
            error.text = Strings.t("amount.error", "Enter a valid amount.")
            amount.forceActiveFocus()
            return
        }
        if (reasonRequired && reason.text.trim() === "") {
            error.text = Strings.t("cash.reason_required",
                                   "Say what this was for — it is the only record.")
            reason.forceActiveFocus()
            return
        }
        if (opening)
            ctrl.openSession(amount.text)
        else if (closing)
            ctrl.closeSession(amount.text)
        else
            ctrl.add(purpose, amount.text, reason.text)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onOpened(result) { dialog.close() }
        function onClosed(result) { dialog.close() }
        function onRecorded(result) { dialog.close() }
        function onRejected(message) { error.text = message }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Text {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            visible: dialog.closing
            text: Strings.t("cash.close.hint",
                            "Count what is in the drawer and enter it. The difference is recorded.")
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textSecondary
        }

        RowLayout {
            Layout.fillWidth: true
            visible: dialog.closing
            spacing: Tokens.spacing.md

            Text {
                text: Strings.t("cash.expected", "Expected in the drawer")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "\u200e" + dialog.money(dialog.expected)
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            spacing: 2

            Text {
                text: dialog.closing
                      ? Strings.t("cash.counted", "Counted cash") + " *"
                      : Strings.t("amount.entered", "Amount") + " *"
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            QC.TextField {
                id: amount
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                onAccepted: dialog.confirm()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: dialog.movement
            spacing: 2

            Text {
                text: dialog.reasonRequired
                      ? Strings.t("cash.reason", "Reason") + " *"
                      : Strings.t("cash.reason", "Reason")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            QC.TextField {
                id: reason
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("cash.reason.ph",
                                           "Delivery fees, rent, bank deposit…")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.confirm()
            }
        }

        /* Live, while there is still time to recount. */
        Rectangle {
            Layout.fillWidth: true
            visible: dialog.closing && amount.text !== ""
            implicitHeight: gap.implicitHeight + 2 * Tokens.spacing.sm
            radius: Tokens.radius.md
            color: Math.abs(dialog.difference) < 0.005 ? Tokens.successTint
                                                       : Tokens.warningTint

            RowLayout {
                id: gap
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacing.md
                anchors.rightMargin: Tokens.spacing.md
                spacing: Tokens.spacing.md

                Text {
                    text: Strings.t("cash.difference", "Difference")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textSecondary
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "\u200e" + dialog.money(dialog.difference)
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.bodyLarge
                    font.weight: Font.DemiBold
                    color: Math.abs(dialog.difference) < 0.005 ? Tokens.success
                         : dialog.difference < 0 ? Tokens.danger : Tokens.warning
                }
            }
        }

        Text {
            id: error
            Layout.fillWidth: true
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.danger
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_checkmark_20_regular"
                text: Strings.t("action.confirm", "Confirm")
                highlighted: true
                enabled: dialog.valid
                onClicked: dialog.confirm()
            }
        }
    }
}
