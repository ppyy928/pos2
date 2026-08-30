import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Export the catalogue as a CSV.
 *
 * A dialog rather than a silent button, for one reason: a file written somewhere
 * the operator cannot find has not been exported. So this shows where it will go
 * before, and the full path after, and the columns are the ones the importer maps —
 * an exported file can be edited in a spreadsheet and brought back.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property int measure: 620

    preferredWidth: 780
    title: Strings.t("reports.export", "Export")

    /* Not "result" and "count": Dialog already owns a FINAL 
esult (its accept
       code), and overriding one is a load error rather than a warning. */
    property string writtenPath: ""
    property int writtenRows: 0

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onExported(path, rows) {
            dialog.writtenPath = path
            dialog.writtenRows = rows
        }

        function onRejected(message) {
            error.text = message
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Text {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            text: Strings.t("export.body",
                            "Every product, with its cost, price, stock, category and unit — the same columns the importer reads.")
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: Strings.t("export.folder", "Folder")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            QC.TextField {
                id: folder
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("export.folder.ph",
                                           "Leave empty for the application's data folder")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                horizontalAlignment: TextInput.AlignLeft
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: dialog.writtenPath !== ""
            implicitHeight: done.implicitHeight + 2 * Tokens.spacing.sm
            radius: Tokens.radius.md
            color: Tokens.successTint

            ColumnLayout {
                id: done
                anchors.fill: parent
                anchors.margins: Tokens.spacing.sm
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: Strings.tf("export.done", "{count} products written",
                                     { count: dialog.writtenRows })
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: "\u200e" + dialog.writtenPath
                    wrapMode: Text.WrapAnywhere
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Fluent.textSecondary
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
                text: dialog.writtenPath !== "" ? Strings.t("action.close", "Close")
                                           : Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_arrow_download_20_regular"
                text: Strings.t("reports.export", "Export")
                highlighted: true
                onClicked: {
                    error.text = ""
                    if (dialog.ctrl)
                        dialog.ctrl.exportProducts(folder.text)
                }
            }
        }
    }
}
