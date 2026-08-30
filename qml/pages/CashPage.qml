import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The cash drawer. Ported from pos's cash page over the CashSession /
 * CashMovement pair.
 *
 *  ┌──────────────────────────────────────────────────────────────────┐
 *  │ ● Open since 27/08 08:00        Expected in drawer  42 180,00    │
 *  │   Opening 10 000,00 · in 38 480,00 · out 6 300,00                │
 *  │   [ Cash in ] [ Expense ] [ Cash out ]        [ Close drawer ]   │
 *  ├──────────────────────────────────────────────────────────────────┤
 *  │ 14:05  Sale TRX-0174                              + 12 480,00    │
 *  │ 12:40  Expense — bread delivery                   −    600,00    │
 *  └──────────────────────────────────────────────────────────────────┘
 *
 * WHY THE SESSION IS A CARD AND NOT A ROW
 *
 * Whether the drawer is open is the first thing this screen has to answer: no
 * session means no movement can be recorded at all, and a cashier who does not
 * notice will find out at the worst moment. So the state is a full-width card with
 * the actions inside it, and the actions that cannot work are not shown rather than
 * shown disabled.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.cash : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property bool isOpen: ctrl ? ctrl.isOpen : false
    readonly property var drawer: ctrl ? ctrl.session : null
    readonly property var totals: ctrl ? ctrl.totals : null
    readonly property bool canManage: session ? session.can("cash.manage") : true

    function reload() {
        if (ctrl)
            ctrl.load()
    }

    function entry(purpose) {
        if (workflows)
            workflows.open("cash_entry", { purpose: purpose })
    }

    function notify(message, severity) {
        toast.show(message, severity)
    }

    function totalText(key) {
        if (!totals)
            return "—"
        var value = totals[key]
        return (value === undefined || value === null || value === "") ? "—" : value
    }

    Component.onCompleted: reload()

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true

        function onOpened(result) {
            root.notify(Strings.t("cash.opened", "The drawer is open."),
                        Severity.success)
        }

        function onClosed(result) {
            /* The difference is the headline of a close, so it is said out loud
               rather than left on a card the operator has to go and read. */
            root.notify(Strings.tf("cash.closed",
                                   "Drawer closed — difference {difference}",
                                   { difference: result.difference_text }),
                        Math.abs(result.difference) < 0.005 ? Severity.success
                                                            : Severity.caution)
        }

        function onRejected(message) {
            root.notify(message, Severity.caution)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.pagePadding
        spacing: Tokens.spacing.lg

        PageHeader {
            Layout.fillWidth: true
            title: Strings.t("nav.cash", "Cash")
            description: Strings.t("cash.description",
                                   "The drawer, its movements and every shift that has been closed.")
        }

        // -----------------------------------------------------------------
        // the drawer
        // -----------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            color: Fluent.cardBackground
            radius: Tokens.radius.lg
            border.width: 1
            border.color: root.isOpen ? Tokens.success : Fluent.dividerBorder
            implicitHeight: card.implicitHeight + 2 * Tokens.size.cardPadding

            ColumnLayout {
                id: card
                anchors.fill: parent
                anchors.margins: Tokens.size.cardPadding
                spacing: Tokens.spacing.md

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.md

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 12
                        height: 12
                        radius: 6
                        color: root.isOpen ? Tokens.success : Fluent.textTertiary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: root.isOpen
                                  ? Strings.t("cash.state.open", "The drawer is open")
                                  : Strings.t("cash.state.closed", "No open drawer")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.bodyLarge
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                        }

                        Text {
                            visible: root.isOpen && root.drawer
                            text: root.drawer && root.drawer.opened_text !== undefined
                                  ? "\u200e" + root.drawer.opened_text : ""
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textSecondary
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.isOpen
                        spacing: 0

                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: Strings.t("cash.expected", "Expected in the drawer")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.1
                            color: Fluent.textTertiary
                        }

                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: "\u200e" + root.totalText("expected")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.amount
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.isOpen
                    text: Strings.t("cash.opening", "Opening") + " " + root.totalText("opening")
                          + "  ·  " + Strings.t("cash.in", "In") + " " + root.totalText("in")
                          + "  ·  " + Strings.t("cash.out", "Out") + " " + root.totalText("out")
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Fluent.textSecondary
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    GlyphButton {
                        visible: !root.isOpen
                        glyph: "ic_fluent_lock_open_20_regular"
                        text: Strings.t("cash.open_session", "Open the drawer")
                        highlighted: true
                        enabled: root.canManage
                        onClicked: root.entry("open")
                    }

                    GlyphButton {
                        visible: root.isOpen
                        glyph: "ic_fluent_arrow_down_20_regular"
                        text: Strings.t("cash.type.cash_in", "Cash in")
                        enabled: root.canManage
                        onClicked: root.entry("cash_in")
                    }

                    GlyphButton {
                        visible: root.isOpen
                        glyph: "ic_fluent_receipt_20_regular"
                        text: Strings.t("cash.type.expense", "Expense")
                        enabled: root.canManage
                        onClicked: root.entry("expense")
                    }

                    GlyphButton {
                        visible: root.isOpen
                        glyph: "ic_fluent_arrow_up_20_regular"
                        text: Strings.t("cash.type.cash_out", "Cash out")
                        enabled: root.canManage
                        onClicked: root.entry("cash_out")
                    }

                    Item { Layout.fillWidth: true }

                    GlyphButton {
                        visible: root.isOpen
                        glyph: "ic_fluent_lock_closed_20_regular"
                        text: Strings.t("cash.close_session", "Close the drawer")
                        highlighted: true
                        enabled: root.canManage
                        onClicked: root.entry("close")
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        // movements
        // -----------------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: Fluent.cardBackground
                radius: Tokens.radius.lg
                border.width: 1
                border.color: Fluent.dividerBorder

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true
                    model: root.ctrl ? root.ctrl.movements : null

                    QC.ScrollBar.vertical: FluentScrollBar {
                        policy: QC.ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData

                        width: list.width
                        height: Tokens.size.tableRow
                        color: hover.hovered ? Fluent.subtleSecondary : "transparent"

                        HoverHandler { id: hover }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacing.md
                            anchors.rightMargin: Tokens.spacing.md
                            spacing: Tokens.spacing.md

                            Text {
                                Layout.preferredWidth: 200
                                text: "\u200e" + row.modelData.when
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                color: Fluent.textSecondary
                            }

                            Text {
                                Layout.preferredWidth: 160
                                text: row.modelData.label
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                font.weight: Font.DemiBold
                                color: Fluent.textPrimary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.reason
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                color: Fluent.textSecondary
                                elide: Text.ElideRight
                            }

                            /* The sign is the information: what came in and what
                               went out of the same drawer. */
                            Text {
                                Layout.preferredWidth: 190
                                text: "\u200e" + (row.modelData.incoming ? "+ " : "− ")
                                      + row.modelData.amount_text
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                font.weight: Font.DemiBold
                                color: row.modelData.incoming ? Tokens.success : Tokens.danger
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                StateView {
                    anchors.fill: parent
                    visible: list.count === 0 && !root.busy
                    variant: root.errorText !== "" ? "error" : "empty"
                    title: root.isOpen
                           ? Strings.t("cash.movements.empty", "No movements yet")
                           : Strings.t("cash.state.closed", "No open drawer")
                    body: root.errorText !== "" ? root.errorText : ""
                    onRetryRequested: root.reload()
                }
            }

            LoadingOverlay {
                visible: root.busy && list.count === 0
            }
        }
    }

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}
