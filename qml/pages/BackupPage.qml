import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Backups — copies of the database, and the way back from one.
 *
 * Creating one is a button. Restoring one replaces the live database, which is the
 * most destructive thing this application can do, so it is confirmed by name and
 * the confirmation says what will happen in plain words. There is no undo, and the
 * dialog does not pretend otherwise.
 *
 * The list is the backups directory as it is on disk. pos writes every backup
 * there — including the ones it takes automatically — so this screen shows the
 * same set of files that the folder does.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.backups : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

    readonly property var rows: ctrl ? ctrl.rows : []
    readonly property bool canManage: session ? session.can("backup.view") : true

    Component.onCompleted: if (ctrl) ctrl.load()

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true

        function onCreated(result) {
            toast.show(Strings.tf("backup.created", "Saved {name}",
                                  { name: result.name }),
                       Severity.success)
        }

        function onRestored(name) {
            /* A restart is the honest advice: every controller is holding data
               from the database that has just been replaced underneath it. */
            toast.show(Strings.t("backup.restored",
                                 "Restored. Close and reopen the application."),
                       Severity.caution)
        }

        function onRejected(message) {
            toast.show(message, Severity.caution)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.pagePadding
        spacing: Tokens.spacing.lg

        PageHeader {
            Layout.fillWidth: true
            title: Strings.t("nav.backup", "Backup")
            description: Strings.t("backup.description",
                                   "Copies of the whole database, newest first.")

            actionItems: [
                GlyphButton {
                    glyph: "ic_fluent_cloud_arrow_up_20_regular"
                    text: Strings.t("backup.create", "Back up now")
                    highlighted: true
                    enabled: root.canManage
                    onClicked: if (root.ctrl) root.ctrl.create()
                }
            ]
        }

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
                    model: root.rows

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
                            anchors.rightMargin: Tokens.spacing.sm
                            spacing: Tokens.spacing.md

                            Text {
                                Layout.fillWidth: true
                                text: "\u200e" + row.modelData.name
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                font.weight: Font.DemiBold
                                color: Fluent.textPrimary
                                elide: Text.ElideMiddle
                            }

                            Text {
                                Layout.preferredWidth: 220
                                text: "\u200e" + row.modelData.when
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                color: Fluent.textSecondary
                            }

                            Text {
                                Layout.preferredWidth: 140
                                text: "\u200e" + row.modelData.size_text
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                color: Fluent.textSecondary
                                horizontalAlignment: Text.AlignRight
                            }

                            GlyphButton {
                                glyph: "ic_fluent_arrow_hook_up_left_20_regular"
                                text: Strings.t("backup.restore", "Restore")
                                enabled: root.canManage
                                onClicked: {
                                    confirmRestore.name = row.modelData.name
                                    confirmRestore.open()
                                }
                            }
                        }
                    }
                }

                StateView {
                    anchors.fill: parent
                    visible: list.count === 0
                    variant: "empty"
                    title: Strings.t("backup.empty.title", "No backups yet")
                    body: Strings.t("backup.empty.body",
                                    "Take one before the first busy day.")
                    actionText: Strings.t("backup.create", "Back up now")
                    onActionRequested: if (root.ctrl) root.ctrl.create()
                }
            }
        }
    }

    FluentDialog {
        id: confirmRestore

        property string name: ""
        readonly property int measure: 520

        modal: true
        title: Strings.t("backup.restore.title", "Restore this backup?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (root.ctrl) root.ctrl.restore(confirmRestore.name)

        contentItem: Column {
            spacing: Tokens.spacing.sm

            /* Two sentences, and the catalogue's own names the file — read through `t`
               it showed a literal "{name}", so this is `tf`. The consequence stays a
               second line of its own: it is the part nobody can undo. */
            Text {
                width: confirmRestore.measure
                text: Strings.tf("backup.restore.body",
                                 "Restore \u201c{name}\u201d? The current database will be REPLACED. This cannot be undone.",
                                 { name: confirmRestore.name })
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }

            Text {
                width: confirmRestore.measure
                text: Strings.t("backup.restore.loss",
                                "Everything recorded since this backup was taken is lost: sales, payments, stock and settings are replaced by the copy.")
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }
        }
    }

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}
