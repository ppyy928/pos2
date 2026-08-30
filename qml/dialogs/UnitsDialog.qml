import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Units of measure — piece, kilogram, litre. Ported from pos's unit management.
 *
 * Two fields, because that is the whole record: a name for the form and an
 * abbreviation for the places a name will not fit, which is the stock column on
 * every product row.
 *
 * A unit in use cannot be deleted. The database refuses it and its sentence is
 * shown as it comes, because "12 products still use this unit" is more useful than
 * anything this screen could invent.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property int measure: 620
    readonly property int listHeight: 300

    preferredWidth: 780
    title: Strings.t("units.title", "Units")

    property var rows: []
    property int selected: -1
    readonly property var current: selected >= 0 && selected < rows.length
                                  ? rows[selected] : null

    Component.onCompleted: reload()

    function reload() {
        rows = ctrl ? ctrl.units() : []
        if (selected >= rows.length)
            selected = -1
        fill()
    }

    function fill() {
        name.text = current ? current.name : ""
        abbreviation.text = current ? current.abbreviation : ""
    }

    onSelectedChanged: fill()

    function save() {
        error.text = ""
        if (ctrl)
            ctrl.saveUnit(name.text, abbreviation.text, current ? current.id : 0)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onChanged() { dialog.reload() }
        function onRejected(message) { error.text = message }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Rectangle {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            Layout.preferredHeight: dialog.listHeight
            color: Fluent.cardBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: dialog.rows

                QC.ScrollBar.vertical: FluentScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    width: list.width
                    height: Tokens.size.tableRow
                    color: index === dialog.selected ? Tokens.brandTint
                         : hover.hovered ? Fluent.subtleSecondary : "transparent"

                    HoverHandler { id: hover }
                    TapHandler { onTapped: dialog.selected = row.index }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.xs
                        spacing: Tokens.spacing.md

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.preferredWidth: 140
                            text: row.modelData.abbreviation
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textSecondary
                        }

                        IconButton {
                            glyph: "ic_fluent_delete_20_regular"
                            glyphSize: Tokens.icon.sm
                            glyphColor: Tokens.danger
                            tooltip: Strings.t("action.delete", "Delete")
                            onClicked: {
                                dialog.selected = row.index
                                if (dialog.ctrl)
                                    dialog.ctrl.deleteUnit(row.modelData.id)
                            }
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: list.count === 0
                variant: "empty"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            QC.TextField {
                id: name
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("units.name", "Unit name")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }

            QC.TextField {
                id: abbreviation
                Layout.preferredWidth: 160
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("units.abbreviation", "Short")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }

            GlyphButton {
                glyph: "ic_fluent_save_20_regular"
                text: dialog.current ? Strings.t("action.save", "Save")
                                     : Strings.t("units.add", "Add")
                enabled: name.text.trim() !== ""
                onClicked: dialog.save()
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

            GlyphButton {
                visible: dialog.selected >= 0
                text: Strings.t("units.new", "New unit")
                onClicked: dialog.selected = -1
            }

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }
        }
    }
}
