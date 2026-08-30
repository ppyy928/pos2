import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Settings — pos's key/value store, grouped and typed.
 *
 * Every change is written when it is made, not on a Save button: these are
 * independent switches and short strings, and a form that could be half-applied
 * because somebody closed it is worse than one that commits as it goes. The toast
 * says which setting was written.
 *
 * The list itself comes from Python: DEFAULT_SETTINGS is the definition of what is
 * configurable, and the controller says which group and which kind each key is. A
 * setting added there appears here without this file changing.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.settings : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

    readonly property var groups: ctrl ? ctrl.groups : []
    readonly property bool canManage: session ? session.can("settings.view") : true

    Component.onCompleted: if (ctrl) ctrl.load()

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true

        function onSaved(key) {
            toast.show(Strings.t("settings.saved", "Saved"), Severity.success)
        }

        function onRejected(message) {
            toast.show(message, Severity.caution)
        }
    }

    function put(key, value) {
        if (ctrl)
            ctrl.put(key, value)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.pagePadding
        spacing: Tokens.spacing.lg

        PageHeader {
            Layout.fillWidth: true
            title: Strings.t("nav.settings", "Settings")
            description: Strings.t("settings.description",
                                   "The shop's details, and how the till and its printers behave.")
        }

        /* A Flickable, not QC.ScrollView: the vendored FluentWinUI3 ScrollView
           references bare `vertical` / `horizontal` inside its own scroll bars,
           which resolve to nothing and fill the console — the same reason NavRail
           does it this way. FluentScrollBar attached here is the scroll bar the
           tables use. */
        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: sheet.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            QC.ScrollBar.vertical: FluentScrollBar { policy: QC.ScrollBar.AsNeeded }

            ColumnLayout {
                id: sheet
                width: scroller.width
                spacing: Tokens.spacing.lg

                Repeater {
                    model: root.groups

                    delegate: Rectangle {
                        id: group
                        required property var modelData

                        Layout.fillWidth: true
                        color: Fluent.cardBackground
                        radius: Tokens.radius.lg
                        border.width: 1
                        border.color: Fluent.dividerBorder
                        implicitHeight: body.implicitHeight + 2 * Tokens.size.cardPadding

                        ColumnLayout {
                            id: body
                            anchors.fill: parent
                            anchors.margins: Tokens.size.cardPadding
                            spacing: Tokens.spacing.md

                            Text {
                                text: group.modelData.label
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.subtitle
                                font.weight: Font.DemiBold
                                color: Fluent.textPrimary
                            }

                            Repeater {
                                model: group.modelData.items

                                delegate: RowLayout {
                                    id: setting
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.md

                                    Text {
                                        Layout.fillWidth: true
                                        text: setting.modelData.label
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.body
                                        color: Fluent.textPrimary
                                        elide: Text.ElideRight
                                    }

                                    QC.Switch {
                                        visible: setting.modelData.kind === "flag"
                                        enabled: root.canManage
                                        checked: setting.modelData.value === true
                                        onToggled: root.put(setting.modelData.key, checked)
                                    }

                                    /* A fixed set of values is a dropdown, not a
                                       text box: "ar", "extra_large" and "dark" are
                                       storage, and typing them by hand is how a
                                       setting ends up with a value the application
                                       does not recognise. */
                                    QC.ComboBox {
                                        id: choice
                                        visible: setting.modelData.kind === "choice"
                                        enabled: root.canManage
                                        Layout.preferredWidth: 260
                                        textRole: "label"
                                        valueRole: "value"
                                        model: setting.modelData.options
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.body

                                        /* Assigned, not bound: a ComboBox writes
                                           its own currentIndex the moment it is
                                           used, which would destroy a binding. */
                                        Component.onCompleted: currentIndex =
                                            indexOfValue(setting.modelData.value)

                                        onActivated: (index) => root.put(
                                            setting.modelData.key,
                                            setting.modelData.options[index].value)
                                    }

                                    QC.TextField {
                                        visible: setting.modelData.kind === "text"
                                                 || setting.modelData.kind === "number"
                                        enabled: root.canManage
                                        Layout.preferredWidth: setting.modelData.kind === "number"
                                                               ? 160 : 420
                                        Layout.preferredHeight: Tokens.size.control
                                        text: setting.modelData.kind === "flag"
                                              ? "" : String(setting.modelData.value)
                                        inputMethodHints: setting.modelData.kind === "number"
                                                          ? Qt.ImhDigitsOnly : Qt.ImhNone
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.body
                                        /* Written on commit, not on every
                                           keystroke: one row per character in the
                                           log is not an audit trail. */
                                        onEditingFinished: root.put(setting.modelData.key, text)
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true; implicitHeight: Tokens.spacing.lg }
            }
        }
    }

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}
