import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Reports — six subjects, one period, and a table you can sort and export.
 *
 *   ┌──────────────────────────────────────────────────────────────────┐
 *   │ Reports                              [Export CSV]  [Refresh]     │
 *   │ ⟨Sales⟩ ⟨Inventory⟩ ⟨Purchases⟩ ⟨Customers⟩ ⟨Cash⟩ ⟨P&L⟩        │
 *   │ ┌ Last 30 days ▾   From […]  To […]   ◉ Compare ───────────────┐ │
 *   │ [ SALES ] [ INVOICES ] [ AVG BASKET ] [ PAID ] [ OUTSTANDING ]   │
 *   │ ┌ Charts ┊ Invoices 113 ┊ Returns 2 ┊ By employee 4 ───────────┐ │
 *   │ │                                                             │ │
 *   │ │   the charts, or the chosen table, filling what is left      │ │
 *   │ └─────────────────────────────────────────────────────────────┘ │
 *   └──────────────────────────────────────────────────────────────────┘
 *
 * WHAT THIS REPLACED, AND WHY THE SHAPE CHANGED
 *
 * Eight flat "kinds" — sales, profit, purchases, expenses, cash, inventory, customer
 * debt, supplier debt — each one a summary strip over a single table, with at most
 * two charts. Six subjects replace them, and each subject now owns several tables
 * rather than one: a Sales report has invoices AND returns AND a per-employee
 * rollup, and all three are the same question asked at different grain.
 *
 * THE SECTION BAR IS WHAT MAKES THAT FIT
 *
 * Six charts and four tables cannot share one viewport, and a page that scrolls them
 * all cannot hold a virtualised table — a DataTable inside a Flickable either loses
 * its virtualisation or fights the outer scroll. So the body shows exactly one thing
 * at a time and SectionBar picks it: the charts, or one table, filling the height
 * that is left. The KPI cards stay above it because they are the answer and the rest
 * is the working.
 *
 * WHAT IS KEPT FROM THE PREVIOUS VERSION
 *
 * The period bar, unchanged in behaviour: the preset combo, the two date fields, and
 * "typing a date means Custom". A `compare` switch joins them, because a detailed
 * report is a comparison — every KPI card carries its change against the window of
 * equal length immediately before this one.
 *
 * SORTING AND EXPORT LIVE IN THE CONTROLLER
 *
 * DataTable emits `sortRequested` and this page forwards it. Neither sorts: the rows
 * QML holds are formatted strings, and `"1,234.50" < "9.00"` is true. `app.reports`
 * still has the numbers and sorts those. Export writes the same raw numbers under
 * the translated headers the table shows.
 */
Item {
    id: root

    signal requestOpen(string key, var context)

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.reports : null

    // =====================================================================
    // STATE
    // =====================================================================
    readonly property var tabs: ctrl ? ctrl.tabs : []
    property string tab: "sales"

    property string from: ""
    property string to: ""

    /* On by default. A detailed report is read against something, and the something
       nearly always wanted is "the same length of time, just before this". */
    property bool compare: true

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property var cards: ctrl ? ctrl.cards : []
    readonly property var charts: ctrl ? ctrl.charts : []
    readonly property var tables: ctrl ? ctrl.tables : []
    readonly property string note: ctrl ? ctrl.note : ""

    /* "charts", or a table id. Reset to the charts whenever the subject changes:
       table ids are per-tab and "invoices" means something different on Sales and on
       Purchases. */
    property string section: "charts"

    readonly property var sections: {
        var out = [{
            key: "charts",
            label: Strings.t("reports.section.charts", "Charts"),
            glyph: "ic_fluent_data_trending_20_regular"
        }]
        var list = root.tables
        for (var i = 0; i < list.length; i++)
            out.push({
                key: list[i].id,
                label: list[i].title,
                glyph: "ic_fluent_table_20_regular",
                count: list[i].rows.length
            })
        return out
    }

    readonly property var currentTable: {
        var list = root.tables
        for (var i = 0; i < list.length; i++)
            if (list[i].id === root.section)
                return list[i]
        return null
    }

    // =====================================================================
    // PAGING
    // =====================================================================
    /*
     * Why a table on this screen is paged when the one on Sales or Products is not.
     *
     * Those pages give their table a viewport and it flicks inside it, so ListView
     * builds a dozen delegates however long the model is. This page has ONE
     * scrollbar — its own — so the table is sized to its content, which means its
     * viewport is its full height and virtualisation has nothing left to skip. Every
     * row it is handed becomes a delegate.
     *
     * Fifty rows is 2,800px and fifty delegates. The two thousand a report can return
     * would be 112,000px and two thousand delegates. So the screen shows a page at a
     * time; the CSV still writes every row, which is what an export is for.
     */
    property int page: 1
    property int pageSize: 50

    readonly property int rowCount: root.currentTable !== null
                                    ? root.currentTable.rows.length : 0

    readonly property var pageRows: {
        if (root.currentTable === null)
            return []
        var all = root.currentTable.rows
        var first = (Math.max(1, root.page) - 1) * root.pageSize
        return all.slice(first, first + root.pageSize)
    }

    /* Page one whenever what is being paged changes underneath. Page 4 of the
       invoices is not page 4 of the returns, and after a re-sort it is not even the
       same rows. */
    onSectionChanged: root.page = 1
    onTabChanged: root.page = 1

    // =====================================================================
    // PERIOD
    // =====================================================================
    /*
     * Unchanged from the version before this one, deliberately — it was the one part
     * of the old screen that worked. `days` counts today as one, so 1 is today alone
     * and 7 is today plus the six before it, which is what "last 7 days" means to
     * somebody counting on a calendar. 0 is everything; -1 means the two date fields
     * are the answer and this control must not touch them.
     */
    readonly property string epoch: "2000-01-01"

    readonly property var periods: [
        { key: "today",   days: 1,
          label: Strings.t("reports.preset.today", "Today") },
        { key: "last7",   days: 7,
          label: Strings.t("reports.preset.last7", "Last 7 days") },
        { key: "last30",  days: 30,
          label: Strings.t("reports.preset.last30", "Last 30 days") },
        { key: "last365", days: 365,
          label: Strings.t("reports.preset.last365", "Last year") },
        { key: "all",     days: 0,
          label: Strings.t("filter.period_all", "All time") },
        { key: "custom",  days: -1,
          label: Strings.t("reports.preset.custom", "Custom") }
    ]

    property string period: "last30"

    function periodAt(key) {
        for (var i = 0; i < root.periods.length; i++)
            if (root.periods[i].key === key)
                return i
        return 0
    }

    readonly property int periodIndex: root.periodAt(root.period)

    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd")
    }

    function daysAgo(days) {
        var then = new Date()
        then.setDate(then.getDate() - days)
        return Qt.formatDate(then, "yyyy-MM-dd")
    }

    function applyPeriod(key) {
        root.period = key
        var days = root.periods[root.periodAt(key)].days
        if (days >= 0) {
            root.to = root.today()
            /* "All time" needs a lower bound because every query takes two dates.
               2000-01-01 is before this product existed, so it cannot exclude a row,
               and it is a real date rather than a sentinel the SQL would have to know
               about. */
            root.from = days === 0 ? root.epoch : root.daysAgo(days - 1)
        }
        root.reload()
    }

    // =====================================================================
    // ACTIONS
    // =====================================================================
    function reload() {
        if (ctrl)
            ctrl.load(root.tab, root.from, root.to, root.compare)
    }

    function pick(key) {
        if (root.tab === key)
            return
        root.tab = key
        root.section = "charts"
        reload()
    }

    function notify(message, severity) {
        toast.show(message, severity)
    }

    function exportCurrent() {
        if (!ctrl || root.currentTable === null)
            return
        /* No destination is asked for. The application's own data folder is the one
           place the process is certain it may write, the toast prints the full path,
           and a save dialog for something the operator will open in Excel three
           seconds later is a step that buys nothing. `Catalogue.exportProducts`
           already works this way. */
        ctrl.exportCsv(root.currentTable.id, "")
    }

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true

        function onRejected(message) {
            root.notify(message, Severity.caution)
        }

        function onExported(path, rows) {
            root.notify(Strings.tf("reports.exported",
                                   "Exported {count} rows to {path}",
                                   { count: rows, path: "\u200e" + path }),
                        Severity.success)
        }
    }

    /* The last thirty days, not today: a report that opens on a single day opens
       empty on any morning before the first sale, and an empty screen teaches nothing
       about whether it works. */
    Component.onCompleted: root.applyPeriod("last30")

    // =====================================================================
    // GEOMETRY
    // =====================================================================
    /* Cards are shorter here than on the dashboard — KpiCard says both of these are
       writable for exactly this case, where a table has to fit underneath. Eight of
       them wrap to two rows on a wide window, and every pixel of that comes out of
       the body. */
    readonly property int cardHeight: 104
    readonly property int cardChip: 44

    readonly property int chartContent: 260

    function hue(name) {
        var value = Tokens.hue[name]
        return value !== undefined ? value : Tokens.hue.violet
    }

    // =====================================================================
    Flickable {
        id: pageScroll

        anchors.fill: parent
        anchors.margins: Tokens.size.pagePadding
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        QC.ScrollBar.vertical: FluentScrollBar { }

        /* A lane for the scrollbar, on BOTH sides.
         *
         * Fluent's bar is an overlay — it does not narrow the flickable — and it
         * mirrors itself to the leading edge in Arabic. Reserving on one side would
         * be right in one language and wrong in the other, so 14 goes on both: the
         * page header's trailing button was being clipped by the bar, and a button
         * you cannot press is a worse trade than 28px of width on a 1500px page. */
        Item {
            id: gutter
            width: pageScroll.width
            height: column.implicitHeight

            ColumnLayout {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: Tokens.spacing.md

            ColumnLayout {
                id: above
                Layout.fillWidth: true
                spacing: Tokens.spacing.md

                PageHeader {
                    Layout.fillWidth: true
                    title: Strings.t("nav.reports", "Reports")
                    description: Strings.t("reports.description",
                                           "What was sold, earned, spent and is still owed.")

                    actionItems: [
                        GlyphButton {
                            glyph: "ic_fluent_arrow_download_20_regular"
                            text: Strings.t("reports.export", "Export CSV")
                            /* Nothing to export from the charts view — and a button
                               that does nothing when pressed is worse than one that
                               is plainly unavailable. */
                            enabled: root.currentTable !== null
                            onClicked: root.exportCurrent()
                        }
                    ]
                }

                CategoryStrip {
                    Layout.fillWidth: true
                    model: root.tabs
                    currentKey: root.tab
                    onActivated: (key) => root.pick(key)
                }

                // ---------------------------------------------------------
                // PERIOD
                // ---------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.size.control + 2 * Tokens.spacing.sm
                    radius: Tokens.radius.md
                    color: Fluent.subtleSecondary
                    border.width: 1
                    border.color: Fluent.dividerBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.md

                        QC.ComboBox {
                            id: periodBox
                            Layout.preferredWidth: 200
                            Layout.preferredHeight: Tokens.size.control
                            model: root.periods
                            textRole: "label"
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            onActivated: (index) => root.applyPeriod(root.periods[index].key)
                        }

                        /* A Binding element, not `currentIndex: root.periodIndex`:
                           ComboBox assigns its own currentIndex on activation, which
                           destroys a declarative binding for good — so the first
                           manual date edit after the first preset pick would leave
                           the combo showing the old preset. A Binding re-applies
                           itself however many times the property has been written to
                           imperatively. */
                        Binding {
                            target: periodBox
                            property: "currentIndex"
                            value: root.periodIndex
                            restoreMode: Binding.RestoreNone
                        }

                        Text {
                            text: Strings.t("reports.from", "From")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textSecondary
                        }

                        QC.TextField {
                            Layout.preferredWidth: 170
                            Layout.preferredHeight: Tokens.size.control
                            text: root.from
                            placeholderText: "yyyy-mm-dd"
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            /* An ISO date is an LTR string whatever the interface
                               language is — pos forces the same on its own date
                               editors. */
                            horizontalAlignment: TextInput.AlignLeft
                            onEditingFinished: {
                                root.from = text
                                root.period = "custom"
                                root.reload()
                            }
                        }

                        Text {
                            text: Strings.t("reports.to", "To")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textSecondary
                        }

                        QC.TextField {
                            Layout.preferredWidth: 170
                            Layout.preferredHeight: Tokens.size.control
                            text: root.to
                            placeholderText: "yyyy-mm-dd"
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            horizontalAlignment: TextInput.AlignLeft
                            onEditingFinished: {
                                root.to = text
                                root.period = "custom"
                                root.reload()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        QC.Switch {
                            text: Strings.t("reports.compare", "Compare with previous")
                            checked: root.compare
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            onToggled: {
                                root.compare = checked
                                root.reload()
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // THE CAVEAT A TAB HAS TO SAY
                // ---------------------------------------------------------
                /* The controller decides when there is one. Today it is the
                   historical-cost note on the two tabs that report profit —
                   `SaleItem` stores no cost, so every past sale is costed at today's
                   purchase price. A screen that reports a number it cannot fully
                   stand behind should say so on the screen, not in a comment. */
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.note !== ""
                    implicitHeight: noteText.implicitHeight + 2 * Tokens.spacing.sm
                    radius: Tokens.radius.sm
                    color: Tokens.warningTint

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.sm
                        anchors.rightMargin: Tokens.spacing.sm
                        spacing: Tokens.spacing.sm

                        Icon {
                            Layout.alignment: Qt.AlignVCenter
                            icon: "ic_fluent_info_20_regular"
                            size: Tokens.icon.sm
                            color: Tokens.warning
                        }

                        Text {
                            id: noteText
                            Layout.fillWidth: true
                            text: root.note
                            wrapMode: Text.WordWrap
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Tokens.warning
                        }
                    }
                }

                // ---------------------------------------------------------
                // THE ANSWER
                // ---------------------------------------------------------
                CardRow {
                    Layout.fillWidth: true
                    visible: root.cards.length > 0

                    Repeater {
                        model: root.cards

                        delegate: KpiCard {
                            required property var modelData

                            label: modelData.label
                            value: modelData.value
                            valueTooltip: modelData.tooltip
                            subtext: modelData.subtext
                            subtextTone: modelData.subtextTone
                            tone: modelData.tone
                            glyph: modelData.glyph
                            /* `raw` is non-zero only where the sign carries meaning
                               — net profit, net cash, a drawer variance — so this
                               fires exactly where a red figure is the right
                               answer. */
                            valueTone: modelData.raw < 0 ? "danger" : ""
                            minHeight: root.cardHeight
                            chipSize: root.cardChip
                        }
                    }
                }

                // ---------------------------------------------------------
                // WHAT THE BODY SHOWS
                // ---------------------------------------------------------
                SectionBar {
                    id: bodyPicker
                    Layout.fillWidth: true
                    visible: root.tables.length > 0
                    sections: root.sections
                    onActivated: (key) => root.section = key
                }

                /* SectionBar owns its currentIndex and writes to it on click, so the
                   link back from `section` runs through a Binding rather than a
                   declarative assignment — same trap as the ComboBox above. */
                Binding {
                    target: bodyPicker
                    property: "currentIndex"
                    value: Math.max(0, bodyPicker.indexOfKey(root.section))
                    restoreMode: Binding.RestoreNone
                }
            }

            Item {
                id: body

                Layout.fillWidth: true
                /*
                 * ONE SCROLLBAR ON THE PAGE, AND ONLY ONE.
                 *
                 * This used to be a fixed 680px viewport with its own scrollbar
                 * inside the page's — two bars, one nested in the other, and the
                 * wheel answering whichever the cursor happened to be over. The body
                 * is now as tall as whatever it is showing, and the page's single bar
                 * moves all of it. Nothing here scrolls on its own.
                 *
                 * `implicitHeight` of the visible child, not `childrenRect`: the two
                 * views are both anchored to fill and only one is visible at a time,
                 * so childrenRect would take the taller of them regardless.
                 */
                Layout.preferredHeight: root.section === "charts"
                                        ? chartGrid.implicitHeight
                                        : tableBlock.implicitHeight

                // ---------------------------------------------------------
                // CHARTS
                // ---------------------------------------------------------
                GridLayout {
                    id: chartGrid
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: root.section === "charts"

                    columns: body.width > 1080 ? 2 : 1
                    columnSpacing: Tokens.spacing.md
                    rowSpacing: Tokens.spacing.md

                    Repeater {
                        model: root.charts

                        delegate: ChartCard {
                            id: card

                            required property var modelData

                            Layout.fillWidth: true
                            title: card.modelData.title
                            subtitle: card.modelData.subtitle
                            ink: root.hue(card.modelData.kind === "line"
                                          && card.modelData.series.length > 0
                                          ? card.modelData.series[0].hue
                                          : (card.modelData.hue !== undefined
                                             ? card.modelData.hue : "violet"))
                            /* Bars are a list and size to their rows; a curve
                               and a ring are shapes and take a fixed band. */
                            contentHeight: card.modelData.kind === "bars"
                                           ? Math.max(1, card.modelData.rows.length) * 46
                                             + Tokens.spacing.xs
                                           : root.chartContent

                            Loader {
                                anchors.fill: parent
                                sourceComponent: card.modelData.kind === "line" ? lineChart
                                               : card.modelData.kind === "bars" ? barsChart
                                               : donutChart

                                /* The delegate's row, handed to whichever
                                   component loads. A Loader's item cannot see
                                   the delegate's scope, so it is passed rather
                                   than reached for. */
                                readonly property var spec: card.modelData

                                onLoaded: item.spec = spec
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // A TABLE, IN PAGES
                // ---------------------------------------------------------
                /*
                 * PAGED BECAUSE IT DOES NOT SCROLL.
                 *
                 * A content-sized table renders every row it is handed — its viewport
                 * is its own full height, so ListView's virtualisation has nothing
                 * left to skip. Fifty rows is 2,800px of page and fifty delegates;
                 * two thousand would be 112,000px and two thousand delegates. So the
                 * page shows a page at a time, and the CSV still exports the lot,
                 * which is the point of an export.
                 */
                ColumnLayout {
                    id: tableBlock
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: root.section !== "charts" && root.currentTable !== null
                             && root.rowCount > 0
                    spacing: Tokens.spacing.sm

                    DataTable {
                        id: table
                        Layout.fillWidth: true
                        Layout.preferredHeight: table.naturalHeight

                        /* The page owns the scrolling. See DataTable's own note. */
                        scrollable: false

                        columns: root.currentTable !== null ? root.currentTable.columns : []
                        model: root.pageRows
                        sortColumn: root.currentTable !== null ? root.currentTable.sortColumn : -1
                        sortDescending: root.currentTable !== null
                                        ? root.currentTable.sortDescending : false

                        onSortRequested: (column) => {
                            if (root.ctrl && root.currentTable !== null) {
                                /* Back to page one: the row that was at the top of
                                   page three is not the row that will be there once
                                   the order changes. */
                                root.page = 1
                                root.ctrl.sortTable(root.currentTable.id, column)
                            }
                        }
                    }

                    PaginationBar {
                        Layout.fillWidth: true
                        visible: root.rowCount > root.pageSize
                        page: root.page
                        total: root.rowCount
                        pageSize: root.pageSize
                        onPageRequested: (value) => root.page = value
                        onPageSizeRequested: (value) => {
                            root.pageSize = value
                            root.page = 1
                        }
                    }
                }

                StateView {
                    anchors.fill: parent
                    anchors.topMargin: Tokens.spacing.xl
                    implicitHeight: 320
                    visible: !root.busy
                             && ((root.section === "charts" && root.charts.length === 0)
                                 || (root.section !== "charts" && root.rowCount === 0))
                    variant: "empty"
                    title: Strings.t("reports.empty.title", "Nothing in this range")
                    body: Strings.t("reports.empty.body", "Try a wider range of dates.")
                }

                LoadingOverlay {
                    anchors.fill: parent
                    visible: root.busy
                }
            }
        }
        }
    }

    // =====================================================================
    // CHART COMPONENTS
    // =====================================================================
    /* Three, chosen by `kind`. Each takes the whole spec row and reads what it needs,
       so adding a chart to a tab is a controller change and nothing here moves. */
    Component {
        id: lineChart

        LineChart {
            property var spec: ({})

            /* The controller sends HUE NAMES, not colours: Tokens owns the palette,
               and a bridge that sent "#4E5BD6" would be a second place the brand is
               defined. */
            series: {
                var out = []
                var lanes = spec.series !== undefined ? spec.series : []
                for (var i = 0; i < lanes.length; i++)
                    out.push({
                        label: lanes[i].label,
                        color: root.hue(lanes[i].hue),
                        points: lanes[i].points,
                        muted: lanes[i].muted === true
                    })
                return out
            }
            showArea: spec.area !== false
            emptyText: Strings.t("reports.empty.title", "Nothing in this range")
        }
    }

    Component {
        id: barsChart

        BarsH {
            property var spec: ({})

            rows: spec.rows !== undefined ? spec.rows : []
            ink: root.hue(spec.hue !== undefined ? spec.hue : "violet")
            showRank: true
            emphasiseFirst: true
            emptyText: Strings.t("reports.empty.title", "Nothing in this range")
        }
    }

    Component {
        id: donutChart

        DonutChart {
            property var spec: ({})

            slices: spec.slices !== undefined ? spec.slices : []
            centerValue: spec.total !== undefined ? spec.total : ""
            centerLabel: Strings.t("reports.summary.total", "Total")
            emptyText: Strings.t("reports.empty.title", "Nothing in this range")
        }
    }

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}
